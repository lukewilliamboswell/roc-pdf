#!/usr/bin/env python3
"""Synthesise the JPEG seed corpus the bounded JPEG inspector fuzz target needs.

Raw byte mutation practically never assembles a stream that clears the
inspector's SOI/SOF/DQT/DHT/SOS/EOI gates, so without seeds the fuzz target only
ever exercises the reject path and every invariant behind an accepted plan is
dead code. These seeds are minimal solid-colour images chosen to cover the
segment shapes the inspector treats differently: baseline and progressive
frames, greyscale and three-component frames, each chroma subsampling mode, a
COM segment that must be stripped, all eight EXIF orientations, and degenerate
one-pixel-tall and one-pixel-wide frames.

Regeneration only. This script needs Pillow, CI never runs it, and the corpus it
writes is committed and pinned by digest in assets/provenance.json.
"""
from __future__ import annotations

import argparse
import hashlib
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "tests" / "assets" / "jpeg-fuzz-corpus"

# Solid fills keep the entropy-coded scan short and, more importantly, keep the
# encoder's output a pure function of the size and encoder options below.
RGB_FILL = (198, 74, 32)
GRAY_FILL = 137
EXIF_ORIENTATION_TAG = 0x0112


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_jpeg(directory: Path, name: str, mode: str, size: tuple[int, int], **options: object) -> Path:
    fill = GRAY_FILL if mode == "L" else RGB_FILL
    image = Image.new(mode, size, fill)
    target = directory / name
    image.save(target, format="JPEG", **options)
    return target


def build(directory: Path) -> list[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    written = [
        write_jpeg(directory, "gray-16x16.jpg", "L", (16, 16), quality=80),
        write_jpeg(directory, "rgb-8x8.jpg", "RGB", (8, 8), quality=90),
        write_jpeg(directory, "rgb-64x32.jpg", "RGB", (64, 32), quality=50),
        write_jpeg(directory, "rgb-progressive-32x32.jpg", "RGB", (32, 32), quality=70, progressive=True),
        write_jpeg(directory, "rgb-subsampling-0.jpg", "RGB", (24, 24), quality=95, subsampling=0),
        write_jpeg(directory, "rgb-subsampling-2.jpg", "RGB", (24, 24), quality=95, subsampling=2),
        write_jpeg(directory, "rgb-comment.jpg", "RGB", (16, 16), quality=80, comment=b"roc-pdf fuzz seed comment"),
    ]
    for orientation in range(1, 9):
        # One seed per EXIF orientation: the inspector resolves orientation
        # before placement, so each value reaches a different branch of the
        # orientation policy and each APP1 segment must still be stripped.
        exif = Image.Exif()
        exif[EXIF_ORIENTATION_TAG] = orientation
        written.append(
            write_jpeg(
                directory,
                f"rgb-exif-orientation-{orientation}.jpg",
                "RGB",
                (20, 12),
                quality=85,
                exif=exif,
            )
        )
    written.append(write_jpeg(directory, "wide-256x1.jpg", "RGB", (256, 1), quality=60))
    written.append(write_jpeg(directory, "tall-1x256.jpg", "RGB", (1, 256), quality=60))
    return sorted(written)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory(prefix="roc-pdf-jpeg-corpus-") as directory:
            for candidate in build(Path(directory)):
                committed = OUTPUT / candidate.name
                if not committed.exists() or committed.read_bytes() != candidate.read_bytes():
                    raise SystemExit(f"{committed} is not a deterministic generated JPEG seed")
        print(f"PASS JPEG fuzz corpus ({len(list(OUTPUT.glob('*.jpg')))} seeds)")
    else:
        for written in build(OUTPUT):
            print(f"Wrote {written.relative_to(ROOT)} ({written.stat().st_size} bytes, sha256={sha256(written)})")


if __name__ == "__main__":
    main()
