#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import tempfile
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "vendor" / "fonts" / "Inter-4.1-Regular.ttf"
OUTPUT = ROOT / "tests" / "assets" / "CallerFont-Regular.ttf"
RESTRICTED_OUTPUT = ROOT / "tests" / "assets" / "CallerFont-Restricted.ttf"
# An unhinted twin: no TrueType instructions and no cvt, fpgm, gasp, or prep
# table, as in unhinted and desktop fonts such as Fraunces and Source Serif 4.
UNHINTED_OUTPUT = ROOT / "tests" / "assets" / "CallerFont-Unhinted.ttf"
HINTING_TABLES = ("cvt ", "fpgm", "gasp", "prep")
SOURCE_SHA256 = "40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82"
FONTTOOLS_VERSION = "4.61.1"
SCALARS = {0x20, 0x43, 0x44, 0x46, 0x50, 0x61, 0x66, 0xE9}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "Caller Fixture Sans",
        2: "Regular",
        3: "CallerFixtureSans-Regular-1.0",
        4: "Caller Fixture Sans Regular",
        6: "CallerFixtureSans-Regular",
        16: "Caller Fixture Sans",
        17: "Regular",
    }
    for record in font["name"].names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


def build(output: Path, restricted: bool, unhinted: bool = False) -> None:
    require_source = sha256(SOURCE)
    if require_source != SOURCE_SHA256:
        raise SystemExit(f"unexpected Inter source digest: {require_source}")

    import fontTools

    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}")

    options = subset.Options()
    options.layout_features = []
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    options.name_languages = [0x0409]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.recalc_timestamp = False
    options.canonical_order = True
    options.hinting = not unhinted

    font = TTFont(SOURCE, recalcTimestamp=False, lazy=False)
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=SCALARS)
    worker.subset(font)
    rename_font(font)
    font["OS/2"].fsType = 0x0002 if restricted else 0
    if unhinted:
        for tag in HINTING_TABLES:
            if tag in font:
                del font[tag]

    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix="CallerFont-", suffix=".ttf", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        font.save(temporary, reorderTables=True)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


OUTPUTS = ((OUTPUT, False, False), (RESTRICTED_OUTPUT, True, False), (UNHINTED_OUTPUT, False, True))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="roc-pdf-caller-font-") as directory:
            temporary = Path(directory)
            for output, restricted, unhinted in OUTPUTS:
                candidate = temporary / output.name
                build(candidate, restricted, unhinted)
                if not output.exists() or candidate.read_bytes() != output.read_bytes():
                    raise SystemExit(f"{output} is not a deterministic generated caller-font fixture")
        print(f"PASS caller font fixture {sha256(OUTPUT)}")
        print(f"PASS restricted caller font fixture {sha256(RESTRICTED_OUTPUT)}")
        print(f"PASS unhinted caller font fixture {sha256(UNHINTED_OUTPUT)}")
    else:
        for output, restricted, unhinted in OUTPUTS:
            build(output, restricted, unhinted)
            print(f"Wrote {output} ({output.stat().st_size} bytes, sha256={sha256(output)})")


if __name__ == "__main__":
    main()
