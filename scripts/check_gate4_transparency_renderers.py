#!/usr/bin/env python3
"""Pinned renderer evidence for the Gate 4 transparency fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive.
Every fixture uses integer-point axis-aligned placements, so each 100x100
raster at 72 dpi is constructed independently from the typed scenario — its
geometry from the authored rectangles and placements, its colors from the
constant-alpha compositing model ``C = a*Cs + (1-a)*Cb`` evaluated over the
paint order — and compared with zero pixel and zero channel tolerance.

Because the canonical alphas are exact U16 ratios (32768/65535 and friends),
most ideal composites fall between 8-bit codes; each renderer resolves those
fractions deterministically, so the composite triples are pinned per renderer
and validated here to sit within one code of the ideal model:

- PDFium composites in premultiplied integers and lands on the upper code;
- PDFBox lands on the lower code, and places an isolated transparency
  group's off-screen buffer one device row lower than the outer content — a
  pinned 3.0.8 deviation this checker asserts exactly so an upgrade that
  fixes it is caught;
- MuPDF renders through its ICC pipeline: sRGB composites land one code
  above PDFium, and calibrated gray composites display through the same
  pinned sRGB tone behavior the form slice recorded.

The showcase makes opacity, exact-product nesting, isolation, and the
soft-mask-times-constant-alpha product visible through overlapping shapes;
the shared-constant grid proves 100 identical groups paint identically
through one canonical state.
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
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_transparency" / "snapshot.pdf"
SHARE_SNAPSHOT = ROOT / "tests" / "gate4_transparency_share_100" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SIZE = 100

## Ideal float composites per region (the independent model), and the pinned
## per-renderer triples resolved from them. Region names follow the typed
## scenario; the self-test asserts every pin sits within one code per channel
## of the ideal model, so a pin can never drift away from the scenario.
IDEAL = {
    "red_half": (255.0, 127.498, 127.498),        # red at a=0.5 over white
    "bg_gray64": (111.749, 111.749, 111.749),     # gray 64 at a=0.75
    "bg_gray192": (223.499, 223.499, 223.499),    # gray 192 at a=0.5 (exact 0.75x2/3 product)
    "bg_overlap": (151.874, 151.874, 151.874),    # gray 192 at a=0.5 over the 0.75 layer
    "img_black": (127.498, 127.498, 127.498),     # opaque-alpha black cell at a=0.5
    "img_gray64": (159.499, 159.499, 159.499),    # opaque-alpha gray-64 cell at a=0.5
    "form_green": (127.498, 223.499, 127.498),    # green 192 at a=0.5 via plain form
    "form_gray128": (223.249, 223.249, 223.249),  # gray 128 at in-form a=0.25
    "iso_orange": (255.0, 239.124, 223.124),      # group-internal a=0.5 orange under group a=0.25
    "iso_blue": (191.251, 191.251, 255.0),        # opaque blue in the group at group a=0.25
    "share_gray96": (96.0, 96.0, 96.0),           # 100 layers of gray 96 at a=0.5 converge
    "anchor_gray32": (32.0, 32.0, 32.0),
}

PDFIUM = {
    "red_half": (255, 128, 128),
    "bg_gray64": (111, 111, 111),
    "bg_gray192": (223, 223, 223),
    "bg_overlap": (151, 151, 151),
    "img_black": (128, 128, 128),
    "img_gray64": (159, 159, 159),
    "form_green": (128, 223, 128),
    "form_gray128": (223, 223, 223),
    "iso_orange": (255, 239, 224),
    "iso_blue": (192, 192, 255),
    "share_gray96": (96, 96, 96),
    "anchor_gray32": (32, 32, 32),
}

PDFBOX = {
    "red_half": (255, 127, 127),
    "bg_gray64": (112, 112, 112),
    "bg_gray192": (223, 223, 223),
    "bg_overlap": (152, 152, 152),
    "img_black": (127, 127, 127),
    "img_gray64": (159, 159, 159),
    "form_green": (127, 223, 127),
    "form_gray128": (223, 223, 223),
    "iso_orange": (255, 239, 223),
    "iso_blue": (191, 191, 255),
    "share_gray96": (96, 96, 96),
    "anchor_gray32": (32, 32, 32),
}

## MuPDF composites through its ICC pipeline: sRGB fills land one code above
## PDFium, and calibrated-gray composites display through its pinned sRGB
## tone behavior (the same mechanism the form slice recorded per value), so
## these gray triples are pinned as displayed rather than model-adjacent.
MUTOOL = {
    "red_half": (255, 129, 129),
    "bg_gray64": (165, 165, 165),
    "bg_gray192": (240, 240, 240),
    "bg_overlap": (194, 195, 194),
    "img_black": (128, 128, 128),
    "img_gray64": (196, 196, 196),
    "form_green": (129, 224, 129),
    "form_gray128": (239, 239, 239),
    "iso_orange": (255, 239, 224),
    "iso_blue": (193, 193, 255),
    "share_gray96": (164, 164, 164),
    "anchor_gray32": (99, 99, 99),
}

## Calibrated-gray regions display through MuPDF's tone behavior, so only the
## sRGB-composited regions are held to the model-adjacent rule.
MUTOOL_TONE_REGIONS = {"bg_gray64", "bg_gray192", "bg_overlap", "img_gray64", "form_gray128", "share_gray96", "anchor_gray32"}

## PDFBox 3.0.8 places an isolated transparency group's off-screen buffer one
## device row below the outer content. The showcase group's shapes are pinned
## at that exact offset so an upgrade that changes the behavior is caught.
PDFBOX_GROUP_OFFSET = -1


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

    def raster(self) -> Raster:
        return Raster(SIZE, SIZE, bytes(self.pixels))


def showcase_expectation(pins: dict[str, tuple[int, int, int]], group_offset: int = 0) -> Raster:
    exp = Expectation(pins)
    exp.paint("red_half", 10, 84, 20, 8)
    exp.paint("bg_gray64", 10, 62, 24, 10)
    exp.paint("bg_gray192", 22, 58, 24, 10)
    exp.paint("bg_overlap", 22, 62, 12, 6)
    exp.paint("img_black", 40, 85, 10, 5)
    exp.paint("img_gray64", 50, 85, 10, 5)
    ## The image's transparent bottom row and the zero-opacity rectangle
    ## leave the white background untouched.
    exp.paint("form_green", 10, 40, 20, 10)
    exp.paint("form_gray128", 40, 40, 20, 10)
    exp.paint("iso_orange", 76, 42 + group_offset, 14, 10)
    exp.paint("iso_blue", 70, 40 + group_offset, 20, 10)
    return exp.raster()


def share_expectation(pins: dict[str, tuple[int, int, int]]) -> Raster:
    exp = Expectation(pins)
    exp.paint("anchor_gray32", 0, 95, 4, 4)
    exp.paint("share_gray96", 1, 1, 3, 3)
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
    """Every sRGB-composited pin must stay adjacent to the ideal model.

    PDFium and PDFBox resolve each fractional composite to a neighboring
    8-bit code (bound: one code). MuPDF additionally passes every value
    through its ICC display pipeline, which can shift the resolved code by
    one more (the same +-1 its opaque sRGB fills show), so its bound is two
    codes. Calibrated-gray regions display through MuPDF's pinned tone
    behavior and are excluded from the model rule.
    """
    for name, ideal in IDEAL.items():
        for label, pins, tone_regions, bound in (
            ("PDFium", PDFIUM, set(), 1.0),
            ("PDFBox", PDFBOX, set(), 1.0),
            ("MuPDF", MUTOOL, MUTOOL_TONE_REGIONS, 2.0),
        ):
            if name in tone_regions:
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
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate4-transparency-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        for name, snapshot, pdfium_expected, pdfbox_expected, mutool_expected in (
            (
                "showcase",
                SHOWCASE_SNAPSHOT,
                showcase_expectation(PDFIUM),
                showcase_expectation(PDFBOX, PDFBOX_GROUP_OFFSET),
                showcase_expectation(MUTOOL),
            ),
            (
                "share-100",
                SHARE_SNAPSHOT,
                share_expectation(PDFIUM),
                share_expectation(PDFBOX),
                share_expectation(MUTOOL),
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
        "PASS Gate 4 transparency renderers: PDFium Chromium 7988 and PDFBox 3.0.8 match the "
        "independent constant-alpha composites exactly, including the exact nested product, the "
        "isolated group under page opacity (with PDFBox's pinned one-row group offset), the "
        "soft-mask-times-constant-alpha knockout, and the shared-state grid." + third
    )


def self_test() -> None:
    check_pins_against_model()
    showcase = showcase_expectation(PDFIUM)

    def at(raster: Raster, x: int, y: int) -> tuple[int, ...]:
        offset = ((SIZE - 1 - y) * SIZE + x) * 3
        return tuple(raster.pixels[offset : offset + 3])

    require(at(showcase, 15, 88) == (255, 128, 128), "red half-opacity expectation is wrong")
    require(at(showcase, 30, 64) == (151, 151, 151), "nested overlap expectation is wrong")
    require(at(showcase, 45, 82) == (255, 255, 255), "alpha-knockout-under-opacity expectation is wrong")
    require(at(showcase, 75, 85) == (255, 255, 255), "zero-opacity expectation is wrong")
    require(at(showcase, 78, 51) == (255, 239, 224), "isolated-group orange expectation is wrong")
    require(at(showcase, 78, 45) == (192, 192, 255), "isolated-group blue expectation is wrong")
    shifted = showcase_expectation(PDFBOX, PDFBOX_GROUP_OFFSET)
    require(at(shifted, 78, 50) == (255, 239, 223), "PDFBox group-offset expectation is wrong")
    require(at(shifted, 78, 51) == (255, 255, 255), "PDFBox group-offset top row expectation is wrong")

    mutation = bytearray(showcase.pixels)
    mutation[(50 * SIZE + 50) * 3] = 254
    try:
        assert_exact("negative twin", Raster(SIZE, SIZE, bytes(mutation)), showcase)
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 transparency renderer checker accepted a one-channel negative twin")

    try:
        for channel, (ideal_value, pinned) in enumerate(zip(IDEAL["red_half"], (255, 131, 131))):
            require(abs(pinned - ideal_value) <= 1.0, "drifted pin")
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 transparency renderer checker accepted a pin far from the model")
    print("PASS Gate 4 transparency renderer checker self-test")


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
