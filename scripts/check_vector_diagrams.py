#!/usr/bin/env python3
"""Offline evidence for the public prepared-vector example (no Node/browser)."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

from check_drawing_labels import artifact_and_tagged_text
from check_pdf_structure import ValidationError, require
from check_structure_semantics import Document, page_order, text_string
from check_visual_renderers import Raster, read_ppm

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / 'examples/vector-diagrams'
PREPARATION = EXAMPLE / 'preparation'
SNAPSHOT = ROOT / 'tests/vector_diagrams/diagrams_1.pdf'
LABELS = ('Café', 'Receive order', 'Check stock', 'Order timber', 'Dispatch')
ALT = 'Café: receive an order, check stock or order timber, then dispatch.'


def validate_vector_diagrams_pdf(pdf: bytes, dimensions: dict[str, int]) -> None:
    count = dimensions['diagrams']
    artifacts, tagged = artifact_and_tagged_text(pdf)
    require(Counter(artifacts) == Counter({label: count for label in LABELS}), 'exact Unicode label multiplicity changed')
    require(not set(LABELS).intersection(tagged), 'figure labels leaked into logical reading order')
    require(tagged.count('Order processing') == count, 'visible caption multiplicity changed')
    document = Document(pdf)
    figures = [document.get(number) for number in document.bodies if isinstance(document.get(number), dict) and document.get(number).get('S') == 'Figure']
    require(len(figures) == count and all(text_string(figure['Alt']) == ALT for figure in figures), 'Figure Alt ownership changed')
    pages: list[int] = []
    page_order(document, int(document.get(document.root)['Pages']), pages)
    for page in pages:
        value = document.get(page)
        require(not value.get('Resources', {}).get('XObject'), 'prepared vector was replaced with a raster or private form')
        content = document.stream(int(value['Contents']))
        require(b' c\n' in content and b' l\n' in content, 'cubic connectors or arrowhead geometry missing')


def check_provenance() -> None:
    provenance = json.loads((PREPARATION / 'provenance.json').read_text())
    require(provenance['browser'] == 'Chrome/155.0.8059.79' and provenance['node'] == 'v23.9.0', 'preparation toolchain changed without review')
    for name, digest in provenance['inputs'].items():
        require(hashlib.sha256((PREPARATION / name).read_bytes()).hexdigest() == digest, f'prepared diagram input changed: {name}')
    require(hashlib.sha256((EXAMPLE / 'fonts/Inter-Regular.ttf').read_bytes()).hexdigest() == provenance['font_sha256'], 'preparation and Roc fonts differ')
    resolved = json.loads((PREPARATION / 'resolved.json').read_text())
    require(tuple(label['text'] for label in resolved['labels']) == LABELS, 'prepared label sources changed')
    require(len(resolved['paths']) == 12 and any(segment[0] == 'C' for path in resolved['paths'] for segment in path['segments']), 'prepared paths changed')
    source = (PREPARATION / 'diagram.svg').read_text()
    require('foreignObject' not in source and 'viewBox="-20 -16 ' in source, 'accepted SVG lost its bounded label/viewBox profile')
    original = ROOT / 'tests/vector_diagrams/html-labels.svg'
    require('foreignObject' in original.read_text(), 'original HTML rejection witness changed')
    original_provenance=json.loads((original.parent/'source-provenance.json').read_text())
    require(hashlib.sha256(original.read_bytes()).hexdigest()==original_provenance['sha256'], 'original HTML rejection witness digest changed')


def read_png(path: Path) -> Raster:
    """Decode only the pinned browser's eight-bit RGB/RGBA PNG oracle."""
    data = path.read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG signature')
    offset, compressed, width, height, channels = 8, bytearray(), 0, 0, 0
    while offset < len(data):
        size = int.from_bytes(data[offset:offset+4], 'big')
        kind, payload = data[offset+4:offset+8], data[offset+8:offset+8+size]
        require(zlib.crc32(kind+payload) == int.from_bytes(data[offset+8+size:offset+12+size], 'big'), 'PNG CRC')
        if kind == b'IHDR':
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            require(depth == 8 and color in (2, 6) and compression == filtering == interlace == 0, 'unsupported oracle PNG')
            channels = 3 if color == 2 else 4
        if kind == b'IDAT': compressed.extend(payload)
        offset += size + 12
    raw = zlib.decompress(compressed)
    stride, previous, rgb = width*channels, bytearray(width*channels), bytearray()
    require(len(raw) == height*(stride+1), 'PNG row sizes')
    for y in range(height):
        start = y*(stride+1)
        kind = raw[start]
        row = bytearray(raw[start+1:start+1+stride])
        require(kind < 5, 'PNG row filter')
        for x in range(stride):
            left, up, corner = (row[x-channels] if x >= channels else 0), previous[x], (previous[x-channels] if x >= channels else 0)
            prediction = left + up - corner
            distances = (abs(prediction-left), abs(prediction-up), abs(prediction-corner))
            paeth = (left, up, corner)[distances.index(min(distances))]
            row[x] = (row[x] + (0, left, up, (left+up)//2, paeth)[kind]) % 256
        for x in range(0, stride, channels):
            require(channels == 3 or row[x+3] == 255, 'PNG oracle is not opaque')
            rgb.extend(row[x:x+3])
        previous = row
    return Raster(width, height, bytes(rgb))


def compare_render() -> None:
    reference = read_png(PREPARATION / 'reference.png')
    with tempfile.TemporaryDirectory(prefix='vector-render-') as name:
        temporary = Path(name)
        jar = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'
        subprocess.run(['javac', '-Xlint:all', '-Werror', '-encoding', 'UTF-8', '-cp', str(jar), '-d', str(temporary), str(ROOT/'scripts/PdfBoxRender.java')], check=True, capture_output=True)
        output = temporary / 'pdfbox.ppm'
        subprocess.run(['java', '-Djava.awt.headless=true', '-cp', f'{temporary}{os.pathsep}{jar}', 'PdfBoxRender', str(SNAPSHOT), str(output), '96'], check=True, capture_output=True)
        rendered = read_ppm(output)
    # The public example's declared 24 pt margins are 32 px at 96 dpi.
    pixels = bytearray()
    for y in range(reference.height):
        start = ((y+32)*rendered.width+32)*3
        pixels.extend(rendered.pixels[start:start+reference.width*3])
    require(len(pixels) == len(reference.pixels), 'render crop dimensions')
    # Compare visible dark ink with one pixel of antialiasing tolerance.
    def ink(data: bytes) -> set[tuple[int, int]]:
        return {(i//3 % reference.width, i//3 // reference.width) for i in range(0,len(data),3) if min(data[i:i+3]) < 180}
    expected, actual = ink(reference.pixels), ink(pixels)
    def missing(left, right):
        return sum(not any((x+dx,y+dy) in right for dx in (-1,0,1) for dy in (-1,0,1)) for x,y in left)
    lost, extra = missing(expected, actual), missing(actual, expected)
    require(lost <= 60 and extra <= 60, f'Chrome SVG/PDFBox vector render mismatch: {lost} missing, {extra} extra dark pixels')
    expected_ink = sum(255-min(reference.pixels[i:i+3]) for i in range(0,len(reference.pixels),3))
    actual_ink = sum(255-min(pixels[i:i+3]) for i in range(0,len(pixels),3))
    require(abs(expected_ink-actual_ink)*10 <= expected_ink, f'Chrome/PDFBox integrated ink changed: {expected_ink} vs {actual_ink}')


def self_test() -> None:
    check_provenance()
    validate_vector_diagrams_pdf(SNAPSHOT.read_bytes(), {'diagrams': 1})
    try:
        validate_vector_diagrams_pdf(SNAPSHOT.read_bytes(), {'diagrams': 2})
    except ValidationError:
        pass
    else:
        raise AssertionError('vector checker accepted missing diagrams')
    compare_render()
    print('PASS prepared vector source provenance, exact Unicode/ownership and independent Chrome/PDFBox rendering')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.parse_args()
    self_test()
