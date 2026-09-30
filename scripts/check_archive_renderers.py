#!/usr/bin/env python3
"""Pinned renderer evidence for static PDF/A-4 (Archive) output.

PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the original snapshot
bytes; ``--mutool`` adds MuPDF 1.28.2 built from the vendored source archive
and renders every page of the multi-page Archive snapshots.

The PDF/A identification is metadata only, so each engine must rasterize an
Archive document and its Standard twin (the same authored document under
``Pdf.Profile.Standard``) to identical pixels: the figures twin carries
opaque, alpha, gray, and JPEG images through the sRGB output intent, and the
navigation twin carries link annotations without appearances. Every Archive
page must render at its A4 geometry, a blank page must stay white, content
pages must carry ink, and no engine may report an error. Rendering is
interoperability evidence only; conformance is veraPDF's and the structural
checker's job (check_pdfa4.py, check_pdfa4_structure.py).
"""
from __future__ import annotations

import re
import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pdf_layout import planned_bodies
from check_form_renderers import compile_java, require  # noqa: E402
from check_visual_renderers import Raster, read_ppm  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "tests" / "archive"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
A4 = (595, 842)
MIN_INK = 200

TWINS = (
    ("figures", ARCHIVE / "archive_figures.pdf", ARCHIVE / "archive_figures_standard.pdf"),
    ("navigation", ARCHIVE / "archive_navigation.pdf", ARCHIVE / "archive_navigation_standard.pdf"),
)
SINGLE_PAGE = (
    ("blank", ARCHIVE / "archive_blank.pdf", False),
    ("caller", ARCHIVE / "archive_caller.pdf", True),
    ("negative", ARCHIVE / "archive_facade_negative.pdf", True),
    ("figures", ARCHIVE / "archive_figures.pdf", True),
    ("navigation", ARCHIVE / "archive_navigation.pdf", True),
)
MULTI_PAGE = (
    ("report", ARCHIVE / "archive_report.pdf", 4),
    ("navigation-64", ARCHIVE / "archive_navigation_64.pdf", 3),
    ("report-400", ARCHIVE / "archive_report_400.pdf", 29),
)


def ink(raster: Raster) -> int:
    return sum(1 for offset in range(0, len(raster.pixels), 3) if min(raster.pixels[offset:offset + 3]) < 200)


def check_page(engine: str, label: str, raster: Raster, inked: bool) -> None:
    require((raster.width, raster.height) == A4, f"{engine} {label} page is {raster.width}x{raster.height}, not A4 at 72 dpi")
    if inked:
        require(ink(raster) >= MIN_INK, f"{engine} {label} page carries no visible content")
    else:
        require(ink(raster) == 0, f"{engine} {label} blank page is not white")


def check_twin(engine: str, label: str, archive: Raster, standard: Raster) -> None:
    require((archive.width, archive.height) == (standard.width, standard.height), f"{engine} {label} twins differ in geometry")
    require(archive.pixels == standard.pixels, f"{engine} {label} Archive and Standard twins rasterize differently")


def run(command: list[str], label: str, cwd: Path) -> None:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, f"{label} failed: {result.stderr.decode(errors='replace')[:300]}")
    require(not result.stderr.strip(), f"{label} reported diagnostics: {result.stderr.decode(errors='replace')[:300]}")


def render_pdfium(renderer: Path, working_directory: Path | None, snapshot: Path, output: Path) -> Raster:
    run([str(renderer), str(snapshot), str(output), "1"], f"PDFium on {snapshot.name}", working_directory or ROOT)
    return read_ppm(output)


def render_pdfbox(classes: Path, snapshot: Path, output: Path) -> Raster:
    run(
        ["java", "-Djava.awt.headless=true", "-cp", f"{classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxRender", str(snapshot), str(output), "72"],
        f"PDFBox on {snapshot.name}",
        ROOT,
    )
    return read_ppm(output)


def render_mutool_pages(mutool: Path, snapshot: Path, temporary: Path, label: str, pages: int) -> list[Raster]:
    pattern = temporary / f"{label}-mutool-p%d.ppm"
    run([str(mutool), "draw", "-q", "-r", "72", "-c", "rgb", "-o", str(pattern), str(snapshot)], f"MuPDF on {snapshot.name}", ROOT)
    rasters = [read_ppm(temporary / f"{label}-mutool-p{page}.ppm") for page in range(1, pages + 1)]
    require(not (temporary / f"{label}-mutool-p{pages + 1}.ppm").exists(), f"MuPDF rendered more than {pages} pages of {snapshot.name}")
    return rasters


def run_matrix(renderer: Path, working_directory: Path | None, mutool: Path | None) -> None:
    with tempfile.TemporaryDirectory(prefix="archive-renderers-") as name:
        temporary = Path(name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)
        engines = ["pdfium", "pdfbox"] + (["mutool"] if mutool is not None else [])

        def render(engine: str, snapshot: Path, label: str) -> Raster:
            output = temporary / f"{label}-{engine}.ppm"
            if engine == "pdfium":
                return render_pdfium(renderer, working_directory, snapshot, output)
            if engine == "pdfbox":
                return render_pdfbox(classes, snapshot, output)
            return render_mutool_pages(mutool, snapshot, temporary, label, 1)[0]

        for engine in engines:
            for label, snapshot, inked in SINGLE_PAGE:
                check_page(engine, label, render(engine, snapshot, f"{label}-page"), inked)
            for label, archive, standard in TWINS:
                check_twin(engine, label, render(engine, archive, f"{label}-archive"), render(engine, standard, f"{label}-standard"))
        if mutool is not None:
            for label, snapshot, pages in MULTI_PAGE:
                for index, raster in enumerate(render_mutool_pages(mutool, snapshot, temporary, label, pages), start=1):
                    check_page("mutool", f"{label} page {index}", raster, True)
    multi = f" MuPDF 1.28.2 also rendered every page of {len(MULTI_PAGE)} multi-page Archive documents." if mutool is not None else ""
    print(
        f"PASS static PDF/A-4 renderers: {', '.join(engines)} render {len(SINGLE_PAGE)} Archive pages at A4 "
        f"without diagnostics, and {len(TWINS)} Archive/Standard twins rasterize identically.{multi}"
    )


def self_test() -> None:
    for label, archive, standard in TWINS:
        archived = archive.read_bytes()
        plain = standard.read_bytes()
        require(b"<pdfaid:part>4</pdfaid:part>" in archived and b"pdfaid" not in plain, f"{label} twins do not differ by identification")
        # Object and xref streams are compressed, so the twins' byte lengths
        # also move with the shifted offsets; compare the objects instead.
        _, archived_bodies = planned_bodies(archived)
        _, plain_bodies = planned_bodies(plain)
        require(sorted(archived_bodies) == sorted(plain_bodies), f"{label} twins do not have the same objects")
        differing = [number for number in archived_bodies if archived_bodies[number] != plain_bodies[number]]
        packets = [number for number in differing if b"/Type /Metadata" in archived_bodies[number]]
        require(len(packets) == 1, f"{label} twins do not differ in exactly one metadata stream")
        require(len(archived_bodies[packets[0]]) - len(plain_bodies[packets[0]]) == 112, f"{label} twins differ by more than the 112-byte identification")
        lengths = [number for number in differing if number != packets[0]]
        require(all(re.fullmatch(rb"[0-9]+\nendobj\n", archived_bodies[number]) for number in lengths) and len(lengths) <= 1, f"{label} twins differ outside the metadata stream and its length")
    white = Raster(A4[0], A4[1], bytes((255, 255, 255)) * (A4[0] * A4[1]))
    check_page("synthetic", "blank", white, False)
    rejected = [
        ("blank content page", lambda: check_page("synthetic", "content", white, True)),
        ("wrong geometry", lambda: check_page("synthetic", "letter", Raster(612, 792, bytes(612 * 792 * 3)), True)),
        ("differing twins", lambda: check_twin("synthetic", "twin", white, Raster(A4[0], A4[1], bytes(A4[0] * A4[1] * 3)))),
    ]
    for label, action in rejected:
        try:
            action()
        except SystemExit:
            continue
        raise SystemExit(f"archive renderer checker accepted {label}")
    print(f"PASS static PDF/A-4 renderer checker self-test: {len(TWINS)} identification-only twins and {len(rejected)} rejected rasters")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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
    main()
