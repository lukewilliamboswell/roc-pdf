#!/usr/bin/env python3
"""Decode first-citation placements, visible backlinks and the complete note graph."""
from __future__ import annotations

import argparse
from pathlib import Path

from check_profile_declarations import validate_claims
from check_rich_inline import page_marked_text
from check_structure_semantics import Document, Ref, ValidationError, element_children, mcr_pages, page_order, require, validate_structure_semantics_pdf
from pdf_layout import mutate

ROOT = Path(__file__).resolve().parents[1]


def validate_footnotes_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    number = dimensions["notes"]
    handbook = bool(dimensions.get("handbook"))
    validate_claims(pdf, wtpdf=bool(dimensions.get("wtpdf")))
    validate_structure_semantics_pdf(pdf, {})
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    visible = {page: dict(page_marked_text(document, page)) for page in pages}
    tree = document.get(int(catalog["StructTreeRoot"]))
    root = tree["K"]
    nodes = logical_nodes(document, root)
    notes = [(ref, element) for ref, element in nodes if element["S"] == "FENote"]
    require(len(notes) == number, "note declarations were omitted or duplicated")
    citations = [(ref, element) for ref, element in nodes if element["S"] == "Link" and "Ref" in element]
    require(len(citations) == number + 1, "citation count changed")
    expected = ["[1]"] if handbook else [f"[N{i}]" for i in range(number)]
    require([marked_text(document, element, visible) for _, element in citations] == expected + [expected[0]], "citation labels or logical order changed")
    declared = list(reversed(expected)) if not handbook else expected
    for i, (ref, note) in enumerate(notes):
        marker = declared[i]
        own_text = " ".join(marked_text(document, note, visible).split())
        require(own_text.startswith(marker + " "), "FENote label or declaration order changed")
        if handbook:
            require("starts when the primary on-call receives a usable alert" in own_text, "handbook note text differs")
        else:
            require(own_text == f"{marker} Information {number - 1 - i} remains on its first citation page.", "scale note text differs")
        if dimensions.get("wtpdf"):
            require(note.get("A") == {"O": "FENote", "NoteType": "Footnote"}, "missing declared FENote subtype")
        else:
            require("A" not in note, "unexpected footnote attribute without a declared extension")
        targets = [(citation, element) for citation, element in citations if marked_text(document, element, visible) == marker]
        require(note.get("Ref") == [citation for citation, _ in targets], "FENote backlink list differs from authored citations")
        first, first_element = targets[0]
        first_page = first_element["Pg"]
        require(mcr_pages(document, int(ref)) == {int(first_page)}, "entire footnote must be painted on the first citation page")
        kids = [kid for kid in element_children(document, note) if isinstance(kid, Ref)]
        require(len(kids) == 1, "FENote must own one visible return link")
        return_link = document.get(int(kids[0]))
        require(return_link["S"] == "Link" and marked_text(document, return_link, visible) == "Return to first citation", "incorrect visible return label")
        return_target = exact_link_action(document, return_link, first, first_page)
        require(return_target[2] == first_page, "backlink geometry and structure resolve to different pages")
        for _, element in targets:
            require(element.get("Ref") == [ref], "citation Ref differs from its authored FENote")
            note_top, marker_bottom, _ = exact_link_action(document, element, ref, first_page)
            if element["Pg"] == first_page:
                require(note_top < marker_bottom, "note must paint below its first citation")
        if handbook:
            require(pages.index(int(first_page)) == 1 and len(pages) == 3, "reserving the note must move the first citation to the second page")
            require(targets[-1][1]["Pg"] == Ref(pages[2]), "repeated citation must remain on the escalation page")


def logical_nodes(document: Document, start: Ref) -> list[tuple[Ref, dict]]:
    result = []
    stack = [start]
    while stack:
        reference = stack.pop()
        element = document.get(int(reference))
        result.append((reference, element))
        stack.extend(kid for kid in reversed(element_children(document, element)) if isinstance(kid, Ref))
    return result


def marked_text(document: Document, element: dict, visible: dict[int, dict[int, str]]) -> str:
    return "".join(visible[int(item["Pg"])][item["MCID"]]
                   for item in element_children(document, element)
                   if isinstance(item, dict) and item.get("Type") == "MCR").strip()


def exact_link_action(document: Document, element: dict, target: Ref, page: Ref) -> tuple[float, float, Ref]:
    references = [kid for kid in element_children(document, element) if isinstance(kid, dict) and kid.get("Type") == "OBJR"]
    require(len(references) == 1, "link must own exactly one widget-free annotation here")
    annotation = document.get(int(references[0]["Obj"]))
    action = annotation["A"]
    require(action["S"] == "GoTo" and action["SD"][0] == target, "link structure destination differs from authored target")
    require(action["D"][0] == page and action["D"][1:] == action["SD"][1:], "structure and geometric destinations disagree")
    return action["D"][3], annotation["Rect"][1], action["D"][0]


def self_test() -> None:
    pdf = (ROOT / "tests/footnotes/handbook.pdf").read_bytes()
    dimensions = {"handbook": 1, "notes": 1}
    validate_footnotes_pdf(pdf, dimensions)
    document = Document(pdf)
    root = document.get(int(document.get(document.root)["StructTreeRoot"]))["K"]
    note_ref, note = next((ref, element) for ref, element in logical_nodes(document, root) if element["S"] == "FENote")
    one, two = note["Ref"]
    full = f"/Ref [{int(one)} 0 R {int(two)} 0 R]".encode()
    cut = f"/Ref [{int(one)} 0 R]".encode()
    wrong = [
        (mutate(pdf, full, cut, scope="objects"), "backlink list"),
        (mutate(pdf, f"/SD [{int(note_ref)} 0 R".encode(), f"/SD [{int(one)} 0 R".encode(), occurrences=None, scope="objects", first_only=True), "structure destination"),
    ]
    for candidate, expected in wrong:
        try:
            validate_footnotes_pdf(candidate, dimensions)
        except ValidationError as error:
            require(expected in str(error), f"unexpected mutation rejection: {error}")
        else:
            raise ValidationError(f"footnote checker accepted mutation: {expected}")
    print("PASS first-citation placement, FENote backlinks and structure destinations")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", required=True)
    parser.parse_args()
    self_test()
