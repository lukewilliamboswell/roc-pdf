#!/usr/bin/env python3
"""Read the authored logical and visible mixed-direction Arabic invoice text."""

from pathlib import Path
import sys

from check_bilingual_invoice import read_international_page
from check_pdf_structure import require


def check(pdf: bytes) -> None:
    entries, _ = read_international_page(pdf)
    paragraphs = entries["P"]
    require([entry.text() for entry in paragraphs] ==
            ["شركة السلام AE-118", "المبلغ المستحق AED 2,400.00"], "Arabic paragraph logical order changed")
    require([entry.text() for entry in entries["TD"]] ==
            ["خدمات النقل TR-17", "AED 2,400.00"], "Arabic cell logical order changed")
    require([(entry.language, entry.mode, entry.text()) for entry in entries["Span"]] == [
        ("ar", "RlTb", "شركة السلام"),
        ("ar", "RlTb", "خدمات النقل"),
        ("ar", "RlTb", "المبلغ المستحق"),
    ], "Arabic span lost language or direction")
    for key, entry in zip(("AE-118", "AED"), paragraphs):
        require(entry.mode == "RlTb" and len({mark.y for mark in entry.marks}) == 1, "wrong Arabic line direction")
        by_paint = sorted(entry.marks, key=lambda mark: mark.x)
        require(by_paint[0].visible == key and by_paint[-1].font == "IBMPlexSansArabic", "Latin and Arabic visual order changed")
        require(all(mark.font == "IBMPlexSansArabic" for mark in entry.marks if any("\u0621" <= ch <= "\u064a" for ch in mark.logical)),
                "Arabic input changed face")
    require([entry.mode for entry in entries["TD"]] == ["RlTb", "LrTb"], "Arabic table cell mode escaped its owner")
    require(paragraphs[0].marks[2].logical == "السلام", "joining word split in the emitted supplier span")


if __name__ == "__main__":
    check(Path(sys.argv[1]).read_bytes())
    print("PASS Arabic invoice logical text, writing mode, language and visual order")
