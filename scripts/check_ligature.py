#!/usr/bin/env python3
"""Original-byte checks for the text-layout advanced `fi` ligature slice."""
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
SNAPSHOT = ROOT / "tests" / "actual_text" / "ligature_text.pdf"
EXPECTED_TEXT = "fi\n".encode()
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF00660069>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_SUBSET_SHA256 = "e99ef53b60c53e5252f0f4ffc0b30c6406766244dae663bf7b147020d326e07b"


def validate_ligature_pdf(pdf: bytes) -> None:
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    _, content = decoded_stream(bodies, dictionary_ref(bodies[page], b"Contents"))
    validate_pdf(pdf, 1, content, normalized_plan_identity=True)
    require(content.count(b" BDC\n") == content.count(b"EMC\n") == 2, "ligature marked content is unbalanced")
    require(b"/Span <</ActualText <FEFF00660069>>> BDC\n" in content, "ligature lacks exact logical ActualText")
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(shown == [1], f"ligature content CIDs differ: {shown!r}")
    resources = re.search(rb"/Resources << .*? /Font << /F1_0 ([1-9][0-9]*) 0 R >>", bodies[page])
    require(resources is not None, "ligature page has no text font resource")
    type0 = bodies[int(resources.group(1))]
    require(b"/Subtype /Type0" in type0 and b"/Encoding /Identity-H" in type0, "ligature font is not Identity-H Type 0")
    cid = bodies[dictionary_ref_array(type0, b"DescendantFonts")[0]]
    require(b"/W [0 [464 633]]" in cid, "ligature CID widths differ from the inspected fixture metrics")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == {1: (0x0066, 0x0069)}, "ligature ToUnicode does not retain logical f+i")
    require(b"<0001> <00660069>" in cmap, "ligature ToUnicode is not canonical UTF-16BE")
    direct = "".join(chr(scalar) for code in shown for scalar in mappings[code]).encode() + b"\n"
    require(direct == EXPECTED_TEXT, "ligature CID/ToUnicode reconstruction differs from logical source")
    descriptor = bodies[dictionary_ref(cid, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(b"/Length1 2144" in font_dictionary and font_bytes.startswith(b"\x00\x01\x00\x00"), "ligature subset is not the expected sanitized TrueType program")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "ligature subset digest differs")


def check_pdfbox_extraction(pdf: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="roc-pdf-ligature-") as directory:
        classes = Path(directory) / "classes"
        classes.mkdir()
        compiled = subprocess.run(["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, "PDFBox extractor compilation failed")
        result = subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        require(result.returncode == 0 and not result.stderr and result.stdout == EXPECTED_TEXT, result.stderr.decode(errors="replace") or repr(result.stdout))
    print("PASS text-layout PDFBox extraction preserves logical fi")


def self_test() -> None:
    original = SNAPSHOT.read_bytes()
    validate_ligature_pdf(original)
    for mutation in (replace_once(original, b"<0001> <00660069>", b"<0001> <0066006A>"), replace_once(original, b"/Encoding /Identity-H", b"/Encoding /Identity-V")):
        try:
            validate_ligature_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("text-layout ligature checker accepted an atomic structural negative")
    print("PASS text-layout ligature checker self-test")


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
    validate_ligature_pdf(pdf.read_bytes())
    print(f"PASS text-layout ligature structure, CID, ActualText, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
