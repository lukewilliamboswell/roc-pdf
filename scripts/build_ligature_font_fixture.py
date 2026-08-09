#!/usr/bin/env python3
"""Subset the test-only IBM Plex Serif source while retaining its `fi` liga."""
from __future__ import annotations

import argparse
import hashlib
import tempfile
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "assets" / "IBMPlexSerif-FiLigature-Fixture.ttf"
SOURCE_SHA256 = "3764f5ddda8c687a765d0105e2a31cd311fca244239b878cb59fedb069a14dbb"
FONTTOOLS_VERSION = "4.61.1"
SCALARS = {0x0066, 0x0069}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "IBM Plex Serif fi Fixture",
        2: "Regular",
        3: "IBMPlexSerifFiFixture-Regular-1.0",
        4: "IBM Plex Serif fi Fixture Regular",
        6: "IBMPlexSerifFiFixture-Regular",
        16: "IBM Plex Serif fi Fixture",
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def build(source: Path, output: Path) -> None:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit(f"unexpected IBM Plex Serif source digest: {sha256(source)}")
    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}")

    font = TTFont(source, recalcTimestamp=False, lazy=False)
    options = subset.Options()
    # This is the fixture's semantic evidence: retain only the selected OpenType
    # feature, so its Type-4 `f` + `i` -> `fi` relationship remains auditable.
    options.layout_features = ["liga"]
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
    rename_font(font)
    font["OS/2"].fsType = 0

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="IBMPlexSerif-FiLigature-", suffix=".ttf", dir=output.parent, delete=False) as temporary:
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
        with tempfile.TemporaryDirectory(prefix="roc-pdf-ligature-font-") as directory:
            candidate = Path(directory) / OUTPUT.name
            build(args.source, candidate)
            if not OUTPUT.exists() or candidate.read_bytes() != OUTPUT.read_bytes():
                raise SystemExit(f"{OUTPUT} is not a deterministic generated ligature fixture")
        print(f"PASS ligature fixture {sha256(OUTPUT)}")
    else:
        build(args.source, OUTPUT)
        print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, sha256={sha256(OUTPUT)})")


if __name__ == "__main__":
    main()
