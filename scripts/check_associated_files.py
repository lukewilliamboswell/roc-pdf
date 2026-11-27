#!/usr/bin/env python3
"""Compare complete document associations against independently authored inputs."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from check_pdf_structure import ValidationError, require
from check_profile_declarations import validate_claims
from check_structure_semantics import Document, Ref, text_string
from pdf_layout import mutate, planned_bodies, serialize_object_streams, trailer_facts

ROOT = Path(__file__).resolve().parents[1]
PDFAID = "http://www.aiim.org/pdfa/ns/id/"
PDFUAID = "http://www.aiim.org/pdfua/ns/id/"
UTF8_BOM = b"\xef\xbb\xbf"


@dataclass(frozen=True)
class File:
    filename: str
    description: str
    relationship: str
    media_type: str
    timestamp: str
    payload: bytes


def fixtures(count: int, volume: int) -> list[File]:
    result = []
    for index in range(count):
        filename = ("statement", "statement.xml", "résumé.csv", "rate%book.csv")[index] if index < 4 else f"part-{index}.csv"
        result.append(File(
            filename, f"Purpose of {filename}", ("Data", "Supplement", "Source", "Alternative")[index % 4],
            "application/xml" if index == 1 else "text/csv", "D:20240229123456Z",
            bytes([32 if index < 2 else (32 + index) % 256]) * volume,
        ))
    return result


def invoice() -> list[File]:
    payload = (ROOT / "examples/invoice-with-data/invoice.xml").read_bytes()
    return [File(
        "invoice.xml", "Supplemental invoice numbers and item totals for importing into accounting software.",
        "Data", "application/xml", "D:20260914000000Z", payload,
    )]


def key(filename: str) -> bytes:
    return UTF8_BOM + filename.encode("utf-8")


def legacy_filename(filename: str) -> str:
    return "".join(chr(byte) if 32 <= byte < 127 and byte != 37 else f"%{byte:02X}" for byte in filename.encode("utf-8"))


def name_bytes(name: str) -> bytes:
    return re.sub(rb"#([A-Fa-f0-9]{2})", lambda m: bytes([int(m[1], 16)]), name.encode("ascii"))


def name_tree(
    document: Document, number: int, wanted: list[bytes], capacity: int, *, root: bool,
) -> list[Ref]:
    branch = document.get(number)
    leaf = capacity == 32
    require(set(branch) == ({"Names" if leaf else "Kids"} | (set() if root else {"Limits"})), "embedded-files node has incorrect shape")
    if not root:
        require(branch["Limits"] == [wanted[0], wanted[-1]], "embedded-files leaf boundaries differ from author keys")
    if leaf:
        items = branch["Names"]
        require(items[::2] == wanted, "embedded-files leaf keys differ from expected encoded order")
        refs = items[1::2]
        require(len(refs) == len(wanted) and all(isinstance(ref, Ref) for ref in refs), "embedded-files leaf must point to indirect file specifications")
        return refs
    children = branch["Kids"]
    child_capacity = capacity // 32
    groups = [
        wanted[index : index + child_capacity]
        for index in range(0, len(wanted), child_capacity)
    ]
    require(len(children) == len(groups) and all(isinstance(ref, Ref) for ref in children), "embedded-files node has incorrect children")
    return [
        ref
        for child, group in zip(children, groups, strict=True)
        for ref in name_tree(document, int(child), group, child_capacity, root=False)
    ]


def validate_associated_files_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    authorship = invoice() if dimensions.get("invoice") else fixtures(dimensions["attachments"], dimensions["file_bytes"])
    validate(pdf, authorship, bool(dimensions.get("accessible")), bool(dimensions.get("wtpdf")), bool(dimensions.get("dests")))


def validate(pdf: bytes, expected: list[File], accessible: bool, wtpdf: bool, dests: bool) -> None:
    document = Document(pdf)
    catalog = document.get(document.root)
    names = catalog["Names"]
    require(set(names) == {"EmbeddedFiles", "Dests"} if dests else set(names) == {"EmbeddedFiles"}, "catalog should use one Names dictionary with all authored trees")
    if dests:
        dest_root = names["Dests"]
        require(isinstance(dest_root, Ref) and document.get(int(dest_root))["Names"][0] == b"start", "existing named navigation was altered by the embedded-files tree")
    ordered = sorted(expected, key=lambda file: key(file.filename))
    embedded = names["EmbeddedFiles"]
    require(isinstance(embedded, Ref), "catalog name dictionary requires an indirect embedded-files root")
    capacity = 32
    while capacity < len(ordered):
        capacity *= 32
    refs = name_tree(document, int(embedded), [key(file.filename) for file in ordered], capacity, root=True)
    associations = catalog["AF"]
    require(all(isinstance(ref, Ref) for ref in associations) and refs == associations and len(set(refs)) == len(refs), "document AF and name-tree file specifications differ")
    streams = set()
    for ref, authored in zip(refs, ordered, strict=True):
        spec = document.get(int(ref))
        require(set(spec) == {"Type", "AFRelationship", "Desc", "F", "UF", "EF"}, "file specification shape changed")
        require(spec["Type"] == "Filespec" and spec["AFRelationship"] == authored.relationship, "authored attachment relationship changed")
        require(text_string(spec["Desc"]) == authored.description, "authored attachment purpose description changed")
        require(text_string(spec["UF"]) == authored.filename, "authored attachment filename changed")
        require(text_string(spec["F"]) == legacy_filename(authored.filename), "legacy attachment filename encoding changed")
        ef = spec["EF"]
        stream = ef["F"]
        require(set(ef) == {"F", "UF"} and isinstance(stream, Ref) and stream == ef["UF"] and stream not in streams, "file specification does not own its own stream")
        streams.add(stream)
        info = document.get(int(stream))
        require(info["Type"] == "EmbeddedFile" and name_bytes(info["Subtype"]) == authored.media_type.encode("ascii"), "stream type or MIME differs from authored input")
        require(info["Params"] == {"ModDate": authored.timestamp.encode("ascii"), "Size": len(authored.payload)}, "stream size or author-supplied modification date changed")
        require(document.stream(int(stream)) == authored.payload, "extracted payload differs from the authored bytes")
    actual_file_objects = {number for number in document.bodies if document.bodies[number].startswith(b"<< /AFRelationship ")}
    actual_streams = {number for number in document.bodies if b"/Type /EmbeddedFile >>\nstream\n" in document.bodies[number].split(b"stream\n", 1)[0] + b"stream\n"}
    require(actual_file_objects == set(refs) and actual_streams == streams, "unowned file specification or embedded stream")
    packet = document.stream(int(catalog["Metadata"]))
    xmp = ET.fromstring(packet.split(b"?>", 1)[1].rsplit(b"<?xpacket", 1)[0])
    for field, expected_text in (("part", "4"), ("rev", "2020"), ("conformance", "F")):
        require([item.text for item in xmp.findall(f".//{{{PDFAID}}}{field}")] == [expected_text], f"XMP PDF/A-4f identification differs at {field}")
    if accessible:
        validate_claims(pdf, wtpdf=wtpdf, associated_files=True)
    else:
        require(not xmp.findall(f".//{{{PDFUAID}}}part"), "archival-only file unexpectedly declares PDF/UA")


def swap_streams(pdf: bytes) -> bytes:
    parsed, bodies = planned_bodies(pdf)
    document = Document(pdf)
    third = document.get(document.root)["AF"][0]
    fourth = document.get(document.root)["AF"][1]
    stream_a = document.get(int(third))["EF"]["F"]
    stream_b = document.get(int(fourth))["EF"]["F"]
    # Both files have the same MIME type, date, and byte count. Competing
    # references therefore look individually valid after the exchange.
    for spec, before, after in ((third, stream_a, stream_b), (fourth, stream_b, stream_a)):
        old = f"{before} 0 R".encode()
        new = f"{after} 0 R".encode()
        require(bodies[int(spec)].count(old) == 2, "stream swap fixture lost its EF edges")
        bodies[int(spec)] = bodies[int(spec)].replace(old, new)
    root, identifier = trailer_facts(parsed)
    return serialize_object_streams(bodies, parsed.header, root, identifier)


def self_test() -> None:
    pdf = (ROOT / "tests/associated_files/files_small.pdf").read_bytes()
    expected = fixtures(4, 16)
    validate(pdf, expected, True, False, True)
    controls = [
        (mutate(pdf, b"/AFRelationship /Source ", b"/AFRelationship /Data ", scope="objects"), "authored attachment relationship"),
        (mutate(pdf, b"/AFRelationship /Data ", b"/AFRelationxxxx /Data ", scope="objects"), "file specification shape"),
        (mutate(pdf, b"/Desc ", b"/Dasc ", occurrences=None, scope="objects", first_only=True), "file specification shape"),
        (mutate(pdf, b"/F (statement) ", b"/G (statement) ", scope="objects"), "file specification shape"),
        (mutate(pdf, b"/UF (statement) ", b"/UX (statement) ", scope="objects"), "file specification shape"),
        (mutate(pdf, b"/ModDate ", b"/ModData ", occurrences=None, scope="objects", first_only=True), "stream size or author-supplied modification date"),
        (mutate(pdf, b"/Subtype /application#2Fxml ", b"/Subtype /application#3Bxml ", scope="objects"), "stream type or MIME"),
        (mutate(pdf, b"/EmbeddedFiles ", b"/EmbeddedLeaves ", scope="objects"), "catalog should use one Names dictionary"),
        (swap_streams(pdf), "extracted payload"),
        (mutate(pdf, b"<pdfaid:conformance>F", b"<pdfaid:conformance>E", scope="payloads"), "XMP PDF/A-4f identification"),
    ]
    for changed, message in controls:
        try:
            validate(changed, expected, True, False, True)
        except ValidationError as error:
            require(message in str(error), f"wrong mutation failure: {error}")
        else:
            raise ValidationError(f"mutation passed: {message}")
    print("PASS independent associated-file checks and atomic mutation controls")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", required=True)
    parser.parse_args()
    self_test()
