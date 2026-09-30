#!/usr/bin/env python3
"""Independent reader and flat re-serializer for roc-pdf file layouts.

The package writes one file layout: stream objects are top-level indirect
objects, every other object is stored in a FlateDecode object stream, and a
FlateDecode cross-reference stream (PNG Up predictor) indexes both. The
structural checkers were written against the older flat layout, in which
every object is a top-level ``N 0 obj`` with an uncompressed ``[1 8 2]`` xref
stream. This module parses either layout from the bytes alone and can
re-serialize any parsed file into that flat layout, so:

- checkers read object bodies in the same ``<value>\\nendobj\\n`` form they
  always have, whatever layout the bytes use;
- negative self-tests mutate a flat, byte-searchable twin (including
  decoded stream payloads, which are re-deflated) instead of compressed
  bytes.

It uses only the Python standard library; zlib is the independent DEFLATE
oracle. It does not trust the file's own layout claims: every xref entry is
checked against the object it locates.
"""
from __future__ import annotations

import re
import zlib
from dataclasses import dataclass, field


class LayoutError(ValueError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise LayoutError(message)


OBJECT_HEADER = re.compile(rb"(?m)^([1-9][0-9]*) 0 obj\n")
FLAT_TAIL = b"\nendobj\n"


@dataclass
class Parsed:
    """One parsed file.

    ``bodies`` maps every object number to its flat body: the object value
    followed by ``\\nendobj\\n`` (streams keep ``stream``/``endstream``).
    ``offsets`` holds the file offset of each top-level object and
    ``compressed`` the ``(object stream, index)`` of each object stored in an
    object stream. ``xref`` is the cross-reference stream's object number.
    """

    bodies: dict[int, bytes] = field(default_factory=dict)
    offsets: dict[int, int] = field(default_factory=dict)
    compressed: dict[int, tuple[int, int]] = field(default_factory=dict)
    object_streams: list[int] = field(default_factory=list)
    xref: int = 0
    xref_offset: int = 0
    xref_dictionary: bytes = b""
    header: bytes = b""


def _top_level(pdf: bytes) -> tuple[dict[int, int], dict[int, bytes]]:
    matches = list(OBJECT_HEADER.finditer(pdf))
    _require(bool(matches), "no indirect objects")
    offsets: dict[int, int] = {}
    bodies: dict[int, bytes] = {}
    for index, match in enumerate(matches):
        number = int(match.group(1))
        _require(number not in offsets, f"duplicate object {number}")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(pdf)
        offsets[number] = match.start()
        bodies[number] = pdf[match.end() : end]
    return offsets, bodies


def _direct_int(dictionary: bytes, name: bytes) -> int | None:
    match = re.search(rb"/" + re.escape(name) + rb" ([0-9]+)(?:\s|>|$)", dictionary)
    return None if match is None else int(match.group(1))


def _stream_data(bodies: dict[int, bytes], number: int, direct_only: bool = False) -> tuple[bytes, bytes]:
    body = bodies[number]
    marker = body.find(b"stream\n")
    _require(marker >= 0, f"object {number} is not a stream")
    dictionary = body[:marker]
    reference = re.search(rb"/Length ([1-9][0-9]*) 0 R(?:\s|$)", dictionary)
    if reference is not None:
        _require(not direct_only, f"object {number} must use a direct /Length")
        length_body = bodies.get(int(reference.group(1)))
        _require(length_body is not None, f"object {number}: /Length object is missing")
        match = re.fullmatch(rb"([0-9]+)\nendobj\n", length_body)
        _require(match is not None, f"object {number}: /Length object is not one integer")
        length = int(match.group(1))
    else:
        length = _direct_int(dictionary, b"Length")
        _require(length is not None, f"object {number} has no /Length")
    start = marker + len(b"stream\n")
    data = body[start : start + length]
    _require(len(data) == length, f"object {number}: stream length exceeds the object")
    _require(body[start + length :].startswith(b"\nendstream\nendobj\n"), f"object {number}: /Length does not land on endstream")
    return dictionary, data


def _inflate(dictionary: bytes, data: bytes, number: int) -> bytes:
    _require(b"/Filter /FlateDecode" in dictionary, f"object {number} is not FlateDecode")
    try:
        return zlib.decompress(data)
    except zlib.error as error:
        raise LayoutError(f"object {number} has invalid zlib DEFLATE: {error}") from error


def _undo_up_predictor(decoded: bytes, columns: int) -> list[bytes]:
    row = columns + 1
    _require(len(decoded) % row == 0, "xref stream is not whole predictor rows")
    rows: list[bytes] = []
    previous = bytes(columns)
    for start in range(0, len(decoded), row):
        _require(decoded[start] == 2, "xref predictor row is not PNG Up")
        current = bytes((decoded[start + 1 + index] + previous[index]) & 0xFF for index in range(columns))
        rows.append(current)
        previous = current
    return rows


def is_object_stream_layout(pdf: bytes) -> bool:
    return b"/Type /ObjStm" in pdf


def parse(pdf: bytes) -> Parsed:
    """Parse the flat or object-stream layout into flat object bodies."""
    parsed = Parsed()
    parsed.header = pdf[: pdf.find(b"\n", pdf.find(b"\n") + 1) + 1]
    offsets, top = _top_level(pdf)
    startxref = re.findall(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    _require(len(startxref) == 1, "missing canonical startxref trailer")
    parsed.xref_offset = int(startxref[0])
    xref_numbers = [number for number, offset in offsets.items() if offset == parsed.xref_offset]
    _require(len(xref_numbers) == 1, "startxref does not point to an object")
    parsed.xref = xref_numbers[0]
    xref_body = top[parsed.xref]
    parsed.xref_dictionary = xref_body[: xref_body.find(b"stream\n")]
    _require(b"/Type /XRef" in parsed.xref_dictionary, "startxref object is not /XRef")
    parsed.offsets = dict(offsets)
    parsed.bodies = dict(top)
    if not is_object_stream_layout(pdf):
        return parsed

    # The xref stream: direct length, FlateDecode with the PNG Up predictor.
    dictionary, data = _stream_data(top, parsed.xref, direct_only=True)
    widths = re.search(rb"/W \[([0-9]+) ([0-9]+) ([0-9]+)\]", dictionary)
    _require(widths is not None, "xref stream has no three-field /W")
    w1, w2, w3 = (int(value) for value in widths.groups())
    columns = w1 + w2 + w3
    parms = re.search(rb"/DecodeParms << /Columns ([0-9]+) /Predictor 12 >>", dictionary)
    _require(parms is not None and int(parms.group(1)) == columns, "xref stream predictor parameters are not canonical")
    rows = _undo_up_predictor(_inflate(dictionary, data, parsed.xref), columns)
    size = _direct_int(dictionary, b"Size")
    _require(size == len(rows), "xref /Size disagrees with its entries")
    _require(b"/Index [0 " + str(size).encode() + b"]" in dictionary, "xref /Index is not contiguous")

    entries: dict[int, tuple[int, int, int]] = {}
    for number, row in enumerate(rows):
        kind = int.from_bytes(row[:w1], "big") if w1 else 1
        second = int.from_bytes(row[w1 : w1 + w2], "big")
        third = int.from_bytes(row[w1 + w2 :], "big")
        entries[number] = (kind, second, third)
    _require(entries[0] == (0, 0, 65535), "object zero is not the canonical free entry")

    # Every object stream: decode and split its members.
    streams = sorted({second for kind, second, _ in entries.values() if kind == 2})
    parsed.object_streams = streams
    for stream_number in streams:
        _require(stream_number in top, f"object stream {stream_number} is not top-level")
        stream_dictionary, stream_data = _stream_data(top, stream_number, direct_only=True)
        _require(b"/Type /ObjStm" in stream_dictionary, f"object {stream_number} is not /ObjStm")
        count = _direct_int(stream_dictionary, b"N")
        first = _direct_int(stream_dictionary, b"First")
        _require(count is not None and first is not None, f"object stream {stream_number} lacks /N or /First")
        decoded = _inflate(stream_dictionary, stream_data, stream_number)
        header = decoded[:first].split()
        _require(len(header) == 2 * count, f"object stream {stream_number} header does not list /N pairs")
        members = [(int(header[2 * index]), int(header[2 * index + 1])) for index in range(count)]
        for index, (number, offset) in enumerate(members):
            end = members[index + 1][1] if index + 1 < count else len(decoded) - first
            _require(0 <= offset <= end, f"object stream {stream_number} offsets are not ascending")
            text = decoded[first + offset : first + end]
            _require(text.endswith(b"\n"), f"object {number} in stream {stream_number} is not newline-terminated")
            _require(number not in parsed.bodies, f"object {number} is stored twice")
            _require(entries.get(number) == (2, stream_number, index), f"object {number} xref entry disagrees with object stream {stream_number}")
            _require(b"stream\n" not in text[:1] and not re.search(rb"\bstream\n", text), f"object {number} in an object stream is a stream")
            parsed.bodies[number] = text[:-1] + FLAT_TAIL
            parsed.compressed[number] = (stream_number, index)

    for number, (kind, second, third) in entries.items():
        if number == 0:
            continue
        if kind == 1:
            _require(third == 0, f"object {number} generation is not zero")
            _require(offsets.get(number) == second, f"object {number} xref offset mismatch")
        else:
            _require(kind == 2, f"object {number} is not an in-use entry")
    _require(set(parsed.bodies) == set(range(1, size)), "object numbers are not contiguous")
    return parsed


def trailer_facts(parsed: Parsed) -> tuple[bytes, bytes]:
    """The /Root reference text and the /ID array text of the xref dictionary."""
    root = re.search(rb"/Root ([1-9][0-9]*) 0 R", parsed.xref_dictionary)
    identifier = re.search(rb"/ID (\[<[0-9A-F]+> <[0-9A-F]+>\])", parsed.xref_dictionary)
    _require(root is not None and identifier is not None, "xref has no /Root or /ID")
    return root.group(1), identifier.group(1)


def serialize_flat(bodies: dict[int, bytes], header: bytes, root: bytes, identifier: bytes) -> bytes:
    """Write the flat layout: every object top-level, uncompressed [1 8 2] xref."""
    numbers = sorted(bodies)
    _require(numbers == list(range(1, len(numbers) + 1)), "objects are not contiguous")
    out = bytearray(header)
    offsets: dict[int, int] = {}
    for number in numbers:
        offsets[number] = len(out)
        out += str(number).encode() + b" 0 obj\n" + bodies[number]
    xref = len(numbers) + 1
    size = xref + 1
    offsets[xref] = len(out)
    entries = bytearray(bytes([0]) + (0).to_bytes(8, "big") + (65535).to_bytes(2, "big"))
    for number in range(1, size):
        entries += bytes([1]) + offsets[number].to_bytes(8, "big") + (0).to_bytes(2, "big")
    out += (
        str(xref).encode()
        + b" 0 obj\n<< /ID "
        + identifier
        + b" /Index [0 "
        + str(size).encode()
        + b"] /Length "
        + str(len(entries)).encode()
        + b" /Root "
        + root
        + b" 0 R /Size "
        + str(size).encode()
        + b" /Type /XRef /W [1 8 2] >>\nstream\n"
    )
    out += entries + b"\nendstream\nendobj\nstartxref\n" + str(offsets[xref]).encode() + b"\n%%EOF\n"
    return bytes(out)


def flatten(pdf: bytes) -> bytes:
    """The equivalent flat-layout file; flat input is returned unchanged."""
    if not is_object_stream_layout(pdf):
        return pdf
    parsed = parse(pdf)
    bodies = {number: body for number, body in parsed.bodies.items() if number != parsed.xref and number not in parsed.object_streams}
    # Object streams and the xref stream sit after every planned object, so
    # dropping them keeps the planned numbers contiguous.
    _require(sorted(bodies) == list(range(1, len(bodies) + 1)), "object streams are not numbered after the planned objects")
    root, identifier = trailer_facts(parsed)
    return serialize_flat(bodies, parsed.header, root, identifier)


def _replace_stream_payload(body: bytes, bodies: dict[int, bytes], number: int, payload: bytes) -> tuple[bytes, int | None, bytes]:
    dictionary, _ = _stream_data(bodies, number)
    encoded = zlib.compress(payload, 9) if b"/Filter /FlateDecode" in dictionary else payload
    reference = re.search(rb"/Length ([1-9][0-9]*) 0 R(?:\s|$)", dictionary)
    if reference is None:
        dictionary = re.sub(rb"/Length [0-9]+", b"/Length " + str(len(encoded)).encode(), dictionary, count=1)
        length_object = None
    else:
        length_object = int(reference.group(1))
    return dictionary + b"stream\n" + encoded + b"\nendstream\nendobj\n", length_object, encoded


def mutate(pdf: bytes, old: bytes, new: bytes, occurrences: int | None = 1) -> bytes:
    """A flat twin of ``pdf`` with ``old`` replaced by ``new``.

    The search covers object bodies (dictionaries, arrays, and stream
    dictionaries) and the decoded payloads of FlateDecode streams, which are
    re-deflated after the edit. ``occurrences`` (when not None) is the exact
    number of places ``old`` must occur across the whole file.
    """
    parsed = parse(flatten(pdf))
    bodies = dict(parsed.bodies)
    xref = parsed.xref
    del bodies[xref]
    found = 0
    edits: dict[int, bytes] = {}
    for number in sorted(bodies):
        body = bodies[number]
        marker = body.find(b"stream\n")
        if marker < 0:
            count = body.count(old)
            if count:
                found += count
                edits[number] = body.replace(old, new)
            continue
        dictionary = body[:marker]
        count = dictionary.count(old)
        if count:
            found += count
            body = dictionary.replace(old, new) + body[marker:]
            bodies[number] = body
            edits[number] = body
        stream_dictionary, data = _stream_data(bodies, number)
        payload = zlib.decompress(data) if b"/Filter /FlateDecode" in stream_dictionary else data
        count = payload.count(old)
        if count:
            found += count
            rebuilt, length_object, encoded = _replace_stream_payload(body, bodies, number, payload.replace(old, new))
            edits[number] = rebuilt
            if length_object is not None:
                edits[length_object] = str(len(encoded)).encode() + FLAT_TAIL
    _require(found > 0, f"mutation target {old!r} not found")
    if occurrences is not None:
        _require(found == occurrences, f"mutation target {old!r} occurs {found} times, expected {occurrences}")
    bodies.update(edits)
    root, identifier = trailer_facts(parsed)
    return serialize_flat(bodies, parsed.header, root, identifier)
