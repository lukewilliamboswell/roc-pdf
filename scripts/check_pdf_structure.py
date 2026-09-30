#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
import zlib
from pathlib import Path

from pdf_layout import LayoutError, OBJECTS_PER_STREAM, is_object_stream_layout, is_stream_body
from pdf_layout import mutate as layout_mutate
from pdf_layout import parse as parse_layout


ROOT = Path(__file__).resolve().parents[1]
BLANK_SNAPSHOT = ROOT / "tests" / "structural_kernel" / "blank.pdf"
DEFLATE_SNAPSHOT = ROOT / "tests" / "structural_kernel" / "deflate.pdf"
OBJECT_HEADER = re.compile(rb"(?m)^([1-9][0-9]*) 0 obj\n")


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


# A canonical string token: uppercase hex, or a literal string whose only
# escapes are \(, \), \\, and three-digit octal (KernelLex's canonical forms).
STRING = rb"(?:<[0-9A-F]*>|\((?:[\x20-\x27\x2A-\x5B\x5D-\x7E]|\\[()\\]|\\[0-7]{3})*\))"


def string_bytes(token: bytes) -> bytes:
    """The bytes of one canonical string token (hex or literal)."""
    if token.startswith(b"<"):
        require(token.endswith(b">") and re.fullmatch(rb"<[0-9A-F]*>", token) is not None, f"string {token!r} is not canonical hex")
        return bytes.fromhex(token[1:-1].decode("ascii"))
    require(re.fullmatch(STRING, token) is not None and token.startswith(b"("), f"string {token!r} is not a canonical literal")
    out = bytearray()
    index = 1
    while index < len(token) - 1:
        byte = token[index]
        if byte == 0x5C:
            following = token[index + 1]
            if following in b"()\\":
                out.append(following)
                index += 2
            else:
                out.append(int(token[index + 1 : index + 4], 8))
                index += 4
        else:
            out.append(byte)
            index += 1
    return bytes(out)


def text_string(token: bytes) -> str:
    """A canonical text string token: UTF-16BE with a BOM, or printable-ASCII
    PDFDocEncoding bytes."""
    data = string_bytes(token)
    if data.startswith(b"\xfe\xff"):
        return data[2:].decode("utf-16-be")
    require(all(0x20 <= byte <= 0x7E for byte in data), f"text string {token!r} is neither UTF-16BE nor printable ASCII")
    return data.decode("ascii")


KID = re.compile(
    rb"\s*(?:([1-9][0-9]*) 0 R"
    rb"|<< /MCID ([0-9]+) /Pg ([1-9][0-9]*) 0 R /Type /MCR >>"
    rb"|<< /Obj ([1-9][0-9]*) 0 R /Pg ([1-9][0-9]*) 0 R /Type /OBJR >>"
    rb"|([0-9]+))"
)


def structure_kids(body: bytes) -> list[tuple[str, int, int]]:
    """The /K kids of one structure element body, as ("element", object, 0),
    ("mcr", mcid, page), or ("objr", annotation, page). A bare integer MCID
    names marked content on the element's own /Pg (ISO 32000-2 14.7.5.2)."""
    start = body.find(b"/K ")
    if start < 0:
        return []
    at = start + 3
    single = not body.startswith(b"[", at)
    if not single:
        at += 1
    kids: list[tuple[str, int, int]] = []
    bare: list[int] = []
    while True:
        if not single and body.startswith(b"]", at):
            at += 1
            break
        match = KID.match(body, at)
        require(match is not None, "structure element /K has an unsupported kid")
        reference, mcid, mcr_page, obj, obj_page, integer = match.groups()
        if reference is not None:
            kids.append(("element", int(reference), 0))
        elif mcid is not None:
            kids.append(("mcr", int(mcid), int(mcr_page)))
        elif obj is not None:
            kids.append(("objr", int(obj), int(obj_page)))
        else:
            kids.append(("mcr", int(integer), -1))
            bare.append(len(kids) - 1)
        at = match.end()
        if single:
            break
        if body.startswith(b" ", at) and not body.startswith(b" ]", at):
            at += 1
    if bare:
        page = re.compile(rb" /Pg ([1-9][0-9]*) 0 R").search(body, at)
        require(page is not None, "a bare MCID kid needs the element's /Pg")
        for index in bare:
            kids[index] = ("mcr", kids[index][1], int(page.group(1)))
    return kids


def is_structure_element(body: bytes) -> bool:
    """A structure element dictionary as the package writes it: a /P parent
    and /S as its last key (/Type /StructElem is optional and omitted)."""
    return b" /P " in body and re.search(rb" /S /[^\s/<>\[\]()]+ >>(?:\nendobj\n)?$", body) is not None


def mcid_owners(bodies: dict[int, bytes], page: int, mcid: int) -> list[int]:
    """Every structure element whose /K references marked content `mcid` on
    `page`, by an MCR or a bare MCID."""
    owners = []
    for number, body in bodies.items():
        if b" /S /" not in body or b"stream\n" in body:
            continue
        for kind, first, second in structure_kids(body):
            if kind == "mcr" and first == mcid and second == page:
                owners.append(number)
    return owners


def utf16_scalars(units_hex: bytes) -> tuple[int, ...]:
    """The scalars of a UTF-16BE hex string, surrogate pairs combined."""
    units = [int(units_hex[index : index + 4], 16) for index in range(0, len(units_hex), 4)]
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
    return tuple(scalars)


TO_UNICODE_BLOCK = re.compile(rb"(?<=\n)([0-9]+) begin(bfchar|bfrange)\n(.*?)end\2\n", re.S)
BFCHAR_ROW = re.compile(rb"<([0-9A-F]{4})> <((?:[0-9A-F]{4})+)>")
BFRANGE_ROW = re.compile(rb"<([0-9A-F]{4})> <([0-9A-F]{4})> <([0-9A-F]{4})>")


def to_unicode_mappings(cmap: bytes) -> dict[int, tuple[int, ...]]:
    """CID -> scalars from the package's canonical ToUnicode CMap: `bfchar`
    rows and single-code-unit `bfrange` rows, each block counted exactly, in
    strictly ascending CID order, a range never crossing a 256-code boundary
    in its CIDs or code units."""
    mappings: dict[int, tuple[int, ...]] = {}
    previous = -1
    blocks = TO_UNICODE_BLOCK.findall(cmap)
    require(blocks, "ToUnicode has no bfchar or bfrange block")
    for count, kind, body in blocks:
        rows = body.split(b"\n")
        require(rows[-1] == b"" and len(rows) - 1 == int(count), f"ToUnicode {kind.decode()} count differs from its rows")
        require(int(count) <= 100, f"ToUnicode {kind.decode()} block exceeds 100 entries")
        for row in rows[:-1]:
            if kind == b"bfchar":
                match = BFCHAR_ROW.fullmatch(row)
                require(match is not None, f"ToUnicode bfchar row {row!r} is not canonical")
                cid = int(match.group(1), 16)
                require(cid > previous, "ToUnicode CIDs are not ascending")
                mappings[cid] = utf16_scalars(match.group(2))
                previous = cid
            else:
                match = BFRANGE_ROW.fullmatch(row)
                require(match is not None, f"ToUnicode bfrange row {row!r} is not canonical")
                low, high, base = (int(value, 16) for value in match.groups())
                require(low > previous and high > low and low >> 8 == high >> 8, "ToUnicode bfrange CIDs are not an ascending run inside one 256-code block")
                require(not 0xD800 <= base <= 0xDFFF and (base & 0xFF) + (high - low) <= 0xFF, "ToUnicode bfrange destination crosses a 256-code boundary")
                for offset in range(high - low + 1):
                    mappings[low + offset] = (base + offset,)
                previous = high
    return mappings


def dictionary_value(body: bytes, key: bytes) -> bytes | None:
    """The balanced `<< ... >>` value of a top-level-looking `/key` entry."""
    start = body.find(b"/" + key + b" <<")
    if start < 0:
        return None
    at = start + len(key) + 2
    depth = 0
    index = at
    while index < len(body):
        if body.startswith(b"<<", index):
            depth += 1
            index += 2
        elif body.startswith(b">>", index):
            depth -= 1
            index += 2
            if depth == 0:
                return body[at:index]
        else:
            index += 1
    return None


def canonical_bytes(data: bytes) -> bytes:
    """The canonical token for a byte string: a literal when strictly shorter
    than hex, otherwise uppercase hex (an independent model of KernelLex)."""
    literal = bytearray(b"(")
    for byte in data:
        if byte in b"()\\":
            literal += b"\\" + bytes([byte])
        elif 0x20 <= byte <= 0x7E:
            literal.append(byte)
        else:
            literal += b"\\" + f"{byte:03o}".encode("ascii")
    literal += b")"
    hexed = b"<" + data.hex().upper().encode("ascii") + b">"
    return bytes(literal) if len(literal) < len(hexed) else hexed


def canonical_text(text: str) -> bytes:
    """The canonical token for a text string: printable ASCII as bytes under
    the byte-string rule, anything else UTF-16BE with a BOM in hex."""
    if all(0x20 <= ord(character) <= 0x7E for character in text):
        return canonical_bytes(text.encode("ascii"))
    return b"<" + (b"\xfe\xff" + text.encode("utf-16-be")).hex().upper().encode("ascii") + b">"


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


def dictionary_ref_array(dictionary: bytes, name: bytes) -> list[int]:
    match = re.search(rb"/" + re.escape(name) + rb" \[([^]]*)\](?:\s|$)", dictionary)
    if match is None:
        raise ValidationError(f"missing reference array /{name.decode('ascii')}")
    contents = match.group(1).strip()
    require(bool(contents), f"/{name.decode('ascii')} must not be empty")
    references = re.findall(rb"([1-9][0-9]*) 0 R", contents)
    canonical = b" ".join(number + b" 0 R" for number in references)
    require(canonical == contents, f"/{name.decode('ascii')} is not a canonical reference array")
    return [int(number) for number in references]


def object_slices(pdf: bytes) -> tuple[dict[int, int], dict[int, bytes]]:
    """File offsets of the top-level objects and the flat body of every
    object, including those stored in object streams."""
    if is_object_stream_layout(pdf):
        try:
            parsed = parse_layout(pdf)
        except LayoutError as error:
            raise ValidationError(str(error)) from error
        return dict(parsed.offsets), dict(parsed.bodies)
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


def decode_stream(bodies: dict[int, bytes], object_number: int) -> tuple[bytes, bytes]:
    """The dictionary and decoded payload of one stream object.

    FlateDecode payloads are inflated with zlib as an independent oracle;
    unfiltered payloads are returned as stored. Any other filter is refused.
    """
    body = bodies.get(object_number)
    require(body is not None, f"object {object_number} does not resolve")
    marker = body.find(b"stream\n")
    require(marker >= 0, f"object {object_number} is not a stream")
    dictionary = body[:marker]
    reference = re.search(rb"/Length ([1-9][0-9]*) 0 R(?:\s|$)", dictionary)
    direct = None if reference is not None else re.search(rb"/Length ([0-9]+)(?:\s|$)", dictionary)
    require(reference is not None or direct is not None, f"object {object_number} has no /Length")
    length = indirect_length(bodies, int(reference.group(1))) if reference is not None else int(direct.group(1))
    _, data = stream_parts(body, length)
    if b"/Filter /FlateDecode" in dictionary:
        try:
            return dictionary, zlib.decompress(data)
        except zlib.error as error:
            raise ValidationError(f"object {object_number} has invalid zlib DEFLATE: {error}") from error
    require(b"/Filter" not in dictionary, f"object {object_number} uses an unexpected filter")
    return dictionary, data


def validate_xref(
    pdf: bytes,
    offsets: dict[int, int],
    bodies: dict[int, bytes],
    xref_object: int,
    xref_offset: int,
) -> tuple[int, bytes]:
    """/Root and the file identifier of a file in the package layout."""
    require(is_object_stream_layout(pdf), "file does not use the object-stream layout")
    found_xref, root, identifier = validate_object_stream_layout(pdf, xref_offset)
    require(found_xref == xref_object, "startxref object is not the xref stream")
    return root, identifier


XREF_DICTIONARY = re.compile(
    rb"<< /DecodeParms << /Columns ([0-9]+) /Predictor 12 >> /Filter /FlateDecode "
    rb"/ID \[<([0-9A-F]{64})> <([0-9A-F]{64})>\] /Index \[0 ([0-9]+)\] /Length ([0-9]+) "
    rb"/Root ([1-9][0-9]*) 0 R /Size ([0-9]+) /Type /XRef /W \[1 ([0-9]+) 2\] >>\n"
)
OBJECT_STREAM_DICTIONARY = re.compile(rb"<< /Filter /FlateDecode /First ([0-9]+) /Length ([0-9]+) /N ([0-9]+) /Type /ObjStm >>\n")


def validate_object_stream_layout(pdf: bytes, xref_offset: int) -> tuple[int, int, bytes]:
    """The package layout, checked from the bytes: returns the xref object,
    /Root, and the file identifier.

    Stream objects are top-level; every other planned object is in an object
    stream; object streams hold OBJECTS_PER_STREAM members in object-number
    order (the last one fewer) and are numbered after the planned objects;
    the xref stream follows them, uses the fewest offset bytes that hold its
    own offset, and is PNG Up predicted. Entry-by-entry agreement between the
    xref rows, the top-level offsets, and the object-stream headers is
    checked by pdf_layout.parse.
    """
    try:
        parsed = parse_layout(pdf)
    except LayoutError as error:
        raise ValidationError(str(error)) from error
    require(parsed.xref_offset == xref_offset, "startxref does not point to the xref stream")
    match = XREF_DICTIONARY.fullmatch(parsed.xref_dictionary)
    require(match is not None, "xref dictionary is not canonical")
    columns, first_id, second_id, index_size, _length, root, size, width = match.groups()
    require(first_id == second_id, "initial file identifier pair differs")
    require(int(index_size) == int(size) == parsed.xref + 1, "xref /Size does not include object zero and xref")
    require(int(width) == max(1, (xref_offset.bit_length() + 7) // 8), "xref offset width is not minimal")
    require(int(columns) == int(width) + 3, "xref predictor columns disagree with /W")

    streams = parsed.object_streams
    planned = parsed.xref - 1 - len(streams)
    require(streams == list(range(planned + 1, parsed.xref)), "object streams are not numbered after the planned objects")
    members = []
    for number in range(1, planned + 1):
        body = parsed.bodies[number]
        if is_stream_body(body):
            require(number in parsed.offsets, f"stream object {number} is in an object stream")
        else:
            require(number in parsed.compressed, f"object {number} is not in an object stream")
            members.append(number)
    expected = {number: (planned + 1 + index // OBJECTS_PER_STREAM, index % OBJECTS_PER_STREAM) for index, number in enumerate(members)}
    require(parsed.compressed == expected, "object streams do not partition the objects in order")
    for ordinal, stream in enumerate(streams):
        body = parsed.bodies[stream]
        dictionary = body[: body.find(b"stream\n")]
        found = OBJECT_STREAM_DICTIONARY.fullmatch(dictionary)
        require(found is not None, f"object stream {stream} dictionary is not canonical")
        count = sum(1 for value in parsed.compressed.values() if value[0] == stream)
        require(int(found.group(3)) == count, f"object stream {stream} /N does not count its members")
    return parsed.xref, int(root), bytes.fromhex(first_id.decode("ascii"))


def validate_stream_lengths(
    bodies: dict[int, bytes], xref_object: int, content_objects: set[int], expected_content: bytes
) -> None:
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
                decoded = zlib.decompress(data)
            except zlib.error as error:
                raise ValidationError(f"object {number} has invalid zlib DEFLATE: {error}") from error
            if number in content_objects:
                require(
                    decoded == expected_content,
                    f"content stream {number} does not match the independently constructed expectation",
                )


def validate_page_tree(bodies: dict[int, bytes], root: int, expected_pages: int) -> set[int]:
    seen_nodes: set[int] = set()
    seen_pages: set[int] = set()

    def walk(node: int, parent: int | None) -> int:
        require(node not in seen_nodes, f"page-tree node {node} is repeated or cyclic")
        body = bodies.get(node)
        require(body is not None, f"missing page-tree node {node}")
        require(b"/Type /Pages" in body, f"page-tree node {node} is not /Pages")
        if parent is None:
            require(b"/Parent " not in body, "root page-tree node has /Parent")
        else:
            require(dictionary_ref(body, b"Parent") == parent, f"page-tree node {node} has wrong /Parent")
        seen_nodes.add(node)

        kids = dictionary_ref_array(body, b"Kids")
        require(len(kids) <= 32, f"page-tree node {node} exceeds fixed fanout 32")
        child_kinds: set[str] = set()
        descendants = 0
        for child in kids:
            child_body = bodies.get(child)
            require(child_body is not None, f"missing page-tree child {child}")
            if b"/Type /Pages" in child_body:
                child_kinds.add("node")
                descendants += walk(child, node)
            else:
                require(b"/Type /Page " in child_body, f"page-tree child {child} is neither /Pages nor /Page")
                require(child not in seen_pages, f"page {child} occurs more than once")
                require(dictionary_ref(child_body, b"Parent") == node, f"page {child} has wrong /Parent")
                seen_pages.add(child)
                child_kinds.add("page")
                descendants += 1
        require(len(child_kinds) == 1, f"page-tree node {node} mixes node and page children")
        require(dictionary_int(body, b"Count") == descendants, f"page-tree node {node} has wrong /Count")
        return descendants

    require(walk(root, None) == expected_pages, "page-tree descendant count mismatch")
    all_nodes = {number for number, body in bodies.items() if b"/Type /Pages" in body}
    all_pages = {number for number, body in bodies.items() if b"/Type /Page " in body}
    require(seen_nodes == all_nodes, "unreachable page-tree node")
    require(seen_pages == all_pages, "unreachable page object")
    return seen_pages


def expected_identifier(bodies: dict[int, bytes], pages: set[int]) -> bytes:
    media_boxes = {
        match.group(1)
        for page in pages
        for match in [re.search(rb"/MediaBox \[0 0 ([0-9]+ [0-9]+)\]", bodies[page])]
        if match is not None
    }
    require(len(media_boxes) == 1, "pages do not share one supported media box")
    media_box = next(iter(media_boxes))
    if media_box == b"595 842":
        size_code = b"\x00"
    elif media_box == b"612 792":
        size_code = b"\x01"
    else:
        raise ValidationError(f"unsupported media box {media_box!r}")

    content_payloads: list[tuple[str, bytes]] = []
    for page in pages:
        content_object = dictionary_ref(bodies[page], b"Contents")
        body = bodies.get(content_object)
        require(body is not None, f"missing content stream {content_object}")
        marker_offset = body.find(b"stream\n")
        require(marker_offset >= 0, f"content object {content_object} is not a stream")
        dictionary = body[:marker_offset]
        length_object = dictionary_ref(dictionary, b"Length")
        _, data = stream_parts(body, indirect_length(bodies, length_object))
        if b"/Filter /FlateDecode" in dictionary:
            try:
                decoded = zlib.decompress(data)
            except zlib.error as error:
                raise ValidationError(f"content stream {content_object} has invalid zlib DEFLATE: {error}") from error
            content_payloads.append(("blank" if decoded == b"" else "generated", decoded))
        else:
            content_payloads.append(("unchanged", data))

    prefix = b"roc-pdf:document-id:v1\x00"
    kinds = {kind for kind, _ in content_payloads}
    require(len(kinds) == 1, "mixed content identity modes")
    kind = next(iter(kinds))
    payloads = [payload for _, payload in content_payloads]
    require(len(set(payloads)) == 1, "content streams do not share one identity")
    if kind == "blank":
        identity = b"blank"
    elif kind == "generated":
        identity = b"generated-content\x00" + hashlib.sha256(payloads[0]).digest()
    else:
        identity = b"unchanged-content\x00" + hashlib.sha256(payloads[0]).digest()

    facts = prefix + identity + b"\x00" + len(pages).to_bytes(8, "big") + size_code
    return hashlib.sha256(facts).digest()


def validate_pdf(
    pdf: bytes,
    expected_pages: int,
    expected_content: bytes = b"",
    normalized_plan_identity: bool = False,
) -> None:
    require(pdf.startswith(b"%PDF-2.0\n%\xe2\xe3\xcf\xd3\n"), "missing PDF 2.0 header or binary marker")
    require(pdf.endswith(b"%%EOF\n"), "missing canonical EOF marker or trailing bytes")
    start_match = re.search(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    require(start_match is not None, "missing canonical startxref")
    xref_offset = int(start_match.group(1))

    offsets, bodies = object_slices(pdf)
    require(xref_offset in offsets.values(), "startxref is not an object boundary")
    require(is_object_stream_layout(pdf), "file does not use the object-stream layout")
    xref_object, root, file_identifier = validate_object_stream_layout(pdf, xref_offset)
    root_body = bodies[root]
    require(b"/Type /Catalog" in root_body, "xref /Root is not a catalog")
    pages = dictionary_ref(root_body, b"Pages")
    page_objects = validate_page_tree(bodies, pages, expected_pages)
    content_objects = {dictionary_ref(bodies[page], b"Contents") for page in page_objects}
    validate_stream_lengths(bodies, xref_object, content_objects, expected_content)
    if not normalized_plan_identity:
        require(file_identifier == expected_identifier(bodies, page_objects), "file identifier does not match normalized plan facts")


def self_test() -> None:
    # The facade blank fixture now carries document facts, so its identifier
    # is the sealed-plan digest rather than the recomputed blank identity;
    # the blank identity derivation stays covered by the kernel-path
    # pages stress case in the ordinary suite run.
    pdf = BLANK_SNAPSHOT.read_bytes()
    validate_pdf(pdf, 1, normalized_plan_identity=True)

    deflate_pdf = DEFLATE_SNAPSHOT.read_bytes()
    generated_content = b"q Q\n" * 65536
    validate_pdf(deflate_pdf, 1, generated_content)
    # The zlib header is CMF 0x78 with FLG 0xDA; 0xDB breaks the header check.
    # Corrupt the content stream's header, located through the parsed layout.
    deflate_layout = parse_layout(deflate_pdf)
    content_number = next(number for number, body in deflate_layout.bodies.items() if b"/Contents" in body)
    content_stream = dictionary_ref(deflate_layout.bodies[content_number], b"Contents")
    content_start = deflate_layout.offsets[content_stream] + deflate_pdf[deflate_layout.offsets[content_stream] :].find(b"stream\n") + len(b"stream\n")
    require(deflate_pdf[content_start : content_start + 2] == b"x\xda", "self-test DEFLATE snapshot has no zlib header")
    corrupt_deflate = deflate_pdf[: content_start + 1] + b"\xdb" + deflate_pdf[content_start + 2 :]
    for label, candidate, content in [
        ("corrupt DEFLATE", corrupt_deflate, generated_content),
        ("wrong generated content", deflate_pdf, generated_content[:-1]),
    ]:
        try:
            validate_pdf(candidate, 1, content)
        except ValidationError:
            pass
        else:
            raise SystemExit(f"structural checker accepted {label}")

    start_match = re.search(rb"startxref\n([0-9]+)\n%%EOF\n$", pdf)
    require(start_match is not None, "self-test fixture has no startxref")
    bad_startxref = (
        b"startxref\n"
        + str(int(start_match.group(1)) + 1).encode("ascii")
        + b"\n%%EOF\n"
    )
    identifier = re.search(rb"/ID \[<([0-9A-F]{64})>", pdf)
    require(identifier is not None, "self-test fixture has no identifier")
    identifier_start = identifier.start(1)
    replacement = b"0" if pdf[identifier_start : identifier_start + 1] != b"0" else b"1"
    bad_identifier = pdf[:identifier_start] + replacement + pdf[identifier_start + 1 :]
    mutations = [
        pdf.replace(start_match.group(0), bad_startxref, 1),
        layout_mutate(pdf, b"/Length 5 0 R", b"/Length 3 0 R", occurrences=1, scope="objects"),
        layout_mutate(pdf, b"/Parent 2 0 R", b"/Parent 1 0 R", occurrences=1, scope="objects"),
        bad_identifier,
        pdf[:-1] + b"x",
    ]
    # A re-serialized twin with no edit must still validate, so every
    # rejected twin is rejected for its edit alone.
    validate_pdf(layout_mutate(pdf, b"/Parent 2 0 R", b"/Parent 2 0 R", occurrences=1, scope="objects"), 1, normalized_plan_identity=True)
    for index, mutation in enumerate(mutations):
        try:
            validate_pdf(mutation, 1, normalized_plan_identity=True)
        except ValidationError:
            continue
        raise SystemExit(f"structural checker accepted mutation {index}")
    print("PASS independent PDF structure checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--pages", type=int, default=1)
    parser.add_argument("--content-stream-bytes", type=int, default=0)
    parser.add_argument("--content-pattern-period", type=int)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None:
        raise SystemExit("a PDF path is required")
    if args.content_stream_bytes == 0 and args.content_pattern_period is None:
        content = b""
    elif args.content_pattern_period == 4:
        pattern = b"q Q\n"
        content = (
            pattern
            * ((args.content_stream_bytes + len(pattern) - 1) // len(pattern))
        )[: args.content_stream_bytes]
    else:
        raise SystemExit("nonempty content requires --content-pattern-period=4")
    validate_pdf(args.pdf.read_bytes(), args.pages, content)
    print(f"PASS independent PDF structure check: {args.pdf}")


if __name__ == "__main__":
    main()
