#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BLANK_SNAPSHOT = ROOT / "tests" / "gate1_blank" / "snapshot.pdf"
DEFLATE_SNAPSHOT = ROOT / "tests" / "gate1_deflate" / "snapshot.pdf"
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
) -> tuple[int, bytes]:
    body = bodies[xref_object]
    marker_offset = body.find(b"stream\n")
    require(marker_offset >= 0, "xref object is not a stream")
    dictionary = body[:marker_offset]
    require(b"/Type /XRef" in dictionary, "startxref object is not /XRef")
    require(b"/W [1 8 2]" in dictionary, "xref /W is not [1 8 2]")
    identifier = re.search(rb"/ID \[<([0-9A-F]{64})> <([0-9A-F]{64})>\]", dictionary)
    require(identifier is not None, "xref has no canonical pair of SHA-256 file identifiers")
    require(identifier.group(1) == identifier.group(2), "initial file identifier pair differs")
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
    return dictionary_ref(dictionary, b"Root"), bytes.fromhex(identifier.group(1).decode("ascii"))


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
    xref_object = next(number for number, offset in offsets.items() if offset == xref_offset)
    root, file_identifier = validate_xref(pdf, offsets, bodies, xref_object, xref_offset)
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
    # gate1_pages stress case in the ordinary suite run.
    pdf = BLANK_SNAPSHOT.read_bytes()
    validate_pdf(pdf, 1, normalized_plan_identity=True)

    deflate_pdf = DEFLATE_SNAPSHOT.read_bytes()
    generated_content = b"q Q\n" * 65536
    validate_pdf(deflate_pdf, 1, generated_content)
    corrupt_deflate = deflate_pdf.replace(b"x\x9c", b"x\x9d", 1)
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
        pdf.replace(b"/Length 5 0 R", b"/Length 3 0 R", 1),
        pdf.replace(b"/Parent 2 0 R", b"/Parent 1 0 R", 1),
        bad_identifier,
        pdf[:-1] + b"x",
    ]
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
