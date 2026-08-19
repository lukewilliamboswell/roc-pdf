#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

from check_text import (
    EXPECTED_CONTENT,
    EXPECTED_MAPPINGS,
    EXPECTED_TEXT,
    check_pdfbox_extraction,
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
SNAPSHOT = ROOT / "tests" / "caller_font" / "caller_text.pdf"
EXPECTED_SUBSET_SHA256 = "84b3e23ae31319dd455662c6f324c4e18c42ba7c3d9f77ea69ab10788a707ea3"
EXPECTED_NAMES = {
    1: "GJLQPJ+Caller Fixture Sans",
    4: "GJLQPJ+Caller Fixture Sans Regular",
    6: "GJLQPJ+CallerFixtureSans-Regular",
}


def subset_names(font: bytes) -> dict[int, str]:
    require(font[:4] == b"\x00\x01\x00\x00" and len(font) >= 12, "embedded caller subset is not TrueType")
    table_count = int.from_bytes(font[4:6], "big")
    require(12 + table_count * 16 <= len(font), "embedded caller subset directory is truncated")
    name_table: bytes | None = None
    for index in range(table_count):
        record = 12 + index * 16
        if font[record : record + 4] != b"name":
            continue
        offset = int.from_bytes(font[record + 8 : record + 12], "big")
        length = int.from_bytes(font[record + 12 : record + 16], "big")
        require(offset <= len(font) and length <= len(font) - offset, "caller subset name table escapes the font")
        name_table = font[offset : offset + length]
    require(name_table is not None and len(name_table) >= 6, "caller subset has no complete name table")
    count = int.from_bytes(name_table[2:4], "big")
    string_offset = int.from_bytes(name_table[4:6], "big")
    require(6 + count * 12 <= string_offset <= len(name_table), "caller subset name records are invalid")
    names: dict[int, str] = {}
    for index in range(count):
        record = 6 + index * 12
        platform = int.from_bytes(name_table[record : record + 2], "big")
        encoding = int.from_bytes(name_table[record + 2 : record + 4], "big")
        language = int.from_bytes(name_table[record + 4 : record + 6], "big")
        name_id = int.from_bytes(name_table[record + 6 : record + 8], "big")
        length = int.from_bytes(name_table[record + 8 : record + 10], "big")
        offset = int.from_bytes(name_table[record + 10 : record + 12], "big")
        require(offset <= len(name_table) - string_offset and length <= len(name_table) - string_offset - offset, "caller subset name string escapes the table")
        if platform == 3 and encoding == 1 and language == 0x0409 and name_id in EXPECTED_NAMES:
            require(name_id not in names, f"caller subset repeats name ID {name_id}")
            try:
                names[name_id] = name_table[string_offset + offset : string_offset + offset + length].decode("utf-16-be")
            except UnicodeDecodeError as error:
                raise ValidationError(f"caller subset name ID {name_id} is not valid UTF-16BE") from error
    return names


def validate_caller_text_pdf(pdf: bytes) -> None:
    validate_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)

    catalog = only_object(bodies, b"/Type /Catalog ", "catalog")
    catalog_body = bodies[catalog]
    require(b"/MarkInfo << /Marked true >>" in catalog_body, "caller catalog does not declare marked content")
    structure_root = dictionary_ref(catalog_body, b"StructTreeRoot")
    require(b"/Type /StructTreeRoot" in bodies[structure_root], "caller catalog structure root has the wrong type")

    page = only_object(bodies, b"/Type /Page ", "page")
    page_body = bodies[page]
    require(b"/StructParents 0" in page_body, "caller page does not have the planned ParentTree key")
    require(b"/Tabs /S" in page_body, "caller page tab order is not structure order")
    resources = re.search(
        rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /Font << /F1_0 ([1-9][0-9]*) 0 R >> /XObject << >> >>",
        page_body,
    )
    require(resources is not None, "caller page does not have the exact color/font resource closure")
    color_space = int(resources.group(1))
    require(b"/CalGray" in bodies[color_space], "caller text color resource is not calibrated Gray")
    type0_body = bodies[int(resources.group(2))]
    require(b"/Subtype /Type0" in type0_body and b"/Encoding /Identity-H" in type0_body, "caller page font is not Identity-H Type 0")
    descendants = dictionary_ref_array(type0_body, b"DescendantFonts")
    require(len(descendants) == 1, "caller Type 0 font does not have one descendant")
    cid_body = bodies[descendants[0]]
    require(b"/Subtype /CIDFontType2" in cid_body, "caller descendant is not CIDFontType2")
    require(b"/W [0 [656 730 722 590 639 562 583 583 370 0 281]]" in cid_body, "caller widths differ from the validated face")

    descriptor_body = bodies[dictionary_ref(cid_body, b"FontDescriptor")]
    require(b"/CapHeight 728" in descriptor_body, "caller descriptor does not use the validated OS/2 CapHeight")
    base_names = re.findall(rb"/(?:BaseFont|FontName) /([A-Z]{6}\+CallerFixtureSans-Regular)", type0_body + cid_body + descriptor_body)
    require(len(base_names) == 3 and len(set(base_names)) == 1, "caller PDF font dictionaries do not share one exact identity")

    _, cid_bytes = decoded_stream(bodies, dictionary_ref(cid_body, b"CIDToGIDMap"))
    require(cid_bytes == b"".join(value.to_bytes(2, "big") for value in range(11)), "caller CIDToGIDMap is not the exact identity map")
    _, cmap = decoded_stream(bodies, dictionary_ref(type0_body, b"ToUnicode"))
    require(cmap_mappings(cmap) == EXPECTED_MAPPINGS, "caller ToUnicode mappings differ from source Unicode")
    shown_cids = [int(value, 16) for value in re.findall(rb"<([0-9A-F]{4})> Tj", EXPECTED_CONTENT)]
    extracted = "".join(chr(scalar) for cid in shown_cids for scalar in EXPECTED_MAPPINGS[cid]).encode() + b"\n"
    require(extracted == EXPECTED_TEXT, "caller direct CID reconstruction differs from expected text")

    font_dictionary, font_bytes = decoded_stream(bodies, dictionary_ref(descriptor_body, b"FontFile2"))
    require(b"/Length1 6820" in font_dictionary, "caller embedded font Length1 is not exact")
    require(hashlib.sha256(font_bytes).hexdigest() == EXPECTED_SUBSET_SHA256, "caller sanitized subset digest differs")
    require(subset_names(font_bytes) == EXPECTED_NAMES, "caller subset name table does not preserve the validated source identity")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_caller_text_pdf(pdf)
    mutations = (
        replace_once(pdf, b"/CapHeight 728", b"/CapHeight 729"),
        replace_once(pdf, b"<0007> <00E9>", b"<0007> <00E8>"),
        replace_once(pdf, b"/FontName /GJLQPJ+CallerFixtureSans-Regular", b"/FontName /GJLQPJ+CallerFixtureSans-Regulbr"),
    )
    for index, mutation in enumerate(mutations):
        try:
            validate_caller_text_pdf(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"text-layout caller text checker accepted negative twin {index}")
    print("PASS text-layout caller-font text structure, identity, and mapping checker self-test")


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
    validate_caller_text_pdf(pdf.read_bytes())
    print(f"PASS text-layout caller-font structure, identity, CID, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)


if __name__ == "__main__":
    main()
