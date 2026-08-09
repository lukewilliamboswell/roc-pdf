#!/usr/bin/env python3
"""Independent structural and reader checks for the Gate 3 facade-output PDF.

This checker deliberately receives the authored extraction string and renderer
metrics as arguments.  The facade pipeline determines its own object numbers,
subset size, glyph/CID plan, and content-stream layout; this oracle verifies
the resulting facts instead of encoding those implementation details as a
second generator.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

from check_gate3_renderers import InkMetrics, check_renderers
from check_gate3_text import PDFBOX_JAR, PDFBOX_SOURCE, cmap_mappings, decoded_stream, only_object, replace_once
from check_pdf_structure import ValidationError, dictionary_ref, dictionary_ref_array, object_slices, require, validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SELF_TEST_SNAPSHOT = ROOT / "tests" / "gate3_text" / "snapshot.pdf"
CID_TOKEN = re.compile(rb"<([0-9A-F]{4})> Tj")


def only_page_font(page: bytes) -> tuple[bytes, int]:
    resources = re.search(rb"/Resources << .*? /Font << (.*?) >> .*? >>", page)
    require(resources is not None, "page does not contain a resource font dictionary")
    fonts = re.findall(rb"/([A-Za-z][A-Za-z0-9_]*) ([1-9][0-9]*) 0 R", resources.group(1))
    require(len(fonts) == 1, f"facade output must use exactly one page font, found {len(fonts)}")
    return fonts[0][0], int(fonts[0][1])


def content_text(content: bytes, mappings: dict[int, tuple[int, ...]]) -> str:
    shown_cids = [int(value, 16) for value in CID_TOKEN.findall(content)]
    require(shown_cids, "facade content does not paint any CID text")
    require(all(cid in mappings for cid in shown_cids), "facade content contains a CID without a ToUnicode mapping")
    return "".join(chr(scalar) for cid in shown_cids for scalar in mappings[cid])


def validate_facade_output_pdf(pdf: bytes, expected_text: str) -> None:
    _, bodies = object_slices(pdf)

    catalog = only_object(bodies, b"/Type /Catalog ", "catalog")
    catalog_body = bodies[catalog]
    require(b"/MarkInfo << /Marked true >>" in catalog_body, "facade catalog does not declare marked content")
    structure_root = dictionary_ref(catalog_body, b"StructTreeRoot")
    require(b"/Type /StructTreeRoot" in bodies[structure_root], "facade catalog has no StructTreeRoot")

    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body, "facade page does not have the planned ParentTree key")
    require(b"/Tabs /S" in page_body, "facade page tab order is not structure order")
    _, content = decoded_stream(bodies, dictionary_ref(page_body, b"Contents"))
    validate_pdf(pdf, 1, content, normalized_plan_identity=True)
    require(content.count(b" BDC\n") >= 1, "facade content is missing fragment marked content")
    require(content.count(b" BDC\n") == content.count(b"EMC\n"), "facade marked-content scopes are unbalanced")
    require(content.count(b"BT\n") == content.count(b"ET\n") >= 1, "facade text-object scopes are unbalanced")
    require(b"/ActualText " not in content, "simple facade output unexpectedly requires ActualText")

    resource_name, type0 = only_page_font(page_body)
    require(re.search(rb"/" + re.escape(resource_name) + rb" [1-9][0-9]*(?:\\.[0-9]+)? Tf\n", content) is not None, "content does not select its page font")
    type0_body = bodies[type0]
    require(b"/Subtype /Type0" in type0_body, "page font is not Type 0")
    require(b"/Encoding /Identity-H" in type0_body, "Type 0 font does not use Identity-H")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "Type 0 font must have exactly one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body, "Type 0 descendant is not CIDFontType2")

    cid_map = dictionary_ref(cid_body, b"CIDToGIDMap")
    cid_dictionary, cid_bytes = decoded_stream(bodies, cid_map)
    require(b"/Filter " not in cid_dictionary, "CIDToGIDMap unexpectedly uses a filter")
    require(len(cid_bytes) > 0 and len(cid_bytes) % 2 == 0, "CIDToGIDMap has no complete CID entries")
    cid_to_gid = [int.from_bytes(cid_bytes[index : index + 2], "big") for index in range(0, len(cid_bytes), 2)]
    require(all(cid == gid for cid, gid in enumerate(cid_to_gid)), "facade CIDToGIDMap is not the planned identity map")

    cmap = dictionary_ref(type0_body, b"ToUnicode")
    _, cmap_bytes = decoded_stream(bodies, cmap)
    mappings = cmap_mappings(cmap_bytes)
    displayed = content_text(content, mappings)
    require(displayed == expected_text, f"direct CID/ToUnicode reconstruction is {displayed!r}, expected {expected_text!r}")
    require(all(cid < len(cid_to_gid) for cid in mappings), "ToUnicode contains a CID outside CIDToGIDMap")

    descriptor = dictionary_ref(cid_body, b"FontDescriptor")
    descriptor_body = bodies[descriptor]
    require(b"/Type /FontDescriptor" in descriptor_body, "CID descendant has no FontDescriptor")
    font_file = dictionary_ref(descriptor_body, b"FontFile2")
    font_dictionary, font_bytes = decoded_stream(bodies, font_file)
    length = re.search(rb"/Length1 ([0-9]+)", font_dictionary)
    require(length is not None and int(length.group(1)) == len(font_bytes), "FontFile2 Length1 does not equal the embedded font bytes")
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "embedded FontFile2 is not a TrueType-flavoured sfnt")
    names = re.findall(rb"/(?:BaseFont|FontName) /([A-Z]{6}\+[A-Za-z0-9._-]+)", type0_body + cid_body + descriptor_body)
    require(len(names) == 3 and len(set(names)) == 1, "font dictionaries do not retain one deterministic subset identity")


def check_pdfbox_extraction(pdf: Path, expected_text: str) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate3-facade-output-") as temporary_name:
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
        require(result.stdout == (expected_text + "\n").encode(), f"PDFBox extracted {result.stdout!r}, expected {(expected_text + chr(10)).encode()!r}")
    print(f"PASS Gate 3 facade output PDFBox 3.0.8 extraction: exact UTF-8 {expected_text!r}")


def parse_metrics(value: str) -> InkMetrics:
    try:
        numbers = tuple(int(item) for item in value.split(","))
    except ValueError as error:
        raise SystemExit("--renderer-metrics must contain seven comma-separated integers") from error
    if len(numbers) != 7:
        raise SystemExit("--renderer-metrics must contain x0,y0,x1,y1,changed,dark,ink")
    return InkMetrics(bounds=numbers[:4], changed_pixels=numbers[4], dark_pixels=numbers[5], ink=numbers[6])


def self_test() -> None:
    pdf = SELF_TEST_SNAPSHOT.read_bytes()
    validate_facade_output_pdf(pdf, "Café PDF")
    mutations = (
        replace_once(pdf, b"<0007> <00E9>", b"<0007> <00E8>"),
        replace_once(pdf, b"/Encoding /Identity-H", b"/Encoding /Identity-V"),
        replace_once(pdf, b"/Length1 6776", b"/Length1 6775"),
    )
    for index, mutation in enumerate(mutations):
        try:
            validate_facade_output_pdf(mutation, "Café PDF")
        except ValidationError:
            continue
        raise SystemExit(f"Gate 3 facade-output checker accepted atomic negative twin {index}")
    print("PASS Gate 3 facade-output structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--expected-text")
    parser.add_argument("--pdfbox-extraction", action="store_true")
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--pdfbox-renderer-metrics")
    parser.add_argument("--pdfium-renderer-metrics")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None or args.expected_text is None:
        parser.error("pdf and --expected-text are required unless --self-test is used")
    renderer_arguments = (args.pdfium_renderer, args.pdfbox_renderer_metrics, args.pdfium_renderer_metrics)
    if any(value is not None for value in renderer_arguments) and any(value is None for value in renderer_arguments):
        parser.error(
            "--pdfium-renderer, --pdfbox-renderer-metrics, and --pdfium-renderer-metrics must be supplied together"
        )
    pdf = args.pdf.resolve()
    validate_facade_output_pdf(pdf.read_bytes(), args.expected_text)
    print(f"PASS Gate 3 facade output structure, font, CID, ToUnicode, and content checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf, args.expected_text)
    if args.pdfium_renderer is not None:
        check_renderers(
            args.pdfium_renderer.resolve(),
            args.pdfium_working_directory,
            pdf,
            "facade output",
            parse_metrics(args.pdfbox_renderer_metrics),
            parse_metrics(args.pdfium_renderer_metrics),
        )


if __name__ == "__main__":
    main()
