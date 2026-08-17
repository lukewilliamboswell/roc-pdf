#!/usr/bin/env python3
"""Pinned renderer evidence for the Gate 4 shading and tiling-pattern
fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive.
Every expected raster is constructed independently from the typed scenario —
never by rendering the PDF through another engine: axial colors from
``t = ((p-p0)·(p1-p0))/|p1-p0|²`` with the exact ``U16`` stop ratios, radial
coverage from the larger root of the standard circle-interpolation quadratic
with extension clamping, tile colors from the authored cell geometry under
the authored pattern matrices, and composites from the exact constant-alpha
model.

A renderer samples the shading function somewhere inside each device pixel
(and rasterizes pattern tiles on its own tile grid), so each pixel is
compared against the per-channel envelope of the ideal model over the pixel
footprint extended by a per-region sampling radius, plus a small pinned
per-renderer code tolerance. Every nonzero tolerance is justified next to
its pin; flat regions (background, tile interiors, extend plateaus) collapse
to exact single-color envelopes, so the tolerance never hides a wrong flat
color by more than the pinned ICC rounding.

Version-scoped deviations pinned exactly rather than tolerated loosely:

- PDFBox 3.0.8 evaluates radial shadings with a coarse in-domain
  approximation: where the near-circle solution exceeds the domain it paints
  the far-circle in-domain solution instead of the extension color, and it
  paints an extension blob on the apex side of the cone. Its radial band is
  therefore checked against the pinned weak model (every pixel stays in the
  authored blue-to-white family) while PDFium and MuPDF are held to the
  exact quadratic model.
- PDFBox 3.0.8 also quantizes shading-function evaluation coarsely
  (roughly 1/32 of the domain), which bounds its ramp deviation at half a
  quantization step of the steepest authored segment.
- MuPDF 1.28.2 displays calibrated-gray shading luminance through the sRGB
  transfer curve per channel (the pinned CalGray tone behavior recorded by
  the form slice); the calibrated band's ideal model applies that exact
  curve for MuPDF only.
- MuPDF 1.28.2 leaves the final device column of the *first* use of an
  unextended RGB axial shading unpainted; later uses of the same cached
  shade paint the column (the showcase's deduplicated twin band proves it,
  painting the exact column the first band drops). The affected column is
  pinned exactly as background white per fixture, never tolerated loosely.
"""
from __future__ import annotations

import argparse
import math
import os
import subprocess
import tempfile
from pathlib import Path

from check_gate2_renderers import Raster, read_ppm
from check_gate4_form_renderers import compile_java, render_mutool, require

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_shadings" / "snapshot.pdf"
SHARE_SNAPSHOT = ROOT / "tests" / "gate4_shadings_share_100" / "snapshot.pdf"
PSHARE_SNAPSHOT = ROOT / "tests" / "gate4_patterns_share_100" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SIZE = 100

RED = (1.0, 0.0, 0.0)
BLUE = (0.0, 0.0, 1.0)
YELLOW = (1.0, 1.0, 0.0)
GREEN = (0.0, 1.0, 0.0)
WHITE = (1.0, 1.0, 1.0)
INDIGO = (8224 / 65535.0, 8224 / 65535.0, 49344 / 65535.0)
ALPHA = 32768 / 65535.0
BOUND_1 = 16384 / 65535.0
BOUND_2 = 49152 / 65535.0
ANCHOR_GRAY = 8224 / 65535.0
CELL_GRAY = 977 / 65535.0

## MuPDF 1.28.2 converts calibrated gray *inside pattern tiles* through a
## different tone path than direct fills (whose luminance displays through
## the sRGB transfer curve). Following the form slice's convention for its
## CalGray tone tables, the exact resulting code for the one authored tile
## gray is pinned rather than modeled loosely.
MUTOOL_TILE_GRAY = 23 / 255.0
BAND_GRAY = 24672 / 65535.0

## Per-renderer, per-region pinned code tolerances over the envelope model.
## Justifications:
## - ``icc`` (1): PDFium's ICC pipeline resolves some exact sRGB codes one
##   code away from the identity mapping (pinned since the color-image
##   slice); MuPDF's pipeline shows the same ±1 on composites.
## - ``edge`` (PDFium bandC 9): PDFium resolves the two-root region within
##   one device pixel of the radial cone silhouette differently; the radial
##   ramp moves at most ~13 codes per pixel, and the measured bound is 9.
## - ``quant`` (PDFBox ramps): PDFBox 3.0.8 quantizes function evaluation at
##   roughly 1/32 of the domain; the steepest authored segment moves ~1020
##   codes per domain unit, so half a step is ~16 codes. Measured bounds:
##   band A/D 2.3, band B 10.2, the placed form's ramp 5.4.
## - ``blend`` (2): the exact U16 alpha product lands between 8-bit codes;
##   each renderer resolves it within one code of the ideal on both sides.
TOLERANCES = {
    "pdfium": {"back": 0, "bandA": 1, "bandB": 3, "bandC": 9, "bandD": 1, "twin": 1, "swap": 2, "patternA": 1, "patternB": 1, "formpat": 1, "formsh": 2, "grid": 1},
    "pdfbox": {"back": 0, "bandA": 3, "bandB": 12, "bandC": None, "bandD": 3, "twin": 3, "swap": 2, "patternA": 2, "patternB": 2, "formpat": 2, "formsh": 6, "grid": 2},
    "mutool": {"back": 0, "bandA": 1, "bandB": 1, "bandC": 1, "bandD": 1, "twin": 1, "swap": 2, "patternA": 2, "patternB": 2, "formpat": 2, "formsh": 1, "grid": 2},
}

## Sampling radii per region, in device pixels beyond the pixel footprint:
## direct ``sh`` regions use half a pixel (sample-position freedom), pattern
## regions a full pixel (tiles rasterize on the renderer's own tile grid),
## and the doubled-matrix pattern 1.5 (the tile grid scales with the
## matrix). The radial band uses a full pixel because the cone silhouette
## curves within a footprint.
RADII = {"back": 0.0, "bandA": 0.5, "bandB": 0.5, "bandC": 1.0, "bandD": 0.5, "twin": 0.5, "swap": 0.5, "patternA": 1.0, "patternB": 1.5, "formpat": 1.0, "formsh": 0.5, "grid": 1.0}
STEPS = 5


def lerp(c0, c1, t):
    return tuple(a + t * (b - a) for a, b in zip(c0, c1))


def clamp(t):
    return min(max(t, 0.0), 1.0)


def axial_t(px, py, x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    return ((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy)


def multi_stop(t):
    if t <= BOUND_1:
        return lerp(RED, YELLOW, t / BOUND_1)
    if t <= BOUND_2:
        return lerp(YELLOW, GREEN, (t - BOUND_1) / (BOUND_2 - BOUND_1))
    return lerp(GREEN, BLUE, (t - BOUND_2) / (1.0 - BOUND_2))


def radial_color(px, py):
    """The largest-root radial parameter for the authored cone
    ((30,59) r 2 to (60,59) r 12, both ends extended), or None outside its
    coverage."""
    cx0, cy0, r0 = 30.0, 59.0, 2.0
    dcx, dcy, dr = 30.0, 0.0, 10.0
    fx, fy = px - cx0, py - cy0
    a = dcx * dcx + dcy * dcy - dr * dr
    b = fx * dcx + fy * dcy + r0 * dr
    c = fx * fx + fy * fy - r0 * r0
    disc = b * b - a * c
    if disc < 0:
        return None
    root = math.sqrt(disc)
    best = None
    for t in ((b + root) / a, (b - root) / a):
        if r0 + t * dr >= 0 and (best is None or t > best):
            best = t
    if best is None:
        return None
    return lerp(BLUE, WHITE, clamp(best))


def gray_color(t, gray_policy):
    if gray_policy == "srgb":
        s = 12.92 * t if t <= 0.0031308 else 1.055 * (t ** (1 / 2.4)) - 0.055
        return (s, s, s)
    return (t, t, t)


def cell_color(cx, cy):
    """The authored pattern cell in cell space: the indigo origin square and
    the yellow-to-green ramp square."""
    if 0 <= cx < 5 and 0 <= cy < 5:
        return INDIGO
    if 5 <= cx < 10 and 5 <= cy < 10:
        return lerp(YELLOW, GREEN, (cx - 5.0) / 5.0)
    return None


def showcase_sample(px, py, sx, sy, gray_policy):
    """(region, ideal color) for the showcase page. The region comes from
    the fixed pixel center ``(px, py)`` (clips do not move with a
    renderer's sampling grid), while the paint formula is evaluated at the
    envelope sample ``(sx, sy)``."""
    if 10 <= px < 90 and 84 <= py < 92:
        return "bandA", lerp(RED, BLUE, clamp(axial_t(sx, sy, 10, 0, 90, 0)))
    if 10 <= px < 90 and 70 <= py < 80:
        t = axial_t(sx, sy, 10, 70, 90, 80)
        if t < 0 or t > 1:
            return "bandB", WHITE
        return "bandB", multi_stop(t)
    if 10 <= px < 90 and 52 <= py < 66:
        color = radial_color(sx, sy)
        return "bandC", (WHITE if color is None else color)
    if 10 <= px < 90 and 40 <= py < 48:
        return "bandD", gray_color(clamp(axial_t(sx, sy, 10, 0, 90, 0)), gray_policy)
    if 10 <= px < 90 and 30 <= py < 36:
        return "twin", lerp(RED, BLUE, clamp(axial_t(sx, sy, 10, 0, 90, 0)))
    if 10 <= px < 90 and 22 <= py < 28:
        base = lerp(BLUE, RED, clamp(axial_t(sx, sy, 10, 0, 90, 0)))
        return "swap", tuple(ALPHA * c + (1 - ALPHA) for c in base)
    if 10 <= px < 40 and 6 <= py < 18:
        color = cell_color(sx % 10, sy % 10)
        return "patternA", (WHITE if color is None else color)
    if 50 <= px < 80 and 6 <= py < 18:
        color = cell_color((sx / 2.0) % 10, (sy / 2.0) % 10)
        return "patternB", (WHITE if color is None else color)
    if 0 <= py < 6 and 10 <= px < 50:
        color = cell_color(sx % 10, sy % 10)
        return "formpat", (WHITE if color is None else color)
    if 0 <= py < 6 and 50 <= px < 90:
        return "formsh", lerp(RED, BLUE, clamp(axial_t(sx, sy, 20, 0, 100, 0)))
    return "back", WHITE


def share_sample(px, py, sx, sy, gray_policy):
    """The shared-shading grid: the calibrated anchor square and one
    two-stop gradient clipped to the large square (100 identical paints)."""
    if 0 <= px < 4 and 95 <= py < 99:
        return "grid", gray_color(ANCHOR_GRAY, gray_policy)
    if 10 <= px < 90 and 10 <= py < 90:
        return "bandA", lerp((255 / 65535.0, 0.0, 0.0), BLUE, clamp(axial_t(sx, sy, 10, 0, 90, 0)))
    return "back", WHITE


def pshare_sample(px, py, sx, sy, gray_policy):
    """The shared-pattern grid: the calibrated anchor square and one page
    region tiled by the gray cell pattern (100 identical fills)."""
    if 0 <= px < 4 and 95 <= py < 99:
        return "grid", gray_color(ANCHOR_GRAY, gray_policy)
    if 10 <= px < 90 and 10 <= py < 90:
        if (sx % 10) < 4 and (sy % 10) < 4:
            if gray_policy == "srgb":
                return "grid", (MUTOOL_TILE_GRAY, MUTOOL_TILE_GRAY, MUTOOL_TILE_GRAY)
            return "grid", gray_color(CELL_GRAY, gray_policy)
        return "grid", WHITE
    return "back", WHITE


def check_raster(label, raster, sample, tolerances, gray_policy, overrides=None):
    require((raster.width, raster.height) == (SIZE, SIZE), f"{label}: unexpected raster size")
    for y in range(SIZE):
        for x in range(SIZE):
            row = SIZE - 1 - y
            offset = (row * SIZE + x) * 3
            actual = raster.pixels[offset : offset + 3]
            if overrides is not None and (x, y) in overrides:
                expected = overrides[(x, y)]
                require(
                    tuple(actual) == expected,
                    f"{label}: ({x}, {y}) = {tuple(actual)} does not match the pinned deviation {expected}",
                )
                continue
            region, _ = sample(x + 0.5, y + 0.5, x + 0.5, y + 0.5, gray_policy)
            tolerance = tolerances[region]
            if tolerance is None:
                ## The pinned PDFBox radial deviation: the band stays inside
                ## the authored blue-to-white family.
                ok = actual[2] == 255 and abs(actual[0] - actual[1]) <= 1
                require(ok, f"{label}: ({x}, {y}) leaves the pinned radial color family: {tuple(actual)}")
                continue
            radius = RADII[region]
            los = [1e9, 1e9, 1e9]
            his = [-1e9, -1e9, -1e9]
            for i in range(STEPS):
                for j in range(STEPS):
                    sx = x + 0.5 + (i / (STEPS - 1) - 0.5) * (1 + 2 * radius)
                    sy = y + 0.5 + (j / (STEPS - 1) - 0.5) * (1 + 2 * radius)
                    _, color = sample(x + 0.5, y + 0.5, sx, sy, gray_policy)
                    for k in range(3):
                        value = color[k] * 255
                        los[k] = min(los[k], value)
                        his[k] = max(his[k], value)
            for k in range(3):
                low = los[k] - tolerance
                high = his[k] + tolerance
                require(
                    low <= actual[k] <= high,
                    f"{label}: ({x}, {y}) channel {k} = {actual[k]} outside the model envelope "
                    f"[{low:.2f}, {high:.2f}] for region {region}",
                )


def render_both(renderer, working_directory, classes, snapshot, temporary, name):
    pdfium_output = temporary / f"{name}-pdfium.ppm"
    pdfbox_output = temporary / f"{name}-pdfbox.ppm"
    subprocess.run([str(renderer), str(snapshot), str(pdfium_output), "1"], cwd=working_directory or ROOT, check=True)
    subprocess.run(
        ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxRender", str(snapshot), str(pdfbox_output), "72"],
        cwd=ROOT,
        check=True,
    )
    return read_ppm(pdfium_output), read_ppm(pdfbox_output)


def check_renderers(renderer: Path, working_directory: Path | None, mutool: Path | None) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    if mutool is not None:
        require(mutool.is_file(), f"mutool does not exist: {mutool}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate4-shading-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        ## MuPDF's pinned first-use axial column: the showcase drops the
        ## band-A column (its twin repaints it), and the shared-shading grid
        ## drops the single gradient's final column.
        mutool_overrides = {
            "showcase": {(89, y): (255, 255, 255) for y in range(84, 92)},
            "share-100": {(89, y): (255, 255, 255) for y in range(10, 90)},
            "pshare-100": {},
        }
        for name, snapshot, sample in (
            ("showcase", SHOWCASE_SNAPSHOT, showcase_sample),
            ("share-100", SHARE_SNAPSHOT, share_sample),
            ("pshare-100", PSHARE_SNAPSHOT, pshare_sample),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, name)
            pdfbox_tolerances = dict(TOLERANCES["pdfbox"])
            if sample is not showcase_sample:
                pdfbox_tolerances["bandC"] = 3
            check_raster(f"PDFium Chromium 7988 {name}", pdfium, sample, TOLERANCES["pdfium"], "direct")
            check_raster(f"PDFBox 3.0.8 {name}", pdfbox, sample, pdfbox_tolerances, "direct")
            if mutool is not None:
                mutool_output = temporary / f"{name}-mutool.ppm"
                render_mutool(mutool, snapshot, mutool_output)
                check_raster(f"MuPDF 1.28.2 {name}", read_ppm(mutool_output), sample, TOLERANCES["mutool"], "srgb", mutool_overrides[name])

    third = (
        " MuPDF 1.28.2 agrees through its ICC pipeline and pinned calibrated-gray tone behavior."
        if mutool is not None
        else ""
    )
    print(
        "PASS Gate 4 shading-pattern renderers: PDFium Chromium 7988 and PDFBox 3.0.8 match the "
        "independent gradient, radial, calibrated-gray, opacity-composite, and tiling models within "
        "the pinned per-region envelopes, including PDFBox's pinned radial deviation, the shared-"
        "shading grid, and the shared-pattern grid." + third
    )


def self_test() -> None:
    ## The model itself: exact interior colors, extension clamps, and tile
    ## geometry at representative points.
    region, color = showcase_sample(50.0, 88.0, 50.0, 88.0, "direct")
    require(region == "bandA" and abs(color[0] - 0.5) < 0.01 and abs(color[2] - 0.5) < 0.01, "band A midpoint model is wrong")
    region, color = showcase_sample(15.0, 75.0, 15.0, 75.0, "direct")
    require(region == "bandB" and color[0] > 0.9, "band B start model is wrong")
    region, color = showcase_sample(20.0, 59.0, 20.0, 59.0, "direct")
    require(region == "bandC" and color == WHITE, "radial apex-side coverage model is wrong")
    region, color = showcase_sample(30.0, 59.0, 30.0, 59.0, "direct")
    require(region == "bandC" and color[2] == 1.0 and color[0] < 0.15, "radial start-circle model is wrong")
    region, color = showcase_sample(85.0, 59.0, 85.0, 59.0, "direct")
    require(region == "bandC" and min(color) > 0.95, "radial extend-end model is wrong")
    region, color = showcase_sample(12.0, 12.0, 12.0, 12.0, "direct")
    require(region == "patternA" and color == INDIGO, "tile origin-square model is wrong")
    region, color = showcase_sample(17.5, 17.5, 17.5, 17.5, "direct")
    require(region == "patternA" and abs(color[0] - 0.5) < 0.01 and color[1] == 1.0, "tile ramp model is wrong")
    region, color = showcase_sample(62.0, 8.0, 62.0, 8.0, "direct")
    require(region == "patternB" and color == INDIGO, "doubled-tile model is wrong")
    region, color = showcase_sample(55.0, 3.0, 55.0, 3.0, "direct")
    require(region == "formsh" and abs(color[0] - (1 - 35 / 80)) < 0.01, "placed-form shading model is wrong")
    gray_direct = gray_color(0.5, "direct")
    gray_srgb = gray_color(0.5, "srgb")
    require(abs(gray_direct[0] - 0.5) < 1e-9 and gray_srgb[0] > 0.7, "gray tone models are wrong")

    ## A one-channel negative twin against a synthetic exact raster.
    pixels = bytearray()
    for y in range(SIZE - 1, -1, -1):
        for x in range(SIZE):
            _, color = showcase_sample(x + 0.5, y + 0.5, x + 0.5, y + 0.5, "direct")
            pixels += bytes(round(c * 255) for c in color)
    raster = Raster(SIZE, SIZE, bytes(pixels))
    check_raster("synthetic ideal", raster, showcase_sample, TOLERANCES["pdfium"], "direct")
    mutated = bytearray(pixels)
    offset = ((SIZE - 1 - 2) * SIZE + 2) * 3
    mutated[offset] = 128
    try:
        check_raster("negative twin", Raster(SIZE, SIZE, bytes(mutated)), showcase_sample, TOLERANCES["pdfium"], "direct")
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 shading renderer checker accepted a one-channel negative twin")
    print("PASS Gate 4 shading-pattern renderer checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--mutool", type=Path, help="mutool built from vendor/mupdf/mupdf-1.28.2-source.tgz")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.pdfium_renderer is not None, "--pdfium-renderer is required unless --self-test is used")
    check_renderers(args.pdfium_renderer.resolve(), args.pdfium_working_directory, args.mutool.resolve() if args.mutool is not None else None)


if __name__ == "__main__":
    main()
