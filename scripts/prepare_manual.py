#!/usr/bin/env python3
"""Stage authored AsciiDoc, exact local assets and release bindings.

The shared native renderer owns parsing, links, source highlighting, HTML,
Markdown and PDF. This stage copies source bytes without format conversion;
only source-revision links and generated release metadata are bound here.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
PROJECT_URL = "https://github.com/lukewilliamboswell/roc-pdf"
ASSETS = {f"images/{name}.png": f"examples/{name}/preview.png"
          for name in ("tax-invoice", "business-report", "vector-diagrams", "remittance-advice")}
HTML_ONLY_PREVIEWS = {"images/business-report.png", "images/vector-diagrams.png",
                      "images/remittance-advice.png"}
CHAPTER_INCLUDE = re.compile(r"^include::([^\[\n]+\.adoc)\[[^\]\n]*\]$", re.M)


def version_key(version: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?", version)
    if not match:
        raise ValueError(f"unsupported release version {version!r}")
    major, minor, patch, candidate = match.groups()
    return int(major), int(minor), int(patch), int(candidate) if candidate else 10**9


def pin_source_links(text: str, revision: str) -> str:
    for route in ("blob", "tree"):
        text = text.replace(f"{PROJECT_URL}/{route}/main/", f"{PROJECT_URL}/{route}/{revision}/")
    return text


def expand_chapter(path: Path, root: Path, seen: Counter[str] | None = None,
                   ancestors: tuple[Path, ...] = ()) -> str:
    """Expand local AsciiDoc chapter includes for the manual inventory and audit."""
    path = path.resolve()
    if not path.is_relative_to(root.resolve()) or path in ancestors or not path.is_file():
        raise ValueError(f"Invalid manual chapter include: {path}")
    if seen is not None:
        seen[path.relative_to(root.resolve()).as_posix()] += 1
    return CHAPTER_INCLUDE.sub(
        lambda include: expand_chapter(path.parent / include.group(1), root, seen, (*ancestors, path)),
        path.read_text(),
    )


def prepare(destination: Path, revision: str, release_version: str | None = None,
            bundle: Path | None = None) -> None:
    docs = ROOT / "docs"
    if (ROOT / "architecture.md").exists():
        raise ValueError("Keep the architecture chapter in docs/architecture.adoc.")
    markdown = sorted(path.relative_to(ROOT).as_posix() for path in docs.rglob("*")
                      if path.is_file() and path.suffix.lower() in {".md", ".markdown"})
    if markdown:
        raise ValueError(f"Use AsciiDoc for authored documentation: {', '.join(markdown)}")
    chapters = {path.relative_to(ROOT).as_posix(): path.name
                for path in sorted(docs.glob("*.adoc"))
                if path.name != "index.adoc"}
    index = (docs / "index.adoc").read_text()
    includes = re.findall(r"^include::([^\[\n]+)\[leveloffset=\+1\]$", index, re.M)
    if sorted(includes) != sorted(chapters.values()):
        raise ValueError("docs/index.adoc must include each top-level AsciiDoc chapter exactly once")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    inventory = []

    def record(source: Path) -> None:
        inventory.append({"path": source.relative_to(ROOT).as_posix(),
                          "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})

    authored = set()
    for path in sorted(docs.rglob("*.adoc")):
        target = path.relative_to(docs)
        if len(target.parts) == 2 and target.parts[0] == "releases":
            continue
        if len(target.parts) != 1:
            raise ValueError(f"{path.relative_to(ROOT)}: keep chapters directly under docs/")
        text = path.read_text()
        if not re.match(r"(?:\[#[^\n]+\]\n)?= [^\n]+", text):
            raise ValueError(f"{path.relative_to(ROOT)}: missing AsciiDoc document title")
        (destination / target).parent.mkdir(parents=True, exist_ok=True)
        (destination / target).write_text(pin_source_links(text, revision))
        record(path)
        authored.add(target.as_posix())
    for target, source in ASSETS.items():
        path = ROOT / source
        (destination / target).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination / target)
        record(path)

    draft = docs / "releases/unreleased.adoc"
    releases = sorted((path for path in (docs / "releases").glob("*.adoc") if path != draft),
                      key=lambda path: version_key(path.stem), reverse=True)
    bindings: dict[str, dict[str, str]] = {}
    listing = []
    if release_version:
        version_key(release_version)
        if bundle is None or not bundle.is_file():
            raise ValueError("versioned manual requires the actual package bundle")
        source = docs / f"releases/{release_version}.adoc"
        if source not in releases:
            raise ValueError("versioned manual requires its authored release notes")
        url = f"{PROJECT_URL}/releases/download/{release_version}/{bundle.name}"
        sha = hashlib.sha256(bundle.read_bytes()).hexdigest()
        bindings[source.relative_to(ROOT).as_posix()] = {"{package-url}": url, "{bundle-sha256}": sha}
        compiler = (ROOT / ".roc-version").read_text().strip()
        listing.extend(["== Install this release", "", "Package dependency:", "",
                        "[source,roc]", "----", f'pdf: "{url}",', "----", "",
                        f"Bundle SHA-256: `{sha}`.", "", f"Compiler: `{compiler}`.", ""])
        record(ROOT / ".roc-version")
    (destination / "releases").mkdir(exist_ok=True)
    if release_version is None and draft.is_file():
        (destination / "releases/unreleased.adoc").write_text(pin_source_links(draft.read_text(), revision))
        authored.add("releases/unreleased.adoc")
        listing.extend(["include::unreleased.adoc[leveloffset=+1]", ""])
        record(draft)
    listing.extend(["== Published versions", ""])
    for source in releases:
        listing.append(f"* {PROJECT_URL}/releases/tag/{source.stem}[{source.stem}]")
        record(source)
    (destination / "releases/list.adoc").write_text("\n".join(listing) + "\n")
    seen: Counter[str] = Counter()
    expand_chapter(destination / "index.adoc", destination, seen)
    missing = sorted(authored - seen.keys())
    repeated = sorted(path for path, count in seen.items() if count > 1)
    if missing or repeated:
        raise ValueError(f"Manual sections missing from the book: {missing}. Repeated sections: {repeated}.")
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
