#!/usr/bin/env python3
"""production-visual navigation renderer and independent-processor evidence.

This lane proves interoperability, not correctness — the structural checker
remains the primary oracle. With the pinned engines it proves that:

- PDFBox 3.0.8 navigates every emitted link through the geometric `/D`
  fallback alone: the extracted per-annotation reports (rect, quad count,
  resolved destination page and `/XYZ` coordinates, URI) equal the pinned
  expectations exactly, for the kernel showcase and for the facade document
  whose long link fragments across the page break. PDFBox never reads
  `/SD`, so this is exactly the pinned issue-140 fallback evidence;
  structure-destination support is inspected structurally, not assumed
  interoperable.
- PDFBox expands the `/PageLabels` number tree into the pinned per-page
  label sequences, including Roman, prefixed-decimal, and prefix-only
  ranges.
- PDFBox resolves outline entries through the named-destination name tree
  to the pinned pages (`findNamedDestinationPage`), and MuPDF 1.28.2 lists
  the same outline with its `#nameddest=` targets.
- PDFBox composites the normal appearance stream of every link that carries
  one: the appearance's inset paint reads the pinned darker code inside the
  annotation rectangle while the page's own paint shows at the inset
  border. The pinned PDFium adapter renders page content without the
  annotation layer (it does not pass FPDF_ANNOT), which is recorded as
  adapter behavior, not a defect.
- MuPDF renders every page of the multi-page fixtures and extracts the
  facade text unchanged.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from check_visual_renderers import Raster, read_ppm

ROOT = Path(__file__).resolve().parents[1]
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
RENDER_SOURCE = ROOT / "scripts" / "PdfBoxRender.java"
EXTRACT_SOURCE = ROOT / "scripts" / "PdfBoxTextExtract.java"
NAVIGATE_SOURCE = ROOT / "scripts" / "PdfBoxNavigate.java"

SHOWCASE = ROOT / "tests" / "navigation" / "navigation.pdf"
APPEARANCE = ROOT / "tests" / "navigation" / "navigation_appearance_16.pdf"
LABELS = ROOT / "tests" / "navigation" / "navigation_labels_8.pdf"
FACADE = ROOT / "tests" / "navigation" / "navigation_facade.pdf"

SHOWCASE_REPORT = """annot page=0 rect=10,44,70,66 quads=2 goto=1 left=10 top=42
annot page=0 rect=10,68,70,78 quads=1 uri=https://example.org/reference?section=1&lang=en
annot page=1 rect=10,32,70,42 quads=1 goto=0 left=10 top=90
label page=0 text=i
label page=1 text=A-5
outline depth=0 page=0 title=Introduction
outline depth=1 page=1 title=Results detail
outline depth=0 page=1 title=Findings
"""

FACADE_REPORT = """annot page=0 rect=72,672,194,686 quads=1 uri=https://www.ala.org.au/species?q=acacia&page=1
annot page=1 rect=72,82,518,110 quads=2 goto=0 left=72 top=734
annot page=2 rect=72,742,507,770 quads=2 goto=0 left=72 top=734
annot page=2 rect=72,672,150,686 quads=1 goto=2 left=72 top=734
label page=0 text=i
label page=1 text=2
label page=2 text=3
outline depth=0 page=0 title=Overview
outline depth=1 page=2 title=Results
"""

LABELS_REPORT = """label page=0 text=1
label page=1 text=S-I
label page=2 text=Annex 
label page=3 text=4
label page=4 text=S-I
label page=5 text=Annex 
label page=6 text=7
label page=7 text=S-I
"""

SHOWCASE_MUTOOL_OUTLINE = """-\t"Introduction"\t#nameddest=intro
|\t\t"Results detail"\t#nameddest=results
|\t"Findings"\t#nameddest=results
"""

FACADE_MUTOOL_OUTLINE = """-\t"Overview"\t#nameddest=overview
|\t\t"Results"\t#nameddest=results
"""

## CalGray paint through PDFBox's direct gray mapping: the appearance's
## 8224/65535 inset paints 32 and the page fragment's 24672/65535 paints 96.
APPEARANCE_INSIDE = (32, 32, 32)
APPEARANCE_BORDER = (96, 96, 96)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"navigation renderer evidence failed: {message}")


def compile_java(classes: Path) -> None:
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
            str(RENDER_SOURCE),
            str(EXTRACT_SOURCE),
            str(NAVIGATE_SOURCE),
        ],
        cwd=ROOT,
        check=True,
    )


def java(classes: Path, tool: str, *arguments: str) -> bytes:
    result = subprocess.run(
        [
            "java",
            "-Djava.awt.headless=true",
            "-cp",
            f"{classes}{os.pathsep}{PDFBOX_JAR}",
            tool,
            *arguments,
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return result.stdout


def at(raster: Raster, x: int, y: int) -> tuple[int, int, int]:
    index = ((raster.height - 1 - y) * raster.width + x) * 3
    return tuple(raster.pixels[index : index + 3])


def check_navigation_reports(classes: Path) -> None:
    for snapshot, expected, label in (
        (SHOWCASE, SHOWCASE_REPORT, "showcase"),
        (FACADE, FACADE_REPORT, "facade"),
        (LABELS, LABELS_REPORT, "labels"),
    ):
        report = java(classes, "PdfBoxNavigate", str(snapshot)).decode("utf-8")
        require(
            report == expected,
            f"{label} navigation report diverged:\n{report}",
        )


def check_appearances(classes: Path, renderer: Path | None, working_directory: Path | None, temporary: Path) -> None:
    output = temporary / "appearance-pdfbox.ppm"
    subprocess.run(
        [
            "java",
            "-Djava.awt.headless=true",
            "-cp",
            f"{classes}{os.pathsep}{PDFBOX_JAR}",
            "PdfBoxRender",
            str(APPEARANCE),
            str(output),
            "72",
        ],
        cwd=ROOT,
        check=True,
    )
    raster = read_ppm(output)
    require(raster.width == 100 and raster.height == 100, "appearance raster size")
    for slot in range(6):
        y_base = 80 - 12 * slot
        require(
            at(raster, 40, y_base + 5) == APPEARANCE_INSIDE,
            f"appearance inset did not composite at row {slot}",
        )
        require(
            at(raster, 11, y_base + 1) == APPEARANCE_BORDER,
            f"page paint missing at the appearance border, row {slot}",
        )
    if renderer is not None:
        pdfium_output = temporary / "appearance-pdfium.ppm"
        subprocess.run(
            [str(renderer), str(APPEARANCE), str(pdfium_output), "1"],
            cwd=working_directory or ROOT,
            check=True,
        )
        pdfium = read_ppm(pdfium_output)
        require(
            at(pdfium, 40, 85) == APPEARANCE_BORDER,
            "pinned adapter behavior changed: the PDFium adapter renders "
            "page content without the annotation layer",
        )


def check_mutool(mutool: Path, temporary: Path) -> None:
    for snapshot, expected, label in (
        (SHOWCASE, SHOWCASE_MUTOOL_OUTLINE, "showcase"),
        (FACADE, FACADE_MUTOOL_OUTLINE, "facade"),
    ):
        result = subprocess.run(
            [str(mutool), "show", str(snapshot), "outline"],
            cwd=ROOT,
            check=True,
            capture_output=True,
        )
        require(
            result.stdout.decode("utf-8") == expected,
            f"mutool outline listing diverged for the {label}",
        )
    for page in (1, 2, 3):
        output = temporary / f"facade-p{page}.ppm"
        subprocess.run(
            [str(mutool), "draw", "-q", "-r", "72", "-c", "rgb", "-o", str(output), str(FACADE), str(page)],
            cwd=ROOT,
            check=True,
        )
        raster = read_ppm(output)
        ink = sum(
            1
            for index in range(0, len(raster.pixels), 3)
            if raster.pixels[index] < 128
        )
        require(ink > 500, f"facade page {page} rendered without ink")
    text = subprocess.run(
        [str(mutool), "draw", "-q", "-F", "txt", "-o", "-", str(FACADE), "1"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8")
    require("Atlas of Living Australia" in text, "facade link text missing from extraction")
    require("Overview" in text, "facade heading text missing from extraction")


def run_matrix(renderer: Path | None, working_directory: Path | None, mutool: Path | None) -> None:
    with tempfile.TemporaryDirectory() as raw:
        temporary = Path(raw)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)
        check_navigation_reports(classes)
        check_appearances(classes, renderer, working_directory, temporary)
        if mutool is not None:
            check_mutool(mutool, temporary)
    tail = (
        "PDFBox /D navigation, page labels, named-destination outlines, and composited appearances"
        + ("; MuPDF outline listing, multi-page rendering, and extraction" if mutool is not None else "")
    )
    print(f"PASS production-visual navigation renderer evidence: {tail}", flush=True)


def self_test() -> None:
    for snapshot in (SHOWCASE, APPEARANCE, LABELS, FACADE):
        pdf = snapshot.read_bytes()
        require(pdf.count(b"/Subtype /Link") >= 1 or snapshot == LABELS, "snapshot lost its links")
    require(SHOWCASE_REPORT.count("annot") == 3, "showcase report shape")
    require(FACADE_REPORT.count("annot") == 4, "facade report shape")
    require(
        FACADE_REPORT.count("goto=0 left=72 top=734") == 2
        and FACADE_REPORT.count("page=1 rect=") + FACADE_REPORT.count("page=2 rect=") == 3,
        "facade split-link pins",
    )
    require(LABELS_REPORT.count("label") == 8, "labels report shape")
    require(APPEARANCE_INSIDE < APPEARANCE_BORDER, "appearance pins must darken inside")
    print(
        "PASS production-visual navigation renderer checker self-test: pinned navigation "
        "reports, label sequences, outline listings, and appearance codes are "
        "internally consistent",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--mutool", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    run_matrix(arguments.pdfium_renderer, arguments.pdfium_working_directory, arguments.mutool)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
