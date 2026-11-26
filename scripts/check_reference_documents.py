#!/usr/bin/env python3
"""Independent checks of the reference invoice, report, and letter.

Reusing only the byte-level value parser of the structure-semantics checker,
and never the Roc package, it proves on the reference snapshots that:

* metadata: the XMP packet's ``dc:title`` (``x-default``) equals the
  metadata title fixed by docs/contributors/reference-documents.adoc, the catalog sets
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
its fixture snapshot, then checks the references and accepted variants for
authored text landmarks in logical order, visible titles, and owned external
links. Mutation twins cover a changed payment URI, a mismatched and an omitted
``dc:title``, ``DisplayDocTitle`` and ``MarkInfo`` switched off, a page
``/Tabs`` changed, a ``/D`` on the wrong page, a ``/D`` point moved off the
heading, and a ``/SD`` naming a paragraph.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_rich_inline import page_marked_text  # noqa: E402
from text_positions import shown_cids  # noqa: E402
from pdf_layout import LayoutError, mutate as layout_mutate, occurrences as layout_occurrences, twin as layout_twin  # noqa: E402
from check_pdf_structure import ValidationError, require, to_unicode_mappings  # noqa: E402
from check_structure_semantics import Document, Ref, element_children, page_order, text_string  # noqa: E402

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
    "invoice_long_text": ROOT / "tests" / "reference_documents" / "invoice_long_text.pdf",
    "invoice_wide_code": ROOT / "tests" / "reference_documents" / "invoice_wide_code.pdf",
    "invoice_split_row": ROOT / "tests" / "reference_documents" / "invoice_split_row.pdf",
    "invoice_totals_carry": ROOT / "tests" / "reference_documents" / "invoice_totals_carry.pdf",
    "invoice_50": ROOT / "tests" / "reference_documents" / "invoice_50.pdf",
    "invoice_500": ROOT / "tests" / "reference_documents" / "invoice_500.pdf",
    "report_figure_caption": ROOT / "tests" / "reference_documents" / "report_figure_caption.pdf",
    "report_ordered": ROOT / "tests" / "reference_documents" / "report_ordered.pdf",
    "report_scaled_figure": ROOT / "tests" / "reference_documents" / "report_scaled_figure.pdf",
    "letter_long_recipient": ROOT / "tests" / "reference_documents" / "letter_long_recipient.pdf",
    "letter_20": ROOT / "tests" / "reference_documents" / "letter_20.pdf",
    "letter_60": ROOT / "tests" / "reference_documents" / "letter_60.pdf",
    "letter_200": ROOT / "tests" / "reference_documents" / "letter_200.pdf",
    "report_heading_keep": ROOT / "tests" / "reference_documents" / "report_heading_keep.pdf",
    "report_table_break": ROOT / "tests" / "reference_documents" / "report_table_break.pdf",
    "report_sections_10": ROOT / "tests" / "reference_documents" / "report_sections_10.pdf",
    "report_sections_100": ROOT / "tests" / "reference_documents" / "report_sections_100.pdf",
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

HEADING_LEADING = 21.0
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
    references = [kid for kid in element_children(document, element) if isinstance(kid, dict) and kid.get("Type") == "MCR"]
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
    kids = element_children(document, element)
    text = ""
    for kid in kids:
        page = int(kid["Pg"])
        content = document.stream(int(document.get(page)["Contents"]))
        start = content.index(b"<</MCID " + str(kid["MCID"]).encode() + b">> BDC")
        end = content.index(b"EMC", start)
        segment = content[start:end]
        font_name = re.search(rb"/(F[0-9_]+) [0-9.]+ Tf", segment).group(1)
        mapping = fonts.setdefault(font_name, font_map(document, page, font_name))
        text += "".join(mapping[cid] for cid in shown_cids(segment))
    return text


def font_map(document: Document, page: int, name: bytes) -> dict[int, str]:
    resources = document.get(page)["Resources"]
    resources = document.get(int(resources)) if isinstance(resources, Ref) else resources
    font = document.get(int(resources["Font"][name.decode()]))
    cmap = document.stream(int(font["ToUnicode"]))
    mapping = {cid: "".join(chr(scalar) for scalar in scalars) for cid, scalars in to_unicode_mappings(cmap).items()}
    return mapping


def check_destinations(document: Document, pages: list[int], expected: dict[str, str], link_targets: list[str]) -> int:
    page_index = {page: index for index, page in enumerate(pages)}
    catalog = document.get(document.root)
    entries = []
    pending = [int(catalog["Names"]["Dests"])]
    visited = set()
    while pending:
        number = pending.pop()
        require(number not in visited, "destination name tree contains a repeated node")
        visited.add(number)
        value = document.get(number)
        if "Kids" in value:
            pending.extend(reversed(value["Kids"]))
        else:
            entries.extend(value["Names"])
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
    observed_links: list[str] = []
    for page in pages:
        for annotation in document.get(page).get("Annots", []):
            action = document.get(int(annotation)).get("A", {})
            if action.get("S") != "GoTo":
                continue
            pair = resolve(document, action, page_index, "link annotation")
            require(pair[1] in by_element and named[by_element[pair[1]]] == pair, "a link's /D and /SD are not its named destination's")
            observed_links.append(by_element[pair[1]])
            checked += 1
    require(observed_links == link_targets, "internal links differ from the authored target sequence")
    outline = document.get(int(catalog["Outlines"]))
    item = outline.get("First")
    stack = []
    observed_outlines: list[str] = []
    while item is not None:
        value = document.get(int(item))
        destination = value.get("Dest")
        require(isinstance(destination, bytes), "an outline item has no named /Dest")
        require(destination.decode("latin-1") in named, "an outline item names an unknown destination")
        require(text_string(value["Title"]) == expected[destination.decode("latin-1")], "an outline title differs from its heading")
        observed_outlines.append(destination.decode("latin-1"))
        checked += 1
        if "First" in value:
            stack.append(value.get("Next"))
            item = value["First"]
        else:
            item = value.get("Next")
            while item is None and stack:
                item = stack.pop()
    require(observed_outlines == list(expected), "outline items differ from the authored sequence")
    return checked


READING_LANDMARKS = {
    "invoice": ("Tax invoice", "Bill to", "Items", "Payment", "pay invoice HF-2026-0417 online"),
    "report": (
        "Quarterly operations report", "1 Summary", "section 3, Supply chain", "2 Sales performance",
        "3 Supply chain", "3.1 Freight", "3.2 Timber sourcing", "4 Outlook", "Appendix A. Supplier register",
    ),
    "letter": (
        "21 September 2026", "Dear Ms Raman,", "Extended warranty for your Level 2–5 fit-out",
        "Yours sincerely,", "Tom Finch", "Schedule 1. Covered items",
    ),
}

URI_LINKS = {
    "invoice": {"https://pay.harbourfinch.example/invoices/HF-2026-0417": "pay invoice HF-2026-0417 online"},
    "report": {"https://www.harbourfinch.example/sustainability": "our published sustainability commitments"},
    "letter": {},
}

VISIBLE_TITLES = {
    "invoice": ["Tax invoice"],
    "report": ["Quarterly operations report"],
    "letter": [],
}


def without_space(text: str) -> str:
    return "".join(text.split())


def check_reading_order(document: Document, pages: list[int], kind: str, sections: int) -> None:
    # Decode glyphs from the page streams, then read them in the structure
    # dictionary's /K order. Furniture and table-header repaints carry no MCID.
    marked = {(page, mcid): text for page in pages for mcid, text in page_marked_text(document, page)}
    root = document.get(int(document.get(document.root)["StructTreeRoot"]))["K"]
    titles: list[str] = []
    links: dict[str, str] = {}

    def read(number: int) -> str:
        element = document.get(number)
        pieces: list[str] = []
        uris: set[str] = set()
        for kid in element_children(document, element):
            if isinstance(kid, Ref):
                pieces.append(read(int(kid)))
            elif kid.get("Type") == "MCR":
                pieces.append(marked[(int(kid["Pg"]), int(kid["MCID"]))])
            elif kid.get("Type") == "OBJR":
                action = document.get(int(kid["Obj"])).get("A", {})
                if action.get("S") == "URI":
                    uris.add(text_string(action["URI"]))
        text = "".join(pieces)
        if element["S"] == "Title":
            titles.append(text)
        if uris:
            require(element["S"] == "Link" and len(uris) == 1, "URI annotations must belong to one logical link and agree on its action")
            uri = next(iter(uris))
            require(uri not in links, f"URI {uri} has multiple logical links")
            links[uri] = without_space(text)
        return text

    logical = without_space(read(int(root)))
    require(titles == VISIBLE_TITLES[kind], f"{kind} has unexpected visible titles {titles!r}")
    offset = 0
    landmarks = READING_LANDMARKS[kind]
    if sections:
        landmarks = ("Quarterly operations report", *(f"{index} Operations area {index}" for index in range(1, sections + 1)))
    for text in landmarks:
        key = without_space(text)
        start = logical.find(key, offset)
        require(start >= 0, f"{kind} logical reading order lost or moved {text!r}")
        offset = start + len(key)
    expected_links = {} if sections else URI_LINKS[kind]
    require(links == {uri: without_space(label) for uri, label in expected_links.items()}, f"{kind} external link destination or label differs from its authored value")


def check_reference(pdf: bytes, label: str) -> int:
    kind = kind_of(label)
    sections = int(label.rsplit("_", 1)[1]) if label.startswith("report_sections_") else 0
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    check_metadata(document, TITLES[kind], pages)
    check_reading_order(document, pages, kind, sections)
    if sections:
        expected = {f"section-{index}": f"{index} Operations area {index}" for index in range(1, sections + 1)}
        return check_destinations(document, pages, expected, [*(f"section-{index}" for index in range(2, sections + 1)), "section-1"])
    if kind == "report":
        return check_destinations(document, pages, REPORT_DESTINATIONS, ["supply-chain"])
    require("Names" not in catalog and "Outlines" not in catalog, f"the {kind} has destinations it did not author")
    return 0


def kind_of(label: str) -> str:
    return label.split("_", 1)[0]


def replace_once(value: bytes, old: bytes, new: bytes) -> bytes:
    require(len(old) == len(new), "mutation twins must preserve length")
    try:
        return layout_twin(value, old, new, exactly_once=False)
    except LayoutError as error:
        raise ValidationError(str(error)) from error


SCALE_PAIRS = (
    ("reference invoice rows x50", "reference invoice rows x500 (INV-A3)"),
    ("reference report sections x10", "reference report sections x100"),
    ("reference letter x20", "reference letter x200"),
    ("reference statement batch x10", "reference statement batch x100"),
)


def check_scale_pairs() -> None:
    # The pinned harness checks the registered counters against executions.
    # Here the two accepted counter vectors are also checked as a pair.
    cases = {case["name"]: case for case in json.loads((ROOT / "tests/spec.json").read_text())["cases"]}
    for small_name, large_name in SCALE_PAIRS:
        for target in ("arm64mac", "x64musl"):
            small = cases[small_name]["expectations"][target]
            large = cases[large_name]["expectations"][target]
            require(large["allocations"] <= 10 * small["allocations"], f"{large_name} {target}: allocation growth exceeds the 10× input ratio")
            for key in ("pages", "fragments", "report_blocks", "report_obligations", "report_coverage"):
                # Report continuation headers contribute three extra cell
                # runs per repeated row beyond the authored body scale.
                extra = 3 * large["work"]["repeated_headers"] if key == "report_coverage" and "report" in large_name else 0
                require(large["work"][key] <= 10 * small["work"][key] + extra,
                        f"{large_name} {target}: {key} growth exceeds the 10× input ratio and header allowance")


def check_statement_batch(count: int) -> None:
    snapshot = ROOT / "tests" / "reference_documents" / f"statements_{count}.pdf"
    document = Document(snapshot.read_bytes())
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    require(len(pages) == count, f"statement batch must have one page per account ({count})")
    check_metadata(document, "September 2026 account statements", pages)
    for account, page in enumerate(pages, start=1001):
        logical = without_space("".join(text for _, text in page_marked_text(document, page)))
        expected = without_space(
            f"Account {account} Statement period: 1 to 30 September 2026 Transactions Description Amount "
            "Opening balance 200.00 Payment received −25.00 Balance due: AUD 175.00"
        )
        require(logical == expected, f"statement for account {account} differs from its authored text or order")


def self_test() -> None:
    check_scale_pairs()
    for count in (10, 100):
        check_statement_batch(count)
    for kind, example in GALLERY.items():
        require(example.read_bytes() == SNAPSHOTS[kind].read_bytes(), f"{example.relative_to(ROOT)} differs from the {kind} fixture snapshot")
    checked = 0
    for label, path in SNAPSHOTS.items():
        checked += check_reference(path.read_bytes(), label)
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
    require(len(heading_point) == len(lifted_point) and layout_occurrences(report, heading_point, "objects") == 2, "the summary destination point is not a length-preserving twin anchor")
    # The /SD of `summary` rewritten to the next element (its paragraph).
    sd_summary = f"/SD [{summary['SD'][0]} 0 R".encode()
    sd_paragraph = f"/SD [{summary['SD'][0] + 1} 0 R".encode()
    letter_document = Document(letter)
    letter_tree = letter_document.get(letter_document.root)["StructTreeRoot"]
    letter_root = letter_document.get(letter_document.get(int(letter_tree))["K"])
    first = list(letter_root["K"][:5])
    swapped = [*first[:3], first[4], first[3]]
    salutation_order = ("/K [" + " ".join(f"{node} 0 R" for node in first)).encode()
    swapped_order = ("/K [" + " ".join(f"{node} 0 R" for node in swapped)).encode()
    twins = [
        ("moved salutation in logical order", "letter", layout_mutate(letter, salutation_order, swapped_order, occurrences=1, scope="objects")),
        ("a changed payment URI", "invoice", replace_once(invoice, b"pay.harbourfinch.example", b"pay.harbourfinch.invalid")),
        ("a mismatched dc:title", "letter", replace_once(letter, b"warranty extension", b"warranty expansion")),
        ("an omitted dc:title", "invoice", replace_once(invoice, b"<dc:title>", b"<dc:titlf>")),
        ("DisplayDocTitle off", "letter", replace_once(letter, b"/DisplayDocTitle true", b"/DisplayDocTitle null")),
        ("MarkInfo off", "invoice", replace_once(invoice, b"/Marked true", b"/Marked null")),
        ("a page /Tabs /R", "letter", replace_once(letter, b"/Tabs /S", b"/Tabs /R")),
        ("a /D on the wrong page", "report", replace_once(report, d_summary, d_other)),
        ("a /D and /SD point off the heading", "report", layout_mutate(report, heading_point, lifted_point, occurrences=2, scope="objects")),
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
        f"post-layout lines; four scale pairs and {len(twins)} rejected twins",
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
