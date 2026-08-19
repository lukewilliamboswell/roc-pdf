#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_text import (
    PDFBOX_JAR,
    PDFBOX_SOURCE,
    cmap_mappings,
    decoded_stream,
    only_object,
    replace_once,
)
from check_pdf_structure import (
    ValidationError,
    dictionary_ref,
    dictionary_ref_array,
    object_slices,
    require,
    validate_pdf,
)


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "actual_text" / "actual_text.pdf"
EXPECTED_TEXT = b"fa\n"
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"q\n"
    b"1 0 0 1 72 700 cm\n"
    b"/Span <</ActualText <FEFF00660061>>> BDC\n"
    b"/CS1_0 cs\n"
    b"0 scn\n"
    b"BT\n"
    b"0 Tr\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 0 0 Tm\n<0001> Tj\n"
    b"1 0 0 1 6 0 Tm\n<0002> Tj\n"
    b"ET\n"
    b"EMC\n"
    b"Q\n"
    b"EMC\n"
)
EXPECTED_MAPPINGS = {0x0001: (0x0061,), 0x0002: (0x0066,)}
EXPECTED_SUBSET_SHA256 = "82a6b44a06ffea8cb1a01fafe00a8cc5c8b1bc2434e29e01feb6edd0a3aa30bc"


def validate_actual_text_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)

    catalog = only_object(bodies, b"/Type /Catalog ", "catalog")
    catalog_body = bodies[catalog]
    require(b"/MarkInfo << /Marked true >>" in catalog_body, "ActualText catalog does not declare marked content")
    structure_root = dictionary_ref(catalog_body, b"StructTreeRoot")
    require(b"/Type /StructTreeRoot" in bodies[structure_root], "ActualText structure root has the wrong type")

    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body, "ActualText page does not have the planned ParentTree key")
    require(b"/Tabs /S" in page_body, "ActualText page tab order is not structure order")
    _, content = decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))
    resources = re.search(
        rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /Font << /F1_0 ([1-9][0-9]*) 0 R >> /XObject << >> >>",
        page_body,
    )
    require(resources is not None, "ActualText page does not have the exact color/font resource closure")
    color_space = int(resources.group(1))
    require(b"/CalGray" in bodies[color_space], "ActualText color resource is not calibrated Gray")
    type0_body = bodies[int(resources.group(2))]
    require(b"/Subtype /Type0" in type0_body and b"/Encoding /Identity-H" in type0_body, "ActualText page font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "ActualText Type 0 font does not have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/W [0 [656 562 370]]" in cid_body, "ActualText widths differ from the validated caller face")

    _, cmap = decoded_stream(bodies, dictionary_ref(type0_body, b"ToUnicode"))
    mappings = cmap_mappings(cmap)
    require(mappings == EXPECTED_MAPPINGS, "ActualText ToUnicode mappings differ from the logical clusters")
    validate_actual_text_content(content, mappings)

    descriptor_body = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor_body, b"FontFile2"))
    require(b"/Length1 5956" in font_dictionary, "ActualText embedded font Length1 is not exact")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "ActualText sanitized subset digest differs")


def validate_actual_text_content(content: bytes, mappings: dict[int, tuple[int, ...]]) -> None:
    shown_cids = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", content)]
    require(all(cid in mappings for cid in shown_cids), "ActualText content shows an unmapped CID")
    direct_text = "".join(chr(scalar) for cid in shown_cids for scalar in mappings[cid])
    require(direct_text == "af", "ActualText fixture does not prove visual glyph reordering")

    actual_match = re.search(rb"(?m)^/Span <</ActualText <([0-9A-F]+)>>> BDC$", content)
    require(actual_match is not None, "ActualText marked-content property is not canonical")
    actual_bytes = bytes.fromhex(actual_match.group(1).decode("ascii"))
    require(actual_bytes.decode("utf-16") == "fa", "ActualText property does not restore logical source order")
    require(content.count(b" BDC\n") == content.count(b"EMC\n") == 2, "ActualText and fragment marked content are not balanced")
    require(
        content.index(b"/P <</MCID 0>> BDC\n")
        < content.index(b"/Span <</ActualText ")
        < content.index(b"BT\n")
        < content.index(b"ET\n")
        < content.index(b"EMC\n"),
        "ActualText is not nested inside its fragment and around the text object",
    )


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-actual-text-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0, compiled.stderr.decode(errors="replace") or "PDFBox extractor compilation failed")
        require(not compiled.stdout and not compiled.stderr, "PDFBox extractor compilation produced diagnostics")
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(not result.stderr, f"PDFBox extraction wrote diagnostics: {result.stderr!r}")
        require(result.stdout == EXPECTED_TEXT, f"PDFBox extracted {result.stdout!r}, expected {EXPECTED_TEXT!r}")
    print("PASS text-layout PDFBox 3.0.8 extraction: ActualText restores logical fa from visual af")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_actual_text_pdf(pdf)
    mutations = (
        replace_once(pdf, b"<0001> <0061>", b"<0001> <0062>"),
        replace_once(pdf, b"/F1_0 20 0 R", b"/F1_0 19 0 R"),
    )
    for index, mutation in enumerate(mutations):
        try:
            validate_actual_text_pdf(mutation)
        except (ValidationError, ValueError):
            continue
        raise SystemExit(f"text-layout ActualText checker accepted negative twin {index}")
    content_mutations = (
        EXPECTED_CONTENT.replace(b"FEFF00660061", b"FEFF00670061"),
        EXPECTED_CONTENT.replace(b"EMC\n", b"EMD\n"),
    )
    for index, mutation in enumerate(content_mutations):
        try:
            validate_actual_text_content(mutation, EXPECTED_MAPPINGS)
        except (ValidationError, ValueError):
            continue
        raise SystemExit(f"text-layout ActualText content checker accepted negative twin {index}")
    print("PASS text-layout reordered ActualText structure and extraction checker self-test")


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
    validate_actual_text_pdf(pdf.read_bytes())
    print(f"PASS text-layout reordered ActualText structure, CID, and mapping checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
