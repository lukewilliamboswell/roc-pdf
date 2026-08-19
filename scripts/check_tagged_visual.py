#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
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
    validate_pdf as validate_structural_pdf,
)


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "tagged_visual" / "minimal.pdf"
EXPECTED_CONTENT = (
    b"/P <</MCID 0>> BDC\n"
    b"/CS1_0 cs\n"
    b"0.50000763 scn\n"
    b"0 0 1 1 re\n"
    b"f\n"
    b"EMC\n"
    b"/Artifact <</Type /Background>> BDC\n"
    b"q\n"
    b"1 0 0 1 2 3 cm\n"
    b"q\n"
    b"2 0 0 1 4 5 cm\n"
    b"/Im1_0 Do\n"
    b"Q\n"
    b"Q\n"
    b"EMC\n"
)


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
    require(b"/Filter /FlateDecode" in dictionary, f"object {number} is not FlateDecode")
    try:
        return dictionary, zlib.decompress(encoded)
    except zlib.error as error:
        raise ValidationError(f"object {number} has invalid zlib DEFLATE: {error}") from error


def validate_tagged_visual_pdf(pdf: bytes) -> None:
    validate_structural_pdf(pdf, 1, EXPECTED_CONTENT, normalized_plan_identity=True)
    _, bodies = object_slices(pdf)

    catalog = only_object(bodies, b"/Type /Catalog", "catalog")
    catalog_body = bodies[catalog]
    require(b"/MarkInfo << /Marked true >>" in catalog_body, "catalog is not marked")
    structure_root = dictionary_ref(catalog_body, b"StructTreeRoot")
    pages_root = dictionary_ref(catalog_body, b"Pages")

    structure_body = bodies[structure_root]
    require(b"/Type /StructTreeRoot" in structure_body, "catalog structure root has wrong type")
    document = dictionary_ref(structure_body, b"K")
    namespace_refs = dictionary_ref_array(structure_body, b"Namespaces")
    require(len(namespace_refs) == 1, "tagged-visual requires exactly one PDF 2.0 namespace")
    namespace = namespace_refs[0]
    parent_tree = dictionary_ref(structure_body, b"ParentTree")
    require(b"/ParentTreeNextKey 1" in structure_body, "ParentTreeNextKey is not exact")

    namespace_body = bodies[namespace]
    expected_namespace = (
        b"<< /NS <FEFF0068007400740070003A002F002F00690073006F002E006F00720067002F"
        b"0070006400660032002F00730073006E> /Type /Namespace >>\nendobj\n"
    )
    require(namespace_body == expected_namespace, "PDF 2.0 namespace is not canonical")

    document_body = bodies[document]
    require(b"/S /Document" in document_body, "top structure element is not Document")
    require(dictionary_ref(document_body, b"P") == structure_root, "Document has wrong structure parent")
    require(dictionary_ref(document_body, b"NS") == namespace, "Document has wrong namespace")
    document_k = dictionary_ref_array(document_body, b"K")
    require(len(document_k) == 1, "Document /K must contain exactly the P child")
    paragraph = document_k[0]

    page = only_object(bodies, b"/Type /Page ", "page")
    require(pages_root in bodies, "catalog page-tree root is missing")
    page_body = bodies[page]
    for box in (b"ArtBox", b"BleedBox", b"CropBox", b"MediaBox", b"TrimBox"):
        require(b"/" + box + b" [0 0 10 10]" in page_body, f"/{box.decode()} is not exact")
    require(b"/Rotate 0" in page_body, "page rotation is not exact")
    require(b"/StructParents 0" in page_body, "page StructParents key is not zero")
    require(b"/Tabs /S" in page_body, "page tab order does not follow structure order")

    paragraph_body = bodies[paragraph]
    require(b"/S /P" in paragraph_body, "structure child is not P")
    require(dictionary_ref(paragraph_body, b"P") == document, "P has wrong structure parent")
    require(dictionary_ref(paragraph_body, b"NS") == namespace, "P has wrong namespace")
    mixed = re.search(
        rb"/K \[([1-9][0-9]*) 0 R << /MCID 0 /Pg ([1-9][0-9]*) 0 R /Type /MCR >>\]",
        paragraph_body,
    )
    require(mixed is not None, "P /K is not exact contextual-Artifact then MCR order")
    contextual_artifact = int(mixed.group(1))
    require(int(mixed.group(2)) == page, "MCR /Pg does not name its painted page")

    artifact_body = bodies[contextual_artifact]
    require(b"/S /Artifact" in artifact_body, "contextual child is not an Artifact structure element")
    require(dictionary_ref(artifact_body, b"P") == paragraph, "contextual Artifact has wrong parent")
    require(
        b"/A << /O /Artifact /Type /Pagination >>" in artifact_body,
        "contextual Artifact attributes are not exact",
    )

    expected_parent_tree = f"<< /Nums [0 [{paragraph} 0 R]] >>\nendobj\n".encode("ascii")
    require(bodies[parent_tree] == expected_parent_tree, "ParentTree row does not map MCID 0 to P")

    resources = re.search(
        rb"/Resources << /ColorSpace << /CS1_0 ([1-9][0-9]*) 0 R >> /XObject << /Im1_0 ([1-9][0-9]*) 0 R >> >>",
        page_body,
    )
    require(resources is not None, "page resources are not the exact normalized closure")
    color_space = int(resources.group(1))
    image = int(resources.group(2))
    require(
        bodies[color_space]
        == b"[/CalGray << /BlackPoint [0 0 0] /WhitePoint [0.95 1 1.089] >>]\nendobj\n",
        "CalGray resource is not exact",
    )

    image_dictionary, pixels = decoded_stream(bodies, image)
    require(b"/Subtype /Image" in image_dictionary, "image resource has wrong subtype")
    require(b"/Width 2" in image_dictionary and b"/Height 2" in image_dictionary, "image dimensions are not 2x2")
    require(b"/BitsPerComponent 8" in image_dictionary, "image component width is not 8")
    require(dictionary_ref(image_dictionary, b"ColorSpace") == color_space, "image has wrong color space")
    require(pixels == bytes((0, 64, 128, 255)), "image pixels differ from independent expectation")

    content = dictionary_ref(page_body, b"Contents")
    _, content_bytes = decoded_stream(bodies, content)
    require(content_bytes == EXPECTED_CONTENT, "content stream differs from independent expectation")
    require(content_bytes.count(b"/P <</MCID 0>> BDC\n") == 1, "meaningful paint ownership is not unique")
    require(
        content_bytes.count(b"/Artifact <</Type /Background>> BDC\n") == 1,
        "page Artifact paint is not distinct and unique",
    )


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "negative twin must preserve byte length")
    require(value.count(old) == 1, f"negative twin source occurs {value.count(old)} times")
    return value.replace(old, new, 1)


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_tagged_visual_pdf(pdf)
    _, bodies = object_slices(pdf)
    paragraph = only_object(bodies, b"/S /P ", "P structure element")
    artifact = only_object(bodies, b"/S /Artifact", "contextual Artifact")
    page = only_object(bodies, b"/Type /Page ", "page")
    parent_tree = only_object(bodies, b"/Nums [0 [", "ParentTree")

    p_ref = f"{paragraph} 0 R".encode("ascii")
    a_ref = f"{artifact} 0 R".encode("ascii")
    page_ref = f"{page} 0 R".encode("ascii")
    mixed = a_ref + b" << /MCID 0 /Pg " + page_ref + b" /Type /MCR >>"
    reordered = b"<< /MCID 0 /Pg " + page_ref + b" /Type /MCR >> " + a_ref
    parent_ref = f"{parent_tree} 0 R".encode("ascii")
    mutations = (
        replace_once(pdf, mixed, reordered),
        replace_once(pdf, b"/Nums [0 [" + p_ref + b"]]", b"/Nums [0 [" + a_ref + b"]]"),
        replace_once(pdf, b"/MCID 0 /Pg " + page_ref, b"/MCID 1 /Pg " + page_ref),
        replace_once(pdf, b"/StructParents 0", b"/StructParents 1"),
        replace_once(pdf, b"/P " + p_ref + b" /S /Artifact", b"/P " + parent_ref + b" /S /Artifact"),
    )
    for index, mutation in enumerate(mutations):
        try:
            validate_tagged_visual_pdf(mutation)
        except ValidationError:
            continue
        raise SystemExit(f"tagged-visual checker accepted negative twin {index}")
    print("PASS tagged-visual normalized structure checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_tagged_visual_pdf(args.pdf.read_bytes())
    print(f"PASS tagged-visual normalized structure check: {args.pdf}")


if __name__ == "__main__":
    main()
