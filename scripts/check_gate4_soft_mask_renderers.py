#!/usr/bin/env python3
"""Pinned renderer evidence for the Gate 4 Form-backed alpha soft-mask
fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive.
Every fixture uses integer-point axis-aligned placements, so each 100x100
raster at 72 dpi is constructed independently from the typed scenario — its
geometry from the authored rectangles, mask bands, and placements, its colors
from the per-sample mask compositing model ``C = m*a*Cs + (1-m*a)*Cb``
evaluated over the paint order, where ``m`` is the mask form's band alpha
(zero outside its painted bands) and ``a`` the ambient constant alpha — and
compared with zero pixel and zero channel tolerance.

The per-renderer resolved codes are pinned and mechanically validated against
the ideal model (one code for PDFium and PDFBox, three for MuPDF, whose ICC
pipeline shifts masked composites by up to one more code than its plain
sRGB fills; its calibrated-gray composites display through the pinned tone
behavior the form slice recorded). Two version-scoped renderer deviations are
pinned exactly rather than tolerated loosely:

- PDFium 7988 re-evaluates the active soft mask in a placed non-group
  form's translated coordinate space, so the masked plain-form band renders
  the intersection of the page-space bands with their form-space copies
  (PDFBox and MuPDF hold the mask in the page space the gs operation fixed).
  The deviant band is pinned exactly against the intersection model.
- PDFBox 3.0.8 renders a masked isolated-group form one device row short at
  the top (the group slice pinned the related one-row placement offset).

The showcase makes the mask bands, the zero-coverage knockout, the constant
times mask product, masked plain and isolated-group placements, and the
inner-times-outer mask composition visible; the reuse grid proves 100
identical mask groups paint identically through one canonical mask state.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from check_gate2_renderers import Raster, read_ppm
from check_gate4_form_renderers import compile_java, render_mutool, require

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_soft_masks" / "snapshot.pdf"
REUSE_SNAPSHOT = ROOT / "tests" / "gate4_soft_masks_reuse_100" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SIZE = 100

## Ideal float composites per region (the independent model). The mask band
## alphas are the exact U16 ratio 32768/65535 for the half band and one for
## the opaque band; coverage is zero outside the bands.
IDEAL = {
    "red_half": (255.0, 127.498, 127.498),
    "red_full": (255.0, 0.0, 0.0),
    "blue_half": (127.498, 127.498, 255.0),
    "blue_full": (0.0, 0.0, 255.0),
    "gray_quarter": (239.251, 239.251, 239.251),  # constant 0.5 x mask 0.5 on gray 192
    "gray_half": (223.499, 223.499, 223.499),
    "green_half": (127.498, 223.499, 127.498),
    "green_full": (0.0, 192.0, 0.0),
    "green_quarter": (191.251, 239.251, 191.251),      # PDFium: page band x its form-space copy
    "green_shift_half": (127.498, 223.499, 127.498),   # PDFium: opaque page band x shifted half band
    "g_quarter": (191.251, 191.251, 255.0),       # outer half x inner half on blue
    "g_half": (127.498, 127.498, 255.0),
    "g_full": (0.0, 0.0, 255.0),
    "reuse_gray96": (96.0, 96.0, 96.0),           # 100 masked layers converge
    "anchor_gray32": (32.0, 32.0, 32.0),
    "showcase_gray96": (96.0, 96.0, 96.0),        # the unmasked plain anchor
}

PDFIUM = {
    "red_half": (255, 128, 128),
    "red_full": (255, 0, 0),
    "blue_half": (128, 128, 255),
    "blue_full": (0, 0, 255),
    "gray_quarter": (239, 239, 239),
    "gray_half": (223, 223, 223),
    "green_half": (128, 223, 128),
    "green_full": (0, 192, 0),
    "green_quarter": (192, 239, 192),
    "green_shift_half": (128, 223, 128),
    "g_quarter": (192, 192, 255),
    "g_half": (128, 128, 255),
    "g_full": (0, 0, 255),
    "reuse_gray96": (96, 96, 96),
    "anchor_gray32": (32, 32, 32),
    "showcase_gray96": (96, 96, 96),
}

PDFBOX = {
    "red_half": (255, 127, 127),
    "red_full": (255, 0, 0),
    "blue_half": (127, 127, 255),
    "blue_full": (0, 0, 255),
    "gray_quarter": (239, 239, 239),
    "gray_half": (223, 223, 223),
    "green_half": (127, 223, 127),
    "green_full": (0, 192, 0),
    "green_quarter": (191, 239, 191),
    "green_shift_half": (127, 223, 127),
    "g_quarter": (191, 191, 255),
    "g_half": (127, 127, 255),
    "g_full": (0, 0, 255),
    "reuse_gray96": (96, 96, 96),
    "anchor_gray32": (32, 32, 32),
    "showcase_gray96": (96, 96, 96),
}

MUTOOL = {
    "red_half": (255, 130, 130),
    "red_full": (255, 0, 0),
    "blue_half": (130, 130, 255),
    "blue_full": (0, 0, 255),
    "gray_quarter": (247, 247, 247),
    "gray_half": (240, 240, 240),
    "green_half": (130, 224, 130),
    "green_full": (0, 192, 0),
    "green_quarter": (194, 240, 194),
    "green_shift_half": (130, 224, 130),
    "g_quarter": (194, 194, 255),
    "g_half": (130, 130, 255),
    "g_full": (0, 0, 255),
    "reuse_gray96": (164, 164, 164),
    "anchor_gray32": (99, 99, 99),
    "showcase_gray96": (165, 165, 165),
}

## Calibrated-gray composites display through MuPDF's pinned tone behavior
## and are excluded from the model-adjacency rule.
MUTOOL_TONE_REGIONS = {"gray_quarter", "gray_half", "reuse_gray96", "anchor_gray32", "showcase_gray96"}

## PDFBox 3.0.8 renders the masked isolated-group form one device row short
## at the top; the region is pinned at that exact height.
PDFBOX_GROUP_ROW_LOSS = 1


class Expectation:
    def __init__(self, pins: dict[str, tuple[int, int, int]]) -> None:
        self.pixels = bytearray((255, 255, 255)) * (SIZE * SIZE)
        self.pins = pins

    def paint(self, region: str, left: int, bottom: int, width: int, height: int) -> None:
        triple = self.pins[region]
        for y in range(bottom, bottom + height):
            row = SIZE - 1 - y
            for x in range(left, left + width):
                offset = (row * SIZE + x) * 3
                self.pixels[offset : offset + 3] = bytes(triple)

    def band(self, half: str, full: str, bottom: int, height: int) -> None:
        ## Content spans x 10..90; the mask's half band covers x 20..50, its
        ## opaque band x 50..80, and coverage is zero elsewhere.
        self.paint(half, 20, bottom, 30, height)
        self.paint(full, 50, bottom, 30, height)

    def raster(self) -> Raster:
        return Raster(SIZE, SIZE, bytes(self.pixels))


def showcase_expectation(pins: dict[str, tuple[int, int, int]], group_row_loss: int = 0, form_mask_shift: bool = False) -> Raster:
    exp = Expectation(pins)
    exp.band("red_half", "red_full", 84, 8)
    exp.band("blue_half", "blue_full", 62, 10)
    exp.band("gray_quarter", "gray_half", 44, 10)
    if form_mask_shift:
        ## PDFium's pinned deviation: the plain form's band is the
        ## intersection of the page-space bands with their copies shifted by
        ## the placement translation (+10), the same zone geometry the
        ## isolated group legitimately produces.
        exp.paint("green_quarter", 30, 26, 20, 8)
        exp.paint("green_shift_half", 50, 26, 10, 8)
        exp.paint("green_full", 60, 26, 20, 8)
    else:
        exp.band("green_half", "green_full", 26, 8)
    ## The isolated-group form at (10, 8) applies the shared mask again in
    ## its translated space, so its inner bands sit at page x 30..60..90 and
    ## intersect the outer bands: quarter, half, then full coverage.
    exp.paint("showcase_gray96", 2, 2, 6, 6)
    exp.paint("g_quarter", 30, 8, 20, 10 - group_row_loss)
    exp.paint("g_half", 50, 8, 10, 10 - group_row_loss)
    exp.paint("g_full", 60, 8, 20, 10 - group_row_loss)
    return exp.raster()


def reuse_expectation(pins: dict[str, tuple[int, int, int]]) -> Raster:
    exp = Expectation(pins)
    exp.paint("anchor_gray32", 0, 95, 4, 4)
    exp.paint("reuse_gray96", 1, 1, 3, 3)
    return exp.raster()


def assert_exact(label: str, actual: Raster, expected: Raster) -> None:
    require((actual.width, actual.height) == (expected.width, expected.height), f"{label}: dimensions differ")
    if actual.pixels == expected.pixels:
        return
    difference = next(index for index, pair in enumerate(zip(actual.pixels, expected.pixels)) if pair[0] != pair[1])
    pixel = difference // 3
    x = pixel % actual.width
    y = actual.height - 1 - pixel // actual.width
    raise SystemExit(
        f"{label}: raster differs from the independent expectation at ({x}, {y}): "
        f"expected {expected.pixels[difference]}, got {actual.pixels[difference]}"
    )


def check_pins_against_model() -> None:
    """Every pin outside the documented tone regions must stay adjacent to
    the ideal mask-compositing model; PDFium's deviant band validates
    against its own pinned intersection model through the dedicated ideal
    entries."""
    for name, ideal in IDEAL.items():
        for label, pins, excluded, bound in (
            ("PDFium", PDFIUM, set(), 1.0),
            ("PDFBox", PDFBOX, set(), 1.0),
            ("MuPDF", MUTOOL, MUTOOL_TONE_REGIONS, 3.0),
        ):
            if name in excluded:
                continue
            pin = pins[name]
            for channel, (ideal_value, pinned) in enumerate(zip(ideal, pin)):
                require(
                    abs(pinned - ideal_value) <= bound,
                    f"{label} pin {name} channel {channel}: {pinned} is not within {bound} of the ideal {ideal_value}",
                )


def render_both(renderer: Path, working_directory: Path | None, classes: Path, snapshot: Path, temporary: Path, name: str) -> tuple[Raster, Raster]:
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
    check_pins_against_model()
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate4-soft-mask-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        for name, snapshot, pdfium_expected, pdfbox_expected, mutool_expected in (
            (
                "showcase",
                SHOWCASE_SNAPSHOT,
                showcase_expectation(PDFIUM, 0, True),
                showcase_expectation(PDFBOX, PDFBOX_GROUP_ROW_LOSS),
                showcase_expectation(MUTOOL),
            ),
            (
                "reuse-100",
                REUSE_SNAPSHOT,
                reuse_expectation(PDFIUM),
                reuse_expectation(PDFBOX),
                reuse_expectation(MUTOOL),
            ),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, name)
            assert_exact(f"PDFium Chromium 7988 {name}", pdfium, pdfium_expected)
            assert_exact(f"PDFBox 3.0.8 {name}", pdfbox, pdfbox_expected)
            if mutool is not None:
                mutool_output = temporary / f"{name}-mutool.ppm"
                render_mutool(mutool, snapshot, mutool_output)
                assert_exact(f"MuPDF 1.28.2 {name}", read_ppm(mutool_output), mutool_expected)

    third = (
        " MuPDF 1.28.2 agrees through its ICC pipeline and pinned calibrated-gray tone behavior."
        if mutool is not None
        else ""
    )
    print(
        "PASS Gate 4 soft-mask renderers: PDFium Chromium 7988 and PDFBox 3.0.8 match the "
        "independent per-sample mask composites exactly, including the zero-coverage knockout, the "
        "constant-times-mask product, masked plain and isolated-group placements with their pinned "
        "version-scoped deviations, and the shared-mask grid." + third
    )


def self_test() -> None:
    check_pins_against_model()
    showcase = showcase_expectation(PDFIUM, 0, True)

    def at(raster: Raster, x: int, y: int) -> tuple[int, ...]:
        offset = ((SIZE - 1 - y) * SIZE + x) * 3
        return tuple(raster.pixels[offset : offset + 3])

    require(at(showcase, 15, 88) == (255, 255, 255), "zero-coverage knockout expectation is wrong")
    require(at(showcase, 35, 88) == (255, 128, 128), "half-band expectation is wrong")
    require(at(showcase, 65, 88) == (255, 0, 0), "opaque-band expectation is wrong")
    require(at(showcase, 35, 48) == (239, 239, 239), "constant-times-mask expectation is wrong")
    require(at(showcase, 25, 30) == (255, 255, 255), "PDFium form-space mask-shift expectation is wrong")
    require(at(showcase, 35, 30) == (192, 239, 192), "PDFium shifted-quarter expectation is wrong")

    require(at(showcase, 40, 12) == (192, 192, 255), "inner-times-outer mask expectation is wrong")
    require(at(showcase, 85, 12) == (255, 255, 255), "outer zero-coverage expectation is wrong")
    shifted = showcase_expectation(PDFBOX, PDFBOX_GROUP_ROW_LOSS)
    require(at(shifted, 40, 17) == (255, 255, 255), "PDFBox group-row-loss expectation is wrong")
    require(at(shifted, 40, 16) == (191, 191, 255), "PDFBox group top-row expectation is wrong")

    mutation = bytearray(showcase.pixels)
    mutation[(50 * SIZE + 50) * 3] = 254
    try:
        assert_exact("negative twin", Raster(SIZE, SIZE, bytes(mutation)), showcase)
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 soft-mask renderer checker accepted a one-channel negative twin")

    try:
        for channel, (ideal_value, pinned) in enumerate(zip(IDEAL["red_half"], (255, 131, 131))):
            require(abs(pinned - ideal_value) <= 1.0, "drifted pin")
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 soft-mask renderer checker accepted a pin far from the model")
    print("PASS Gate 4 soft-mask renderer checker self-test")


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
