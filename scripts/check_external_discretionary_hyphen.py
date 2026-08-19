#!/usr/bin/env python3
"""Structural, logical-extraction, and presentation oracle for a selected external hyphen."""
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
SNAPSHOT = ROOT / "tests" / "actual_text" / "external_discretionary_hyphen.pdf"
EXPECTED_TEXT = b"ab\n"
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF00610062>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"1 0 0 1 6 0 Tm\n<0003> Tj\n"
    b"1 0 0 1 12 0 Tm\n<0002> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_MAPPINGS = {0x0001: (0x0061,), 0x0002: (0x0062,), 0x0003: (0x002D,)}
EXPECTED_SUBSET_SHA256 = "6e6811fa7dc3bd1b2334079f0d3c696d465655d502889515a51edd331d7a9be2"


def validate_external_discretionary_hyphen_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body and b"/Tabs /S" in page_body, "external discretionary-hyphen page lost tagged ownership")
    type0 = dictionary_ref(page_body, b"F1_0")
    type0_body = bodies[type0]
    require(b"/Subtype /Type0" in type0_body and b"/Encoding /Identity-H" in type0_body, "external discretionary-hyphen font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "external discretionary-hyphen Type 0 font has the wrong descendant count")
    cid_body = bodies[descendants[0]]
    require(b"/W [0 [656 562 612 460]]" in cid_body, "external discretionary-hyphen widths differ from the selected glyph closure")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0_body, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == EXPECTED_MAPPINGS, "external discretionary-hyphen ToUnicode does not retain explicit presentation Unicode")
    validate_actual_text_content(decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))[1], mappings)
    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(b"/Length1 6036" in font_dictionary, "external discretionary-hyphen sanitized FontFile2 length differs")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "external discretionary-hyphen subset digest differs")


def validate_actual_text_content(content: bytes, mappings: dict[int, tuple[int, ...]]) -> None:
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(shown == [0x0001, 0x0003, 0x0002], "external discretionary-hyphen visual glyph order changed")
    direct = "".join(chr(scalar) for cid in shown for scalar in mappings[cid])
    require(direct == "a-b", "external discretionary-hyphen CMap mapping is not the typed visible presentation")
    actual = re.search(rb"(?m)^/Span <</ActualText <([0-9A-F]+)>>> BDC$", content)
    require(actual is not None, "external discretionary-hyphen presentation is missing ActualText")
    require(bytes.fromhex(actual.group(1).decode("ascii")).decode("utf-16") == "ab", "ActualText did not preserve the zero-width logical source boundary")
    require(content.count(b" BDC\n") == content.count(b"EMC\n") == 2, "external discretionary-hyphen marked content is unbalanced")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-external-hyphen-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, "PDFBox extractor compilation failed")
        result = subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(result.returncode == 0 and not result.stderr, "PDFBox extraction failed")
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS text-layout PDFBox 3.0.8 extraction: external visible hyphen preserves logical ab")


def self_test() -> None:
    if not SNAPSHOT.is_file() or not SNAPSHOT.read_bytes().startswith(b"%PDF-"):
        print("PASS text-layout external discretionary-hyphen checker self-test deferred until its generated fixture exists")
        return
    pdf = SNAPSHOT.read_bytes()
    validate_external_discretionary_hyphen_pdf(pdf)
    for mutation in (replace_once(pdf, b"<0003> <002D>", b"<0003> <00AD>"),):
        try:
            validate_external_discretionary_hyphen_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("external discretionary-hyphen checker accepted a structural negative twin")
    try:
        validate_actual_text_content(
            EXPECTED_CONTENT.replace(b"FEFF00610062", b"FEFF00610063"),
            EXPECTED_MAPPINGS,
        )
    except (ValidationError, ValueError):
        pass
    else:
        raise SystemExit("external discretionary-hyphen checker accepted an ActualText negative twin")
    print("PASS text-layout external discretionary-hyphen structure and extraction checker self-test")


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
    validate_external_discretionary_hyphen_pdf(pdf.read_bytes())
    print(f"PASS text-layout external discretionary-hyphen structure, CID, presentation, and logical source checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
