#!/usr/bin/env python3
"""Freeze and subset the pinned Noto Sans SC regular instance.

The script verifies the immutable Google Fonts source digest before retaining
the test or gallery repertoire and the required sfnt tables.
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
GALLERY_OUTPUT = ROOT / "examples" / "ordered-han" / "fonts" / "ReceivingHan-Regular.ttf"
GALLERY_SCALARS = {ord(character) for character in "仓库交接"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont, family: str) -> None:
    postscript = family.replace(" ", "")
    replacements = {
        1: family,
        2: "Regular",
        3: f"{postscript}-Regular-1.0",
        4: f"{family} Regular",
        6: f"{postscript}-Regular",
        16: family,
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def add_empty_required_table(font: TTFont, tag: str) -> None:
    # The Roc subsetter preserves these optional TrueType hinting tables exactly.
    # This upstream variable source legitimately omits two of them, so the
    # derived static face supplies empty sfnt tables for those tags. The
    # glyph outlines still come from the pinned source.
    if tag not in font:
        table = DefaultTable(tag)
        table.data = b""
        font[tag] = table


def build(source: Path, output: Path, repertoire: set[int], family: str) -> None:
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
    worker.populate(unicodes=repertoire)
    worker.subset(font)
    add_empty_required_table(font, "cvt ")
    add_empty_required_table(font, "fpgm")
    rename_font(font, family)
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
    parser.add_argument("--gallery", action="store_true", help="build the four-character Receiving Han gallery face")
    args = parser.parse_args()
    output, repertoire, family = (
        (GALLERY_OUTPUT, GALLERY_SCALARS, "Receiving Han")
        if args.gallery else (OUTPUT, SCALARS, "Noto SC CJK Fixture")
    )
    if args.check:
        with tempfile.TemporaryDirectory(prefix="roc-pdf-cjk-font-") as directory:
            candidate = Path(directory) / output.name
            build(args.source, candidate, repertoire, family)
            if not output.exists() or candidate.read_bytes() != output.read_bytes():
                raise SystemExit(f"{output} is not a deterministic generated CJK fixture")
        print(f"PASS CJK fixture {sha256(output)}")
    else:
        build(args.source, output, repertoire, family)
        print(f"Wrote {output} ({output.stat().st_size} bytes, sha256={sha256(output)})")


if __name__ == "__main__":
    main()
