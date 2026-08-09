#!/usr/bin/env python3
"""Original-byte checks for the Gate 3 advanced combining-mark slice."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_gate3_text import PDFBOX_JAR, PDFBOX_SOURCE, cmap_mappings, decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require, validate_pdf


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_TEXT = "A\u0300"


def validate_combining_pdf(pdf: bytes) -> None:
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    content_ref = dictionary_ref(page_body, b"Contents")
    _, content = decoded_stream(bodies, content_ref)
    validate_pdf(pdf, 1, content, normalized_plan_identity=True)
    require(b"/P <</MCID 0>> BDC\n" in content, "combining text has no fragment MCID")
    require(content.count(b" BDC\n") == content.count(b"EMC\n") == 1, "combining marked content is unbalanced")
    require(content.count(b"BT\n") == content.count(b"ET\n") == 1, "combining text object is unbalanced")
    require(b"/ActualText " not in content, "one-glyph combining mapping must use its complete ToUnicode row")

    resources = re.search(rb"/Resources << .*? /Font << /F1_0 ([1-9][0-9]*) 0 R >>", page_body)
    require(resources is not None, "combining page has no exact text font resource")
    type0 = bodies[int(resources.group(1))]
    require(b"/Subtype /Type0" in type0 and b"/Encoding /Identity-H" in type0, "combining font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0, b"DescendantFonts")
    require(len(descendants) == 1 and b"/Subtype /CIDFontType2" in bodies[descendants[0]], "combining font has no CIDFontType2 descendant")

    _, cmap = decoded_stream(bodies, dictionary_ref(type0, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(shown == [2], f"combining content CIDs differ: {shown!r}")
    require(mappings == {2: (0x0041, 0x0300)}, "combining ToUnicode row does not retain decomposed source scalars")
    direct = "".join(chr(scalar) for cid in shown for scalar in mappings[cid])
    require(direct == EXPECTED_TEXT, f"direct combining extraction differs: {direct!r}")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate3-combining-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, compiled.stderr.decode(errors="replace"))
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        expected = (EXPECTED_TEXT + "\n").encode()
        require(result.returncode == 0 and not result.stderr and result.stdout == expected, result.stderr.decode(errors="replace") or repr(result.stdout))
    print("PASS Gate 3 PDFBox extraction preserves decomposed combining text")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--pdfbox-extraction", action="store_true")
    args = parser.parse_args()
    pdf = args.pdf.resolve()
    original = pdf.read_bytes()
    validate_combining_pdf(original)
    for mutation in (
        replace_once(original, b"<0002> <00410300>", b"<0002> <00410301>"),
        replace_once(original, b"/Encoding /Identity-H", b"/Encoding /Identity-V"),
    ):
        try:
            validate_combining_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit("Gate 3 combining checker accepted an atomic structural negative")
    print(f"PASS Gate 3 combining structure, CID, and decomposed ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
