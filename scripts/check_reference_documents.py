#!/usr/bin/env python3
"""Independent checks of the reference invoice, report, and letter.

Reusing only the byte-level value parser of the structure-semantics checker,
and never the Roc package, it proves on the reference snapshots that:

* metadata: the XMP packet's ``dc:title`` (``x-default``) equals the
  metadata title fixed by docs/reference-documents.md, the catalog sets
  ``/ViewerPreferences << /DisplayDocTitle true >>`` and ``/MarkInfo <<
  /Marked true >>``, and every page has ``/Tabs /S`` (LET-A4: the letter has
  no visible ``Title`` element and still carries all four);
* destinations: every internal ``GoTo`` action (link annotations, the
  ``/Dests`` name tree, and outline items) pairs ``/SD`` and ``/D``, the
  ``/SD`` element is a numbered heading whose marked content lies on the
  ``/D`` page, and the ``/D`` point is the post-layout top-left of that
  heading's first line: its x is the line's start and its y lies above the
  line's baseline by no more than one heading leading. Each named
  destination resolves to the heading authored for it, and every link and
  outline item resolves to the same pair as its named destination.

``--self-test`` first proves each gallery example PDF is byte-identical to
its fixture snapshot, then checks the three references and the REP-A1 and
REP-A3 variants, and rejects twins: a mismatched and an omitted
``dc:title``, ``DisplayDocTitle`` and ``MarkInfo`` switched off, a page
``/Tabs`` changed, a ``/D`` on the wrong page, a ``/D`` point moved off the
heading, and a ``/SD`` naming a paragraph.
"""
from __future__ import annotations

import argparse
import re
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_pdf_structure import ValidationError, require  # noqa: E402
from check_structure_semantics import Document, Ref, page_order, text_string  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

TITLES = {
    "invoice": "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd",
    "report": "Harbour & Finch quarterly operations report, Q1 FY2027",
    "letter": "Letter to Northstar Cooperative about the warranty extension, 21 September 2026",
}

SNAPSHOTS = {
    "invoice": ROOT / "tests" / "reference_documents" / "invoice.pdf",
    "report": ROOT / "tests" / "reference_documents" / "report.pdf",
    "letter": ROOT / "tests" / "reference_documents" / "letter.pdf",
    "report_heading_keep": ROOT / "tests" / "reference_documents" / "report_heading_keep.pdf",
    "report_table_break": ROOT / "tests" / "reference_documents" / "report_table_break.pdf",
}

# Destination names and the visible text of the heading authored for each.
REPORT_DESTINATIONS = {
    "summary": "1 Summary",
    "sales": "2 Sales performance",
    "supply-chain": "3 Supply chain",
    "freight": "3.1 Freight",
    "timber": "3.2 Timber sourcing",
    "outlook": "4 Outlook",
    "appendix-a": "Appendix A. Supplier register",
}

# The ordinary references are the gallery examples: the fixture snapshots and
# the committed example PDFs must be the same bytes (scripts/check_gallery.py
# proves each example program regenerates its PDF).
GALLERY = {
    "invoice": ROOT / "examples" / "tax-invoice" / "tax-invoice.pdf",
    "report": ROOT / "examples" / "business-report" / "business-report.pdf",
    "letter": ROOT / "examples" / "warranty-letter" / "warranty-letter.pdf",
}

HEADING_LEADING = 18.0
DC_TITLE = re.compile(rb"<dc:title>\s*<rdf:Alt>\s*<rdf:li xml:lang=\"x-default\">([^<]*)</rdf:li>\s*</rdf:Alt>\s*</dc:title>")
MARKED = re.compile(rb"/[A-Za-z0-9]+ <</MCID (\d+)>> BDC\nq\n1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm\n")
TEXT_SHOW = re.compile(rb"<([0-9A-F]+)> Tj")


def unescape_xml(value: bytes) -> str:
    return value.decode("utf-8").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&apos;", "'").replace("&amp;", "&")


def check_metadata(document: Document, title: str, pages: list[int]) -> None:
    catalog = document.get(document.root)
    xmp = document.stream(int(catalog["Metadata"]))
    match = DC_TITLE.search(xmp)
    require(match is not None, "the XMP packet has no x-default dc:title")
    require(unescape_xml(match.group(1)) == title, f"XMP dc:title {unescape_xml(match.group(1))!r} is not the metadata title {title!r}")
    require(catalog.get("ViewerPreferences") == {"DisplayDocTitle": True}, "the catalog does not set DisplayDocTitle true")
    require(catalog.get("MarkInfo") == {"Marked": True}, "the catalog does not set /MarkInfo << /Marked true >>")
    for index, page in enumerate(pages):
        require(document.get(page).get("Tabs") == "S", f"page {index + 1} does not set /Tabs /S")


def heading_line(document: Document, element_number: int, page_index: dict[int, int]) -> tuple[int, float, float]:
    """The page, x, and baseline y of a heading's first marked line."""
    element = document.get(element_number)
    require(re.fullmatch(r"H[1-6]", str(element["S"])) is not None, f"/SD names a /{element['S']}, not a numbered heading")
    kids = element.get("K", [])
    kids = kids if isinstance(kids, list) else [kids]
    references = [kid for kid in kids if isinstance(kid, dict) and kid.get("Type") == "MCR"]
    require(references, "the heading owns no marked content")
    first = references[0]
    page = int(first["Pg"])
    require(page in page_index, "the heading's MCR /Pg is not a page")
    content = document.stream(int(document.get(page)["Contents"]))
    for match in MARKED.finditer(content):
        if int(match.group(1)) == int(first["MCID"]):
            return page, float(match.group(2)), float(match.group(3))
    raise ValidationError("the heading's first MCID is not painted as a positioned line")


def resolve(document: Document, target: list, page_index: dict[int, int], kind: str) -> tuple[int, int, float, float]:
    """Check one /D + /SD pair and return (page, element, x, y)."""
    d = target.get("D")
    sd = target.get("SD")
    require(isinstance(d, list) and isinstance(sd, list), f"{kind} lacks a paired /D and /SD")
    require(len(d) == 5 and d[1] == "XYZ" and d[4] is None, f"{kind} /D is not [page /XYZ x y null]")
    require(len(sd) == 5 and sd[1] == "XYZ" and sd[4] is None, f"{kind} /SD is not [element /XYZ x y null]")
    page, element = int(d[0]), int(sd[0])
    require(page in page_index, f"{kind} /D does not name a page")
    require(d[2:4] == sd[2:4], f"{kind} /D and /SD carry different points")
    line_page, x, baseline = heading_line(document, element, page_index)
    require(line_page == page, f"{kind} /D names page {page_index[page] + 1}, but its /SD heading is on page {page_index[line_page] + 1}")
    require(float(d[2]) == x, f"{kind} /D x {d[2]} is not the heading line's start {x}")
    require(baseline < float(d[3]) <= baseline + HEADING_LEADING, f"{kind} /D y {d[3]} is not the top of the heading line at baseline {baseline}")
    return page, element, float(d[2]), float(d[3])


def heading_text(document: Document, element_number: int, fonts: dict[bytes, dict[int, str]]) -> str:
    """The heading's text, decoded through the page font's ToUnicode map."""
    element = document.get(element_number)
    kids = element.get("K", [])
    kids = kids if isinstance(kids, list) else [kids]
    text = ""
    for kid in kids:
        page = int(kid["Pg"])
        content = document.stream(int(document.get(page)["Contents"]))
        start = content.index(b"<</MCID " + str(kid["MCID"]).encode() + b">> BDC")
        end = content.index(b"EMC", start)
        segment = content[start:end]
        font_name = re.search(rb"/(F[0-9_]+) [0-9.]+ Tf", segment).group(1)
        mapping = fonts.setdefault(font_name, font_map(document, page, font_name))
        text += "".join(mapping[int(glyph, 16)] for glyph in TEXT_SHOW.findall(segment))
    return text


def font_map(document: Document, page: int, name: bytes) -> dict[int, str]:
    resources = document.get(page)["Resources"]
    resources = document.get(int(resources)) if isinstance(resources, Ref) else resources
    font = document.get(int(resources["Font"][name.decode()]))
    cmap = document.stream(int(font["ToUnicode"]))
    mapping: dict[int, str] = {}
    for block in re.findall(rb"beginbfchar\n(.*?)endbfchar", cmap, re.S):
        for source, target in re.findall(rb"<([0-9A-F]+)> <([0-9A-F]+)>", block):
            mapping[int(source, 16)] = bytes.fromhex(target.decode()).decode("utf-16-be")
    for block in re.findall(rb"beginbfrange\n(.*?)endbfrange", cmap, re.S):
        for low, high, target in re.findall(rb"<([0-9A-F]+)> <([0-9A-F]+)> <([0-9A-F]+)>", block):
            base = int(target, 16)
            for offset, code in enumerate(range(int(low, 16), int(high, 16) + 1)):
                mapping[code] = chr(base + offset)
    return mapping


def check_destinations(document: Document, pages: list[int], expected: dict[str, str]) -> int:
    page_index = {page: index for index, page in enumerate(pages)}
    catalog = document.get(document.root)
    names = document.get(int(catalog["Names"]["Dests"]))
    entries = names["Names"]
    named: dict[str, tuple[int, int, float, float]] = {}
    fonts: dict[bytes, dict[int, str]] = {}
    for index in range(0, len(entries), 2):
        name = entries[index].decode("latin-1")
        pair = resolve(document, entries[index + 1], page_index, f"named destination {name}")
        require(name in expected, f"unexpected named destination {name}")
        require(heading_text(document, pair[1], fonts) == expected[name], f"named destination {name} resolves to a heading that is not {expected[name]!r}")
        named[name] = pair
    require(set(named) == set(expected), "the named destinations differ from the authored destination headings")
    checked = len(named)
    by_element = {pair[1]: name for name, pair in named.items()}
    for page in pages:
        for annotation in document.get(page).get("Annots", []):
            action = document.get(int(annotation)).get("A", {})
            if action.get("S") != "GoTo":
                continue
            pair = resolve(document, action, page_index, "link annotation")
            require(pair[1] in by_element and named[by_element[pair[1]]] == pair, "a link's /D and /SD are not its named destination's")
            checked += 1
    outline = document.get(int(catalog["Outlines"]))
    item = outline.get("First")
    stack = []
    while item is not None:
        value = document.get(int(item))
        destination = value.get("Dest")
        require(isinstance(destination, bytes), "an outline item has no named /Dest")
        require(destination.decode("latin-1") in named, "an outline item names an unknown destination")
        require(text_string(value["Title"]) == expected[destination.decode("latin-1")], "an outline title differs from its heading")
        checked += 1
        if "First" in value:
            stack.append(value.get("Next"))
            item = value["First"]
        else:
            item = value.get("Next")
            while item is None and stack:
                item = stack.pop()
    return checked


def check_reference(pdf: bytes, kind: str) -> int:
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    check_metadata(document, TITLES[kind], pages)
    if kind == "report":
        return check_destinations(document, pages, REPORT_DESTINATIONS)
    require("Names" not in catalog and "Outlines" not in catalog, f"the {kind} has destinations it did not author")
    return 0


def kind_of(label: str) -> str:
    return label.split("_", 1)[0]


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "mutation twins must preserve length")
    require(value.count(old) >= 1, f"mutation anchor {old!r} is absent")
    return value.replace(old, new, 1)


def self_test() -> None:
    for kind, example in GALLERY.items():
        require(example.read_bytes() == SNAPSHOTS[kind].read_bytes(), f"{example.relative_to(ROOT)} differs from the {kind} fixture snapshot")
    checked = 0
    for label, path in SNAPSHOTS.items():
        checked += check_reference(path.read_bytes(), kind_of(label))
    invoice = SNAPSHOTS["invoice"].read_bytes()
    letter = SNAPSHOTS["letter"].read_bytes()
    report = SNAPSHOTS["report"].read_bytes()
    document = Document(report)
    names = document.get(int(document.get(document.root)["Names"]["Dests"]))["Names"]
    summary = names[names.index(b"summary") + 1]
    d_summary = f"/D [{summary['D'][0]} 0 R".encode()
    # Another page object with a reference of the same length.
    other_page = next(value["D"][0] for value in names[1::2] if value["D"][0] != summary["D"][0] and len(str(value["D"][0])) == len(str(summary["D"][0])))
    d_other = f"/D [{other_page} 0 R".encode()
    # Both points of `summary` lifted 40 pt above its heading line.
    heading_point = f"/XYZ 56 {summary['D'][3]:g} null]".encode()
    lifted_point = f"/XYZ 56 {summary['D'][3] + 40:g} null]".encode()
    require(len(heading_point) == len(lifted_point) and report.count(heading_point) == 2, "the summary destination point is not a length-preserving twin anchor")
    # The /SD of `summary` rewritten to the next element (its paragraph).
    sd_summary = f"/SD [{summary['SD'][0]} 0 R".encode()
    sd_paragraph = f"/SD [{summary['SD'][0] + 1} 0 R".encode()
    twins = [
        ("a mismatched dc:title", "letter", replace_once(letter, b"warranty extension", b"warranty expansion")),
        ("an omitted dc:title", "invoice", replace_once(invoice, b"<dc:title>", b"<dc:titlf>")),
        ("DisplayDocTitle off", "letter", replace_once(letter, b"/DisplayDocTitle true", b"/DisplayDocTitle null")),
        ("MarkInfo off", "invoice", replace_once(invoice, b"/Marked true", b"/Marked null")),
        ("a page /Tabs /R", "letter", replace_once(letter, b"/Tabs /S", b"/Tabs /R")),
        ("a /D on the wrong page", "report", replace_once(report, d_summary, d_other)),
        ("a /D and /SD point off the heading", "report", report.replace(heading_point, lifted_point)),
        ("a /SD naming a paragraph", "report", replace_once(report, sd_summary, sd_paragraph)),
    ]
    for label, kind, twin in twins:
        try:
            check_reference(twin, kind)
        except (ValidationError, KeyError, ValueError, TypeError, AttributeError, IndexError, zlib.error):
            continue
        raise SystemExit(f"reference-documents checker accepted {label}")
    print(
        f"PASS reference-documents checker self-test: XMP dc:title, DisplayDocTitle, MarkInfo, and page /Tabs on {len(SNAPSHOTS)} "
        f"reference snapshots; {checked} paired /SD + /D destinations, links, and outline items resolved to their authored headings' "
        f"post-layout lines; {len(twins)} twins rejected",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--kind", choices=sorted(TITLES))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        elif args.pdf is not None and args.kind is not None:
            checked = check_reference(args.pdf.read_bytes(), args.kind)
            print(f"PASS {args.pdf}: {args.kind} metadata and {checked} destinations")
        else:
            parser.error("give a PDF with --kind, or --self-test")
    except ValidationError as error:
        raise SystemExit(f"reference-documents check failed: {error}") from error


if __name__ == "__main__":
    main()
