#!/usr/bin/env python3
"""Regenerate the public gallery, optionally using a served release bundle."""

from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import os
import re
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path


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
    "operations-handbook",
    "product-brief",
    "quarterly-report",
    "release-notes",
    "tax-invoice",
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
    shutil.copytree(example, destination, ignore=shutil.ignore_patterns("*.pdf", "preview.png"))
    (destination / "main.roc").write_text(
        text.replace(PACKAGE_DEPENDENCY, f'pdf: "{bundle_url}",'),
        encoding="utf-8",
        newline="\n",
    )
    return destination / "main.roc"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path)
    args = parser.parse_args()

    output = ROOT / ".roc-pdf-tmp" / "gallery-output"
    output.mkdir(parents=True, exist_ok=True)
    bundle = args.bundle_path.resolve() if args.bundle_path is not None else None
    if bundle is not None and not bundle.is_file():
        raise SystemExit(f"bundle does not exist: {bundle}")

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
                expected = (example / pdf_name).read_bytes()
                if generated != expected:
                    raise SystemExit(f"{name}: generated PDF differs from {pdf_name}")
                generated_path.unlink()
                print(f"PASS {name}/main.roc -> {pdf_name} ({len(expected)} bytes)", flush=True)
            if server is not None and server.get_requests == 0:
                raise SystemExit("gallery never requested the served package bundle")


if __name__ == "__main__":
    main()
