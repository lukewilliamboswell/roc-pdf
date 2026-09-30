#!/usr/bin/env python3
"""Subset the test-only Noto Sans Mono inline-code fixture.

The input is the Debian fonts-noto-mono 2.006 static regular face
(/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf, OFL-1.1, no Reserved
Font Name). It is deliberately not vendored: this script verifies its digest
and retains only printable ASCII, the monospace coverage a `Code` role face
needs in the reference report, with no layout features.
"""
from __future__ import annotations

import argparse
import hashlib
import tempfile
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "assets" / "NotoSansMono-Code-Fixture.ttf"
SOURCE_SHA256 = "6b692c4b6d15ccf59f1c1fe8d11cb8a92f51960f3e9f1f523781755a3af7e29f"
FONTTOOLS_VERSION = "4.61.1"
SCALARS = set(range(0x20, 0x7F))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "Noto Mono Code Fixture",
        2: "Regular",
        3: "NotoMonoCodeFixture-Regular-1.0",
        4: "Noto Mono Code Fixture Regular",
        6: "NotoMonoCodeFixture-Regular",
        16: "Noto Mono Code Fixture",
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def add_empty_required_table(font: TTFont, tag: str) -> None:
    # The Roc subsetter preserves these optional TrueType hinting tables exactly.
    # The source carries them; this keeps the fixture valid if a subset
    # drops one, without changing the production subsetter.
    if tag not in font:
        table = DefaultTable(tag)
        table.data = b""
        font[tag] = table


def build(source: Path, output: Path) -> None:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit(f"unexpected Noto Sans Mono source digest: {sha256(source)}")
    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}")

    font = TTFont(source, recalcTimestamp=False, lazy=False)
    options = subset.Options()
    options.layout_features = []
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    options.name_languages = [0x0409]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.recalc_timestamp = False
    options.canonical_order = True
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=SCALARS)
    worker.subset(font)
    add_empty_required_table(font, "cvt ")
    add_empty_required_table(font, "fpgm")
    rename_font(font)
    font["OS/2"].fsType = 0

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="NotoSansMono-Code-", suffix=".ttf", dir=output.parent, delete=False) as temporary:
        candidate = Path(temporary.name)
    try:
        font.save(candidate, reorderTables=True)
        candidate.replace(output)
    finally:
        candidate.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="roc-pdf-mono-font-") as directory:
            candidate = Path(directory) / OUTPUT.name
            build(args.source, candidate)
            if not OUTPUT.exists() or candidate.read_bytes() != OUTPUT.read_bytes():
                raise SystemExit(f"{OUTPUT} is not a deterministic generated monospace fixture")
        print(f"PASS monospace fixture {sha256(OUTPUT)}")
    else:
        build(args.source, OUTPUT)
        print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, sha256={sha256(OUTPUT)})")


if __name__ == "__main__":
    main()
