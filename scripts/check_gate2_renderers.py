#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "gate2_minimal" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
PDFBOX_SOURCE = ROOT / "scripts" / "PdfBoxRender.java"
WIDTH = 100
HEIGHT = 100


@dataclass(frozen=True)
class Raster:
    width: int
    height: int
    pixels: bytes


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def read_ppm(path: Path) -> Raster:
    payload = path.read_bytes()
    parts = payload.split(b"\n", 3)
    require(len(parts) == 4, f"{path}: incomplete PPM header")
    magic, dimensions, maximum, pixels = parts
    require(magic == b"P6", f"{path}: expected binary PPM P6")
    fields = dimensions.split(b" ")
    require(len(fields) == 2 and all(field.isdigit() for field in fields), f"{path}: invalid dimensions")
    width, height = (int(field) for field in fields)
    require(maximum == b"255", f"{path}: expected eight-bit components")
    require(len(pixels) == width * height * 3, f"{path}: pixel payload has wrong length")
    return Raster(width, height, pixels)


def expected_raster() -> Raster:
    pixels = bytearray((255, 255, 255)) * (WIDTH * HEIGHT)

    def fill(left: int, top: int, right: int, bottom: int, value: int) -> None:
        for y in range(top, bottom):
            for x in range(left, right):
                offset = (y * WIDTH + x) * 3
                pixels[offset : offset + 3] = bytes((value, value, value))

    # One PDF point is ten pixels at 720 dpi. PDF user space is bottom-left,
    # while PPM rows are top-left. All fixture edges therefore land exactly on
    # pixel boundaries and need no antialiasing tolerance.
    fill(0, 90, 10, 100, 128)
    fill(60, 10, 70, 15, 0)
    fill(70, 10, 80, 15, 64)
    fill(60, 15, 70, 20, 128)
    fill(70, 15, 80, 20, 255)
    return Raster(WIDTH, HEIGHT, bytes(pixels))


def assert_expected(label: str, actual: Raster, expected: Raster) -> None:
    require((actual.width, actual.height) == (expected.width, expected.height), f"{label}: dimensions differ")
    if actual.pixels == expected.pixels:
        return
    difference = next(index for index, pair in enumerate(zip(actual.pixels, expected.pixels)) if pair[0] != pair[1])
    pixel = difference // 3
    x = pixel % actual.width
    y = pixel // actual.width
    channel = ("red", "green", "blue")[difference % 3]
    raise SystemExit(
        f"{label}: independent raster differs at ({x}, {y}) {channel}: "
        f"expected {expected.pixels[difference]}, got {actual.pixels[difference]}"
    )


def compile_pdfbox_renderer(classes: Path) -> None:
    subprocess.run(
        [
            "javac",
            "-Xlint:all",
            "-Werror",
            "-encoding",
            "UTF-8",
            "-cp",
            str(PDFBOX_JAR),
            "-d",
            str(classes),
            str(PDFBOX_SOURCE),
        ],
        cwd=ROOT,
        check=True,
    )


def render_pdfbox(classes: Path, output: Path) -> None:
    subprocess.run(
        [
            "java",
            "-Djava.awt.headless=true",
            "-cp",
            f"{classes}{os.pathsep}{PDFBOX_JAR}",
            "PdfBoxRender",
            str(SNAPSHOT),
            str(output),
        ],
        cwd=ROOT,
        check=True,
    )


def render_pdfium(renderer: Path, output: Path, working_directory: Path | None) -> None:
    subprocess.run(
        [str(renderer), str(SNAPSHOT), str(output)],
        cwd=working_directory or ROOT,
        check=True,
    )


def check_renderers(renderer: Path, working_directory: Path | None) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    expected = expected_raster()
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate2-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        pdfbox_output = temporary / "pdfbox.ppm"
        pdfium_output = temporary / "pdfium.ppm"
        compile_pdfbox_renderer(classes)
        render_pdfbox(classes, pdfbox_output)
        render_pdfium(renderer, pdfium_output, working_directory)
        pdfbox = read_ppm(pdfbox_output)
        pdfium = read_ppm(pdfium_output)
        assert_expected("PDFBox 3.0.8", pdfbox, expected)
        assert_expected("PDFium Chromium 7988", pdfium, expected)
        require(pdfbox == pdfium, "PDFium and PDFBox rasters differ despite zero declared tolerance")
    print(
        "PASS Gate 2 renderers: PDFium Chromium 7988 and PDFBox 3.0.8 "
        "match the independent 100x100 raster with zero pixel/channel tolerance"
    )


def self_test() -> None:
    expected = expected_raster()
    require(len(expected.pixels) == WIDTH * HEIGHT * 3, "independent raster length is wrong")
    require(expected.pixels[(95 * WIDTH + 5) * 3] == 128, "path expectation is wrong")
    require(expected.pixels[(12 * WIDTH + 65) * 3] == 0, "image black-cell expectation is wrong")
    require(expected.pixels[(12 * WIDTH + 75) * 3] == 64, "image dark-cell expectation is wrong")
    require(expected.pixels[(17 * WIDTH + 65) * 3] == 128, "image gray-cell expectation is wrong")
    require(expected.pixels[(17 * WIDTH + 75) * 3] == 255, "image white-cell expectation is wrong")
    mutation = bytearray(expected.pixels)
    mutation[(50 * WIDTH + 50) * 3] = 254
    try:
        assert_expected("negative twin", Raster(WIDTH, HEIGHT, bytes(mutation)), expected)
    except SystemExit:
        pass
    else:
        raise SystemExit("renderer checker accepted a one-channel negative twin")
    print("PASS Gate 2 renderer checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.pdfium_renderer is not None, "--pdfium-renderer is required unless --self-test is used")
    check_renderers(args.pdfium_renderer.resolve(), args.pdfium_working_directory)


if __name__ == "__main__":
    main()
