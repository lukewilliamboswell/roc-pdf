#!/usr/bin/env python3
"""Original-byte checks for the text-layout case-transformation slice."""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_text import PDFBOX_JAR, PDFBOX_SOURCE, cmap_mappings, decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require, validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "actual_text" / "case_text.pdf"

# Full Unicode default uppercase of the authored source. The expansion is the
# dependency's resolved mapping, never a fixture-local table.
LOGICAL_TEXT = "a\u00df"
PRESENTATION_TEXT = "ASS"
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF006100DF>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"1 0 0 1 7.589 0 Tm\n<0002> Tj\n"
    b"1 0 0 1 14.647 0 Tm\n<0002> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_ACTUAL_TEXT = b"<FEFF006100DF>"
EXPECTED_MAPPINGS = {0x0001: (0x0061,), 0x0002: (0x00DF,)}
EXPECTED_SUBSET_SHA256 = "aea5b021187971fd57d34562eae236065d1c77e466b7a47e31b0f00529681717"
EXPECTED_SUBSET_LENGTH1 = 5800
EXPECTED_PDFBOX_TEXT = "a\u00df\n".encode()


def validate_case_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    _, content = decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))

    # The transformation forces ActualText, and that text is the unchanged
    # authored source rather than the visible presentation.
    require(EXPECTED_ACTUAL_TEXT in content, "case run does not carry the exact logical ActualText")
    recovered = bytes.fromhex(EXPECTED_ACTUAL_TEXT[5:-1].decode()).decode("utf-16-be")
    require(recovered == LOGICAL_TEXT, f"case ActualText is not the logical source: {recovered!r}")
    require(recovered != PRESENTATION_TEXT, "case ActualText must not be the presentation")

    resources = re.search(rb"/Font << /F1_0 ([1-9][0-9]*) 0 R >>", page_body)
    require(resources is not None, "case page has no exact text font resource")
    type0 = bodies[int(resources.group(1))]
    require(b"/Subtype /Type0" in type0 and b"/Encoding /Identity-H" in type0, "case font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0, b"DescendantFonts")
    require(len(descendants) == 1, "case Type 0 font must have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body, "case descendant is not CIDFontType2")

    _, cmap = decoded_stream(bodies, dictionary_ref(type0, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == EXPECTED_MAPPINGS, f"case ToUnicode rows differ: {mappings!r}")

    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(len(shown) == len(PRESENTATION_TEXT), f"case paints {len(shown)} CIDs, expected {len(PRESENTATION_TEXT)}")
    # The expansion paints one glyph per presentation scalar while the two
    # identical output scalars legitimately share one CID; the surviving
    # per-CID mapping therefore cannot reconstruct the source on its own,
    # which is exactly why ActualText is mandatory for this row.
    require(shown[1] == shown[2], "case expansion does not reuse one CID for its two identical output scalars")
    require(len(set(shown)) == 2, "case output does not use exactly two distinct CIDs")
    per_cid = "".join(chr(scalar) for cid in dict.fromkeys(shown) for scalar in mappings[cid])
    require(per_cid == LOGICAL_TEXT, f"case per-CID mapping does not recover the source: {per_cid!r}")

    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(f"/Length1 {EXPECTED_SUBSET_LENGTH1}".encode() in font_dictionary, "case sanitized FontFile2 length differs")
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "case FontFile2 is not a TrueType-flavoured sfnt")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "case sanitized subset digest differs")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-case-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, compiled.stderr.decode(errors="replace") or "PDFBox extractor compilation failed")
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0 and not result.stderr, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(result.stdout == EXPECTED_PDFBOX_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_PDFBOX_TEXT!r}")
    print("PASS text-layout PDFBox extraction recovers the authored source through ActualText")


def self_test() -> None:
    original = SNAPSHOT.read_bytes()
    validate_case_pdf(original)
    for mutation in (
        replace_once(original, b"<0002> <00DF>", b"<0002> <0053>"),
        replace_once(original, b"<0001> <0061>", b"<0001> <0041>"),
        replace_once(original, b"/Length1 5800", b"/Length1 5801"),
        replace_once(original, b"/Encoding /Identity-H", b"/Encoding /Identity-V"),
    ):
        try:
            validate_case_pdf(mutation)
        except (ValidationError, ValueError, KeyError):
            continue
        raise SystemExit("text-layout case checker accepted an atomic structural negative")
    print("PASS text-layout case transformation checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SNAPSHOT)
    parser.add_argument("--pdfbox-extraction", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    pdf = args.pdf.resolve()
    validate_case_pdf(pdf.read_bytes())
    print(f"PASS text-layout case transformation presentation, logical ActualText, CID, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
