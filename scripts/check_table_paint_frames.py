#!/usr/bin/env python3
"""Check scoped table paint against authored frames, without paginator/report facts."""
from __future__ import annotations

import argparse
from fractions import Fraction as F
import json
import os
import subprocess
from pathlib import Path
import re

from check_pdf_structure import ValidationError, require
from check_rich_flow import ARTIFACT, FONT, MARKED, RECT, paint, read
from check_visual_renderers import read_ppm
from check_structure_semantics import furniture_by_page
from pdf_layout import twin

ROOT = Path(__file__).resolve().parents[1]


def inspect(pdf: bytes, count: int, mode: int) -> None:
    document, pages, root, artifacts = read(pdf)
    require(len(pages) == 3 * count + 1, 'scoped table page count/empty boundary changed')
    require([n.role for n in root.children] == ['Table'] * count + ['H1'], 'scoped tables changed semantic ownership')
    require(root.children[-1].text == 'End target', 'table end destination changed')
    require({m.page for m in root.children[-1].marks} == {len(pages) - 1}, 'scope exit did not commit a fresh unscoped page')
    furniture = furniture_by_page(document, pages)
    painted = mode in (0, 1, 2, 5)
    padding = 3 if painted else 0
    for group, table in enumerate(root.children[:-1]):
        require([n.role for n in table.children] == ['THead', 'TBody'], 'one logical table header/body was not retained')
        header, body = table.children
        require(len(header.children) == 1 and len(body.children) == 80, 'table rows lost/repeated')
        expected_header = ['Step'] if mode == 4 else ['Step', f'End {len(pages)}' if mode == 5 else 'Detail']
        require([n.text for n in header.children[0].children] == expected_header, 'logical table header/reference value changed')
        for number, row in enumerate(body.children, 1):
            expected = [f'S{group + 1} row {number}'] + ([] if mode == 4 else ['Boundary data'])
            require([n.text for n in row.children] == expected, 'table body text/order/ownership changed')
        table_pages = {m.page for m in table.marks}
        require(table_pages == set(range(3 * group, 3 * group + 3)), 'table scope continuation changed')
        for local in range(3):
            index = 3 * group + local
            top, bottom = (F(746), F(106)) if local == 0 else (F(726), F(126))
            headers = ''.join(text for kind, _body, text in furniture[index] if kind == 'Header')
            footers = ''.join(text for kind, _body, text in furniture[index] if kind == 'Footer')
            require(headers == f'{"OPEN" if local == 0 else "CONT"} {group + 1}' and footers == f'LOW {group + 1}', 'selected scoped furniture changed')
            marks = [m for m in table.marks if m.page == index]
            repeated = []
            rectangles = []
            for page, props, block, _order in artifacts:
                if page != index:
                    continue
                require(not re.search(rb'(?:^|\n)(?:W|W\*|[4-7] Tr)(?:\n|$)', block), 'table decoration was clipped')
                if FONT.search(block) and b'/Subtype' not in props:
                    require(props == b'<</Type /Pagination>>', 'repeated table header lost pagination artifact ownership')
                    repeated.append(paint(document, pages[index], index, -1, block))
                for raw in RECT.findall(block):
                    x, y, w, h = (F(v.decode()) for v in raw)
                    require(props == b'<</Type /Layout>>', 'table decoration lost layout artifact ownership')
                    require(F(72) <= x <= x + w <= F(523) and bottom <= y <= y + h <= top, f'page {index + 1}: table paint escaped selected body frame: {(x, y, w, h)}')
                    rectangles.append((x, y, w, h))
            require(''.join(m.text for m in repeated) == (''.join(expected_header) if local else ''), 'repeated header text/reference differs or became semantic content')
            physical = marks + repeated
            require(physical and max(m.bounds[3] for m in physical) == top - padding, 'table first/repeated row did not reserve exactly its outer half gap')
            require(all(F(72) <= m.bounds[0] <= m.bounds[2] <= F(523) and bottom <= m.bounds[1] <= m.bounds[3] <= top for m in physical), 'table text escaped scoped body frame')
            physical_rows = len({m.bounds[3] for m in physical})
            require(physical_rows == (32 if local == 0 else 30 if local == 1 else 21), 'exact boundary rows did not fit as specified')
            if local < 2 and painted:
                require(min(m.bounds[1] for m in physical) - padding == bottom, 'full table fragment did not consume the exact lower painted boundary')
            require(bool(rectangles) == (mode != 4), 'paint/no-paint table control changed')
            if mode in (0, 5):
                require(max(y + h for _x, y, _w, h in rectangles) == top, 'table outer paint left an unreserved top gap')
                if local < 2:
                    require(min(y for _x, y, _w, _h in rectangles) == bottom, 'table outer paint left an unreserved bottom gap')
    require(not furniture[-1], 'scope furniture escaped the explicit boundary')


def validate_table_paint_frames_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    inspect(pdf, dimensions['table_scope_count'], dimensions['table_paint_mode'])


def self_test() -> None:
    cases = [c for c in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'table_paint_frames' in c['validators']]
    require(len(cases) == 7, 'scoped table footprint case matrix incomplete')
    for case in cases:
        validate_table_paint_frames_pdf((ROOT / case['snapshot']).read_bytes(), case['dimensions'])
    sample = next(c for c in cases if c['dimensions']['table_scope_count'] == 2)
    original = (ROOT / sample['snapshot']).read_bytes()
    # Move actual emitted paint beyond each authored boundary, independently
    # of source code, stored work counters, and the accepted-page facts.
    document, pages, _root, artifacts = read(original)
    first = [block for page, _props, block, _order in artifacts if page == 0 and RECT.search(block)]
    rectangles = [raw for block in first for raw in RECT.findall(block)]
    top = next(raw for raw in rectangles if F(raw[1].decode()) + F(raw[3].decode()) == 746)
    bottom = next(raw for raw in rectangles if F(raw[1].decode()) == 106)
    changes = [
        (b' '.join(top) + b' re', b' '.join([top[0], top[1], top[2], str(F(top[3].decode()) + 1).encode()]) + b' re'),
        (b' '.join(bottom) + b' re', b' '.join([bottom[0], b'105', bottom[2], bottom[3]]) + b' re'),
        (b'/Artifact <</Type /Pagination>>', b'/Artifact <</Type /Layout>>'),
        (b'/Subtype /Header', b'/Subtype /Footer'),
    ]
    for old, new in changes:
        damaged = twin(original, old, new)
        try:
            validate_table_paint_frames_pdf(damaged, sample['dimensions'])
        except ValidationError:
            pass
        else:
            raise ValidationError(f'table paint checker accepted mutation {old!r}')
    print('PASS scoped table painted boundaries, source-free references, semantic/repeated headers and four mutation twins')


def reader_check(mutool: Path | None) -> None:
    cases = [c for c in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'table_paint_frames' in c['validators']]
    output = ROOT / '.roc-pdf-tmp/table-paint-readers'
    classes = output / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    jar = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'

    def run(command: list[str]) -> bytes:
        result = subprocess.run(command, capture_output=True, timeout=180)
        require(result.returncode == 0 and not result.stderr.strip(), f'table paint reader failed: {result.stderr.decode(errors="replace")}')
        return result.stdout

    run(['javac', '-cp', str(jar), '-d', str(classes), str(ROOT / 'scripts/PdfBoxPages.java')])
    total = 0
    for case in cases:
        path = ROOT / case['snapshot']
        validate_table_paint_frames_pdf(path.read_bytes(), case['dimensions'])
        document, pages, _root, _artifacts = read(path.read_bytes())
        expected = []
        for index, page in enumerate(pages):
            stream = document.stream(int(document.get(page)['Contents']))
            pieces = [(m.start(), m[2]) for m in MARKED.finditer(stream)]
            pieces += [(m.start(), m[2]) for m in ARTIFACT.finditer(stream) if FONT.search(m[2])]
            expected.append(''.join(paint(document, page, index, -1, block).text for _order, block in sorted(pieces)))
        box = output / path.stem / 'pdfbox'
        count = int(run(['java', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{jar}', 'PdfBoxPages', str(path), str(box)]))
        require(count == len(pages), 'PDFBox table paint page count changed')
        text = ''.join((box / f'page-{page:04d}.txt').read_text() for page in range(1, count + 1))
        require(''.join(text.split()) == ''.join(''.join(expected).split()), 'PDFBox table/reference/furniture extraction changed')
        engines = [[box / f'page-{page:04d}.ppm' for page in range(1, count + 1)]]
        if mutool is not None:
            mupdf = output / path.stem / 'mupdf'
            mupdf.mkdir(exist_ok=True)
            run([str(mutool), 'draw', '-q', '-r', '72', '-c', 'rgb', '-o', str(mupdf / 'page-%d.ppm'), str(path)])
            text = run([str(mutool), 'draw', '-q', '-F', 'txt', '-O', 'ignore-actualtext', '-o', '-', str(path)]).decode()
            require(''.join(text.split()) == ''.join(''.join(expected).split()), 'MuPDF table/reference/furniture extraction changed')
            engines.append([mupdf / f'page-{page}.ppm' for page in range(1, count + 1)])
        for images in engines:
            for image in images:
                raster = read_ppm(image)
                require((raster.width, raster.height) == (595, 842) and min(raster.pixels) < 100, 'reader lost table page geometry/ink')
                image.unlink()  # The source PDFs and exact oracle remain the evidence.
                total += 1
    print(f'PASS table paint PDFBox/MuPDF whole-file text and rendering: {total} page renders')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--readers', action='store_true')
    parser.add_argument('--mutool', type=Path)
    parser.add_argument('pdf', type=Path, nargs='?')
    parser.add_argument('--count', type=int, default=2)
    parser.add_argument('--mode', type=int, default=0)
    args = parser.parse_args()
    require(args.self_test or args.readers or args.pdf is not None, 'use --self-test, --readers or a fixture PDF')
    if args.self_test:
        self_test()
    if args.readers:
        reader_check(args.mutool)
    if args.pdf is not None:
        inspect(args.pdf.read_bytes(), args.count, args.mode)
        print('PASS scoped table painted frame')
