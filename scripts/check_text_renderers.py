#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from check_visual_renderers import Raster, read_ppm


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "visible_text" / "text.pdf"
CALLER_SNAPSHOT = ROOT / "tests" / "caller_font" / "caller_text.pdf"
ACTUAL_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "actual_text.pdf"
SUPPLEMENTARY_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "supplementary_text.pdf"
CJK_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "cjk_text.pdf"
LIGATURE_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "ligature_text.pdf"
MULTIFACE_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "multiface_text.pdf"
MULTIFACE_FACADE_SNAPSHOT = ROOT / "tests" / "multiface_facade" / "multiface_facade.pdf"
RTL_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "rtl_text.pdf"
CASE_TEXT_SNAPSHOT = ROOT / "tests" / "actual_text" / "case_text.pdf"
SOFT_HYPHEN_SNAPSHOT = ROOT / "tests" / "actual_text" / "soft_hyphen.pdf"
EXTERNAL_DISCRETIONARY_HYPHEN_SNAPSHOT = ROOT / "tests" / "actual_text" / "external_discretionary_hyphen.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
PDFBOX_SOURCE = ROOT / "scripts" / "PdfBoxRender.java"


@dataclass(frozen=True)
class InkMetrics:
    bounds: tuple[int, int, int, int]
    changed_pixels: int
    dark_pixels: int
    ink: int


PDFBOX_EXPECTED = InkMetrics(bounds=(72, 133, 120, 142), changed_pixels=241, dark_pixels=100, ink=29490)
PDFIUM_EXPECTED = InkMetrics(bounds=(72, 133, 120, 142), changed_pixels=313, dark_pixels=109, ink=31149)
PDFBOX_ACTUAL_TEXT_EXPECTED = InkMetrics(bounds=(72, 133, 81, 142), changed_pixels=60, dark_pixels=27, ink=6883)
PDFIUM_ACTUAL_TEXT_EXPECTED = InkMetrics(bounds=(71, 133, 82, 142), changed_pixels=78, dark_pixels=27, ink=7350)
PDFBOX_SUPPLEMENTARY_EXPECTED = InkMetrics(bounds=(72, 133, 81, 142), changed_pixels=65, dark_pixels=30, ink=7884)
PDFIUM_SUPPLEMENTARY_EXPECTED = InkMetrics(bounds=(72, 133, 81, 142), changed_pixels=77, dark_pixels=30, ink=8280)
PDFBOX_CJK_EXPECTED = InkMetrics(bounds=(73, 132, 81, 142), changed_pixels=47, dark_pixels=20, ink=6866)
PDFIUM_CJK_EXPECTED = InkMetrics(bounds=(72, 132, 82, 142), changed_pixels=77, dark_pixels=32, ink=7649)
PDFBOX_LIGATURE_EXPECTED = InkMetrics(bounds=(72, 133, 78, 141), changed_pixels=42, dark_pixels=19, ink=4579)
PDFIUM_LIGATURE_EXPECTED = InkMetrics(bounds=(72, 133, 78, 141), changed_pixels=53, dark_pixels=20, ink=4959)
PDFBOX_MULTIFACE_EXPECTED = InkMetrics(bounds=(72, 132, 95, 142), changed_pixels=130, dark_pixels=52, ink=15844)
PDFIUM_MULTIFACE_EXPECTED = InkMetrics(bounds=(72, 132, 96, 142), changed_pixels=174, dark_pixels=64, ink=17144)
PDFBOX_MULTIFACE_FACADE_EXPECTED = InkMetrics(bounds=(72, 73, 96, 83), changed_pixels=129, dark_pixels=52, ink=15843)
PDFIUM_MULTIFACE_FACADE_EXPECTED = InkMetrics(bounds=(72, 73, 97, 83), changed_pixels=178, dark_pixels=64, ink=17161)
PDFBOX_CASE_EXPECTED = InkMetrics(bounds=(72, 133, 93, 142), changed_pixels=122, dark_pixels=59, ink=14186)
PDFIUM_CASE_EXPECTED = InkMetrics(bounds=(71, 133, 93, 142), changed_pixels=155, dark_pixels=60, ink=15048)
PDFBOX_RTL_EXPECTED = InkMetrics(bounds=(72, 133, 141, 144), changed_pixels=373, dark_pixels=150, ink=39329)
PDFIUM_RTL_EXPECTED = InkMetrics(bounds=(72, 133, 141, 144), changed_pixels=491, dark_pixels=162, ink=43564)
PDFBOX_SOFT_HYPHEN_EXPECTED = InkMetrics(bounds=(72, 134, 131, 144), changed_pixels=271, dark_pixels=118, ink=32548)
PDFIUM_SOFT_HYPHEN_EXPECTED = InkMetrics(bounds=(72, 134, 132, 144), changed_pixels=352, dark_pixels=121, ink=35014)
PDFBOX_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED = InkMetrics(bounds=(72, 134, 90, 142), changed_pixels=82, dark_pixels=36, ink=9433)
PDFIUM_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED = InkMetrics(bounds=(71, 133, 90, 142), changed_pixels=98, dark_pixels=37, ink=10094)
BOUNDS_TOLERANCE = 2
CHANGED_PIXELS_TOLERANCE = 60
DARK_PIXELS_TOLERANCE = 40
INK_TOLERANCE = 6000


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def ink_metrics(raster: Raster) -> InkMetrics:
    require((raster.width, raster.height) == (595, 842), "text-layout text raster is not exact A4 dimensions at 72 dpi")
    points: list[tuple[int, int]] = []
    dark_pixels = 0
    ink = 0
    for index in range(0, len(raster.pixels), 3):
        red, green, blue = raster.pixels[index : index + 3]
        require(red == green == blue, "text-layout black text produced a non-gray raster pixel")
        if red != 255:
            pixel = index // 3
            points.append((pixel % raster.width, pixel // raster.width))
            ink += 255 - red
            if red < 128:
                dark_pixels += 1
    require(bool(points), "text-layout text raster is blank")
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return InkMetrics(
        bounds=(min(xs), min(ys), max(xs), max(ys)),
        changed_pixels=len(points),
        dark_pixels=dark_pixels,
        ink=ink,
    )


def assert_close(label: str, actual: InkMetrics, expected: InkMetrics) -> None:
    require(
        all(abs(actual_value - expected_value) <= BOUNDS_TOLERANCE for actual_value, expected_value in zip(actual.bounds, expected.bounds)),
        f"{label}: ink bounds {actual.bounds} exceed ±{BOUNDS_TOLERANCE} from {expected.bounds}",
    )
    require(
        abs(actual.changed_pixels - expected.changed_pixels) <= CHANGED_PIXELS_TOLERANCE,
        f"{label}: changed-pixel count {actual.changed_pixels} exceeds ±{CHANGED_PIXELS_TOLERANCE} from {expected.changed_pixels}",
    )
    require(
        abs(actual.dark_pixels - expected.dark_pixels) <= DARK_PIXELS_TOLERANCE,
        f"{label}: dark-pixel count {actual.dark_pixels} exceeds ±{DARK_PIXELS_TOLERANCE} from {expected.dark_pixels}",
    )
    require(
        abs(actual.ink - expected.ink) <= INK_TOLERANCE,
        f"{label}: grayscale ink {actual.ink} exceeds ±{INK_TOLERANCE} from {expected.ink}",
    )


def assert_geometry_agreement(pdfium: InkMetrics, pdfbox: InkMetrics) -> None:
    require(
        all(abs(pdfium_value - pdfbox_value) <= BOUNDS_TOLERANCE for pdfium_value, pdfbox_value in zip(pdfium.bounds, pdfbox.bounds)),
        f"PDFium versus PDFBox: ink bounds {pdfium.bounds} exceed ±{BOUNDS_TOLERANCE} from {pdfbox.bounds}",
    )


def compile_pdfbox_renderer(classes: Path) -> None:
    subprocess.run(
        ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
        cwd=ROOT,
        check=True,
    )


def check_renderers(
    renderer: Path,
    working_directory: Path | None,
    snapshot: Path,
    label: str,
    pdfbox_expected: InkMetrics,
    pdfium_expected: InkMetrics,
) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        pdfbox_output = temporary / "pdfbox.ppm"
        pdfium_output = temporary / "pdfium.ppm"
        compile_pdfbox_renderer(classes)
        subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxRender", str(snapshot), str(pdfbox_output), "72"],
            cwd=ROOT,
            check=True,
        )
        subprocess.run(
            [str(renderer), str(snapshot), str(pdfium_output), "1"],
            cwd=working_directory or ROOT,
            check=True,
        )
        pdfbox = ink_metrics(read_ppm(pdfbox_output))
        pdfium = ink_metrics(read_ppm(pdfium_output))
        assert_close("PDFBox 3.0.8", pdfbox, pdfbox_expected)
        assert_close("PDFium Chromium 7988", pdfium, pdfium_expected)
        assert_geometry_agreement(pdfium, pdfbox)
    print(
        f"PASS text-layout {label} renderers: PDFium Chromium 7988 and PDFBox 3.0.8 independently render "
        "visible text within the declared 72-dpi bounds, pixel-count, and grayscale-ink tolerances"
    )


def self_test() -> None:
    assert_close("exact PDFBox synthetic", PDFBOX_EXPECTED, PDFBOX_EXPECTED)
    assert_close("exact PDFium synthetic", PDFIUM_EXPECTED, PDFIUM_EXPECTED)
    assert_close("exact PDFBox ActualText synthetic", PDFBOX_ACTUAL_TEXT_EXPECTED, PDFBOX_ACTUAL_TEXT_EXPECTED)
    assert_close("exact PDFium ActualText synthetic", PDFIUM_ACTUAL_TEXT_EXPECTED, PDFIUM_ACTUAL_TEXT_EXPECTED)
    assert_close("exact PDFBox supplementary synthetic", PDFBOX_SUPPLEMENTARY_EXPECTED, PDFBOX_SUPPLEMENTARY_EXPECTED)
    assert_close("exact PDFium supplementary synthetic", PDFIUM_SUPPLEMENTARY_EXPECTED, PDFIUM_SUPPLEMENTARY_EXPECTED)
    assert_close("exact PDFBox CJK synthetic", PDFBOX_CJK_EXPECTED, PDFBOX_CJK_EXPECTED)
    assert_close("exact PDFium CJK synthetic", PDFIUM_CJK_EXPECTED, PDFIUM_CJK_EXPECTED)
    assert_close("exact PDFBox ligature synthetic", PDFBOX_LIGATURE_EXPECTED, PDFBOX_LIGATURE_EXPECTED)
    assert_close("exact PDFium ligature synthetic", PDFIUM_LIGATURE_EXPECTED, PDFIUM_LIGATURE_EXPECTED)
    assert_close("exact PDFBox multi-face synthetic", PDFBOX_MULTIFACE_EXPECTED, PDFBOX_MULTIFACE_EXPECTED)
    assert_close("exact PDFium multi-face synthetic", PDFIUM_MULTIFACE_EXPECTED, PDFIUM_MULTIFACE_EXPECTED)
    assert_close("exact PDFBox multiface-facade synthetic", PDFBOX_MULTIFACE_FACADE_EXPECTED, PDFBOX_MULTIFACE_FACADE_EXPECTED)
    assert_close("exact PDFium multiface-facade synthetic", PDFIUM_MULTIFACE_FACADE_EXPECTED, PDFIUM_MULTIFACE_FACADE_EXPECTED)
    assert_close("exact PDFBox case synthetic", PDFBOX_CASE_EXPECTED, PDFBOX_CASE_EXPECTED)
    assert_close("exact PDFium case synthetic", PDFIUM_CASE_EXPECTED, PDFIUM_CASE_EXPECTED)
    assert_close("exact PDFBox RTL synthetic", PDFBOX_RTL_EXPECTED, PDFBOX_RTL_EXPECTED)
    assert_close("exact PDFium RTL synthetic", PDFIUM_RTL_EXPECTED, PDFIUM_RTL_EXPECTED)
    assert_close("exact PDFBox soft-hyphen synthetic", PDFBOX_SOFT_HYPHEN_EXPECTED, PDFBOX_SOFT_HYPHEN_EXPECTED)
    assert_close("exact PDFium soft-hyphen synthetic", PDFIUM_SOFT_HYPHEN_EXPECTED, PDFIUM_SOFT_HYPHEN_EXPECTED)
    assert_close("exact PDFBox external discretionary-hyphen synthetic", PDFBOX_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED, PDFBOX_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED)
    assert_close("exact PDFium external discretionary-hyphen synthetic", PDFIUM_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED, PDFIUM_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED)
    assert_geometry_agreement(PDFIUM_EXPECTED, PDFBOX_EXPECTED)
    mutation = InkMetrics(
        bounds=(PDFBOX_EXPECTED.bounds[0] + BOUNDS_TOLERANCE + 1, *PDFBOX_EXPECTED.bounds[1:]),
        changed_pixels=PDFBOX_EXPECTED.changed_pixels,
        dark_pixels=PDFBOX_EXPECTED.dark_pixels,
        ink=PDFBOX_EXPECTED.ink,
    )
    try:
        assert_close("negative twin", mutation, PDFBOX_EXPECTED)
    except SystemExit:
        pass
    else:
        raise SystemExit("text-layout renderer checker accepted an out-of-bounds negative twin")
    geometry_mutation = InkMetrics(
        bounds=(PDFIUM_EXPECTED.bounds[0] + BOUNDS_TOLERANCE + 1, *PDFIUM_EXPECTED.bounds[1:]),
        changed_pixels=PDFIUM_EXPECTED.changed_pixels,
        dark_pixels=PDFIUM_EXPECTED.dark_pixels,
        ink=PDFIUM_EXPECTED.ink,
    )
    try:
        assert_geometry_agreement(geometry_mutation, PDFBOX_EXPECTED)
    except SystemExit:
        pass
    else:
        raise SystemExit("text-layout renderer checker accepted a cross-renderer geometry mismatch")
    print("PASS text-layout renderer checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--caller", action="store_true")
    parser.add_argument("--actual-text", action="store_true")
    parser.add_argument("--supplementary", action="store_true")
    parser.add_argument("--cjk", action="store_true")
    parser.add_argument("--ligature", action="store_true")
    parser.add_argument("--multiface", action="store_true")
    parser.add_argument("--multiface-facade", action="store_true")
    parser.add_argument("--rtl", action="store_true")
    parser.add_argument("--case", action="store_true")
    parser.add_argument("--soft-hyphen", action="store_true")
    parser.add_argument("--external-discretionary-hyphen", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.pdfium_renderer is not None, "--pdfium-renderer is required unless --self-test is used")
    require(sum((args.caller, args.actual_text, args.supplementary, args.cjk, args.ligature, args.multiface, args.multiface_facade, args.rtl, args.case, args.soft_hyphen, args.external_discretionary_hyphen)) <= 1, "renderer fixture selectors are mutually exclusive")
    if args.actual_text:
        snapshot = ACTUAL_TEXT_SNAPSHOT
        label = "reordered ActualText"
        pdfbox_expected = PDFBOX_ACTUAL_TEXT_EXPECTED
        pdfium_expected = PDFIUM_ACTUAL_TEXT_EXPECTED
    elif args.supplementary:
        snapshot = SUPPLEMENTARY_TEXT_SNAPSHOT
        label = "supplementary-plane text"
        pdfbox_expected = PDFBOX_SUPPLEMENTARY_EXPECTED
        pdfium_expected = PDFIUM_SUPPLEMENTARY_EXPECTED
    elif args.cjk:
        snapshot = CJK_TEXT_SNAPSHOT
        label = "CJK text"
        pdfbox_expected = PDFBOX_CJK_EXPECTED
        pdfium_expected = PDFIUM_CJK_EXPECTED
    elif args.ligature:
        snapshot = LIGATURE_TEXT_SNAPSHOT
        label = "parsed fi ligature text"
        pdfbox_expected = PDFBOX_LIGATURE_EXPECTED
        pdfium_expected = PDFIUM_LIGATURE_EXPECTED
    elif args.case:
        snapshot = CASE_TEXT_SNAPSHOT
        label = "case transformation text"
        pdfbox_expected = PDFBOX_CASE_EXPECTED
        pdfium_expected = PDFIUM_CASE_EXPECTED
    elif args.rtl:
        snapshot = RTL_TEXT_SNAPSHOT
        label = "resolved right-to-left text"
        pdfbox_expected = PDFBOX_RTL_EXPECTED
        pdfium_expected = PDFIUM_RTL_EXPECTED
    elif args.multiface_facade:
        snapshot = MULTIFACE_FACADE_SNAPSHOT
        label = "public ordered multi-face facade text"
        pdfbox_expected = PDFBOX_MULTIFACE_FACADE_EXPECTED
        pdfium_expected = PDFIUM_MULTIFACE_FACADE_EXPECTED
    elif args.multiface:
        snapshot = MULTIFACE_TEXT_SNAPSHOT
        label = "ordered multi-face text"
        pdfbox_expected = PDFBOX_MULTIFACE_EXPECTED
        pdfium_expected = PDFIUM_MULTIFACE_EXPECTED
    elif args.soft_hyphen:
        snapshot = SOFT_HYPHEN_SNAPSHOT
        label = "selected soft-hyphen text"
        pdfbox_expected = PDFBOX_SOFT_HYPHEN_EXPECTED
        pdfium_expected = PDFIUM_SOFT_HYPHEN_EXPECTED
    elif args.external_discretionary_hyphen:
        snapshot = EXTERNAL_DISCRETIONARY_HYPHEN_SNAPSHOT
        label = "selected external discretionary-hyphen text"
        pdfbox_expected = PDFBOX_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED
        pdfium_expected = PDFIUM_EXTERNAL_DISCRETIONARY_HYPHEN_EXPECTED
    elif args.caller:
        snapshot = CALLER_SNAPSHOT
        label = "caller-font text"
        pdfbox_expected = PDFBOX_EXPECTED
        pdfium_expected = PDFIUM_EXPECTED
    else:
        snapshot = SNAPSHOT
        label = "built-in text"
        pdfbox_expected = PDFBOX_EXPECTED
        pdfium_expected = PDFIUM_EXPECTED
    check_renderers(
        args.pdfium_renderer.resolve(),
        args.pdfium_working_directory,
        snapshot,
        label,
        pdfbox_expected,
        pdfium_expected,
    )


if __name__ == "__main__":
    main()
