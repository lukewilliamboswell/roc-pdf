#!/usr/bin/env python3
"""Regenerate the public gallery, optionally using a served release bundle."""

from __future__ import annotations

import argparse
import contextlib
from dataclasses import dataclass
import functools
import hashlib
import http.server
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from check_drawing_labels import artifact_and_tagged_text
from check_generated_handbook import check as check_generated_handbook
from check_gallery_features import check_features
from check_table_spans import validate_quarterly, validate_regional


ROOT = Path(__file__).resolve().parents[1]
GALLERY = ROOT / "examples"
ROC = os.environ.get("ROC", "roc")
PACKAGE_DEPENDENCY = 'pdf: "../../package/main.roc",'
# Each example is a directory holding its app root `main.roc`, the assets it
# imports, the PDF it writes (named after the directory), and a preview.
EXAMPLES = (
    "arabic-invoice",
    "audit-log",
    "bilingual-invoice",
    "brand-brief",
    "business-report",
    "chunked-export",
    "field-guide",
    "furniture-typography",
    "font-families",
    "hindi-statement",
    "invoice-with-data",
    "operations-handbook",
    "ordered-han",
    "pilot-findings",
    "product-brief",
    "quarterly-report",
    "release-notes",
    "remittance-advice",
    "service-intake",
    "source-blocks",
    "tax-invoice",
    "thai-notice",
    "vector-diagrams",
    "warranty-letter",
)
PREVIEW_PAGES = {"quarterly-report": 2}
LOCAL_IMPORT = re.compile(r'^import "([^"]+)"', re.MULTILINE)


@dataclass(frozen=True)
class Case:
    args: tuple[str, ...]
    snapshot: str | None = None
    diagnosis: str | None = None
    facts: tuple[str, ...] = ()


CASES = {
    "audit-log": (
        Case(("archive",), "audit-log-archive.pdf"),
        Case(("standard",), "audit-log-standard.pdf"),
        Case(("invalid",), diagnosis="semantics.heading_level at contents[1]"),
    ),
    "business-report": (
        Case(("report",), "business-report.pdf", facts=("Language en-AU", "repeated header", "alternative:", "Author check")),
        Case(("report-budget",), "business-report.pdf", facts=("Language en-AU", "repeated header")),
        Case(("report-tiny",), diagnosis="report.budget_exceeded"),
        Case(("heat-map",), "business-report-heat-map.pdf", facts=("figure on page 5", "applied figure scale 731 per thousand")),
        Case(("heat-exact",), diagnosis="document.figure_oversize at contents[7].contents[2]"),
        Case(("heat-high-floor",), diagnosis="below its ScaleToFit floor of 90%"),
    ),
    "chunked-export": tuple(
        Case((compression, delivery), f"chunked-export{suffix}.pdf")
        for compression, suffix in (("balanced", ""), ("smallest", "-smallest"), ("fastest", "-fastest"))
        for delivery in ("share", "own", "buffered")
    ),
    "field-guide": (
        Case(("pocket",), "field-guide-pocket.pdf", facts=("Preferred species note keep relaxed",)),
    ),
    "operations-handbook": (
        Case(("generated",), "operations-handbook-generated.pdf"),
        Case(("index",), "operations-handbook-index.pdf"),
        Case(("flow-short",), "operations-handbook-flow-short.pdf", facts=("A-1 on physical page 1",)),
        Case(("flow-long",), "operations-handbook-flow-long.pdf", facts=("RECOVERY-CHECKS-2 on physical page 2",)),
    ),
    "ordered-han": (
        Case(("latin-only",), diagnosis="text.coverage_missing at contents[1].inlines[1].inlines[0]"),
    ),
    "quarterly-report": (
        Case(("regional",), "quarterly-report-regional.pdf", facts=("Repeated header on page 2", "Continued row contents[0].table.body_rows[1] on page 2")),
        Case(("regional-keep",), diagnosis="layout.oversize_span_group at contents[0].table.body_rows[0], contents[0].table.body_rows[1]"),
    ),
    "source-blocks": (
        Case(("plain",), "source-blocks-plain.pdf"),
        Case(("bad-range",), diagnosis="source.foreground_range at contents[2]"),
    ),
    "tax-invoice": (
        Case(("split",), "tax-invoice-split.pdf", facts=("Repeated header", "Continued row contents[4].contents[1].table.body_rows[30]")),
        Case(("keep",), diagnosis="layout.oversize_row at contents[4].contents[1].table.body_rows[30]"),
    ),
}


def check_cases(name: str, source: Path, example: Path, output: Path) -> None:
    generated = output / f"{name}.pdf"
    sentinel = b"gallery check: existing output must survive a rejected document"
    for case in CASES.get(name, ()):
        label = f"{name}/main.roc {' '.join(case.args)}"
        command = [ROC, "run", str(source), *case.args]
        result = subprocess.run(command, cwd=output, capture_output=True, text=True)
        if case.diagnosis is not None:
            if result.returncode != 1 or case.diagnosis not in result.stderr or generated.exists():
                raise SystemExit(f"{label}: expected a rejected document and no new file\n{result.stderr}")
            generated.write_bytes(sentinel)
            try:
                repeat = subprocess.run(command, cwd=output, capture_output=True, text=True)
                if (repeat.returncode != 1 or case.diagnosis not in repeat.stderr
                        or not generated.is_file() or generated.read_bytes() != sentinel):
                    raise SystemExit(f"{label}: rejected document changed an existing output file")
            finally:
                generated.unlink(missing_ok=True)
        else:
            if result.returncode != 0 or not generated.is_file():
                raise SystemExit(f"{label}: generation failed\n{result.stderr}")
            if not all(fact in result.stdout for fact in case.facts):
                raise SystemExit(f"{label}: missing expected review facts\n{result.stdout}")
            if generated.read_bytes() != (example / case.snapshot).read_bytes():
                raise SystemExit(f"{label}: generated PDF differs from {case.snapshot}")
            generated.unlink()
        print(f"PASS {label}", flush=True)


class BundleRequestHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass

    def do_GET(self) -> None:
        self.server.bundle_get_requests += 1  # type: ignore[attr-defined]
        super().do_GET()


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(BundleRequestHandler, directory=str(bundle.parent))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.server.bundle_get_requests = 0  # type: ignore[attr-defined]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> BundleServer:
        self.thread.start()
        return self

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    @property
    def get_requests(self) -> int:
        return int(self.server.bundle_get_requests)  # type: ignore[attr-defined]


def bundled_example(example: Path, destination: Path, bundle_url: str) -> Path:
    """Copy one example directory and point it at the served bundle.

    A bundle consumer has only the example's own directory, so every byte
    import must name a file inside it.
    """
    text = (example / "main.roc").read_text(encoding="utf-8")
    if text.count(PACKAGE_DEPENDENCY) != 1:
        raise SystemExit(f"{example.name}: expected one local package dependency")
    for imported in LOCAL_IMPORT.findall(text):
        resolved = (example / imported).resolve()
        if not resolved.is_relative_to(example.resolve()) or not resolved.is_file():
            raise SystemExit(f"{example.name}: import {imported!r} is not a file inside the example directory")
    shutil.copytree(example, destination, ignore=shutil.ignore_patterns("*.pdf", "preview*.png", "node_modules"))
    (destination / "main.roc").write_text(
        text.replace(PACKAGE_DEPENDENCY, f'pdf: "{bundle_url}",'),
        encoding="utf-8",
        newline="\n",
    )
    return destination / "main.roc"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path)
    parser.add_argument("--example", action="append", choices=EXAMPLES, help="Limit the check to selected examples")
    parser.add_argument("--update", action="store_true", help="Regenerate reviewed PDFs and Poppler previews, updating their provenance")
    parser.add_argument("--update-reason", help="Architectural cause reviewed before accepting changed gallery output")
    parser.add_argument("--report", type=Path, default=ROOT / ".roc-pdf-tmp/gallery-update-report.json")
    args = parser.parse_args()
    if args.update and not args.update_reason:
        parser.error("--update requires the reviewed architectural cause in --update-reason")
    pinned = (ROOT / ".roc-version").read_text().strip()
    if pinned not in subprocess.check_output([ROC, "version"], text=True):
        parser.error(f"gallery checks require {pinned}")
    if args.update:
        version = subprocess.run(["pdftoppm", "-v"], capture_output=True, text=True, check=True)
        if "pdftoppm version 26.07.0" not in version.stderr:
            parser.error("preview regeneration requires the retained Poppler 26.07.0 renderer")

    output = ROOT / ".roc-pdf-tmp" / "gallery-output"
    output.mkdir(parents=True, exist_ok=True)
    bundle = args.bundle_path.resolve() if args.bundle_path is not None else None
    if bundle is not None and not bundle.is_file():
        raise SystemExit(f"bundle does not exist: {bundle}")
    changes = []
    provenance_path = ROOT / "assets/provenance.json"
    provenance = provenance_path.read_text()

    def update_pin(path: Path) -> None:
        nonlocal provenance
        relative = path.relative_to(ROOT).as_posix()
        pattern = r'("path"\s*:\s*"' + re.escape(relative) + r'".*?"bytes"\s*:\s*)\d+(.*?"sha256"\s*:\s*")[0-9a-f]{64}'
        payload = path.read_bytes()
        provenance, count = re.subn(pattern, lambda match: match[1] + str(len(payload)) + match[2] + hashlib.sha256(payload).hexdigest(), provenance, flags=re.S)
        if count != 1:
            raise SystemExit(f"expected exactly one provenance record for {relative}")
        if path.name == "preview.png":
            pattern = r'("path"\s*:\s*"' + re.escape(relative) + r'".*?"attribution"\s*:\s*")([^\"]+)(")'
            provenance, count = re.subn(pattern, lambda match: match[1] + re.sub(r"Poppler [0-9.]+", "Poppler 26.07.0.", match[2]) + match[3], provenance, flags=re.S)
            if count != 1:
                raise SystemExit(f"expected exactly one preview attribution for {relative}")

    with tempfile.TemporaryDirectory(prefix="gallery-sources-", dir=output) as temporary:
        temporary_path = Path(temporary)
        server_context = BundleServer(bundle) if bundle is not None else contextlib.nullcontext()
        with server_context as server:
            for name in args.example or EXAMPLES:
                example = GALLERY / name
                pdf_name = f"{name}.pdf"
                source = example / "main.roc"
                if server is not None:
                    source = bundled_example(example, temporary_path / name, server.url)
                generated_path = output / pdf_name
                if generated_path.exists():
                    generated_path.unlink()
                subprocess.run([ROC, "run", str(source)], cwd=output, check=True)
                generated = generated_path.read_bytes()
                expected_path = example / pdf_name
                expected = expected_path.read_bytes()
                if args.update:
                    # Typography and metadata changes may alter wrapping and
                    # page furniture; semantic source characters must survive.
                    old_artifacts, old_text = artifact_and_tagged_text(expected)
                    new_artifacts, new_text = artifact_and_tagged_text(generated)
                    canonical = lambda text: re.sub(r"\s+", "", "".join(text))
                    if canonical(old_text) != canonical(new_text):
                        raise SystemExit(f"{name}: semantic source characters changed; review before accepting output")
                    backup = ROOT / ".roc-pdf-tmp/gallery-review/old" / name
                    backup.mkdir(parents=True, exist_ok=True)
                    (backup / pdf_name).write_bytes(expected)
                    shutil.copyfile(example / "preview.png", backup / "preview.png")
                    preview_prefix = output / f"{name}-preview"
                    subprocess.run(["pdftoppm", "-f", str(PREVIEW_PAGES.get(name, 1)), "-singlefile", "-r", "96", "-png", str(generated_path), str(preview_prefix)], check=True)
                    preview = preview_prefix.with_suffix(".png")
                    expected_path.write_bytes(generated)
                    shutil.copyfile(preview, example / "preview.png")
                    update_pin(expected_path)
                    update_pin(example / "preview.png")
                    changes.append({"example": name,
                                    "old_pdf_sha256": hashlib.sha256(expected).hexdigest(),
                                    "new_pdf_sha256": hashlib.sha256(generated).hexdigest(),
                                    "old_bytes": len(expected), "new_bytes": len(generated),
                                    "semantic_characters_preserved": True,
                                    "old_artifact_spans": len(old_artifacts), "new_artifact_spans": len(new_artifacts)})
                    preview.unlink()
                elif generated != expected:
                    raise SystemExit(f"{name}: generated PDF differs from {pdf_name}")
                generated_path.unlink()
                print(f"PASS {name}/main.roc -> {pdf_name} ({len(generated)} bytes)", flush=True)
                check_cases(name, source, example, output)
                if name == "operations-handbook":
                    check_generated_handbook(example)
                check_features(name, example)
                if name == "quarterly-report":
                    validate_quarterly(generated)
                    validate_regional((example / "quarterly-report-regional.pdf").read_bytes())
            if server is not None and server.get_requests == 0:
                raise SystemExit("gallery never requested the served package bundle")
    if args.update:
        provenance_path.write_text(provenance)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({"reason": args.update_reason, "compiler": pinned,
                                          "preview_renderer": "Poppler 26.07.0, 96 dpi", "examples": changes}, indent=2) + "\n")
        print(f"Reviewed gallery update report: {args.report}")


if __name__ == "__main__":
    main()
