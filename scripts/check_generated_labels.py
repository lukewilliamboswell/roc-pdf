#!/usr/bin/env python3
"""Original-byte checks for the text-layout generated-list-label slice."""

from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from check_facade_output import validate_facade_output_pdf
from check_text_renderers import InkMetrics, assert_geometry_agreement, compile_pdfbox_renderer, ink_metrics
from check_text import PDFBOX_JAR, PDFBOX_SOURCE
from check_visual_renderers import read_ppm
from check_pdf_structure import ValidationError, object_slices, require


ROOT = Path(__file__).resolve().parents[1]
SELF_TEST_SNAPSHOT = ROOT / "tests" / "generated_label" / "generated_label.pdf"
DIRECT_TEXT = "•First•Second"
PDFBOX_TEXT = "• First\n• Second\n"
PDFBOX_METRICS = InkMetrics(bounds=(73, 74, 128, 97), changed_pixels=340, dark_pixels=164, ink=41648)
PDFIUM_METRICS = InkMetrics(bounds=(72, 74, 128, 97), changed_pixels=458, dark_pixels=175, ink=44607)


def validate_generated_labels_pdf(pdf: bytes) -> None:
    validate_facade_output_pdf(pdf, DIRECT_TEXT)
    _, bodies = object_slices(pdf)
    require(sum(b"/S /L " in body for body in bodies.values()) == 1, "generated-label PDF does not contain one list structure element")
    require(sum(b"/S /LI " in body for body in bodies.values()) == 2, "generated-label PDF does not contain two list-item structure elements")
    require(sum(b"/S /Lbl " in body for body in bodies.values()) == 2, "generated-label PDF does not contain two label structure elements")
    require(sum(b"/S /LBody " in body for body in bodies.values()) == 2, "generated-label PDF does not contain two list-body structure elements")


def check_pdfbox_extraction(pdf: Path) -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-generated-label-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(PDFBOX_SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0, compiled.stderr.decode(errors="replace") or "PDFBox extractor compilation failed")
        require(not compiled.stdout and not compiled.stderr, "PDFBox extractor compilation produced diagnostics")
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxTextExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0, result.stderr.decode(errors="replace") or "PDFBox extraction failed")
        require(not result.stderr, f"PDFBox extraction wrote diagnostics: {result.stderr!r}")
        require(result.stdout == PDFBOX_TEXT.encode(), f"PDFBox extracted {result.stdout!r}, expected {PDFBOX_TEXT.encode()!r}")
    print("PASS text-layout generated labels PDFBox 3.0.8 extraction: exact logical labels and bodies")


def check_renderers(renderer: Path, working_directory: Path | None, pdf: Path) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-generated-label-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        pdfbox_output = temporary / "pdfbox.ppm"
        pdfium_output = temporary / "pdfium.ppm"
        compile_pdfbox_renderer(classes)
        subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxRender", str(pdf), str(pdfbox_output), "72"],
            cwd=ROOT,
            check=True,
        )
        subprocess.run([str(renderer), str(pdf), str(pdfium_output), "1"], cwd=working_directory or ROOT, check=True)
        pdfbox = ink_metrics(read_ppm(pdfbox_output))
        pdfium = ink_metrics(read_ppm(pdfium_output))
        require(pdfbox == PDFBOX_METRICS, f"PDFBox metrics changed: {pdfbox!r}, expected {PDFBOX_METRICS!r}")
        require(pdfium == PDFIUM_METRICS, f"PDFium metrics changed: {pdfium!r}, expected {PDFIUM_METRICS!r}")
        assert_geometry_agreement(pdfium, pdfbox)
    print("PASS text-layout generated-label renderers: independently pinned exact 72-dpi PDFBox and PDFium metrics")


def self_test() -> None:
    pdf = SELF_TEST_SNAPSHOT.read_bytes()
    validate_generated_labels_pdf(pdf)
    mutation = pdf.replace(b"<2022>", b"<002D>", 1)
    require(mutation != pdf, "generated-label self-test fixture does not contain the bullet ToUnicode row")
    try:
        validate_generated_labels_pdf(mutation)
    except ValidationError:
        pass
    else:
        raise SystemExit("text-layout generated-label checker accepted an atomic bullet-mapping negative")
    print("PASS text-layout generated-label structural checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--pdfbox-extraction", action="store_true")
    parser.add_argument("--pdfium-renderer", type=Path)
    parser.add_argument("--pdfium-working-directory", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.pdf is None:
        parser.error("pdf is required unless --self-test is used")
    pdf = args.pdf.resolve()
    validate_generated_labels_pdf(pdf.read_bytes())
    print(f"PASS text-layout generated-label structure, typed list ownership, CID, and ToUnicode checks: {pdf}")
    if args.pdfbox_extraction:
        check_pdfbox_extraction(pdf)
    if args.pdfium_renderer is not None:
        check_renderers(args.pdfium_renderer.resolve(), args.pdfium_working_directory, pdf)


if __name__ == "__main__":
    main()
