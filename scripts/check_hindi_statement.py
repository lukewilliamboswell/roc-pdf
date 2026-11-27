#!/usr/bin/env python3
"""Check the Hindi statement through the emitted PDF's text and structure."""

from pathlib import Path
import sys

from check_bilingual_invoice import read_international_page
from check_pdf_structure import require

INDIC = "IBMPlexSansDevanagari"


def check(pdf: bytes) -> None:
    entries, _ = read_international_page(pdf)
    require([entry.text() for entry in entries["P"]] ==
            ["वित्तीय विवरण FY 2026", "कृपया भुगतान करें by 30 November."], "Hindi paragraph logical text changed")
    require([entry.text() for entry in entries["TD"]] ==
            ["प्रशिक्षण शुल्क IN-42", "INR 8,400.00"], "Hindi statement logical cell changed")
    spans = entries["Span"]
    require([(entry.language, entry.mode, entry.text()) for entry in spans] == [
        ("hi", "LrTb", "वित्तीय विवरण"), ("hi", "LrTb", "प्रशिक्षण शुल्क"), ("hi", "LrTb", "कृपया भुगतान करें"),
    ], "Hindi span language or logical text changed")
    require(all(mark.font == INDIC for entry in spans for mark in entry.marks if mark.logical.strip()),
            "an authored Hindi word changed font")
    for word, expected_x in [(spans[0].marks[0], [0, 3410, 10274, 18304, 21714]),
                             (spans[2].marks[0], [0, 6468, 9427, 16093, 23606])]:
        require(word.replaced, "shaped cluster lost its logical replacement text")
        require(len(word.positions) == len(expected_x), "Hindi changed its shaped glyph count")
        require(all(abs(x-expected) <= 2 and y == 0 for (x, y), expected in zip(word.positions, expected_x)),
                "Hindi dependent vowel or mark lost its HarfBuzz position")


if __name__ == "__main__":
    check(Path(sys.argv[1]).read_bytes())
    print("PASS Hindi statement logical text, language, conjunct and dependent vowel positions")
