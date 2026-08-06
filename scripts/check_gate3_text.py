#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
import zlib
from pathlib import Path

from check_pdf_structure import (
    ValidationError,
    dictionary_ref,
    dictionary_ref_array,
    indirect_length,
    object_slices,
    require,
    stream_parts,
    validate_pdf,
)


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "gate3_text" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
PDFBOX_SOURCE = ROOT / "scripts" / "PdfBoxTextExtract.java"
EXPECTED_TEXT = "Café PDF\n".encode()
EXPECTED_CONTENT = (
    b"BT\n"
    b"/F1_0 11 Tf\n"
    b"1 0 0 1 72 700 Tm\n<0001> Tj\n"
    b"1 0 0 1 80.035 700 Tm\n<0005> Tj\n"
    b"1 0 0 1 86.212 700 Tm\n<0008> Tj\n"
    b"1 0 0 1 90.283 700 Tm\n<0007> Tj\n"
    b"1 0 0 1 96.696 700 Tm\n<000A> Tj\n"
    b"1 0 0 1 99.79 700 Tm\n<0004> Tj\n"
    b"1 0 0 1 106.815 700 Tm\n<0002> Tj\n"
    b"1 0 0 1 114.753 700 Tm\n<0003> Tj\n"
    b"ET\n"
)
EXPECTED_MAPPINGS = {
    0x0001: (0x0043,),
    0x0002: (0x0044,),
    0x0003: (0x0046,),
    0x0004: (0x0050,),
    0x0005: (0x0061,),
    0x0007: (0x00E9,),
    0x0008: (0x0066,),
    0x000A: (0x0020,),
}
EXPECTED_SUBSET_SHA256 = "d6fc1c3f18830871b0d04fb7d5fd7d60c5b25d9ba9c28b621059526235c6382c"


def only_object(bodies: dict[int, bytes], marker: bytes, label: str) -> int:
    matches = [number for number, body in bodies.items() if marker in body]
    require(len(matches) == 1, f"expected exactly one {label}, found {len(matches)}")
    return matches[0]


def decoded_stream(bodies: dict[int, bytes], number: int) -> tuple[bytes, bytes]:
    body = bodies[number]
    marker_offset = body.find(b"stream\n")
    require(marker_offset >= 0, f"object {number} is not a stream")
    dictionary = body[:marker_offset]
    length = indirect_length(bodies, dictionary_ref(dictionary, b"Length"))
    _, encoded = stream_parts(body, length)
    if b"/Filter /FlateDecode" not in dictionary:
        return dictionary, encoded
    try:
        return dictionary, zlib.decompress(encoded)
    except zlib.error as error:
        raise ValidationError(f"object {number} has invalid zlib DEFLATE: {error}") from error


def cmap_mappings(cmap: bytes) -> dict[int, tuple[int, ...]]:
    require(b"1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n" in cmap, "ToUnicode codespace is not exact")
    count_match = re.search(rb"\n([0-9]+) beginbfchar\n", cmap)
    require(count_match is not None, "ToUnicode has no bfchar block")
    block_start = count_match.end()
    block_end = cmap.find(b"endbfchar\n", block_start)
    require(block_end >= 0, "ToUnicode bfchar block does not end")
    rows = re.findall(rb"^<([0-9A-F]{4})> <([0-9A-F]{4}(?:[0-9A-F]{4})*)>$", cmap[block_start:block_end], re.MULTILINE)
    require(len(rows) == int(count_match.group(1)), "ToUnicode bfchar count differs from its rows")
    mappings: dict[int, tuple[int, ...]] = {}
    for encoded_cid, encoded_unicode in rows:
        cid = int(encoded_cid, 16)
        require(cid not in mappings, f"ToUnicode repeats CID {cid}")
        units = [int(encoded_unicode[index : index + 4], 16) for index in range(0, len(encoded_unicode), 4)]
        scalars: list[int] = []
        index = 0
        while index < len(units):
            unit = units[index]
            if 0xD800 <= unit <= 0xDBFF:
                require(index + 1 < len(units), "ToUnicode ends with a high surrogate")
                low = units[index + 1]
                require(0xDC00 <= low <= 0xDFFF, "ToUnicode high surrogate has no low surrogate")
                scalars.append(0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00)
                index += 2
            else:
                require(not 0xDC00 <= unit <= 0xDFFF, "ToUnicode contains an unpaired low surrogate")
                scalars.append(unit)
                index += 1
        mappings[cid] = tuple(scalars)
    return mappings


def validate_gate3_text_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)

    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    resources = re.search(rb"/Resources << /Font << /F1_0 ([1-9][0-9]*) 0 R >> >>", page_body)
    require(resources is not None, "page does not have the exact one-font resource closure")
    type0 = int(resources.group(1))
    type0_body = bodies[type0]
    require(b"/Subtype /Type0" in type0_body, "page font is not Type 0")
    require(b"/Encoding /Identity-H" in type0_body, "Type 0 font does not use Identity-H")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "Type 0 font must have exactly one descendant")
    cid_font = descendants[0]
    to_unicode = dictionary_ref(type0_body, b"ToUnicode")

    cid_body = bodies[cid_font]
    require(b"/Subtype /CIDFontType2" in cid_body, "descendant font is not CIDFontType2")
    require(b"/DW 1000" in cid_body, "CID font default width is not exact")
    require(
        b"/W [0 [656 730 722 590 639 562 583 583 370 0 281]]" in cid_body,
        "CID widths are not the independently expected sequence",
    )
    cid_map = dictionary_ref(cid_body, b"CIDToGIDMap")
    descriptor = dictionary_ref(cid_body, b"FontDescriptor")

    descriptor_body = bodies[descriptor]
    require(b"/Type /FontDescriptor" in descriptor_body, "font descriptor has wrong type")
    require(b"/CapHeight 728" in descriptor_body, "font descriptor does not use the validated OS/2 CapHeight")
    font_file = dictionary_ref(descriptor_body, b"FontFile2")
    base_names = re.findall(rb"/(?:BaseFont|FontName) /([A-Z]{6}\+RocPdfSans-Regular)", type0_body + cid_body + descriptor_body)
    require(len(base_names) == 3 and len(set(base_names)) == 1, "subset font names are not one exact identity")

    cid_dictionary, cid_bytes = decoded_stream(bodies, cid_map)
    require(b"/Filter " not in cid_dictionary, "CIDToGIDMap unexpectedly uses a filter")
    require(cid_bytes == b"".join(value.to_bytes(2, "big") for value in range(11)), "CIDToGIDMap is not identity for CIDs 0 through 10")

    _, cmap = decoded_stream(bodies, to_unicode)
    require(cmap_mappings(cmap) == EXPECTED_MAPPINGS, "ToUnicode mappings differ from source Unicode")
    shown_cids = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", EXPECTED_CONTENT)]
    require(all(cid in EXPECTED_MAPPINGS for cid in shown_cids), "content contains a CID without extraction mapping")
    extracted = "".join(chr(scalar) for cid in shown_cids for scalar in EXPECTED_MAPPINGS[cid]).encode() + b"\n"
    require(extracted == EXPECTED_TEXT, "direct CID/ToUnicode reconstruction differs from expected text")

    font_dictionary, font_bytes = decoded_stream(bodies, font_file)
    require(b"/Length1 6776" in font_dictionary, "embedded font Length1 is not exact")
    require(font_bytes.startswith(b"\x00\x01\x00\x00"), "embedded FontFile2 is not TrueType-flavoured sfnt")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "embedded sanitized subset digest differs")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate3-extract-") as temporary_name:
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
    print("PASS Gate 3 PDFBox 3.0.8 extraction: exact UTF-8 Café PDF")


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "negative twin must preserve byte length")
    require(value.count(old) == 1, f"negative twin source occurs {value.count(old)} times")
    return value.replace(old, new, 1)


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_gate3_text_pdf(pdf)
    mutations = (
        replace_once(pdf, b"<0007> <00E9>", b"<0007> <00E8>"),
        replace_once(pdf, b"/F1_0 14 0 R", b"/F1_0 13 0 R"),
        replace_once(pdf, b"/CIDToGIDMap 8 0 R", b"/CIDToGIDMap 9 0 R"),
        replace_once(pdf, b"/Length1 6776", b"/Length1 6775"),
        replace_once(pdf, b"/CapHeight 728", b"/CapHeight 729"),
    )
    for index, mutation in enumerate(mutations):
        try:
            validate_gate3_text_pdf(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"Gate 3 text checker accepted negative twin {index}")
    print("PASS Gate 3 text structure and mapping checker self-test")


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
    validate_gate3_text_pdf(pdf.read_bytes())
    print(f"PASS Gate 3 visible text structure, font, CID, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
