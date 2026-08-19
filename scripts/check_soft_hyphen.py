#!/usr/bin/env python3
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
SNAPSHOT = ROOT / "tests" / "actual_text" / "soft_hyphen.pdf"
EXPECTED_TEXT = b"cooperate \n"
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF0063006F00AD006F007000650072006100740065>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0002> Tj\n"
    b"1 0 0 1 6 0 Tm\n<0004> Tj\n"
    b"1 0 0 1 12 0 Tm\n<0008> Tj\n"
    b"1 0 0 1 18 0 Tm\n<0004> Tj\n"
    b"1 0 0 1 24 0 Tm\n<0005> Tj\n"
    b"1 0 0 1 30 0 Tm\n<0003> Tj\n"
    b"1 0 0 1 36 0 Tm\n<0006> Tj\n"
    b"1 0 0 1 42 0 Tm\n<0001> Tj\n"
    b"1 0 0 1 48 0 Tm\n<0007> Tj\n"
    b"1 0 0 1 54 0 Tm\n<0003> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_MAPPINGS = {
    0x0001: (0x0061,),
    0x0002: (0x0063,),
    0x0003: (0x0065,),
    0x0004: (0x006F,),
    0x0005: (0x0070,),
    0x0006: (0x0072,),
    0x0007: (0x0074,),
    0x0008: (0x00AD,),
}
EXPECTED_SUBSET_SHA256 = "311755f3701e6290fc7e42eac9fefe18c9fb41a29f3fe16fbeed8a0206f72816"


def validate_soft_hyphen_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)
    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    font_match = re.search(rb"/Font << /F1_0 ([1-9][0-9]*) 0 R", page_body)
    require(font_match is not None, "soft-hyphen page has no planned Type 0 font")
    type0 = int(font_match.group(1))
    type0_body = bodies[type0]
    require(b"/Subtype /Type0" in type0_body and b"/Encoding /Identity-H" in type0_body, "soft-hyphen font is not Identity-H Type 0")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0_body, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == EXPECTED_MAPPINGS, "soft-hyphen ToUnicode mappings do not retain U+00AD")
    validate_actual_text_content(decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))[1], mappings)

    descendant = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendant) == 1, "soft-hyphen Type 0 font has the wrong descendant count")
    cid_body = bodies[descendant[0]]
    require(b"/W [0 [656 562 571 583 600 612 376 327 460]]" in cid_body, "soft-hyphen widths differ from the selected glyph closure")
    descriptor = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor, b"FontFile2"))
    require(b"/Length1 6868" in dictionary, "soft-hyphen subset has the wrong exact length")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "soft-hyphen subset digest differs")


def validate_actual_text_content(content: bytes, mappings: dict[int, tuple[int, ...]]) -> None:
    shown = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(all(cid in mappings for cid in shown), "soft-hyphen content shows an unmapped CID")
    direct = "".join(chr(scalar) for cid in shown for scalar in mappings[cid])
    require(direct == "co\u00adoperate", "soft-hyphen direct CMap extraction did not retain its original source scalar")
    actual = re.search(rb"(?m)^/Span <</ActualText <([0-9A-F]+)>>> BDC$", content)
    require(actual is not None, "soft-hyphen presentation is missing ActualText")
    require(bytes.fromhex(actual.group(1).decode("ascii")).decode("utf-16") == direct, "ActualText does not restore the exact source text")
    require(content.count(b" BDC\n") == content.count(b"EMC\n") == 2, "soft-hyphen marked content is unbalanced")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-soft-hyphen-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compile_result = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compile_result.returncode == 0 and not compile_result.stdout and not compile_result.stderr, "PDFBox extractor compilation failed")
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0 and not result.stderr, "PDFBox extraction failed")
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS text-layout PDFBox 3.0.8 extraction: selected soft hyphen remains source-preserving")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_soft_hyphen_pdf(pdf)
    for index, mutation in enumerate((
        replace_once(pdf, b"<0008> <00AD>", b"<0008> <002D>"),
        replace_once(pdf, b"/F1_0 20 0 R", b"/F1_0 19 0 R"),
    )):
        try:
            validate_soft_hyphen_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit(f"soft-hyphen checker accepted PDF negative twin {index}")
    try:
        validate_actual_text_content(
            EXPECTED_CONTENT.replace(b"FEFF0063006F00AD006F", b"FEFF0063006F002D006F"),
            EXPECTED_MAPPINGS,
        )
    except (ValidationError, ValueError):
        pass
    else:
        raise SystemExit("soft-hyphen checker accepted an ActualText negative twin")
    print("PASS text-layout soft-hyphen structure and extraction checker self-test")


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
    validate_soft_hyphen_pdf(pdf.read_bytes())
    print(f"PASS text-layout soft-hyphen structure, CID, and mapping checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
