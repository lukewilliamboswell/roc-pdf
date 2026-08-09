#!/usr/bin/env python3
"""Freeze and subset the test-only Noto Sans SC CJK fixture.

The input is the immutable Google Fonts source recorded in assets/provenance.
It is deliberately not vendored: this script verifies its digest, freezes the
regular wght instance, and retains only U+4E2D plus the minimal sfnt facts the
bounded Roc TrueType subsetter consumes.
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
from fontTools.varLib.instancer import instantiateVariableFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "assets" / "NotoSansSC-CJK-Fixture.ttf"
SOURCE_SHA256 = "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"
FONTTOOLS_VERSION = "4.46.0"
SCALARS = {0x4E2D}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "Noto SC CJK Fixture",
        2: "Regular",
        3: "NotoSCCJKFixture-Regular-1.0",
        4: "Noto SC CJK Fixture Regular",
        6: "NotoSCCJKFixture-Regular",
        16: "Noto SC CJK Fixture",
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def add_empty_required_table(font: TTFont, tag: str) -> None:
    # The Roc subsetter preserves these optional TrueType hinting tables exactly.
    # This upstream variable source legitimately omits two of them, so the
    # test-only derived static fixture supplies empty, valid sfnt tables rather
    # than changing the production subsetter or fabricating glyph data.
    if tag not in font:
        table = DefaultTable(tag)
        table.data = b""
        font[tag] = table


def build(source: Path, output: Path) -> None:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit(f"unexpected Noto Sans SC source digest: {sha256(source)}")
    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}")

    font = TTFont(source, recalcTimestamp=False, lazy=False)
    instantiateVariableFont(font, {"wght": 400}, inplace=True)
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
    with tempfile.NamedTemporaryFile(prefix="NotoSansSC-CJK-", suffix=".ttf", dir=output.parent, delete=False) as temporary:
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
        with tempfile.TemporaryDirectory(prefix="roc-pdf-cjk-font-") as directory:
            candidate = Path(directory) / OUTPUT.name
            build(args.source, candidate)
            if not OUTPUT.exists() or candidate.read_bytes() != OUTPUT.read_bytes():
                raise SystemExit(f"{OUTPUT} is not a deterministic generated CJK fixture")
        print(f"PASS CJK fixture {sha256(OUTPUT)}")
    else:
        build(args.source, OUTPUT)
        print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, sha256={sha256(OUTPUT)})")


if __name__ == "__main__":
    main()
