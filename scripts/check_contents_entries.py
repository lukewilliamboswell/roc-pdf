#!/usr/bin/env python3
"""Inspect contents columns, links, source order and decorative leaders in bytes."""
from __future__ import annotations

import argparse
from fractions import Fraction as F
import json
from pathlib import Path
import re

from check_navigation import check_name_tree
from check_pdf_structure import ValidationError, require
from check_rich_flow import ORIGIN, read
from check_structure_semantics import element_children
from pdf_layout import twin

ROOT = Path(__file__).resolve().parents[1]
RECT = re.compile(rb'(-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) re')


def title(index: int, tall: bool) -> str:
    if tall:
        return ' '.join(['continuing title'] * 700)
    if index % 3 == 1:
        return 'WrappedMarker ' + ' '.join(['wrapping title'] * 18)
    return f'Café overview {index}'


def validate_contents_entries_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    document, pages, root, artifacts = read(pdf)
    entries = dimensions['entries']
    tall = bool(dimensions.get('tall', 0))
    require(len(pages) == dimensions['pages'], 'contents pagination changed')
    named = check_name_tree(document.bodies, document.root, pages)
    require(set(named) == {b'target'}, 'contents destination identity changed')
    target_page = pages.index(named[b'target'][0])
    lists = [node for node in root.children if node.role == 'TOC']
    require(len(lists) == 1, 'consecutive entries did not form one TOC')
    items = lists[0].children
    require(len(items) == entries and all(node.role == 'TOCI' for node in items),
            'each authored entry must have one TOCI in logical order')
    require(all(len(node.children) == 1 and node.children[0].role == 'P' for node in items),
            'contents entries lost paragraph ownership')
    paragraphs = [node.children[0] for node in items]
    structure_target = next(node.number for node in root.children if node.role == 'H1')
    for item in items:
        require(item.value.get('Ref') == [structure_target], 'contents item points to the wrong structure element')
    require(not any(node.role in ('L', 'Lbl', 'Table') for node in root.descendants()),
            'contents entries were replaced by bullet or table semantics')
    for index, node in enumerate(paragraphs):
        label = title(index, tall)
        require(node.text == label + ' ' + str(target_page + 1), 'contents source text changed or gained leader dots')
        links = [child for child in node.children if child.role == 'Link']
        require(len(links) == 2 and links[0].text == label and links[1].text == str(target_page + 1),
                'contents title and page field need independent links in source order')
        first, number = links
        require(all(abs(mark.bounds[2] - F(545)) <= F(1, 2) for mark in number.marks),
                'contents page numbers do not share the content right edge')
        inset = F(50 + (index % 3) * 18)
        require(abs(first.marks[0].bounds[0] - inset) <= F(1, 50), 'contents indentation changed')
        rows = {}
        for mark in first.marks:
            rows.setdefault((mark.page, mark.glyphs[0][2]), []).append(mark)
            require(mark.bounds[2] <= F(507) + F(1, 50), 'contents title invaded reserved page field')
        require(all(abs(min(mark.bounds[0] for mark in marks) - inset) <= F(1, 50)
                    for marks in rows.values()), 'wrapped contents title lost hanging indentation')
        require((number.marks[-1].page, number.marks[-1].glyphs[0][2]) ==
                (first.marks[-1].page, first.marks[-1].glyphs[0][2]),
                'page reference is not beside the final title line')
        for link in links:
            objects = [kid for kid in element_children(document, link.value)
                       if isinstance(kid, dict) and kid.get('Type') == 'OBJR']
            require(len(objects) == len({mark.page for mark in link.marks}),
                    'continued contents link lost page annotation ownership')
            for kid in objects:
                annotation = document.get(int(kid['Obj']))
                action = annotation['A']
                require(int(action['D'][0]) == pages[target_page], 'contents link targets the wrong page')
                require(int(action['SD'][0]) == structure_target, 'contents link and item Ref name different structure elements')
        if tall:
            require(len({mark.page for mark in first.marks}) > 1, 'tall entry did not continue across pages')
    dots = []
    for page, _kind, block, _ in artifacts:
        require(b' Tf' not in block and b'/ActualText' not in block, 'leader decoration became text')
        for raw in RECT.findall(block):
            x, y, width, height = map(lambda value: F(value.decode()), raw)
            require(width == height == F(3, 5), 'leader dot dimensions changed')
            dots.append((page, x, y))
    if entries > 1:
        require(dots, 'subsection contents lost decorative leaders')
        for page, x, y in dots:
            owners = [node for index, node in enumerate(paragraphs) if index % 3 != 0
                      and node.marks[-1].page == page
                      and abs(node.marks[-1].glyphs[0][2] + F(3, 5) - y) <= F(1, 50)]
            require(len(owners) == 1, 'leader does not belong to exactly one final title line')
            first, number = [child for child in owners[0].children if child.role == 'Link']
            require(x >= first.marks[-1].bounds[2] + 2 and x + F(3, 5) <= 510,
                    'leader collides with its title or number column')
    else:
        require(not dots, 'chapter-only entry unexpectedly has leaders')


def registered():
    return [case for case in json.loads((ROOT / 'tests/spec.json').read_text())['cases']
            if 'contents_entries' in case['validators']]


def self_test() -> None:
    for case in registered():
        pdf = (ROOT / case['snapshot']).read_bytes()
        validate_contents_entries_pdf(pdf, case['dimensions'])
        _, _, root, _ = read(pdf)
        first_item = next(node for node in root.children if node.role == 'TOC').children[0]
        number = first_item.children[0].children[-1].marks[-1]
        moved = ORIGIN.sub(lambda match: b'1 0 0 1 ' + str(float(F(match[1].decode()) - 2)).encode()
                           + b' ' + match[2] + b' cm', number.block, count=1)
        require(moved != number.block, 'number-column mutation changed no origin')
        try:
            validate_contents_entries_pdf(twin(pdf, number.block, moved), case['dimensions'])
        except ValidationError:
            pass
        else:
            raise ValidationError('contents oracle accepted a displaced page-number column')
        actual_target, = first_item.value['Ref']
        ref_entry = f'/Ref [{actual_target} 0 R]'.encode()
        wrong_target = first_item.children[0].number
        mutations = (
            ('missing Ref', b'/Ree' + ref_entry[4:]),
            ('Ref to another valid structure element', f'/Ref [{wrong_target} 0 R]'.encode()),
        )
        for name, replacement in mutations:
            mutated = twin(pdf, ref_entry, replacement, exactly_once=False)
            try:
                validate_contents_entries_pdf(mutated, case['dimensions'])
            except ValidationError as error:
                require('wrong structure element' in str(error), f'{name} control failed for a different reason')
            else:
                raise ValidationError(f'contents oracle accepted {name}')
    print('PASS contents alignment, wrapping, references, link ownership, artifact leaders and mutation twins')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true', required=True)
    parser.parse_args()
    try:
        self_test()
    except (ValidationError, ValueError) as error:
        raise SystemExit(f'FAIL {error}') from error
