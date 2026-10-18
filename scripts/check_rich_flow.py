#!/usr/bin/env python3
"""Read rich-flow emitted bytes independently of the Roc layout/report plans."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
from fractions import Fraction as F
import json
import os
import subprocess
from pathlib import Path
import re

from check_pdf_structure import ValidationError, require
from check_rich_inline import text_string, to_unicode
from check_source_blocks import decoded_text, widths, FONT, MARKED, RECT
from check_structure_semantics import Document, Ref, element_children, page_order
from pdf_layout import twin
from text_positions import glyph_positions
from check_visual_renderers import read_ppm

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = re.compile(rb'/Artifact (.*?) BDC\n(.*?)\nEMC', re.S)
ORIGIN = re.compile(rb'1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm')
TOL = F(1, 50)  # At most 0.02 pt for the embedded font's integer W widths.


@dataclass
class Expected:
    role: str
    children: list['Expected'] = field(default_factory=list)
    text: str | None = None
    actual: str | None = None
    alt: str | None = None
    padding: int | None = None
    column_width: int | None = None


def e(role: str, *children: Expected, text: str | None = None, **kwargs) -> Expected:
    return Expected(role, list(children), text, **kwargs)


def paragraph(text: str) -> Expected:
    return e('P', text=text)


def source(text: str, padding: int) -> Expected:
    return e('P', e('Code', text=text.replace('\n', ''), actual=text, padding=padding))


def figure(caption: str, alt: str) -> Expected:
    return e('Sect', e('Figure', text=' ', alt=alt), e('Caption', paragraph(caption)))


def table(caption: str, headers: tuple[str, str], rows: int, prefix: str, detail: str, column_width: int = 60) -> Expected:
    return e('Table', e('Caption', paragraph(caption)),
             e('THead', e('TR', e('TH', text=headers[0]), e('TH', text=headers[1]))),
             e('TBody', *(e('TR', e('TH', text=f'{prefix} {n}'), e('TD', text=detail)) for n in range(1, rows + 1))), column_width=column_width)


def expected_tree(kind: int, count: int) -> Expected:
    if kind == 0:
        items = []
        for n in range(1, count + 1):
            items.append(e('LI', e('Lbl', text=f'{99+n}.'), e('LBody',
                paragraph(f'Instruction {n}: prepare the workflow.'),
                source('  keep = exact_source  \n\n' * 15, 8),
                paragraph('The source and diagram belong to this instruction.'),
                figure('Workflow stage', 'A rectangular workflow stage'),
                table('Instruction parts', ('Part', 'Instruction detail'), 8, 'Part', 'Measured inside this numbered instruction.', 65),
                e('L', e('LI', e('Lbl', text='•'), e('LBody', paragraph('Check the nested result.'), source('nested = preserved', 8)))),
                paragraph('Complete this instruction before the next generated label.'))))
        return e('Document', e('L', *items))
    if kind == 1:
        paragraphs = [e('P', e('Strong', text=f'Note {n}. '), text=f'Note {n}. ' + 'This wrapped paragraph belongs to one logical callout. ' * 6) for n in range(1, count+1)]
        return e('Document', paragraph('Before the callout.'), e('Div', *paragraphs, padding=8), paragraph('After the callout.'))
    if kind == 2:
        groups = []
        for _ in range(count):
            inner = e('Div', paragraph('Inner paragraph before the exact source.'), source('  exact = source  \n\n' * 25, 6),
                figure('Inner diagram', 'A bounded procedure diagram'),
                table('Inner tasks', ('Task', 'Detail'), 25, 'Task', 'This cell remains inside both panels and its numbered instruction.'),
                paragraph('Inner paragraph after the continued table.'), padding=8)
            groups.append(e('Div', e('P', e('Strong', text='Warning. '), e('Link', text='Reference'), text='Warning. Preserve the complete procedure and its examples.Reference'),
                e('L', e('LI', e('Lbl', text='100.'), e('LBody', paragraph('The inner callout belongs to instruction 100.'), inner, paragraph('Finish the instruction without generating another label.'))),
                    e('LI', e('Lbl', text='101.'), e('LBody', paragraph('The next generated label is 101.')))),
                paragraph('Outer paragraph after the complete numbered procedure.'), padding=10))
        return e('Document', *groups)
    if kind == 3:
        text = 'Reusable. Shared authoring must preserve independent semantic occurrences.'
        return e('Document', *(e('Div', e('P', e('Strong', text='Reusable. '), text=text), padding=8) for _ in range(count)))
    if kind == 4:
        return e('Document', e('Div', table('Continued table with a flush panel', ('Row', 'Detail'), 80, 'Row', 'The table frame stays inside the filled panel on every continued page.'), padding=0))
    raise ValidationError('unknown rich-flow scenario')


@dataclass
class Paint:
    page: int
    mcid: int
    text: str
    block: bytes
    bounds: tuple[F, F, F, F]
    glyphs: list[tuple[str, F, F, F, tuple[int, int, int]]]
    order: int = 0


@dataclass
class Node:
    number: int
    value: dict
    children: list['Node']
    marks: list[Paint]
    text: str
    expected: Expected | None = None
    left: F = F(72)
    right: F = F(523)

    @property
    def role(self) -> str:
        return self.value['S']

    def descendants(self):
        yield self
        for child in self.children:
            yield from child.descendants()


@dataclass
class Panel:
    page: int
    rect: tuple[F, F, F, F]
    order: int
    used: bool = False


def color(block: bytes) -> tuple[int, int, int]:
    found = re.findall(rb'([0-9.]+)(?: ([0-9.]+) ([0-9.]+))? scn', block)
    require(len(found) == 1, 'rich-flow paint must select one profile-aware colour')
    components = [F(p.decode()) for p in found[0] if p]
    require(len(components) in (1, 3) and re.search(rb'/CS[0-9_]+ cs', block), 'rich-flow colour bypasses profile selection')
    if len(components) == 1:
        components *= 3
    return tuple(round(p * 255) for p in components)


def paint(document: Document, page: int, index: int, mcid: int, block: bytes) -> Paint:
    fonts = document.get(page)['Resources'].get('Font', {})
    selected = FONT.findall(block)
    origins = ORIGIN.findall(block)
    if selected:
        require(len(selected) == 1 and len(origins) >= 1 and len(set(origins)) == 1, 'rich-flow text lost its exact face/origin')
        name, size_raw = selected[0]
        size = F(size_raw.decode())
        font = int(fonts[name.decode()])
        cache = getattr(document, '_rich_fonts', None)
        if cache is None:
            document._rich_fonts = cache = {}
        if font not in cache:
            cache[font] = (to_unicode(document, font), widths(document, font))
        mapping, font_widths = cache[font]
        text = decoded_text(block, mapping)
        advances = {name: font_widths}
        tx, ty = (F(p.decode()) for p in origins[0])
        positions = glyph_positions(block, advances)
        require(len(positions) == len(text), 'rich-flow glyph/text cardinality differs')
        rgb = color(block[block.rfind(b'q\n'):])
        glyphs = [(c, x / 1000 + tx, y / 1000 + ty, size, rgb) for c, (_, _, x, y) in zip(text, positions)]
        left = min(g[1] for g in glyphs)
        right = max(x / 1000 + tx + advances[font][cid] * size / 1000 for font, cid, x, _ in positions)
        baseline = glyphs[0][2]
        require(all(g[2] == baseline for g in glyphs), 'rich-flow marked text changed baseline within a run')
        leading = 12 if size == 9 else 14
        bounds = (left, baseline - (leading - size), right, baseline + size)
    else:
        # Fixture vectors are authored rectangles; read their path and transform.
        require(len(origins) == 1, 'rich-flow figure lost explicit placement')
        tx, ty = (F(p.decode()) for p in origins[0])
        points = re.findall(rb'(-?[0-9.]+) (-?[0-9.]+) [ml]', block)
        require(points, 'rich-flow figure has no vector path')
        xs = [F(x.decode()) + tx for x, _ in points]
        ys = [F(y.decode()) + ty for _, y in points]
        bounds = (min(xs), min(ys), max(xs), max(ys))
        text, glyphs = '', []
    vector_rects = RECT.findall(block)
    if vector_rects:
        require(len(vector_rects) == 1, 'rich-flow figure invented vector panels')
        x, y, w, h = (F(p.decode()) for p in vector_rects[0])
        tx, ty = (F(p.decode()) for p in origins[0])
        bounds = (x + tx, y + ty, x + tx + w, y + ty + h)
    require(not re.search(rb'(?:^|\n)(?:W|W\*|[4-7] Tr)(?:\n|$)', block), 'rich-flow paint was clipped')
    return Paint(index, mcid, text, block, bounds, glyphs)


def read(pdf: bytes):
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)['Pages']), pages)
    marks: dict[tuple[int, int], Paint] = {}
    physical: list[tuple[int, int]] = []
    artifacts: list[tuple[int, bytes, bytes, int]] = []
    for index, page in enumerate(pages):
        content = document.stream(int(document.get(page)['Contents']))
        for match in MARKED.finditer(content):
            key = (page, int(match[1]))
            require(key not in marks, 'duplicate rich-flow MCID')
            marks[key] = paint(document, page, index, key[1], match[2])
            marks[key].order = match.start()
            physical.append(key)
        for match in ARTIFACT.finditer(content):
            require(b'/MCID' not in match[0], 'rich-flow artifact acquired semantic ownership')
            artifacts.append((index, match[1], match[2], match.start()))
    logical: list[tuple[int, int]] = []
    seen: set[int] = set()
    def node(number: int) -> Node:
        require(number not in seen, 'shared authoring aliased semantic occurrences')
        seen.add(number)
        value = document.get(number)
        children, owned, text = [], [], []
        for child in element_children(document, value):
            if isinstance(child, Ref):
                nested = node(int(child))
                children.append(nested)
                owned.extend(nested.marks)
                text.append(nested.text)
            elif isinstance(child, dict) and child.get('Type') == 'MCR':
                key = (int(child['Pg']), int(child['MCID']))
                require(key in marks, 'rich-flow semantic owner refers to missing paint')
                logical.append(key)
                owned.append(marks[key])
                text.append(marks[key].text)
        return Node(number, value, children, owned, ''.join(text))
    root = node(int(document.get(int(document.get(document.root)['StructTreeRoot']))['K']))
    require(logical == physical, 'rich-flow paint differs from semantic reading order or appears more than once')
    return document, pages, root, artifacts


def match_tree(node: Node, expected: Expected) -> None:
    require(node.role == expected.role, f'rich-flow semantic role {node.role} replaced {expected.role}')
    require(len(node.children) == len(expected.children), f'rich-flow {node.role} child count/ownership changed')
    node.expected = expected
    if expected.text is not None:
        require(node.text == expected.text, f'rich-flow {node.role} text changed, repeated or reordered: {node.text[:70]!r}')
    if expected.actual is not None:
        require(text_string(node.value.get('ActualText', b'')) == expected.actual, 'rich-flow Code canonical LF, blank/final lines or trailing spaces changed')
    if expected.alt is not None:
        require(text_string(node.value.get('Alt', b'')) == expected.alt, 'rich-flow figure alternative changed')
    for child, contract in zip(node.children, expected.children):
        match_tree(child, contract)


def frames(node: Node, left: F = F(72), right: F = F(523)) -> None:
    node.left, node.right = left, right
    child_left, child_right = left, right
    if node.expected.padding is not None:
        child_left += node.expected.padding
        child_right -= node.expected.padding
    if node.role == 'Table':
        frames(node.children[0], left, right)
        for section in node.children[1:]:
            section.left, section.right = left, right
            for row in section.children:
                row.left, row.right = left, right
                frames(row.children[0], left + 4, left + node.expected.column_width - 4)
                frames(row.children[1], left + node.expected.column_width + 4, right - 4)
        return
    if node.role == 'L':
        columns = []
        for item in node.children:
            label = item.children[0]
            require(label.marks, 'rich-flow list label disappeared')
            extent = max(mark.bounds[2] for mark in label.marks) - left
            columns.append(F(18) if extent <= 18 else extent + F(11, 2))
        column = max(columns)
        for item in node.children:
            item.left, item.right = left, right
            frames(item.children[0], left, left + column)
            lead = item.children[1].children[0]
            actual_left = min(mark.bounds[0] for mark in lead.marks)
            require(abs(actual_left - left - column) <= TOL, 'rich-flow wide generated label lost its shared hanging column')
            frames(item.children[1], actual_left, right)
        return
    for child in node.children:
        frames(child, child_left, child_right)
    if not node.children:
        for mark in node.marks:
            require(mark.bounds[0] >= child_left - TOL and mark.bounds[2] <= child_right + TOL, f'rich-flow {node.role} escapes its parent width')
            require(mark.bounds[1] >= 72 and mark.bounds[3] <= 770, 'rich-flow paint escapes the page body')


def panels_from_artifacts(artifacts) -> list[Panel]:
    rectangles = []
    panels = []
    for page, kind, block, order in artifacts:
        if b'/Layout' not in kind or b' Tf' in block:
            continue
        found = RECT.findall(block)
        require(len(found) <= 1, 'rich-flow rectangle artifact contains ambiguous panels')
        if not found:
            continue
        rect = tuple(F(part.decode()) for part in found[0])
        rectangles.append((page, rect, color(block), order))
        if color(block) == (238, 240, 242):
            panels.append(Panel(page, rect, order))
    index = 0
    while index + 3 < len(rectangles):
        page, (x, y, width, height), rgb, order = rectangles[index]
        other = rectangles[index + 1:index + 4]
        if height == 1 and width > 1 and all(item[0] == page and item[2] == (0, 0, 0) for item in other) and rgb == (0, 0, 0):
            upper, left, right = (item[1] for item in other)
            full_height = upper[1] + 1 - y
            if upper == (x, y + full_height - 1, width, F(1)) and left == (x, y, F(1), full_height) and right == (x + width - 1, y, F(1), full_height):
                panels.append(Panel(page, (x, y, width, full_height), max([order] + [item[3] for item in other])))
                index += 4
                continue
        index += 1
    return panels


def check_panels(root: Node, artifacts, count: int) -> None:
    panels = panels_from_artifacts(artifacts)
    callouts = [node for node in root.descendants() if node.role == 'Div']
    require(len(callouts) == count, 'rich-flow authored callout count changed')
    outer_padding: dict[int, int] = {}
    def visit(node: Node, padding: int = 0) -> None:
        outer_padding[node.number] = padding
        for child in node.children:
            visit(child, padding + (node.expected.padding if node.role == 'Div' else 0))
    visit(root)
    for node in callouts:
        padding = node.expected.padding
        pages = sorted({mark.page for mark in node.marks})
        require(pages and pages == list(range(pages[0], pages[-1] + 1)), 'rich-flow callout skipped a continuation page')
        for page in pages:
            marks = [mark for mark in node.marks if mark.page == page]
            lo = min(mark.bounds[1] for mark in marks)
            hi = max(mark.bounds[3] for mark in marks)
            matches = [panel for panel in panels if not panel.used and panel.page == page and abs(panel.rect[0] - node.left) <= TOL and abs(panel.rect[2] - (node.right - node.left)) <= TOL and panel.rect[1] + padding <= lo and panel.rect[1] + panel.rect[3] - padding >= hi]
            require(len(matches) == 1, 'rich-flow fragment lost its unique contained padded panel')
            panel = matches[0]
            panel.used = True
            require(panel.order < min(mark.order for mark in marks), 'rich-flow panel paints over its child content')
            x, y, width, height = panel.rect
            require(y >= 72 and y + height <= 770, 'rich-flow panel escapes the body frame')
            if page == pages[0]:
                require(y + height == hi + padding + (2 if node.children[0].role == 'Table' else 0), 'rich-flow opening padding was omitted or applied twice')
            else:
                # A fresh continuation starts at body top, less the reopened outer padding.
                ancestor_padding = outer_padding[node.number]
                require(y + height == 770 - ancestor_padding, 'rich-flow continuation padding/header order changed')
            if page == pages[-1]:
                require(y == lo - padding - (2 if node.children[-1].role == 'Table' else 0), 'rich-flow closing padding was omitted or applied twice')
            for mark in marks:
                require(mark.bounds[0] >= x + padding - TOL and mark.bounds[2] <= x + width - padding + TOL, 'rich-flow child escapes its padded panel width')
            # Every decoration within this panel must respect its actual padded frame.
            for artifact_page, kind, block, _ in artifacts:
                if artifact_page != page or b'/Layout' not in kind:
                    continue
                for raw in RECT.findall(block):
                    rx, ry, rw, rh = (F(part.decode()) for part in raw)
                    if (rh < 1 or rw < 1 or color(block) in {(219, 228, 233), (227, 233, 238)}) and y <= ry <= y + height:
                        require(rx >= x + padding - TOL and rx + rw <= x + width - padding + TOL and ry >= y + padding and ry + rh <= y + height - padding, 'rich-flow table decoration escaped callout padding')
    require(all(panel.used for panel in panels), 'rich-flow emitted an empty or duplicate callout panel')


def check_sources(root: Node, kind: int) -> None:
    for node in root.descendants():
        if node.role != 'Code':
            continue
        glyphs = [glyph for mark in node.marks for glyph in mark.glyphs]
        expected = [(character, (0, 0, 0)) for character in node.expected.actual.replace('\n', '')]
        if kind == 0 and node.expected.actual.startswith('  keep'):
            expected[2:6] = [(c, (128, 0, 192)) for c, _ in expected[2:6]]
        require([(g[0], g[4]) for g in glyphs] == expected, 'rich-flow original-source foregrounds or characters changed')
        require(all(g[3] == 9 for g in glyphs), 'rich-flow source local typography changed')
        rows = sorted({(mark.page, mark.glyphs[0][2]) for mark in node.marks})
        for (page, baseline), (next_page, next_baseline) in zip(rows, rows[1:]):
            if page == next_page:
                require(abs(next_baseline - baseline) == 24, 'rich-flow source blank-line leading changed')


def check_headers(document: Document, pages: list[int], root: Node, artifacts) -> None:
    wanted = Counter()
    for node in root.descendants():
        if node.role != 'Table':
            continue
        body_pages = sorted({mark.page for mark in node.children[-1].marks})
        headers = tuple(child.text for child in node.children[1].children[0].children)
        for page in body_pages[1:]:
            wanted[(page, headers, node.left)] += 1
    observed = Counter()
    grouped: dict[int, list[Paint]] = {}
    for page, kind, block, _ in artifacts:
        if b' Tf' not in block:
            continue
        require(kind == b'<</Type /Pagination>>', 'rich-flow repeated table header lost its pagination artifact role')
        grouped.setdefault(page, []).append(paint(document, pages[page], page, -1, block))
    for page, marks in grouped.items():
        require(len(marks) % 2 == 0, 'rich-flow repeat lost one table header cell')
        for first, second in zip(marks[::2], marks[1::2]):
            require(first.bounds[1] == second.bounds[1], 'rich-flow repeated header cells lost their row baseline')
            observed[(page, (first.text, second.text), first.bounds[0] - 4)] += 1
    # List columns carry sub-millipoint shaping; compare their emitted decimal origins.
    require(len(wanted) == len(observed), 'rich-flow missing or duplicated table repeat pages')
    for (page, texts, left), count in wanted.items():
        require(sum(n for (p, t, x), n in observed.items() if p == page and t == texts and abs(x - left) <= TOL) == count, 'rich-flow repeated header text, origin or count changed')


def validate_rich_flow_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    kind, count = dimensions['rich_kind'], dimensions['rich_count']
    document, pages, root, artifacts = read(pdf)
    require(len(pages) == dimensions['pages'], 'rich-flow pagination changed')
    match_tree(root, expected_tree(kind, count))
    frames(root)
    check_sources(root, kind)
    check_headers(document, pages, root, artifacts)
    callouts = count if kind in (2, 3) else 1 if kind in (1, 4) else 0
    check_panels(root, artifacts, callouts * (2 if kind == 2 else 1))


def self_test() -> None:
    cases = [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'rich_flow' in case['validators']]
    require(len(cases) >= 11, 'rich-flow scale/shared/zero-padding coverage incomplete')
    for case in cases:
        validate_rich_flow_pdf((ROOT / case['snapshot']).read_bytes(), case['dimensions'])
    mutations = [
        (next(c for c in cases if c['dimensions']['rich_kind'] == 0), b'/S /LBody', b'/S /Div'),
        (next(c for c in cases if c['dimensions']['rich_kind'] == 1), b'/S /Div', b'/S /Sect'),
        (next(c for c in cases if c['dimensions']['rich_kind'] == 1), b'451 1 re\nf', b'452 1 re\nf'),
        (next(c for c in cases if c['dimensions']['rich_kind'] == 0), b'0.501960784 0 0.752941176 scn', b'0 0 0 scn'),
        (next(c for c in cases if c['dimensions']['rich_kind'] == 0), b'00200020000A000A', b'002000200020000A'),
        (next(c for c in cases if c['dimensions']['rich_kind'] == 2), b'/Artifact <</Type /Pagination>>', b'/Artifact <</Type /Layout>>'),
    ]
    for case, old, new in mutations:
        original = (ROOT / case['snapshot']).read_bytes()
        mutant = twin(original, old, new)
        try:
            validate_rich_flow_pdf(mutant, case['dimensions'])
        except ValidationError:
            pass
        else:
            raise ValidationError(f'rich-flow oracle accepted mutation {old!r}')
    print('PASS rich-flow exact semantic owners/text, shared occurrences, source foregrounds, frame/panel padding, table headers and mutation twins')



def reader_check(mutool: Path | None) -> None:
    cases = [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'rich_flow' in case['validators']]
    samples = [next(case for case in cases if case['dimensions']['rich_kind'] == kind) for kind in range(5)]
    output = ROOT / '.roc-pdf-tmp/rich-flow-readers'
    classes = output / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    jar = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'
    def run(command: list[str]) -> bytes:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        require(result.returncode == 0 and not result.stderr.strip(), f'rich-flow reader failed: {result.stderr.decode(errors="replace")}')
        return result.stdout
    run(['javac', '-cp', str(jar), '-d', str(classes), str(ROOT / 'scripts/PdfBoxPages.java')])
    total = 0
    for case in samples:
        path = ROOT / case['snapshot']
        pdf = path.read_bytes()
        validate_rich_flow_pdf(pdf, case['dimensions'])
        document, pages, _, _ = read(pdf)
        expected = []
        for page_index, page in enumerate(pages):
            stream = document.stream(int(document.get(page)['Contents']))
            pieces = [(match.start(), match[2]) for match in MARKED.finditer(stream)]
            pieces += [(match.start(), match[2]) for match in ARTIFACT.finditer(stream) if b' Tf' in match[2]]
            expected.append(''.join(paint(document, page, page_index, -1, block).text for _, block in sorted(pieces)))
        box = output / path.stem / 'pdfbox'
        count = int(run(['java', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{jar}', 'PdfBoxPages', str(path), str(box)]))
        require(count == len(pages), 'PDFBox rich-flow page count changed')
        extracted = ''.join((box / f'page-{page:04d}.txt').read_text() for page in range(1, count+1))
        require(''.join(extracted.split()) == ''.join(''.join(expected).split()), 'PDFBox rich-flow whole-file extraction changed text/order')
        engines = [('PDFBox 3.0.8', [box / f'page-{page:04d}.ppm' for page in range(1, count+1)])]
        if mutool is not None:
            mupdf = output / path.stem / 'mupdf'
            mupdf.mkdir(exist_ok=True)
            run([str(mutool), 'draw', '-q', '-r', '72', '-c', 'rgb', '-o', str(mupdf / 'page-%d.ppm'), str(path)])
            extracted = run([str(mutool), 'draw', '-q', '-F', 'txt', '-O', 'ignore-actualtext', '-o', '-', str(path)]).decode()
            require(''.join(extracted.split()) == ''.join(''.join(expected).split()), 'MuPDF rich-flow glyph/ToUnicode extraction changed text/order')
            engines.append(('MuPDF 1.28.2', [mupdf / f'page-{page}.ppm' for page in range(1, count+1)]))
        for engine, paths in engines:
            purple = False
            for image in paths:
                raster = read_ppm(image)
                require((raster.width, raster.height) == (595, 842) and min(raster.pixels) < 100, f'{engine} lost rich-flow geometry/ink')
                for offset in range(0, len(raster.pixels), 3):
                    red, green, blue = raster.pixels[offset:offset+3]
                    if red > green + 60 and blue > green + 80:
                        purple = True
                total += 1
            if case['dimensions']['rich_kind'] == 0:
                require(purple, f'{engine} lost the rich-list source foreground')
    print(f'PASS rich-flow whole-file PDFBox and optional MuPDF extraction/rendering: {total} page renders')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--readers', action='store_true')
    parser.add_argument('--mutool', type=Path)
    args = parser.parse_args()
    require(args.self_test or args.readers, 'use --self-test or --readers; dimensions come from tests/spec.json')
    if args.self_test:
        self_test()
    if args.readers:
        reader_check(args.mutool)


if __name__ == '__main__':
    try:
        main()
    except (ValidationError, ValueError) as error:
        raise SystemExit(f'FAIL {error}') from error
