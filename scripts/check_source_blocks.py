#!/usr/bin/env python3
"""Independent source-block structure, measured geometry and whole-file readers.

The byte oracle decodes actual CIDs through embedded ToUnicode mappings and
checks the canonical /Code ActualText separately. Reader mode passes the exact
whole emitted PDF to PDFBox and optional MuPDF; no per-page PDF is rewritten.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
from fractions import Fraction
from pathlib import Path

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text, text_string, to_unicode
from check_structure_semantics import Document, Ref, element_children, page_order
from check_visual_renderers import read_ppm
from text_positions import glyph_positions, shown_strings

ROOT = Path(__file__).resolve().parents[1]
PDFBOX = ROOT / "vendor/pdfbox/pdfbox-app-3.0.8.jar"
MARKED = re.compile(rb"/[A-Za-z0-9]+ <</MCID ([0-9]+)>> BDC\n(.*?)\nEMC", re.S)
ARTIFACT = re.compile(rb"/Artifact <</Type /Layout>> BDC\n(.*?)\nEMC", re.S)
FONT = re.compile(rb"/([A-Za-z0-9_]+) ([0-9.]+) Tf")
RECT = re.compile(rb"(-?[0-9.]+) (-?[0-9.]+) ([0-9.]+) ([0-9.]+) re\nf")
URL = "https://example.test/releases/download/package/abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789.tar.zst"
SHORT = "    let value = 42\n\n\n  print(value)  \n"
UNICODE = '  let café = "Ångström"\n\n  print("naïve café")\n'
BODY = ("Body before source.", "Body after source.", "Body spacing stays unchanged.")


def expected_source(dimensions: dict[str, int]) -> str:
    scenario = dimensions["source_scenario"]
    if scenario in (0, 5):
        return SHORT
    if scenario in (1, 2):
        return "\n".join(f'line {line} = "kept exactly once"' for line in range(1, dimensions["source_lines"] + 1))
    if scenario == 3:
        return URL + "\n" + "x" * 220 + "\n  final = 42"
    if scenario == 4:
        return UNICODE
    if scenario == 12:
        return "中\n\n中\n"
    if scenario == 11:
        return SHARED_SOURCE + "Between source blocks." + DISTINCT_SOURCE + SHARED_SOURCE
    if scenario == 10:
        return "a\n\n    b\n"
    if scenario == 9:
        return ""
    if scenario == 8:
        return "中\n\n中\n"
    if scenario == 7:
        return "defaults = 42\nnext = defaults"
    if scenario == 6:
        return "\n" * dimensions["source_lines"]
    raise ValidationError(f"unknown source scenario {scenario}")


def widths(document: Document, font: int) -> dict[int, int]:
    descendant = document.get(int(document.get(font)["DescendantFonts"][0]))
    entries = descendant["W"]
    result: dict[int, int] = {}
    index = 0
    while index < len(entries):
        first = int(entries[index])
        values = entries[index + 1]
        if isinstance(values, list):
            result.update((first + offset, int(value)) for offset, value in enumerate(values))
            index += 2
        else:
            result.update((cid, int(entries[index + 2])) for cid in range(first, int(values) + 1))
            index += 3
    return result



def decoded_text(block: bytes, mapping: dict[int, str]) -> str:
    parts: list[str] = []
    for raw in shown_strings(block):
        data = bytes.fromhex(raw.decode())
        require(len(data) % 2 == 0, "source string is not two-byte CIDs")
        for index in range(0, len(data), 2):
            cid = int.from_bytes(data[index:index + 2], "big")
            require(cid in mapping, "source CID has no Unicode mapping")
            parts.append(mapping[cid])
    return "".join(parts)

def validate_source_blocks_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    source = expected_source(dimensions)
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog["Pages"]), pages)
    if "pages" in dimensions:
        require(len(pages) == dimensions["pages"], "source pagination changed")
    codes: list[str] = []
    logical: list[str] = []
    marked = {(page, mcid): text for page in pages for mcid, text in page_marked_text(document, page)}

    def walk(number: int) -> None:
        element = document.get(number)
        if element["S"] == "Code":
            require("ActualText" in element or source == "", "Code lacks its canonical source ActualText")
            codes.append(text_string(element["ActualText"]) if "ActualText" in element else "")
        for child in element_children(document, element):
            if isinstance(child, Ref):
                walk(int(child))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                key = (int(child["Pg"]), int(child["MCID"]))
                require(key in marked, "source MCR owns no shown text")
                logical.append(marked[key])
    tree = document.get(int(catalog["StructTreeRoot"]))
    walk(int(tree["K"]))
    require(codes == [source], "canonical source, tabs, LF/CRLF, blank lines, or trailing spaces changed")
    paint: list[str] = []
    source_paint: list[str] = []
    source_rows: list[tuple[int, Fraction]] = []
    body_rows: dict[str, tuple[int, Fraction]] = {}
    declared_fonts: set[int] = set()
    selected_fonts: set[int] = set()
    panel_count = 0
    panel_height = Fraction(0)
    for page_index, page in enumerate(pages):
        value = document.get(page)
        fonts = value.get("Resources", {}).get("Font", {})
        content = document.stream(int(value["Contents"]))
        used_fonts = {name.decode() for name, _ in FONT.findall(content)}
        require(used_fonts <= set(fonts), "source page omits a selected font")
        declared_fonts.update(int(font) for font in fonts.values())
        selected_fonts.update(int(fonts[name]) for name in used_fonts)
        mappings = {name: to_unicode(document, int(fonts[name])) for name in used_fonts}
        advances = {name.encode(): widths(document, int(fonts[name])) for name in used_fonts}
        if dimensions["source_scenario"] == 7:
            artifacts = re.findall(rb"/Artifact.*?BDC\n(.*?)\nEMC", content, re.S)
            text_artifacts = [block for block in artifacts if b" Tf" in block]
            require(len(text_artifacts) == 1 and FONT.findall(text_artifacts[0])[0][1] == b"8", "source changed independent furniture typography")
        panels = []
        for artifact in ARTIFACT.findall(content):
            require(b"/MCID" not in artifact and b" Tf" not in artifact, "source panel owns text")
            require(b"0.941176471 0.949019608 0.960784314 scn" in artifact, "source background color changed")
            for rectangle in RECT.findall(artifact):
                x, y, width, height = (Fraction(part.decode()) for part in rectangle)
                require(x == 72 and width == 451 and y >= 72 and y + height <= 770, "source panel escapes the body frame")
                panels.append((x, y, width, height))
                panel_height += height
        panel_count += len(panels)
        for match in MARKED.finditer(content):
            block = match.group(2)
            selected = FONT.findall(block)
            require(len(selected) == 1, "source paint does not select exactly one font")
            name, size_text = selected[0]
            size = Fraction(size_text.decode())
            mapping = mappings[name.decode()]
            text = decoded_text(block, mapping)
            paint.append(text)
            origins = re.findall(rb"1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm", block)
            require(len(origins) == 1, "source fixture text lacks its explicit placement transform")
            tx, ty = (Fraction(part.decode()) * 1000 for part in origins[0])
            positions = [(font, cid, x + tx, y + ty) for font, cid, x, y in glyph_positions(block, advances)]
            require(positions, "blank source line invented an empty painted run")
            y = positions[0][3] / 1000
            font_name = str(document.get(int(fonts[name.decode()]))["BaseFont"])
            if "SourceCodePro" in font_name or "NotoSCCJKFixture" in font_name:
                require(size == 9, "source size changed body or lost local typography")
                if dimensions["source_scenario"] != 7:
                    require(b"0.078431373 0.156862745 0.31372549 scn" in block, "source local text color changed")
                require(not re.search(rb"(?:^|\n)(?:W|W\*|[4-7] Tr)(?:\n|$)", block), "source text was clipped")
                source_paint.append(text)
                source_rows.append((page_index, y))
                if dimensions["source_scenario"] != 7:
                    require(len(panels) == 1, "source fragment lacks its one artifact panel")
                    x0, y0, width, height = panels[0]
                    require(y0 + 8 <= y <= y0 + height - 8, "source baseline escapes its padded fragment")
                for font, cid, x, _ in positions:
                    require(x >= 80000 and x + advances[font][cid] * 9 <= 515001, "source glyph exceeds the padded width")
                if panels:
                    require(content.index(ARTIFACT.search(content).group(0)) < match.start(), "source panel paints over its text")
            else:
                require(size == 11 and text in BODY, "ordinary body text changed")
                body_rows[text] = (page_index, y)
    require(declared_fonts == selected_fonts, "source document retains a globally unused font")
    require(paint == logical, "source paint order differs from semantic order")
    require("".join(source_paint) == source.replace("\n", ""), "source characters were dropped, repeated, or reordered by wrapping/continuation")
    if dimensions["source_scenario"] in (6, 9, 10, 12):
        require(not body_rows, "blank-only source invented body content")
    else:
        require(set(body_rows) == set(BODY), "source changed surrounding body content")
        after_page, after_y = body_rows[BODY[1]]
        next_page, next_y = body_rows[BODY[2]]
        require(after_page == next_page and after_y - next_y == 23, "ordinary body leading or paragraph spacing changed")
    if dimensions["source_scenario"] in (7, 9):
        require(panel_count == 0, "default source invented a background")
    else:
        require(panel_count >= 1, "source has no panel")
    scenario = dimensions["source_scenario"]
    if scenario in (0, 5):
        require(len(source_rows) == 2 and source_rows[0][1] - source_rows[1][1] == 36, "consecutive blank source rows lost their leading")
        require(panel_height == 76, "trailing empty source row or padding disappeared")
    elif scenario in (4, 8, 10, 12):
        require(len(source_rows) == 2 and source_rows[0][1] - source_rows[1][1] == 24, "Unicode blank source row changed")
        require(panel_height == 64, "Unicode terminal blank source row changed")
    elif scenario in (1, 2):
        require(len(source_rows) == dimensions["source_lines"], "source line appeared more than once or disappeared")
        require(panel_height == 12 * dimensions["source_lines"] + 16 * panel_count, "source fragment padding or local leading changed")
        require(panel_count >= 2, "long source did not continue across pages")
        if scenario == 2:
            require(source_rows[0][0] == 0 and source_rows[0][1] <= 140, "near-bottom source moved whole instead of continuing")
    elif scenario == 3:
        require(len(source_rows) == 6 and panel_height == 88, "measured source wrapping is not the six expected visual rows")
        require(source_paint[0].endswith("/") and source_paint[1] == URL.rsplit("/", 1)[1], "URL failed to wrap at the useful slash boundary")
        require("".join(source_paint[2:-1]) == "x" * 220 and source_paint[-1] == "  final = 42", "oversized token fallback lost characters")
    elif scenario == 7:
        require(len(source_rows) == 2 and source_rows[0][1] - source_rows[1][1] == 12, "default source leading changed")
    elif scenario == 6:
        require(not source_rows and panel_count == 1, "blank source invented text or fragments")
        require(panel_height == 12 * (dimensions["source_lines"] + 1) + 16, "blank source row geometry changed")
    for (page, y), (next_page, next_y) in zip(source_rows, source_rows[1:]):
        if page == next_page:
            require(y > next_y and (y - next_y) % 12 == 0, "source visual rows do not use their own 12 pt leading")



SHARED_SOURCE = "same = 1\n\n  keep = same"
DISTINCT_SOURCE = "different = 2\n\n    keep = different\n"


def validate_multiple_sources_pdf(pdf: bytes, _dimensions: dict[str, int]) -> None:
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)["Pages"]), pages)
    require(len(pages) == 1, "bounded multiple-source document changed pagination")
    marked = {(page, mcid): text for page in pages for mcid, text in page_marked_text(document, page)}
    codes: list[tuple[int, str]] = []
    logical: list[str] = []

    def walk(number: int) -> None:
        element = document.get(number)
        if element["S"] == "Code":
            require("ActualText" in element, "repeated source Code lost canonical source")
            codes.append((number, text_string(element["ActualText"])))
        for child in element_children(document, element):
            if isinstance(child, Ref):
                walk(int(child))
            elif isinstance(child, dict) and child.get("Type") == "MCR":
                key = (int(child["Pg"]), int(child["MCID"]))
                require(key in marked, "multiple-source MCR owns no text")
                logical.append(marked[key])
    walk(int(document.get(int(document.get(document.root)["StructTreeRoot"]))["K"]))
    require(len({number for number, _ in codes}) == 3, "equal sources shared semantic ownership")
    require([text for _, text in codes] == [SHARED_SOURCE, DISTINCT_SOURCE, SHARED_SOURCE], "source interning merged different canonical contents")
    paint: list[str] = []
    fonts_used: set[str] = set()
    for page in pages:
        value = document.get(page)
        fonts = value.get("Resources", {}).get("Font", {})
        content = document.stream(int(value["Contents"]))
        require(b"/Artifact" not in content, "default multiple-source blocks invented panels")
        for match in MARKED.finditer(content):
            block = match.group(2)
            selected = FONT.findall(block)
            require(len(selected) == 1, "multiple-source run lacks exact font selection")
            name, size = selected[0]
            font = int(fonts[name.decode()])
            font_name = str(document.get(font)["BaseFont"])
            text = decoded_text(block, to_unicode(document, font))
            if "SourceCodePro" in font_name:
                require(size == b"9", "repeated source lost local typography")
            else:
                require(size == b"11" and text == "Between source blocks.", "intervening prose changed")
            fonts_used.add(font_name)
            paint.append(text)
    require(len(fonts_used) == 2, "equal source placements duplicated or substituted fonts")
    require(paint == logical, "multiple-source paint and reading orders differ")
    expected = SHARED_SOURCE.replace("\n", "") + "Between source blocks." + DISTINCT_SOURCE.replace("\n", "") + SHARED_SOURCE.replace("\n", "")
    require("".join(paint) == expected, "later source arena offsets dropped, duplicated, or reordered characters")

def reader_check(snapshot: Path, dimensions: dict[str, int], mutool: Path | None) -> None:
    original = snapshot.read_bytes()
    (validate_multiple_sources_pdf if dimensions["source_scenario"] == 11 else validate_source_blocks_pdf)(original, dimensions)
    with tempfile.TemporaryDirectory(prefix="source-readers-") as name:
        temporary = Path(name)
        classes = temporary / "classes"
        classes.mkdir()
        result = subprocess.run(["javac", "-cp", str(PDFBOX), "-d", str(classes), str(ROOT / "scripts/PdfBoxPages.java")], capture_output=True, timeout=60)
        require(result.returncode == 0, f"PDFBox driver compilation failed: {result.stderr.decode(errors='replace')}")
        output = temporary / "pages"
        result = subprocess.run(["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX}", "PdfBoxPages", str(snapshot), str(output)], capture_output=True, timeout=120)
        require(result.returncode == 0 and not result.stderr.strip(), f"PDFBox source reader failed: {result.stderr.decode(errors='replace')}")
        pages = int(result.stdout)
        extracted = "".join((output / f"page-{page:04d}.txt").read_text() for page in range(1, pages + 1))
        if dimensions["source_scenario"] == 7:
            require(extracted.count("Quiet running header") == pages, "PDFBox lost source-case furniture")
            extracted = extracted.replace("Quiet running header", "")
        # Layout extraction may normalize whitespace; the byte oracle above
        # proves every source scalar and exact logical LF/blank-line content.
        expected = expected_source(dimensions) if dimensions["source_scenario"] in (6, 9, 10, 11, 12) else BODY[0] + expected_source(dimensions) + BODY[1] + BODY[2]
        require("".join(extracted.split()) == "".join(expected.split()), "PDFBox extraction lost, duplicated, or reordered source characters")
        for page in range(1, pages + 1):
            raster = read_ppm(output / f"page-{page:04d}.ppm")
            require((raster.width, raster.height) == (595, 842), "PDFBox page geometry changed")
            require(all(channel == 255 for channel in raster.pixels) if dimensions["source_scenario"] == 9 else any(channel < (250 if dimensions["source_scenario"] == 6 else 200) for channel in raster.pixels), "PDFBox source ink changed")
        if mutool is not None:
            result = subprocess.run([str(mutool), "draw", "-q", "-r", "72", "-c", "rgb", "-o", str(temporary / "mupdf-%d.ppm"), str(snapshot)], capture_output=True, timeout=120)
            require(result.returncode == 0 and not result.stderr.strip(), f"MuPDF source renderer failed: {result.stderr.decode(errors='replace')}")
            for page in range(1, pages + 1):
                raster = read_ppm(temporary / f"mupdf-{page}.ppm")
                require((raster.width, raster.height) == (595, 842), "MuPDF page geometry changed")
                require(all(channel == 255 for channel in raster.pixels) if dimensions["source_scenario"] == 9 else any(channel < (250 if dimensions["source_scenario"] == 6 else 200) for channel in raster.pixels), "MuPDF source ink changed")
        require(snapshot.read_bytes() == original, "reader changed the emitted PDF")



def self_test() -> None:
    cases = [case for case in json.loads((ROOT / "tests/spec.json").read_text())["cases"] if case["source"] == "tests/source_blocks/package.roc" and "source_foregrounds" not in case["validators"]]
    require(len(cases) >= 10, "source acceptance family is incomplete")
    for case in cases:
        validator = validate_multiple_sources_pdf if "source_blocks_multiple" in case["validators"] else validate_source_blocks_pdf
        validator((ROOT / case["snapshot"]).read_bytes(), case["dimensions"])
    try:
        validate_source_blocks_pdf((ROOT / "tests/page_templates/typography_3.pdf").read_bytes(), {"source_scenario": 0, "source_lines": 0})
    except ValidationError:
        pass
    else:
        raise ValidationError("source oracle accepted running furniture as source code")
    sample = next(case for case in cases if case["dimensions"]["source_scenario"] == 0)
    try:
        validate_source_blocks_pdf((ROOT / sample["snapshot"]).read_bytes(), {"source_scenario": 4, "source_lines": 0})
    except ValidationError:
        pass
    else:
        raise ValidationError("source oracle accepted changed canonical source")
    print("PASS source block checker self-test: exact source, measured blank rows, wrapping, panels, empty/default cases, and rejection twins")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--scenario", type=int)
    parser.add_argument("--lines", type=int, default=0)
    parser.add_argument("--readers", action="store_true")
    parser.add_argument("--mutool", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None or args.scenario is None:
        parser.error("PDF and --scenario are required without --self-test")
    dimensions = {"source_scenario": args.scenario, "source_lines": args.lines}
    if args.readers:
        reader_check(args.pdf.resolve(), dimensions, args.mutool)
    else:
        (validate_multiple_sources_pdf if args.scenario == 11 else validate_source_blocks_pdf)(args.pdf.read_bytes(), dimensions)
    print(f"PASS source blocks: {args.pdf}")


if __name__ == "__main__":
    main()
