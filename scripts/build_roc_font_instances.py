#!/usr/bin/env python3
"""Materialize the pinned roc-font sans/mono instances; never a runtime dependency."""
import argparse
import hashlib
import json
import tempfile
from pathlib import Path

import fontTools
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'vendor/fonts/roc-font'
OUTPUT = ROOT / 'package/fonts'
INSTANCES = (
    ('Inter-Variable.ttf', 'Inter-Regular.ttf', {'opsz': 14, 'wght': 400}),
    ('Inter-Variable.ttf', 'Inter-Bold.ttf', {'opsz': 14, 'wght': 700}),
    ('FiraCode-Variable.ttf', 'FiraCode-Regular.ttf', {'wght': 400}),
)


def build(destination):
    if fontTools.__version__ != '4.61.1':
        raise SystemExit('Requires fontTools 4.61.1')
    pins = json.loads((SOURCE / 'upstream-pins.json').read_text())
    for source, output, axes in INSTANCES:
        pin = next(p for p in pins['faces'] if Path(p['file']).name == source)
        data = (SOURCE / source).read_bytes()
        assert hashlib.sha256(data).hexdigest() == pin['sha256'], source
        license_name = Path(pin['licence']['file']).name
        license_data = (SOURCE / license_name).read_bytes()
        assert hashlib.sha256(license_data).hexdigest() == pin['licence']['sha256'], license_name
        assert (OUTPUT / license_name).read_bytes() == license_data, license_name
        font = TTFont(SOURCE / source, recalcTimestamp=False)
        font = instantiateVariableFont(font, axes, inplace=True, updateFontNames=True)
        assert 'fvar' not in font and 'gvar' not in font and 'HVAR' not in font
        assert 0x2318 in font.getBestCmap()
        font.save(destination / output, reorderTables=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory)
            build(candidate)
            for _, name, _ in INSTANCES:
                assert (candidate / name).read_bytes() == (OUTPUT / name).read_bytes(), name
        print('PASS deterministic roc-font static instances')
    else:
        build(OUTPUT)
