#!/usr/bin/env python3
"""production-visual metadata, document-language, and output-intent structural checker.

Independently of the Roc implementation, this proves from the emitted bytes
that:

- the catalog carries `/Lang`, `/Metadata`, and `/OutputIntents` entries in
  canonical sorted key order;
- `/Lang` is the canonical BOM-prefixed UTF-16BE text string of the fixture's
  validated language and agrees with the XMP `dc:language` bag entry;
- the metadata stream is `/Type /Metadata /Subtype /XML`, carries no filter,
  and its payload is byte-identical to the canonical XMP packet recomputed
  here from the fixture's typed facts (framing, byte-order mark, namespace
  and property order, escaping, and timestamp omission rules included);
- the catalog's single output intent is a direct `/GTS_PDFA1` dictionary
  whose `/OutputConditionIdentifier` is `sRGB2014`, whose `/RegistryName` is
  `http://www.color.org`, and whose `/DestOutputProfile` references an ICC
  stream;
- that ICC stream declares `/N 3`, carries no filter, and is byte-identical
  to the vendored `vendor/icc/sRGB2014.icc` asset;
- exactly one such profile stream exists in the file even when many ICCBased
  color spaces and the output intent share it, and every `/ICCBased` array
  references exactly that object;
- no external color dependency (`/DestOutputProfileRef`) appears anywhere.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from check_pdf_structure import (
    ValidationError,
    dictionary_int,
    dictionary_ref,
    object_slices,
    indirect_length,
    require,
    stream_parts,
    validate_page_tree,
    validate_stream_lengths,
    validate_xref,
)
from check_forms import replace_once
import re as _re

ROOT = Path(__file__).resolve().parents[1]
SRGB_PROFILE = ROOT / "vendor" / "icc" / "sRGB2014.icc"

SHOWCASE_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata.pdf"
MINIMAL_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_minimal.pdf"
UNIQUE_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_unique.pdf"
RETAINED_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_retained.pdf"
SHARE_16_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_share_16.pdf"
SHARE_64_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_share_64.pdf"
TITLE_64_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_title_64.pdf"
TITLE_256_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_title_256.pdf"
NEGATIVE_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_negative.pdf"
FACADE_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_facade.pdf"
FACADE_NEGATIVE_SNAPSHOT = ROOT / "tests" / "metadata" / "metadata_facade_negative.pdf"

SHOWCASE_TITLE = "Café Metadata & <Intent> — 概要"
FACADE_TITLE = "Café Metadata & <Report> — 概要"
SHOWCASE_CREATED = "2026-01-02T03:04:05Z"
SHOWCASE_MODIFIED = "2026-08-18T09:30:00Z"

OUTPUT_INTENT = re.compile(
    rb"/OutputIntents \[<< /DestOutputProfile ([0-9]+) 0 R"
    rb" /OutputConditionIdentifier <([0-9A-F]+)>"
    rb" /RegistryName <([0-9A-F]+)>"
    rb" /S /GTS_PDFA1 /Type /OutputIntent >>\]"
)
ICC_BASED = re.compile(rb"\[/ICCBased ([0-9]+) 0 R\]")


def escape_xml(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def canonical_xmp(
    title: str,
    language: str,
    created: str | None = None,
    modified: str | None = None,
) -> bytes:
    """The canonical XMP policy, reimplemented independently of KernelXmp."""
    parts = ['<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n']
    parts.append('<x:xmpmeta xmlns:x="adobe:ns:meta/">\n')
    parts.append('\t<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n')
    parts.append('\t\t<rdf:Description rdf:about=""')
    if created is not None or modified is not None:
        parts.append(' xmlns:xmp="http://ns.adobe.com/xap/1.0/"')
    parts.append(' xmlns:dc="http://purl.org/dc/elements/1.1/">\n')
    if created is not None:
        parts.append(f"\t\t\t<xmp:CreateDate>{created}</xmp:CreateDate>\n")
    if modified is not None:
        parts.append(f"\t\t\t<xmp:ModifyDate>{modified}</xmp:ModifyDate>\n")
    parts.append("\t\t\t<dc:language>\n\t\t\t\t<rdf:Bag>\n")
    parts.append(f"\t\t\t\t\t<rdf:li>{language}</rdf:li>\n")
    parts.append("\t\t\t\t</rdf:Bag>\n\t\t\t</dc:language>\n")
    parts.append("\t\t\t<dc:title>\n\t\t\t\t<rdf:Alt>\n")
    parts.append(f'\t\t\t\t\t<rdf:li xml:lang="x-default">{escape_xml(title)}</rdf:li>\n')
    parts.append("\t\t\t\t</rdf:Alt>\n\t\t\t</dc:title>\n")
    parts.append("\t\t</rdf:Description>\n\t</rdf:RDF>\n</x:xmpmeta>\n")
    parts.append('<?xpacket end="w"?>')
    return "".join(parts).encode("utf-8")


def utf16_hex(text: str) -> bytes:
    return (b"\xfe\xff" + text.encode("utf-16-be")).hex().upper().encode("ascii")


def check_metadata(
    pdf: bytes,
    title: str,
    language: str,
    created: str | None,
    modified: str | None,
    expected_pages: int,
    icc_based_spaces: int,
) -> None:
    # File skeleton: header, EOF, xref integrity, page tree, and stream
    # lengths; content-stream bytes are covered by the exact snapshot and the
    # per-slice checks below rather than the blank-content expectation.
    require(pdf.startswith(b"%PDF-2.0\n%\xe2\xe3\xcf\xd3\n"), "missing PDF 2.0 header or binary marker")
    require(pdf.endswith(b"%%EOF\n"), "missing canonical EOF marker or trailing bytes")
    start_match = _re.search(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    require(start_match is not None, "missing canonical startxref")
    xref_offset = int(start_match.group(1))
    offsets, bodies = object_slices(pdf)
    require(xref_offset in offsets.values(), "startxref is not an object boundary")
    xref_object = next(number for number, offset in offsets.items() if offset == xref_offset)
    root, _file_identifier = validate_xref(pdf, offsets, bodies, xref_object, xref_offset)
    validate_page_tree(bodies, dictionary_ref(bodies[root], b"Pages"), expected_pages)
    validate_stream_lengths(bodies, xref_object, set(), b"")
    require(b"/DestOutputProfileRef" not in pdf, "forbidden external profile reference")
    catalogs = [number for number, body in bodies.items() if b"/Type /Catalog" in body]
    require(len(catalogs) == 1, "expected exactly one catalog")
    catalog = bodies[catalogs[0]]

    # /Lang: the canonical BOM-prefixed UTF-16BE text string.
    lang = re.search(rb"/Lang <([0-9A-F]+)>", catalog)
    require(lang is not None, "catalog has no /Lang text string")
    require(lang.group(1) == utf16_hex(language), "catalog /Lang is not the validated language")

    # Sorted catalog key order is part of the canonical serialization.
    key_positions = [catalog.find(b"/" + key) for key in (b"Lang", b"MarkInfo", b"Metadata", b"OutputIntents", b"Pages")]
    if b"/MarkInfo" not in catalog:
        key_positions = [position for position in key_positions if position >= 0]
    require(all(position >= 0 for position in key_positions), "catalog is missing a metadata slice entry")
    require(key_positions == sorted(key_positions), "catalog keys are not in canonical sorted order")

    # The metadata stream: correct type facts, no filter, canonical payload.
    metadata_object = dictionary_ref(catalog, b"Metadata")
    metadata_body = bodies.get(metadata_object)
    require(metadata_body is not None, "catalog /Metadata reference does not resolve")
    marker = metadata_body.find(b"stream\n")
    require(marker >= 0, "metadata object is not a stream")
    metadata_dictionary = metadata_body[:marker]
    require(b"/Subtype /XML" in metadata_dictionary, "metadata stream is not /Subtype /XML")
    require(b"/Type /Metadata" in metadata_dictionary, "metadata stream is not /Type /Metadata")
    require(b"/Filter" not in metadata_dictionary, "metadata stream must stay unfiltered")
    length = indirect_length(bodies, dictionary_ref(metadata_dictionary, b"Length"))
    _, packet = stream_parts(metadata_body, length)
    expected_packet = canonical_xmp(title, language, created, modified)
    require(packet == expected_packet, "metadata stream is not the canonical XMP packet")

    # The XMP language bag must agree with the catalog /Lang entry.
    bag = re.search(rb"<rdf:li>([^<]*)</rdf:li>", packet)
    require(bag is not None, "XMP packet has no dc:language item")
    require(bag.group(1).decode("utf-8") == language, "XMP dc:language disagrees with /Lang")

    # The single output intent and its packaged profile stream.
    intent = OUTPUT_INTENT.search(catalog)
    require(intent is not None, "catalog has no canonical /OutputIntents entry")
    require(intent.group(2) == utf16_hex("sRGB2014"), "output intent condition identifier mismatch")
    require(intent.group(3) == utf16_hex("http://www.color.org"), "output intent registry mismatch")
    profile_object = int(intent.group(1))
    profile_body = bodies.get(profile_object)
    require(profile_body is not None, "output intent profile reference does not resolve")
    profile_marker = profile_body.find(b"stream\n")
    require(profile_marker >= 0, "output intent profile is not a stream")
    profile_dictionary = profile_body[:profile_marker]
    require(dictionary_int(profile_dictionary, b"N") == 3, "profile stream does not declare three components")
    require(b"/Filter" not in profile_dictionary, "profile stream must stay unfiltered")
    profile_length = indirect_length(bodies, dictionary_ref(profile_dictionary, b"Length"))
    _, profile_bytes = stream_parts(profile_body, profile_length)
    require(profile_bytes == SRGB_PROFILE.read_bytes(), "profile stream is not the vendored sRGB2014 asset")

    # Exactly one embedded copy of the packaged profile, shared by every
    # consumer: the output intent and each /ICCBased color-space array.
    copies = 0
    for number, body in bodies.items():
        body_marker = body.find(b"stream\n")
        if body_marker < 0 or b"/N 3" not in body[:body_marker]:
            continue
        body_length = indirect_length(bodies, dictionary_ref(body[:body_marker], b"Length"))
        _, payload = stream_parts(body, body_length)
        if payload == profile_bytes:
            copies += 1
    require(copies == 1, f"expected exactly one embedded profile, found {copies}")

    icc_references = {int(match.group(1)) for body in bodies.values() for match in ICC_BASED.finditer(body)}
    require(len(icc_references) == (1 if icc_based_spaces > 0 else 0), "unexpected ICCBased reference set")
    if icc_based_spaces > 0:
        require(icc_references == {profile_object}, "ICCBased spaces do not share the intent profile stream")
    icc_arrays = sum(1 for body in bodies.values() for _ in ICC_BASED.finditer(body))
    require(icc_arrays == icc_based_spaces, f"expected {icc_based_spaces} ICCBased arrays, found {icc_arrays}")


def validate_showcase(pdf: bytes) -> None:
    check_metadata(pdf, SHOWCASE_TITLE, "en-AU", SHOWCASE_CREATED, SHOWCASE_MODIFIED, 1, 1)


def validate_minimal(pdf: bytes) -> None:
    check_metadata(pdf, SHOWCASE_TITLE, "en-AU", None, None, 1, 1)
    offsets, bodies = object_slices(pdf)
    for body in bodies.values():
        require(b"CreateDate" not in body and b"xmlns:xmp" not in body, "omitted timestamps must omit their namespace")


def validate_share(pdf: bytes) -> None:
    check_metadata(pdf, SHOWCASE_TITLE, "en-AU", SHOWCASE_CREATED, SHOWCASE_MODIFIED, 1, 1)


def validate_title(pdf: bytes, segments: int) -> None:
    check_metadata(pdf, "A&" * segments, "en-AU", SHOWCASE_CREATED, SHOWCASE_MODIFIED, 1, 1)


def validate_facade(pdf: bytes, pages: int) -> None:
    check_metadata(pdf, FACADE_TITLE, "en-AU", SHOWCASE_CREATED, SHOWCASE_MODIFIED, pages, 0)


def validate_facade_negative(pdf: bytes) -> None:
    check_metadata(pdf, "Valid", "en-AU", None, None, 1, 0)


def validate_metadata_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    pages = dimensions.get("pages", 1)
    if dimensions.get("metadata_minimal", 0) == 1:
        validate_minimal(pdf)
    elif dimensions.get("metadata_share", 0) == 1:
        validate_share(pdf)
    elif dimensions.get("metadata_title", 0) == 1:
        validate_title(pdf, dimensions["title_segments"])
    elif dimensions.get("metadata_facade", 0) == 1:
        validate_facade(pdf, pages)
    elif dimensions.get("metadata_facade_negative", 0) == 1:
        validate_facade_negative(pdf)
    else:
        # showcase, unique, retained, and the negative sweep's carrier all
        # emit the showcase document.
        validate_showcase(pdf)


def self_test() -> None:
    validate_showcase(SHOWCASE_SNAPSHOT.read_bytes())
    validate_minimal(MINIMAL_SNAPSHOT.read_bytes())
    validate_showcase(UNIQUE_SNAPSHOT.read_bytes())
    validate_showcase(RETAINED_SNAPSHOT.read_bytes())
    validate_share(SHARE_16_SNAPSHOT.read_bytes())
    validate_share(SHARE_64_SNAPSHOT.read_bytes())
    validate_title(TITLE_64_SNAPSHOT.read_bytes(), 64)
    validate_title(TITLE_256_SNAPSHOT.read_bytes(), 256)
    validate_showcase(NEGATIVE_SNAPSHOT.read_bytes())
    validate_facade(FACADE_SNAPSHOT.read_bytes(), 3)
    validate_facade_negative(FACADE_NEGATIVE_SNAPSHOT.read_bytes())

    pdf = SHOWCASE_SNAPSHOT.read_bytes()
    mutations = [
        ("altered XMP packet byte", replace_once(pdf, b"<dc:title>", b"<dc:titlf>")),
        ("altered /Lang value", replace_once(pdf, b"/Lang <FEFF", b"/Lang <FEFE")),
        ("altered intent subtype", replace_once(pdf, b"/S /GTS_PDFA1", b"/S /GTS_PDFB1")),
        ("altered profile component count", replace_once(pdf, b"/N 3", b"/N 4")),
        ("altered metadata subtype", replace_once(pdf, b"/Subtype /XML", b"/Subtype /XNL")),
        ("filtered metadata stream", replace_once(pdf, b"/Subtype /XML /Type /Metadata", b"/Filterx /XML /Type /Metadata")),
    ]
    profile_payload = SRGB_PROFILE.read_bytes()
    corrupt_profile = bytearray(pdf)
    profile_offset = pdf.find(profile_payload)
    require(profile_offset >= 0, "self-test snapshot does not embed the vendored profile")
    corrupt_profile[profile_offset + 100] ^= 0xFF
    mutations.append(("altered ICC payload byte", bytes(corrupt_profile)))

    for label, mutation in mutations:
        try:
            validate_showcase(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"metadata checker accepted {label}")

    print(
        "PASS check_metadata self-test: canonical XMP packets, /Lang "
        "agreement, GTS_PDFA1 output intents, single shared sRGB2014 profile "
        "streams, and seven mutation twins across eleven snapshots"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.pdf is None:
        parser.error("provide a PDF path or --self-test")
    validate_showcase(arguments.pdf.read_bytes())
    print(f"PASS {arguments.pdf}")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
