#!/usr/bin/env python3
"""Independent original-byte colour mapping and colour/plain geometry oracle."""
from __future__ import annotations

import argparse
import json
import re
import os
import subprocess
from fractions import Fraction
from pathlib import Path

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text, text_string, to_unicode
from check_visual_renderers import read_ppm
from check_source_blocks import BODY, MARKED, FONT, RECT, ARTIFACT, URL, widths, decoded_text
from check_structure_semantics import Document, Ref, element_children, page_order
from text_positions import glyph_positions

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = (20, 40, 80)
KEYWORD = (128, 0, 192)
STRING = (0, 80, 208)
COMMENT = (0, 128, 64)


def original(dimensions: dict[str, int]) -> tuple[str, list[tuple[int, int, tuple[int, int, int]]]]:
    kind, lines = dimensions['foreground_kind'], dimensions['source_lines']
    if kind in (0, 3):
        text = '\tlet café = "blue"\r\n\r\n  # comment  \n\n'
        ranges = [(0, 4, KEYWORD), (5, 10, STRING), (13, 19, STRING), (25, 36, COMMENT)]
    elif kind == 1:
        text = URL + '\n' + 'x' * 220 + '\n  final = 42\n' + '\n'.join(f'line {n} = "kept exactly once"' for n in range(1, 81))
        ranges = [(0, 122, STRING), (123, len(text.encode()), COMMENT)]
    elif kind == 2:
        line = 'let x = 42 # note\n'
        text = line * lines
        ranges = [(i * len(line) + start, i * len(line) + end, color) for i in range(lines) for start, end, color in ((0, 3, KEYWORD), (8, 10, STRING), (11, 16, COMMENT))]
    else:
        raise ValidationError('unknown foreground scenario')
    return text, ranges if dimensions['colored'] else []


def canonical(dimensions: dict[str, int]) -> tuple[str, list[tuple[str, tuple[int, int, int]]]]:
    source, ranges = original(dimensions)
    result: list[str] = []
    painted: list[tuple[str, tuple[int, int, int]]] = []
    byte = column = cursor = 0
    for character in source:
        start = byte
        byte += len(character.encode())
        if character == '\r':
            continue
        while cursor < len(ranges) and ranges[cursor][1] <= start:
            cursor += 1
        color = ranges[cursor][2] if cursor < len(ranges) and ranges[cursor][0] <= start < ranges[cursor][1] else DEFAULT
        expanded = ' ' * (4 - column % 4) if character == '\t' else character
        result.append(expanded)
        if character == '\n':
            column = 0
        else:
            column += len(expanded)
            painted.extend((scalar, color) for scalar in expanded)
    if dimensions['foreground_kind'] == 3:
        return ''.join(result) * 2, painted + [(character, (0, 0, 0)) for character in ''.join(result).replace('\n', '')]
    return ''.join(result), painted


def inspect(pdf: bytes) -> tuple[str, list[tuple[object, ...]], list[tuple[object, ...]], list[str]]:
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog['Pages']), pages)
    marked = {(page, mcid): text for page in pages for mcid, text in page_marked_text(document, page)}
    codes: list[str] = []
    logical: list[str] = []
    roles: list[str] = []
    def walk(number: int) -> None:
        element = document.get(number)
        roles.append(element['S'])
        if element['S'] == 'Code':
            codes.append(text_string(element['ActualText']))
        for child in element_children(document, element):
            if isinstance(child, Ref):
                walk(int(child))
            elif isinstance(child, dict) and child.get('Type') == 'MCR':
                logical.append(marked[(int(child['Pg']), int(child['MCID']))])
    walk(int(document.get(int(catalog['StructTreeRoot']))['K']))
    require(len(codes) >= 1 and roles.count('Code') == len(codes) and not {'Span', 'Strong', 'Em', 'Figure'} & set(roles), 'foreground colours changed source semantic elements')
    glyphs: list[tuple[object, ...]] = []
    panels: list[tuple[object, ...]] = []
    paint: list[str] = []
    for page_index, page in enumerate(pages):
        value = document.get(page)
        fonts = value['Resources']['Font']
        content = document.stream(int(value['Contents']))
        maps = {name: to_unicode(document, int(ref)) for name, ref in fonts.items()}
        advances = {name.encode(): widths(document, int(ref)) for name, ref in fonts.items()}
        for artifact in ARTIFACT.findall(content):
            for rectangle in RECT.findall(artifact):
                panels.append((page_index, *map(Fraction, (part.decode() for part in rectangle))))
        for match in MARKED.finditer(content):
            block = match.group(2)
            selections = FONT.findall(block)
            require(len(selections) == 1, 'foreground piece did not retain one exact face')
            name, size = selections[0]
            text = decoded_text(block, maps[name.decode()])
            paint.append(text)
            origin = re.findall(rb'1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm', block)
            require(len(origin) == 1, 'foreground piece lost explicit origin')
            tx, ty = (Fraction(part.decode()) * 1000 for part in origin[0])
            colors = re.findall(rb'([0-9.]+) ([0-9.]+) ([0-9.]+) scn', block)
            require(len(colors) == 1 and re.search(rb'/CS[0-9_]+ cs', block), 'foreground text bypassed profile-aware colour')
            components = tuple(Fraction(part.decode()) for part in colors[0])
            color = tuple(round(component * 255) for component in components)
            require(all(abs(component - Fraction(channel, 255)) <= Fraction(1, 10**9) for component, channel in zip(components, color)), 'foreground colour lost exact sRGB channel values')
            source_font = 'SourceCodePro' in str(document.get(int(fonts[name.decode()]))['BaseFont'])
            positions = glyph_positions(block, advances)
            require(len(positions) == len(text), 'source glyph/text cardinality changed')
            for character, (font, cid, x, y) in zip(text, positions):
                if source_font:
                    glyphs.append((character, page_index, x + tx, y + ty, Fraction(size.decode()), color))
    require(paint == logical, 'foreground paint order differs from semantic reading order')
    return ''.join(codes), glyphs, panels, roles


def validate_source_foregrounds_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    expected, colored = canonical(dimensions)
    actual, glyphs, panels, _ = inspect(pdf)
    require(actual == expected, 'original byte normalization changed canonical Code ActualText')
    require([(g[0], g[5]) for g in glyphs] == colored, 'foreground ranges lost text, original UTF-8 mapping, tabs, or per-character colours')
    require(len(panels) == dimensions.get('panels', dimensions['pages']), 'foreground continuation lost padded artifact panels')
    require(all(g[4] == 9 for g in glyphs), 'foreground changed source typography')


def self_test() -> None:
    cases = [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'source_foregrounds' in case['validators']]
    require(len(cases) == 10, 'foreground paired coverage incomplete')
    for case in cases:
        pdf = (ROOT / case['snapshot']).read_bytes()
        validate_source_foregrounds_pdf(pdf, case['dimensions'])
        if case['dimensions']['colored']:
            plain = (ROOT / case['snapshot'].replace('_color.pdf', '_plain.pdf')).read_bytes()
            a, ga, pa, ra = inspect(pdf)
            b, gb, pb, rb = inspect(plain)
            require((a, [g[:5] for g in ga], pa, ra) == (b, [g[:5] for g in gb], pb, rb), 'foreground ranges changed positions, wrapping, pagination, panels, or semantic roles')
            try:
                validate_source_foregrounds_pdf(plain, case['dimensions'])
            except ValidationError:
                pass
            else:
                raise ValidationError('colour oracle accepted monochrome mutation twin')
    print('PASS source foreground original-byte mapping, colours, exact geometry/semantics, continuation, scale pairs and monochrome rejection twins')


def reader_check(mutool: Path | None, pdfium: Path | None) -> None:
    cases = [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases'] if 'source_foregrounds' in case['validators']]
    output = ROOT / '.roc-pdf-tmp' / 'source-foreground-readers'
    classes = output / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    jar = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'
    def run(command: list[str]) -> bytes:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        require(result.returncode == 0 and not result.stderr.strip(), f'reader failed: {command}: {result.stderr.decode(errors="replace")}')
        return result.stdout
    run(['javac', '-cp', str(jar), '-d', str(classes), str(ROOT / 'scripts/PdfBoxPages.java')])
    total = 0
    for case in cases:
        snapshot = ROOT / case['snapshot']
        original_pdf = snapshot.read_bytes()
        dimensions = case['dimensions']
        validate_source_foregrounds_pdf(original_pdf, dimensions)
        _, glyphs, _, _ = inspect(original_pdf)
        stem = snapshot.stem
        box = output / stem / 'pdfbox'
        pages = int(run(['java', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{jar}', 'PdfBoxPages', str(snapshot), str(box)]))
        require(pages == dimensions['pages'], 'PDFBox foreground page count changed')
        expected = BODY[0] + canonical(dimensions)[0] + BODY[1] + BODY[2]
        extracted = ''.join((box / f'page-{page:04d}.txt').read_text() for page in range(1, pages + 1))
        require(''.join(extracted.split()) == ''.join(expected.split()), 'PDFBox foreground extraction lost or reordered source')
        engines = [('PDFBox 3.0.8', [box / f'page-{page:04d}.ppm' for page in range(1, pages + 1)])]
        if mutool is not None:
            mupdf = output / stem / 'mupdf'
            mupdf.mkdir(exist_ok=True)
            run([str(mutool), 'draw', '-q', '-r', '72', '-c', 'rgb', '-o', str(mupdf / 'page-%d.ppm'), str(snapshot)])
            # Explicit glyph/ToUnicode extraction; default parent-ActualText
            # repetition is retained below as a separate reader observation.
            extracted = run([str(mutool), 'draw', '-q', '-F', 'txt', '-O', 'ignore-actualtext', '-o', '-', str(snapshot)]).decode()
            require(''.join(extracted.split()) == ''.join(expected.split()), 'MuPDF glyph/ToUnicode extraction lost or reordered source')
            if dimensions['foreground_kind'] == 0:
                default = run([str(mutool), 'draw', '-q', '-F', 'txt', '-o', '-', str(snapshot)]).decode()
                (mupdf / 'default-actualtext.txt').write_text(default)
                repetitions = 7 if dimensions['colored'] else 2
                observed = BODY[0] + canonical(dimensions)[0] * repetitions + BODY[1] + BODY[2]
                require(''.join(default.split()) == ''.join(observed.split()), 'MuPDF parent-ActualText observation changed; review its original-byte report')
            engines.append(('MuPDF 1.28.2', [mupdf / f'page-{page}.ppm' for page in range(1, pages + 1)]))
        if pdfium is not None:
            rendered = output / stem / 'pdfium'
            rendered.mkdir(exist_ok=True)
            count = int(run(['docker', 'run', '--rm', '--platform', 'linux/amd64', '-v', f'{ROOT}:/work:ro', '-v', f'{pdfium.resolve()}:/pdfium:ro', '-v', f'{rendered}:/output', '-e', 'LD_LIBRARY_PATH=/pdfium/lib', 'ubuntu:24.04', '/pdfium/pdfium_pages', '/work/' + case['snapshot'], '/output']))
            require(count == pages, 'PDFium foreground page count changed')
            engines.append(('PDFium 7988', [rendered / f'page-{page:04d}.ppm' for page in range(1, pages + 1)]))
        for engine, paths in engines:
            for page, path in enumerate(paths):
                raster = read_ppm(path)
                require((raster.width, raster.height) == (595, 842), f'{engine} page geometry changed')
                require(min(raster.pixels) < 100, f'{engine} lost source/body ink')
                expected_colors = {glyph[5] for glyph in glyphs if glyph[1] == page and not str(glyph[0]).isspace()} & {KEYWORD, STRING, COMMENT}
                seen = set()
                for offset in range(0, len(raster.pixels), 3):
                    red, green, blue = raster.pixels[offset:offset + 3]
                    if red > green + 60 and blue > green + 80:
                        seen.add(KEYWORD)
                    if blue > red + 80 and blue > green + 60:
                        seen.add(STRING)
                    if green > red + 60 and green > blue + 40:
                        seen.add(COMMENT)
                require(expected_colors <= seen, f'{engine} lost highlighted colour on page {page + 1}: {expected_colors - seen}')
        require(snapshot.read_bytes() == original_pdf, 'reader changed the original PDF')
        total += pages
        print(f'PASS foreground readers: {snapshot.name}, {pages} pages, {len(engines)} engines, exact extractor text and raster colours', flush=True)
    print(f'PASS foreground reader matrix: {len(cases)} original PDFs, {total} pages', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--readers', action='store_true')
    parser.add_argument('--mutool', type=Path)
    parser.add_argument('--pdfium', type=Path, help='Provisioned PDFium Linux directory with lib/ and pdfium_pages')
    args = parser.parse_args()
    if args.self_test:
        self_test()
    if args.readers:
        reader_check(args.mutool, args.pdfium)
