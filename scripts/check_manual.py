#!/usr/bin/env python3
"""Check admitted source text, local links, Markdown and independent PDF text."""
from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit

from check_structure_semantics import Document
from check_vector_diagrams import read_png

ROOT = Path(__file__).resolve().parents[1]


class Page(HTMLParser):
    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.images = []
        self.code = []
        self.pre = False
        self.tables = []
        self.in_table = False
        self.in_cell = False
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if tag == "img":
            assert attrs.get("alt"), "image lacks descriptive alternative text"
            self.images.append(attrs["src"])
        if tag == "pre":
            self.pre = True
            self.code.append("")
        if tag == "table":
            self.in_table = True
            self.tables.append([])
        if tag == "tr" and self.in_table:
            self.tables[-1].append([])
        if tag in ("th", "td") and self.in_table:
            self.in_cell = True
            self.tables[-1][-1].append("")

    def handle_endtag(self, tag):
        if tag == "pre":
            self.pre = False
        if tag in ("td", "th"):
            self.in_cell = False
        if tag == "table":
            self.in_table = False

    def handle_data(self, data):
        if self.pre:
            self.code[-1] += data
        if self.in_cell:
            self.tables[-1][-1][-1] += data


def source_blocks(source: str) -> list[str]:
    return re.findall(r"^```[^\n]*\n(.*?)^```\s*$", source, re.M | re.S)


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def check(site: Path, source: Path, pdf: Path | None, review: Path | None = None) -> None:
    inventory = json.loads((source / "source-digests.json").read_text())
    for entry in inventory["sources"]:
        assert hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest() == entry["sha256"], entry["path"]
    pages = {path.name: Page(path.read_text()) for path in site.glob("*.html")}
    assert "index.html" in pages and (site / "llms.txt").is_file()
    all_code = []
    table_cells = []
    table_count = 0
    expected_table_shapes = []
    for path, prepared in inventory["chapters"].items():
        page = pages[prepared.removesuffix(".adoc") + ".html"]
        authored = (ROOT / path).read_text()
        for placeholder, value in inventory.get("release_bindings", {}).get(path, {}).items():
            authored = authored.replace(placeholder, value)
        expected = source_blocks(authored)
        assert [code.rstrip("\n") for code in page.code] == [code.rstrip("\n") for code in expected], f"source whitespace changed in {path}"
        all_code.extend(expected)
        grids = []
        rows = []
        for line in authored.splitlines():
            if line.startswith("|"):
                if re.fullmatch(r"\|[ |:-]+\|", line):
                    table_count += 1
                else:
                    row = []
                    for cell in line.strip("|").split("|"):
                        plain = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cell).replace("`", "")
                        table_cells.append(plain)
                        row.append(compact(plain))
                    rows.append(row)
            elif rows:
                grids.append(rows)
                rows = []
        if rows:
            grids.append(rows)
        actual_grids = [[[compact(cell) for cell in row] for row in table] for table in page.tables]
        assert actual_grids == grids, f"HTML table row/cell associations changed in {path}"
        expected_table_shapes.extend(tuple(len(row) for row in grid) for grid in grids)
    for name, page in pages.items():
        assert (site / name.replace(".html", ".md")).is_file(), f"missing Markdown: {name}"
        text = (site / name).read_text()
        assert 'type="text/markdown"' in text and 'href="llms.txt"' in text
        for href in page.links + page.images:
            target = urlsplit(href)
            if target.scheme or target.netloc:
                continue
            path = (site / unquote(target.path)).resolve() if target.path else (site / name).resolve()
            assert path.is_relative_to(site.resolve()), f"link escapes manual: {href}"
            assert path.exists(), f"missing link target in {name}: {href}"
            if target.fragment and path.suffix == ".html":
                assert unquote(target.fragment) in pages[path.name].ids, f"missing anchor in {name}: {href}"
    if pdf:
        jar = ROOT / "vendor/pdfbox/pdfbox-app-3.0.8.jar"
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(["javac", "-cp", str(jar), "-d", directory,
                            str(ROOT / "scripts/ManualTextExtract.java")], check=True)
            command = ["java", "-Djava.awt.headless=true", "-cp", f"{directory}{os.pathsep}{jar}", "ManualTextExtract", str(pdf)]
            if review:
                review.mkdir(parents=True, exist_ok=True)
                for previous in review.glob("pdf-page-*.png"):
                    previous.unlink()
                command.append(str(review))
            extracted = subprocess.check_output(command, text=True)
        # Remove only known running furniture at the edges of each page;
        # leave identical authored body occurrences intact.
        titles = {(ROOT / path).read_text().splitlines()[0][2:] for path in inventory["chapters"]}
        titles.update({"roc-pdf user manual", "Release notes", "Runnable document gallery"})
        body = []
        for page in extracted.split("\f"):
            lines = page.splitlines()
            nonempty = [index for index, line in enumerate(lines) if line.strip()]
            removed = set()
            for index in nonempty[:3]:
                if (lines[index].strip() in titles or lines[index].startswith("roc-pdf user manual ")
                        or lines[index].strip() == "Authoring surface Support"):
                    removed.add(index)
            for index in nonempty[-3:]:
                if re.fullmatch(r"\s*\d+\s*/\s*\d+\s*", lines[index]):
                    removed.add(index)
            body.extend(line for index, line in enumerate(lines) if index not in removed)
        actual = compact("\n".join(body))
        raw_actual = compact(extracted)
        for code in all_code:
            assert compact(code) in actual, f"independent PDF reader lost source text: {code[:100]!r}"
        for text in ("Runnable document gallery", "Invoice", "Business report", "Supported features"):
            assert compact(text) in actual, f"PDF lost {text}"
        # The manual embeds the three original RGB previews, with no lossy
        # preparation or omitted figures. Check exact decoded pixel content.
        document = Document(pdf.read_bytes())
        images = []
        tables = []
        for number in document.bodies:
            value = document.get(number)
            if isinstance(value, dict) and value.get("Subtype") == "Image":
                images.append((value["Width"], value["Height"], hashlib.sha256(document.stream(number)).hexdigest()))
            if isinstance(value, dict) and value.get("S") == "Table":
                tables.append(number)
        expected_images = []
        for name in ("tax-invoice", "business-report", "vector-diagrams"):
            image = read_png(ROOT / f"examples/{name}/preview.png")
            expected_images.append((image.width, image.height, hashlib.sha256(image.pixels).hexdigest()))
        assert sorted(images) == sorted(expected_images), "PDF figure pixels differ from prepared source previews"
        assert len(tables) == table_count, "manual tables lost semantic ownership"
        actual_table_shapes = []
        for table in tables:
            rows = []
            pending = [table]
            while pending:
                node = document.get(pending.pop())
                if node.get("S") == "TR":
                    cells = node.get("K", [])
                    assert all(document.get(cell).get("S") in ("TH", "TD") for cell in cells)
                    rows.append(len(cells))
                else:
                    pending.extend(reversed(node.get("K", [])))
            actual_table_shapes.append(tuple(rows))
        assert sorted(actual_table_shapes) == sorted(expected_table_shapes), "PDF table rows/cells differ from the authored grids"
        for cell in table_cells:
            # Initial headers can also sit at the page edge; their source
            # text must remain in raw extraction even when repeated headers
            # are removed to join a continued body cell.
            assert compact(cell) in actual or compact(cell) in raw_actual, f"PDF lost table cell: {cell}"
        if review:
            review.mkdir(parents=True, exist_ok=True)
            java = subprocess.run(["java", "-version"], text=True, capture_output=True, check=True)
            (review / "pdf-report.json").write_text(json.dumps({
                "pdf_sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
                "pages": sum(isinstance(document.get(n), dict) and document.get(n).get("Type") == "Page" for n in document.bodies),
                "exact_source_blocks": len(all_code), "exact_rgb_figures": len(images),
                "tagged_tables": len(tables), "pdfbox": "3.0.8", "java": java.stderr.strip(),
                "rendered_review_pages": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                                          for path in sorted(review.glob("pdf-page-*.png"))},
            }, indent=2) + "\n")
    print(f"PASS manual: {len(pages)} pages, {len(all_code)} exact source blocks, links, Markdown, asset digests" + ("; PDFBox source/table text, tagged table and three exact RGB figures" if pdf else ""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--review", type=Path, help="Retain independent PDFBox contents/figure preview images")
    args = parser.parse_args()
    check(args.site, args.source, args.pdf, args.review)


if __name__ == "__main__":
    main()
