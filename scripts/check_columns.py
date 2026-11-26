#!/usr/bin/env python3
"""Verify the pilot article's geometry and authored order in the PDF."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

from check_fixed_pages import Document, read_pages, structure_contents
from check_pdf_structure import ValidationError, require
from pdf_layout import twin
from check_rich_flow import ORIGIN

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "examples/pilot-findings/Pilot.roc"
SMALL = ROOT / "tests/columns/article_1.pdf"


def authored_paragraph() -> str:
    text = SOURCE.read_text().split("findings = ", 1)[1]
    parts = re.findall(r'^\s+(".*"),$', text, flags=re.M)
    words = [json.loads(part) for part in parts if part != '" "']
    require(len(words) == 7, "pilot source should contain seven authored sentences")
    return " ".join(words)


def validate_columns_pdf(data: bytes, dimensions: dict[str, int]) -> None:
    document = Document(data)
    pages = read_pages(document)
    require(len(pages) == dimensions["pages"], "unexpected physical page count")
    contents = structure_contents(document, pages)
    require(contents[0][:3] == (0, "Title", "Pilot findings"), "missing first logical title")
    paragraphs: dict[int, list[str]] = defaultdict(list)
    appearances: dict[int, set[int]] = defaultdict(set)
    for page, role, text, owner in contents[1:]:
        require(role == "P", "a continuation has the wrong structure role")
        paragraphs[owner].append(text)
        appearances[owner].add(page)
    require(len(paragraphs) == dimensions["paragraphs"], "the structure duplicated a continued paragraph")
    authored = authored_paragraph()
    for owner, parts in paragraphs.items():
        require("".join(parts) == authored, "a paragraph was reordered, lost, or duplicated")
        require(len(appearances[owner]) >= 2, "the paragraph never crossed a physical page")

    positions = []
    for page in pages:
        require(document.get(page.number)["MediaBox"] == [0, 0, 456, 228], "unexpected page box")
        origins = [(int(x), int(y)) for x, y in ORIGIN.findall(page.stream)]
        require(len(origins) == len(page.text), "a painted line has no exact column origin")
        require(all(x in (24, 246) and 24 < y < 204 for x, y in origins), "line outside its authored columns")
        require(origins == sorted(origins, key=lambda item: (item[0], -item[1])), "stream did not fill columns sequentially")
        require(len(origins) == len(set(origins)), "column lines overlap")
        positions.append(origins)
    if dimensions["paragraphs"] == 1:
        expected = [
            [(24, 184)] + [(24, y) for y in range(161, 32, -16)] + [(246, y) for y in range(193, 32, -16)],
            [(24, y) for y in range(193, 32, -16)] + [(246, y) for y in range(193, 112, -16)],
        ]
        require(positions == expected, "pilot lines chose a different column or baseline")
        # Compare authored expectations at all three continuation boundaries.
        parts = list(paragraphs.values())[0]
        require(parts[8].endswith("The library "), "first column lost the last source range")
        require(parts[9].startswith("collected the largest share"), "second column resumed at the wrong range")
        require(parts[19].endswith("a two-"), "first page changed its final source range")
        require(parts[20].startswith("minute hold"), "second page resumed at the wrong range")


def verify_twins(data: bytes) -> None:
    document = Document(data)
    contents = structure_contents(document, read_pages(document))
    body = document.bodies[contents[1][3]]
    first, second = list(re.finditer(rb"<< /MCID [0-9]+ /Pg [0-9]+ 0 R /Type /MCR >>", body))[:2]
    reordered = body[:first.start()] + second[0] + body[first.end():second.start()] + first[0] + body[second.end():]
    mutations = [
        (twin(data, body, reordered, exactly_once=True), "a paragraph was reordered"),
        (twin(data, b"1 0 0 1 246 193 cm", b"1 0 0 1 24 193 cm"), "stream did not fill columns"),
    ]
    for corrupted, expected in mutations:
        try:
            validate_columns_pdf(corrupted, {"paragraphs": 1, "pages": 2})
        except ValidationError as error:
            require(expected in str(error), f"mutation failed for the wrong reason: {error}")
        else:
            raise ValidationError(f"column mutation passed: {expected}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("pdf", nargs="?", type=Path)
    args = parser.parse_args()
    try:
        data = (args.pdf or SMALL).read_bytes()
        validate_columns_pdf(data, {"paragraphs": 1, "pages": 2})
        if args.self_test:
            verify_twins(data)
    except ValidationError as error:
        parser.exit(1, f"column fixture: {error}\n")
    print("PASS pilot column geometry and logical reading order")


if __name__ == "__main__":
    main()
