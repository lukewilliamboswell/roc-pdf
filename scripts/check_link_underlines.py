#!/usr/bin/env python3
"""Independent evidence for themed link underlines.

Every link annotation quadrilateral (one per painted line of a link) must
have at least one filled rectangle in a `/Artifact <</Type /Layout>>`
decoration below its baseline and inside its horizontal extent, and every
such underline must lie under some quadrilateral of a link on its page.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from check_pdf_structure import ValidationError, dictionary_ref, object_slices, require
from check_text import decoded_stream


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "rich_inline" / "link_style_10.pdf"
LAYOUT_RECT = re.compile(rb"/Artifact <</Type /Layout>> BDC\n(?:/CS\S+ cs\n)?(?:[0-9. ]+ (?:scn|g|rg)\n)?(-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+) re\nf\nEMC\n")
NUMBERS = re.compile(rb"-?[0-9]+(?:\.[0-9]+)?")
TOLERANCE = 0.01


def page_quads(bodies: dict[int, bytes], page: bytes) -> list[tuple[float, float, float, float]]:
    """Each link quadrilateral as (x0, x1, bottom, top)."""
    annots = re.search(rb"/Annots \[([^\]]*)\]", page)
    quads: list[tuple[float, float, float, float]] = []
    if annots is None:
        return quads
    for number in re.findall(rb"(\d+) 0 R", annots.group(1)):
        body = bodies[int(number)]
        if b"/Subtype /Link" not in body:
            continue
        points = re.search(rb"/QuadPoints \[([^\]]*)\]", body)
        require(points is not None, "link annotation has no /QuadPoints")
        values = [float(value) for value in NUMBERS.findall(points.group(1))]
        require(len(values) % 8 == 0, "link /QuadPoints is not a list of quadrilaterals")
        for index in range(0, len(values), 8):
            xs = values[index:index + 8:2]
            ys = values[index + 1:index + 8:2]
            quads.append((min(xs), max(xs), min(ys), max(ys)))
    return quads


def validate_link_underlines_pdf(pdf: bytes) -> None:
    _, bodies = object_slices(pdf)
    pages = [body for body in bodies.values() if b"/Type /Page " in body]
    total = 0
    for page in pages:
        _, content = decoded_stream(bodies, dictionary_ref(page, b"Contents"))
        rects = [tuple(float(value) for value in match.groups()) for match in LAYOUT_RECT.finditer(content)]
        quads = page_quads(bodies, page)
        underlines = []
        for x, y, width, height in rects:
            under = [quad for quad in quads if quad[0] - TOLERANCE <= x and x + width <= quad[1] + TOLERANCE and quad[2] - TOLERANCE <= y and y + height <= quad[3] + TOLERANCE]
            if under:
                require(width > 0 and height > 0, "a link underline is empty")
                underlines.append((x, y, width, height))
        for quad in quads:
            require(any(quad[0] - TOLERANCE <= x and x + width <= quad[1] + TOLERANCE and quad[2] - TOLERANCE <= y and y + height <= quad[3] + TOLERANCE for x, y, width, height in underlines), f"a link line at x {quad[0]}..{quad[1]} has no underline decoration")
        total += len(underlines)
    require(total > 0, "no link underline decoration was painted")


def self_test() -> None:
    pdf = SNAPSHOT.read_bytes()
    validate_link_underlines_pdf(pdf)
    # The mixed rich-inline snapshot has link annotations and no underline
    # theme: it must be rejected.
    try:
        validate_link_underlines_pdf((ROOT / "tests" / "rich_inline" / "mixed.pdf").read_bytes())
    except ValidationError:
        pass
    else:
        raise SystemExit("link-underline checker accepted links without underlines")
    print("PASS link underline checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path, default=SNAPSHOT)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    validate_link_underlines_pdf(args.pdf.read_bytes())
    print(f"PASS link underlines: {args.pdf}")


if __name__ == "__main__":
    main()
