#!/usr/bin/env python3
"""Check printed references against committed PDF destinations and label rules.

This oracle reads emitted glyphs, structure, annotations and /PageLabels. It
never reads the Roc reference plan, measured rows, reports or resolved values.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from fractions import Fraction as F
from pathlib import Path
import re

from check_navigation import check_name_tree
from check_pdf_structure import ValidationError, require
from check_rich_flow import ARTIFACT, FONT, MARKED, ORIGIN, TOL, paint, read
from check_visual_renderers import read_ppm
from check_rich_inline import text_string
from check_structure_semantics import element_children
from pdf_layout import twin

ROOT = Path(__file__).resolve().parents[1]


def roman(number: int) -> str:
    value = []
    for count, letters in ((1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'),
                           (100, 'C'), (90, 'XC'), (50, 'L'), (40, 'XL'),
                           (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')):
        copies, number = divmod(number, count)
        value.append(letters * copies)
    return ''.join(value)


def page_label(document, page: int) -> str:
    catalog = document.get(document.root)
    if 'PageLabels' not in catalog:
        return str(page + 1)
    rules = document.get(int(catalog['PageLabels']))['Nums']
    candidates = [(rules[index], rules[index + 1]) for index in range(0, len(rules), 2)
                  if rules[index] <= page]
    require(candidates, 'reference label rules omit the physical page')
    start, rule = max(candidates, key=lambda pair: pair[0])
    number = rule.get('St', 1) + page - start
    style = rule.get('S')
    if style is None:
        value = ''
    elif style == 'D':
        value = str(number)
    elif style in ('r', 'R'):
        value = roman(number)
        value = value.lower() if style == 'r' else value
    elif style in ('a', 'A'):
        value = chr(ord('A') + (number - 1) % 26) * ((number - 1) // 26 + 1)
        value = value.lower() if style == 'a' else value
    else:
        raise ValidationError('unsupported emitted label rule')
    return text_string(rule.get('P', b'')) + value


def overrides(marks) -> str:
    # The occurrence's exact logical override is carried by its actual paint
    # pieces; it is not a structure element property on the enclosing Link/P.
    return ''.join(text_string(bytes.fromhex(value.decode()))
                   for mark in marks
                   for value in re.findall(rb'/ActualText\s*<([0-9A-Fa-f]+)>', mark.block))


def close(actual, expected, message: str) -> None:
    require(abs(actual - expected) <= TOL, f'{message}: {actual} != {expected}')


def validate_geometry(document, pages, root, artifacts, dimensions) -> None:
    require(len(pages) == dimensions['pages'] == 3, 'scaled geometry introduced a blank or extra page')
    named = check_name_tree(document.bodies, document.root, pages)
    require(set(named) == {b'target'}, 'scaled geometry target changed')
    heading = next(node for node in root.children if node.role == 'H1')
    require(heading.text == 'Geometry target' and {mark.page for mark in heading.marks} == {2},
            'scaled geometry target heading moved')
    require(named[b'target'][0] == pages[2], 'scaled reference destination and heading disagree')
    require(not any(node.role == 'Link' for node in root.descendants()), 'reference created an automatic link')
    require(all(not document.get(page).get('Annots') for page in pages), 'unlinked reference created an annotation')

    # The fixture registers a 600-unit monospace face. Read its emitted resource
    # identity and widths before using that independently known cell geometry.
    def scaled(marks, baseline=None):
        require(marks and all(mark.glyphs for mark in marks), 'scaled text lost its paint')
        for mark in marks:
            resource = FONT.search(mark.block)[1].decode()
            font = int(document.get(pages[mark.page])['Resources']['Font'][resource])
            require('NotoMonoCodeFixture' in str(document.get(font)['BaseFont']), 'scaled text changed its registered face')
            _, font_widths = document._rich_fonts[font]
            require(set(font_widths.values()) == {600}, 'geometry fixture monospace widths changed')
            require(all(glyph[3] == F(15, 2) for glyph in mark.glyphs), 'scaled-only body reverted to theme size')
            if baseline is not None:
                close(mark.glyphs[0][2], baseline, 'scaled-only baseline')

    def visible(marks):
        glyphs = [glyph for mark in marks for glyph in mark.glyphs if glyph[0] != ' ']
        require(glyphs, 'aligned cell lost its visible glyphs')
        return min(g[1] for g in glyphs), max(g[1] + g[3] * F(3, 5) for g in glyphs)

    paragraphs = [node for node in root.children if node.role == 'P']
    require([node.text for node in paragraphs] == ['Scaled literal.', '3'], 'scaled-only paragraphs changed')
    require(any(node.role == 'Code' for node in paragraphs[0].descendants()), 'literal code ownership changed')
    scaled(paragraphs[0].marks, F(1589, 2))  # 842 - top margin 40 - body size 7.5.
    scaled(paragraphs[1].marks, F(1557, 2))
    close(visible(paragraphs[1].marks)[1], F(74), 'reference-only paragraph reserved advance')
    label = next(node for node in root.descendants() if node.role == 'Lbl')
    body = next(node for node in root.descendants() if node.role == 'LBody')
    require(body.text == 'Scaled list.' and all(g[3] == 10 for m in label.marks for g in m.glyphs),
            'list label and body size distinction changed')
    scaled(body.marks, F(1525, 2))
    close(label.marks[0].glyphs[0][2], F(1525, 2), 'generated label affected body baseline')

    table = next(node for node in root.children if node.role == 'Table')
    headers = [node for node in table.descendants() if node.role == 'TH']
    cells = [node for node in table.descendants() if node.role == 'TD']
    require([node.text for node in headers] == ['Head ', 'Header 3 ', '3Tail'] and len(cells) == 120,
            'scaled table ownership or contents changed')

    def header_geometry(marks, baseline):
        require(''.join(mark.text for mark in marks) == 'Head Header 3 3Tail', 'repeated header text changed')
        require(len(marks) == 6, 'header piece boundaries changed')
        for mark in marks[:5]:
            scaled([mark], baseline)
        scaled(marks[5:], baseline - 13)
        close(visible(marks[:1])[1], F(146), 'end-aligned literal trailing space')
        prefix, value = marks[1:3]
        left, _ = visible([prefix])
        right = visible([value])[1]
        close((left + right) / 2, F(200), 'center-aligned mixed reference row')
        close(right - prefix.glyphs[0][1] - F(63, 2), F(24), 'aligned reference lost reserved advance')
        close(visible(marks[4:5])[1], F(278), 'header reference-only reserved advance')

    header_geometry([mark for header in headers for mark in header.marks], F(1493, 2))
    require(overrides(headers[2].marks) == '3 ', 'header authored break lost its logical separator')
    seen_rows = {0: 0, 1: 0}
    for index in range(40):
        end, center, reference = cells[index * 3:index * 3 + 3]
        require(end.text == 'word word word word word word ' and center.text == 'B ' and reference.text == '3',
                'scaled table body row text changed')
        require(len(end.marks) == 2 and len(center.marks) == len(reference.marks) == 1, 'scaled cell wrap changed')
        page = end.marks[0].page
        require(page in seen_rows and all(mark.page == page for cell in (end, center, reference) for mark in cell.marks),
                'scaled table row split across pages')
        row = seen_rows[page]
        baseline = (F(1433, 2) if page == 0 else F(1529, 2)) - row * 30
        scaled(end.marks[:1], baseline)
        scaled(end.marks[1:], baseline - 13)
        scaled(center.marks + reference.marks, baseline)
        for mark in end.marks:
            close(visible([mark])[1], F(146), 'wrapped end-aligned row included trailing literal space')
        left, right = visible(center.marks)
        close((left + right) / 2, F(200), 'center-aligned literal trailing space')
        close(visible(reference.marks)[1], F(278), 'reference-only cell baseline or reserved advance')
        seen_rows[page] += 1
    require(seen_rows == {0: 22, 1: 18}, 'scaled table continuation capacity changed')
    repeated = [paint(document, pages[page], page, -1, block)
                for page, _, block, _ in artifacts if FONT.search(block)]
    require(repeated and {mark.page for mark in repeated} == {1}, 'repeated header artifact page changed')
    require(all(b'/ActualText' not in mark.block for mark in repeated), 'artifact header acquired body semantic overrides')
    header_geometry(repeated, F(1589, 2))


def validate_destination_references_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    document, pages, root, artifacts = read(pdf)
    if dimensions.get('geometry', 0):
        validate_geometry(document, pages, root, artifacts, dimensions)
        return
    sections = dimensions['sections']
    styled = dimensions.get('styled', 0)
    ordered = dimensions.get('ordered', 0)
    headings = {node.text: node for node in root.descendants() if node.role == 'H1'}
    named = check_name_tree(document.bodies, document.root, pages)
    physical = {number: index for index, number in enumerate(pages)}
    names = ({b'start': 'Styled references', b'end': 'Styled target'} if styled else
             {b'start': 'Ordered references', b'end': 'Ordered target'} if ordered else {
        b'toc': 'Destination reference evidence', **{
            f'section-{index}'.encode(): f'Section {index}' for index in range(1, sections + 1)}})
    require(set(named) == set(names), 'named reference targets changed')
    target_pages = {}
    for name, title in names.items():
        node = headings[title]
        page, x, y = named[name]
        require(node.marks and {mark.page for mark in node.marks} == {physical[page]},
                'named destination page differs from its actual heading fragment')
        close(F(x.decode()), min(mark.bounds[0] for mark in node.marks), 'destination anchor x')
        close(F(y.decode()), max(mark.bounds[3] for mark in node.marks), 'destination anchor y')
        target_pages[name] = physical[page]
    expected_count = 2 if styled or ordered else sections + 1
    require(len(pages) == expected_count == dimensions['pages'], 'reference pages changed or an empty page was introduced')
    require(target_pages[next(iter(names))] == 0, 'reference front matter moved')
    for node in root.descendants():
        for mark in node.marks:
            require(mark.bounds[0] >= 50 - TOL and mark.bounds[2] <= 545 + TOL,
                    'reference paint escaped its declared body width')
    paragraphs = [node for node in root.children if node.role == 'P']
    if ordered:
        label = page_label(document, target_pages[b'end'])
        require(label == 'p中', 'ordered reference label rule changed')
        paragraph = paragraphs[0]
        require(paragraph.text == f'Ordered label {label}Physical 2.',
                'ordered mixed-face reference changed visible Unicode')
        links = [node for node in paragraph.descendants() if node.role == 'Link']
        require(len(links) == 1 and links[0].text == label,
                'mixed-face reference lost its single semantic link')
        link = links[0]
        selected = {FONT.search(mark.block)[1] for mark in link.marks}
        require(len(selected) == 2, 'mixed-script reference did not use both policy faces')
        for mark in link.marks:
            resource = FONT.search(mark.block)[1].decode()
            font = document.get(pages[mark.page])['Resources']['Font'][resource]
            base = str(document.get(int(font))['BaseFont'])
            require(('NotoSCCJKFixture' in base) == ('中' in mark.text),
                    'ordered reference selected the wrong registered script face')
        require(any(text_string(node.value.get('Lang', b'')) == 'zh-Hans'
                    for node in paragraph.descendants()), 'ordered reference lost language ownership')
        require(overrides(link.marks) == label + ' ',
                'mixed-face authored break duplicated or lost logical override pieces')
        prefix = paragraph.marks[0]
        close(max(mark.bounds[2] for mark in link.marks) - prefix.bounds[2], F(60),
              'ordered mixed-face reserved box advance')
        physical = paragraph.marks[-2]
        close(physical.glyphs[0][2], prefix.glyphs[0][2] - 13,
              'ordered reference mandatory break baseline')
        return
    if styled:
        label = page_label(document, target_pages[b'end'])
        require(paragraphs[0].text == f'Scaled label {label} ends here.', 'inherited-face reference value changed')
        emphasis = next(node for node in paragraphs[0].descendants() if node.role == 'Em')
        require(emphasis.text == label and emphasis.marks, 'reference lost emphasis ownership')
        require(any(text_string(node.value.get('Lang', b'')) == 'fr' for node in emphasis.descendants()),
                'reference lost its authored language')
        require(all(glyph[3] == F(15, 2) for mark in emphasis.marks for glyph in mark.glyphs), 'reference ignored its inherited scale')
        for mark in emphasis.marks:
            resource = FONT.search(mark.block)
            require(resource is not None, 'reference-only role has no selected font')
            font = document.get(pages[mark.page])['Resources']['Font'][resource[1].decode()]
            require('NotoMonoCodeFixture' in str(document.get(int(font)).get('BaseFont', '')),
                    'reference-only role did not select its inherited registered font')
        prefix, value, suffix = paragraphs[0].marks
        close(value.bounds[2] - prefix.bounds[2], F(60), 'scaled end-aligned box advance')
        close(suffix.bounds[0], value.bounds[2], 'text following scaled reserved field')
        return
    for index in range(1, sections + 1):
        target = target_pages[f'section-{index}'.encode()]
        require(target == index, 'section heading no longer starts on its declared physical page')
        expected = f'TOC {index}: {page_label(document, target)} / physical {target + 1}.'
        require(paragraphs[index - 1].text == expected, f'printed forward reference disagrees with target {index}')
    first = page_label(document, target_pages[b'section-1'])
    final_page = target_pages[f'section-{sections}'.encode()]
    final_label = page_label(document, final_page)
    only = paragraphs[sections]
    require(only.text == first + '1' and len(only.marks) == 2, 'reference-only explicit segments were dropped, padded or joined')
    close(only.marks[0].bounds[2], F(98), 'reference-only first reserved width')
    close(only.marks[1].bounds[2], F(74), 'reference-only second reserved width')
    close(only.marks[0].glyphs[0][2] - only.marks[1].glyphs[0][2], F(13), 'explicit break after reference')
    require(overrides(only.marks) == first + ' ', 'authored break lost its explicit logical separator')
    adjacent = paragraphs[sections + 1]
    require(adjacent.text == f'Adjacent 2{final_page + 1}.', 'adjacent reference atoms were padded or split')
    prefix, one, two, suffix = adjacent.marks
    close(one.bounds[2] - prefix.bounds[2], F(24), 'first adjacent field advance')
    close(two.bounds[2] - one.bounds[2], F(24), 'second adjacent field advance')
    close(suffix.bounds[0], two.bounds[2], 'text following adjacent field')
    all_paragraphs = [node.text for node in root.descendants() if node.role == 'P']
    require(f'List target {first}.' in all_paragraphs and f'Callout target {final_label}.' in all_paragraphs,
            'reference lost numbered-item or callout ownership')
    cells = [node for node in root.descendants() if node.role == 'TD']
    require(len(cells) == 2 and cells[0].text == first, 'reference-only table cell changed or became empty')
    for index in range(1, sections + 1):
        require(paragraphs[sections + 1 + index].text == f'Back to {page_label(document, 0)}; final {final_page + 1}.',
                'backward/shared-target reference disagrees with its committed destination')
    links = [node for node in root.descendants() if node.role == 'Link']
    require(len(links) == 2 * sections + 2, 'references unexpectedly created annotations or lost explicit links')
    for node in links:
        objects = [kid for kid in element_children(document, node.value) if isinstance(kid, dict) and kid.get('Type') == 'OBJR']
        require(len(objects) == 1, 'reference-only link lacks exactly one annotation owner')
        annotation = document.get(int(objects[0]['Obj']))
        action = annotation['A']
        page = physical[int(action['D'][0])]
        require(node.text == page_label(document, page), 'linked reference value and action target disagree')
        require(action['D'][2:] == action['SD'][2:], 'link layout and semantic destinations diverged')
        rectangle = annotation['Rect']
        require(rectangle[2] > rectangle[0] and rectangle[3] > rectangle[1], 'reference-only annotation has empty geometry')
        close(F(rectangle[0]), min(mark.bounds[0] for mark in node.marks), 'reference link left edge')
        close(F(rectangle[2]), max(mark.bounds[2] for mark in node.marks), 'reference link right edge')
        top = max(glyph[2] + glyph[3] for mark in node.marks for glyph in mark.glyphs)
        close(F(rectangle[3]), top, 'reference link top edge')
        close(F(rectangle[1]), top - 13, 'reference link bottom edge')
        require(annotation['QuadPoints'] == [rectangle[0], rectangle[3], rectangle[2], rectangle[3],
                                             rectangle[0], rectangle[1], rectangle[2], rectangle[1]],
                'reference link quad differs from its actual glyph line')
    footer = {}
    for page, kind, block, _ in artifacts:
        if FONT.search(block):
            footer.setdefault(page, []).append(paint(document, pages[page], page, -1, block).text)
    for page in range(len(pages)):
        require(''.join(footer.get(page, [])) == f'Label {page_label(document, page)} | {page + 1}',
                'visible page-label furniture differs from semantic reference numbering')


def mutation_checks(pdf: bytes, dimensions: dict[str, int]) -> None:
    document, pages, root, _ = read(pdf)
    labels = int(document.get(document.root)['PageLabels'])
    original_rule = document.bodies[labels]
    changed_rule = original_rule.replace(b'/St 27', b'/St 28')
    require(changed_rule != original_rule, 'reference mutation has no alphabetic label start')
    paragraphs = [node for node in root.children if node.role == 'P']
    adjacent = paragraphs[dimensions['sections'] + 1].marks[1]
    shifted = ORIGIN.sub(lambda match: b'1 0 0 1 ' + str(float(F(match[1].decode()) + 3)).encode() + b' ' + match[2] + b' cm', adjacent.block, count=1)
    require(shifted != adjacent.block, 'reference mutation has no field origin')
    only = paragraphs[dimensions['sections']]
    old_override = only.marks[0].block
    new_override = re.sub(rb'/ActualText <[0-9A-Fa-f]+> ?', b'', old_override, count=1)
    require(new_override != old_override, 'reference mutation has no explicit break separator')
    for name, old, new in [('page labels', original_rule, changed_rule), ('fixed advance', adjacent.block, shifted), ('logical separator', old_override, new_override)]:
        mutant = twin(pdf, old, new, exactly_once=True)
        try:
            validate_destination_references_pdf(mutant, dimensions)
        except ValidationError:
            continue
        raise ValidationError(f'reference oracle accepted mutated {name}')


def geometry_mutations(pdf: bytes, dimensions: dict[str, int]) -> None:
    _, _, root, artifacts = read(pdf)
    first = next(node for node in root.children if node.role == 'P').marks[0]
    cells = [node for node in root.descendants() if node.role == 'TD']
    headers = [node for node in root.descendants() if node.role == 'TH']
    repeated = next(block for _, _, block, _ in artifacts if FONT.search(block))
    cases = [('scaled baseline', first.block, 0, 1),
             ('wrapped end alignment', cells[0].marks[0].block, -1, 0),
             ('center reference advance', headers[1].marks[1].block, 2, 0),
             ('repeated header alignment', repeated, -1, 0)]
    for name, old, dx, dy in cases:
        new = ORIGIN.sub(lambda match: b'1 0 0 1 ' + str(float(F(match[1].decode()) + dx)).encode()
                         + b' ' + str(float(F(match[2].decode()) + dy)).encode() + b' cm', old)
        require(new != old, f'geometry mutation has no origin for {name}')
        mutant = twin(pdf, old, new, exactly_once=True)
        try:
            validate_destination_references_pdf(mutant, dimensions)
        except ValidationError:
            continue
        raise ValidationError(f'reference oracle accepted mutated {name}')


def registered_cases():
    return [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases']
            if 'destination_references' in case['validators']]


def self_test() -> None:
    for case in registered_cases():
        pdf = (ROOT / case['snapshot']).read_bytes()
        validate_destination_references_pdf(pdf, case['dimensions'])
        if case['dimensions'].get('geometry', 0):
            geometry_mutations(pdf, case['dimensions'])
        elif case['dimensions']['sections'] == 2 and not case['dimensions'].get('styled', 0):
            mutation_checks(pdf, case['dimensions'])
    print('PASS destination reference values, targets, geometry, ownership and seven mutation twins')


def reader_check(mutool: Path | None) -> None:
    output = ROOT / '.roc-pdf-tmp/destination-reference-readers'
    classes = output / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    jar = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'
    def run(command: list[str]) -> bytes:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        require(result.returncode == 0 and not result.stderr.strip(),
                f'reference reader failed: {result.stderr.decode(errors="replace")}')
        return result.stdout
    run(['javac', '-cp', str(jar), '-d', str(classes), str(ROOT / 'scripts/PdfBoxPages.java')])
    total = 0
    for case in registered_cases():
        path = ROOT / case['snapshot']
        pdf = path.read_bytes()
        validate_destination_references_pdf(pdf, case['dimensions'])
        document, pages, _, _ = read(pdf)
        expected = []
        for page_index, page in enumerate(pages):
            stream = document.stream(int(document.get(page)['Contents']))
            pieces = [(match.start(), match[2]) for match in MARKED.finditer(stream)]
            pieces += [(match.start(), match[2]) for match in ARTIFACT.finditer(stream) if b' Tf' in match[2]]
            expected.append(''.join(paint(document, page, page_index, -1, block).text for _, block in sorted(pieces)))
        box = output / path.stem / 'pdfbox'
        count = int(run(['java', '-Djava.awt.headless=true', '-cp', f'{classes}{os.pathsep}{jar}',
                         'PdfBoxPages', str(path), str(box)]))
        require(count == len(pages), 'PDFBox reference page count changed')
        extracted = ''.join((box / f'page-{page:04d}.txt').read_text() for page in range(1, count+1))
        require(''.join(extracted.split()) == ''.join(''.join(expected).split()),
                'PDFBox reference whole-file extraction changed text/order')
        engines = [('PDFBox 3.0.8', [box / f'page-{page:04d}.ppm' for page in range(1, count+1)])]
        if mutool is not None:
            mupdf = output / path.stem / 'mupdf'
            mupdf.mkdir(exist_ok=True)
            run([str(mutool), 'draw', '-q', '-r', '72', '-c', 'rgb', '-o', str(mupdf / 'page-%d.ppm'), str(path)])
            extracted = run([str(mutool), 'draw', '-q', '-F', 'txt', '-O', 'ignore-actualtext', '-o', '-', str(path)]).decode()
            require(''.join(extracted.split()) == ''.join(''.join(expected).split()),
                    'MuPDF reference glyph/ToUnicode extraction changed text/order')
            engines.append(('MuPDF 1.28.2', [mupdf / f'page-{page}.ppm' for page in range(1, count+1)]))
        for engine, images in engines:
            for image in images:
                raster = read_ppm(image)
                require((raster.width, raster.height) == (595, 842) and min(raster.pixels) < 100,
                        f'{engine} lost reference page geometry/ink')
                total += 1
    print(f'PASS destination-reference whole-file extraction/rendering: {total} page renders')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--readers', action='store_true')
    parser.add_argument('--mutool', type=Path)
    args = parser.parse_args()
    require(args.self_test or args.readers, 'use --self-test or --readers; cases come from tests/spec.json')
    if args.self_test:
        self_test()
    if args.readers:
        reader_check(args.mutool)


if __name__ == '__main__':
    try:
        main()
    except (ValidationError, ValueError) as error:
        raise SystemExit(f'FAIL {error}') from error
