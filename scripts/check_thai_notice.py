#!/usr/bin/env python3
"""Check that a Thai notice wraps at authored dictionary boundaries."""

from collections import defaultdict
from pathlib import Path
import sys

from check_bilingual_invoice import read_international_page
from check_pdf_structure import require

WORDS = ["กรุณา", "ชำระ", "เงิน", "ภายใน", "วันนี้"]
NOTICE = "".join(WORDS)


def check(pdf: bytes) -> None:
    entries, _ = read_international_page(pdf)
    require([node.text() for node in entries["P"]] == [NOTICE, "Quote TH-2026 with your payment."],
            "Thai notice logical source changed")
    spans = entries["Span"]
    require(len(spans) == 1 and spans[0].language == "th" and spans[0].mode == "LrTb" and spans[0].text() == NOTICE,
            "Thai notice language, direction or ownership changed")
    lines = defaultdict(list)
    for mark in spans[0].marks:
        require(mark.font == "IBMPlexSansThaiLooped", "Thai notice changed its selected font")
        lines[mark.y].append(mark.logical)
    require(len(lines) == 2 and list(lines)[0] > list(lines)[1] and list(lines.values()) ==
            [["กรุณา", "ชำระ", "เงิน"], ["ภายใน", "วันนี้"]], "Thai notice changed its committed dictionary cut")
    for mark, expected in [
        (spans[0].marks[1], [(0, 0), (6897, 0), (6853, 0), (12265, 0), (18535, 0)]),
        (spans[0].marks[-1], [(0, 0), (6325, 0), (5544, 0), (12980, 0), (19459, 0), (21087, 880)]),
    ]:
        require(mark.replaced and len(mark.positions) == len(expected) and
                all(abs(x-ex) <= 2 and abs(y-ey) <= 2 for (x, y), (ex, ey) in zip(mark.positions, expected)),
                "Thai SARA AM decomposition or attached mark positions changed")


def check_scale(pdf: bytes, dimensions: dict[str, int]) -> None:
    entries, _ = read_international_page(pdf)
    copies = dimensions["dictionary_repetitions"]
    require(len(entries["P"]) == 1, "Thai scale paragraph lost its single owner")
    paragraph = entries["P"][0]
    require(paragraph.language == "th" and paragraph.mode == "LrTb" and paragraph.text() == NOTICE * copies,
            "Thai scale logical text, language or writing mode changed")
    require([mark.logical for mark in paragraph.marks] == WORDS * copies,
            "Thai scale lost a grapheme-aligned word edge")
    baselines = defaultdict(list)
    for mark in paragraph.marks:
        baselines[mark.y].append(mark.x)
    require(len(baselines) >= copies and list(baselines) == sorted(baselines, reverse=True),
            "Thai scale paragraph lost a committed line")
    require(all(positions == sorted(positions) and len(set(positions)) == len(positions)
                for positions in baselines.values()), "Thai scale painted a line in the wrong order")


if __name__ == "__main__":
    check(Path(sys.argv[1]).read_bytes())
    print("PASS Thai notice logical text, language, dictionary wrapping and mark positions")
