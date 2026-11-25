#!/usr/bin/env python3
"""Check fixed remittance sheets using the PDF and the authored expectations."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from fractions import Fraction
import json
from pathlib import Path
import re
import subprocess
import tempfile

from check_accessible_archive import validate_claims
from check_pdf_structure import ValidationError, require
from check_rich_flow import ORIGIN, RECT, Paint, color, paint
from check_rich_inline import page_marked_text
from check_structure_semantics import (
    Document, Parser, Ref, element_children, page_order, validate_structure_semantics_pdf,
)
from check_technical_manual import Sequence, sequences
from check_visual_renderers import read_ppm
from pdf_layout import twin


ROOT = Path(__file__).resolve().parents[1]
EXPECTATIONS = ROOT / "tests/fixed_pages/remittance-expectations.json"
PDFBOX = ROOT / "vendor/pdfbox/pdfbox-app-3.0.8.jar"
MARK_ID = re.compile(rb"<</MCID ([0-9]+)>>")
INDIRECT_KID = re.compile(rb"\b[0-9]+ 0 R\b")
K_ARRAY = re.compile(rb"/K \[([^]]+)\]")
MARK_OPERATORS = re.compile(rb"^(?:BT|W\*?|S|s|f\*?|B\*?|b\*?|BI|[0-9]+ Tr|/[^ ]+ (?:Do|sh))$", re.M)
PAINT_TRANSFORM = re.compile(rb"^.* cm$", re.M)


@dataclass(frozen=True)
class Placement:
    role: str
    text: str
    frame: tuple[int, int, int, int]


@dataclass(frozen=True)
class Artifact:
    kind: str
    rect: tuple[int, int, int, int]
    rgb: tuple[int, int, int]


@dataclass(frozen=True)
class Sheet:
    size: tuple[int, int]
    placements: tuple[Placement, ...]
    paint_order: tuple[int, ...]
    artifacts: tuple[Artifact, ...]


@dataclass(frozen=True)
class Page:
    number: int
    stream: bytes
    marks: tuple[Sequence, ...]
    text: dict[int, str]


def expected_sheets(count: int) -> tuple[Sheet, ...]:
    contract = json.loads(EXPECTATIONS.read_text(encoding="utf-8"))
    require(contract["schema_version"] == 1, "fixed page expectation version changed")
    sheets = []
    for index in range(count):
        kind = contract["sheet_kinds"][index % len(contract["sheet_kinds"])]
        offset = kind["vertical_offset"]

        def translate(box):
            x, y, width, height = box
            return x, y + offset, width, height

        placements = tuple(
            Placement(
                placement["role"],
                placement["text"].format(
                    reference=contract["first_invoice_reference"] + index,
                    amount=kind["amount"],
                ),
                translate(placement["frame"]),
            )
            for placement in contract["placements"]
        )
        artifacts = tuple(
            Artifact(artifact["type"], translate(artifact["rect"]), tuple(artifact["rgb"]))
            for artifact in contract["artifacts"]
        )
        sheets.append(Sheet(tuple(kind["size"]), placements, tuple(kind["paint_order"]), artifacts))
    return tuple(sheets)


def mark_id(mark: Sequence) -> int:
    match = MARK_ID.fullmatch(mark.props)
    require(match is not None, "fixed page text lacks its own MCID")
    return int(match[1])


def read_pages(document: Document) -> tuple[Page, ...]:
    numbers: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), numbers)
    pages = []
    for number in numbers:
        stream = document.stream(int(document.get(number)["Contents"]))
        marks = tuple(sequences(stream))
        require(all(not mark.children for mark in marks), "fixed page nests marked content")
        previous = 0
        for mark in marks:
            require(not MARK_OPERATORS.search(stream[previous:mark.start]), "fixed page paints outside a marked sequence")
            previous = mark.end
        require(not MARK_OPERATORS.search(stream[previous:]), "fixed page paints outside a marked sequence")
        ordered_text = page_marked_text(document, number)
        expected_marks = [mark_id(mark) for mark in marks if mark.role != b"Artifact"]
        require([mcid for mcid, _ in ordered_text] == expected_marks, "fixed page MCID order disagrees with the stream")
        require(len(set(expected_marks)) == len(expected_marks), "fixed page repeats a stream MCID")
        pages.append(Page(number, stream, marks, dict(ordered_text)))
    return tuple(pages)


def structure_contents(document: Document, pages: tuple[Page, ...]) -> list[tuple[int, str, str, int]]:
    catalog = document.get(document.root)
    tree = document.get(int(catalog["StructTreeRoot"]))
    root = int(tree["K"])
    page_index = {page.number: index for index, page in enumerate(pages)}
    contents = []
    visited: set[int] = set()

    def walk(number: int) -> None:
        require(number not in visited, "fixed page structure aliases a node")
        visited.add(number)
        element = document.get(number)
        for child in element_children(document, element):
            if isinstance(child, Ref):
                walk(int(child))
            else:
                require(isinstance(child, dict) and child.get("Type") == "MCR", "fixed page structure has an unexpected content item")
                page = page_index[int(child["Pg"])]
                mcid = int(child["MCID"])
                require(mcid in pages[page].text, "fixed page structure refers outside its page's text")
                contents.append((page, element["S"], pages[page].text[mcid], number))

    walk(root)
    return contents


def check_logical_order(document: Document, pages: tuple[Page, ...], sheets: tuple[Sheet, ...]) -> None:
    expected = [
        (index, placement.role, placement.text)
        for index, sheet in enumerate(sheets)
        for placement in sheet.placements
    ]
    actual = [(page, role, text) for page, role, text, _ in structure_contents(document, pages)]
    require(actual == expected, "fixed page logical reading order or role changed")


def check_artifact(page: Page, mark: Sequence, expected: Artifact) -> None:
    parser = Parser(mark.props, canonical=False)
    properties = parser.value()
    require(properties == {"Type": expected.kind}, "fixed page artifact layer or classification changed")
    block = mark.clean(page.stream)
    rectangles = RECT.findall(block)
    require(len(rectangles) == 1, "fixed page artifact is not one filled rectangle")
    actual = tuple(Fraction(value.decode("ascii")) for value in rectangles[0])
    require(actual == expected.rect, "fixed page artifact rectangle changed")
    require(all(transform == b"1 0 0 1 0 0 cm" for transform in PAINT_TRANSFORM.findall(block)), "fixed page artifact moved in a transformed coordinate system")
    require(color(block) == expected.rgb, "fixed page artifact colour changed")
    require(MARK_OPERATORS.findall(block) == [b"f"], "fixed page rectangular artifact gained other paint")


def check_frame(mark: Paint, placement: Placement) -> None:
    x, y, width, height = placement.frame
    left, bottom, right, top = mark.bounds
    require(left == x and right <= x + width and y <= bottom <= top <= y + height, "fixed page text escaped its authored frame")


def check_physical_page(document: Document, page: Page, sheet: Sheet, index: int) -> None:
    value = document.get(page.number)
    require(value["MediaBox"] == [0, 0, *sheet.size], "fixed page MediaBox differs from its authored size")
    require("CropBox" not in value or value["CropBox"] == value["MediaBox"], "fixed page is cropped")
    require("Rotate" not in value or value["Rotate"] == 0, "fixed page was rotated")
    require(not value.get("Annots") and not value["Resources"].get("XObject"), "fixed page acquired an annotation or XObject")
    require(len(page.marks) == len(sheet.placements) + 2, "fixed page mark count changed")
    background, *marks, overlay = page.marks
    require(background.role == overlay.role == b"Artifact" and all(mark.role != b"Artifact" for mark in marks), "fixed page artifact layers changed")
    check_artifact(page, background, sheet.artifacts[0])
    check_artifact(page, overlay, sheet.artifacts[1])
    observed = [page.text[mark_id(mark)] for mark in marks]
    expected = [sheet.placements[placement].text for placement in sheet.paint_order]
    require(observed == expected, "fixed page stream paint order changed")
    for mark, placement_index in zip(marks, sheet.paint_order, strict=True):
        block = mark.clean(page.stream)
        require(len(PAINT_TRANSFORM.findall(block)) == 1 and ORIGIN.search(block) is not None, "fixed page text paint has an unexpected transform")
        painted = paint(document, page.number, index, mark_id(mark), block)
        placement = sheet.placements[placement_index]
        require(painted.text == placement.text, "fixed page glyph decoding disagrees with its authored text")
        check_frame(painted, placement)


def validate_fixed_pages_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    count = dimensions["pages"]
    require(count in (2, 20), "fixed page oracle expects the remittance scale pair")
    validate_claims(pdf)
    validate_structure_semantics_pdf(pdf, dimensions)
    document = Document(pdf)
    pages, sheets = read_pages(document), expected_sheets(count)
    require(len(pages) == count, "fixed page count differs from authorship")
    check_logical_order(document, pages, sheets)
    for index, (page, sheet) in enumerate(zip(pages, sheets, strict=True)):
        check_physical_page(document, page, sheet, index)


def swap_items(source: bytes, first: Sequence, second: Sequence) -> tuple[bytes, bytes]:
    left, right = sorted((first, second), key=lambda item: item.start)
    require(left.end <= right.start, "fixed page mutation regions overlap")
    previous = source[left.start:right.end]
    swapped = source[right.start:right.end] + source[left.end:right.start] + source[left.start:left.end]
    return previous, swapped


def logical_twin(pdf: bytes, document: Document, pages: tuple[Page, ...]) -> bytes:
    contents = structure_contents(document, pages)
    first, second = contents[1][3], contents[4][3]
    parent = int(document.get(first)["P"])
    require(parent == int(document.get(second)["P"]), "fixed page twin needs two semantic siblings")
    body = document.bodies[parent]
    match = K_ARRAY.search(body)
    require(match is not None, "fixed page twin needs an ordered /K array")
    kid1, kid2 = f"{first} 0 R".encode("ascii"), f"{second} 0 R".encode("ascii")
    refs = INDIRECT_KID.findall(match[1])
    require(refs.count(kid1) == refs.count(kid2) == 1, "fixed page twin needs unique sibling references")
    swapped = INDIRECT_KID.sub(
        lambda ref: {kid1: kid2, kid2: kid1}.get(ref[0], ref[0]), match[1]
    )
    changed = body[:match.start(1)] + swapped + body[match.end(1):]
    return twin(pdf, body, changed, exactly_once=True)


def verify_twins(pdf: bytes) -> None:
    validate_fixed_pages_pdf(pdf, {"pages": 2})
    document = Document(pdf)
    pages = read_pages(document)
    first = pages[0]
    background, _title, amount, intro, _heading, _invoice, overlay = first.marks
    paint_old, paint_changed = swap_items(first.stream, amount, intro)
    layer_old, layer_changed = swap_items(first.stream, background, overlay)
    transform = ORIGIN.search(intro.clean(first.stream))
    require(transform is not None, "fixed page twin needs an exact text translation")
    block = first.stream[intro.start:intro.end]
    moved = block.replace(transform[0], b"1 0 0 1 611 " + transform[2] + b" cm", 1)
    mutations = (
        (logical_twin(pdf, document, pages), "fixed page logical reading order or role changed"),
        (twin(pdf, paint_old, paint_changed, exactly_once=True), "fixed page stream paint order changed"),
        (twin(pdf, block, moved, exactly_once=True), "fixed page text escaped its authored frame"),
        (twin(pdf, layer_old, layer_changed, exactly_once=True), "fixed page artifact layer or classification changed"),
    )
    for altered, expected_error in mutations:
        try:
            validate_fixed_pages_pdf(altered, {"pages": 2})
        except ValidationError as error:
            require(str(error) == expected_error, f"fixed page twin failed for the wrong reason: {error}")
        else:
            raise ValidationError(f"fixed page oracle accepted a mutation targeting {expected_error}")


def verify_artifact_pixels(path: Path, count: int) -> None:
    sheets = expected_sheets(count)
    with tempfile.TemporaryDirectory(prefix="roc-fixed-pages-") as name:
        directory = Path(name)
        classes = directory / "classes"
        classes.mkdir()
        subprocess.run(["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", PDFBOX, "-d", classes, ROOT / "scripts/PdfBoxPages.java"], check=True, capture_output=True)
        renders = directory / "renders"
        subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}:{PDFBOX}", "PdfBoxPages", path, renders], check=True, capture_output=True)
        for index, sheet in enumerate(sheets, 1):
            image = read_ppm(renders / f"page-{index:04d}.ppm")
            require((image.width, image.height) == sheet.size, "fixed page PDFBox raster dimensions changed")
            for artifact, y_offset in zip(sheet.artifacts, (5, 0), strict=True):
                x, y, _, _ = artifact.rect
                row = image.height - 1 - (y + y_offset)
                start = (row * image.width + x + 6) * 3
                rgb = image.pixels[start:start + 3]
                require(all(abs(a - b) <= 2 for a, b in zip(rgb, artifact.rgb, strict=True)), "fixed page PDFBox paint layers changed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--pages", type=int, choices=(2, 20), default=2)
    parser.add_argument("--self-test", action="store_true", help="run four independent mutations against the two-sheet fixture")
    parser.add_argument("--render", action="store_true", help="check artifact overlap pixels with pinned PDFBox")
    args = parser.parse_args()
    data = args.pdf.read_bytes()
    if args.self_test:
        if args.pages != 2:
            parser.error("--self-test requires the two-sheet fixture")
        verify_twins(data)
    else:
        validate_fixed_pages_pdf(data, {"pages": args.pages})
    if args.render:
        verify_artifact_pixels(args.pdf, args.pages)
    print(f"PASS {args.pdf}: exact fixed sheet geometry, independent reading and paint order, and artifact layers")


if __name__ == "__main__":
    main()
