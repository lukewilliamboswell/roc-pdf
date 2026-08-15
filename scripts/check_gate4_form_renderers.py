#!/usr/bin/env python3
"""Pinned renderer and extraction evidence for the Gate 4 Form XObject fixtures.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes. Every vector fixture uses integer-point axis-aligned gray fills, so its
100x100 raster at 72 dpi is constructed independently from the typed scenario
and compared with zero pixel and zero channel tolerance in both renderers:

- the showcase (nested forms, shared visuals under distinct semantic and
  artifact owners, interleaved ordinary content) renders exactly;
- 1000 repeated placements of one artifact form render at each declared
  transform;
- the nested DAG renders each parent's shared bases and its own marker.

The text fixture paints the same shaped run as the Gate 3 text fixture inside
a meaningful form, so it must reproduce the Gate 3 ink metrics within the same
declared tolerances, and PDFBox text extraction must return exactly the
logical text; the artifact-only showcase must extract nothing.

The deep-chain fixture records a version-scoped tool limitation: PDFium 7988
stops expanding nested form XObjects at depth 40 and PDFBox 3.0.8 at depth 50
(logging "recursion is too deep"), well below the fixture's legal depth of 64.
The checker asserts each renderer paints the chain exactly to its pinned
depth, so an upgrade that changes either limit is caught explicitly.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from check_gate2_renderers import Raster, read_ppm

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "gate4_forms" / "snapshot.pdf"
REPEAT_SNAPSHOT = ROOT / "tests" / "gate4_forms_repeat_1000" / "snapshot.pdf"
DAG_SNAPSHOT = ROOT / "tests" / "gate4_forms_dag_8" / "snapshot.pdf"
DEEP_SNAPSHOT = ROOT / "tests" / "gate4_forms_deep_64" / "snapshot.pdf"
TEXT_SNAPSHOT = ROOT / "tests" / "gate4_form_text" / "snapshot.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
RENDER_SOURCE = ROOT / "scripts" / "PdfBoxRender.java"
EXTRACT_SOURCE = ROOT / "scripts" / "PdfBoxTextExtract.java"
SIZE = 100

## The Gate 3 visible-text expectations apply unchanged because the fixture
## paints the identical shaped run at the identical placement, only inside a
## form invocation.
@dataclass(frozen=True)
class InkMetrics:
    bounds: tuple[int, int, int, int]
    changed_pixels: int
    dark_pixels: int
    ink: int


PDFBOX_TEXT_EXPECTED = InkMetrics(bounds=(72, 133, 120, 142), changed_pixels=241, dark_pixels=100, ink=29490)
PDFIUM_TEXT_EXPECTED = InkMetrics(bounds=(72, 133, 120, 142), changed_pixels=313, dark_pixels=109, ink=31149)
BOUNDS_TOLERANCE = 2
CHANGED_PIXELS_TOLERANCE = 60
DARK_PIXELS_TOLERANCE = 40
INK_TOLERANCE = 6000
PDFIUM_DEEP_REACH = 39
PDFBOX_DEEP_REACH = 49



def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


class Expectation:
    def __init__(self) -> None:
        self.pixels = bytearray((255, 255, 255)) * (SIZE * SIZE)

    def fill(self, left: int, bottom: int, width: int, height: int, value: int) -> None:
        for y in range(bottom, bottom + height):
            row = SIZE - 1 - y
            for x in range(left, left + width):
                offset = (row * SIZE + x) * 3
                self.pixels[offset : offset + 3] = bytes((value, value, value))

    def image(self, left: int, bottom: int) -> None:
        ## The 2x2 gray fixture image stretched to 20x10 points: four 10x5
        ## cells in source row order, top row first.
        self.fill(left, bottom + 5, 10, 5, 0)
        self.fill(left + 10, bottom + 5, 10, 5, 64)
        self.fill(left, bottom, 10, 5, 128)
        self.fill(left + 10, bottom, 10, 5, 255)

    def raster(self) -> Raster:
        return Raster(SIZE, SIZE, bytes(self.pixels))


def showcase_expectation() -> Raster:
    exp = Expectation()
    exp.fill(0, 90, 20, 10, 64)      # semantic B placement, first painted
    exp.fill(40, 90, 10, 10, 32)     # ordinary page path inside the artifact group
    exp.fill(0, 75, 10, 10, 128)     # artifact form A, first placement
    exp.fill(15, 75, 10, 10, 128)    # artifact form A, second placement
    exp.image(60, 90)                # ordinary page image placement
    exp.fill(30, 75, 20, 10, 64)     # second semantic B placement
    exp.fill(20, 60, 10, 10, 192)    # nested D via semantic form C
    exp.image(0, 60)                 # image painted inside form C
    exp.fill(60, 75, 20, 10, 64)     # artifact placement of the B visual
    exp.image(0, 45)                 # image painted inside artifact form E
    exp.fill(20, 45, 10, 10, 192)    # nested D via artifact form E
    exp.fill(0, 30, 20, 10, 64)      # split occurrence, first placement
    exp.fill(30, 30, 20, 10, 64)     # split occurrence, second placement
    return exp.raster()


def repeat_expectation() -> Raster:
    exp = Expectation()
    exp.fill(0, 95, 4, 4, 32)        # the meaningful anchor path
    for column in range(10):
        for row in range(9):
            exp.fill(column * 10, row * 10, 4, 4, 128)
    return exp.raster()


def dag_expectation(parents: int) -> Raster:
    exp = Expectation()
    exp.fill(0, 95, 4, 4, 32)
    for parent in range(parents):
        left = (parent % 10) * 10
        bottom = ((parent // 10) % 8 + 1) * 10
        exp.fill(left, bottom, 2, 2, 32)              # base S0
        exp.fill(left + 2, bottom, 2, 1, 64)          # base S1
        exp.fill(left + 4, bottom, 1, 2, 96)          # base S2
        exp.fill(left + 7, bottom, 1, 2, 128)         # base S3
        exp.fill(left + parent % 10, bottom + 3, 1, 1, (parent // 10 + 1) * 16)
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


def ink_metrics(raster: Raster) -> InkMetrics:
    require((raster.width, raster.height) == (595, 842), "text raster is not exact A4 at 72 dpi")
    points: list[tuple[int, int]] = []
    dark_pixels = 0
    ink = 0
    for index in range(0, len(raster.pixels), 3):
        red, green, blue = raster.pixels[index : index + 3]
        require(red == green == blue, "black text produced a non-gray pixel")
        if red != 255:
            pixel = index // 3
            points.append((pixel % raster.width, pixel // raster.width))
            ink += 255 - red
            if red < 128:
                dark_pixels += 1
    require(bool(points), "text raster is blank")
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return InkMetrics((min(xs), min(ys), max(xs), max(ys)), len(points), dark_pixels, ink)


def assert_close(label: str, actual: InkMetrics, expected: InkMetrics) -> None:
    require(
        all(abs(a - e) <= BOUNDS_TOLERANCE for a, e in zip(actual.bounds, expected.bounds)),
        f"{label}: ink bounds {actual.bounds} exceed ±{BOUNDS_TOLERANCE} from {expected.bounds}",
    )
    require(
        abs(actual.changed_pixels - expected.changed_pixels) <= CHANGED_PIXELS_TOLERANCE,
        f"{label}: changed pixels {actual.changed_pixels} exceed ±{CHANGED_PIXELS_TOLERANCE} from {expected.changed_pixels}",
    )
    require(
        abs(actual.dark_pixels - expected.dark_pixels) <= DARK_PIXELS_TOLERANCE,
        f"{label}: dark pixels {actual.dark_pixels} exceed ±{DARK_PIXELS_TOLERANCE} from {expected.dark_pixels}",
    )
    require(
        abs(actual.ink - expected.ink) <= INK_TOLERANCE,
        f"{label}: ink {actual.ink} exceeds ±{INK_TOLERANCE} from {expected.ink}",
    )


def deep_reach(raster: Raster) -> int:
    ## The chain's step squares advance one point right and up per nesting
    ## level, so the highest inked near-diagonal coordinate is the rendered
    ## depth.
    reach = -1
    for index in range(0, len(raster.pixels), 3):
        if raster.pixels[index] != 255:
            pixel = index // 3
            x = pixel % raster.width
            y = raster.height - 1 - pixel // raster.width
            if abs(x - y) <= 1 and x > reach:
                reach = x
    return reach


def compile_java(classes: Path) -> None:
    subprocess.run(
        ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(RENDER_SOURCE), str(EXTRACT_SOURCE)],
        cwd=ROOT,
        check=True,
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


def extract_text(classes: Path, snapshot: Path) -> str:
    result = subprocess.run(
        ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(snapshot)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return result.stdout.decode("utf-8")


def check_renderers(renderer: Path, working_directory: Path | None) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-gate4-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        for name, snapshot, expected in (
            ("showcase", SHOWCASE_SNAPSHOT, showcase_expectation()),
            ("repeat-1000", REPEAT_SNAPSHOT, repeat_expectation()),
            ("dag-8", DAG_SNAPSHOT, dag_expectation(8)),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, name)
            assert_exact(f"PDFium Chromium 7988 {name}", pdfium, expected)
            assert_exact(f"PDFBox 3.0.8 {name}", pdfbox, expected)

        pdfium_text, pdfbox_text = render_both(renderer, working_directory, classes, TEXT_SNAPSHOT, temporary, "text")
        pdfium_metrics = ink_metrics(pdfium_text)
        pdfbox_metrics = ink_metrics(pdfbox_text)
        assert_close("PDFium Chromium 7988 text-in-form", pdfium_metrics, PDFIUM_TEXT_EXPECTED)
        assert_close("PDFBox 3.0.8 text-in-form", pdfbox_metrics, PDFBOX_TEXT_EXPECTED)
        require(
            all(abs(a - e) <= BOUNDS_TOLERANCE for a, e in zip(pdfium_metrics.bounds, pdfbox_metrics.bounds)),
            "PDFium and PDFBox text geometry disagrees beyond the declared tolerance",
        )

        extracted = extract_text(classes, TEXT_SNAPSHOT)
        require(extracted.strip() == "Café PDF", f"text-in-form extraction returned {extracted!r}")
        artifact_only = extract_text(classes, SHOWCASE_SNAPSHOT)
        require(artifact_only.strip() == "", f"artifact-only fixture extracted {artifact_only!r}")

        pdfium_deep, pdfbox_deep = render_both(renderer, working_directory, classes, DEEP_SNAPSHOT, temporary, "deep")
        require(
            deep_reach(pdfium_deep) == PDFIUM_DEEP_REACH,
            f"PDFium nested-form depth reach changed from the pinned {PDFIUM_DEEP_REACH}",
        )
        require(
            deep_reach(pdfbox_deep) == PDFBOX_DEEP_REACH,
            f"PDFBox nested-form depth reach changed from the pinned {PDFBOX_DEEP_REACH}",
        )
    print(
        "PASS Gate 4 form renderers: PDFium Chromium 7988 and PDFBox 3.0.8 match the independent "
        "showcase/repeat/DAG rasters exactly, reproduce the Gate 3 text metrics inside a form, "
        "extract the logical text, and hold their pinned nested-form depth limits"
    )


def self_test() -> None:
    showcase = showcase_expectation()
    require(len(showcase.pixels) == SIZE * SIZE * 3, "showcase expectation has wrong size")
    require(showcase.pixels[((SIZE - 1 - 95) * SIZE + 5) * 3] == 64, "showcase B expectation is wrong")
    require(showcase.pixels[((SIZE - 1 - 62) * SIZE + 25) * 3] == 192, "showcase nested D expectation is wrong")
    require(showcase.pixels[((SIZE - 1 - 97) * SIZE + 65) * 3] == 0, "showcase image cell expectation is wrong")
    repeat = repeat_expectation()
    require(repeat.pixels[((SIZE - 1 - 81) * SIZE + 91) * 3] == 128, "repeat grid expectation is wrong")
    dag = dag_expectation(8)
    require(dag.pixels[((SIZE - 1 - 13) * SIZE + 22) * 3] == 16, "dag marker expectation is wrong")
    require(dag.pixels[((SIZE - 1 - 10) * SIZE + 37) * 3] == 128, "dag base expectation is wrong")

    mutation = bytearray(showcase.pixels)
    mutation[(50 * SIZE + 50) * 3] = 254
    try:
        assert_exact("negative twin", Raster(SIZE, SIZE, bytes(mutation)), showcase)
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 renderer checker accepted a one-channel negative twin")
    try:
        assert_close(
            "negative twin",
            InkMetrics(
                bounds=(PDFIUM_TEXT_EXPECTED.bounds[0] + BOUNDS_TOLERANCE + 1, *PDFIUM_TEXT_EXPECTED.bounds[1:]),
                changed_pixels=PDFIUM_TEXT_EXPECTED.changed_pixels,
                dark_pixels=PDFIUM_TEXT_EXPECTED.dark_pixels,
                ink=PDFIUM_TEXT_EXPECTED.ink,
            ),
            PDFIUM_TEXT_EXPECTED,
        )
    except SystemExit:
        pass
    else:
        raise SystemExit("Gate 4 renderer checker accepted out-of-bounds text metrics")
    print("PASS Gate 4 form renderer checker self-test")


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
