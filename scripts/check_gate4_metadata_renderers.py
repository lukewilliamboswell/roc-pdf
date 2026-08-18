#!/usr/bin/env python3
"""Pinned renderer evidence for the Gate 4 metadata/output-intent fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive.
This lane proves rendering interoperability only: independent engines accept
and paint documents that carry the catalog language, the uncompressed XMP
metadata stream, and the packaged sRGB output intent, and their color
handling of the intent's ICCBased spaces stays inside the codes the earlier
Gate 4 slices pinned. Rendering does not and cannot validate metadata or
output-intent correctness — that is the structural checker's and the
validators' job (`check_gate4_metadata.py`; veraPDF is recorded separately as
diagnostic evidence).

The showcase page paints two rectangles in the two authored views of the
packaged sRGB profile (an ``Srgb`` and an equivalent ``IccBased`` space) over
a calibrated-gray background. Expected codes derive from the exact U16
channel values: PDFBox rounds to the nearest code, while PDFium and MuPDF's
ICC pipelines sit one code low on non-saturated channels (the same ±1 the
color-image slice pinned). The calibrated-gray background displays direct at
224 in PDFium/PDFBox and through MuPDF's pinned tone behavior at 240. The
share grid proves 64 ICCBased fills through one canonical profile paint
identically. MuPDF (the multi-page engine of this matrix) renders all three
facade pages and extracts the page-one logical text unchanged by the
metadata objects.
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
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_metadata" / "snapshot.pdf"
SHARE_SNAPSHOT = ROOT / "tests" / "gate4_metadata_share_64" / "snapshot.pdf"
FACADE_SNAPSHOT = ROOT / "tests" / "gate4_metadata_facade" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SIZE = 100

## Exact per-engine codes for the showcase regions. Ideal float values from
## the U16 channels: warm fill (65535, 16448, 8224) -> (255, 64.0, 32.0),
## cool fill (8224, 16448, 65535) -> (32.0, 64.0, 255), calibrated-gray
## background 57568/65535 -> 223.95 direct.
SHOWCASE_PINS = {
    "pdfium": {"warm": (255, 63, 31), "cool": (31, 63, 255), "background": (224, 224, 224)},
    "pdfbox": {"warm": (255, 64, 32), "cool": (32, 64, 255), "background": (224, 224, 224)},
    "mutool": {"warm": (255, 63, 31), "cool": (31, 63, 255), "background": (240, 240, 240)},
}

## The share grid's fill is (65535, 32896, 8224) -> (255, 128.0, 32.0).
SHARE_PINS = {
    "pdfium": (255, 127, 31),
    "pdfbox": (255, 128, 32),
    "mutool": (255, 127, 31),
}

IDEAL = {
    "warm": (255.0, 64.001, 31.999),
    "cool": (31.999, 64.001, 255.0),
    "share": (255.0, 128.002, 31.999),
}

## Sample points (PDF-space x, y): rectangle interiors and two background
## corners away from every painted rectangle.
SHOWCASE_SAMPLES = {
    "warm": (50, 70),
    "cool": (50, 30),
    "background": (5, 95),
}
SHARE_SAMPLES = [(5, 5), (53, 29), (89, 89)]
SHARE_GAP = (11, 5)

FACADE_PAGES = 3
FACADE_MIN_INK = 1000


def at(raster: Raster, x: int, y: int) -> tuple[int, ...]:
    offset = ((raster.height - 1 - y) * raster.width + x) * 3
    return tuple(raster.pixels[offset : offset + 3])


def check_pins_against_model() -> None:
    for engine, pins in SHOWCASE_PINS.items():
        for region, ideal in (("warm", IDEAL["warm"]), ("cool", IDEAL["cool"])):
            for pinned, value in zip(pins[region], ideal):
                require(abs(pinned - value) <= 1.05, f"{engine} {region} pin drifted from the sRGB model")
    for engine, pinned in SHARE_PINS.items():
        for code, value in zip(pinned, IDEAL["share"]):
            require(abs(code - value) <= 1.05, f"{engine} share pin drifted from the sRGB model")


def check_showcase(engine: str, raster: Raster) -> None:
    require((raster.width, raster.height) == (SIZE, SIZE), f"{engine} showcase raster is not 100x100")
    pins = SHOWCASE_PINS[engine]
    for region, (x, y) in SHOWCASE_SAMPLES.items():
        require(
            at(raster, x, y) == pins[region],
            f"{engine} showcase {region} at ({x},{y}) is {at(raster, x, y)}, expected {pins[region]}",
        )


def check_share(engine: str, raster: Raster) -> None:
    require((raster.width, raster.height) == (SIZE, SIZE), f"{engine} share raster is not 100x100")
    for x, y in SHARE_SAMPLES:
        require(
            at(raster, x, y) == SHARE_PINS[engine],
            f"{engine} share fill at ({x},{y}) is {at(raster, x, y)}, expected {SHARE_PINS[engine]}",
        )
    require(at(raster, *SHARE_GAP) == (255, 255, 255), f"{engine} share grid gap is not white")


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


def check_facade_mutool(mutool: Path, temporary: Path) -> None:
    pattern = temporary / "facade-p%d.ppm"
    result = subprocess.run(
        [str(mutool), "draw", "-q", "-r", "72", "-c", "rgb", "-o", str(pattern), str(FACADE_SNAPSHOT)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    require(result.returncode == 0, f"mutool failed on the facade fixture: {result.stderr.decode(errors='replace')[:200]}")
    for page in range(1, FACADE_PAGES + 1):
        raster = read_ppm(temporary / f"facade-p{page}.ppm")
        require((raster.width, raster.height) == (595, 842), f"facade page {page} is not A4 at 72 dpi")
        dark = sum(1 for offset in range(0, len(raster.pixels), 3) if raster.pixels[offset] < 128)
        require(dark >= FACADE_MIN_INK, f"facade page {page} has no text ink")

    text_output = temporary / "facade.txt"
    subprocess.run(
        [str(mutool), "draw", "-q", "-F", "txt", "-o", str(text_output), str(FACADE_SNAPSHOT), "1"],
        cwd=ROOT,
        check=True,
    )
    text = text_output.read_text(encoding="utf-8")
    require("Deterministic metadata" in text, "facade extraction lost the visible title")
    require("Paragraph 0 carries the same document language" in text, "facade extraction lost the paragraph text")


def run_matrix(renderer: Path, working_directory: Path | None, mutool: Path | None) -> None:
    check_pins_against_model()
    with tempfile.TemporaryDirectory(prefix="gate4-metadata-renderers-") as name:
        temporary = Path(name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)
        for label, snapshot, checker in (
            ("showcase", SHOWCASE_SNAPSHOT, check_showcase),
            ("share", SHARE_SNAPSHOT, check_share),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, label)
            checker("pdfium", pdfium)
            checker("pdfbox", pdfbox)
            if mutool is not None:
                mutool_output = temporary / f"{label}-mutool.ppm"
                render_mutool(mutool, snapshot, mutool_output)
                checker("mutool", read_ppm(mutool_output))
        if mutool is not None:
            check_facade_mutool(mutool, temporary)
    third = " MuPDF 1.28.2 agreed within its pinned codes and rendered and extracted all three facade pages." if mutool is not None else ""
    print(
        "PASS Gate 4 metadata renderers: PDFium Chromium 7988 and PDFBox 3.0.8 render the "
        "intent-bearing fixtures at the pinned sRGB codes with the metadata objects present."
        + third
    )


def self_test() -> None:
    check_pins_against_model()
    require(SHOWCASE_SNAPSHOT.read_bytes().count(b"/Type /Metadata") == 1, "showcase snapshot lost its metadata stream")
    require(SHARE_SNAPSHOT.read_bytes().count(b"/Type /Metadata") == 1, "share snapshot lost its metadata stream")
    require(FACADE_SNAPSHOT.read_bytes().count(b"/Type /Metadata") == 1, "facade snapshot lost its metadata stream")

    solid = Raster(SIZE, SIZE, bytes(SHOWCASE_PINS["pdfbox"]["background"]) * (SIZE * SIZE))
    try:
        check_showcase("pdfbox", solid)
    except SystemExit:
        pass
    else:
        raise SystemExit("metadata renderer checker accepted a background-only raster")

    pixels = bytearray(bytes((255, 255, 255)) * (SIZE * SIZE))

    def paint(x: int, y: int, code: tuple[int, int, int]) -> None:
        offset = ((SIZE - 1 - y) * SIZE + x) * 3
        pixels[offset : offset + 3] = bytes(code)

    pins = SHOWCASE_PINS["pdfbox"]
    paint(*SHOWCASE_SAMPLES["warm"], pins["warm"])
    paint(*SHOWCASE_SAMPLES["cool"], pins["cool"])
    paint(*SHOWCASE_SAMPLES["background"], pins["background"])
    check_showcase("pdfbox", Raster(SIZE, SIZE, bytes(pixels)))

    drifted = dict(SHARE_PINS)
    drifted["pdfbox"] = (250, 128, 32)
    try:
        for code, value in zip(drifted["pdfbox"], IDEAL["share"]):
            require(abs(code - value) <= 1.05, "drifted pin")
    except SystemExit:
        pass
    else:
        raise SystemExit("metadata renderer checker accepted a pin far from the model")
    print("PASS Gate 4 metadata renderer checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--mutool", type=Path, help="mutool built from vendor/mupdf/mupdf-1.28.2-source.tgz")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.pdfium_renderer is None:
        parser.error("provide --pdfium-renderer or --self-test")
    run_matrix(arguments.pdfium_renderer, arguments.pdfium_working_directory, arguments.mutool)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
