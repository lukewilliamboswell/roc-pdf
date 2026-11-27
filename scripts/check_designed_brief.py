#!/usr/bin/env python3
"""Check the fixed brief's authored frames, reading order and paint order."""
from __future__ import annotations

import argparse
from fractions import Fraction
from pathlib import Path

from check_fixed_pages import Artifact, K_ARRAY, check_artifact, mark_id, read_pages, structure_contents
from check_pdf_structure import ValidationError, require
from check_profile_declarations import validate_claims
from check_rich_flow import ORIGIN, RECT, paint
from check_structure_semantics import Document, element_children, text_string, validate_structure_semantics_pdf
from pdf_layout import twin


TITLE = "Sprout 2.4 launch brief"
CARD = (
    "Key figures ",
    "Three rollout waves from October to November 2026. ",
    "Three plans with boards and a shared decision log. ",
    "Team starts at USD 12 per editor per month.",
)
ALTERNATIVE = (
    "Sprout board with three proposed cards, two decisions in progress and four decided cards. "
    "The progress bar is about two-thirds full."
)
CAPTION = "The Sprout board moves each decision from proposed through deciding to decided."


def document_node(document: Document) -> int:
    tree = document.get(int(document.get(document.root)["StructTreeRoot"]))
    return int(tree["K"])


def read_structure(document: Document, pages) -> None:
    expected = [
        (number, role, text)
        for number in range(len(pages))
        for role, text in (("Title", TITLE), ("Strong", CARD[0]), *(("P", line) for line in CARD[1:]), ("Figure", " "), ("P", CAPTION))
    ]
    elements = structure_contents(document, pages)
    require([(page, role, text) for page, role, text, _ in elements] == expected, "designed brief logical reading order changed")
    root = document.get(document_node(document))
    sections = element_children(document, root)
    require(len(sections) == len(pages) * 3, "designed brief lost an authored placement")
    for index in range(len(pages)):
        title, key_card, figure_section = [document.get(int(ref)) for ref in sections[index * 3 : index * 3 + 3]]
        require([title["S"], key_card["S"], figure_section["S"]] == ["Title", "P", "Sect"], "designed brief lost its authored hierarchy")
        figure, caption = [document.get(int(ref)) for ref in element_children(document, figure_section)]
        require(figure["S"] == "Figure" and caption["S"] == "Caption", "designed brief lost its captioned figure")
        require(text_string(figure["Alt"]) == ALTERNATIVE, "designed brief figure alternative differs from source")


def assert_page(document: Document, page, index: int) -> None:
    width, height = (595, 842) if index % 2 else (612, 792)
    page_value = document.get(page.number)
    require(page_value["MediaBox"] == [0, 0, width, height], "designed brief page size changed")
    require(page_value.get("CropBox", page_value["MediaBox"]) == page_value["MediaBox"], "designed brief page cropped")
    require(page_value.get("Rotate", 0) == 0, "designed brief page rotated")
    require(len(page.marks) == 13, "designed brief marked sequence count changed")
    top, card = height - 136, height - 293
    backgrounds, marks, accents = page.marks[:3], page.marks[3:10], page.marks[10:]
    require(all(mark.role == b"Artifact" for mark in (*backgrounds, *accents)), "designed brief decoration is semantic")
    require(all(mark.role != b"Artifact" for mark in marks), "designed brief semantic paint became an artifact")
    for mark, expected in zip((*backgrounds, *accents), (
        Artifact("Background", (0, 0, width, height), (244, 247, 243)),
        Artifact("Background", (0, top, width, 136), (20, 53, 44)),
        Artifact("Background", (54, card, 487, 108), (255, 255, 255)),
        Artifact("Layout", (54, top + 20, 39, 4), (213, 232, 139)),
        Artifact("Layout", (54, card + 53, 3, 55), (20, 111, 98)),
        Artifact("Layout", (54, 70, 487, 1), (221, 233, 225)),
    ), strict=True):
        check_artifact(page, mark, expected)
    require([page.text[mark_id(mark)] for mark in marks] == [" ", CAPTION, TITLE, *CARD], "designed brief stream paint order changed")
    figure, *text = marks
    data = figure.clean(page.stream)
    rectangles = [tuple(Fraction(v.decode()) for v in rect) for rect in RECT.findall(data)]
    require(ORIGIN.findall(data) == [(b"54", str(card - 257).encode())] * 2, "designed brief figure transform changed")
    require(len(rectangles) == 45 and rectangles[0] == (0, 0, 487, 218), "designed brief board drawing changed")
    columns = (13, 170, 327)
    require(all((x, 26, 146, 178) in rectangles for x in columns), "designed brief board lost a column")
    require([sum(x == column + 10 and w == 126 and h == 22 for x, _, w, h in rectangles) for column in columns] == [3, 2, 4], "designed brief board card counts changed")
    require(all(x >= 0 and y >= 0 and x + w <= 487 and y + h <= 218 for x, y, w, h in rectangles), "designed brief figure paint escaped its frame")

    text_positions = [(54, card - 279), (54, top + 68), *((70, card + 83 - 18 * line) for line in range(4))]
    for mark, (x, y) in zip(text, text_positions, strict=True):
        block = mark.clean(page.stream)
        origins = ORIGIN.findall(block)
        require(origins == [(str(x).encode(), str(y).encode())], "designed brief text origin changed")
        painted = paint(document, page.number, index, mark_id(mark), block)
        left, _, right, _ = painted.bounds
        require(left == x and left < right <= (526 if x == 70 else 541), "designed brief glyphs escaped the frame")


def validate_designed_brief_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    validate_claims(pdf, wtpdf=True)
    validate_structure_semantics_pdf(pdf, dimensions)
    document = Document(pdf)
    pages = read_pages(document)
    require(len(pages) == dimensions["pages"], "designed brief page count differs from source")
    read_structure(document, pages)
    for index, page in enumerate(pages):
        assert_page(document, page, index)


def check_logical_twin(pdf: bytes) -> None:
    document = Document(pdf)
    source = document.bodies[document_node(document)]
    match = K_ARRAY.search(source)
    require(match is not None, "designed brief mutation needs the root /K array")
    refs = match[1].split(b" ")
    require(len(refs) >= 9, "designed brief mutation needs three indirect children")
    moved = refs[6:9] + refs[:6] + refs[9:]
    mutated = twin(pdf, source, source[:match.start(1)] + b" ".join(moved) + source[match.end(1):], exactly_once=True)
    validate_structure_semantics_pdf(mutated, {})
    doc = Document(mutated)
    try:
        read_structure(doc, read_pages(doc))
    except ValidationError as error:
        require(str(error) == "designed brief logical reading order changed", str(error))
    else:
        raise ValidationError("paint-order structure mutation passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--pages", default=1, type=int)
    args = parser.parse_args()
    pdf = args.pdf.read_bytes()
    validate_designed_brief_pdf(pdf, {"pages": args.pages})
    check_logical_twin(pdf)
    print("PASS designed brief frames, figure and caption, independent paint and reading orders, and logical mutation")


if __name__ == "__main__":
    main()
