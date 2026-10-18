#!/usr/bin/env python3
"""Inspect committed chapter boundaries, running artifacts and body frames."""
from __future__ import annotations

import argparse
import re
from fractions import Fraction
from pathlib import Path

from check_pdf_structure import ValidationError, require
from check_rich_inline import page_marked_text
from check_source_blocks import widths
from check_structure_semantics import Document, Ref, element_children, furniture_by_page, page_order
from text_positions import glyph_positions

ROOT = Path(__file__).resolve().parents[1]
MARKED = re.compile(rb'/[A-Za-z0-9]+ <</MCID [0-9]+>> BDC\n(.*?)EMC\n', re.S)


def inspect(pdf: bytes, chapters: int, mode: int) -> None:
    document = Document(pdf)
    catalog = document.get(document.root)
    pages: list[int] = []
    page_order(document, int(catalog['Pages']), pages)
    page_indices = {page: index for index, page in enumerate(pages)}
    marked = {(page, mcid): text for page in pages for mcid, text in page_marked_text(document, page)}
    headings: list[tuple[str, int]] = []
    logical: list[str] = []

    def walk(number: int) -> None:
        element = document.get(number)
        own: list[str] = []
        own_pages: list[int] = []
        for child in element_children(document, element):
            if isinstance(child, Ref):
                walk(int(child))
            elif isinstance(child, dict) and child.get('Type') == 'MCR':
                key = (int(child['Pg']), int(child['MCID']))
                own.append(marked[key])
                own_pages.append(page_indices[key[0]])
        if own:
            text = ''.join(own)
            logical.append(text)
            if element['S'] == 'H1':
                headings.append((text, min(own_pages)))

    walk(int(document.get(int(catalog['StructTreeRoot']))['K']))
    require([text for text, _page in headings] == [f'Chapter {n}' for n in range(1, chapters + 1)], 'chapter headings were lost, repeated or reordered')
    ending = [page_indices[page] for (page, _mcid), text in marked.items() if text.startswith('Unscoped ending')]
    require(len(ending) == 1, 'unscoped ending was lost or duplicated')
    end_page = ending[0]
    expected: dict[int, tuple[int, bool]] = {}
    for index, (_text, start) in enumerate(headings):
        end = headings[index + 1][1] if index + 1 < chapters else end_page
        require(end > start + 1, 'chapter continuation was not exercised')
        for page in range(start, end):
            expected[page] = (index + 1, page == start)
    require(headings[0][1] == (0 if mode == 1 else 1), 'scope entry did not start on the expected fresh body page')
    require(end_page == len(pages) - 1, 'scope exit introduced a blank page')
    furniture = furniture_by_page(document, pages)
    for index, page in enumerate(pages):
        bodies = page_marked_text(document, page)
        require(bodies, 'scope produced a furniture-only/blank page')
        headers = ''.join(text for kind, _body, text in furniture[index] if kind == 'Header')
        context = expected.get(index)
        chapter, opening = context if context is not None else (0, False)
        expected_label = f'Chapter {chapter} · Café' if context is not None and not opening and mode != 2 else ''
        require(headers == expected_label, f'page {index + 1}: running label {headers!r} differs from {expected_label!r}')
        numbers = ''.join(text for kind, _body, text in furniture[index] if kind == 'PageNum')
        expected_number = f'Page {index + 1} of {len(pages)}' if context is not None or mode != 1 else ''
        require(numbers == expected_number, f'page {index + 1}: global page fields differ')
        fonts = document.get(page)['Resources']['Font']
        advances = {name.encode(): widths(document, int(ref)) for name, ref in fonts.items()}
        content = document.stream(int(document.get(page)['Contents']))
        upper = 794000 if context is not None and opening else 740000 if context is not None else 794000
        for body in MARKED.findall(content):
            origin = re.search(rb'1 0 0 1 (-?[0-9.]+) (-?[0-9.]+) cm', body)
            require(origin is not None, 'body text lacks its explicit page translation')
            dx, dy = (Fraction(value.decode()) * 1000 for value in origin.groups())
            for _font, _cid, local_x, local_y in glyph_positions(body, advances):
                x, y = local_x + dx, local_y + dy
                require(56000 <= x <= 539000 and 76000 <= y <= upper, f'page {index + 1}: body glyph escaped selected frame')
    joined = ''.join(logical)
    for chapter in range(1, chapters + 1):
        for paragraph in range(1, 21):
            require(joined.count(f'Chapter {chapter} paragraph {paragraph}.') == 1, 'body content was duplicated or omitted')
    require(joined.count('Semantic document lead') == (0 if mode == 1 else 1), 'first-page lead changed ownership')


def validate_chapter_templates_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    inspect(pdf, dimensions['chapters'], dimensions['chapter_mode'])


def self_test() -> None:
    from pdf_layout import twin
    for name, count, mode in [('chapters_2', 2, 0), ('chapters_20', 20, 0), ('chapters_no_templates', 1, 1), ('chapters_reset', 1, 2)]:
        data = (ROOT / 'tests/page_templates' / f'{name}.pdf').read_bytes()
        inspect(data, count, mode)
        if mode != 2:
            damaged = twin(data, b'/Subtype /Header', b'/Subtype /Footer', exactly_once=False)
            try:
                inspect(damaged, count, mode)
            except ValidationError:
                pass
            else:
                raise ValidationError('chapter checker accepted a misplaced running-label twin')
    print('PASS chapter scope boundary, artifact, frame and mutation checks')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
