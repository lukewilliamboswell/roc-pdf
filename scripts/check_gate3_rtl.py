#!/usr/bin/env python3
"""Original-byte checks for the Gate 3 real UAX #9 right-to-left slice."""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_gate3_text import PDFBOX_JAR, PDFBOX_SOURCE, cmap_mappings, decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require, validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "gate3_rtl_text" / "snapshot.pdf"

# The fixture text is the UAX #9 bracket-pair example; every expectation below
# is the normative Unicode 17.0.0 BidiCharacterTest row for it under a
# right-to-left paragraph direction.
LOGICAL_TEXT = "\u05d0\u05d1(\u05d2\u05d3[&ef].)gh"
NORMATIVE_VISUAL_ORDER = (12, 13, 11, 10, 9, 7, 8, 6, 5, 4, 3, 2, 1, 0)
# Logical indices 2, 5, 9 and 11 are the four brackets; at odd resolved level
# each paints its mirrored partner's glyph, so its CID maps back to the
# logical character rather than to the glyph's own character.
MIRRORED_LOGICAL_INDICES = (2, 5, 9, 11)
EXPECTED_ACTUAL_TEXT = b"<FEFF05D005D1002805D205D3005B002600650066005D002E002900670068>"
EXPECTED_SUBSET_SHA256 = "9ede12f9cb952e570feb4161f3951a3245116236f88da3511bdb01674d46705c"
EXPECTED_SUBSET_LENGTH1 = 4380
# PDFBox applies its own bidi normalization and bracket mirroring to the text
# it extracts, so this is an empirically pinned PDFBox-specific normalization
# of the painted sequence, not a second opinion on reading order. The
# authoritative logical recovery is the ActualText and ToUnicode evidence.
EXPECTED_PDFBOX_TEXT = "hg).]fe&[\u05d0\u05d1)\u05d2\u05d3\n".encode()

EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF05D005D1002805D205D3005B002600650066005D002E002900670068>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n"
    b"<0003> Tj\n"
    b"1 0 0 1 5.808 0 Tm\n"
    b"<0004> Tj\n"
    b"1 0 0 1 12.056 0 Tm\n"
    b"<0007> Tj\n"
    b"1 0 0 1 15.741 0 Tm\n"
    b"<0006> Tj\n"
    b"1 0 0 1 18.733 0 Tm\n"
    b"<0009> Tj\n"
    b"1 0 0 1 22.22 0 Tm\n"
    b"<0001> Tj\n"
    b"1 0 0 1 28.259 0 Tm\n"
    b"<0002> Tj\n"
    b"1 0 0 1 31.823 0 Tm\n"
    b"<0005> Tj\n"
    b"1 0 0 1 39.457 0 Tm\n"
    b"<000A> Tj\n"
    b"1 0 0 1 42.944 0 Tm\n"
    b"<000E> Tj\n"
    b"1 0 0 1 48.752 0 Tm\n"
    b"<000D> Tj\n"
    b"1 0 0 1 53.361 0 Tm\n"
    b"<0008> Tj\n"
    b"1 0 0 1 57.046 0 Tm\n"
    b"<000C> Tj\n"
    b"1 0 0 1 63.118 0 Tm\n"
    b"<000B> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)


def validate_gate3_rtl_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body and b"/Tabs /S" in page_body, "RTL page does not retain tagged reading-order facts")
    _, content = decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))

    require(EXPECTED_ACTUAL_TEXT in content, "RTL run does not carry the exact logical ActualText")
    actual_text_hex = EXPECTED_ACTUAL_TEXT[5:-1].decode()
    recovered = bytes.fromhex(actual_text_hex).decode("utf-16-be")
    require(recovered == LOGICAL_TEXT, f"RTL ActualText is not the logical source: {recovered!r}")

    resources = re.search(rb"/Font << /F1_0 ([1-9][0-9]*) 0 R >>", page_body)
    require(resources is not None, "RTL page has no exact text font resource")
    type0 = bodies[int(resources.group(1))]
    require(b"/Subtype /Type0" in type0 and b"/Encoding /Identity-H" in type0, "RTL font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0, b"DescendantFonts")
    require(len(descendants) == 1, "RTL Type 0 font must have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body, "RTL descendant is not CIDFontType2")

    _, cmap = decoded_stream(bodies, dictionary_ref(type0, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(len(shown) == len(LOGICAL_TEXT), f"RTL paints {len(shown)} CIDs, expected {len(LOGICAL_TEXT)}")

    # The painted sequence must be the normative visual order, recovered
    # through each CID's own ToUnicode row.
    painted = "".join(chr(scalar) for cid in shown for scalar in mappings[cid])
    expected_painted = "".join(LOGICAL_TEXT[index] for index in NORMATIVE_VISUAL_ORDER)
    require(painted == expected_painted, f"RTL paint order is not the resolved visual order: {painted!r}")

    # Every logical character keeps exactly one CID, and the four mirrored
    # brackets map back to their logical character, never to the glyph they
    # actually paint.
    by_logical = {index: shown[position] for position, index in enumerate(NORMATIVE_VISUAL_ORDER)}
    require(len(set(by_logical.values())) == len(LOGICAL_TEXT), "RTL CIDs are not one per logical character")
    for index in MIRRORED_LOGICAL_INDICES:
        cid = by_logical[index]
        require(mappings[cid] == (ord(LOGICAL_TEXT[index]),), f"mirrored logical index {index} does not map back to its source character")
    partners = {2: 11, 11: 2, 5: 9, 9: 5}
    for index, partner in partners.items():
        require(by_logical[index] != by_logical[partner], f"mirrored pair {index}/{partner} collapsed onto one CID")

    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(f"/Length1 {EXPECTED_SUBSET_LENGTH1}".encode() in font_dictionary, "RTL sanitized FontFile2 length differs")
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "RTL FontFile2 is not a TrueType-flavoured sfnt")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "RTL sanitized subset digest differs")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate3-rtl-") as temporary_name:
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
    print("PASS Gate 3 PDFBox extraction matches its pinned right-to-left normalization")


def self_test() -> None:
    original = SNAPSHOT.read_bytes()
    validate_gate3_rtl_pdf(original)
    for mutation in (
        # a mirrored bracket remapped to the glyph it actually paints, which
        # is the unmirrored-extraction bug this row exists to exclude
        replace_once(original, b"<0007> <0029>", b"<0007> <0028>"),
        # a Hebrew letter remapped, breaking the painted-order reconstruction
        replace_once(original, b"<000B> <05D0>", b"<000B> <05D2>"),
        # a changed embedded subset length
        replace_once(original, b"/Length1 4380", b"/Length1 4381"),
        # a changed encoding
        replace_once(original, b"/Encoding /Identity-H", b"/Encoding /Identity-V"),
    ):
        try:
            validate_gate3_rtl_pdf(mutation)
        except (ValidationError, ValueError, KeyError):
            continue
        raise SystemExit("Gate 3 RTL checker accepted an atomic structural negative")
    print("PASS Gate 3 RTL checker self-test")


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
    validate_gate3_rtl_pdf(pdf.read_bytes())
    print(f"PASS Gate 3 RTL resolved visual order, mirrored presentation, logical ActualText, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
