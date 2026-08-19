#!/usr/bin/env python3
"""Structural and extraction oracle for ordered multi-face text-layout output."""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_text import PDFBOX_JAR, PDFBOX_SOURCE, cmap_mappings, decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require, validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "actual_text" / "multiface_text.pdf"
EXPECTED_TEXT = "C中é\n".encode()
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n1 0 0 1 72 700 cm\n"
    b"/CS1_0 cs\n0 scn\nBT\n0 Tr\n/F1_0 11 Tf\n1 0 0 1 0 0 Tm\n<0001> Tj\nET\n"
    b"/CS1_0 cs\n0 scn\nBT\n0 Tr\n/F1_1 11 Tf\n1 0 0 1 7 0 Tm\n<0001> Tj\nET\n"
    b"/CS1_0 cs\n0 scn\nBT\n0 Tr\n/F1_0 11 Tf\n1 0 0 1 18 0 Tm\n<0003> Tj\nET\n"
    b"Q\nEMC\n"
)
EXPECTED_LATIN = {0x0001: (0x0043,), 0x0003: (0x00E9,)}
EXPECTED_CJK = {0x0001: (0x4E2D,)}


def font_mappings(bodies: dict[int, bytes], type0: int) -> dict[int, tuple[int, ...]]:
    _, cmap = decoded_stream(bodies, dictionary_ref(bodies[type0], b"ToUnicode"))
    return cmap_mappings(cmap)


def validate_multiface_text_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    resources = re.search(rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /Font << /F1_0 ([1-9][0-9]*) 0 R /F1_1 ([1-9][0-9]*) 0 R >> /XObject << >> >>", page_body)
    require(resources is not None, "multi-face page does not have the exact two-font resource closure")
    require(b"/CalGray" in bodies[int(resources.group(1))], "multi-face text color is not calibrated Gray")
    latin, cjk = int(resources.group(2)), int(resources.group(3))
    for font in (latin, cjk):
        body = bodies[font]
        require(b"/Subtype /Type0" in body and b"/Encoding /Identity-H" in body, "multi-face resource is not an Identity-H Type 0 font")
        require(len(dictionary_ref_array(body, b"DescendantFonts")) == 1, "multi-face Type 0 font does not have exactly one CID descendant")
    require(font_mappings(bodies, latin) == EXPECTED_LATIN, "Latin Type 0 ToUnicode mappings differ from the two selected Latin runs")
    require(font_mappings(bodies, cjk) == EXPECTED_CJK, "CJK Type 0 ToUnicode mapping differs from the selected Han run")
    for font in (latin, cjk):
        cid = dictionary_ref_array(bodies[font], b"DescendantFonts")[0]
        descriptor = dictionary_ref(bodies[cid], b"FontDescriptor")
        dictionary, program = decoded_stream(bodies, dictionary_ref(bodies[descriptor], b"FontFile2"))
        require(b"/Length1 " in dictionary and program.startswith(b"\x00\x01\x00\x00"), "embedded multi-face program is not a sanitized TrueType sfnt")
        require(b"/FontFile2" in bodies[descriptor], "multi-face descriptor lacks an embedded font program")
    shown = ((latin, 0x0001), (cjk, 0x0001), (latin, 0x0003))
    direct = "".join(chr(scalar) for font, cid in shown for scalar in font_mappings(bodies, font)[cid]).encode() + b"\n"
    require(direct == EXPECTED_TEXT, "two-font CID/ToUnicode reconstruction differs from paint-order source text")
    require(b"/FontFile2" in pdf and b"/Type /Font" in pdf, "multi-face PDF lacks embedded font closure")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-multiface-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, compiled.stderr.decode(errors="replace") or "PDFBox extractor compilation failed")
        result = subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(result.returncode == 0 and not result.stderr, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS text-layout PDFBox 3.0.8 extraction: exact mixed Latin+CJK source")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_multiface_text_pdf(pdf)
    for mutation in (replace_once(pdf, b"/F1_1 ", b"/F1_X "), replace_once(pdf, b"<0001> <4E2D>", b"<0001> <4E2E>")):
        try:
            validate_multiface_text_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("text-layout multi-face checker accepted a structural negative twin")
    print("PASS text-layout multi-face text structure and extraction checker self-test")


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
    validate_multiface_text_pdf(pdf.read_bytes())
    print(f"PASS text-layout multi-face text structure, two Type 0/CID resources, and mappings: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
