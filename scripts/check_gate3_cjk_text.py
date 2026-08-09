#!/usr/bin/env python3
"""Structural and extraction oracle for the Gate 3 one-scalar CJK slice."""
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
SNAPSHOT = ROOT / "tests" / "gate3_cjk_text" / "snapshot.pdf"
EXPECTED_TEXT = "中\n".encode()
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"ET\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_MAPPINGS = {0x0001: (0x4E2D,)}
EXPECTED_SUBSET_SHA256 = "e63604452a131dbaf60dd6baf21017b1ac63e13199c5bd5846dd77ecb97e2175"


def validate_gate3_cjk_text_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    catalog = only_object(bodies, b"/Type /Catalog ", "catalog")
    require(b"/MarkInfo << /Marked true >>" in bodies[catalog], "CJK catalog does not declare marked content")
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body and b"/Tabs /S" in page_body, "CJK page does not retain tagged reading-order facts")
    resources = re.search(rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /Font << /F1_0 ([1-9][0-9]*) 0 R >> /XObject << >> >>", page_body)
    require(resources is not None, "CJK page does not have the exact color/font resource closure")
    require(b"/CalGray" in bodies[int(resources.group(1))], "CJK text color is not calibrated Gray")
    type0_body = bodies[int(resources.group(2))]
    require(b"/Subtype /Type0" in type0_body and b"/Encoding /Identity-H" in type0_body, "CJK page font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "CJK Type 0 font must have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body and b"/W [0 [1000 1000]]" in cid_body, "CJK CID widths are not the inspected fixture metrics")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0_body, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == EXPECTED_MAPPINGS, "CJK ToUnicode mapping is not the exact source scalar")
    require(b"<0001> <4E2D>" in cmap, "CJK ToUnicode mapping is not canonical UTF-16BE BMP output")
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", EXPECTED_CONTENT)]
    direct = "".join(chr(scalar) for cid in shown for scalar in mappings[cid]).encode() + b"\n"
    require(direct == EXPECTED_TEXT, "CJK CID/ToUnicode reconstruction differs from the source")
    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(b"/Length1 940" in font_dictionary, "CJK sanitized FontFile2 length differs")
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "CJK FontFile2 is not a TrueType-flavoured sfnt")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "CJK sanitized subset digest differs")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate3-cjk-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, compiled.stderr.decode(errors="replace") or "PDFBox extractor compilation failed")
        result = subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(result.returncode == 0 and not result.stderr, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS Gate 3 PDFBox 3.0.8 extraction: exact CJK UTF-8 source")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_gate3_cjk_text_pdf(pdf)
    for mutation in (replace_once(pdf, b"<0001> <4E2D>", b"<0001> <4E2E>"), replace_once(pdf, b"/Encoding /Identity-H", b"/Encoding /Identity-V")):
        try:
            validate_gate3_cjk_text_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("Gate 3 CJK checker accepted a structural negative twin")
    print("PASS Gate 3 CJK text structure and extraction checker self-test")


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
    validate_gate3_cjk_text_pdf(pdf.read_bytes())
    print(f"PASS Gate 3 CJK text structure, CID, and mapping checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
