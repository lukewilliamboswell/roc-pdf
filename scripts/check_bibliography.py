#!/usr/bin/env python3
"""Check authored bibliography order, linked citations, and reciprocal Ref arrays."""

import argparse
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text
from check_structure_semantics import (
    Document, PDF17_NAMESPACE, PDF20_NAMESPACE, Ref, check_structure_semantics,
    element_children, page_order, text_string,
)
from pdf_layout import twin

POLICY = "Payments Reliability. Service-level policy, revision 3.2."
CHECKLIST = "Payments Reliability. Recovery checklist, revision 2.4."
LABELS = ["Recovery checklist", "Service-level policy"]
ENTRY_BY_LABEL = dict(zip(LABELS, (CHECKLIST, POLICY)))


@dataclass
class Node:
    number: int
    raw: dict
    text: str
    children: list
    objects: list


def read_graph(pdf: bytes):
    check_structure_semantics(pdf)
    doc = Document(pdf)
    catalog = doc.get(doc.root)
    pages = []
    page_order(doc, int(catalog["Pages"]), pages)
    marked = {page: dict(page_marked_text(doc, page)) for page in pages}
    roles = defaultdict(list)

    def visit(number: int, inherited_page=None) -> Node:
        raw = doc.get(number)
        page = int(raw["Pg"]) if "Pg" in raw else inherited_page
        chunks, nodes, objects = [], [], []
        for child in element_children(doc, raw):
            if isinstance(child, Ref):
                node = visit(int(child), page)
                nodes.append(node)
                chunks.append(node.text)
            elif isinstance(child, int):
                chunks.append(marked[page].get(child, ""))
            elif child["Type"] == "MCR":
                chunks.append(marked[int(child["Pg"])].get(child["MCID"], ""))
            elif child["Type"] == "OBJR":
                objects.append(int(child["Obj"]))
        node = Node(number, raw, "".join(chunks), nodes, objects)
        roles[raw["S"]].append(node)
        return node

    structure = doc.get(int(catalog["StructTreeRoot"]))
    visit(int(structure["K"]))
    return doc, roles


def check(pdf: bytes, dimensions: dict[str, int]):
    doc, roles = read_graph(pdf)
    count = dimensions["bibliography_citations"]
    sections = [node for node in roles["Sect"] if node.raw.get("A") == {"O": "ARIA-1.1", "role": "doc-bibliography"}]
    require(len(sections) == 1, "missing or duplicate ARIA bibliography section")
    section = sections[0]
    require(text_string(doc.get(int(section.raw["NS"]))["NS"]) == PDF20_NAMESPACE, "bibliography section must use the PDF 2.0 namespace")
    require(len(section.children) == 2 and all(node.raw["S"] == "P" and len(node.children) == 1 for node in section.children),
            "bibliography entries lost their authored section")
    entries = [node.children[0] for node in section.children]
    require([node.text for node in entries] == [POLICY, CHECKLIST] and len(roles["BibEntry"]) == 2,
            "bibliography entries lost their explicit order")
    for entry in entries:
        require(entry.raw["S"] == "BibEntry" and text_string(doc.get(int(entry.raw["NS"]))["NS"]) == PDF17_NAMESPACE,
                "bibliography entry must use the PDF 1.7 namespace")

    citations = [node for node in roles["Link"] if "Ref" in node.raw]
    require([node.text for node in citations] == [LABELS[i % 2] for i in range(count)], "citation text or logical order changed")
    by_text = {node.text: node for node in entries}
    backlinks = defaultdict(list)
    for citation in citations:
        target = by_text[ENTRY_BY_LABEL[citation.text]]
        require(citation.raw["Ref"] == [Ref(target.number)], "citation refers to the wrong authored entry")
        require(citation.objects, "citation lost its interactive link annotation")
        for annotation in citation.objects:
            action = doc.get(annotation)["A"]
            require(action["S"] == "GoTo" and int(action["SD"][0]) == target.number,
                    "citation structure destination differs from its authored entry")
            require(int(action["D"][0]) == int(target.raw["Pg"]) and action["SD"][1:] == action["D"][1:],
                    "page and structure destinations differ")
        backlinks[target.number].append(Ref(citation.number))
    for entry in entries:
        require(entry.raw.get("Ref", []) == backlinks[entry.number], "entry lost a backlink or changed citation order")
    return entries, citations


def check_mutations(pdf: bytes, dimensions: dict[str, int]) -> None:
    entries, citations = check(pdf, dimensions)
    first_cites = entries[0].raw["Ref"]
    require(len(first_cites) >= 2, "mutation needs repeated citations")
    ref_array = lambda refs: b"/Ref [" + b" ".join(f"{int(ref)} 0 R".encode() for ref in refs) + b"]"
    wrong_sd = f"/SD [{citations[0].raw['Ref'][0]} 0 R".encode()
    wrong_target = f"/SD [{entries[0].number} 0 R".encode()
    for old, new in [(ref_array(first_cites), ref_array(first_cites[1:])), (wrong_sd, wrong_target)]:
        try:
            check(twin(pdf, old, new), dimensions)
        except ValidationError:
            continue
        raise ValidationError("bibliography oracle accepted a changed graph")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--citations", type=int, default=2)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        root = Path(__file__).resolve().parents[1]
        pdf = (root / "tests/bibliography/graph-20.pdf").read_bytes()
        check_mutations(pdf, {"bibliography_citations": 20})
    elif args.pdf:
        check(args.pdf.read_bytes(), {"bibliography_citations": args.citations})
    else:
        parser.error("select a PDF or --self-test")
    print("PASS bibliography order, section owner, citation targets, and backlinks")


if __name__ == "__main__":
    main()
