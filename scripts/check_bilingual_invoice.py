#!/usr/bin/env python3
"""Check the bilingual invoice from PDF bytes and authored expectations."""

import argparse
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal
from fractions import Fraction
from pathlib import Path
import re

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text
from check_structure_semantics import (
    Document, Ref, check_structure_semantics, element_children, page_order, text_string,
)
from check_source_blocks import widths
from check_technical_manual import sequences
from pdf_layout import twin
from text_positions import glyph_positions

HEBREW_ADDRESS = "נועה לוי רחוב הרצל 24 תל אביב"
ADDRESS = f"{HEBREW_ADDRESS} (PO-1042) ישראל"
SERVICE = "ייעוץ בטיחות SKU-42 ILS 1,250.00"
FRENCH = "virement bancaire, s'il vous plaît"
POSITION = re.compile(rb"(?m)^1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm$")
MCID = re.compile(rb"<</MCID ([0-9]+)>>")
ACTUAL = re.compile(rb"<</ActualText <([0-9A-F]+)>>>")
FONT = re.compile(rb"(?m)^/([A-Za-z0-9_]+) [0-9.]+ Tf$")


@dataclass(frozen=True)
class Mark:
    logical: str
    visible: str
    x: Decimal
    y: Decimal
    font: str
    replaced: bool
    positions: tuple[tuple[Fraction, Fraction], ...]


@dataclass
class Owned:
    role: str
    language: str
    mode: str
    marks: list[Mark]

    def text(self) -> str:
        return "".join(mark.logical for mark in self.marks)


def read_international_page(pdf: bytes) -> tuple[dict[str, list[Owned]], list[Mark]]:
    check_structure_semantics(pdf)
    doc = Document(pdf)
    catalog = doc.get(doc.root)
    pages = []
    page_order(doc, int(catalog["Pages"]), pages)
    require(len(pages) == 1, "expected one international text page")
    page = pages[0]
    page_obj = doc.get(page)
    stream = doc.stream(int(page_obj["Contents"]))
    displayed = dict(page_marked_text(doc, page))
    fonts = page_obj["Resources"]["Font"]
    metrics = {name.encode(): widths(doc, int(font)) for name, font in fonts.items()}
    marks = {}
    for sequence in sequences(stream):
        identity = MCID.fullmatch(sequence.props)
        if identity is None:
            continue
        mcid = int(identity[1])
        body = stream[sequence.body_start:sequence.body_end]
        replacement = [ACTUAL.fullmatch(child.props) for child in sequence.children]
        require(len(replacement) <= 1 and all(replacement), "unexpected scope inside bilingual text")
        glyphs = displayed[mcid]
        logical = text_string(bytes.fromhex(replacement[0][1].decode())) if replacement else glyphs
        position, face = POSITION.search(body), FONT.search(body)
        require(position is not None and face is not None, "missing text position or face")
        x, y = [Decimal(item.decode()) for item in position.groups()]
        raw_name = doc.get(int(fonts[face[1].decode()]))["BaseFont"]
        positions = tuple((gx, gy) for _, _, gx, gy in glyph_positions(body, metrics))
        marks[mcid] = Mark(logical, glyphs, x, y, raw_name.split("+")[-1], bool(replacement), positions)

    entries: dict[str, list[Owned]] = defaultdict(list)
    owned_mcids = []

    def visit(number: int, language: str, mode: str) -> Owned:
        node = doc.get(number)
        language = text_string(node["Lang"]) if "Lang" in node else language
        attrs = node.get("A", [])
        for attr in attrs if isinstance(attrs, list) else [attrs]:
            if attr["O"] == "Layout":
                mode = attr["WritingMode"]
        result = Owned(node["S"], language, mode, [])
        for child in element_children(doc, node):
            if isinstance(child, Ref):
                result.marks.extend(visit(int(child), language, mode).marks)
            else:
                require(child["Type"] == "MCR" and int(child["Pg"]) == page, "wrong marked content page")
                mcid = child["MCID"]
                owned_mcids.append(mcid)
                result.marks.append(marks[mcid])
        entries[result.role].append(result)
        return result

    structure = doc.get(int(catalog["StructTreeRoot"]))
    visit(int(structure["K"]), text_string(catalog["Lang"]), "LrTb")
    require(owned_mcids == list(marks), "painted tags do not match logical structure order")
    return entries, list(marks.values())


def check(pdf: bytes) -> None:
    entries, marks = read_international_page(pdf)
    require([entry.text() for entry in entries["H1"]] == ["Bill to", "Items", "Payment"], "heading reading order changed")
    require([entry.text() for entry in entries["P"]] == [
        "Harbour & Finch Pty Ltd", ADDRESS, f"Pay by bank transfer ({FRENCH}).",
    ], "authored paragraph order or logical replacement text changed")
    require([entry.text() for entry in entries["TD"]] == [SERVICE, "ILS 1,250.00"], "logical cell text changed")
    require([(entry.text(), entry.language, entry.mode) for entry in entries["Span"]] == [
        (HEBREW_ADDRESS, "he", "RlTb"), (" ישראל", "he", "RlTb"),
        ("ייעוץ בטיחות", "he", "RlTb"), (FRENCH, "fr", "LrTb"),
    ], "wrong effective language or writing mode")
    require([entry.mode for entry in entries["TD"]] == ["RlTb", "LrTb"], "cell direction leaked between nodes")
    require([entry.text() for entry in entries["Strong"]] == [f"{HEBREW_ADDRESS} (PO-1042)"], "standalone span lost the styled boundary")

    address = entries["P"][1]
    lines = defaultdict(list)
    for mark in address.marks:
        lines[mark.y].append(mark)
    by_line = list(lines.values())
    require(len(by_line) == 2 and list(lines)[0] > list(lines)[1], "expected two descending address baselines")
    require(["".join(mark.logical for mark in line) for line in by_line] ==
            [f"{HEBREW_ADDRESS} ", "(PO-1042) ישראל"], "unexpected committed address break")
    require(all(left.x > right.x for left, right in zip(by_line[0], by_line[0][1:])), "first address line lost RTL positions")
    visual = "".join(mark.visible for mark in sorted(by_line[1], key=lambda mark: mark.x))
    require(visual == "לארשי (PO-1042)", "wrapped line lost its visual order or mirrored brackets")
    cell = entries["TD"][0].marks
    require(len({mark.y for mark in cell}) == 1, "mixed item cell should occupy one line")
    require("".join(mark.visible for mark in sorted(cell, key=lambda mark: mark.x)) ==
            "SKU-42 ILS 1,250.00 תוחיטב ץועיי", "mixed item cell has wrong visual order")
    for mark in marks:
        if any("\u05d0" <= scalar <= "\u05ea" for scalar in mark.logical):
            require(mark.font == "IBMPlexSansHebrew", "Hebrew used the wrong embedded font")
        elif mark.logical.strip() and mark.logical != "24":
            require(mark.font == "Inter-Regular", "Latin used the wrong embedded font")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.pdf is None and not args.self_test:
        parser.error("select a PDF or request --self-test")
    snapshot = Path(__file__).resolve().parents[1] / "examples/bilingual-invoice/bilingual-invoice.pdf"
    pdf = (args.pdf or snapshot).read_bytes()
    check(pdf)
    mutations = [
        # Attach a valid replacement to a different painted fragment.
        (b"FEFF05E005D505E205D4", b"FEFF05D405E805E605DC"),
        # Place the second line's opening logical bracket before the Latin ID.
        (b"1 0 0 1 157.539 653 cm", b"1 0 0 1 106.539 653 cm"),
        (b"/WritingMode /RlTb", b"/WritingMode /LrTb"),
    ]
    for old, new in mutations:
        try:
            check(twin(pdf, old, new))
        except ValidationError:
            continue
        raise ValidationError(f"bilingual invoice oracle missed mutation {old!r}")
    print("PASS bilingual invoice logical text, direction, language, positioning, and mutations")


if __name__ == "__main__":
    main()
