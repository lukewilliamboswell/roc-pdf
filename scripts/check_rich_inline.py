#!/usr/bin/env python3
"""Independent logical-text and inline-structure checker for rich inline output.

It reuses only the byte-level value parser of the structure-semantics checker
and derives, without consulting the Roc package:

* the text of every marked-content sequence, by decoding each shown CID
  through its font's embedded /ToUnicode CMap;
* the logical text of every block element, by walking the structure tree in
  /K order, with each inline element rendered as ``[Role attrs:text]``;
* that logical (structure) order and content-stream (paint) order agree on
  every page, so a reader that extracts in paint order recovers the same
  text as one that follows the structure tree;
* that every inline element (Em, Strong, Code, Quote, Span, Link) owns text,
  every /E expansion names a Span with text, and every Link owns at least one
  OBJR, one per page its runs are painted on;
* optional dimension counts of inline elements and link annotations.

The self-test pins the exact rendering of the rich-inline snapshots and
rejects mutation twins for their intended reason. ``--pdfbox-extraction``
additionally compares PDFBox 3.0.8 text extraction of the one-page mixed
snapshot with the expected lines.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_pdf_structure import ValidationError, require  # noqa: E402
from check_structure_semantics import Document, Parser, Ref, page_order, text_string  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MIXED = ROOT / "tests" / "rich_inline" / "mixed.pdf"
ORDERED = ROOT / "tests" / "rich_inline" / "ordered.pdf"
PARAGRAPHS = ROOT / "tests" / "rich_inline" / "paragraphs_10.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
PDFBOX_SOURCE = ROOT / "scripts" / "PdfBoxTextExtract.java"

INLINE_ROLES = {"Em", "Strong", "Code", "Quote", "Span", "Link"}
BLOCK_ROLES = {"Title", "P", "H1", "H2", "H3", "H4", "H5", "H6", "Lbl", "LBody", "Caption", "Figure"}

TOKEN = re.compile(
    rb"\s*(?:(<<)|(>>)|(\[)|(\])|<([0-9A-Fa-f]*)>|/([^\s/<>\[\]()%{}]+)|([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+))|([A-Za-z'\"*]+))"
)


def to_unicode(document: Document, font: int) -> dict[int, str]:
    """CID -> text from the font's ToUnicode bfchar/bfrange blocks."""
    dictionary = document.get(font)
    require(dictionary.get("Subtype") == "Type0" and dictionary.get("Encoding") == "Identity-H", "shown font is not an Identity-H Type 0 font")
    cmap = document.stream(int(dictionary["ToUnicode"]))
    mappings: dict[int, str] = {}
    for block in re.findall(rb"beginbfchar\n(.*?)endbfchar", cmap, re.S):
        for source, target in re.findall(rb"<([0-9A-F]+)> <([0-9A-F]+)>", block):
            mappings[int(source, 16)] = bytes.fromhex(target.decode()).decode("utf-16-be")
    for block in re.findall(rb"beginbfrange\n(.*?)endbfrange", cmap, re.S):
        for low, high, target in re.findall(rb"<([0-9A-F]+)> <([0-9A-F]+)> <([0-9A-F]+)>", block):
            base = bytes.fromhex(target.decode()).decode("utf-16-be")
            for offset in range(int(low, 16), int(high, 16) + 1):
                mappings[offset] = base[:-1] + chr(ord(base[-1]) + offset - int(low, 16))
    require(mappings, "ToUnicode CMap maps no CID")
    return mappings


def page_marked_text(document: Document, page: int) -> list[tuple[int, str]]:
    """(MCID, decoded text) for each MCID-bearing marked-content sequence in stream order."""
    page_value = document.get(page)
    fonts = page_value.get("Resources", {}).get("Font", {})
    content = document.stream(int(page_value["Contents"]))
    decoders: dict[str, dict[int, str]] = {}
    stack: list[int | None] = []
    texts: dict[int, list[str]] = {}
    order: list[int] = []
    operands: list[object] = []
    current: dict[int, str] | None = None
    at = 0
    while at < len(content):
        if content[at] in b" \t\r\n":
            at += 1
            continue
        if content.startswith(b"<<", at):
            parser = Parser(content)
            parser.at = at
            operands.append(parser.value())
            at = parser.at
            continue
        match = TOKEN.match(content, at)
        require(match is not None and match.end() > at, f"unparseable content at {content[at:at + 20]!r}")
        at = match.end()
        if match.group(3) is not None:
            operands.append("[")
        elif match.group(4) is not None:
            items = []
            while operands and operands[-1] != "[":
                items.append(operands.pop())
            require(operands, "unbalanced content array")
            operands.pop()
            operands.append(list(reversed(items)))
        elif match.group(5) is not None:
            operands.append(bytes.fromhex(match.group(5).decode()))
        elif match.group(6) is not None:
            operands.append("/" + match.group(6).decode("latin-1"))
        elif match.group(7) is not None:
            operands.append(float(match.group(7)))
        else:
            operator = match.group(8).decode("latin-1")
            if operator == "BDC":
                properties = operands[-1]
                mcid = properties.get("MCID") if isinstance(properties, dict) else None
                stack.append(mcid)
                if mcid is not None:
                    require(mcid not in texts, f"MCID {mcid} is marked twice on one page")
                    texts[mcid] = []
                    order.append(mcid)
            elif operator == "BMC":
                stack.append(None)
            elif operator == "EMC":
                require(stack, "EMC without an open marked-content sequence")
                stack.pop()
            elif operator == "Tf":
                name = str(operands[-2])[1:]
                require(name in fonts, f"content selects an undeclared font /{name}")
                if name not in decoders:
                    decoders[name] = to_unicode(document, int(fonts[name]))
                current = decoders[name]
            elif operator in ("Tj", "TJ"):
                shown = operands[-1]
                strings = [shown] if isinstance(shown, bytes) else [item for item in shown if isinstance(item, bytes)]
                owner = next((mcid for mcid in reversed(stack) if mcid is not None), None)
                require(owner is not None, "text is shown outside any MCID-bearing marked content")
                require(current is not None, "text is shown before a font is selected")
                for string in strings:
                    require(len(string) % 2 == 0, "Identity-H string has an odd byte length")
                    for index in range(0, len(string), 2):
                        cid = int.from_bytes(string[index : index + 2], "big")
                        require(cid in current, f"CID {cid} has no ToUnicode mapping")
                        texts[owner].append(current[cid])
            operands = []
    require(not stack, "marked content is not balanced")
    return [(mcid, "".join(texts[mcid])) for mcid in order]


class Inline:
    def __init__(self) -> None:
        self.inline_elements = 0
        self.links = 0


def render(pdf: bytes, dimensions: dict[str, int] | None = None) -> list[str]:
    """Logical block renderings in structure order; validates the generic invariants."""
    dimensions = dimensions or {}
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    marked: dict[tuple[int, int], str] = {}
    paint_order: list[str] = []
    for page in pages:
        for mcid, text in page_marked_text(document, page):
            require(text, f"MCID {mcid} on page {pages.index(page)} shows no text")
            marked[(page, mcid)] = text
            paint_order.append(text)
    counts = Inline()
    logical_order: list[str] = []
    blocks: list[str] = []

    def walk(number: int) -> str:
        element = document.get(number)
        role = str(element["S"])
        facts = []
        if "Lang" in element:
            facts.append(f"Lang={text_string(element['Lang'])}")
        if "E" in element:
            require(role == "Span", "/E appears on a role other than Span")
            facts.append(f"E={text_string(element['E'])}")
        if "ActualText" in element:
            facts.append(f"ActualText={text_string(element['ActualText'])}")
        children = element.get("K", [])
        if not isinstance(children, list):
            children = [children]
        pieces: list[str] = []
        annotations: list[str] = []
        for child in children:
            if isinstance(child, Ref):
                pieces.append(walk(int(child)))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                key = (int(child["Pg"]), int(child["MCID"]))
                require(key in marked, "a structure MCR names an MCID with no shown text")
                logical_order.append(marked[key])
                pieces.append(marked[key])
            elif isinstance(child, dict) and child.get("Type") == "OBJR":
                annotation = document.get(int(child["Obj"]))
                action = annotation.get("A", {})
                if action.get("S") == "URI":
                    annotations.append("uri " + action["URI"].decode("latin-1"))
                elif action.get("S") == "GoTo":
                    require("SD" in action and "D" in action, "an internal link lacks paired /SD and /D destinations")
                    annotations.append("goto")
                else:
                    raise ValidationError(f"link annotation action {action.get('S')!r} is unsupported")
        text = "".join(pieces)
        if role in INLINE_ROLES:
            counts.inline_elements += 1
            require(re.sub(r"\[[^:\]]*:", "", text).replace("]", ""), f"/{role} owns no text")
            if role == "Link":
                counts.links += len(annotations)
                require(annotations, "a Link owns no link annotation")
                facts.append("(" + ", ".join(annotations) + ")")
            label = " ".join([role] + facts)
            return f"[{label}:{text}]"
        if role in BLOCK_ROLES:
            blocks.append(" ".join([role] + facts) + ": " + text)
        return text

    tree_root = document.get(int(catalog["StructTreeRoot"]))
    walk(int(tree_root["K"]))
    require("".join(logical_order) == "".join(paint_order), "structure order and paint order disagree on the shown text")
    expected_inline = dimensions.get("inline_elements")
    if expected_inline is not None:
        require(counts.inline_elements == expected_inline, f"expected {expected_inline} inline elements, found {counts.inline_elements}")
    expected_links = dimensions.get("link_annotations")
    if expected_links is not None:
        require(counts.links == expected_links, f"expected {expected_links} link annotations, found {counts.links}")
    return blocks


def validate_rich_inline_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    render(pdf, dimensions)


MIXED_EXPECTED = [
    "Title: Quarterly summary",
    "H1: 1 Summary",
    "P: Q1 [Span E=financial year 2027:FY2027]: July to September 2026 · Prepared by the finance team.",
    "P: Revenue rose [Strong:5.0%] to AUD 9.22 million, led by [Em:Queensland]. Freight costs fell for the second quarter; see "
    "[Link (goto):section 3, [Em:Operations]].",
    "P: Revenue is reported net of [Span E=Goods and Services Tax:GST]. Stock counts come from the warehouse system [Code:WMS-7], "
    "which records every [Span Lang=fr:Cafetière « Élégance »] shipment.",
    "H1: 3 Operations",
    "P: Our oak supplier [Span Lang=fr:Atelier Beaulieu] puts it simply: [Quote:[Span Lang=fr:« Le bois ne ment pas. »]] Read "
    "[Link (uri https://harbourfinch.example/sustainability):our published sustainability commitments, including the "
    "[Strong:2026 timber audit] and its appendix] before the next review.",
    "P: [Em:Nested [Strong:strong and [Code:code]] text] closes the summary.",
    "Lbl: •",
    "LBody: Receiving hours are 7 am to 3 pm",
    "Lbl: •",
    "LBody: Dispatch follows confirmation order",
    "P: A plain paragraph shares the page with rich text.",
]

ORDERED_EXPECTED = ["P: [Span Lang=fr:Café][Span Lang=zh-Hans:中][Em:PDF]"]

# Lines keep their painted trailing space before each soft break.
PDFBOX_EXPECTED = (
    "Quarterly summary\n1 Summary\nQ1 FY2027: July to September 2026 · Prepared by the finance team.\n"
    "Revenue rose 5.0% to AUD 9.22 million, led by Queensland. Freight costs fell for the \n"
    "second quarter; see section 3, Operations.\n"
    "Revenue is reported net of GST. Stock counts come from the warehouse system \n"
    "WMS-7, which records every Cafetière « Élégance » shipment.\n3 Operations\n"
    "Our oak supplier Atelier Beaulieu puts it simply: « Le bois ne ment pas. » Read our \n"
    "published sustainability commitments, including the 2026 timber audit and its \n"
    "appendix before the next review.\nNested strong and code text closes the summary.\n"
    "• Receiving hours are 7 am to 3 pm\n• Dispatch follows confirmation order\n"
    "A plain paragraph shares the page with rich text.\n"
)


def mutate(value: bytes, old: bytes, new: bytes) -> bytes:
    require(value.count(old) >= 1, f"mutation anchor {old!r} is absent")
    return value.replace(old, new, 1)


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-rich-inline-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, "PDFBox extractor compilation failed")
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0 and not result.stderr, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(result.stdout == PDFBOX_EXPECTED.encode(), f"PDFBox extracted {result.stdout.decode()!r}, expected {PDFBOX_EXPECTED!r}")
    print("PASS rich-inline PDFBox 3.0.8 extraction: exact logical text across styled runs, spans, and wrapped links")


def self_test() -> None:
    mixed = MIXED.read_bytes()
    require(render(mixed) == MIXED_EXPECTED, f"mixed rich-inline rendering changed: {render(mixed)!r}")
    require(render(ORDERED.read_bytes()) == ORDERED_EXPECTED, "ordered rich-inline rendering changed")
    render(PARAGRAPHS.read_bytes())
    expansion = re.search(rb"/E <[0-9A-F]+> /K \[[^\]]*\] /NS [0-9]+ 0 R /P [0-9]+ 0 R /S /Span ", mixed)
    require(expansion is not None, "mixed snapshot has no expansion Span")
    twins = [
        ("structure order swapped against paint order", mutate(mutate(mutate(mixed, b"<< /MCID 6 /Pg", b"<< /MCID X /Pg"), b"<< /MCID 7 /Pg", b"<< /MCID 6 /Pg"), b"<< /MCID X /Pg", b"<< /MCID 7 /Pg"), "structure order and paint order disagree"),
        ("a Link without an OBJR", mutate(mixed, b"/Type /OBJR", b"/Type /OBJX"), "a Link owns no link annotation"),
        ("an expansion on a non-Span role", mutate(mixed, expansion.group(0), expansion.group(0)[:-6] + b"/Code "), "/E appears on a role other than Span"),
        ("a missing ToUnicode mapping", mutate(mixed, b"beginbfchar", b"beginbfchaR"), "ToUnicode CMap maps no CID"),
    ]
    rejected = 0
    for label, source, reason in twins:
        try:
            render(source)
        except ValidationError as error:
            require(reason in str(error), f"rich-inline twin {label!r} was rejected for {error}, not {reason!r}")
            rejected += 1
            continue
        raise SystemExit(f"rich-inline checker accepted {label}")
    print(
        "PASS rich-inline checker self-test: ToUnicode-decoded logical text, structure/paint order agreement, "
        f"inline roles, /E, /Lang, and link annotations pinned on 2 snapshots; {rejected} mutation twins rejected",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--pdfbox-extraction", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None:
        parser.error("pdf is required unless --self-test is used")
    for line in render(args.pdf.read_bytes()):
        print(line)
    print(f"PASS {args.pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(args.pdf.resolve())


if __name__ == "__main__":
    main()
