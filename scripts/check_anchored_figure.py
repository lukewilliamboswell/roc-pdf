#!/usr/bin/env python3
"""Check that the introducing paragraph and tagged figure defer together."""
from __future__ import annotations

import argparse
from pathlib import Path

from check_fixed_pages import K_ARRAY
from check_gallery_features import tagged
from check_pdf_structure import ValidationError, require
from check_profile_declarations import validate_claims
from check_rich_flow import MARKED, ORIGIN, RECT
from check_structure_semantics import Document, text_string, validate_structure_semantics_pdf
from pdf_layout import twin


GALLERY_ALT = (
    "Diagram of the payments request path. Traffic flows left to right from the edge load balancer (1) "
    "through the API gateway (2) and payments API (3) to the acquirer adapters (4). "
    "The payments API writes to the ledger database (5), and the adapters publish to the settlement queue (6), "
    "which the settlement worker (7) consumes before reconciling against the ledger."
)
GALLERY_INTRO = (
    "Every payment enters through the edge, is authorised by the payments API, and is written to the ledger "
    "before any acquirer is told to capture funds. Figure 1 shows the tiers you will meet during an incident."
)
GALLERY_LABELS = (
    "1Edge load balancer2API gateway3Payments API4Acquirer adapters5Ledger database"
    "6Settlement queue7Settlement worker"
)


def check_pair(document, pages, paragraph, section, intro, alternative, caption, labels) -> None:
    require(paragraph.role == "P" and paragraph.text.rstrip() == intro, "wrong introducing paragraph in logical order")
    require(section.role == "Sect" and [node.role for node in section.children] == ["Figure", "Caption"], "the anchored section lost Figure then Caption")
    figure, visible = section.children
    require(text_string(figure.value["Alt"]) == alternative, "wrong authored figure alternative")
    require([node.role for node in visible.children] == ["P"] and visible.text == caption, "wrong caption text or owner")
    require(figure.text.strip() == labels, "figure drawing labels changed logical ownership or order")
    require(paragraph.pages == figure.pages == visible.pages == {pages[1]}, "paragraph, figure and caption did not defer together")
    require(len(paragraph.marks) == 2 and len(visible.marks) == 1, "unexpected anchor or caption flow lines")
    content = document.stream(int(document.get(pages[1])["Contents"]))
    marks = [(int(mcid), body) for mcid, body in MARKED.findall(content)]
    paint_order = [mcid for mcid, _ in marks]
    body = dict(marks)
    para_mcid = [mcid for _, mcid in paragraph.marks]
    figure_mcid = [mcid for _, mcid in figure.marks]
    visible_mcid = [mcid for _, mcid in visible.marks]
    require(paint_order == para_mcid + figure_mcid[:1] + visible_mcid + figure_mcid[1:], "anchored paint order or ownership changed")
    if labels:
        expected = [(b"52", b"296"), (b"52", b"282"), (b"52", b"96.6"), (b"52", b"79.6")]
        require(len(figure_mcid) == 15, "the topology figure lost its drawing or fourteen labels")
    else:
        expected = [(b"20", b"140"), (b"20", b"126"), (b"20", b"54"), (b"20", b"40")]
        require(RECT.findall(body[figure_mcid[0]]) == [(b"0", b"0", b"96", b"64")], "figure drawing changed size or position")
    geometry = [ORIGIN.findall(body[mcid])[0] for mcid in para_mcid + figure_mcid[:1] + visible_mcid]
    require(geometry == expected, "anchored figure escaped its committed frame")


def validate_anchored_figure_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    validate_claims(pdf, wtpdf=True)
    validate_structure_semantics_pdf(pdf, dimensions)
    count = dimensions["anchored_figures"]
    document, pages, root = tagged(pdf)
    require(len(pages) == 2 * count and len(root.children) == 3 * count, "anchor fixture changed its pages or logical children")
    for index in range(count):
        active = pages[2 * index : 2 * index + 2]
        context, paragraph, section = root.children[3 * index : 3 * index + 3]
        ordinal = index + 1
        require(context.role == "P" and context.text == f"Incident context {ordinal}" and context.pages == {active[0]}, "fixture context moved with the anchor")
        require(all(document.get(page)["MediaBox"] == [0, 0, 310, 170] for page in active), "fixture page geometry changed")
        intro = f"Anchor {ordinal}: a payment reaches the gateway. Follow the request in the diagram."
        check_pair(document, active, paragraph, section, intro, "Teal rectangle represents the API gateway.", "API gateway request path", "")


def assert_topology_order(pdf: bytes) -> None:
    document, pages, root = tagged(pdf)
    require(len(pages) == 2 and [node.role for node in root.children] == ["Title", "P", "P", "Sect"], "topology lost its authored reading order")
    require(all(document.get(page)["MediaBox"] == [0, 0, 595, 350] for page in pages), "topology page geometry changed")
    title, context, paragraph, section = root.children
    require(title.text == "Service topology" and title.pages == context.pages == {pages[0]}, "topology context moved with its anchor")
    check_pair(document, pages, paragraph, section, GALLERY_INTRO, GALLERY_ALT, "Figure 1. Request path through the production zone (shaded)", GALLERY_LABELS)


def validate_topology(pdf: bytes) -> None:
    validate_claims(pdf, wtpdf=True)
    validate_structure_semantics_pdf(pdf, {})
    assert_topology_order(pdf)

    document = Document(pdf)
    tree = document.get(int(document.get(document.root)["StructTreeRoot"]))
    raw = document.bodies[int(tree["K"])]
    kids = K_ARRAY.search(raw)
    require(kids is not None, "topology mutation needs root children")
    refs = kids[1].split(b" ")
    require(len(refs) == 12, "topology mutation needs four indirect children")
    swapped = b" ".join(refs[:6] + refs[9:12] + refs[6:9])
    wrong = twin(pdf, raw, raw[:kids.start(1)] + swapped + raw[kids.end(1):], exactly_once=True)
    validate_structure_semantics_pdf(wrong, {})
    try:
        assert_topology_order(wrong)
    except ValidationError as error:
        require(str(error) == "topology lost its authored reading order", str(error))
    else:
        raise ValidationError("topology logical-order mutation passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--figures", type=int)
    args = parser.parse_args()
    pdf = args.pdf.read_bytes()
    if args.figures is None:
        validate_topology(pdf)
    else:
        validate_anchored_figure_pdf(pdf, {"anchored_figures": args.figures})
    print("PASS anchor deferral, caption and drawing ownership, authored order and independent geometry")


if __name__ == "__main__":
    main()
