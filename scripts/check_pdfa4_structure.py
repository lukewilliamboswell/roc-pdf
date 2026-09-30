#!/usr/bin/env python3
"""Independent structural inspection of static PDF/A-4 (Archive) output.

This checker re-derives the package's static PDF/A-4 facts from the emitted
bytes alone, without sharing code with the Roc validator:

- the PDF 2.0 file skeleton: header, binary marker, EOF, cross-reference
  stream, page tree, stream lengths, a file identifier, and no /Info or
  /Encrypt trailer entry;
- the catalog's unfiltered /Type /Metadata /Subtype /XML stream, which must be
  well-formed XML declaring exactly `pdfaid:part` 4 and `pdfaid:rev` 2020 (and
  no `pdfaid:conformance`), with namespaces in canonical URI order and the
  Dublin Core title and language present;
- exactly one GTS_PDFA1 output intent whose DestOutputProfile is the vendored
  sRGB2014 profile (an ICC v2-v4 `mntr`/`prtr` profile) and no
  DestOutputProfileRef;
- every annotation is a printable, visible Link whose optional appearance is a
  single /N stream, and every action is URI or GoTo without /Next;
- every font is an embedded Type 0 / CIDFontType2 font with FontFile2 and a
  CIDToGIDMap, only FlateDecode/DCTDecode filters appear, image bit depths are
  permitted, and no package-excluded key occurs anywhere.

Standard output is checked in the opposite direction: it must never declare
PDF/A identification (``validate_standard_pdf``).
"""
from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

from check_pdf_structure import (
    ValidationError,
    dictionary_ref,
    indirect_length,
    object_slices,
    require,
    stream_parts,
    validate_page_tree,
    validate_stream_lengths,
    validate_xref,
)

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "tests" / "archive"
SRGB_PROFILE = ROOT / "package" / "sRGB2014.icc"

SNAPSHOTS: tuple[tuple[str, int], ...] = (
    ("archive_blank.pdf", 1),
    ("archive_report.pdf", 4),
    ("archive_report_400.pdf", 29),
    ("archive_figures.pdf", 1),
    ("archive_navigation.pdf", 1),
    ("archive_navigation_64.pdf", 3),
    ("archive_caller.pdf", 1),
    ("archive_facade_negative.pdf", 1),
)

PDFAID_NAMESPACE = "http://www.aiim.org/pdfa/ns/id/"
DC_NAMESPACE = "http://purl.org/dc/elements/1.1/"
XMP_NAMESPACE = "http://ns.adobe.com/xap/1.0/"
PDFAID_BLOCK = b"\t\t\t<pdfaid:part>4</pdfaid:part>\n\t\t\t<pdfaid:rev>2020</pdfaid:rev>\n"

# Keys the package's static profile excludes anywhere in the file. The
# trailing delimiter class keeps /AF from matching /AFRelationship-like names.
FORBIDDEN_KEYS = (
    b"Encrypt", b"JS", b"JavaScript", b"AA", b"OCProperties", b"OC", b"AcroForm", b"XFA",
    b"NeedAppearances", b"NeedsRendering", b"EmbeddedFiles", b"AF", b"Alternates", b"OPI",
    b"TR", b"TR2", b"HT", b"HTO", b"Requirements", b"PresSteps", b"AlternatePresentations",
    b"Perms", b"PieceInfo", b"FFilter", b"FDecodeParms", b"DestOutputProfileRef", b"Ref",
)
FORBIDDEN_FILTERS = (b"LZWDecode", b"JPXDecode", b"JBIG2Decode", b"Crypt", b"RunLengthDecode", b"CCITTFaxDecode", b"ASCIIHexDecode", b"ASCII85Decode")
ACTION_TYPES = (
    b"GoTo", b"GoToR", b"GoToE", b"GoToDp", b"Launch", b"Thread", b"URI", b"Sound", b"Movie", b"Hide",
    b"Named", b"SubmitForm", b"ResetForm", b"ImportData", b"JavaScript", b"SetOCGState", b"Rendition",
    b"Trans", b"GoTo3DView", b"RichMediaExecute", b"NOP", b"SetState",
)
DELIMITER = rb"(?=[\s/<>\[\]()])"


def key_pattern(name: bytes) -> re.Pattern[bytes]:
    return re.compile(rb"/" + re.escape(name) + DELIMITER)


# A forbidden name is a key, never a structure type: `/S /TR` names the
# table-row role, not the graphics-state transfer function `/TR`.
FORBIDDEN_PATTERNS = tuple((name, re.compile(rb"(?<!/S )/" + re.escape(name) + DELIMITER)) for name in FORBIDDEN_KEYS)


def dictionary_part(body: bytes) -> bytes:
    marker = body.find(b"stream\n")
    return body if marker < 0 else body[:marker]


def skeleton(pdf: bytes, pages: int) -> tuple[dict[int, int], dict[int, bytes], int, int]:
    require(pdf.startswith(b"%PDF-2.0\n%\xe2\xe3\xcf\xd3\n"), "missing PDF 2.0 header or binary marker")
    require(pdf.endswith(b"%%EOF\n"), "missing canonical EOF marker or trailing bytes")
    start = re.search(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    require(start is not None, "missing canonical startxref")
    xref_offset = int(start.group(1))
    offsets, bodies = object_slices(pdf)
    require(xref_offset in offsets.values(), "startxref is not an object boundary")
    xref_object = next(number for number, offset in offsets.items() if offset == xref_offset)
    root, _identifier = validate_xref(pdf, offsets, bodies, xref_object, xref_offset)
    xref_dictionary = dictionary_part(bodies[xref_object])
    require(re.search(rb"/ID \[<[0-9A-F]{64}> <[0-9A-F]{64}>\]", xref_dictionary) is not None, "missing file identifier")
    require(b"/Info" not in xref_dictionary, "trailer must not reference a document information dictionary")
    require(b"/Encrypt" not in xref_dictionary, "trailer must not reference encryption")
    if pages > 0:
        validate_page_tree(bodies, dictionary_ref(bodies[root], b"Pages"), pages)
    validate_stream_lengths(bodies, xref_object, set(), b"")
    return offsets, bodies, root, xref_object


def stream_payload(bodies: dict[int, bytes], number: int) -> tuple[bytes, bytes]:
    body = bodies.get(number)
    require(body is not None, f"object {number} does not resolve")
    marker = body.find(b"stream\n")
    require(marker >= 0, f"object {number} is not a stream")
    dictionary = body[:marker]
    length = indirect_length(bodies, dictionary_ref(dictionary, b"Length"))
    _, payload = stream_parts(body, length)
    return dictionary, payload


def check_metadata(bodies: dict[int, bytes], catalog: bytes) -> bytes:
    dictionary, packet = stream_payload(bodies, dictionary_ref(catalog, b"Metadata"))
    require(b"/Type /Metadata" in dictionary and b"/Subtype /XML" in dictionary, "metadata stream is not /Type /Metadata /Subtype /XML")
    require(b"/Filter" not in dictionary, "metadata stream must stay unfiltered")
    require(packet.startswith(b"<?xpacket begin=\"\xef\xbb\xbf\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>"), "XMP packet header is not the canonical UTF-8 frame")
    require(b" bytes=" not in packet[:120] and b" encoding=" not in packet[:120], "XMP packet header must not use bytes or encoding attributes")
    require(packet.endswith(b"<?xpacket end=\"w\"?>"), "XMP packet trailer is not canonical")
    try:
        document = ElementTree.fromstring(packet.split(b"?>", 1)[1].rsplit(b"<?xpacket", 1)[0])
    except ElementTree.ParseError as error:
        raise ValidationError(f"XMP packet is not well-formed XML: {error}") from error
    part = document.findall(f".//{{{PDFAID_NAMESPACE}}}part")
    revision = document.findall(f".//{{{PDFAID_NAMESPACE}}}rev")
    require([item.text for item in part] == ["4"], "XMP must declare exactly pdfaid:part 4")
    require([item.text for item in revision] == ["2020"], "XMP must declare exactly pdfaid:rev 2020")
    require(not document.findall(f".//{{{PDFAID_NAMESPACE}}}conformance"), "static PDF/A-4 must not declare pdfaid:conformance")
    require(document.find(f".//{{{DC_NAMESPACE}}}title") is not None, "XMP has no dc:title")
    require(document.find(f".//{{{DC_NAMESPACE}}}language") is not None, "XMP has no dc:language")
    require(packet.count(PDFAID_BLOCK) == 1, "pdfaid properties are not in canonical form")
    positions = [packet.find(f'"{uri}"'.encode()) for uri in (XMP_NAMESPACE, DC_NAMESPACE, PDFAID_NAMESPACE)]
    present = [position for position in positions if position >= 0]
    require(positions[1] >= 0 and positions[2] >= 0 and present == sorted(present), "XMP namespaces are not in canonical URI order")
    require(packet.find(b"</dc:title>") < packet.find(b"<pdfaid:part>"), "pdfaid properties must follow the Dublin Core properties")
    return packet


def check_output_intent(bodies: dict[int, bytes], catalog: bytes) -> None:
    intents = re.findall(rb"/OutputIntents \[(<<.*?>>)\]", catalog, re.S)
    require(len(intents) == 1, "catalog must carry exactly one /OutputIntents array")
    require(intents[0].count(b"/Type /OutputIntent") == 1, "exactly one output intent is required")
    require(b"/S /GTS_PDFA1" in intents[0], "output intent is not GTS_PDFA1")
    require(b"/DestOutputProfileRef" not in intents[0], "output intent must embed its profile")
    _dictionary, profile = stream_payload(bodies, dictionary_ref(intents[0], b"DestOutputProfile"))
    require(profile == SRGB_PROFILE.read_bytes(), "output intent profile is not the vendored sRGB2014 asset")
    require(2 <= profile[8] <= 4 and profile[12:16] in (b"mntr", b"prtr"), "output intent profile is not an ICC v2-v4 monitor or output profile")


def check_annotations_and_actions(bodies: dict[int, bytes]) -> int:
    annotations = 0
    for number, body in bodies.items():
        dictionary = dictionary_part(body)
        if re.search(rb"/Type /Annot" + DELIMITER, dictionary) is not None:
            annotations += 1
            require(b"/Subtype /Link" in dictionary, f"object {number}: only Link annotations are permitted")
            flags = re.search(rb"/F ([0-9]+)" + DELIMITER, dictionary)
            require(flags is not None, f"object {number}: annotation has no /F flags")
            value = int(flags.group(1))
            require(value & 4 == 4 and value & (1 | 2 | 32 | 256) == 0, f"object {number}: annotation is not printable and visible")
            appearance = re.search(rb"/AP <<(.*?)>>", dictionary, re.S)
            if appearance is not None:
                require(re.fullmatch(rb" /N [0-9]+ 0 R ", appearance.group(1)) is not None, f"object {number}: appearance must be a single /N stream")
        for action in re.finditer(rb"/S /([A-Za-z0-9]+)" + DELIMITER, dictionary):
            name = action.group(1)
            if name in ACTION_TYPES:
                require(name in (b"URI", b"GoTo"), f"object {number}: action /{name.decode()} is not permitted")
                require(key_pattern(b"Next").search(dictionary) is None or b"/Type /Action" not in dictionary, f"object {number}: chained actions are not permitted")
    return annotations


def check_resources(bodies: dict[int, bytes]) -> None:
    for number, body in bodies.items():
        dictionary = dictionary_part(body)
        for name, pattern in FORBIDDEN_PATTERNS:
            require(pattern.search(dictionary) is None, f"object {number}: package-excluded key /{name.decode()}")
        for name in FORBIDDEN_FILTERS:
            require(key_pattern(name).search(dictionary) is None, f"object {number}: filter /{name.decode()} is not permitted")
        require(b"/Interpolate true" not in dictionary, f"object {number}: image interpolation is not permitted")
        for bits in re.finditer(rb"/BitsPerComponent ([0-9]+)", dictionary):
            require(int(bits.group(1)) in (1, 2, 4, 8, 16), f"object {number}: unsupported BitsPerComponent")
        for blend in re.finditer(rb"/BM /([A-Za-z]+)", dictionary):
            require(blend.group(1) == b"Normal", f"object {number}: only the Normal blend mode is permitted")
        if re.search(rb"/Type /Font" + DELIMITER, dictionary) is not None:
            subtype = re.search(rb"/Subtype /([A-Za-z0-9]+)", dictionary)
            require(subtype is not None and subtype.group(1) in (b"Type0", b"CIDFontType2"), f"object {number}: only Type 0 / CIDFontType2 fonts are permitted")
            if subtype.group(1) == b"CIDFontType2":
                require(b"/CIDToGIDMap" in dictionary, f"object {number}: CIDFontType2 has no CIDToGIDMap")
        if b"/Type /FontDescriptor" in dictionary:
            require(b"/FontFile2 " in dictionary and b"/FontFile " not in dictionary and b"/FontFile3" not in dictionary, f"object {number}: font program is not embedded as FontFile2")


def replace_first(pdf: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "self-test mutations must preserve length")
    require(old in pdf, f"self-test mutation target {old!r} is absent")
    return pdf.replace(old, new, 1)


def validate_archive_pdf(pdf: bytes, pages: int = 0) -> dict[str, int]:
    _offsets, bodies, root, _xref = skeleton(pdf, pages)
    catalog = dictionary_part(bodies[root])
    require(b"/Type /Catalog" in catalog, "root is not the catalog")
    version = re.search(rb"/Version /([^\s/>]+)", catalog)
    require(version is None or version.group(1).startswith(b"2."), "catalog version is not a PDF 2.x version")
    packet = check_metadata(bodies, catalog)
    check_output_intent(bodies, catalog)
    annotations = check_annotations_and_actions(bodies)
    check_resources(bodies)
    return {"annotations": annotations, "packet_bytes": len(packet)}


def validate_standard_pdf(pdf: bytes) -> None:
    require(b"pdfaid" not in pdf, "Standard output must never declare PDF/A identification")


def validate_pdfa4_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    validate_archive_pdf(pdf, dimensions.get("pages", 0))


def validate_standard_twin_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    """A Standard twin keeps the PDF 2.0 skeleton and never declares PDF/A."""
    skeleton(pdf, dimensions.get("pages", 0))
    validate_standard_pdf(pdf)


def self_test() -> None:
    for name, pages in SNAPSHOTS:
        validate_archive_pdf((ARCHIVE / name).read_bytes(), pages)
    validate_standard_pdf((ROOT / "tests" / "metadata" / "metadata.pdf").read_bytes())
    for name in ("archive_figures_standard.pdf", "archive_navigation_standard.pdf"):
        validate_standard_twin_pdf((ARCHIVE / name).read_bytes(), {"pages": 1})

    navigation = (ARCHIVE / "archive_navigation.pdf").read_bytes()
    report = (ARCHIVE / "archive_report.pdf").read_bytes()
    # Every mutation preserves byte length, so offsets and the cross-reference
    # stream stay valid and each rejection is attributable to the mutated fact.
    mutations = [
        ("wrong pdfaid part", replace_first(report, b"<pdfaid:part>4<", b"<pdfaid:part>3<")),
        ("wrong pdfaid revision", replace_first(report, b"<pdfaid:rev>2020<", b"<pdfaid:rev>2019<")),
        ("altered intent subtype", replace_first(report, b"/S /GTS_PDFA1", b"/S /GTS_PDFX1")),
        ("filtered metadata", replace_first(report, b"/Subtype /XML /Type /Metadata", b"/Filterx /XML /Type /Metadata")),
        ("hidden link", replace_first(navigation, b"/F 4 ", b"/F 6 ")),
        ("forbidden action", replace_first(navigation, b"/S /URI ", b"/S /NOP ")),
        ("excluded key", replace_first(report, b"/Lang ", b"/Ref  ")),
        ("simple font", replace_first(report, b"/Subtype /Type0", b"/Subtype /Type1")),
    ]
    for label, mutation in mutations:
        try:
            validate_archive_pdf(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"PDF/A-4 structure checker accepted {label}")
    try:
        validate_standard_pdf(report)
    except ValidationError:
        pass
    else:
        raise SystemExit("PDF/A-4 structure checker accepted identification in Standard output")
    print(
        f"PASS check_pdfa4_structure self-test: {len(SNAPSHOTS)} Archive snapshots, "
        f"Standard non-declaration, and {len(mutations) + 1} mutation twins"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdfs", nargs="*", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if not arguments.pdfs:
        parser.error("provide PDF paths or --self-test")
    for path in arguments.pdfs:
        facts = validate_archive_pdf(path.read_bytes())
        print(f"PASS {path} ({facts['annotations']} annotations, {facts['packet_bytes']}-byte packet)")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
