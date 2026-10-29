#!/usr/bin/env python3
"""Prepare the repository's bounded Markdown guides as an AsciiDoc book.

Markdown remains the authored GitHub source, preserving existing URLs and
anchors. This adapter admits only the syntax used by these guides. It records
exact source/asset digests and never executes examples or downloads resources.
The released shared renderer owns parsing, layout and publication.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
CHAPTERS = {
    "docs/README.md": "start-here.adoc",
    "docs/authoring.md": "authoring.adoc",
    "docs/manual-composition.md": "manual-composition.adoc",
    "docs/destination-page-references.md": "destination-page-references.adoc",
    "docs/roc-font.md": "roc-font.adoc",
    "docs/migrating-named-arguments.md": "migrating-named-arguments.adoc",
    "docs/migrating-to-rc2.md": "migrating-to-rc2.adoc",
}
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")


def slug(heading: str) -> str:
    return re.sub(r"[^\w -]", "", heading.replace("`", "")).strip().lower().replace(" ", "-")


def prepare(destination: Path, revision: str, release_version: str | None = None, bundle: Path | None = None) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    chapters = dict(CHAPTERS)
    releases = sorted((ROOT / "docs/releases").glob("*.md"),
                      key=lambda p: version_key(p.stem), reverse=True)
    for release in releases:
        chapters[release.relative_to(ROOT).as_posix()] = f"release-{release.stem}.adoc"
    titles = {}
    for source in chapters:
        first = (ROOT / source).read_text().splitlines()[0]
        if not first.startswith("# "):
            raise ValueError(f"{source}: missing Markdown document title")
        titles[source] = slug(first[2:])
    inventory = []
    bindings = {}
    if release_version:
        version_key(release_version)
        if bundle is None or not bundle.is_file():
            raise ValueError("versioned manual requires the actual package bundle")
        bindings[f"docs/releases/{release_version}.md"] = {
            "{package-url}": f"https://github.com/lukewilliamboswell/roc-pdf/releases/download/{release_version}/{bundle.name}",
            "{bundle-sha256}": hashlib.sha256(bundle.read_bytes()).hexdigest(),
        }

    def record(source: Path) -> None:
        inventory.append({"path": source.relative_to(ROOT).as_posix(),
                          "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})

    for source, target in chapters.items():
        path = ROOT / source
        text = path.read_text()
        for placeholder, value in bindings.get(source, {}).items():
            text = text.replace(placeholder, value)
        (destination / target).write_text(convert(text, source, chapters, titles, revision))
        record(path)
    shutil.copyfile(ROOT / "docs/index.adoc", destination / "index.adoc")
    record(ROOT / "docs/index.adoc")
    (destination / "releases.adoc").write_text("= Release notes\n\n" + "\n".join(
        f"include::{chapters[p.relative_to(ROOT).as_posix()]}[leveloffset=+1]\n" for p in releases))
    gallery = ["= Runnable document gallery", "", "These examples use public Roc APIs. Download the PDF or open the checked source to run an example.", ""]
    for name, title in (("tax-invoice", "Invoice"), ("business-report", "Business report"),
                        ("vector-diagrams", "Prepared vector diagrams")):
        gallery.extend([f"== {title}", "", f"image::images/{name}.png[{title} preview]", "",
                        f"https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/examples/{name}/main.roc[Runnable source] · "
                        f"https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/examples/{name}/{name}.pdf[PDF output]", ""])
        source = ROOT / "examples" / name / "preview.png"
        (destination / "images").mkdir(exist_ok=True)
        shutil.copyfile(source, destination / "images" / f"{name}.png")
        record(source)
    (destination / "gallery.adoc").write_text("\n".join(gallery))
    (destination / "source-digests.json").write_text(json.dumps({
        "schema_version": 1, "revision": revision, "sources": inventory,
        "chapters": chapters, "release_bindings": bindings,
    }, indent=2) + "\n")


def version_key(version: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-rc(\d+))?", version)
    if not match:
        raise ValueError(f"unsupported release version {version!r}")
    major, minor, patch, candidate = match.groups()
    return int(major), int(minor), int(patch), int(candidate) if candidate else 10**9


def convert(text: str, source: str, chapters: dict[str, str], titles: dict[str, str], revision: str) -> str:
    def link(match: re.Match) -> str:
        label, target = match.groups()
        parsed = urlsplit(target)
        if parsed.scheme:
            return f"{target}[{label}]"
        resolved = (ROOT / source).parent / parsed.path if parsed.path else ROOT / source
        resolved = resolved.resolve()
        if not resolved.is_relative_to(ROOT):
            raise ValueError(f"{source}: link escapes repository: {target}")
        relative = resolved.relative_to(ROOT).as_posix()
        if relative in chapters:
            anchor = slug(Path(chapters[relative]).stem) + "-" + (parsed.fragment or titles[relative])
            return f"xref:{chapters[relative]}#{anchor}[{label}]"
        if not resolved.exists():
            raise ValueError(f"{source}: missing link target: {target}")
        suffix = f"#{parsed.fragment}" if parsed.fragment else ""
        return f"https://github.com/lukewilliamboswell/roc-pdf/blob/{revision}/{relative}{suffix}[{label}]"

    output = []
    fenced = False
    table = False
    seen = set()
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("```"):
            if table:
                raise ValueError(f"{source}:{index + 1}: source block in table")
            if fenced:
                output.append("----")
            else:
                language = line[3:]
                if not re.fullmatch(r"[\w-]*", language):
                    raise ValueError(f"{source}:{index + 1}: unsupported source language")
                output.extend([f"[source,{language or 'text'}]", "----"])
            fenced = not fenced
            continue
        if fenced:
            output.append(line)
            continue
        if line.startswith("|"):
            if not table:
                cells = line.strip("|").split("|")
                output.extend([f'[cols="{",".join("1" for _ in cells)}",options="header"]', "|==="])
                table = True
            if re.fullmatch(r"\|[ |:-]+\|", line):
                continue
            # Markdown closes its row with a pipe; in PSV that pipe starts
            # another cell. Preserve the leading cell delimiters only.
            output.append(LINK.sub(link, line.rstrip().removesuffix("|")))
            continue
        if table:
            output.append("|===")
            table = False
        heading = re.fullmatch(r"(#{1,6}) (.+)", line)
        if heading:
            level, title = heading.groups()
            anchor = slug(title)
            if anchor in seen:
                raise ValueError(f"{source}:{index + 1}: duplicate anchor {anchor}")
            seen.add(anchor)
            output.extend([f"[#{slug(Path(chapters[source]).stem)}-{anchor}]", f"{'=' * len(level)} {title}"])
        elif line.startswith((">", "![", "<")):
            raise ValueError(f"{source}:{index + 1}: unsupported authored Markdown block")
        else:
            output.append(LINK.sub(link, re.sub(r"^(\s*)- ", r"\1* ", line)))
    if fenced:
        raise ValueError(f"{source}: unterminated source block")
    if table:
        output.append("|===")
    return "\n".join(output) + "\n"


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
    print(f"Prepared bounded AsciiDoc manual in {destination}")


if __name__ == "__main__":
    main()
