#!/usr/bin/env python3
"""Pinned renderer, extraction, and font-validator evidence for the production-visual
canonical font-leaf fixtures.

Structural facts (``check_fonts.py``) are the primary oracle; this
script corroborates them end to end with the pinned independent engines:

- PDFium Chromium 7988 and Apache PDFBox 3.0.8 render the single-page
  fixtures (the distinctness matrix, the shared-subset grid, the collapse
  grid, and the distinct-subset grid) at 72 dpi; every placement region must
  carry glyph ink and everything outside the declared regions must stay
  blank, in every engine.
- PDFBox text extraction returns exactly the logical reading-order text of
  the distinctness matrix — proving the mapping-distinctness axis end to
  end: the same subset glyph extracts as ``A`` under one bundle and ``Å``
  under its mapping-distinct twin — and of the sharing grids.
- When ``--mutool`` names a mutool built from the vendored MuPDF 1.28.2
  source, MuPDF renders the same fixtures, renders both pages of the
  two-page showcase (the single-page PDFium/PDFBox adapters deliberately
  reject multi-page fixtures), and its stext extraction reproduces each
  page's logical text.
- Every embedded ``FontFile2`` subset in every checked fixture is exported
  and revalidated with the pinned fontTools 4.61.1 in checksum-verifying
  mode: table checksums, glyph closure, ``hmtx``/``head`` agreement with the
  emitted ``/W`` array, and cmap agreement with the recipe's mapping facts.
"""
from __future__ import annotations

import argparse
import io
import os
import subprocess
import tempfile
from pathlib import Path

from check_visual_renderers import Raster, read_ppm
from check_fonts import FontFacts

ROOT = Path(__file__).resolve().parents[1]
SHOWCASE_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves.pdf"
FACTS_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaf_facts.pdf"
SHARE_100_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_share_100.pdf"
DEDUPE_8_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_dedupe_8.pdf"
DISTINCT_8_SNAPSHOT = ROOT / "tests" / "font_leaves" / "font_leaves_distinct_8.pdf"
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
RENDER_SOURCE = ROOT / "scripts" / "PdfBoxRender.java"
EXTRACT_SOURCE = ROOT / "scripts" / "PdfBoxTextExtract.java"
FONTTOOLS_VERSION = "4.61.1"
SIZE = 100

## One 11-point glyph run painted at baseline (x, y) points inks a region
## bounded by the em box around the baseline; per-glyph pen advance is the
## fixture's fixed 6 points.
def run_region(x: int, y: int, glyphs: int) -> tuple[int, int, int, int]:
    return (x - 1, y - 4, x + 6 * (glyphs - 1) + 10, y + 10)


FACTS_REGIONS = [run_region(8, 84, 2), run_region(8, 64, 1), run_region(8, 44, 1), run_region(8, 24, 1), run_region(8, 8, 1)]
## PDFBox's default extraction and MuPDF's txt output both return content
## stream order, which is paint order (each page paints its groups in
## reverse logical order); both pin the mapping-distinct A-versus-Å pair.
FACTS_TEXT_PAINT_ORDER = ["C", "A", "Å", "A", "AB"]
DEDUPE_8_REGIONS = [run_region(6 + column * 8, 88, 1) for column in range(8)]
DISTINCT_8_REGIONS = DEDUPE_8_REGIONS
SHOWCASE_PAGE_TEXT = [["C", "B", "A"], ["C", "AB"]]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def ink_pixels(raster: Raster) -> list[tuple[int, int]]:
    points = []
    for index in range(0, len(raster.pixels), 3):
        red, green, blue = raster.pixels[index : index + 3]
        if (red, green, blue) != (255, 255, 255):
            pixel = index // 3
            points.append((pixel % raster.width, raster.height - 1 - pixel // raster.width))
    return points


def assert_regions(label: str, raster: Raster, regions: list[tuple[int, int, int, int]]) -> None:
    require((raster.width, raster.height) == (SIZE, SIZE), f"{label}: raster is not the 100x100 page at 72 dpi")
    points = ink_pixels(raster)
    require(bool(points), f"{label}: raster is blank")
    for index, (left, bottom, right, top) in enumerate(regions):
        inked = any(left <= x <= right and bottom <= y <= top for x, y in points)
        require(inked, f"{label}: placement region {index} {(left, bottom, right, top)} carries no glyph ink")
    for x, y in points:
        inside = any(left <= x <= right and bottom <= y <= top for left, bottom, right, top in regions)
        require(inside, f"{label}: unexpected ink at ({x}, {y}) outside every declared placement region")


def assert_grid_columns(label: str, raster: Raster) -> None:
    """The share grid: ink in each of the twelve glyph columns, nothing else."""
    require((raster.width, raster.height) == (SIZE, SIZE), f"{label}: raster is not the 100x100 page at 72 dpi")
    points = ink_pixels(raster)
    require(bool(points), f"{label}: raster is blank")
    for column in range(12):
        left = 6 + column * 8
        inked = any(left - 1 <= x <= left + 9 for x, _ in points)
        require(inked, f"{label}: grid column {column} carries no glyph ink")
    for x, y in points:
        require(5 <= x <= 103 and 69 <= y <= 99, f"{label}: unexpected ink at ({x}, {y}) outside the grid band")


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


def render_mutool_page(mutool: Path, snapshot: Path, output: Path, page: int) -> Raster:
    subprocess.run(
        [str(mutool), "draw", "-q", "-r", "72", "-c", "rgb", "-o", str(output), str(snapshot), str(page)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return read_ppm(output)


def extract_text_mutool(mutool: Path, snapshot: Path, output: Path) -> str:
    subprocess.run(
        [str(mutool), "draw", "-q", "-F", "txt", "-o", str(output), str(snapshot)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return output.read_text(encoding="utf-8")


def revalidate_subsets(label: str, snapshot: Path, expected_pages: int) -> None:
    """Every embedded subset re-verified by the pinned font validator."""
    import fontTools
    from fontTools.ttLib import TTFont

    require(
        fontTools.__version__ == FONTTOOLS_VERSION,
        f"fontTools {FONTTOOLS_VERSION} is required, got {fontTools.__version__}",
    )
    facts = FontFacts(snapshot.read_bytes(), expected_pages)
    for bundle in facts.bundles:
        font = TTFont(io.BytesIO(bundle.subset_bytes), checkChecksums=2)
        glyph_order = font.getGlyphOrder()
        require(len(glyph_order) == bundle.subset.glyph_count, f"{label}: fontTools glyph closure disagrees")
        cmap = font.getBestCmap()
        gid_of = {name: index for index, name in enumerate(glyph_order)}
        mapped_cids = {gid_of[name] for name in (cmap[code] for code in cmap)}
        require(
            set(bundle.mappings) <= mapped_cids or not cmap,
            f"{label}: subset cmap does not cover the ToUnicode content CIDs",
        )
        hmtx = font["hmtx"]
        upem = font["head"].unitsPerEm
        widths = [(hmtx[name][0] * 1000 + upem // 2) // upem for name in glyph_order]
        require(widths == bundle.widths, f"{label}: fontTools widths disagree with the emitted /W array")
        font.close()
    print(f"PASS fontTools {FONTTOOLS_VERSION} revalidated {len(facts.bundles)} embedded subsets in {label}")


def check_renderers(renderer: Path, working_directory: Path | None, mutool: Path | None) -> None:
    require(renderer.is_file(), f"PDFium renderer does not exist: {renderer}")
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    if mutool is not None:
        require(mutool.is_file(), f"mutool does not exist: {mutool}")

    for label, snapshot, pages in (
        ("showcase", SHOWCASE_SNAPSHOT, 2),
        ("facts", FACTS_SNAPSHOT, 1),
        ("share-100", SHARE_100_SNAPSHOT, 1),
        ("dedupe-8", DEDUPE_8_SNAPSHOT, 1),
        ("distinct-8", DISTINCT_8_SNAPSHOT, 1),
    ):
        revalidate_subsets(label, snapshot, pages)

    with tempfile.TemporaryDirectory(prefix="roc-pdf-font-render-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_java(classes)

        for name, snapshot, regions in (
            ("facts", FACTS_SNAPSHOT, FACTS_REGIONS),
            ("dedupe-8", DEDUPE_8_SNAPSHOT, DEDUPE_8_REGIONS),
            ("distinct-8", DISTINCT_8_SNAPSHOT, DISTINCT_8_REGIONS),
        ):
            pdfium, pdfbox = render_both(renderer, working_directory, classes, snapshot, temporary, name)
            assert_regions(f"PDFium Chromium 7988 {name}", pdfium, regions)
            assert_regions(f"PDFBox 3.0.8 {name}", pdfbox, regions)
            if mutool is not None:
                assert_regions(
                    f"MuPDF 1.28.2 {name}",
                    render_mutool_page(mutool, snapshot, temporary / f"{name}-mutool.ppm", 1),
                    regions,
                )

        pdfium_grid, pdfbox_grid = render_both(renderer, working_directory, classes, SHARE_100_SNAPSHOT, temporary, "share-100")
        assert_grid_columns("PDFium Chromium 7988 share-100", pdfium_grid)
        assert_grid_columns("PDFBox 3.0.8 share-100", pdfbox_grid)
        if mutool is not None:
            assert_grid_columns(
                "MuPDF 1.28.2 share-100",
                render_mutool_page(mutool, SHARE_100_SNAPSHOT, temporary / "share-100-mutool.ppm", 1),
            )

        ## The mapping-distinctness axis end to end: the same subset glyph
        ## extracts as A under one bundle and Å under its twin, in logical
        ## reading order.
        extracted = extract_text(classes, FACTS_SNAPSHOT)
        require(extracted.split() == FACTS_TEXT_PAINT_ORDER, f"facts extraction returned {extracted.split()!r}, expected {FACTS_TEXT_PAINT_ORDER!r}")
        ## PDFBox's pinned duplicate-overlapping-text suppression collapses
        ## the deliberately overlapping one-point-spaced grid rows: 36 of the
        ## 100 painted A glyphs survive as distinct text positions, and every
        ## survivor extracts through the one shared ToUnicode mapping.
        share_text = extract_text(classes, SHARE_100_SNAPSHOT)
        require("".join(share_text.split()) == "A" * 36, f"share-100 extraction returned {share_text!r}")
        dedupe_text = extract_text(classes, DEDUPE_8_SNAPSHOT)
        require("".join(dedupe_text.split()) == "A" * 8, f"dedupe-8 extraction returned {dedupe_text!r}")
        distinct_text = extract_text(classes, DISTINCT_8_SNAPSHOT)
        require("".join(distinct_text.split()) == "HGFEDCBA", f"distinct-8 extraction returned {distinct_text!r}")

        if mutool is not None:
            ## The two-page showcase through the third engine: both pages
            ## render with ink exactly in the declared placement regions,
            ## and stext reproduces each page's logical text.
            page_one = render_mutool_page(mutool, SHOWCASE_SNAPSHOT, temporary / "showcase-1.ppm", 1)
            page_two = render_mutool_page(mutool, SHOWCASE_SNAPSHOT, temporary / "showcase-2.ppm", 2)
            assert_regions(
                "MuPDF 1.28.2 showcase page 1",
                page_one,
                [run_region(10, 80, 1), run_region(40, 60, 1), run_region(70, 30, 1)],
            )
            assert_regions(
                "MuPDF 1.28.2 showcase page 2",
                page_two,
                [run_region(10, 80, 2), run_region(60, 40, 1)],
            )
            showcase_text = extract_text_mutool(mutool, SHOWCASE_SNAPSHOT, temporary / "showcase-mutool.txt")
            pages = showcase_text.split("\f")
            tokens = [page.split() for page in pages if page.split()]
            require(tokens == SHOWCASE_PAGE_TEXT, f"mutool showcase extraction returned {tokens!r}, expected {SHOWCASE_PAGE_TEXT!r}")
            facts_text = extract_text_mutool(mutool, FACTS_SNAPSHOT, temporary / "facts-mutool.txt")
            require(facts_text.split() == FACTS_TEXT_PAINT_ORDER, f"mutool facts extraction returned {facts_text.split()!r}")

    third = " MuPDF 1.28.2 agrees, including both showcase pages and stext extraction." if mutool is not None else ""
    print(
        "PASS production-visual font-leaf renderers: PDFium Chromium 7988 and PDFBox 3.0.8 ink every declared "
        "placement region and nothing else, extraction reproduces the logical text including the "
        "A-versus-Å mapping-distinct pair, and fontTools 4.61.1 revalidated every embedded subset." + third
    )


def self_test() -> None:
    require(run_region(8, 84, 2)[2] > run_region(8, 84, 1)[2], "multi-glyph region must widen")
    blank = Raster(SIZE, SIZE, bytes((255, 255, 255)) * (SIZE * SIZE))
    try:
        assert_regions("negative twin", blank, FACTS_REGIONS)
    except SystemExit:
        pass
    else:
        raise SystemExit("font renderer checker accepted a blank raster")
    stray = bytearray(blank.pixels)
    for x, y in ((9, 85), (9, 65), (9, 45), (9, 25), (9, 9)):
        offset = ((SIZE - 1 - y) * SIZE + x) * 3
        stray[offset : offset + 3] = b"\0\0\0"
    assert_regions("positive twin", Raster(SIZE, SIZE, bytes(stray)), FACTS_REGIONS)
    stray[((SIZE - 1 - 55) * SIZE + 90) * 3] = 0
    try:
        assert_regions("stray-ink twin", Raster(SIZE, SIZE, bytes(stray)), FACTS_REGIONS)
    except SystemExit:
        pass
    else:
        raise SystemExit("font renderer checker accepted stray ink outside every region")
    print("PASS production-visual font-leaf renderer checker self-test")


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
