"""Inspect the public gallery scenarios independently of the Roc authoring code."""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
import re

from check_navigation import check_name_tree
from check_pdf_structure import require
from check_profile_declarations import validate_claims
from check_rich_flow import ARTIFACT, FONT, MARKED, paint
from check_rich_inline import page_marked_text
from check_source_foregrounds import inspect as inspect_foregrounds
from check_structure_semantics import Document, Ref, element_children, page_order, text_string


@dataclass
class Node:
    value: dict
    text: str
    children: list[Node]
    pages: set[int]
    marks: list[tuple[int, int]]

    @property
    def role(self) -> str:
        return self.value["S"]

    def descendants(self):
        yield self
        for child in self.children:
            yield from child.descendants()


def tagged(pdf: bytes) -> tuple[Document, list[int], Node]:
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    marks = {page: dict(page_marked_text(document, page)) for page in pages}

    def read(number: int) -> Node:
        value = document.get(number)
        text = []
        children = []
        owned = set()
        paint_ids = []
        for child in element_children(document, value):
            if isinstance(child, Ref):
                node = read(int(child))
                children.append(node)
                text.append(node.text)
                owned.update(node.pages)
                paint_ids.extend(node.marks)
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                page, mcid = int(child["Pg"]), int(child["MCID"])
                text.append(marks[page][mcid])
                owned.add(page)
                paint_ids.append((page, mcid))
        return Node(value, "".join(text), children, owned, paint_ids)

    return document, pages, read(int(document.get(int(catalog["StructTreeRoot"]))["K"]))


def artifacts(document: Document, pages: list[int], page: int, kind: bytes) -> str:
    content = document.stream(int(document.get(page)["Contents"]))
    return "".join(
        paint(document, page, pages.index(page), -1, block).text
        for declaration, block in ARTIFACT.findall(content)
        if kind in declaration and FONT.search(block)
    )


def only(nodes, role: str, contains: str) -> Node:
    found = [node for node in nodes if node.role == role and contains in node.text]
    require(len(found) == 1, f"expected one gallery {role} containing {contains!r}")
    return found[0]


def check_invoice(example: Path) -> None:
    document, pages, root = tagged((example / "tax-invoice-split.pdf").read_bytes())
    row = only(root.descendants(), "TR", "HF-INS-HRS/L5")
    require(len(row.pages) > 1, "the long service description must continue in one logical row")
    for page in sorted(row.pages, key=pages.index)[1:]:
        repeated = artifacts(document, pages, page, b"/Type /Pagination")
        require("Description" in repeated and "Amount (AUD)" in repeated, "a continued invoice row lost its repeated table header")
    footer = only(root.descendants(), "TFoot", "Total due (AUD)")
    require(len(footer.children) == 3 and len(footer.pages) == 1, "invoice totals must stay together")


def check_report(example: Path) -> None:
    document, _, root = tagged((example / "business-report-heat-map.pdf").read_bytes())
    image_streams = [
        document.stream(number)
        for number in document.bodies
        if isinstance(value := document.get(number), dict)
        and value.get("Subtype") == "Image"
        and (value.get("Width"), value.get("Height"), value.get("BitsPerComponent")) == (8, 4, 8)
    ]
    palette = {"L": (230, 239, 244), "M": (94, 168, 179), "H": (20, 73, 92)}
    expected = bytes(channel for shade in "LLMHHMMLLLLMMMLLLLLLMMMLLLMMMMMM" for channel in palette[shade])
    require(image_streams == [expected], "receiving heat map lost the packed RGB sample grid")
    require(any(node.role == "Figure" and text_string(node.value["Alt"]).startswith("Zone A reaches")
                for node in root.descendants()), "receiving heat map lost its pattern description")
    only(root.descendants(), "Caption", "Figure 3. Hourly receiving load by zone")
    only(root.descendants(), "P", "Pale blue means 0–7 bins")


def check_handbook(example: Path) -> None:
    document, pages, root = tagged((example / "operations-handbook.pdf").read_bytes())
    toc = only(root.descendants(), "TOC", "Appendix A. Command reference")
    require([part.role for part in toc.children] == ["TOCI"] * 4, "authored contents lost entry ownership")
    links = [child for child in toc.children[0].descendants() if child.role == "Link"]
    require(len(links[0].marks) >= 2, "the long authored contents title no longer wraps")
    front = document.stream(int(document.get(pages[0])["Contents"]))
    require(re.search(rb" 0\.6 0\.6 re", front) is not None, "indented contents item lost its decorative leaders")
    parts = [part for part in root.children if part.role == "Part"]
    require(len(parts) == 2, "handbook procedures and appendices need separate Part elements")
    rollback = only(parts[0].descendants(), "LI", "Roll back to the approved revision")
    require([node.role for node in rollback.children] == ["Lbl", "LBody"]
            and rollback.children[0].text == "3."
            and len(rollback.children[0].marks) == 1, "continued rollback item must own one step label")
    body = rollback.children[1]
    require([node.role for node in body.children] == ["P", "P", "Table", "Div"]
            and body.children[1].children[0].role == "Code"
            and "Recovery checks" in body.children[2].text, "rollback item lost rich child reading order")
    note = body.children[3]
    require(len(note.pages) == 2 and "First five minutes" in note.text and "Handover" in note.text,
            "post-rollback observation must remain one continued callout")
    for page in note.pages:
        content = document.stream(int(document.get(page)["Contents"]))
        rectangles = [
            tuple(Fraction(value.decode()) for value in rectangle)
            for kind, block in ARTIFACT.findall(content)
            if kind == b"<</Type /Layout>>" and b"0.933333333 0.956862745 0.909803922 scn" in block
            for rectangle in re.findall(rb"([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) re", block)
        ]
        require(len(rectangles) == 1, "each continued callout fragment needs one repeating artifact panel")
        x, y, width, height = rectangles[0]
        note_ids = {mcid for owner_page, mcid in note.marks if owner_page == page}
        for number, block in MARKED.findall(content):
            if int(number) in note_ids:
                left, bottom, right, top = paint(document, page, pages.index(page), int(number), block).bounds
                require(x + 12 <= left <= right <= x + width - 12 and y + 12 <= bottom <= top <= y + height - 12,
                        "continued callout text must keep its 12 pt panel padding")

    named = check_name_tree(document.bodies, document.root, pages)
    appendix = named[b"commands"][0]
    catalog = document.get(document.root)
    labels = document.get(int(catalog["PageLabels"]))["Nums"]
    require(labels[2] == pages.index(appendix) and labels[3]["S"] == "D"
            and labels[3].get("St", 1) == 1 and text_string(labels[3]["P"]) == "A-",
            "appendix page labels must restart at the command reference")
    require("Page A-1" in artifacts(document, pages, appendix, b"/Subtype /PageNum"),
            "appendix footer lost restarted page label")
    require("A-1" in toc.children[-1].text, "authored contents lost the appendix page label")
    only(parts[0].descendants(), "P", "command reference starts on page A-1")
    only(parts[0].descendants(), "TD", "commands p. A-1")
    opening = named[b"response"][0]
    require(not artifacts(document, pages, opening, b"/Subtype /Header")
            and "Incident response" in artifacts(document, pages, pages[pages.index(opening) + 1], b"/Subtype /Header"),
            "chapter opener and continuation no longer use their own headers")


def check_han(example: Path) -> None:
    document, pages, root = tagged((example / "ordered-han.pdf").read_bytes())
    phrase = "仓库交接"
    span = only(root.descendants(), "Span", phrase)
    require(span.text == phrase and text_string(span.value["Lang"]) == "zh-Hans", "Han phrase lost text or language")
    require(len(pages) == 2 and all(f"Receiving{phrase}" in artifacts(document, pages, page, b"/Subtype /Header") for page in pages),
            "running furniture lost its mixed-face text")
    require(only(root.descendants(), "TD", "28").text == "28", "ordered policy lost the number-only cell")


def check_pocket(example: Path) -> None:
    document, pages, root = tagged((example / "field-guide-pocket.pdf").read_bytes())
    require(all(document.get(page)["MediaBox"] == [0, 0, 306, 468] for page in pages),
            "pocket guide must use its exact custom page size")
    note = only(root.descendants(), "P", "A tiny, fast-running plover")
    card = only(root.descendants(), "Caption", "Pocket plover observation card")
    require(note.pages.isdisjoint(card.pages), "pocket guide should exercise a relaxed species note keep")
    details = only(root.descendants(), "Table", "Table 1. Survey details")
    counts = only(root.descendants(), "Table", "Table 2. Pocket survey counts")
    require(details.pages == counts.pages and len(details.pages) == 1, "required pocket survey sheet must stay together")


def check_source(example: Path) -> None:
    highlighted = (example / "source-blocks.pdf").read_bytes()
    plain = (example / "source-blocks-plain.pdf").read_bytes()
    text, glyphs, panels, roles = inspect_foregrounds(highlighted)
    other_text, other_glyphs, other_panels, other_roles = inspect_foregrounds(plain)
    require((text, [glyph[:5] for glyph in glyphs], panels, roles)
            == (other_text, [glyph[:5] for glyph in other_glyphs], other_panels, other_roles),
            "source colours changed selectable text, spacing or pagination")
    require("profile: café" in text and "# Worker slots  4 per zone" in text
            and len({glyph[1] for glyph in glyphs}) >= 2, "YAML lost accented value, tab expansion, or continuation")
    blue = [glyph for glyph in glyphs if glyph[5] == (0, 80, 160)]
    require("café" in "".join(glyph[0] for glyph in blue) and len({(glyph[1], glyph[3]) for glyph in blue}) >= 3,
            "YAML colour ranges must include café and cross a visual wrap")


def check_audit(example: Path) -> None:
    texts = []
    for setting in ("", "-archive", "-standard"):
        pdf = (example / f"audit-log{setting}.pdf").read_bytes()
        document, _, root = tagged(pdf)
        catalog = document.get(document.root)
        metadata = document.stream(int(catalog["Metadata"]))
        require((b"<pdfaid:part>4</pdfaid:part>" in metadata) == (setting != "-standard"), "audit profile lost its explicit PDF/A-4 choice")
        require((b"<pdfuaid:part>2</pdfuaid:part>" in metadata) == (setting == ""), "audit profile lost its exact PDF/UA-2 choice")
        if not setting:
            validate_claims(pdf)
        texts.append(root.text)
    require(texts[0] == texts[1] == texts[2] and texts[0].count("pallet seal checked and recorded.") == 72
            and all(f"{shift} dispatch 24" in texts[0] for shift in ("Morning", "Afternoon", "Evening")), "audit batches lost entries or changed between profiles")


def check_bilingual(example: Path) -> None:
    from check_bilingual_invoice import check
    check((example / "bilingual-invoice.pdf").read_bytes())


def check_arabic(example: Path) -> None:
    from check_arabic_invoice import check
    check((example / "arabic-invoice.pdf").read_bytes())


def check_hindi(example: Path) -> None:
    from check_hindi_statement import check
    check((example / "hindi-statement.pdf").read_bytes())


def check_thai(example: Path) -> None:
    from check_thai_notice import check
    check((example / "thai-notice.pdf").read_bytes())


CHECKS = {
    "thai-notice": check_thai,
    "hindi-statement": check_hindi,
    "arabic-invoice": check_arabic,
    "bilingual-invoice": check_bilingual,
    "audit-log": check_audit,
    "business-report": check_report,
    "field-guide": check_pocket,
    "operations-handbook": check_handbook,
    "ordered-han": check_han,
    "source-blocks": check_source,
    "tax-invoice": check_invoice,
}


def check_features(name: str, example: Path) -> None:
    if name in CHECKS:
        CHECKS[name](example)
        print(f"PASS {name} gallery structure", flush=True)
