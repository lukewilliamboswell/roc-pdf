#!/usr/bin/env python3
"""Independent extraction and rendering of the roc-font facade regression."""
import subprocess
import tempfile
from pathlib import Path

from check_visual_renderers import read_ppm

ROOT = Path(__file__).resolve().parents[1]
PDF = ROOT / 'tests/caller_font_facade/roc_fonts.pdf'
JAR = ROOT / 'vendor/pdfbox/pdfbox-app-3.0.8.jar'


def main():
    expected = ['Body ⌘K', 'Inline ⌘K Bold', 'Source ⌘K']
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        subprocess.run(['javac', '-cp', str(JAR), '-d', str(temp),
                        str(ROOT / 'scripts/PdfBoxTextExtract.java'),
                        str(ROOT / 'scripts/PdfBoxRender.java')], check=True)
        text = subprocess.check_output(['java', '-cp', f'{temp}:{JAR}', 'PdfBoxTextExtract', str(PDF)], text=True)
        assert text.splitlines() == expected, repr(text)
        poppler = subprocess.check_output(['pdftotext', '-layout', str(PDF), '-'], text=True)
        assert [line.strip() for line in poppler.splitlines() if line.strip()] == expected, repr(poppler)
        image = temp / 'render.ppm'
        subprocess.run(['java', '-Djava.awt.headless=true', '-cp', f'{temp}:{JAR}', 'PdfBoxRender', str(PDF), str(image), '72'], check=True)
        raster = read_ppm(image)
        assert raster.width > 500 and raster.height > 700
        # Every text row must paint visible glyphs; the source row includes padding.
        rows = []
        for y in range(raster.height):
            row = raster.pixels[y*raster.width*3:(y+1)*raster.width*3]
            if any(value < 200 for value in row):
                if not rows or y > rows[-1][-1] + 1:
                    rows.append([y])
                else:
                    rows[-1].append(y)
        assert len(rows) == 3, rows
        assert all(len(row) >= 6 for row in rows), rows
    print('PASS roc-font exact Unicode extraction and three visible text rows')


if __name__ == '__main__':
    main()
