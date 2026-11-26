#!/usr/bin/env python3
"""Check Inter shaping against independently pinned OpenType glyph advances."""

from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
from pathlib import Path
import re

from check_pdf_structure import ValidationError, require
from check_rich_flow import color
from check_rich_inline import to_unicode
from check_source_blocks import FONT, decoded_text, widths
from check_structure_semantics import Document, Ref, element_children, page_order
from check_technical_manual import sequences
from pdf_layout import mutate
from text_positions import glyph_positions

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests/inter_latin/report_2.pdf"
FONT_SHA256 = "40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82"
# HarfBuzz 14.6.0, Inter Regular above, Latn/en/LTR. The first and second
# independent spans come from both sides of the legal cut inside a->b.
LINES = (
    ("a-", (1150, 942)),
    (">b", (1355, 1254)),
    ("AV Proposed -> Decided ", (1273, 1413, 576, 1308, 737, 1228, 1254, 1228, 1081, 1194, 1254, 576, 1954, 576, 1478, 1194, 1170, 496, 1254, 1194, 1254, 576)),
    ("→ Archived", (1954, 576, 1413, 737, 1170, 1211, 496, 1111, 1194, 1254)),
)
ACTUAL = re.compile(rb"<</ActualText <([0-9A-F]+)>>>")
MCID = re.compile(rb"<</MCID ([0-9]+)>>")


def validate_inter_latin_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    """Verify written glyph origins, logical and literal arrows, and line owners."""
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    require(len(pages) == dimensions["pages"], "Inter paragraph pagination changed")
    require(len(pages) > 0, "Inter fixture has no pages")

    observed: list[tuple[int, int]] = []
    arrows: set[tuple[int, int]] = set()
    for page in pages:
        dictionary = document.get(page)
        stream = document.stream(int(dictionary["Contents"]))
        fonts = dictionary["Resources"]["Font"]
        require(len(fonts) == 1, "Inter fixture changed selected face")
        for mark in sequences(stream):
            if mark.role != b"P":
                continue
            identity = MCID.fullmatch(mark.props)
            require(identity is not None, "Inter line has no MCID")
            index = len(observed)
            observed.append((page, int(identity[1])))
            line_index = index if index < 2 else 2 + (index % 2)
            text, advances = LINES[line_index]
            block = stream[mark.body_start:mark.body_end]
            names = FONT.findall(block)
            require(len(names) == 1 and names[0][1] == b"11", "Inter line changed its selected size")
            name = names[0][0]
            font = int(fonts[name.decode("ascii")])
            mapping = to_unicode(document, font)
            painted = decoded_text(block, mapping)
            # ISO 32000-2:2020 9.10.3 and 14.9.4. The ligature and literal
            # use the same CID. ToUnicode retains the exact unscoped literal.
            replacement = ACTUAL.search(block)
            if line_index == 2:
                require(painted == text.replace("->", "→"), "the ligature lost its canonical ToUnicode mapping")
                require(replacement is not None and bytes.fromhex(replacement[1].decode()).decode("utf-16") == text,
                        "ActualText lost a ligature contributor or wrapped separator")
                require(len(mark.children) == 1 and mark.children[0].role == b"Span",
                        "ActualText is not inside the original line's tagged owner")
            else:
                require(replacement is None and painted == text, "unscoped text lost its authored source")
            positions = glyph_positions(block, {name: widths(document, font)})
            require(len(positions) == len(advances), "Inter line lost a glyph")
            expected_pen = 0
            for (_, cid, actual_x, actual_y), advance in zip(positions, advances):
                require(abs(actual_x - expected_pen) <= 6 and actual_y == 0,
                        "Inter emitted glyph position disagrees with HarfBuzz")
                expected_pen += (advance * 11000 + 1024) // 2048
                if mapping[cid] == "→":
                    arrows.add((font, cid))
            paint = (12, 52, 116) if index >= 2 and (index - 2) // 2 % 2 else (0, 0, 0)
            require(color(block) == paint, "paragraph scope failed to change paint independently of shaping")
    require(len(arrows) == 1, "the two spellings failed to share one embedded CID")
    require(len(observed) == (dimensions["paragraphs"] + 1) * 2, "Inter line count changed")

    tree = document.get(int(catalog["StructTreeRoot"]))
    root = document.get(int(tree["K"]))
    logical: list[tuple[int, int]] = []
    for group in element_children(document, root):
        require(isinstance(group, Ref), "Inter frame has no semantic owner")
        container = document.get(int(group))
        paragraphs = element_children(document, container)
        require(len(paragraphs) == 1 and isinstance(paragraphs[0], Ref), "Inter frame must own one paragraph")
        paragraph = document.get(int(paragraphs[0]))
        members = element_children(document, paragraph)
        require(paragraph["S"] == "P" and len(members) == 2, "wrapped Inter lines changed semantic owner")
        for member in members:
            require(isinstance(member, dict) and member["Type"] == "MCR", "unexpected Inter paragraph child")
            logical.append((int(member["Pg"]), member["MCID"]))
    require(logical == observed, "Inter lines changed tagged reading order")


def harfbuzz_check() -> None:
    import uharfbuzz as hb

    data = (ROOT / "package/fonts/Inter-Regular.ttf").read_bytes()
    require(hashlib.sha256(data).hexdigest() == FONT_SHA256, "Inter checkpoint font bytes changed")
    require(hb.__version__ == "0.56.3" and hb.version_string() == "14.6.0", "unpinned HarfBuzz checkpoint")
    font = hb.Font(hb.Face(data))

    def shaped(text: str, features: dict[str, bool] | None = None) -> list[tuple[int, int, int]]:
        buf = hb.Buffer()
        buf.add_utf8(text.encode())
        buf.direction, buf.script, buf.language = "ltr", "Latn", "en"
        hb.shape(font, buf, features)
        return [(info.codepoint, info.cluster, pos.x_advance) for info, pos in zip(buf.glyph_infos, buf.glyph_positions)]

    for text, expected in LINES:
        require(tuple(glyph[2] for glyph in shaped(text)) == expected, f"HarfBuzz checkpoint changed for {text!r}")
    require(shaped("AV") == [(2, 0, 1273), (456, 1, 1413)], "AV pair no longer kerns")
    require(shaped("AV", {"kern": False}) == [(2, 0, 1413), (456, 1, 1413)], "kern negative no longer isolates the pair")
    require(shaped("->") == shaped("→") == [(1805, 0, 1954)], "arrow spellings no longer agree visually")
    require(shaped("->", {"calt": False}) == [(1459, 0, 942), (1517, 1, 1355)],
            "calt negative no longer isolates the ligature")
    require(shaped("a->b")[1] == (1805, 1, 1954), "unsafe-cut control no longer ligates without isolation")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    dimensions = {"pages": 1, "paragraphs": 2}
    validate_inter_latin_pdf(pdf, dimensions)
    for before, after, message in (
        (b"002D003E0020", b"003E0020", "lost a ligature contributor"),
        (b"<0001> 68.5 <00040014>", b"<0001> <00040014>", "glyph position disagrees"),
    ):
        invalid = mutate(pdf, before, after, occurrences=2, scope="payloads")
        Document(invalid)
        try:
            validate_inter_latin_pdf(invalid, dimensions)
        except ValidationError as error:
            require(message in str(error), f"Inter twin failed for an unrelated reason: {error}")
        else:
            raise ValidationError(f"Inter oracle accepted mutation {before!r}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the committed fixture and mutation twins")
    parser.add_argument("--harfbuzz", action="store_true", help="also verify the checkpoints with uharfbuzz 0.56.3")
    args = parser.parse_args()
    self_test()
    if args.harfbuzz:
        harfbuzz_check()
    print("PASS Inter text positions, source mapping, and mutation twins")
