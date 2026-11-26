"""Inspect the declarations and supported font bundles written by roc-pdf."""
from __future__ import annotations

import argparse
import re
from pathlib import Path
import xml.etree.ElementTree as ET

from check_fonts import Bundle
from check_pdf_structure import ValidationError, require as require_structure
from check_pdfa4_structure import check_metadata, dictionary_part, skeleton
from pdf_layout import mutate

RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
UAID = "http://www.aiim.org/pdfua/ns/id/"
DECLARATIONS = "http://pdfa.org/declarations/"
ACCESSIBILITY = DECLARATIONS + "wtpdf#accessibility1.0"


def validate_supported_fonts(bodies: dict[int, bytes]) -> None:
    for number, body in bodies.items():
        dictionary = dictionary_part(body)
        if b"/Subtype /Type0 " in dictionary and b"/Type /Font" in dictionary:
            Bundle(bodies, number)


def validate_claims(data: bytes, *, wtpdf: bool = False, associated_files: bool = False) -> None:
    _offsets, bodies, root, _xref = skeleton(data, 0)
    validate_supported_fonts(bodies)
    packet = check_metadata(bodies, dictionary_part(bodies[root]), associated_files=associated_files)
    try:
        xml = ET.fromstring(packet.split(b"?>", 1)[1].rsplit(b"<?xpacket", 1)[0])
    except ET.ParseError as error:
        raise ValidationError(f"XMP packet is invalid XML: {error}") from error
    description = f".//{{{RDF}}}Description"
    for field, expected in (("part", "2"), ("rev", "2024")):
        key = f"{{{UAID}}}{field}"
        values = [item.text for item in xml.findall(f"{description}/{key}")]
        all_values = xml.findall(f".//{key}")
        require_structure(values == [expected] and len(all_values) == 1, f"XMP must declare exactly pdfuaid:{field} {expected}")
        require_structure(re.search(rb"<pdfuaid:" + field.encode() + rb">", packet) is not None, f"XMP pdfuaid:{field} prefix changed")
    declaration_path = f"{description}/{{{DECLARATIONS}}}declarations/{{{RDF}}}Bag/{{{RDF}}}li"
    resources = xml.findall(declaration_path)
    declarations = xml.findall(f".//{{{DECLARATIONS}}}declarations")
    all_targets = xml.findall(f".//{{{DECLARATIONS}}}conformsTo")
    if wtpdf:
        require_structure(len(declarations) == len(resources) == len(all_targets) == 1, "XMP must carry one WTPDF declaration resource")
        resource = resources[0]
        require_structure(resource.get(f"{{{RDF}}}parseType") == "Resource", "WTPDF declaration must be an RDF resource")
        targets = resource.findall(f"{{{DECLARATIONS}}}conformsTo")
        require_structure([item.text for item in targets] == [ACCESSIBILITY], "XMP must declare WTPDF 1.0 Accessibility")
    else:
        require_structure(not declarations and not all_targets, "unexpected WTPDF declaration")


def self_test() -> None:
    root = Path(__file__).resolve().parents[1]
    combined = (root / "tests/fixed_pages/remittance_2.pdf").read_bytes()
    wtpdf = (root / "tests/fixed_pages/remittance_wtpdf_2.pdf").read_bytes()
    validate_claims(combined)
    validate_claims(wtpdf, wtpdf=True)

    controls = [
        (combined, False, b"<pdfuaid:part>2</pdfuaid:part>", b"<pdfuaid:part>1</pdfuaid:part>", "XMP must declare exactly pdfuaid:part 2"),
        (wtpdf, True, ACCESSIBILITY.encode(), b"http://pdfa.org/declarations/example", "XMP must declare WTPDF 1.0 Accessibility"),
    ]
    for source, with_wtpdf, old, new, diagnostic in controls:
        changed = mutate(source, old, new, occurrences=None, scope="payloads", first_only=True)
        try:
            validate_claims(changed, wtpdf=with_wtpdf)
        except ValidationError as error:
            require_structure(str(error) == diagnostic, f"unexpected mutation diagnostic: {error}")
        else:
            raise ValidationError(f"declaration checker missed mutation: {diagnostic}")

    print("PASS project-owned PDF/UA-2 and WTPDF declaration checks and mutation controls")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", required=True)
    parser.parse_args()
    self_test()
