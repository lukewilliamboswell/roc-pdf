#!/usr/bin/env python3
"""Independent checks of emitted visible labels and PDF PageLabels facts."""
from __future__ import annotations

from check_pdf_structure import require
from check_rich_inline import page_marked_text
from check_structure_semantics import Document, page_order, text_string


def validate_page_labels_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    require(len(pages) == dimensions["pages"], "visible label fixture page count changed")
    root = document.get(int(catalog["PageLabels"]))
    ranges = root["Nums"]
    require(ranges[0] == 0 and ranges[2] == 2, "configured label range starts changed")
    first = ranges[1]
    letters = ranges[3]
    require(first["S"] == "r" and text_string(first["P"]) == "pré-", "front-matter PDF label rule changed")
    require(letters["S"] == "A" and letters["St"] == 27 and text_string(letters["P"]) == "A-", "alphabetic PDF label rule changed")
    if len(pages) > 15:
        require(ranges[4] == 15 and ranges[5]["S"] == "D" and ranges[5]["St"] == 4, "decimal restart PDF label rule changed")
    for index, page in enumerate(pages):
        if index < 2:
            label = "pré-" + ("i" if index == 0 else "ii")
        elif index < 15:
            number = 27 + index - 2
            label = "A-" + chr(65 + (number - 1) % 26) * ((number - 1) // 26 + 1)
        else:
            label = f"R-{4 + index - 15}"
        fonts: dict[str, list[str]] = {}
        body = page_marked_text(document, page, by_font=fonts, artifacts=True)
        actual = "".join("".join(parts) for parts in fonts.values())
        expected = f"Label {label} · Physical {index + 1}/{len(pages)}"
        require(actual == expected, f"page {index + 1}: visible label {actual!r}, expected {expected!r}")
        require("".join(text for _, text in body) == f"Page body {index + 1}.", "running label entered semantic body text")
