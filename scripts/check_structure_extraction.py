#!/usr/bin/env python3
"""Structure-tree extraction agreement across independent inspection paths.

Two extractors read the same emitted bytes and must produce the same
normalized structure tree:

* the project's byte-level parser in ``check_structure_semantics.py``, which
  renders every element as its role, /Lang, /Alt, /E, /ActualText, and /ID
  facts and its kids in /K order (typed ``/A`` attributes are dropped here,
  because PDFBox exposes them through a different model);
* PDFBox 3.0.8's logical-structure API (``PdfBoxStructureExtract.java``),
  which walks ``PDStructureTreeRoot`` and prints the same projection.

Neither consults the Roc package. ``--self-test`` compares the two on the
reference invoice, report, and letter and on the tagged container, table,
figure, template, and custom-block snapshots, and rejects a mutation twin in
which the two paths would disagree (a /Lang rewritten in the bytes is seen
by both, so the twin instead feeds PDFBox a different document).
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_pdf_structure import ValidationError, require  # noqa: E402
from check_structure_semantics import check_structure_semantics  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PDFBOX_JAR = ROOT / "vendor" / "pdfbox" / "pdfbox-app-3.0.8.jar"
SOURCE = ROOT / "scripts" / "PdfBoxStructureExtract.java"

SNAPSHOTS = [
    ROOT / "tests" / "reference_documents" / "invoice.pdf",
    ROOT / "tests" / "reference_documents" / "report.pdf",
    ROOT / "tests" / "reference_documents" / "letter.pdf",
    ROOT / "tests" / "reference_documents" / "report_ordered.pdf",
    ROOT / "tests" / "containers" / "nested.pdf",
    ROOT / "tests" / "containers" / "lowering.pdf",
    ROOT / "tests" / "tables" / "spans.pdf",
    ROOT / "tests" / "flow_figures" / "report.pdf",
    ROOT / "tests" / "page_templates" / "letter_6.pdf",
    ROOT / "tests" / "custom_block" / "report.pdf",
    ROOT / "tests" / "rich_inline" / "mixed.pdf",
]

ATTRIBUTES = re.compile(r" A=\{[^{}]*\}")


def project_line(pdf: bytes) -> str:
    """The byte-level checker's normalized tree without typed attributes."""
    lines = check_structure_semantics(pdf)
    require(len(lines) == 1, "the structure checker did not render one tree")
    return ATTRIBUTES.sub("", lines[0])


class PdfBox:
    def __init__(self, classes: Path) -> None:
        self.classes = classes
        compiled = subprocess.run(
            ["javac", "-Xlint:all", "-Werror", "-encoding", "UTF-8", "-cp", str(PDFBOX_JAR), "-d", str(classes), str(SOURCE)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(compiled.returncode == 0 and not compiled.stdout and not compiled.stderr, "PDFBox structure extractor compilation failed: " + compiled.stderr.decode(errors="replace"))

    def extract(self, pdf: Path) -> str:
        result = subprocess.run(
            ["java", "-Djava.awt.headless=true", "-cp", f"{self.classes}{os.pathsep}{PDFBOX_JAR}", "PdfBoxStructureExtract", str(pdf)],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(result.returncode == 0 and not result.stderr, result.stderr.decode(errors="replace") or "PDFBox structure extraction failed")
        return result.stdout.decode("utf-8").rstrip("\n")


def compare(pdfbox: PdfBox, pdf: Path) -> int:
    ours = project_line(pdf.read_bytes())
    theirs = pdfbox.extract(pdf)
    if ours != theirs:
        index = next((i for i, (a, b) in enumerate(zip(ours, theirs)) if a != b), min(len(ours), len(theirs)))
        raise ValidationError(f"{pdf.relative_to(ROOT)}: structure extraction disagrees at character {index}: ours {ours[max(0, index - 60):index + 60]!r}, PDFBox {theirs[max(0, index - 60):index + 60]!r}")
    return ours.count("[") + ours.count(", ")


def self_test() -> None:
    require(PDFBOX_JAR.is_file(), f"vendored PDFBox JAR does not exist: {PDFBOX_JAR}")
    with tempfile.TemporaryDirectory(prefix="roc-pdf-structure-extraction-") as temporary_name:
        classes = Path(temporary_name) / "classes"
        classes.mkdir()
        pdfbox = PdfBox(classes)
        items = 0
        for snapshot in SNAPSHOTS:
            items += compare(pdfbox, snapshot)
        # Twin: two different documents must not agree.
        different = project_line(SNAPSHOTS[0].read_bytes()) == pdfbox.extract(SNAPSHOTS[2])
        require(not different, "structure extraction agreement accepted two different documents")
    print(
        f"PASS structure extraction agreement: the byte-level checker and PDFBox 3.0.8 derive identical normalized trees "
        f"(roles, languages, alternatives, expansions, IDs, and MCID/OBJR kids in /K order) on {len(SNAPSHOTS)} snapshots "
        f"({items} tree items); a mismatched-document twin is rejected",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        elif args.pdf is not None:
            with tempfile.TemporaryDirectory(prefix="roc-pdf-structure-extraction-") as temporary_name:
                classes = Path(temporary_name) / "classes"
                classes.mkdir()
                compare(PdfBox(classes), args.pdf.resolve())
            print(f"PASS {args.pdf}: structure extraction agrees")
        else:
            parser.error("give a PDF or --self-test")
    except ValidationError as error:
        raise SystemExit(f"structure extraction check failed: {error}") from error


if __name__ == "__main__":
    main()
