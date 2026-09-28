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
  first-or-last Caption rule against its OWN transcription of ISO/TS 32005
  Table 5 (not the Roc table). When the pinned veraPDF installation is
  provisioned, the self-test also compares that transcription with the
  veraPDF PDFUA-2-ISO32005 profile rules.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_pdf_structure import (  # noqa: E402
    ValidationError,
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
    "navigation": ROOT / "tests" / "navigation" / "navigation_facade.pdf",
    "figure": ROOT / "tests" / "pdf_facade" / "image_figure.pdf",
    "table": ROOT / "tests" / "tables" / "spans.pdf",
    "continued_table": ROOT / "tests" / "tables" / "footer_carry.pdf",
}

VERAPDF_JAR_GLOB = ".roc-pdf-tmp/extended-tools/verapdf/bin/cli-*.jar"
VERAPDF_PROFILE = "org/verapdf/pdfa/validation/PDFUA-2-ISO32005.xml"

# ---------------------------------------------------------------------------
# ISO/TS 32005:2023 Table 5, transcribed independently as the set of child
# roles each parent may contain ("Hn" stands for H1..H6). This is the
# checker's own table; it is compared against the Roc kernel only through
# emitted PDFs and against veraPDF's encoding of Table 5 by the self-test.
# ---------------------------------------------------------------------------
INLINE = {"Lbl", "Figure", "Link", "Span", "Em", "Strong", "Code", "Quote"}
ALL_ROLES = {
    "Document", "DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "LI", "Lbl",
    "LBody", "Figure", "Caption", "Link", "Span", "Em", "Strong", "Code", "Quote", "Table", "THead",
    "TBody", "TFoot", "TR", "TH", "TD",
}
DOCUMENT_CHILDREN = {"Document", "DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "Figure", "Link", "Code", "Table"}
CELL_CHILDREN = {"Sect", "Div", "H", "Hn", "P", "L", "Table"} | INLINE
MAY_CONTAIN: dict[str, set[str]] = {
    "Document": DOCUMENT_CHILDREN,
    "DocumentFragment": DOCUMENT_CHILDREN,
    "Part": set(ALL_ROLES),
    "Div": set(ALL_ROLES),
    "Sect": {"DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "Lbl", "Figure", "Caption", "Link", "Code", "Table"},
    "Title": {"Part", "Div", "P", "L", "Caption", "Table"} | INLINE,
    "H": {"Sect"} | INLINE,
    "Hn": {"Sect"} | INLINE,
    "P": {"L", "Table"} | INLINE,
    "L": {"L", "LI", "Caption"},
    "LI": {"Div", "Lbl", "LBody"},
    "Lbl": INLINE - {"Lbl"},
    "LBody": {"Part", "Sect", "Div", "H", "Hn", "P", "L", "Caption", "Table"} | (INLINE - {"Lbl"}),
    "Figure": {"Part", "Sect", "Div", "H", "Hn", "P", "L", "Caption", "Table"} | INLINE,
    "Caption": {"DocumentFragment", "Part", "Sect", "Div", "H", "Hn", "P", "L", "Table"} | INLINE,
    "Link": {"DocumentFragment", "Part", "Sect", "Div", "Title", "H", "Hn", "P", "L", "Caption", "Table"} | INLINE,
    "Span": set(INLINE),
    "Em": set(INLINE),
    "Strong": set(INLINE),
    "Code": {"DocumentFragment", "Part", "Sect", "Div", "P", "L", "Caption", "Table"} | INLINE,
    "Quote": {"Div"} | INLINE,
    "Table": {"Caption", "THead", "TBody", "TFoot", "TR"},
    "THead": {"TR"},
    "TBody": {"TR"},
    "TFoot": {"TR"},
    "TR": {"TH", "TD"},
    "TH": set(CELL_CHILDREN),
    "TD": set(CELL_CHILDREN),
}
NO_CONTENT_ITEMS = {"Document", "DocumentFragment", "Sect", "L", "LI", "Table", "THead", "TBody", "TFoot", "TR"}
AT_MOST_ONE: dict[str, set[str]] = {
    "Document": {"H"}, "DocumentFragment": {"H"}, "Sect": {"H"}, "Caption": {"H"}, "TH": {"H"}, "TD": {"H"},
    "LBody": {"H", "Caption"}, "Figure": {"H", "Caption"}, "H": {"Sect"}, "Hn": {"Sect"},
    "Title": {"Caption"}, "L": {"Caption"}, "Link": {"Caption"}, "Code": {"Caption"},
    "Table": {"Caption", "THead", "TFoot"},
}
TABLE_ATTRIBUTES = {"ColSpan", "Headers", "O", "RowSpan", "Scope", "Summary"}
LIST_NUMBERING = {
    "None", "Unordered", "Description", "Disc", "Circle", "Square", "Ordered", "Decimal", "UpperRoman",
    "LowerRoman", "UpperAlpha", "LowerAlpha",
}
LANGUAGE_TAG = re.compile(r"[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*")


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
    def __init__(self, data: bytes):
        self.data = data
        self.at = 0

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
                require(previous is None or str(previous).encode("latin-1") < str(key).encode("latin-1"), f"dictionary keys not in canonical order at /{key}")
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
            return zlib.decompress(encoded)
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
        require(LANGUAGE_TAG.fullmatch(catalog_language) is not None, "catalog /Lang is not a language tag")

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
    for namespace in namespaces:
        value = document.get(namespace)
        require(value.get("Type") == "Namespace" and text_string(value["NS"]) == "http://iso.org/pdf2/ssn", "namespace is not PDF 2.0")

    lines: list[str] = []
    mcr_owner: dict[tuple[int, int], int] = {}
    objr_owner: dict[int, int] = {}
    identifiers: dict[bytes, int] = {}
    visited: set[int] = set()
    labelled_items: set[int] = set()

    def walk(number: int, parent: int, inherited: str | None, parent_role: str | None, depth: int) -> str:
        require(depth <= 64, "structure tree too deep")
        require(number not in visited, f"structure element {number} is reachable twice")
        visited.add(number)
        element = document.get(number)
        require(element.get("Type") == "StructElem", f"object {number} is not a StructElem")
        require(int(element["P"]) == parent, f"structure element {number} /P does not name its parent")
        require(int(element["NS"]) in namespaces, "structure element namespace is not declared")
        role = str(element["S"])
        row = table_role(role)
        require(row in MAY_CONTAIN, f"unsupported structure role /{role}")
        if parent_role is None:
            require(role == "Document", "the structure root is not Document")
        else:
            require(row in MAY_CONTAIN[table_role(parent_role)], f"/{parent_role} may not contain /{role}")
            require(role != "Document", "Document is nested")
        facts: list[str] = []
        language = inherited
        if "Lang" in element:
            tag = text_string(element["Lang"])
            require(LANGUAGE_TAG.fullmatch(tag) is not None, f"structure /Lang {tag!r} is not a language tag")
            require(tag != inherited, f"structure /Lang {tag!r} repeats its inherited language")
            facts.append(f"Lang={tag}")
            language = tag
        for key in ("Alt", "E", "ActualText"):
            if key in element:
                facts.append(f"{key}={text_string(element[key])!r}")
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
        children = element.get("K", [])
        if not isinstance(children, list):
            children = [children]
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
                if child_row in AT_MOST_ONE.get(row, set()):
                    require(child_row not in limited_seen, f"/{role} contains more than one /{child_role}")
                    limited_seen.add(child_row)
                child_roles.append(child_role)
                leaves.append(walk(int(child), number, language, role, depth + 1))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                require(role not in NO_CONTENT_ITEMS, f"/{role} owns a content item")
                page = int(child["Pg"])
                require(page in page_index, "MCR /Pg is not a page")
                key = (page, int(child["MCID"]))
                require(key not in mcr_owner, f"MCID {key[1]} on page {page_index[page]} is referenced twice")
                mcr_owner[key] = number
                leaves.append(f"mcid p{page_index[page]}:{key[1]}")
            elif isinstance(child, dict) and child.get("Type") == "OBJR":
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

    lines.append(walk(int(root_element), tree_root_number, catalog_language, None, 1))

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

    check_tables(document, visited, identifiers, pages, page_index)

    expected_elements = dimensions.get("structure_elements")
    if expected_elements is not None:
        require(len(visited) == expected_elements, f"expected {expected_elements} structure elements, found {len(visited)}")
    expected_ids = dimensions.get("element_identifiers")
    if expected_ids is not None:
        require(len(identifiers) == expected_ids, "element identifier count differs")
    return lines


def table_attributes(element: dict) -> dict:
    values = element.get("A")
    for dictionary in values if isinstance(values, list) else [values]:
        if isinstance(dictionary, dict) and dictionary.get("O") == "Table":
            return dictionary
    return {}


def element_children(document: Document, element: dict) -> list:
    children = element.get("K", [])
    return children if isinstance(children, list) else [children]


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


def check_tables(document: Document, visited: set[int], identifiers: dict[bytes, int], pages: list[int], page_index: dict[int, int]) -> None:
    """Independent table checks, derived from the bytes alone:

    * grid regularity: every row of a table spans the same number of
      columns (the sum of its cells' /ColSpan, default 1), and no cell spans
      rows (the package's declared subset);
    * every TH declares a /Scope, and every /Headers target resolves through
      the IDTree to a TH;
    * header-once semantics: a table's THead content lies on the table's
      first page only;
    * repeated headers are artifacts: every later page on which the table
      continues repaints text inside /Artifact <</Type /Pagination>> marked
      content that carries no MCID.
    """
    for number in sorted(visited):
        element = document.get(number)
        if str(element["S"]) == "TH":
            require("Scope" in table_attributes(element), "a TH declares no /Scope")
        headers = table_attributes(element).get("Headers")
        if headers is not None:
            for target in headers:
                require(target in identifiers and str(document.get(identifiers[target])["S"]) == "TH", "/Headers names an element that is not a TH")
        if str(element["S"]) != "Table":
            continue
        rows: list[int] = []
        head: list[int] = []
        for child in element_children(document, element):
            if not isinstance(child, Ref):
                continue
            child_role = str(document.get(int(child))["S"])
            if child_role == "TR":
                rows.append(int(child))
            elif child_role in ("THead", "TBody", "TFoot"):
                if child_role == "THead":
                    head.append(int(child))
                rows.extend(int(row) for row in element_children(document, document.get(int(child))) if isinstance(row, Ref))
        widths = set()
        for row in rows:
            width = 0
            for cell in element_children(document, document.get(row)):
                if not isinstance(cell, Ref):
                    continue
                attributes = table_attributes(document.get(int(cell)))
                require(attributes.get("RowSpan", 1) == 1, "a table cell spans rows outside the declared subset")
                span = attributes.get("ColSpan", 1)
                require(isinstance(span, int) and span >= 1, "a /ColSpan is not a positive integer")
                width += span
            widths.add(width)
        require(len(widths) <= 1, f"table rows span different column counts {sorted(widths)}")
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
    check_structure_semantics(pdf, dimensions)


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
    "[TR [TH ID=hdr-price A={O=Table Scope=Column}, TD Lang=fr ID=cell-price A={Headers=[hdr-price] O=Table} "
    "[Span Lang=fr-FR E='Café Portable Document Format' ActualText='Café PDF' [mcid p0:0]]]]]"
]


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "mutation twins must preserve length")
    require(value.count(old) >= 1, f"mutation anchor {old!r} is absent")
    return value.replace(old, new, 1)


def independent_table_matches_verapdf() -> str:
    jars = sorted(ROOT.glob(VERAPDF_JAR_GLOB))
    if not jars:
        return "veraPDF not provisioned; Table 5 cross-check skipped"
    with zipfile.ZipFile(jars[-1]) as archive:
        profile = archive.read(VERAPDF_PROFILE).decode("utf-8")
    forbidden = set()
    for parent, child in re.findall(r"<description>&lt;(\w+)&gt;(?:, when used as [a-z ]+,)? shall not contain &lt;(\w+)&gt;</description>", profile):
        forbidden.add((parent, child))
    require(bool(forbidden), "the veraPDF profile yielded no Table 5 containment rules")
    for parent in ALL_ROLES:
        for child in ALL_ROLES:
            allowed = child in MAY_CONTAIN[parent]
            require(allowed == ((parent, child) not in forbidden), f"independent Table 5 transcription disagrees with veraPDF for {parent} > {child}")
    content_rules = set(re.findall(r"<description>&lt;(\w+)&gt; shall not contain content items</description>", profile))
    require(NO_CONTENT_ITEMS - {"LI"} == content_rules & ALL_ROLES, "content-item roles disagree with veraPDF")
    return f"Table 5 transcription agrees with {jars[-1].name} on {len(ALL_ROLES) ** 2} role pairs"


def self_test() -> None:
    for label, path in SNAPSHOTS.items():
        check_structure_semantics(path.read_bytes())
    require(check_structure_semantics(SNAPSHOTS["nested"].read_bytes()) == NESTED_EXPECTED, "nested normalized structure changed")
    require(check_structure_semantics(SNAPSHOTS["lowering"].read_bytes()) == LOWERING_EXPECTED, "lowering normalized structure changed")

    nested = SNAPSHOTS["nested"].read_bytes()
    lowering = SNAPSHOTS["lowering"].read_bytes()
    facade = SNAPSHOTS["facade"].read_bytes()
    table = SNAPSHOTS["table"].read_bytes()
    mutations = [
        ("irregular table grid", table, b"/ColSpan 2", b"/ColSpan 3"),
        ("row span outside the declared subset", table, b"/ColSpan 2", b"/RowSpan 2"),
        ("/Headers names a TD", table, b"/Headers [<63303030303032> <63303030303035> <63303030303038>]", b"/Headers [<63303030303032> <63303030303035> <63303030303039>]"),
        ("illegal containment Document > Span", nested, b"/S /Part ", b"/S /Span "),
        ("illegal containment Sect > LI", nested, b"/S /H1 ", b"/S /LI "),
        ("content item in L", nested, b"/P 5 0 R /S /P /Type", b"/P 5 0 R /S /L /Type"),
        ("DisplayDocTitle false", nested, b"/DisplayDocTitle true", b"/DisplayDocTitle null"),
        ("DisplayDocTitle removed", facade, b"/ViewerPreferences", b"/ViewerPreferencez"),
        ("MarkInfo not marked", facade, b"/Marked true", b"/Marked null"),
        ("page Tabs not /S", facade, b"/Tabs /S", b"/Tabs /R"),
        ("duplicate MCID reference", nested, b"<< /MCID 1 /Pg", b"<< /MCID 0 /Pg"),
        ("ParentTree row drift", lowering, b"/Nums [0 [10 0 R]]", b"/Nums [0 [ 9 0 R]]"),
        ("IDTree key without /ID", lowering, b"<63656C6C2D7072696365> 9 0 R", b"<63656C6C2D7072696366> 9 0 R"),
        ("/Headers names a missing identifier", lowering, b"/Headers [<6864722D7072696365>]", b"/Headers [<6864722D7072696366>]"),
        ("malformed nested language", lowering, b"/Lang <FEFF00660072>", b"/Lang <FEFF00360072>"),
        ("invalid Scope value", lowering, b"/A << /O /Table /Scope /Column >> /ID", b"/A << /O /Table /Scope /Colunn >> /ID"),
        ("labelled list numbered /None", nested, b"/ListNumbering /Disc", b"/ListNumbering /None"),
    ]
    for label, source, old, new in mutations:
        mutated = replace_once(source, old, new)
        try:
            check_structure_semantics(mutated)
        except (ValidationError, KeyError, ValueError, TypeError, AttributeError, IndexError, zlib.error):
            continue
        raise SystemExit(f"structure-semantics checker accepted {label}")
    cross_check = independent_table_matches_verapdf()
    print(
        "PASS structure-semantics checker self-test: normalized trees, ParentTree/MCID/OBJR "
        "exactly-once, IDTree/ID, language, attributes, DisplayDocTitle, MarkInfo, Tabs, and "
        f"Table 5 containment verified on {len(SNAPSHOTS)} snapshots; {len(mutations)} "
        f"length-preserving mutation twins rejected; {cross_check}",
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
