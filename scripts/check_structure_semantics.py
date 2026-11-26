#!/usr/bin/env python3
"""Independent structure-semantics checker for roc-pdf tagged output.

It parses the emitted bytes with its own small PDF value parser and derives,
without consulting the Roc package:

* an object-number-independent normalized structure tree (roles, /Lang, /ID,
  /A, /Alt, /E, /ActualText, and ordered MCR/OBJR/child leaves, with pages
  named by page-tree index);
* ParentTree <-> MCID/OBJR agreement in both directions, exactly once, and
  every content-stream MCID owned by exactly one marked-content reference;
* IDTree <-> /ID agreement (a balanced name tree with valid /Limits);
* /Lang well-formedness and inheritance (no redundant /Lang);
* typed /A attribute dictionaries and /Headers targets;
* catalog /ViewerPreferences /DisplayDocTitle true whenever the catalog
  carries a metadata stream, plus /MarkInfo /Marked true and page /Tabs /S;
* parent/child containment, content items, at-most-one children, and the
  first-or-last Caption rule for the roles roc-pdf emits. See ISO/TS 32005
  Table 5 for the containment rules;
* page furniture: every /Artifact <</Type /Pagination /Subtype
  /Header|/Footer|/PageNum>> sequence carries no MCID (so no structure element can
  own it), every page-number artifact's ToUnicode-decoded text that reads
  "N of M" names its own page and the page count, and the per-subtype
  artifact counts match the case dimensions.
* namespaces: only the PDF 2.0 and PDF 1.7 standard structure namespaces
  are declared, and each element is in the namespace that defines its role
  (`Code` and `Quote` in PDF 1.7, every other role in PDF 2.0).
* custom blocks: every `Div` holding only `P` children is counted, and the
  `/Artifact <</Type /Layout>>` sequences a page paints before its first
  marked content (a custom block's panel, painted behind its text) are
  counted, and both counts match the case dimensions.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pdf_layout import LayoutError, twin as layout_twin  # noqa: E402
from check_pdf_structure import (  # noqa: E402
    ValidationError,
    decode_flate,
    indirect_length,
    object_slices,
    require,
    stream_parts,
    validate_xref,
)

ROOT = Path(__file__).resolve().parents[1]

SNAPSHOTS = {
    "nested": ROOT / "tests" / "containers" / "nested.pdf",
    "sections": ROOT / "tests" / "containers" / "sections_10.pdf",
    "lowering": ROOT / "tests" / "containers" / "lowering.pdf",
    "facade": ROOT / "tests" / "pdf_facade" / "pdf_facade.pdf",
    "navigation": ROOT / "tests" / "navigation_facade" / "navigation_facade.pdf",
    "figure": ROOT / "tests" / "pdf_facade" / "image_figure.pdf",
    "table": ROOT / "tests" / "tables" / "spans.pdf",
    "continued_table": ROOT / "tests" / "tables" / "footer_carry.pdf",
    "templates": ROOT / "tests" / "page_templates" / "letter_6.pdf",
    "figures": ROOT / "tests" / "flow_figures" / "report.pdf",
    "figure_sections": ROOT / "tests" / "flow_figures" / "sections_10.pdf",
    "custom_blocks": ROOT / "tests" / "custom_block" / "callouts_10.pdf",
    "custom_defaults": ROOT / "tests" / "custom_block" / "defaults.pdf",
    "inline_roles": ROOT / "tests" / "rich_inline" / "mixed.pdf",
    "empty_cells": ROOT / "tests" / "tables" / "empty_cells_40.pdf",
}


# ---------------------------------------------------------------------------
# Supported ISO/TS 32005:2023 Table 5 edges ("Hn" stands for H1..H6).
# Parent context is checked separately for Part and Div. Grouping-only
# children of Caption, Code and Link are outside the bounded text subset.
# ---------------------------------------------------------------------------
PDF20_NAMESPACE = "http://iso.org/pdf2/ssn"
PDF17_NAMESPACE = "http://iso.org/pdf/ssn"
# These unique PDF 1.7 roles retain that namespace in mixed structure
# trees under ISO/TS 32005 §5.5 and PDF/UA-2 §8.2.4.
PDF17_ROLES = {"Code", "Quote", "TOC", "TOCI", "Index", "Reference"}

INLINE = {"Lbl", "Figure", "Link", "Span", "Em", "Strong", "Code", "Quote"}
ALL_ROLES = {
    "Document", "DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "LI", "Lbl",
    "LBody", "Figure", "Caption", "Link", "Span", "Em", "Strong", "Code", "Quote", "Table", "THead",
    "TBody", "TFoot", "TR", "TH", "TD", "TOC", "TOCI", "Form", "Index", "Reference", "FENote",
}
DOCUMENT_CHILDREN = {"Document", "DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "Figure", "Link", "Code", "Table", "TOC", "Form", "FENote"}
GROUPING_WRAPPERS = {"Part", "Div"}
# ISO/TS 32005 Table 5 lists these supported children in the Part row.
PART_CHILDREN = DOCUMENT_CHILDREN | {"Caption", "Lbl", "TOCI"}
CELL_CHILDREN = {"Sect", "Div", "H", "Hn", "P", "L", "Table"} | INLINE
MAY_CONTAIN: dict[str, set[str]] = {
    "Document": DOCUMENT_CHILDREN | {"Index"},
    "DocumentFragment": DOCUMENT_CHILDREN,
    "Part": set(ALL_ROLES),
    "Div": set(ALL_ROLES),
    "Sect": {"DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "Lbl", "Figure", "Caption", "Link", "Code", "Table", "TOC"},
    "Title": {"Part", "Div", "P", "L", "Caption", "Table"} | INLINE,
    "H": {"Sect"} | INLINE,
    "Hn": {"Sect"} | INLINE,
    "P": {"L", "Table", "Reference"} | INLINE,
    "L": {"L", "LI", "Caption"},
    "LI": {"Div", "Lbl", "LBody"},
    "Lbl": INLINE - {"Lbl"},
    "Form": {"Lbl"},
    "FENote": {"Link"},
    "LBody": {"Part", "Sect", "Div", "H", "Hn", "P", "L", "Caption", "Table"} | (INLINE - {"Lbl"}),
    "Figure": {"Part", "Sect", "Div", "H", "Hn", "P", "L", "Caption", "Table"} | INLINE,
    "Caption": {"Part", "Sect", "Div", "H", "Hn", "P", "L", "Table"} | INLINE,
    "Link": {"Sect", "Div"} | (INLINE - {"Link"}),
    "Span": set(INLINE),
    "Em": set(INLINE),
    "Strong": set(INLINE),
    "Code": {"Part", "Div", "Link", "Span", "Em", "Strong"},
    "Quote": set(INLINE),
    "Table": {"Caption", "THead", "TBody", "TFoot", "TR"},
    "THead": {"TR"},
    "TBody": {"TR"},
    "TFoot": {"TR"},
    "TR": {"TH", "TD"},
    "TH": set(CELL_CHILDREN),
    "TD": set(CELL_CHILDREN),
    "TOC": {"Part", "Caption", "TOC", "TOCI"},
    "TOCI": {"Div", "P", "Lbl", "TOC"},
    "Index": {"P"},
    "Reference": {"Link"},
}
NO_CONTENT_ITEMS = {"Document", "DocumentFragment", "Sect", "L", "LI", "Table", "THead", "TBody", "TFoot", "TR", "TOC", "TOCI"}
AT_MOST_ONE: dict[str, set[str]] = {
    "Document": {"H"}, "DocumentFragment": {"H"}, "Sect": {"H"}, "Caption": {"H"}, "TH": {"H"}, "TD": {"H"},
    "LBody": {"H", "Caption"}, "Figure": {"H", "Caption"}, "H": {"Sect"}, "Hn": {"Sect"},
    "Title": {"Caption"}, "L": {"Caption"},
    "Table": {"Caption", "THead", "TFoot"},
    "TOC": {"Caption"},
}
TABLE_ATTRIBUTES = {"ColSpan", "Headers", "O", "RowSpan", "Scope", "Summary"}
LIST_NUMBERING = {
    "None", "Unordered", "Description", "Disc", "Circle", "Square", "Ordered", "Decimal", "UpperRoman",
    "LowerRoman", "UpperAlpha", "LowerAlpha",
}
# ISO 32000-2 14.9.2.2 refers to the RFC 5646 language-tag syntax.
LANGUAGE_TAG = re.compile(
    r"(?:[a-z]{2,3}(?:-[a-z]{3}){0,3}|[a-z]{4,8})"
    r"(?:-[a-z]{4})?(?:-(?:[a-z]{2}|[0-9]{3}))?"
    r"(?P<variants>(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*)"
    r"(?P<extensions>(?:-[0-9a-wy-z](?:-[a-z0-9]{2,8})+)*)"
    r"(?:-x(?:-[a-z0-9]{1,8})+)?"
    r"|x(?:-[a-z0-9]{1,8})+"
    r"|en-gb-oed"
    r"|i-(?:ami|bnn|default|enochian|hak|klingon|lux|mingo|navajo|pwn|tao|tay|tsu)"
    r"|sgn-(?:be-(?:fr|nl)|ch-de)",
    re.ASCII | re.IGNORECASE,
)


def language_tag_valid(tag: str) -> bool:
    shape = LANGUAGE_TAG.fullmatch(tag)
    if shape is None:
        return False
    variants = (shape["variants"] or "").lower().split("-")[1:]
    extension_parts = (shape["extensions"] or "").lower().split("-")[1:]
    singletons = [part for part in extension_parts if len(part) == 1]
    return len(set(variants)) == len(variants) and len(set(singletons)) == len(singletons)


def table_role(role: str) -> str:
    return "Hn" if re.fullmatch(r"H[1-6]", role) else role


# ---------------------------------------------------------------------------
# A small PDF value parser (dictionaries, arrays, names, strings, numbers,
# booleans, null, and indirect references).
# ---------------------------------------------------------------------------
class Name(str):
    pass


class Ref(int):
    pass


DELIMITERS = b"()<>[]{}/%"
WHITESPACE = b" \t\r\n\f\x00"


class Parser:
    """PDF value parser. Object dictionaries must use the serializer's
    canonical (sorted) key order; content-stream property lists, which the
    package writes as fixed literals such as `<</Type /Pagination /Subtype
    /Header>>`, are parsed with `canonical=False`."""

    def __init__(self, data: bytes, canonical: bool = True):
        self.data = data
        self.at = 0
        self.canonical = canonical

    def skip(self) -> None:
        while self.at < len(self.data) and self.data[self.at] in WHITESPACE:
            self.at += 1

    def value(self):
        self.skip()
        data = self.data
        require(self.at < len(data), "unexpected end of PDF value")
        if data.startswith(b"<<", self.at):
            self.at += 2
            result: dict[str, object] = {}
            previous = None
            while True:
                self.skip()
                if data.startswith(b">>", self.at):
                    self.at += 2
                    return result
                key = self.value()
                require(isinstance(key, Name), "dictionary key is not a name")
                require(not self.canonical or previous is None or str(previous).encode("latin-1") < str(key).encode("latin-1"), f"dictionary keys not in canonical order at /{key}")
                require(key not in result, f"duplicate dictionary key /{key}")
                previous = key
                result[key] = self.value()
        if data[self.at] == ord("["):
            self.at += 1
            items = []
            while True:
                self.skip()
                if data[self.at] == ord("]"):
                    self.at += 1
                    return items
                items.append(self.value())
        if data[self.at] == ord("<"):
            end = data.index(b">", self.at)
            text = data[self.at + 1 : end].decode("ascii")
            require(re.fullmatch(r"[0-9A-F]*", text) is not None and len(text) % 2 == 0, "malformed hex string")
            self.at = end + 1
            return bytes.fromhex(text)
        if data[self.at] == ord("("):
            depth = 0
            out = bytearray()
            self.at += 1
            while True:
                byte = data[self.at]
                if byte == ord("\\"):
                    escaped = data[self.at + 1 : self.at + 4]
                    if re.fullmatch(rb"[0-7]{3}", escaped) is not None:
                        out.append(int(escaped, 8))
                        self.at += 4
                    else:
                        out.append(data[self.at + 1])
                        self.at += 2
                    continue
                if byte == ord("("):
                    depth += 1
                elif byte == ord(")"):
                    if depth == 0:
                        self.at += 1
                        return bytes(out)
                    depth -= 1
                out.append(byte)
                self.at += 1
        if data[self.at] == ord("/"):
            start = self.at + 1
            end = start
            while end < len(data) and data[end] not in WHITESPACE and data[end] not in DELIMITERS:
                end += 1
            self.at = end
            return Name(data[start:end].decode("latin-1"))
        match = re.compile(rb"([+-]?[0-9]+(?:\.[0-9]*)?)").match(data, self.at)
        if match is not None:
            reference = re.compile(rb"([0-9]+) 0 R").match(data, self.at)
            if reference is not None:
                self.at = reference.end()
                return Ref(int(reference.group(1)))
            self.at = match.end()
            text = match.group(1)
            return float(text) if b"." in text else int(text)
        for keyword, value in ((b"true", True), (b"false", False), (b"null", None)):
            if data.startswith(keyword, self.at):
                self.at += len(keyword)
                return value
        raise ValidationError(f"unparseable PDF value at {data[self.at:self.at + 20]!r}")


def parse_object(body: bytes):
    parser = Parser(body)
    value = parser.value()
    parser.skip()
    rest = body[parser.at :]
    require(rest.startswith(b"endobj") or rest.startswith(b"stream\n"), "object has trailing syntax")
    return value


def text_string(value) -> str:
    require(isinstance(value, bytes), "expected a text string")
    if value.startswith(b"\xfe\xff"):
        return value[2:].decode("utf-16-be")
    return value.decode("latin-1")


class Document:
    def __init__(self, pdf: bytes):
        require(pdf.startswith(b"%PDF-2.0\n"), "missing PDF 2.0 header")
        start = re.search(rb"startxref\n(\d+)\n%%EOF\n$", pdf)
        require(start is not None, "missing startxref")
        offset = int(start.group(1))
        self.offsets, self.bodies = object_slices(pdf)
        xref = next(number for number, value in self.offsets.items() if value == offset)
        self.root, _ = validate_xref(pdf, self.offsets, self.bodies, xref, offset)
        self.values: dict[int, object] = {}

    def get(self, number: int):
        if number not in self.values:
            require(number in self.bodies, f"missing object {number}")
            self.values[number] = parse_object(self.bodies[number])
        return self.values[number]

    def stream(self, number: int) -> bytes:
        body = self.bodies[number]
        dictionary = self.get(number)
        require(isinstance(dictionary, dict), "stream object is not a dictionary")
        length = indirect_length(self.bodies, int(dictionary["Length"]))
        _, encoded = stream_parts(body, length)
        if dictionary.get("Filter") == "FlateDecode":
            return decode_flate(encoded, number)
        require("Filter" not in dictionary, "unsupported content filter")
        return encoded


def page_order(document: Document, node: int, out: list[int], depth: int = 0) -> None:
    require(depth < 32, "page tree too deep")
    value = document.get(node)
    if value.get("Type") == "Page":
        out.append(node)
        return
    require(value.get("Type") == "Pages", "page tree node is neither Pages nor Page")
    for kid in value["Kids"]:
        page_order(document, int(kid), out, depth + 1)


def walk_name_tree(document: Document, node: int, depth: int = 0) -> list[tuple[bytes, int]]:
    require(depth < 16, "IDTree too deep")
    value = document.get(node)
    entries: list[tuple[bytes, int]] = []
    if "Kids" in value:
        require("Names" not in value, "IDTree node has both /Kids and /Names")
        for kid in value["Kids"]:
            require(isinstance(kid, Ref), "IDTree /Kids entry is not an indirect reference")
            entries.extend(walk_name_tree(document, int(kid), depth + 1))
    else:
        names = value.get("Names")
        require(isinstance(names, list) and len(names) % 2 == 0 and names, "IDTree leaf has no /Names pairs")
        for index in range(0, len(names), 2):
            require(isinstance(names[index], bytes) and isinstance(names[index + 1], Ref), "IDTree pair is not (string, reference)")
            entries.append((names[index], int(names[index + 1])))
    if depth > 0:
        limits = value.get("Limits")
        require(isinstance(limits, list) and len(limits) == 2, "non-root IDTree node lacks /Limits")
        require(entries[0][0] == limits[0] and entries[-1][0] == limits[1], "IDTree /Limits disagree with the node's keys")
    else:
        require("Limits" not in value, "IDTree root carries /Limits")
    return entries


def mcids_in(content: bytes) -> list[tuple[str, int]]:
    """Marked-content sequences with an MCID, as (tag, mcid) in stream order."""
    found = [
        (match.group(1).decode("latin-1"), int(match.group(2)))
        for match in re.finditer(rb"/([A-Za-z0-9]+) <</MCID ([0-9]+)>> BDC", content)
    ]
    require(len(found) == content.count(b"/MCID"), "an MCID appears outside a canonical BDC property list")
    return found


def containment_scope(ancestors: tuple[str, ...]) -> tuple[str, bool]:
    """Walk through enclosing Div and Part to the effective role."""
    through_part = False
    for role in reversed(ancestors):
        if role not in GROUPING_WRAPPERS:
            return role, through_part
        through_part |= role == "Part"
    raise ValidationError("a structure grouping has no containing role")


def check_structure_semantics(pdf: bytes, dimensions: dict[str, int] | None = None) -> list[str]:
    dimensions = dimensions or {}
    document = Document(pdf)
    catalog = document.get(document.root)
    require(catalog.get("Type") == "Catalog", "root is not a Catalog")
    require(catalog.get("MarkInfo") == {"Marked": True}, "catalog /MarkInfo is not << /Marked true >>")
    if "Metadata" in catalog:
        require(catalog.get("ViewerPreferences") == {"DisplayDocTitle": True}, "a document with a metadata title lacks /ViewerPreferences << /DisplayDocTitle true >>")
    catalog_language = text_string(catalog["Lang"]) if "Lang" in catalog else None
    if catalog_language is not None:
        require(language_tag_valid(catalog_language), "catalog /Lang is not a language tag")

    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    page_index = {page: index for index, page in enumerate(pages)}

    tree_root_number = int(catalog["StructTreeRoot"])
    tree_root = document.get(tree_root_number)
    require(tree_root.get("Type") == "StructTreeRoot", "catalog /StructTreeRoot is not a StructTreeRoot")
    require("RoleMap" not in tree_root, "an unexpected /RoleMap is present")
    kids = tree_root["K"]
    root_element = kids if isinstance(kids, Ref) else None
    require(root_element is not None, "StructTreeRoot /K is not a single Document reference")
    namespaces = [int(value) for value in tree_root["Namespaces"]]
    require(namespaces, "StructTreeRoot has no /Namespaces")
    namespace_uris: dict[int, str] = {}
    for namespace in namespaces:
        value = document.get(namespace)
        require(value.get("Type") == "Namespace", "namespace is not a Namespace dictionary")
        uri = text_string(value["NS"])
        require(uri in (PDF20_NAMESPACE, PDF17_NAMESPACE), f"namespace {uri!r} is not a standard structure namespace")
        require(uri not in namespace_uris.values(), f"namespace {uri!r} is declared twice")
        namespace_uris[namespace] = uri
    require(PDF20_NAMESPACE in namespace_uris.values(), "the PDF 2.0 namespace is not declared")

    lines: list[str] = []
    mcr_owner: dict[tuple[int, int], int] = {}
    objr_owner: dict[int, int] = {}
    identifiers: dict[bytes, int] = {}
    visited: set[int] = set()
    labelled_items: set[int] = set()
    contents_targets: list[int] = []

    def walk(number: int, parent: int, inherited: str | None, ancestors: tuple[str, ...]) -> str:
        require(len(ancestors) < 64, "structure tree too deep")
        require(number not in visited, f"structure element {number} is reachable twice")
        visited.add(number)
        element = document.get(number)
        require(element.get("Type", "StructElem") == "StructElem" and "S" in element, f"object {number} is not a StructElem")
        parent_ref = element.get("P")
        require(isinstance(parent_ref, Ref) and int(parent_ref) == parent, f"structure element {number} /P does not name its parent")
        require(int(element["NS"]) in namespaces, "structure element namespace is not declared")
        role = str(element["S"])
        expected_namespace = PDF17_NAMESPACE if role in PDF17_ROLES else PDF20_NAMESPACE
        require(namespace_uris[int(element["NS"])] == expected_namespace, f"/{role} is not in the namespace that defines it ({expected_namespace})")
        row = table_role(role)
        require(row in MAY_CONTAIN, f"unsupported structure role /{role}")
        if not ancestors:
            require(role == "Document", "the structure root is not Document")
        else:
            containment, through_part = containment_scope(ancestors)
            allowed = row in MAY_CONTAIN[table_role(containment)]
            require(allowed and (not through_part or row in PART_CHILDREN), f"/{ancestors[-1]} may not contain /{role} under /{containment}")
            require(role != "Document", "Document is nested")
        facts: list[str] = []
        language = inherited
        if "Lang" in element:
            tag = text_string(element["Lang"])
            require(language_tag_valid(tag), f"structure /Lang {tag!r} is not a language tag")
            require(tag != inherited, f"structure /Lang {tag!r} repeats its inherited language")
            facts.append(f"Lang={tag}")
            language = tag
        for key in ("Alt", "E", "ActualText"):
            if key in element:
                facts.append(f"{key}={text_string(element[key])!r}")
        if role in {"TOCI", "Reference"}:
            refs = element.get("Ref")
            require(isinstance(refs, list) and len(refs) == 1 and isinstance(refs[0], Ref), f"{role} must have one structure target")
            contents_targets.append(int(refs[0]))
        if role == "Figure":
            require("Alt" in element or "ActualText" in element, "Figure has neither /Alt nor /ActualText")
        if "ID" in element:
            identifier = element["ID"]
            require(isinstance(identifier, bytes) and identifier, "structure /ID is not a non-empty byte string")
            require(identifier not in identifiers, f"duplicate structure /ID {identifier!r}")
            identifiers[identifier] = number
            facts.append(f"ID={identifier.decode('latin-1')}")
        if "A" in element:
            facts.append("A=" + normalize_attributes(element["A"], role))
        if "Pg" in element:
            require(int(element["Pg"]) in page_index, "structure element /Pg is not a page")
        children = element_children(document, element)
        path = (*ancestors, role)
        containment, _ = containment_scope(path)
        leaves: list[str] = []
        limited_seen: set[str] = set()
        child_roles: list[str] = []
        for child in children:
            if isinstance(child, Ref):
                child_role = str(document.get(int(child))["S"])
                if child_role == "Artifact":
                    leaves.append("Artifact")
                    continue
                child_row = table_role(child_role)
                if child_row in AT_MOST_ONE.get(table_role(containment), set()):
                    require(child_row not in limited_seen, f"/{role} contains more than one /{child_role}")
                    limited_seen.add(child_row)
                child_roles.append(child_role)
                leaves.append(walk(int(child), number, language, path))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                require(role not in GROUPING_WRAPPERS and role not in NO_CONTENT_ITEMS, f"/{role} owns a content item")
                # The writer identifies its one ordinary page stream by /Pg.
                require("Stm" not in child and "StmOwn" not in child, "a page-content MCR names an additional stream or owner")
                page = int(child["Pg"])
                require(page in page_index, "MCR /Pg is not a page")
                key = (page, int(child["MCID"]))
                require(key not in mcr_owner, f"MCID {key[1]} on page {page_index[page]} is referenced twice")
                mcr_owner[key] = number
                leaves.append(f"mcid p{page_index[page]}:{key[1]}")
            elif isinstance(child, dict) and child.get("Type") == "OBJR":
                require(role not in GROUPING_WRAPPERS and role not in NO_CONTENT_ITEMS, f"/{role} owns a content item")
                annotation = int(child["Obj"])
                require(annotation not in objr_owner, "an annotation is referenced by two OBJRs")
                objr_owner[annotation] = number
                annotation_value = document.get(annotation)
                annots = document.get(int(child["Pg"])).get("Annots", [])
                require(Ref(annotation) in annots, "OBJR /Pg is not the page that lists the annotation")
                leaves.append(f"objr {annotation_value.get('Subtype')} p{page_index[int(child['Pg'])]}")
            else:
                raise ValidationError(f"structure element {number} has an unsupported /K item")
        if "Caption" in child_roles:
            positions = [index for index, value in enumerate(child_roles) if value == "Caption"]
            require(all(index in (0, len(child_roles) - 1) for index in positions), f"/{role} Caption is neither first nor last")
        if role == "LI" and "Lbl" in child_roles:
            labelled_items.add(number)
        if role == "L" and any(isinstance(child, Ref) and int(child) in labelled_items for child in children):
            # PDF/UA-2 8.2.5.25: a list whose items carry labels declares its
            # numbering; /None would leave the labels unexplained.
            numbering = [value.get("ListNumbering") for value in (element.get("A") if isinstance(element.get("A"), list) else [element.get("A")]) if isinstance(value, dict) and value.get("O") == "List"]
            require(numbering and numbering[0] not in (None, "None"), "an L with labelled items lacks a /ListNumbering other than /None")
        label = " ".join([role] + facts)
        return label + ("" if not leaves else " [" + ", ".join(leaves) + "]")

    lines.append(walk(int(root_element), tree_root_number, catalog_language, ()))
    for target in contents_targets:
        require(target in visited and table_role(str(document.get(target)["S"])) in ("P", "Hn"),
                "contents reference does not name a reachable destination")

    # ParentTree <-> MCR/OBJR, exactly once in both directions.
    parent_tree = document.get(int(tree_root["ParentTree"]))
    nums = parent_tree.get("Nums")
    require(isinstance(nums, list) and len(nums) % 2 == 0, "ParentTree is not a flat /Nums number tree")
    rows: dict[int, object] = {}
    previous_key = -1
    for index in range(0, len(nums), 2):
        key = nums[index]
        require(isinstance(key, int) and key > previous_key, "ParentTree keys are not strictly ascending")
        previous_key = key
        rows[key] = nums[index + 1]
    require(tree_root["ParentTreeNextKey"] == previous_key + 1, "ParentTreeNextKey is not one past the last key")
    seen_mcr: set[tuple[int, int]] = set()
    for page in pages:
        page_value = document.get(page)
        require(page_value.get("Tabs") == "S", "page /Tabs is not /S")
        content = document.stream(int(page_value["Contents"]))
        marked = mcids_in(content)
        if not marked:
            continue
        key = page_value.get("StructParents")
        require(isinstance(key, int) and key in rows, "a page with MCIDs has no ParentTree row")
        row = rows[key]
        require(isinstance(row, list), "a page ParentTree row is not an array")
        require(sorted(mcid for _, mcid in marked) == list(range(len(row))), "page MCIDs are not dense 0..n-1 or repeat")
        for _tag, mcid in marked:
            owner = mcr_owner.get((page, mcid))
            require(owner is not None, f"MCID {mcid} on page {page_index[page]} has no structure reference")
            require(int(row[mcid]) == owner, f"ParentTree row disagrees with the owner of MCID {mcid}")
            seen_mcr.add((page, mcid))
    require(seen_mcr == set(mcr_owner), "a structure MCR names an MCID absent from its page content")
    for annotation, owner in objr_owner.items():
        key = document.get(annotation).get("StructParent")
        require(isinstance(key, int) and key in rows, "an OBJR annotation has no ParentTree row")
        require(isinstance(rows[key], Ref) and int(rows[key]) == owner, "annotation ParentTree row disagrees with its OBJR owner")
    used_rows = {document.get(page).get("StructParents") for page in pages} | {document.get(a).get("StructParent") for a in objr_owner}
    require(set(rows) <= used_rows, "a ParentTree row is referenced by no page or annotation")

    # IDTree <-> /ID.
    if "IDTree" in tree_root:
        entries = walk_name_tree(document, int(tree_root["IDTree"]))
        keys = [key for key, _ in entries]
        require(keys == sorted(keys) and len(set(keys)) == len(keys), "IDTree keys are not strictly ascending")
        require(dict(entries) == identifiers, "IDTree entries disagree with structure /ID values")
    else:
        require(not identifiers, "structure /ID values exist without an IDTree")
    for line in lines:
        for match in re.finditer(r"Headers=\[([^\]]*)\]", line):
            for target in filter(None, match.group(1).split(",")):
                require(target.encode("latin-1") in identifiers, f"/Headers names unknown element identifier {target}")

    check_tables(document, visited, identifiers, pages, page_index, dimensions)
    check_furniture(furniture_by_page(document, pages), dimensions)
    check_figures(document, visited, pages, page_index, dimensions)
    check_custom_blocks(document, visited, pages, dimensions)

    expected_elements = dimensions.get("structure_elements")
    if expected_elements is not None:
        require(len(visited) == expected_elements, f"expected {expected_elements} structure elements, found {len(visited)}")
    expected_ids = dimensions.get("element_identifiers")
    if expected_ids is not None:
        require(len(identifiers) == expected_ids, "element identifier count differs")
    return lines


FURNITURE = re.compile(rb"/Artifact <</Type /Pagination /Subtype /(Header|Footer|PageNum)>> BDC\n(.*?)EMC\n", re.S)
FURNITURE_KINDS = {"Header": "header_artifacts", "Footer": "footer_artifacts", "PageNum": "page_number_artifacts"}


def furniture_by_page(document: Document, pages: list[int]) -> list[list[tuple[str, bytes, str]]]:
    """Each page's furniture artifacts as (subtype, marked body, decoded text)."""
    from check_rich_inline import to_unicode  # noqa: PLC0415 (the text checker imports this module)

    decoded: list[list[tuple[str, bytes, str]]] = []
    decoders: dict[int, dict[int, str]] = {}
    for page in pages:
        page_value = document.get(page)
        fonts = page_value.get("Resources", {}).get("Font", {})
        content = document.stream(int(page_value["Contents"]))
        items: list[tuple[str, bytes, str]] = []
        for match in FURNITURE.finditer(content):
            body = match.group(2)
            text: list[str] = []
            current: dict[int, str] | None = None
            for token in re.finditer(rb"/([A-Za-z0-9_]+) [0-9.]+ Tf|<([0-9A-Fa-f]*)> Tj|\[((?:<[0-9A-Fa-f]*>|-?[0-9.]+| )*)\] TJ", body):
                if token.group(1) is not None:
                    name = token.group(1).decode("latin-1")
                    require(name in fonts, f"furniture selects an undeclared font /{name}")
                    number = int(fonts[name])
                    if number not in decoders:
                        decoders[number] = to_unicode(document, number)
                    current = decoders[number]
                else:
                    require(current is not None, "furniture text is shown before a font is selected")
                    hex_text = token.group(2) if token.group(2) is not None else b"".join(re.findall(rb"<([0-9A-Fa-f]*)>", token.group(3)))
                    string = bytes.fromhex(hex_text.decode())
                    for index in range(0, len(string), 2):
                        cid = int.from_bytes(string[index : index + 2], "big")
                        require(cid in current, f"furniture CID {cid} has no ToUnicode mapping")
                        text.append(current[cid])
            items.append((match.group(1).decode("latin-1"), body, "".join(text)))
        decoded.append(items)
    return decoded


def check_furniture(pages: list[list[tuple[str, bytes, str]]], dimensions: dict[str, int]) -> None:
    """Page furniture is artifact content: no MCID, correct page fields, and
    the expected number of header, footer, and page-number artifacts."""
    counts = {key: 0 for key in FURNITURE_KINDS.values()}
    for index, items in enumerate(pages):
        for subtype, body, text in items:
            require(b"/MCID" not in body, f"{subtype} furniture on page {index} carries an MCID")
            counts[FURNITURE_KINDS[subtype]] += 1
            if subtype == "PageNum":
                require(text, f"a page-number artifact on page {index} shows no text")
                field = re.search(r"([0-9]+) of ([0-9]+)", text)
                if field is not None:
                    require(int(field.group(1)) == index + 1, f"page {index + 1} shows page number {field.group(1)}")
                    require(int(field.group(2)) == len(pages), f"page {index + 1} shows a total of {field.group(2)}, not {len(pages)}")
    for key, count in counts.items():
        expected = dimensions.get(key)
        if expected is not None:
            require(count == expected, f"expected {expected} {key.replace('_', ' ')}, found {count}")


LAYOUT_ARTIFACT = re.compile(rb"/Artifact <</Type /Layout>> BDC\n")
MARKED_FIGURE = re.compile(rb"/[A-Za-z0-9]+ <</MCID ([0-9]+)>> BDC\nq\n([-0-9.]+) 0 0 ([-0-9.]+) [-0-9.]+ [-0-9.]+ cm\n")


def check_figures(document: Document, visited: set[int], pages: list[int], page_index: dict[int, int], dimensions: dict[str, int]) -> None:
    """Independent figure and decoration checks, derived from the bytes:

    - every Figure has a non-empty /Alt and owns its drawing MCID and its
      optional label text MCIDs on the same page;
    - a Caption beside a Figure is the last child of a Sect whose children
      are exactly that Figure and Caption, so the caption is exposed
      independently of the figure's /Alt;
    - each Figure's marked content begins with its drawing's uniform scale
      (`s 0 0 s x y cm`), and the counts of figures, captioned figures,
      scaled figures (s != 1), and in-flow `/Artifact <</Type /Layout>>`
      sequences (table rules and decorations) equal the case dimensions.
    """
    figures = 0
    captioned = 0
    scaled = 0
    drawing_marks: dict[int, dict[int, tuple[bytes, bytes]]] = {}
    text_marks: dict[int, set[int]] = {}
    for number in sorted(visited):
        element = document.get(number)
        role = str(element["S"])
        children = element_children(document, element)
        child_roles = [str(document.get(int(child))["S"]) if isinstance(child, Ref) else None for child in children]
        if role == "Figure":
            figures += 1
            require(isinstance(element.get("Alt"), bytes) and text_string(element["Alt"]).strip(), "a Figure has an empty /Alt")
            marks = [child for child in children if isinstance(child, dict) and child.get("Type") == "MCR"]
            require(marks and len(marks) == len(children), "a facade Figure must directly own its drawing and label sequences")
            page = int(marks[0]["Pg"])
            if page not in drawing_marks:
                content = document.stream(int(document.get(page)["Contents"]))
                drawing_marks[page] = {int(match[1]): (match[2], match[3]) for match in MARKED_FIGURE.finditer(content)}
                text_marks[page] = {
                    int(match[1]) for match in re.finditer(rb"/[A-Za-z0-9]+ <</MCID (\d+)>> BDC\n(.*?)\nEMC\n", content, re.S)
                    if b"\nBT\n" in match[2]
                }
            drawing = int(marks[0]["MCID"])
            require(drawing in drawing_marks[page], f"the Figure's first MCID on page {page_index[page]} does not begin with its drawing's placement")
            for label in marks[1:]:
                require(int(label["Pg"]) == page and int(label["MCID"]) in text_marks[page], "a Figure label must be a text sequence on its drawing's page")
            horizontal, vertical = drawing_marks[page][drawing]
            require(horizontal == vertical and 0 < float(horizontal) <= 1, "a Figure's drawing is not scaled uniformly by at most 1")
            if float(horizontal) != 1:
                scaled += 1
        if "Caption" in child_roles and "Figure" in child_roles:
            require(role == "Sect" and child_roles == ["Figure", "Caption"], f"a figure caption is not the last child of a Sect holding only its Figure (found /{role} {child_roles})")
            caption = document.get(int(children[1]))
            caption_children = [str(document.get(int(child))["S"]) for child in element_children(document, caption) if isinstance(child, Ref)]
            require(caption_children == ["P"], "a figure Caption does not hold one P")
            captioned += 1
    layout = sum(len(LAYOUT_ARTIFACT.findall(document.stream(int(document.get(page)["Contents"])))) for page in pages)
    for key, count in (("figure_nodes", figures), ("captioned_figures", captioned), ("scaled_figures", scaled), ("layout_artifacts", layout)):
        expected = dimensions.get(key)
        if expected is not None:
            require(count == expected, f"expected {expected} {key.replace('_', ' ')}, found {count}")


MCID_BDC = re.compile(rb"<</MCID \d+>> BDC")


def check_custom_blocks(document: Document, visited: set[int], pages: list[int], dimensions: dict[str, int]) -> None:
    """Custom-block checks, derived from the bytes: the number of `Div`
    elements whose children are one or more `P` elements only, and the
    number of `/Artifact <</Type /Layout>>` sequences each page paints
    before its first marked content (an underlay: a custom block's panel
    behind its text). Both counts must equal the case dimensions.
    """
    paragraph_divs = 0
    for number in sorted(visited):
        element = document.get(number)
        if str(element["S"]) != "Div":
            continue
        children = element_children(document, element)
        roles = [str(document.get(int(child))["S"]) if isinstance(child, Ref) else None for child in children]
        if roles and all(role == "P" for role in roles):
            paragraph_divs += 1
    underlays = 0
    for page in pages:
        content = document.stream(int(document.get(page)["Contents"]))
        first = MCID_BDC.search(content)
        underlays += len(LAYOUT_ARTIFACT.findall(content[: first.start()] if first else content))
    for key, count in (("paragraph_divs", paragraph_divs), ("underlays", underlays)):
        expected = dimensions.get(key)
        if expected is not None:
            require(count == expected, f"expected {expected} {key.replace('_', ' ')}, found {count}")

    inset_delta = dimensions.get("custom_inset_delta")
    if inset_delta is not None:
        # The defaults fixture has one line in each of four custom blocks:
        # +8 pt, omitted, explicit zero, and both defaults. Inspect the
        # emitted transforms, independently of the Roc geometry planner.
        offsets = []
        for page in pages:
            content = document.stream(int(document.get(page)["Contents"]))
            offsets.extend(float(match.group(1)) for match in re.finditer(
                rb"<</MCID \d+>> BDC\s+q\s+1 0 0 1 (-?[0-9.]+) -?[0-9.]+ cm", content
            ))
        require(len(offsets) == 4, f"expected four custom-block text origins, found {offsets}")
        origin = dimensions.get("custom_origin_x")
        require(origin is not None, "custom inset geometry needs its body-margin origin")
        require(all(offset == origin for offset in offsets[1:]), f"zero/default insets must start at body margin {origin}, found {offsets}")
        require(offsets[0] - offsets[1] == inset_delta, f"expected custom inset offset {inset_delta}, found {offsets}")


def table_attributes(element: dict) -> dict:
    values = element.get("A")
    for dictionary in values if isinstance(values, list) else [values]:
        if isinstance(dictionary, dict) and dictionary.get("O") == "Table":
            return dictionary
    return {}


def element_children(document: Document, element: dict) -> list:
    """The element's /K kids with every bare integer MCID expanded to the
    marked-content reference it abbreviates: an MCR on the element's /Pg
    (ISO 32000-2 14.7.5.2)."""
    children = element.get("K", [])
    children = children if isinstance(children, list) else [children]
    expanded = []
    for child in children:
        if isinstance(child, int) and not isinstance(child, (bool, Ref)):
            require("Pg" in element, "a bare MCID kid needs the element's /Pg")
            expanded.append({"MCID": child, "Pg": element["Pg"], "Type": "MCR"})
        else:
            expanded.append(child)
    return expanded


def mcr_pages(document: Document, number: int) -> set[int]:
    """Pages of every MCR in the subtree of structure element `number`."""
    found: set[int] = set()
    stack = [number]
    while stack:
        element = document.get(stack.pop())
        for child in element_children(document, element):
            if isinstance(child, Ref):
                stack.append(int(child))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                found.add(int(child["Pg"]))
    return found


def check_scoped_table_headers(document: Document, rows: list[int]) -> None:
    """Check each facade cell's explicit headers against the grid and scopes."""
    column_headers: dict[int, set[bytes | None]] = {}
    for row in rows:
        cells = []
        column = 0
        for ref in element_children(document, document.get(row)):
            require(isinstance(ref, Ref), "facade table row contains a non-cell item")
            cell = document.get(int(ref))
            attributes = table_attributes(cell)
            if cell["S"] == "TH":
                require(attributes.get("Scope") in ("Row", "Column", "Both"), "a TH lacks valid /Scope")
            end = column + attributes.get("ColSpan", 1)
            cells.append((cell, attributes, range(column, end)))
            column = end

        row_headers = {
            cell.get("ID")
            for cell, attributes, _ in cells
            if cell["S"] == "TH" and attributes["Scope"] in ("Row", "Both")
        }
        preceding_row_headers: set[bytes | None] = set()
        for cell, attributes, columns in cells:
            is_header = cell["S"] == "TH"
            expected = (preceding_row_headers if is_header else row_headers).copy()
            for column in columns:
                expected.update(column_headers.get(column, ()))
            require(None not in expected, "a scoped header lacks its referenced /ID")
            actual = attributes.get("Headers", [])
            role = "header" if is_header else "data"
            require(
                set(actual) == expected and len(actual) == len(expected),
                f"facade {role} cell /Headers disagrees with its scoped table headers",
            )
            if is_header and attributes["Scope"] in ("Row", "Both"):
                preceding_row_headers.add(cell.get("ID"))

        for cell, attributes, columns in cells:
            if cell["S"] == "TH" and attributes["Scope"] in ("Column", "Both"):
                for column in columns:
                    column_headers.setdefault(column, set()).add(cell.get("ID"))


def check_table_grid(document: Document, row_groups: list[list[int]]) -> None:
    """Expand rectangles independently of the writer's track-cursor algorithm."""
    expected_width = None
    occupied_tracks = 0
    for rows in row_groups:
        occupied = [set() for _ in rows]
        for row_index, row in enumerate(rows):
            column = 0
            for cell in element_children(document, document.get(row)):
                require(isinstance(cell, Ref), "table row has a non-cell child")
                attributes = table_attributes(document.get(int(cell)))
                height = attributes.get("RowSpan", 1)
                width = attributes.get("ColSpan", 1)
                require(1 <= height <= len(rows) - row_index, "/RowSpan exceeds its row group")
                require(width >= 1, "/ColSpan is not positive")
                occupied_tracks += width * height
                require(occupied_tracks <= 1_000_000, "expanded table grid exceeds the checker budget")
                while column in occupied[row_index]:
                    column += 1
                covered = set(range(column, column + width))
                for row_mask in occupied[row_index : row_index + height]:
                    require(row_mask.isdisjoint(covered), "table cells overlap")
                    row_mask.update(covered)
                column += width
            if expected_width is None:
                expected_width = len(occupied[row_index])
            require(
                len(occupied[row_index]) == expected_width
                and max(occupied[row_index], default=-1) == expected_width - 1,
                "table grid leaves a gap or extends past its width",
            )


def check_tables(document: Document, visited: set[int], identifiers: dict[bytes, int], pages: list[int], page_index: dict[int, int], dimensions: dict[str, int]) -> None:
    """Independent table checks, derived from the bytes alone:

    * an empty cell (a TH or TD authored with no content) is an element
      with no /K and no /Pg: it owns no marked content, and there are
      exactly `empty_cells` of them when the case declares the count;

    * grid regularity: expanded row and column spans cover every track
      exactly once, within each row group;
    * every TH declares a /Scope, and every /Headers target resolves through
      the IDTree to a TH;
    * header-once semantics: a table's THead content lies on the table's
      first page only;
    * repeated headers are artifacts: every later page on which the table
      continues repaints text inside /Artifact <</Type /Pagination>> marked
      content that carries no MCID.
    """
    empty_cells = 0
    for number in sorted(visited):
        element = document.get(number)
        if str(element["S"]) in ("TH", "TD") and not element_children(document, element):
            require("K" not in element and "Pg" not in element, "an empty table cell carries an empty /K or a /Pg")
            empty_cells += 1
        if str(element["S"]) == "TH":
            require("Scope" in table_attributes(element), "a TH declares no /Scope")
        headers = table_attributes(element).get("Headers")
        if headers is not None:
            for target in headers:
                require(target in identifiers and str(document.get(identifiers[target])["S"]) == "TH", "/Headers names an element that is not a TH")
        if str(element["S"]) != "Table":
            continue
        row_groups: list[list[int]] = []
        direct_rows: list[int] = []
        head: list[int] = []
        for child in element_children(document, element):
            if not isinstance(child, Ref):
                continue
            child_role = str(document.get(int(child))["S"])
            if child_role == "TR":
                direct_rows.append(int(child))
            elif child_role in ("THead", "TBody", "TFoot"):
                if direct_rows:
                    row_groups.append(direct_rows)
                    direct_rows = []
                if child_role == "THead":
                    head.append(int(child))
                row_groups.append([int(row) for row in element_children(document, document.get(int(child))) if isinstance(row, Ref)])
        if direct_rows:
            row_groups.append(direct_rows)
        check_table_grid(document, row_groups)
        if dimensions.get("facade_table_headers"):
            check_scoped_table_headers(document, [row for group in row_groups for row in group])
        table_pages = sorted(mcr_pages(document, number), key=lambda page: page_index[page])
        if not head or not table_pages:
            continue
        first = table_pages[0]
        require(mcr_pages(document, head[0]) <= {first}, "a THead's content appears after the table's first page")
        for page in table_pages[1:]:
            content = document.stream(int(document.get(page)["Contents"]))
            repainted = False
            for match in re.finditer(rb"/Artifact <</Type /Pagination>> BDC\n(.*?)EMC\n", content, re.S):
                body = match.group(1)
                require(b"/MCID" not in body, "a repeated header artifact carries an MCID")
                repainted = repainted or b"Tj" in body or b"TJ" in body
            require(repainted, f"table continues on page {page_index[page]} without repainting its header rows as a pagination artifact")
    expected_empty = dimensions.get("empty_cells")
    if expected_empty is not None:
        require(empty_cells == expected_empty, f"expected {expected_empty} empty table cells, found {empty_cells}")


def normalize_attributes(value, role: str) -> str:
    dictionaries = value if isinstance(value, list) else [value]
    rendered = []
    for dictionary in dictionaries:
        require(isinstance(dictionary, dict), "/A entry is not a dictionary")
        owner = dictionary.get("O")
        if owner == "Table":
            require(set(dictionary) <= TABLE_ATTRIBUTES, "unknown Table attribute")
            if "Scope" in dictionary:
                require(role == "TH" and dictionary["Scope"] in ("Row", "Column", "Both"), "invalid /Scope")
            if "Headers" in dictionary:
                headers = dictionary["Headers"]
                require(role in ("TH", "TD") and isinstance(headers, list) and headers and all(isinstance(h, bytes) for h in headers), "invalid /Headers")
            for span in ("ColSpan", "RowSpan"):
                if span in dictionary:
                    require(role in ("TH", "TD") and isinstance(dictionary[span], int) and dictionary[span] >= 1, f"invalid /{span}")
            if "Summary" in dictionary:
                require(role == "Table", "/Summary outside Table")
        elif owner == "FENote":
            require(role == "FENote" and dictionary == {"O": "FENote", "NoteType": "Footnote"}, "invalid footnote attribute")
        elif owner == "Layout":
            require(set(dictionary) == {"O", "WritingMode"}, "invalid Layout attributes")
            require(dictionary["WritingMode"] in ("LrTb", "RlTb"), "invalid /WritingMode")
        elif owner == "List":
            require(set(dictionary) <= {"O", "ListNumbering"} and role == "L", "invalid List attributes")
            require(dictionary.get("ListNumbering") in LIST_NUMBERING, "invalid /ListNumbering")
        else:
            raise ValidationError(f"unsupported attribute owner {owner!r}")
        parts = []
        for key in sorted(dictionary):
            item = dictionary[key]
            if key == "Headers":
                parts.append("Headers=[" + ",".join(h.decode("latin-1") for h in item) + "]")
            elif isinstance(item, bytes):
                parts.append(f"{key}={text_string(item)!r}")
            else:
                parts.append(f"{key}={item}")
        rendered.append("{" + " ".join(parts) + "}")
    return "".join(rendered)


def validate_structure_semantics_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    rendered = check_structure_semantics(pdf, dimensions)
    if dimensions.get("authored_nested"):
        require(rendered == NESTED_EXPECTED, "emitted container tree differs from the authored hierarchy")


# ---------------------------------------------------------------------------
# Self-test.
# ---------------------------------------------------------------------------
NESTED_EXPECTED = [
    "Document [Title [mcid p0:0], P [mcid p0:1], Part [Sect [H1 [mcid p0:2], P [mcid p0:3], Div [Sect [H2 [mcid p0:4], P [mcid p0:5], "
    "L A={ListNumbering=Disc O=List} [LI [Lbl [mcid p0:6], LBody [mcid p0:7]], LI [Lbl [mcid p0:8], LBody [mcid p0:9]], LI [Lbl [mcid p0:10], LBody [mcid p0:11]]]]], "
    "P [Link [mcid p0:12, objr Link p0]]], Sect [H1 [mcid p0:13], P [mcid p0:14]]], Div [P [mcid p0:15]]]"
]

LOWERING_EXPECTED = [
    "Document [Table Alt='A one-row price table' A={O=Table Summary='One priced item with its column header.'} "
    "[TR [TH ID=hdr-price A={O=Table Scope=Column}, TD Lang=fr A={Headers=[hdr-price] O=Table} "
    "[Span Lang=fr-FR E='Café Portable Document Format' ActualText='Café PDF' [mcid p0:0]]]]]"
]


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "mutation twins must preserve length")
    try:
        return layout_twin(value, old, new, exactly_once=False)
    except LayoutError as error:
        raise ValidationError(str(error)) from error


def self_test() -> None:
    for label, path in SNAPSHOTS.items():
        check_structure_semantics(path.read_bytes())
    validate_structure_semantics_pdf(SNAPSHOTS["nested"].read_bytes(), {"authored_nested": 1})
    require(check_structure_semantics(SNAPSHOTS["lowering"].read_bytes()) == LOWERING_EXPECTED, "lowering normalized structure changed")

    nested = SNAPSHOTS["nested"].read_bytes()
    authored_group_twins = ((b"/S /Part", b"/S /Div"), (b"/P 8 0 R /S /Sect", b"/P 8 0 R /S /Div"))
    for old, new in authored_group_twins:
        altered_group = layout_twin(nested, old, new, exactly_once=False)
        try:
            validate_structure_semantics_pdf(altered_group, {"authored_nested": 1})
        except ValidationError as error:
            require(str(error) == "emitted container tree differs from the authored hierarchy", str(error))
        else:
            raise ValidationError("the authored container tree accepted a substituted grouping role")
    lowering = SNAPSHOTS["lowering"].read_bytes()
    facade = SNAPSHOTS["facade"].read_bytes()
    table = SNAPSHOTS["table"].read_bytes()
    figure_sections = SNAPSHOTS["figure_sections"].read_bytes()
    inline_roles = SNAPSHOTS["inline_roles"].read_bytes()
    inline_document = Document(inline_roles)
    for parent_role, original_role, forbidden_role in (("Quote", "Span", "Div"), ("Link", "Em", "P")):
        offending_child = next(
            int(child) for number in inline_document.bodies
            if re.search(rb"/S /" + parent_role.encode() + rb" >>", inline_document.bodies[number])
            for child in element_children(inline_document, inline_document.get(number))
            if isinstance(child, Ref) and inline_document.get(int(child))["S"] == original_role
        )
        body = inline_document.bodies[offending_child]
        changed = body.replace(f"/S /{original_role} >>".encode(), f"/S /{forbidden_role} >>".encode(), 1)
        require(changed != body, "role-only containment control failed to change a structure dictionary")
        twin = layout_twin(inline_roles, body, changed, exactly_once=True)
        try:
            check_structure_semantics(twin)
        except ValidationError as error:
            require(str(error) == f"/{parent_role} may not contain /{forbidden_role} under /{parent_role}", str(error))
        else:
            raise ValidationError(f"checker accepted {parent_role} > {forbidden_role}")
    check_structure_semantics(SNAPSHOTS["figures"].read_bytes(), {"figure_nodes": 4, "captioned_figures": 3, "scaled_figures": 1, "layout_artifacts": 2})
    mutations = [
        ("figure caption in a transparent Part", figure_sections, b"/S /Sect", b"/S /Part"),
        ("Figure without /Alt", figure_sections, b"/Alt ", b"/Alz "),
        ("irregular table grid", table, b"/ColSpan 2", b"/ColSpan 3"),
        ("row span outside the declared subset", table, b"/ColSpan 2", b"/RowSpan 2"),
        ("/Headers names a TD", table, b"/Headers [(c000002) (c000005) (c000008)]", b"/Headers [(c000002) (c000005) (c000009)]"),
        ("illegal containment Document > Span", nested, b"/S /Part ", b"/S /Span "),
        ("illegal containment Sect > LI", nested, b"/S /H1 ", b"/S /LI "),
        ("content item in L", nested, b"/P 5 0 R /Pg 34 0 R /S /P >>", b"/P 5 0 R /Pg 34 0 R /S /L >>"),
        ("DisplayDocTitle false", nested, b"/DisplayDocTitle true", b"/DisplayDocTitle null"),
        ("DisplayDocTitle removed", facade, b"/ViewerPreferences", b"/ViewerPreferencez"),
        ("MarkInfo not marked", facade, b"/Marked true", b"/Marked null"),
        ("page Tabs not /S", facade, b"/Tabs /S", b"/Tabs /R"),
        ("duplicate MCID reference", nested, b"<< /K [1] /NS", b"<< /K [0] /NS"),
        ("ParentTree row drift", lowering, b"/Nums [0 [10 0 R]]", b"/Nums [0 [ 9 0 R]]"),
        ("IDTree key without /ID", lowering, b"(hdr-price) 8 0 R", b"(hdr-pricf) 8 0 R"),
        ("/Headers names a missing identifier", lowering, b"/Headers [(hdr-price)]", b"/Headers [(hdr-pricf)]"),
        ("malformed nested language", lowering, b"/Lang (fr)", b"/Lang (6r)"),
        ("invalid Scope value", lowering, b"/A << /O /Table /Scope /Column >> /ID", b"/A << /O /Table /Scope /Colunn >> /ID"),
        ("labelled list numbered /None", nested, b"/ListNumbering /Disc", b"/ListNumbering /None"),
        ("PDF 1.7 Quote claimed by the PDF 2.0 namespace", inline_roles, b"/NS 5 0 R /P 21 0 R /S /Quote ", b"/NS 4 0 R /P 21 0 R /S /Quote "),
        ("PDF 2.0 P claimed by the PDF 1.7 namespace", inline_roles, b"/NS 4 0 R /P 6 0 R /Pg 41 0 R /S /P >>", b"/NS 5 0 R /P 6 0 R /Pg 41 0 R /S /P >>"),
    ]
    for label, source, old, new in mutations:
        mutated = replace_once(source, old, new)
        try:
            check_structure_semantics(mutated)
        except (ValidationError, KeyError, ValueError, TypeError, AttributeError, IndexError):
            continue
        raise SystemExit(f"structure-semantics checker accepted {label}")
    document = Document(nested)
    catalog = document.get(document.root)
    tree_root = int(catalog["StructTreeRoot"])
    root = int(document.get(tree_root)["K"])
    parent_entry = f" /P {tree_root} 0 R".encode("ascii")
    root_body = document.bodies[root]
    require(root_body.count(parent_entry) == 1, "Document parent control source changed")
    without_parent = layout_twin(nested, root_body, root_body.replace(parent_entry, b""), exactly_once=True)
    try:
        check_structure_semantics(without_parent)
    except ValidationError as error:
        require(str(error) == f"structure element {root} /P does not name its parent", "missing parent twin failed for the wrong reason")
    else:
        raise ValidationError("structure-semantics checker accepted an element with no /P")
    navigation = SNAPSHOTS["navigation"].read_bytes()
    document = Document(navigation)
    mcr_pattern = re.compile(rb"<< /MCID [0-9]+ /Pg ([0-9]+) 0 R /Type /MCR >>")
    mcr = next(match for body in document.bodies.values() if (match := mcr_pattern.search(body)))
    pages: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), pages)
    other_page = next(page for page in pages if page != int(mcr.group(1)))
    other_stream = int(document.get(other_page)["Contents"])
    wrong_stream = mcr.group(0).replace(b" /Type", f" /Stm {other_stream} 0 R /Type".encode("ascii"))
    try:
        check_structure_semantics(layout_twin(navigation, mcr.group(0), wrong_stream, exactly_once=True))
    except ValidationError as error:
        require(str(error) == "a page-content MCR names an additional stream or owner", "foreign-stream MCR twin failed for the wrong reason")
    else:
        raise SystemExit("structure-semantics checker accepted a page-content MCR naming another stream")

    bad_region = replace_once(lowering, b"/Lang (fr-FR)", b"/Lang (en-12)")
    try:
        check_structure_semantics(bad_region)
    except ValidationError as error:
        require(str(error) == "structure /Lang 'en-12' is not a language tag", "invalid region twin failed for the wrong reason")
    else:
        raise ValidationError("structure-semantics checker accepted an invalid language region subtag")
    for tag in ("I-klingon", "en-0-12", "de-DE-x-phonebk", "art-lojban", "de-1901-x-1901", "en-u-ca-gregory-x-u-u"):
        require(language_tag_valid(tag), f"checker rejected well-formed language tag {tag}")
    for tag in ("de-1901-1901", "sl-rozaj-BISKE-ROZAJ", "en-u-ca-gregory-U-nu-latn", "en-0-ab-0-cd"):
        changed_language = layout_twin(lowering, b"/Lang (fr-FR)", f"/Lang ({tag})".encode("ascii"), exactly_once=True)
        try:
            check_structure_semantics(changed_language)
        except ValidationError as error:
            require(str(error) == f"structure /Lang {tag!r} is not a language tag", "duplicate subtag twin failed for the wrong reason")
        else:
            raise ValidationError("structure-semantics checker accepted a duplicate language subtag")

    # Wrappers between Document and Span still expose the illegal edge.
    grouping_twins = (("Part", "Part"), ("Div", "Div"), ("Part", "Div"), ("Div", "Part"))
    for outer, inner in grouping_twins:
        grouped = replace_once(nested, b"/P 8 0 R /S /Sect", f"/P 8 0 R /S /{inner:4}".encode("ascii"))
        if outer == "Div":
            grouped = replace_once(grouped, b"/S /Part ", b"/S /Div  ")
        check_structure_semantics(grouped)
        span = replace_once(grouped, b"/P 9 0 R /Pg 34 0 R /S /H1 >>", b"/P 9 0 R /Pg 34 0 R/S /Span>>")
        try:
            check_structure_semantics(span)
        except ValidationError as error:
            require(str(error) == f"/{inner} may not contain /Span under /Document", "nested grouping twin failed for the wrong reason")
        else:
            raise ValidationError(f"structure-semantics checker accepted Span inside {outer} and {inner}")

    # Custom-block twins: a callout's Div rewritten as another role, and
    # in-flow decorations (painted after their page's text) presented as
    # the callouts' underlays.
    callouts = SNAPSHOTS["custom_blocks"].read_bytes()
    callout_dimensions = {"paragraph_divs": 10, "underlays": 10, "layout_artifacts": 10}
    check_structure_semantics(callouts, callout_dimensions)
    check_structure_semantics(SNAPSHOTS["custom_defaults"].read_bytes(), {"paragraph_divs": 4, "layout_artifacts": 2, "custom_inset_delta": 8, "custom_origin_x": 56})
    check_structure_semantics(SNAPSHOTS["empty_cells"].read_bytes(), {"empty_cells": 75})
    callout_twins = [
        ("a wrong default custom inset", SNAPSHOTS["custom_defaults"].read_bytes(), {"custom_inset_delta": 9, "custom_origin_x": 56}),
        ("a callout Div that is not a Div", replace_once(callouts, b"/S /Div ", b"/S /Art "), callout_dimensions),
        ("decorations painted after text counted as underlays", figure_sections, {"underlays": 10}),
        ("a table without empty cells counted as having one", table, {"empty_cells": 1}),
        ("an empty-cell table with one empty cell uncounted", SNAPSHOTS["empty_cells"].read_bytes(), {"empty_cells": 74}),
    ]
    for label, source, dimensions in callout_twins:
        try:
            check_structure_semantics(source, dimensions)
        except (ValidationError, KeyError, ValueError, TypeError, AttributeError, IndexError):
            continue
        raise SystemExit(f"structure-semantics checker accepted {label}")
    # Explicit scope membership is stronger than validity of each /ID.
    header_dimensions = {"facade_table_headers": 1}
    check_structure_semantics(table, header_dimensions)
    header_entry = b"/Headers [(c000002) (c000005) (c000008)] "
    for replacement in (b"/Headers [(c000002) (c000006) (c000008)] ", b""):
        twin = layout_twin(table, header_entry, replacement, exactly_once=True)
        try:
            check_structure_semantics(twin, header_dimensions)
        except ValidationError as error:
            require(
                str(error) == "facade data cell /Headers disagrees with its scoped table headers",
                "scope-header twin failed for a different reason",
            )
        else:
            raise ValidationError("scope-header twin passed the facade table checker")

    # A row header in the combined letter inherits its column heading.
    # Remove only that explicit association, leaving its Scope intact.
    letter = (ROOT / "tests" / "reference_documents" / "letter.pdf").read_bytes()
    check_structure_semantics(letter, header_dimensions)
    letter_objects = Document(letter)
    headed_row_header = next(
        body for body in letter_objects.bodies.values()
        if b"/S /TH >>" in body and b"/Scope /Row" in body and b"/Headers" in body
    )
    without_column_heading = re.sub(rb"/Headers \[[^\]]+\] ", b"", headed_row_header, count=1)
    twin = layout_twin(letter, headed_row_header, without_column_heading, exactly_once=True)
    try:
        check_structure_semantics(twin, header_dimensions)
    except ValidationError as error:
        require(str(error) == "facade header cell /Headers disagrees with its scoped table headers", str(error))
    else:
        raise ValidationError("scope-header twin dropped a row header's column heading")

    # Furniture twins mutate decoded page furniture: an MCID inside a
    # pagination artifact, a wrong page number, a wrong total, and a missing
    # page-number artifact.
    templates = Document(SNAPSHOTS["templates"].read_bytes())
    template_pages: list[int] = []
    page_order(templates, int(templates.get(templates.root)["Pages"]), template_pages)
    furniture = furniture_by_page(templates, template_pages)
    check_furniture(furniture, {"page_number_artifacts": 2})

    def page_number_twin(transform):
        return [[transform(item) if item[0] == "PageNum" and index == 1 else item for item in items] for index, items in enumerate(furniture)]

    furniture_twins = [
        ("an MCID inside furniture", page_number_twin(lambda item: (item[0], item[1] + b"/P <</MCID 0>> BDC\n", item[2])), {}),
        ("a wrong page number", page_number_twin(lambda item: (item[0], item[1], item[2].replace("2 of", "3 of"))), {}),
        ("a wrong page total", page_number_twin(lambda item: (item[0], item[1], item[2].replace("of 3", "of 4"))), {}),
        ("a missing page-number artifact", [[item for item in items if item[0] != "PageNum" or index != 1] for index, items in enumerate(furniture)], {"page_number_artifacts": 2}),
    ]
    for label, twin, dimensions in furniture_twins:
        try:
            check_furniture(twin, dimensions)
        except ValidationError:
            continue
        raise SystemExit(f"structure-semantics checker accepted {label}")
    print(
        "PASS structure-semantics checker self-test: normalized trees, ParentTree/MCID/OBJR "
        "exactly-once, IDTree/ID, language, attributes, DisplayDocTitle, MarkInfo, Tabs, "
        f"Table 5 containment, page furniture, figure captions and scales, and custom-block Divs and underlays verified on {len(SNAPSHOTS)} snapshots; {len(mutations) + len(grouping_twins) + len(authored_group_twins)} "
        f"length-preserving mutation twins, two role-only containment twins, one foreign-stream MCR twin, five invalid language-tag twins, 3 scope-header twins, {len(furniture_twins)} furniture twins, and {len(callout_twins)} custom-block twins rejected",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="*", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if not arguments.pdf:
        raise SystemExit("provide PDF paths or --self-test")
    for path in arguments.pdf:
        for line in check_structure_semantics(path.read_bytes()):
            print(line)
        print(f"PASS {path}", flush=True)


if __name__ == "__main__":
    main()
