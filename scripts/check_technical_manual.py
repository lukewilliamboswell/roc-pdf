#!/usr/bin/env python3
"""Combined manual oracle from emitted structure, glyphs and drawing artifacts.

No preparation report, reference resolver state or pager frame fact is read.
Expected pages come from each authored heading's actual marked content; the
publicly declared templates and widths are this oracle's independent contract.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from fractions import Fraction as F
import json
import os
import subprocess
from pathlib import Path
import re

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text, text_string, to_unicode
from check_rich_flow import (Expected, Node, Paint, TOL, e, paragraph, source, frames,
                             match_tree, paint, color, panels_from_artifacts, FONT, RECT)
from check_structure_semantics import Document, Ref, element_children, page_order
from check_navigation import check_name_tree, walk_name_tree
from check_source_blocks import decoded_text
from check_visual_renderers import read_ppm
from pdf_layout import twin

ROOT = Path(__file__).resolve().parents[1]
LABELS = ('Café', 'Receive order', 'Check stock', 'Order timber', 'Dispatch')
ALT = 'Café: receive an order, check stock or order timber, then dispatch.'
NUMBER = rb'-?[0-9]+(?:\.[0-9]+)?'
EVENT = re.compile(rb'/([A-Za-z0-9]+) (<<[^\n]*?>>) BDC\n|EMC\n')
MATRIX = re.compile(rb'(' + NUMBER + rb') 0 0 (' + NUMBER + rb') (' + NUMBER + rb') (' + NUMBER + rb') cm')


@dataclass
class Sequence:
    role: bytes
    props: bytes
    start: int
    body_start: int
    body_end: int = 0
    end: int = 0
    children: list['Sequence'] = field(default_factory=list)

    def clean(self, content: bytes) -> bytes:
        chunks, cursor = [], self.body_start
        for child in self.children:
            require(child.role == b'Artifact', 'manual nests semantic marked content')
            chunks.append(content[cursor:child.start])
            cursor = child.end
        chunks.append(content[cursor:self.body_end])
        return b''.join(chunks)


def sequences(content: bytes) -> list[Sequence]:
    stack, found = [], []
    for event in EVENT.finditer(content):
        if event[1] is not None:
            sequence = Sequence(event[1], event[2], event.start(), event.end())
            if stack:
                stack[-1].children.append(sequence)
            stack.append(sequence)
            found.append(sequence)
        else:
            require(stack, 'manual unbalanced EMC')
            sequence = stack.pop()
            sequence.body_end, sequence.end = event.start(), event.end()
    require(not stack, 'manual unterminated marked content')
    return found


def read_manual(pdf: bytes):
    document = Document(pdf)
    pages: list[int] = []
    page_order(document, int(document.get(document.root)['Pages']), pages)
    marks, physical, artifacts = {}, [], []
    for index, page in enumerate(pages):
        stream = document.stream(int(document.get(page)['Contents']))
        shown = dict(page_marked_text(document, page))
        for sequence in sequences(stream):
            block = sequence.clean(stream)
            if sequence.role == b'Artifact':
                require(b'/MCID' not in sequence.props, 'manual artifact owns an MCID')
                artifacts.append((index, sequence.props, block, sequence.start))
                continue
            identity = re.fullmatch(rb'<</MCID ([0-9]+)>>', sequence.props)
            require(identity is not None, 'manual marked content lacks its explicit MCID')
            key = (page, int(identity[1]))
            require(key not in marks and key[1] in shown, 'manual marked content identity is missing or repeated')
            if MATRIX.search(block) and RECT.search(block):
                rectangle = RECT.search(block)
                matrix = MATRIX.search(block)
                require(rectangle is not None and matrix is not None, 'manual vector lost its declared backdrop/placement')
                x, y, width, height = (F(part.decode()) for part in rectangle.groups())
                a, d, tx, ty = (F(part.decode()) for part in matrix.groups())
                require(a > 0 and a == d, 'manual vector was not scaled uniformly')
                mark = Paint(index, key[1], shown[key[1]], block, (x*a+tx, y*d+ty, (x+width)*a+tx, (y+height)*d+ty), [], sequence.start)
                require(b' c\n' in block and b' l\n' in block, 'manual vector connectors/arrowheads disappeared')
            else:
                mark = paint(document, page, index, key[1], block)
                require(mark.text == shown[key[1]], 'manual independent glyph decoding disagrees')
                mark.order = sequence.start
                # Body, source and heading styles all have 3 pt of descent in
                # their authored line box, including the 15/18 pt heading.
                mark.bounds = (mark.bounds[0], mark.glyphs[0][2] - 3, mark.bounds[2], mark.bounds[3])
            marks[key] = mark
            physical.append(key)
        require(not document.get(page).get('Resources', {}).get('XObject'), 'manual vector acquired a raster/form fallback')
    visited, logical = set(), []
    def node(number: int) -> Node:
        require(number not in visited, 'manual aliases semantic occurrences')
        visited.add(number)
        value, children, owned, text = document.get(number), [], [], []
        for child in element_children(document, value):
            if isinstance(child, Ref):
                nested = node(int(child))
                children.append(nested); owned.extend(nested.marks); text.append(nested.text)
            elif isinstance(child, dict) and child.get('Type') == 'MCR':
                key = (int(child['Pg']), int(child['MCID']))
                require(key in marks, 'manual MCR has no paint')
                logical.append(key); owned.append(marks[key]); text.append(marks[key].text)
        return Node(number, value, children, owned, ''.join(text))
    root = node(int(document.get(int(document.get(document.root)['StructTreeRoot']))['K']))
    require(logical == physical, 'manual semantic and physical reading order disagree')
    return document, pages, root, artifacts


def contract(chapters: int, starts: dict[int, int]) -> Expected:
    final = starts[chapters]
    contents = [e('H1', text='Technical manual contents')]
    for number in range(1, chapters + 1):
        page = starts[number]
        contents.append(e('P', e('Link', text=f'Procedure {number}'), text=f'Procedure {number} — label M-{page}; physical {page}'))
    for number in range(1, chapters + 1):
        table = e('Table', e('Caption', paragraph(f'Procedure {number} checklist')),
            e('THead', e('TR', e('TH', text='Step'), e('TH', text='Contents label M-1'))),
            e('TBody', *(e('TR', e('TH', text=f'Step {row}'), e('TD', text='Retain the procedure, its boxed instructions and the measured table columns.')) for row in range(1, 41))), column_width=66)
        inner = e('Div', paragraph('The continued table remains inside the instruction and both callout panels.'), table,
            paragraph('The inner callout closes after the complete checklist.'), padding=6)
        item = e('LI', e('Lbl', text='100.'), e('LBody',
            paragraph(f'Prepare procedure {number} without losing source whitespace.'),
            source(f'  verify = procedure_{number}  \n\n' * 16, 6),
            e('Sect', e('Figure', text=' ', alt=ALT), e('Caption', paragraph(f'Prepared procedure diagram {number}'))),
            inner, paragraph(f'Complete procedure {number} before the next chapter begins.')))
        contents.extend([e('H1', text=f'Procedure {number}'),
            paragraph(f'Contents physical 1; final procedure label M-{final}; final physical {final}.'),
            e('Div', paragraph('One logical procedure keeps its numbered instruction and rich children together in reading order.'),
              e('L', item), paragraph('The outer callout closes after its one logical instruction.'), padding=8)])
    return e('Document', *contents)


def heading_pages(root: Node, chapters: int) -> tuple[dict[int, int], dict[int, Node]]:
    headings = {node.text: node for node in root.descendants() if node.role == 'H1'}
    require(set(headings) == {'Technical manual contents', *(f'Procedure {n}' for n in range(1, chapters + 1))}, 'manual heading set changed')
    starts, nodes = {}, {}
    for number in range(1, chapters + 1):
        node = headings[f'Procedure {number}']
        pages = {mark.page for mark in node.marks}
        require(len(pages) == 1, 'manual chapter heading was split')
        starts[number] = next(iter(pages)) + 1
        nodes[number] = node
    require(starts[1] == 2 and list(starts.values()) == sorted(set(starts.values())), 'manual full-page chapter boundaries changed')
    return starts, nodes


def destinations(document: Document, pages: list[int], root: Node, nodes: dict[int, Node]) -> None:
    headings = {b'contents': root.children[0], **{f'chapter-{n}'.encode(): node for n, node in nodes.items()}}
    named = check_name_tree(document.bodies, document.root, pages)
    require(set(named) == set(headings), 'manual named destinations changed')
    catalog = document.get(document.root)
    raw = dict(walk_name_tree(document.bodies, int(catalog['Names']['Dests'])))
    for name, node in headings.items():
        page, x, y = named[name]
        require(page == pages[node.marks[0].page] and F(x.decode()) == 72 and F(y.decode()) == max(mark.bounds[3] for mark in node.marks), 'printed manual reference target differs from its actual heading placement')
        target = re.search(rb'/SD \[([0-9]+) 0 R', raw[name])
        require(target is not None and int(target[1]) == node.number, 'manual structured destination targets the wrong semantic owner')
    # GoTo actions and named destinations must share both physical and
    # structured targets, even when an annotation occurs before the name tree.
    targets = {(pages[node.marks[0].page], F(72), max(mark.bounds[3] for mark in node.marks)): node.number for node in headings.values()}
    direct = re.compile(rb'/D \[([0-9]+) 0 R /XYZ (' + NUMBER + rb') (' + NUMBER + rb') null\](?: /S /GoTo)? /SD \[([0-9]+) 0 R /XYZ (' + NUMBER + rb') (' + NUMBER + rb') null\]')
    count = 0
    for body in document.bodies.values():
        for target in direct.finditer(body):
            page, x, y, owner, sx, sy = target.groups()
            key = (int(page), F(x.decode()), F(y.decode()))
            require(key in targets and targets[key] == int(owner) and x == sx and y == sy, 'manual GoTo physical and structured destination disagree')
            count += 1
    require(count == 2 * len(nodes) + 1, 'manual link/name-tree destination occurrence set changed')
    outline_root = int(catalog['Outlines'])
    outline = document.get(outline_root)
    require(outline['Count'] == len(nodes) + 1, 'manual outline count changed')
    cursor = int(outline['First']); observed = []; seen = set()
    while cursor:
        require(cursor not in seen, 'manual outline cycle')
        seen.add(cursor); entry = document.get(cursor)
        require(int(entry['Parent']) == outline_root and 'First' not in entry, 'manual outline hierarchy changed')
        observed.append((text_string(entry['Title']), text_string(entry['Dest'])))
        cursor = int(entry.get('Next', 0))
    require(observed == [('Contents', 'contents')] + [(f'Procedure {n}', f'chapter-{n}') for n in nodes], 'manual outline titles/targets changed')
    labels = document.get(int(catalog['PageLabels']))['Nums']
    require(len(labels) == 2 and labels[0] == 0 and labels[1].get('S') == 'D' and labels[1].get('St', 1) == 1 and text_string(labels[1]['P']) == 'M-', 'manual configured page labels changed')


def chapter_for(page: int, starts: dict[int, int]) -> int:
    return max((number for number, start in starts.items() if start <= page + 1), default=0)


def furniture(document: Document, pages: list[int], artifacts, starts: dict[int, int]):
    footer, header, repeat, labels = defaultdict(list), defaultdict(list), defaultdict(list), Counter()
    for page, kind, block, order in artifacts:
        if not FONT.search(block):
            continue
        mark = paint(document, pages[page], page, -1, block)
        if b'/Subtype /Footer' in kind or b'/Subtype /PageNum' in kind:
            footer[page].append(mark.text)
        elif b'/Subtype /Header' in kind:
            header[page].append(mark.text)
        elif kind == b'<</Type /Pagination>>':
            repeat[page].append(mark)
        else:
            require(kind == b'<</Type /Layout>>' and mark.text in LABELS, 'manual unexpected text artifact')
            labels[mark.text] += 1
    require(labels == Counter({label: len(starts) for label in LABELS}), 'manual prepared vector labels changed or leaked ownership')
    bounds = {}
    for page in range(len(pages)):
        chapter = chapter_for(page, starts)
        opening = chapter > 0 and page + 1 == starts[chapter]
        expected = 'FRONT' if chapter == 0 else 'OPEN' if opening else 'CONT'
        require(''.join(footer[page]) == f'{expected} M-{page+1} | {page+1}/{len(pages)}', 'manual page-label/physical/total/footer fields changed')
        require(''.join(header[page]) == (f'Procedure {chapter} running' if chapter and not opening else ''), 'manual running label or opening template changed')
        bounds[page] = (F(98), F(732 if chapter and not opening else 770))
    return bounds, repeat


def panel_geometry(root: Node, artifacts, bounds) -> None:
    panels = panels_from_artifacts(artifacts)
    outer_padding = {}
    def visit(node: Node, amount: int = 0):
        outer_padding[node.number] = amount
        for child in node.children:
            visit(child, amount + (node.expected.padding if node.role == 'Div' else 0))
    visit(root)
    for node in root.descendants():
        for mark in node.marks:
            bottom, top = bounds[mark.page]
            require(mark.bounds[1] >= bottom and mark.bounds[3] <= top, 'manual content escaped its declared scope frame')
        if node.role != 'Div':
            continue
        padding = node.expected.padding
        pages = sorted({mark.page for mark in node.marks})
        require(pages == list(range(pages[0], pages[-1]+1)), 'manual callout skipped a continuation page')
        for page in pages:
            marks = [mark for mark in node.marks if mark.page == page]
            low, high = min(mark.bounds[1] for mark in marks), max(mark.bounds[3] for mark in marks)
            candidates = [panel for panel in panels if not panel.used and panel.page == page and abs(panel.rect[0] - node.left) <= TOL and abs(panel.rect[2] - node.right + node.left) <= TOL and panel.rect[1] + padding <= low and panel.rect[1] + panel.rect[3] - padding >= high]
            require(len(candidates) == 1, 'manual lost its unique padded callout fragment')
            panel = candidates[0]; panel.used = True
            x, y, width, height = panel.rect
            require(panel.order < min(mark.order for mark in marks), 'manual panel paints over its content')
            require(y >= bounds[page][0] and y + height <= bounds[page][1], 'manual panel escaped its scope body frame')
            expected_top = high + padding if page == pages[0] else bounds[page][1] - outer_padding[node.number]
            require(y + height == expected_top, 'manual continuation reopened padding below the wrong template/header')
            if page == pages[-1]:
                require(y == low - padding, 'manual closing panel padding changed')
            for artifact_page, kind, block, _ in artifacts:
                if artifact_page != page or b'/Layout' not in kind or not RECT.search(block):
                    continue
                for rectangle in RECT.findall(block):
                    rx, ry, rw, rh = (F(p.decode()) for p in rectangle)
                    if (rh < 1 or rw < 1 or color(block) in {(219, 228, 233), (227, 233, 238)}) and y <= ry <= y+height:
                        require(rx >= x+padding-TOL and rx+rw <= x+width-padding+TOL and ry >= y+padding and ry+rh <= y+height-padding, 'manual continued table decoration escaped its actual panel frame')
    require(all(panel.used for panel in panels), 'manual empty/duplicate panel')


def source_and_headers(root: Node, repeat) -> None:
    expected_repeats = Counter()
    for node in root.descendants():
        if node.role == 'Code':
            glyphs = [glyph for mark in node.marks for glyph in mark.glyphs]
            expected = [(character, (0, 0, 0)) for character in node.expected.actual.replace('\n', '')]
            expected[2:8] = [(c, (128, 0, 192)) for c, _ in expected[2:8]]
            require([(glyph[0], glyph[4]) for glyph in glyphs] == expected, 'manual source characters/foregrounds changed')
            require(all(glyph[3] == 9 for glyph in glyphs), 'manual source local typography changed')
        if node.role == 'Table':
            pages = sorted({mark.page for mark in node.children[-1].marks})
            require(len(pages) >= 2, 'manual checklist no longer exercises continuation')
            for page in pages[1:]:
                expected_repeats[(page, node.left)] += 1
    observed = Counter()
    for page, marks in repeat.items():
        lines = defaultdict(list)
        for mark in marks:
            lines[mark.glyphs[0][2]].append(mark)
        for baseline, line in lines.items():
            line.sort(key=lambda mark: mark.bounds[0])
            require(''.join(mark.text for mark in line) == 'StepContents label M-1', 'manual repeated header reference or text changed')
            left = line[0].bounds[0] - 4
            observed[(page, left)] += 1
            # Both nested panels and the table footprint precede the repeated header.
            require(baseline + 11 <= 732 - 8 - 6 - 2, 'manual repeated header overlaps reopened padding/running furniture')
    require(len(expected_repeats) == len(observed), 'manual repeated header page set changed')
    for (page, left), count in expected_repeats.items():
        require(sum(n for (p, x), n in observed.items() if p == page and abs(x-left) <= TOL) == count, 'manual missing/duplicated table header artifact')


def fixed_reference_widths(root: Node, chapters: int, starts: dict[int, int]) -> None:
    # The fixture puts a literal before each symbolic field. These independent
    # glyph advances prove the reservation and the requested End alignment.
    for number in range(1, chapters+1):
        node = root.children[number]
        marks = node.marks
        label = next(mark for mark in marks if mark.text == f'M-{starts[number]}')
        before = next(mark for mark in marks if mark.text == ' — label ')
        require(abs(label.bounds[2] - before.bounds[2] - 44) <= TOL, 'manual TOC label field lost fixed width or End alignment')
        physical = marks[-1]
        literal = next(mark for mark in marks if mark.text == '; physical ')
        require(physical.text == str(starts[number]) and abs(physical.bounds[2] - literal.bounds[2] - 24) <= TOL, 'manual TOC physical field lost fixed width or End alignment')


def validate_technical_manual_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    chapters = dimensions['chapters']
    document, pages, root, artifacts = read_manual(pdf)
    require(len(pages) == dimensions['pages'], 'manual page count changed')
    starts, headings = heading_pages(root, chapters)
    match_tree(root, contract(chapters, starts))
    destinations(document, pages, root, headings)
    frames(root)
    bounds, repeat = furniture(document, pages, artifacts, starts)
    panel_geometry(root, artifacts, bounds)
    source_and_headers(root, repeat)
    fixed_reference_widths(root, chapters, starts)


def replace_digit(document: Document, page: int, block: bytes, old: str, new: str) -> bytes:
    selected = FONT.findall(block)
    require(len(selected) == 1, 'manual mutation needs one exact face')
    fonts = document.get(page)['Resources']['Font']
    mapping = to_unicode(document, int(fonts[selected[0][0].decode()]))
    old_cid = next(cid for cid, text in mapping.items() if text == old)
    new_cid = next(cid for cid, text in mapping.items() if text == new)
    for shown in re.finditer(rb'<([0-9A-F]+)>', block):
        raw = shown[1]
        for offset in range(0, len(raw), 4):
            if int(raw[offset:offset+4], 16) == old_cid:
                return block[:shown.start(1)+offset] + f'{new_cid:04X}'.encode() + block[shown.start(1)+offset+4:]
    raise ValidationError('manual mutation could not find its printed digit')


def self_test():
    cases = [case for case in json.loads((ROOT/'tests/spec.json').read_text())['cases'] if 'technical_manual' in case['validators']]
    require(len(cases) == 2 and {case['dimensions']['chapters'] for case in cases} == {2, 20}, 'manual scale pair incomplete')
    for case in cases:
        validate_technical_manual_pdf((ROOT/case['snapshot']).read_bytes(), case['dimensions'])
    sample = next(case for case in cases if case['dimensions']['chapters'] == 2)
    pdf = (ROOT/sample['snapshot']).read_bytes()
    document, pages, root, artifacts = read_manual(pdf)
    starts, nodes = heading_pages(root, 2)
    label = next(mark for mark in root.children[1].marks if mark.text == f'M-{starts[1]}')
    wrong_label = replace_digit(document, pages[label.page], label.block, str(starts[1])[-1], '9')
    mutations = [
        (label.block, wrong_label),
        (f'/SD [{nodes[1].number} 0 R /XYZ'.encode(), f'/SD [{nodes[2].number} 0 R /XYZ'.encode()),
        (b'/Subtype /Header', b'/Subtype /Footer'),
        (b'451 1 re\nf', b'452 1 re\nf'),
    ]
    for old, new in mutations:
        mutant = twin(pdf, old, new)
        try:
            validate_technical_manual_pdf(mutant, sample['dimensions'])
        except ValidationError:
            pass
        else:
            raise ValidationError(f'manual oracle accepted mutation {old[:60]!r}')
    print('PASS combined manual destination/printed values, scoped furniture, rich LI/callout source/diagram/table semantics and geometry, and four mutation twins')


def reader_check(mutool: Path | None):
    cases = [case for case in json.loads((ROOT/'tests/spec.json').read_text())['cases'] if 'technical_manual' in case['validators']]
    output = ROOT/'.roc-pdf-tmp/technical-manual-readers'
    classes = output/'classes'; classes.mkdir(parents=True, exist_ok=True)
    jar = ROOT/'vendor/pdfbox/pdfbox-app-3.0.8.jar'
    def run(command: list[str]) -> bytes:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        require(result.returncode == 0 and not result.stderr.strip(), f'manual reader failed: {result.stderr.decode(errors="replace")}')
        return result.stdout
    run(['javac', '-cp', str(jar), '-d', str(classes), str(ROOT/'scripts/PdfBoxPages.java')])
    total = 0
    for case in cases:
        path = ROOT/case['snapshot']; pdf = path.read_bytes()
        validate_technical_manual_pdf(pdf, case['dimensions'])
        document, pages, root, _ = read_manual(pdf)
        expected = []
        for page in pages:
            stream = document.stream(int(document.get(page)['Contents']))
            fonts = document.get(page)['Resources']['Font']
            maps = {name: to_unicode(document, int(font)) for name, font in fonts.items()}
            pieces = []
            for sequence in sequences(stream):
                block = sequence.clean(stream); selected = FONT.findall(block)
                if selected:
                    require(len(selected) == 1, 'manual reader text piece mixes exact faces')
                    pieces.append((sequence.start, decoded_text(block, maps[selected[0][0].decode()])))
            expected.append(''.join(text for _, text in sorted(pieces)))
        box = output/path.stem/'pdfbox'
        count = int(run(['java', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{jar}', 'PdfBoxPages', str(path), str(box)]))
        require(count == len(pages), 'PDFBox manual page count changed')
        extracted = ''.join((box/f'page-{page:04d}.txt').read_text() for page in range(1, count+1))
        require(''.join(extracted.split()) == ''.join(''.join(expected).split()), 'PDFBox manual whole-file extraction changed text/order')
        engines = [('PDFBox 3.0.8', [box/f'page-{page:04d}.ppm' for page in range(1, count+1)])]
        if mutool is not None:
            mupdf = output/path.stem/'mupdf'; mupdf.mkdir(exist_ok=True)
            run([str(mutool), 'draw', '-q', '-r', '72', '-c', 'rgb', '-o', str(mupdf/'page-%d.ppm'), str(path)])
            extracted = run([str(mutool), 'draw', '-q', '-F', 'txt', '-O', 'ignore-actualtext', '-o', '-', str(path)]).decode()
            require(''.join(extracted.split()) == ''.join(''.join(expected).split()), 'MuPDF manual glyph/ToUnicode extraction changed text/order')
            engines.append(('MuPDF 1.28.2', [mupdf/f'page-{page}.ppm' for page in range(1, count+1)]))
        purple_pages = {mark.page for node in root.descendants() if node.role == 'Code' for mark in node.marks if any(glyph[4] == (128,0,192) for glyph in mark.glyphs)}
        figure_pages = {mark.page for node in root.descendants() if node.role == 'Figure' for mark in node.marks}
        for engine, paths in engines:
            for page, image in enumerate(paths):
                raster = read_ppm(image)
                require((raster.width, raster.height) == (595,842) and min(raster.pixels) < 100, f'{engine} lost manual page geometry/ink')
                purple = blue = False
                for offset in range(0,len(raster.pixels),3):
                    red,green,b = raster.pixels[offset:offset+3]
                    purple |= red > green+60 and b > green+80
                    blue |= b > red+30 and b > green+10 and b < 200
                if page in purple_pages:
                    require(purple, f'{engine} lost manual source foreground')
                if page in figure_pages:
                    require(blue, f'{engine} lost prepared diagram vector/label ink')
                total += 1
    print(f'PASS manual whole-file PDFBox/MuPDF text, references, headers, foreground and vector ink: {total} page renders')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--readers', action='store_true')
    parser.add_argument('--mutool', type=Path)
    args = parser.parse_args()
    try:
        require(args.self_test or args.readers, 'use --self-test or --readers')
        if args.self_test:
            self_test()
        if args.readers:
            reader_check(args.mutool)
    except (ValidationError, ValueError) as error:
        raise SystemExit(f'FAIL {error}') from error
