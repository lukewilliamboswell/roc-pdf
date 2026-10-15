#!/usr/bin/env python3
"""Generate the business report's Figure 2 photograph.

A deterministic, fictional "photograph" of oak boards air-drying under an
open shed, drawn with Pillow and written as a baseline sRGB JPEG with no
EXIF or ICC segments (the report places it with
``Image.Source.jpeg_srgb(..., RequireDisplayReady)``). The output is
committed at ``examples/business-report/drying-yard.jpg``; rerunning this
script with the pinned Pillow version reproduces it, and
``assets/provenance.json`` records its length and digest.
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "examples" / "business-report" / "drying-yard.jpg"
WIDTH, HEIGHT = 966, 520


def main() -> None:
    rng = random.Random(20261012)
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    # Overcast sky fading to the horizon.
    for y in range(HEIGHT):
        t = y / HEIGHT
        draw.line([(0, y), (WIDTH, y)], fill=(int(176 + 40 * t), int(196 + 30 * t), int(214 + 20 * t)))
    # Distant tree line.
    for x in range(0, WIDTH, 6):
        top = 300 - int(30 * abs(((x * 7) % 97) / 97 - 0.5)) - rng.randint(0, 12)
        draw.rectangle([x, top, x + 7, 360], fill=(58 + rng.randint(0, 14), 84 + rng.randint(0, 14), 60 + rng.randint(0, 10)))
    # Gravel yard.
    draw.rectangle([0, 400, WIDTH, HEIGHT], fill=(122, 112, 98))
    for _ in range(9000):
        x, y = rng.randrange(WIDTH), rng.randrange(400, HEIGHT)
        shade = rng.randint(80, 170)
        draw.point((x, y), fill=(shade, shade - 8, shade - 20))
    # Shed posts and roof.
    for x in (110, 470, 830):
        draw.rectangle([x, 120, x + 16, 420], fill=(70, 72, 76))
    draw.polygon([(60, 128), (906, 128), (870, 70), (96, 70)], fill=(64, 74, 88))
    draw.rectangle([60, 128, 906, 140], fill=(44, 50, 60))
    # Shadow under the roof.
    draw.rectangle([90, 140, 876, 410], fill=(96, 92, 86))
    # Stacked oak boards with stickers between the layers.
    y = 395
    for layer in range(11):
        h = 18
        for stack, (left, right) in enumerate(((140, 460), (500, 820))):
            x = left
            while x < right:
                w = rng.randint(60, 110)
                base = (196 + rng.randint(-16, 12), 146 + rng.randint(-14, 10), 88 + rng.randint(-12, 10))
                draw.rectangle([x, y - h, min(x + w, right), y], fill=base)
                draw.line([(x, y - h), (min(x + w, right), y - h)], fill=(226, 186, 128))
                draw.line([(x, y), (min(x + w, right), y)], fill=(120, 84, 46))
                x += w + 2
            for sx in range(left + 20, right, 74):
                draw.rectangle([sx, y - h - 5, sx + 10, y - h], fill=(92, 64, 40))
        y -= h + 5
    # Soft focus and a little sensor noise.
    image = image.filter(ImageFilter.GaussianBlur(0.8))
    pixels = image.load()
    for _ in range(40000):
        x, y = rng.randrange(WIDTH), rng.randrange(HEIGHT)
        r, g, b = pixels[x, y]
        d = rng.randint(-10, 10)
        pixels[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)))
    image.save(OUTPUT, "JPEG", quality=82, optimize=False, progressive=False, subsampling="4:2:0")
    print(f"wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
