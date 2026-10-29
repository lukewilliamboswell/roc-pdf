#!/usr/bin/env python3
"""Regenerate the public gallery, optionally using a served release bundle."""

from __future__ import annotations

import argparse
import contextlib
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


ROOT = Path(__file__).resolve().parents[1]
GALLERY = ROOT / "examples"
ROC = os.environ.get("ROC", "roc")
PACKAGE_DEPENDENCY = 'pdf: "../../package/main.roc",'
# Each example is a directory holding its app root `main.roc`, the assets it
# imports, the PDF it writes (named after the directory), and a preview.
EXAMPLES = (
    "brand-brief",
    "business-report",
    "chunked-export",
    "field-guide",
    "furniture-typography",
    "font-families",
    "operations-handbook",
    "product-brief",
    "quarterly-report",
    "release-notes",
    "source-blocks",
    "tax-invoice",
    "vector-diagrams",
    "warranty-letter",
)
LOCAL_IMPORT = re.compile(r'^import "([^"]+)"', re.MULTILINE)


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
    shutil.copytree(example, destination, ignore=shutil.ignore_patterns("*.pdf", "preview.png", "node_modules"))
    (destination / "main.roc").write_text(
        text.replace(PACKAGE_DEPENDENCY, f'pdf: "{bundle_url}",'),
        encoding="utf-8",
        newline="\n",
    )
    return destination / "main.roc"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path)
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

    with tempfile.TemporaryDirectory(prefix="gallery-sources-", dir=output) as temporary:
        temporary_path = Path(temporary)
        server_context = BundleServer(bundle) if bundle is not None else contextlib.nullcontext()
        with server_context as server:
            for name in EXAMPLES:
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
                    subprocess.run(["pdftoppm", "-f", "1", "-singlefile", "-r", "96", "-png", str(generated_path), str(preview_prefix)], check=True)
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
