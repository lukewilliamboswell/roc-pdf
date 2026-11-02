#!/usr/bin/env python3
"""Stage authored AsciiDoc, exact local assets and release bindings.

The shared native renderer owns parsing, links, source highlighting, HTML,
Markdown and PDF. This stage copies source bytes without format conversion;
only source-revision links and generated release metadata are bound here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://github.com/lukewilliamboswell/roc-pdf/blob/main/"
ASSETS = {f"images/{name}.png": f"examples/{name}/preview.png"
          for name in ("tax-invoice", "business-report", "vector-diagrams")}


def version_key(version: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?", version)
    if not match:
        raise ValueError(f"unsupported release version {version!r}")
    major, minor, patch, candidate = match.groups()
    return int(major), int(minor), int(patch), int(candidate) if candidate else 10**9


def prepare(destination: Path, revision: str, release_version: str | None = None,
            bundle: Path | None = None) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    chapters = {path.relative_to(ROOT).as_posix(): path.name
                for path in sorted((ROOT / "docs").glob("*.adoc"))
                if path.name != "index.adoc"}
    inventory = []

    def record(source: Path) -> None:
        inventory.append({"path": source.relative_to(ROOT).as_posix(),
                          "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})

    for source, target in {"docs/index.adoc": "index.adoc", **chapters}.items():
        path = ROOT / source
        text = path.read_text()
        if not re.match(r"(?:\[#[^\n]+\]\n)?= [^\n]+", text):
            raise ValueError(f"{source}: missing AsciiDoc document title")
        (destination / target).write_text(text.replace(SOURCE_URL,
            f"https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/"))
        record(path)
    for target, source in ASSETS.items():
        path = ROOT / source
        (destination / target).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination / target)
        record(path)

    releases = sorted((ROOT / "docs/releases").glob("*.md"),
                      key=lambda path: version_key(path.stem), reverse=True)
    bindings = {}
    listing = []
    if release_version:
        version_key(release_version)
        if bundle is None or not bundle.is_file():
            raise ValueError("versioned manual requires the actual package bundle")
        source = f"docs/releases/{release_version}.md"
        if not (ROOT / source).is_file():
            raise ValueError("versioned manual requires its authored release notes")
        url = f"https://github.com/lukewilliamboswell/roc-pdf/releases/download/{release_version}/{bundle.name}"
        sha = hashlib.sha256(bundle.read_bytes()).hexdigest()
        bindings[source] = {"{package-url}": url, "{bundle-sha256}": sha}
        compiler = (ROOT / ".roc-version").read_text().strip()
        listing.extend(["== Install this release", "", "Package dependency:", "",
                        "[source,roc]", "----", f'pdf: "{url}",', "----", "",
                        f"Bundle SHA-256: `{sha}`.", "", f"Compiler: `{compiler}`.", ""])
        record(ROOT / ".roc-version")
    listing.extend(["== Source release notes", ""])
    for source in releases:
        relative = source.relative_to(ROOT).as_posix()
        listing.append(f"* https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/{relative}[{source.stem}]")
        record(source)
    (destination / "releases").mkdir(exist_ok=True)
    (destination / "releases/list.adoc").write_text("\n".join(listing) + "\n")
    (destination / "source-digests.json").write_text(json.dumps({
        "schema_version": 1, "revision": revision, "sources": inventory,
        "chapters": chapters, "release_bindings": bindings,
    }, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".roc-pdf-tmp/manual-source")
    parser.add_argument("--revision", default="main")
    parser.add_argument("--release-version")
    parser.add_argument("--bundle", type=Path)
    options = parser.parse_args()
    destination = options.output.resolve()
    if not destination.is_relative_to(ROOT / ".roc-pdf-tmp"):
        parser.error("prepared manual output must be under .roc-pdf-tmp")
    prepare(destination, options.revision, options.release_version, options.bundle)
    print(f"Staged authored AsciiDoc manual in {destination}")


if __name__ == "__main__":
    main()
