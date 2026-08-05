#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BLANK_SNAPSHOT = ROOT / "tests" / "gate1_blank" / "snapshot.pdf"
OBJECT_HEADER = re.compile(rb"(?m)^([1-9][0-9]*) 0 obj\n")


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def dictionary_int(dictionary: bytes, name: bytes) -> int:
    match = re.search(rb"/" + re.escape(name) + rb" ([0-9]+)(?:\s|$)", dictionary)
    if match is None:
        raise ValidationError(f"missing integer /{name.decode('ascii')}")
    return int(match.group(1))


def dictionary_ref(dictionary: bytes, name: bytes) -> int:
    match = re.search(rb"/" + re.escape(name) + rb" ([1-9][0-9]*) 0 R(?:\s|$)", dictionary)
    if match is None:
        raise ValidationError(f"missing reference /{name.decode('ascii')}")
    return int(match.group(1))


def object_slices(pdf: bytes) -> tuple[dict[int, int], dict[int, bytes]]:
    matches = list(OBJECT_HEADER.finditer(pdf))
    require(bool(matches), "no indirect objects")
    offsets: dict[int, int] = {}
    bodies: dict[int, bytes] = {}
    for index, match in enumerate(matches):
        number = int(match.group(1))
        require(number not in offsets, f"duplicate object {number}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(pdf)
        offsets[number] = match.start()
        bodies[number] = pdf[match.end() : end]
    return offsets, bodies


def stream_parts(body: bytes, length: int) -> tuple[bytes, bytes]:
    marker = b"stream\n"
    marker_offset = body.find(marker)
    require(marker_offset >= 0, "stream object has no stream keyword")
    dictionary = body[:marker_offset]
    start = marker_offset + len(marker)
    end = start + length
    require(end <= len(body), "stream length exceeds object body")
    data = body[start:end]
    require(body[end:].startswith(b"\nendstream\nendobj\n"), "stream length does not land on endstream")
    return dictionary, data


def indirect_length(bodies: dict[int, bytes], object_number: int) -> int:
    body = bodies.get(object_number)
    require(body is not None, f"missing length object {object_number}")
    match = re.fullmatch(rb"([0-9]+)\nendobj\n", body)
    require(match is not None, f"length object {object_number} is not one canonical integer")
    return int(match.group(1))


def validate_xref(
    pdf: bytes,
    offsets: dict[int, int],
    bodies: dict[int, bytes],
    xref_object: int,
    xref_offset: int,
) -> int:
    body = bodies[xref_object]
    marker_offset = body.find(b"stream\n")
    require(marker_offset >= 0, "xref object is not a stream")
    dictionary = body[:marker_offset]
    require(b"/Type /XRef" in dictionary, "startxref object is not /XRef")
    require(b"/W [1 8 2]" in dictionary, "xref /W is not [1 8 2]")
    size = dictionary_int(dictionary, b"Size")
    length = dictionary_int(dictionary, b"Length")
    require(length == size * 11, "xref length is not exactly 11 bytes per entry")
    require(b"/Index [0 " + str(size).encode("ascii") + b"]" in dictionary, "xref /Index is not contiguous")
    _, data = stream_parts(body, length)
    require(len(data) == length, "xref stream length mismatch")
    require(size == xref_object + 1, "xref /Size does not include object zero and xref")
    require(set(offsets) == set(range(1, size)), "object numbers are not contiguous")

    for number in range(size):
        entry = data[number * 11 : (number + 1) * 11]
        require(len(entry) == 11, f"short xref entry {number}")
        entry_type = entry[0]
        entry_offset = int.from_bytes(entry[1:9], "big")
        generation = int.from_bytes(entry[9:11], "big")
        if number == 0:
            require((entry_type, entry_offset, generation) == (0, 0, 65535), "bad free object-zero entry")
        else:
            require(entry_type == 1, f"object {number} is not an in-use xref entry")
            require(generation == 0, f"object {number} generation is not zero")
            require(entry_offset == offsets[number], f"object {number} xref offset mismatch")

    require(offsets[xref_object] == xref_offset, "startxref does not point to xref object")
    return dictionary_ref(dictionary, b"Root")


def validate_stream_lengths(bodies: dict[int, bytes], xref_object: int) -> None:
    for number, body in bodies.items():
        if number == xref_object or b"stream\n" not in body:
            continue
        marker_offset = body.find(b"stream\n")
        dictionary = body[:marker_offset]
        reference = re.search(rb"/Length ([1-9][0-9]*) 0 R(?:\s|$)", dictionary)
        direct = None if reference is not None else re.search(rb"/Length ([0-9]+)(?:\s|$)", dictionary)
        require(reference is not None or direct is not None, f"object {number} must have one length strategy")
        length = indirect_length(bodies, int(reference.group(1))) if reference is not None else int(direct.group(1))
        _, data = stream_parts(body, length)
        if b"/Filter /FlateDecode" in dictionary:
            try:
                decoded = zlib.decompress(data, -15)
            except zlib.error as error:
                raise ValidationError(f"object {number} has invalid raw DEFLATE: {error}") from error
            require(decoded == b"", f"Gate 1 blank stream {number} is not empty")


def validate_pdf(pdf: bytes, expected_pages: int) -> None:
    require(pdf.startswith(b"%PDF-2.0\n%\xe2\xe3\xcf\xd3\n"), "missing PDF 2.0 header or binary marker")
    require(pdf.endswith(b"%%EOF\n"), "missing canonical EOF marker or trailing bytes")
    start_match = re.search(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    require(start_match is not None, "missing canonical startxref")
    xref_offset = int(start_match.group(1))

    offsets, bodies = object_slices(pdf)
    require(xref_offset in offsets.values(), "startxref is not an object boundary")
    xref_object = next(number for number, offset in offsets.items() if offset == xref_offset)
    root = validate_xref(pdf, offsets, bodies, xref_object, xref_offset)
    validate_stream_lengths(bodies, xref_object)

    root_body = bodies[root]
    require(b"/Type /Catalog" in root_body, "xref /Root is not a catalog")
    pages = dictionary_ref(root_body, b"Pages")
    pages_body = bodies[pages]
    require(b"/Type /Pages" in pages_body, "catalog /Pages is not a page-tree node")
    require(dictionary_int(pages_body, b"Count") == expected_pages, "page-tree /Count mismatch")
    actual_pages = sum(b"/Type /Page " in body for body in bodies.values())
    require(actual_pages == expected_pages, "page object count mismatch")


def self_test() -> None:
    pdf = BLANK_SNAPSHOT.read_bytes()
    validate_pdf(pdf, 1)
    mutations = [
        pdf.replace(b"startxref\n318", b"startxref\n319", 1),
        pdf.replace(b"/Length 5 0 R", b"/Length 3 0 R", 1),
        pdf[:-1] + b"x",
    ]
    for index, mutation in enumerate(mutations):
        try:
            validate_pdf(mutation, 1)
        except ValidationError:
            continue
        raise SystemExit(f"structural checker accepted mutation {index}")
    print("PASS independent PDF structure checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--pages", type=int, default=1)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None:
        raise SystemExit("a PDF path is required")
    validate_pdf(args.pdf.read_bytes(), args.pages)
    print(f"PASS independent PDF structure check: {args.pdf}")


if __name__ == "__main__":
    main()
