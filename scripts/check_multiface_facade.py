#!/usr/bin/env python3
"""Structural oracle for the text-layout public ordered multi-face facade slice."""
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
SNAPSHOT = ROOT / "tests" / "multiface_facade" / "multiface_facade.pdf"
EXPECTED_TEXT = "C中é\n".encode()
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 759 cm\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"ET\n"
    b"Q\n"
    b"EMC\n"
    b"/P <</MCID 1>> BDC\n"
    b"q\n"
    b"1 0 0 1 80.035 759 cm\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_1 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"ET\n"
    b"Q\n"
    b"EMC\n"
    b"/P <</MCID 2>> BDC\n"
    b"q\n"
    b"1 0 0 1 91.035 759 cm\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0003> Tj\n"
    b"ET\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_LATIN_MAPPINGS = {0x0001: (0x0043,), 0x0003: (0x00E9,)}
EXPECTED_CJK_MAPPINGS = {0x0001: (0x4E2D,)}
EXPECTED_LATIN_SUBSET_SHA256 = "77b0528896cf30390cecb2554e74d424aa5331f153845282bc63cacded6d0d29"
EXPECTED_CJK_SUBSET_SHA256 = "e63604452a131dbaf60dd6baf21017b1ac63e13199c5bd5846dd77ecb97e2175"


def font_facts(bodies: dict[int, bytes], type0_number: int, expected_widths: bytes) -> tuple[dict[int, tuple[int, ...]], bytes, bytes]:
    type0 = bodies[type0_number]
    require(b"/Subtype /Type0" in type0 and b"/Encoding /Identity-H" in type0, "multiface facade font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0, b"DescendantFonts")
    require(len(descendants) == 1, "multiface facade Type 0 font must have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body, "multiface facade descendant is not CIDFontType2")
    require(expected_widths in cid_body, "multiface facade CID widths are not the inspected fixture metrics")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0, b"ToUnicode"))
    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "multiface facade FontFile2 is not a TrueType-flavoured sfnt")
    return cmap_mappings(cmap), cmap, font_bytes


def validate_multiface_facade_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    resources = re.search(
        rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /Font << /F1_0 ([1-9][0-9]*) 0 R /F1_1 ([1-9][0-9]*) 0 R >> /XObject << >> >>",
        page_body,
    )
    require(resources is not None, "multiface facade page does not carry exactly the two dense font resources")
    latin_mappings, latin_cmap, latin_bytes = font_facts(bodies, int(resources.group(2)), b"/W [0 [656 730 583 583 0]]")
    cjk_mappings, cjk_cmap, cjk_bytes = font_facts(bodies, int(resources.group(3)), b"/W [0 [1000 1000]]")
    require(latin_mappings == EXPECTED_LATIN_MAPPINGS, "multiface facade Latin ToUnicode rows differ")
    require(cjk_mappings == EXPECTED_CJK_MAPPINGS, "multiface facade Han ToUnicode rows differ")
    require(b"<0001> <0043>" in latin_cmap and b"<0003> <00E9>" in latin_cmap, "multiface facade Latin CMap rows are not canonical UTF-16BE")
    require(b"<0001> <4E2D>" in cjk_cmap, "multiface facade Han CMap row is not canonical UTF-16BE")
    require(hashlib.sha256(latin_bytes).hexdigest() == EXPECTED_LATIN_SUBSET_SHA256, "multiface facade Latin subset digest differs")
    require(hashlib.sha256(cjk_bytes).hexdigest() == EXPECTED_CJK_SUBSET_SHA256, "multiface facade Han subset digest differs")

    shown = re.findall(rb"/(F1_[01]) 11 Tf\n1 0 0 1 0 0 Tm\n<([0-9A-F]{4})> Tj", EXPECTED_CONTENT)
    require(shown == [(b"F1_0", b"0001"), (b"F1_1", b"0001"), (b"F1_0", b"0003")], "multiface facade paint sequence differs")
    by_font = {b"F1_0": latin_mappings, b"F1_1": cjk_mappings}
    direct = "".join(chr(scalar) for font, cid in shown for scalar in by_font[font][int(cid, 16)]).encode() + b"\n"
    require(direct == EXPECTED_TEXT, "multiface facade CID/ToUnicode reconstruction differs from the source")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-multiface-facade-") as temporary_name:
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
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS text-layout PDFBox extraction preserves the mixed-face source text")


def self_test() -> None:
    original = SNAPSHOT.read_bytes()
    validate_multiface_facade_pdf(original)
    for mutation in (
        replace_once(original, b"<0001> <4E2D>", b"<0001> <4E2E>"),
        replace_once(original, b"/W [0 [1000 1000]]", b"/W [0 [1000 1001]]"),
        replace_once(original, b"<0003> <00E9>", b"<0003> <00EA>"),
    ):
        try:
            validate_multiface_facade_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("text-layout multiface facade checker accepted an atomic structural negative")
    print("PASS text-layout multiface facade checker self-test")


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
    validate_multiface_facade_pdf(pdf.read_bytes())
    print(f"PASS text-layout multiface facade structure, dense font resources, CID, and per-font ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
