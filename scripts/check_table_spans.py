#!/usr/bin/env python3
"""Compare spanning schedules to independently authored cell and paint facts."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

from check_gallery_features import Node, artifacts, only, tagged
from check_pdf_structure import ValidationError, require
from check_profile_declarations import validate_claims
from check_rich_flow import MARKED, ORIGIN
from check_rich_inline import page_marked_text
from check_structure_semantics import check_structure_semantics, table_attributes, walk_name_tree


@dataclass(frozen=True)
class Cell:
    text: str
    role: str = "TD"
    row_span: int = 1
    column_span: int = 1
    scope: str | None = None
    identifier: int | None = None
    headers: tuple[int, ...] = ()


def id_bytes(ordinal: int) -> bytes:
    return f"c{ordinal:06d}".encode("ascii")


def compact(text: str) -> str:
    return "".join(text.split())


def check_cell(node: Node, expected: Cell, ids: dict[bytes, int], document) -> None:
    attributes = table_attributes(node.value)
    key = None if expected.identifier is None else id_bytes(expected.identifier)
    label = expected.text
    require(node.role == expected.role and compact(node.text) == compact(label), f"wrong logical cell for {label!r}")
    require(attributes.get("RowSpan", 1) == expected.row_span, f"wrong /RowSpan on {label!r}")
    require(attributes.get("ColSpan", 1) == expected.column_span, f"wrong /ColSpan on {label!r}")
    require(attributes.get("Scope") == expected.scope, f"wrong /Scope on {label!r}")
    require(attributes.get("Headers", []) == list(map(id_bytes, expected.headers)), f"wrong /Headers on {label!r}")
    require(node.value.get("ID") == key, f"wrong byte ID on {label!r}")
    if key is not None:
        require(key in ids and document.get(ids[key]) == node.value, f"wrong IDTree target for {label!r}")


def check_row(row: Node, cells: list[Cell], ids: dict[bytes, int], document) -> None:
    require(row.role == "TR" and len(row.children) == len(cells), f"wrong logical row for {cells[0].text!r}")
    for cell, expected in zip(row.children, cells, strict=True):
        check_cell(cell, expected, ids, document)


def identifiers(document) -> dict[bytes, int]:
    tree = document.get(int(document.get(document.root)["StructTreeRoot"]))
    return dict(walk_name_tree(document, int(tree["IDTree"])))


def first_origins(document, pages: list[int]) -> dict[tuple[int, int], tuple[Fraction, Fraction]]:
    origins = {}
    for page in pages:
        content = document.stream(int(document.get(page)["Contents"]))
        for mark, block in MARKED.findall(content):
            match = ORIGIN.search(block)
            if match is not None:
                origins[(page, int(mark))] = tuple(Fraction(item.decode()) for item in match.groups())
    return origins


def schedule_head(rows: list[Node], ids: dict[bytes, int], document, quarterly: bool) -> None:
    require(len(rows) == 2, "layered schedule needs two logical header rows")
    first = 62 if quarterly else 1
    upper = [
        Cell("Business group", "TH", row_span=2, scope="Column", identifier=first),
        Cell("Segment", "TH", row_span=2, scope="Column", identifier=first + 1),
        Cell("Revenue (AUD thousands)", "TH", column_span=2, scope="Column", identifier=first + 2),
    ]
    if quarterly:
        upper.extend(
            Cell(label, "TH", row_span=2, scope="Column", identifier=first + ordinal)
            for ordinal, label in enumerate(("Share", "YoY growth", "Margin"), 3)
        )
    check_row(rows[0], upper, ids, document)
    names = ("Q1", "Q2") if quarterly else ("Prior quarter", "Current quarter")
    lower = [
        Cell(label, "TH", scope="Column", identifier=first + len(upper) + ordinal, headers=(first + 2,))
        for ordinal, label in enumerate(names)
    ]
    check_row(rows[1], lower, ids, document)


def validate_spanning_schedule(pdf: bytes, dimensions: dict[str, int]) -> None:
    validate_claims(pdf, wtpdf=True)
    document, pages, root = tagged(pdf)
    ids = identifiers(document)
    table = only(root.descendants(), "Table", "Farm schedule")
    require([node.role for node in table.children] == ["Caption", "THead", "TBody"], "schedule lost its row groups")
    _, head, body = table.children
    schedule_head(head.children, ids, document, quarterly=False)
    groups = dimensions["spanning_schedule_groups"]
    require(len(body.children) == 2 * groups, "wrong number of authored body rows")
    require(len(pages) == dimensions["pages"], "wrong number of pages for the kept groups")
    origins = first_origins(document, pages)
    for group in range(groups):
        farm, grain, supplies = 6 + 7 * group, 7 + 7 * group, 10 + 7 * group
        first, second = body.children[2 * group : 2 * group + 2]
        check_row(first, [
            Cell("Farm operations", "TH", row_span=2, scope="Row", identifier=farm, headers=(1,)),
            Cell("Grain", "TH", scope="Row", identifier=grain, headers=(2, farm)),
            Cell("2,785", headers=(3, 4, farm, grain)),
            Cell("3,262", headers=(5, 3, grain, farm)),
        ], ids, document)
        check_row(second, [
            Cell("Farm supplies", "TH", scope="Row", identifier=supplies, headers=(2, farm)),
            Cell("2,167", headers=(3, 4, farm, supplies)),
            Cell("2,436", headers=(3, 5, farm, supplies)),
        ], ids, document)
        require(len(first.pages | second.pages) == 1, "a kept farm group broke across a page")
        group_x, first_y = origins[first.children[0].marks[0]]
        grain_x, grain_y = origins[first.children[1].marks[0]]
        supplies_x, supplies_y = origins[second.children[0].marks[0]]
        require(grain_x - group_x == 110 and supplies_x == grain_x, "a carried cell displaced its neighbor")
        require(first_y == grain_y and supplies_y < grain_y, "kept grid uses the wrong baselines")
    require(head.pages == {pages[0]}, "repeated headers acquired logical content")
    expected = "BusinessgroupSegmentRevenue(AUDthousands)PriorquarterCurrentquarter"
    for page in pages[1:]:
        require(compact(artifacts(document, pages, page, b"/Type /Pagination")) == expected, "wrong repeated header text")


def validate_quarterly(pdf: bytes) -> None:
    validate_claims(pdf, wtpdf=True)
    check_structure_semantics(pdf)
    document, pages, root = tagged(pdf)
    ids = identifiers(document)
    table = only(root.descendants(), "Table", "Table 3. Results by segment")
    require([node.role for node in table.children] == ["Caption", "THead", "TBody", "TFoot"], "financial schedule lost its row groups")
    _, head, body, foot = table.children
    schedule_head(head.children, ids, document, quarterly=True)
    first, second = body.children[:2]
    group, grain, explicit = first.children[0], first.children[1], first.children[3]
    supplies, implicit = second.children[0], second.children[2]
    check_cell(group, Cell("Farm operations", "TH", row_span=2, scope="Row", identifier=70, headers=(62,)), ids, document)
    check_cell(grain, Cell("Grain and fodder", "TH", scope="Row", identifier=71, headers=(63, 70)), ids, document)
    check_cell(explicit, Cell("3,262", headers=(69, 64, 71, 70)), ids, document)
    check_cell(supplies, Cell("Farm supplies", "TH", scope="Row", identifier=77, headers=(63, 70)), ids, document)
    check_cell(implicit, Cell("2,436", headers=(64, 69, 70, 77)), ids, document)
    total = foot.children[0].children[0]
    check_cell(total, Cell("Total", "TH", column_span=2, scope="Row", identifier=104, headers=(62, 63)), ids, document)
    require(first.pages == second.pages == head.pages == {pages[1]}, "kept quarterly schedule did not stay on page two")

    # Replace Q2 with the legitimate Q1 ID, preserving type and ownership.
    table_attributes(explicit.value)["Headers"][0] = id_bytes(68)
    try:
        check_cell(explicit, Cell("3,262", headers=(69, 64, 71, 70)), ids, document)
    except ValidationError as error:
        require(str(error) == "wrong /Headers on '3,262'", str(error))
    else:
        raise ValidationError("an internally valid but incorrect edge passed")



def validate_continuing_span(pdf: bytes, count: int) -> None:
    validate_claims(pdf, wtpdf=True)
    document, pages, root = tagged(pdf)
    ids = identifiers(document)
    table = only(root.descendants(), "Table", "Regional observations")
    caption, head, body, foot = table.children
    require([node.role for node in (caption, head, body, foot)] == ["Caption", "THead", "TBody", "TFoot"], "continuing schedule changed its row groups")
    check_row(head.children[0], [
        Cell("Segment", "TH", scope="Column", identifier=1),
        Cell("Observation", "TH", scope="Column", identifier=2),
        Cell("Amount", "TH", scope="Column", identifier=3),
    ], ids, document)
    require(len(body.children) == 2 and len(foot.children) == 1, "a continued fragment added a logical row")
    first, second = body.children
    expected_lines = tuple(f"Regional observation {ordinal}" for ordinal in range(1, count + 1))
    check_row(first, [
        Cell("Grain", "TH", scope="Row", identifier=4, headers=(1,)),
        Cell(" ".join(expected_lines), row_span=2, headers=(2, 4, 7)),
        Cell("3,262", headers=(3, 4)),
    ], ids, document)
    check_row(second, [
        Cell("Farm supplies", "TH", scope="Row", identifier=7, headers=(1,)),
        Cell("2,436", headers=(3, 7)),
    ], ids, document)
    check_row(foot.children[0], [
        Cell("Total", "TH", column_span=2, scope="Row", identifier=9, headers=(1, 2)),
        Cell("5,698", headers=(3, 9)),
    ], ids, document)
    require(head.pages == {pages[0]} and foot.pages == {pages[-1]}, "header or footer ownership escaped its page")
    note = first.children[1]
    text = {(p, mcid): value.rstrip() for p in pages for mcid, value in page_marked_text(document, p)}
    origins = first_origins(document, pages)
    expected_cuts = {64: (46, 18), 128: (46, 48, 34)}[count]
    require(tuple(sum(page == p for page, _ in note.marks) for p in pages) == expected_cuts, "wrong continuation cuts")
    require(tuple(text[mark] for mark in note.marks) == expected_lines, "continued span lost or duplicated text")
    require({origins[mark][0] for mark in note.marks} == {176}, "continued span shifted columns")
    for page in pages[1:]:
        require(artifacts(document, pages, page, b"/Type /Pagination") == "SegmentObservationAmount", "wrong repeated span headers")


def validate_table_spans(pdf: bytes, dimensions: dict[str, int]) -> None:
    if count := dimensions.get("continuing_span_lines"):
        validate_continuing_span(pdf, count)
    else:
        validate_spanning_schedule(pdf, dimensions)


REGIONAL_LINES = (
    "North: morning transfers cleared.",
    "North: growers delivered to plan.",
    "North: standing orders held.",
    "Coast: harvest intake rose.",
    "Coast: farm supplies held steady.",
    "Coast: garage deliveries resumed.",
    "South: grain testing finished.",
    "South: the new silo opened.",
    "South: carrying costs eased.",
    "East: invoices caught up.",
    "East: road access improved.",
    "East: fewer delayed orders.",
    "West: storage stayed full.",
    "West: demand for seed grew.",
    "West: shared routes cut mileage.",
    "All regions: reconcile in January.",
)


def validate_regional(pdf: bytes) -> None:
    validate_claims(pdf, wtpdf=True)
    check_structure_semantics(pdf)
    document, pages, root = tagged(pdf)
    require(len(pages) == 2, "regional schedule needs exactly two pages")
    page1, page2 = pages
    ids = identifiers(document)
    table = only(root.descendants(), "Table", "Regional revenue commentary")
    require([node.role for node in table.children] == ["Caption", "THead", "TBody"], "regional schedule lost its row groups")
    _, head, body = table.children
    require(head.pages == {page1}, "regional repeat acquired logical header content")
    check_row(head.children[0], [
        Cell("Segment", "TH", scope="Column", identifier=1),
        Cell("Regional commentary", "TH", scope="Column", identifier=2),
        Cell("Q2 (AUD thousands)", "TH", scope="Column", identifier=3),
    ], ids, document)
    require(len(body.children) == 2, "a continuation acquired a logical row")
    first, second = body.children
    check_row(first, [
        Cell("Grain North Coast South East West All regions", "TH", scope="Row", identifier=4, headers=(1,)),
        Cell(" ".join(REGIONAL_LINES), row_span=2, headers=(2, 4, 7)),
        Cell("3,262", headers=(3, 4)),
    ], ids, document)
    check_row(second, [
        Cell("Farm supplies", "TH", scope="Row", identifier=7, headers=(1,)),
        Cell("2,436", headers=(3, 7)),
    ], ids, document)
    repeated = artifacts(document, pages, page2, b"/Type /Pagination")
    require(repeated == "SegmentRegional commentaryQ2 (AUD thousands)", "wrong repeated regional header text")

    note = first.children[1]
    text = {(page, mcid): value.rstrip() for page in pages for mcid, value in page_marked_text(document, page)}
    origins = first_origins(document, pages)

    def check_continuation(marks: list[tuple[int, int]]) -> None:
        require([page for page, _ in marks] == [page1] * 10 + [page2] * 6, "wrong regional continuation partition")
        require(tuple(text[mark] for mark in marks) == REGIONAL_LINES, "wrong regional continuation text")
        require({origins[mark][0] for mark in marks} == {165}, "the continued cell drifted across columns")
        require(
            [origins[mark][1] for mark in marks] == [Fraction(value, 2) for value in
                (359, 331, 303, 275, 247, 219, 191, 153, 125, 97, 397, 369, 341, 313, 285, 257)],
            "regional cell line geometry changed",
        )

    check_continuation(note.marks)
    # Drop the last continuation mark while preserving the logical cell and
    # its complete headers. The authored page and fragment oracle must fail.
    try:
        check_continuation(note.marks[:-1])
    except ValidationError as error:
        require(str(error) == "wrong regional continuation partition", str(error))
    else:
        raise ValidationError("continued cell with missing paint passed")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--groups", type=int)
    parser.add_argument("--regional", action="store_true")
    parser.add_argument("--pages", type=int)
    parser.add_argument("--continued", type=int)
    args = parser.parse_args()
    pdf = args.pdf.read_bytes()
    if args.continued:
        check_structure_semantics(pdf)
        validate_continuing_span(pdf, args.continued)
    elif args.regional:
        validate_regional(pdf)
    elif args.groups is None:
        validate_quarterly(pdf)
    else:
        check_structure_semantics(pdf)
        validate_spanning_schedule(pdf, {"spanning_schedule_groups": args.groups, "pages": args.pages})
    print("PASS spanning schedule grid, cells, ownership, header IDs, repeated artifacts and geometry")


if __name__ == "__main__":
    main()
