#!/usr/bin/env python3
"""Subset the test-only IBM Plex Sans Hebrew source for the text-layout RTL slice."""
from __future__ import annotations

import argparse
import hashlib
import tempfile
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "assets" / "IBMPlexSansHebrew-Rtl-Fixture.ttf"
SOURCE_SHA256 = "98cd8ca13fef47fb57c20faed17a346639bb418b7abeb096fd9693ea3eecc445"
FONTTOOLS_VERSION = "4.61.1"

# The fixture text is the UAX #9 BD16 bracket-pair example transcribed from
# the normative BidiCharacterTest: four non-joining Hebrew letters, two
# adjacent Latin pairs, two neutrals, and two nested mirrored bracket pairs.
# Both members of each mirrored pair are required, because an odd-level
# bracket paints its mirrored partner's glyph.
SCALARS = {
    0x0026,  # &
    0x0028,  # (
    0x0029,  # )
    0x002E,  # .
    0x005B,  # [
    0x005D,  # ]
    0x0065,  # e
    0x0066,  # f
    0x0067,  # g
    0x0068,  # h
    0x05D0,  # alef
    0x05D1,  # bet
    0x05D2,  # gimel
    0x05D3,  # dalet
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "IBM Plex Sans Hebrew RTL Fixture",
        2: "Regular",
        3: "IBMPlexSansHebrewRtlFixture-Regular-1.0",
        4: "IBM Plex Sans Hebrew RTL Fixture Regular",
        6: "IBMPlexSansHebrewRtlFixture-Regular",
        16: "IBM Plex Sans Hebrew RTL Fixture",
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def build(source: Path, output: Path) -> None:
    if sha256(source) != SOURCE_SHA256:
        raise SystemExit(f"unexpected IBM Plex Sans Hebrew source digest: {sha256(source)}")
    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}")

    font = TTFont(source, recalcTimestamp=False, lazy=False)
    options = subset.Options()
    # No OpenType layout feature is part of this fixture's evidence: the four
    # Hebrew letters are non-joining and mirroring is a UAX #9 fact resolved
    # before shaping, never a GSUB substitution.
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
    rename_font(font)
    font["OS/2"].fsType = 0

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="IBMPlexSansHebrew-Rtl-", suffix=".ttf", dir=output.parent, delete=False) as temporary:
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
        with tempfile.TemporaryDirectory(prefix="roc-pdf-rtl-font-") as directory:
            candidate = Path(directory) / OUTPUT.name
            build(args.source, candidate)
            if not OUTPUT.exists() or candidate.read_bytes() != OUTPUT.read_bytes():
                raise SystemExit(f"{OUTPUT} is not a deterministic generated RTL fixture")
        print(f"PASS RTL fixture {sha256(OUTPUT)}")
    else:
        build(args.source, OUTPUT)
        print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, sha256={sha256(OUTPUT)})")


if __name__ == "__main__":
    main()
