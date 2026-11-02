#!/usr/bin/env python3
"""Verify or install unchanged static faces from the pinned roc-font release.

The historical rc3 instancing recipe is retained beside its original pins in
vendor/fonts/roc-font/. Current defaults require no fontTools transformation.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINS = ROOT / "vendor/fonts/roc-font/upstream-pins.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify retained files without changing them (the default).')
    parser.add_argument('--bundle', type=Path, help='Also compare each file with this published rc4 bundle.')
    parser.add_argument('--install', action='store_true', help='Install exact files from --bundle after validating it.')
    args = parser.parse_args()
    if args.install and args.bundle is None:
        parser.error('--install requires --bundle')
    pins = json.loads(PINS.read_text())
    if args.bundle is not None:
        payload = args.bundle.read_bytes()
        release = pins['roc_font_release']
        assert len(payload) == release['size'], 'release bundle size'
        assert hashlib.sha256(payload).hexdigest() == release['sha256'], 'release bundle digest'
    entries = {entry['file']: entry for face in pins['faces'] for entry in (face, face['licence'])}
    for name, pin in entries.items():
        target = ROOT / name
        if args.bundle is not None:
            data = subprocess.check_output(['tar', '--zstd', '-xOf', str(args.bundle), name.removeprefix('package/')])
            assert len(data) == pin['size'] and hashlib.sha256(data).hexdigest() == pin['sha256'], name
            if args.install:
                target.write_bytes(data)
            else:
                assert target.read_bytes() == data, name
        data = target.read_bytes()
        assert len(data) == pin['size'] and hashlib.sha256(data).hexdigest() == pin['sha256'], name
    actual = {str(path.relative_to(ROOT)) for path in (ROOT / 'package/fonts').iterdir() if path.is_file()}
    assert actual == set(entries), 'unmanifested package font files'
    print('PASS ten unchanged roc-font rc4 static faces and three family licences')


if __name__ == '__main__':
    main()
