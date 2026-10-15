#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "vendor" / "fonts" / "Inter-4.1-Regular.ttf"
# The face lives inside the package so its byte import never escapes the
# package directory; scripts/bundle.sh lists it for `roc bundle` explicitly.
OUTPUT = ROOT / "package" / "RocPdfSans-Regular.ttf"
MODULE_OUTPUT = ROOT / "package" / "KernelBuiltInFont.roc"
PROVENANCE = ROOT / "assets" / "provenance.json"
PROVENANCE_ID = "roc-pdf-sans-regular-font"
SOURCE_SHA256 = "40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82"
FONTTOOLS_VERSION = "4.61.1"

# The built-in facade declares this exact coverage policy. Advanced callers
# supply separately validated faces for other scripts and ranges.
UNICODE_RANGES = (
    (0x0020, 0x007E),
    (0x00A0, 0x017F),
    (0x0300, 0x036F),
    (0x2000, 0x206F),
    (0x20AC, 0x20AC),
    (0x2122, 0x2122),
    (0x2190, 0x2193),
    (0x2212, 0x2212),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def selected_scalars() -> set[int]:
    return {
        scalar
        for first, last in UNICODE_RANGES
        for scalar in range(first, last + 1)
    }


def rename_font(font: TTFont) -> None:
    replacements = {
        1: "Roc PDF Sans",
        2: "Regular",
        3: "RocPdfSans-Regular-1.0",
        4: "Roc PDF Sans Regular",
        6: "RocPdfSans-Regular",
        16: "Roc PDF Sans",
        17: "Regular",
    }
    names = font["name"]
    for record in names.names:
        replacement = replacements.get(record.nameID)
        if replacement is not None:
            record.string = replacement.encode(record.getEncoding())


MODULE_SOURCE = (
    "## The audited built-in face, generated into `package/RocPdfSans-Regular.ttf`\n"
    "## by scripts/build_builtin_font.py. The byte import keeps the face inside the\n"
    "## package directory, so `roc bundle` ships it once scripts/bundle.sh lists it.\n"
    f"import \"{OUTPUT.name}\" as font_bytes : List(U8)\n"
    "\n"
    "KernelBuiltInFont :: [].{\n"
    "\tbytes : List(U8)\n"
    "\tbytes = font_bytes\n"
    "}\n"
)


def write_module(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(MODULE_SOURCE, encoding="utf-8", newline="\n")


def provenance_entry(document: dict) -> dict:
    entries = [asset for asset in document["assets"] if asset["id"] == PROVENANCE_ID]
    if len(entries) != 1:
        raise SystemExit(f"{PROVENANCE}: expected one {PROVENANCE_ID} entry")
    entry = entries[0]
    if entry["path"] != OUTPUT.relative_to(ROOT).as_posix():
        raise SystemExit(f"{PROVENANCE}: {PROVENANCE_ID} must record {OUTPUT.relative_to(ROOT)}")
    return entry


def update_provenance(font_bytes: bytes) -> None:
    # Edit only this entry's recorded length and digest in place, so the rest
    # of the hand-maintained manifest keeps its layout.
    text = PROVENANCE.read_text(encoding="utf-8")
    entry = provenance_entry(json.loads(text))
    anchor = text.index(f'"id": "{PROVENANCE_ID}"')
    end = text.index("}", text.index(f'"sha256": "{entry["sha256"]}"', anchor))
    fields = text[anchor:end]
    fields = fields.replace(f'"bytes": {entry["bytes"]},', f'"bytes": {len(font_bytes)},', 1)
    fields = fields.replace(
        f'"sha256": "{entry["sha256"]}"', f'"sha256": "{hashlib.sha256(font_bytes).hexdigest()}"', 1
    )
    PROVENANCE.write_text(text[:anchor] + fields + text[end:], encoding="utf-8", newline="\n")
    check_provenance(font_bytes)


def check_provenance(font_bytes: bytes) -> None:
    entry = provenance_entry(json.loads(PROVENANCE.read_text(encoding="utf-8")))
    if entry["bytes"] != len(font_bytes) or entry["sha256"] != hashlib.sha256(font_bytes).hexdigest():
        raise SystemExit(f"{PROVENANCE}: {PROVENANCE_ID} does not record the generated font")


def build(output: Path, module_output: Path | None = None) -> None:
    if sha256(SOURCE) != SOURCE_SHA256:
        raise SystemExit(f"unexpected Inter source digest: {sha256(SOURCE)}")

    import fontTools

    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise SystemExit(
            f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}"
        )

    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    options.name_languages = [0x0409]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.recalc_timestamp = False
    options.canonical_order = True

    font = TTFont(SOURCE, recalcTimestamp=False, lazy=False)
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=selected_scalars())
    worker.subset(font)
    rename_font(font)

    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix="RocPdfSans-", suffix=".ttf", dir=output.parent)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        font.save(temporary, reorderTables=True)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    if module_output is not None:
        write_module(module_output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Regenerate to a temporary file and compare it with the retained asset.",
    )
    args = parser.parse_args()

    if args.check:
        with tempfile.TemporaryDirectory(prefix="roc-pdf-font-") as directory:
            candidate = Path(directory) / OUTPUT.name
            candidate_module = Path(directory) / MODULE_OUTPUT.name
            build(candidate, candidate_module)
            if not OUTPUT.exists() or candidate.read_bytes() != OUTPUT.read_bytes():
                raise SystemExit(f"{OUTPUT} is not the deterministic generated font")
            if not MODULE_OUTPUT.exists() or candidate_module.read_bytes() != MODULE_OUTPUT.read_bytes():
                raise SystemExit(f"{MODULE_OUTPUT} is not the deterministic generated font module")
            check_provenance(OUTPUT.read_bytes())
        print(f"PASS built-in font {sha256(OUTPUT)}")
    else:
        build(OUTPUT, MODULE_OUTPUT)
        update_provenance(OUTPUT.read_bytes())
        print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, sha256={sha256(OUTPUT)})")


if __name__ == "__main__":
    main()
