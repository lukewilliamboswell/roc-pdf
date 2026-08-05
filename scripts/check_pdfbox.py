#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts" / "StrictPdfCheck.java"
PDFBOX_VERSION = "3.0.8"
PDFBOX_SHA512 = (
    "768847238f683568507bf73570a2b6fedcbe58b25c7b4f97fba536ba110b290fe"
    "96ba065aed58629d41fb94857d76bc1978c2f31d294b553c69f287f71ee9600"
)
STARTXREF = re.compile(rb"startxref\n([0-9]+)\n%%EOF\n$")


@dataclass(frozen=True)
class Fixture:
    name: str
    pages: int
    objects: int
    page_tree_nodes: int
    content_bytes: int
    operators: int

    @property
    def path(self) -> Path:
        return ROOT / "tests" / self.name / "snapshot.pdf"

    def arguments(self) -> list[str]:
        return [
            str(self.path),
            str(self.pages),
            str(self.objects),
            str(self.page_tree_nodes),
            str(self.content_bytes),
            str(self.operators),
        ]


FIXTURES = (
    Fixture("gate1_blank", 1, 6, 1, 0, 0),
    Fixture("gate1_deflate_one_block", 1, 6, 1, 65_535, 32_768),
    Fixture("gate1_deflate", 1, 6, 1, 262_144, 131_072),
    Fixture("gate1_pages", 4_096, 12_423, 133, 0, 0),
    Fixture("gate1_retention", 1, 6, 1, 64, 0),
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def verify_jar(jar: Path) -> None:
    require(jar.is_file(), f"PDFBox jar does not exist: {jar}")
    hasher = hashlib.sha512()
    with jar.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    require(
        digest == PDFBOX_SHA512,
        f"PDFBox {PDFBOX_VERSION} SHA-512 mismatch: expected {PDFBOX_SHA512}, got {digest}",
    )


def compile_checker(jar: Path, classes: Path) -> None:
    subprocess.run(
        [
            "javac",
            "-Xlint:all",
            "-Werror",
            "-encoding",
            "UTF-8",
            "-cp",
            str(jar),
            "-d",
            str(classes),
            str(SOURCE),
        ],
        cwd=ROOT,
        check=True,
    )


def command(jar: Path, classes: Path, arguments: list[str]) -> list[str]:
    return ["java", "-cp", f"{classes}{os.pathsep}{jar}", "StrictPdfCheck", *arguments]


def run_fixture(jar: Path, classes: Path, fixture: Fixture) -> None:
    result = subprocess.run(
        command(jar, classes, fixture.arguments()),
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    require(result.returncode == 0, result.stderr.strip() or "PDFBox strict check failed")
    require(not result.stderr, f"PDFBox strict check wrote stderr: {result.stderr!r}")
    expected_prefix = f"PASS PDFBox {PDFBOX_VERSION} strict: {fixture.path}"
    require(result.stdout.startswith(expected_prefix), "PDFBox strict check returned an unexpected report")
    print(result.stdout, end="")


def corrupt_startxref(pdf: bytes) -> bytes:
    match = STARTXREF.search(pdf)
    require(match is not None, "negative fixture has no canonical startxref")
    replacement = str(int(match.group(1)) + 1).encode("ascii")
    require(len(replacement) == len(match.group(1)), "negative startxref changed width")
    return pdf[: match.start(1)] + replacement + pdf[match.end(1) :]


def run_recovery_negative(jar: Path, classes: Path, temporary: Path) -> None:
    fixture = FIXTURES[0]
    negative = temporary / "bad-startxref.pdf"
    negative.write_bytes(corrupt_startxref(fixture.path.read_bytes()))
    arguments = fixture.arguments()
    arguments[0] = str(negative)
    result = subprocess.run(
        command(jar, classes, arguments),
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    require(result.returncode == 2, "PDFBox strict parser accepted or did not parse-reject bad startxref")
    require(not result.stdout, "PDFBox strict negative unexpectedly emitted a success report")
    require(
        result.stderr.startswith("FAIL PDFBox strict parse:"),
        "PDFBox negative failed outside the strict parsing boundary",
    )
    print("PASS PDFBox strict recovery negative: shifted startxref rejected during parsing")


def self_test() -> None:
    discovered = {path.parent.name for path in (ROOT / "tests").glob("gate1_*/snapshot.pdf")}
    declared = {fixture.name for fixture in FIXTURES}
    require(discovered == declared, "PDFBox fixture table must cover every Gate 1 snapshot")
    original = FIXTURES[0].path.read_bytes()
    mutation = corrupt_startxref(original)
    require(len(mutation) == len(original), "PDFBox negative twin must preserve file length")
    require(mutation != original, "PDFBox negative twin did not change startxref")
    print("PASS PDFBox strict checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jar", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.jar is not None, "--jar is required unless --self-test is used")
    jar = args.jar.resolve()
    verify_jar(jar)
    with tempfile.TemporaryDirectory(prefix="roc-pdf-pdfbox-") as temporary_name:
        temporary = Path(temporary_name)
        classes = temporary / "classes"
        classes.mkdir()
        compile_checker(jar, classes)
        for fixture in FIXTURES:
            run_fixture(jar, classes, fixture)
        run_recovery_negative(jar, classes, temporary)


if __name__ == "__main__":
    main()
