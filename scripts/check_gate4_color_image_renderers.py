#!/usr/bin/env python3
"""Pinned renderer evidence for the Gate 4 color and image leaf fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive.
Every fixture uses integer-point axis-aligned placements of exact 8-bit
values, so each 100x100 raster at 72 dpi is constructed independently from the
typed scenario and compared with zero pixel and zero channel tolerance:

- the showcase renders the ICCBased sRGB raster (compact and padded authored
  twins through one canonical object), the calibrated-gray raster whose alpha
  plane must knock out its bottom row through the emitted soft mask, the
  3-component DCT stream (a DC-only baseline JPEG every conforming decoder
  reproduces exactly), the calibrated background path, and the form that
  reuses the deduplicated image;
- the duplicate-image grid renders 64 placements of the one canonical image;
- the distinct-image grid renders each of its 8 distinct rasters.

Color management is pinned per renderer and version, still with zero
tolerance. PDFBox 3.0.8 displays the embedded sRGB2014 profile as the
identity mapping. PDFium 7988 maps two exact values one code apart under its
ICC pipeline: pure green displays as (1, 255, 0) and the (64, 64, 192) fill
as (63, 63, 192). MuPDF 1.28.2 shares the (63, 63, 192) fill, keeps the
primaries identical, and displays calibrated gray through the sRGB transfer
curve exactly as pinned by the Gate 4 form renderer checker; its distinct-grid
lane is deliberately omitted because only the calibrated values 0, 64, 128,
and 255 carry pinned tone triples.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from check_gate2_renderers import Raster, read_ppm
from check_gate4_form_renderers import (
    MUTOOL_IMAGE_TONES,
    MUTOOL_VECTOR_TONES,
    compile_java,
    render_mutool,
    require,
)

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_color_images" / "snapshot.pdf"
DEDUP_SNAPSHOT = ROOT / "tests" / "gate4_color_images_dedup_64" / "snapshot.pdf"
DISTINCT_SNAPSHOT = ROOT / "tests" / "gate4_color_images_distinct_8" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SIZE = 100

IDENTITY_SRGB = {
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "white": (255, 255, 255),
    "fill": (64, 64, 192),
    "jpeg": (128, 128, 128),
}
PDFIUM_SRGB = {**IDENTITY_SRGB, "green": (1, 255, 0), "fill": (63, 63, 192)}
MUTOOL_SRGB = {**IDENTITY_SRGB, "fill": (63, 63, 192)}


class Expectation:
    """An independent raster built from the typed scenario."""

    def __init__(
        self,
        srgb: dict[str, tuple[int, int, int]],
        vector_tones: dict[int, tuple[int, int, int]] | None = None,
        image_tones: dict[int, tuple[int, int, int]] | None = None,
    ) -> None:
        self.pixels = bytearray((255, 255, 255)) * (SIZE * SIZE)
        self.srgb = srgb
        self.vector_tones = vector_tones or {}
        self.image_tones = image_tones or {}

    def paint(self, left: int, bottom: int, width: int, height: int, triple: tuple[int, int, int]) -> None:
        for y in range(bottom, bottom + height):
            row = SIZE - 1 - y
            for x in range(left, left + width):
                offset = (row * SIZE + x) * 3
                self.pixels[offset : offset + 3] = bytes(triple)

    def fill(self, left: int, bottom: int, width: int, height: int, value: int) -> None:
        self.paint(left, bottom, width, height, self.vector_tones.get(value, (value, value, value)))

    def gray_cell(self, left: int, bottom: int, width: int, height: int, value: int) -> None:
        self.paint(left, bottom, width, height, self.image_tones.get(value, (value, value, value)))

    def rgb_image(self, left: int, bottom: int) -> None:
        ## The 2x2 sRGB raster stretched to 20x10 points: red, green over
        ## blue, white in source row order (top row first).
        self.paint(left, bottom + 5, 10, 5, self.srgb["red"])
        self.paint(left + 10, bottom + 5, 10, 5, self.srgb["green"])
        self.paint(left, bottom, 10, 5, self.srgb["blue"])
        self.paint(left + 10, bottom, 10, 5, self.srgb["white"])

    def gray_alpha_image(self, left: int, bottom: int) -> None:
        ## The 2x2 calibrated raster stretched to 20x10 points; the alpha
        ## plane is opaque on the top row and fully transparent on the bottom
        ## row, so the soft mask must leave the background untouched there.
        self.gray_cell(left, bottom + 5, 10, 5, 0)
        self.gray_cell(left + 10, bottom + 5, 10, 5, 64)

    def grid_image(self, left: int, bottom: int, first: int) -> None:
        ## One 2x2 grid raster stretched to 8x8 points.
        self.gray_cell(left, bottom + 4, 4, 4, first)
        self.gray_cell(left + 4, bottom + 4, 4, 4, 64)
        self.gray_cell(left, bottom, 4, 4, 128)
        self.gray_cell(left + 4, bottom, 4, 4, 255)

    def raster(self) -> Raster:
        return Raster(SIZE, SIZE, bytes(self.pixels))


def showcase_expectation(
    srgb: dict[str, tuple[int, int, int]],
    vector_tones: dict[int, tuple[int, int, int]] | None = None,
    image_tones: dict[int, tuple[int, int, int]] | None = None,
) -> Raster:
    exp = Expectation(srgb, vector_tones, image_tones)
    exp.rgb_image(10, 80)            # compact RGB raster, meaningful placement
    exp.gray_alpha_image(40, 80)     # gray raster; alpha knocks out the bottom row
    exp.paint(70, 80, 10, 10, exp.srgb["jpeg"])  # the DCT stream, sRGB-managed
    exp.fill(10, 10, 30, 10, 128)    # calibrated background path
    exp.rgb_image(10, 40)            # padded twin painted inside the form
    exp.paint(30, 40, 10, 10, exp.srgb["fill"])  # ICCBased fill inside the form
    exp.gray_alpha_image(40, 60)     # duplicated gray twin as decoration
    return exp.raster()


def dedup_expectation(
    placements: int,
    vector_tones: dict[int, tuple[int, int, int]] | None = None,
    image_tones: dict[int, tuple[int, int, int]] | None = None,
) -> Raster:
    exp = Expectation(IDENTITY_SRGB, vector_tones, image_tones)
    exp.fill(0, 95, 4, 4, 32)        # the meaningful anchor path
    for index in range(placements):
        exp.grid_image((index % 10) * 10, ((index // 10) % 9) * 10, 0)
    return exp.raster()


def distinct_expectation(placements: int) -> Raster:
    exp = Expectation(IDENTITY_SRGB)
    exp.fill(0, 95, 4, 4, 32)
    for index in range(placements):
        exp.grid_image((index % 10) * 10, ((index // 10) % 9) * 10, index)
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
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate4-color-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        for name, snapshot, pdfium_expected, pdfbox_expected, mutool_expected in (
            (
                "showcase",
                SHOWCASE_SNAPSHOT,
                showcase_expectation(PDFIUM_SRGB),
                showcase_expectation(IDENTITY_SRGB),
                showcase_expectation(MUTOOL_SRGB, MUTOOL_VECTOR_TONES, MUTOOL_IMAGE_TONES),
            ),
            (
                "dedup-64",
                DEDUP_SNAPSHOT,
                dedup_expectation(64),
                dedup_expectation(64),
                dedup_expectation(64, MUTOOL_VECTOR_TONES, MUTOOL_IMAGE_TONES),
            ),
            ("distinct-8", DISTINCT_SNAPSHOT, distinct_expectation(8), distinct_expectation(8), None),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, name)
            assert_exact(f"PDFium Chromium 7988 {name}", pdfium, pdfium_expected)
            assert_exact(f"PDFBox 3.0.8 {name}", pdfbox, pdfbox_expected)
            if mutool is not None and mutool_expected is not None:
                mutool_output = temporary / f"{name}-mutool.ppm"
                render_mutool(mutool, snapshot, mutool_output)
                assert_exact(f"MuPDF 1.28.2 {name}", read_ppm(mutool_output), mutool_expected)

    third = (
        " MuPDF 1.28.2 agrees on the showcase and duplicate grid through its pinned CalGray and sRGB mappings."
        if mutool is not None
        else ""
    )
    print(
        "PASS Gate 4 color-image renderers: PDFium Chromium 7988 and PDFBox 3.0.8 match the "
        "independent showcase/dedup/distinct rasters exactly, including the ICCBased sRGB raster, "
        "the DCT stream, and the alpha soft-mask knockout." + third
    )


def self_test() -> None:
    showcase = showcase_expectation(IDENTITY_SRGB)
    require(len(showcase.pixels) == SIZE * SIZE * 3, "showcase expectation has wrong size")

    def at(raster: Raster, x: int, y: int) -> tuple[int, int, int]:
        offset = ((SIZE - 1 - y) * SIZE + x) * 3
        return tuple(raster.pixels[offset : offset + 3])

    require(at(showcase, 15, 87) == (255, 0, 0), "showcase red cell expectation is wrong")
    require(at(showcase, 25, 82) == (255, 255, 255), "showcase white cell expectation is wrong")
    require(at(showcase, 45, 82) == (255, 255, 255), "alpha knockout expectation is wrong")
    require(at(showcase, 45, 87) == (0, 0, 0), "opaque gray cell expectation is wrong")
    require(at(showcase, 75, 85) == (128, 128, 128), "DCT flat-value expectation is wrong")
    require(at(showcase, 35, 45) == (64, 64, 192), "ICCBased fill expectation is wrong")
    pdfium = showcase_expectation(PDFIUM_SRGB)
    require(at(pdfium, 25, 87) == (1, 255, 0), "PDFium green tone expectation is wrong")
    require(at(pdfium, 35, 45) == (63, 63, 192), "PDFium fill tone expectation is wrong")
    mutool = showcase_expectation(MUTOOL_SRGB, MUTOOL_VECTOR_TONES, MUTOOL_IMAGE_TONES)
    require(at(mutool, 25, 15) == (187, 187, 187), "mutool vector tone expectation is wrong")
    require(at(mutool, 55, 87) == (137, 137, 137), "mutool image tone expectation is wrong")
    distinct = distinct_expectation(8)
    require(at(distinct, 71, 5) == (7, 7, 7), "distinct grid first-pixel expectation is wrong")
    require(at(distinct, 75, 1) == (255, 255, 255), "distinct grid last-cell expectation is wrong")
    require(at(distinct, 50, 50) == (255, 255, 255), "distinct grid background expectation is wrong")

    mutation = bytearray(showcase.pixels)
    mutation[(50 * SIZE + 50) * 3] = 254
    try:
        assert_exact("negative twin", Raster(SIZE, SIZE, bytes(mutation)), showcase)
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 color-image renderer checker accepted a one-channel negative twin")
    print("PASS Gate 4 color-image renderer checker self-test")


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
