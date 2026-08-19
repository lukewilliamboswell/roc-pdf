#!/usr/bin/env python3
"""Regenerate the public gallery, optionally using a served release bundle."""

from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import os
import subprocess
import tempfile
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GALLERY = ROOT / "examples"
ROC = os.environ.get("ROC", "roc")
PACKAGE_DEPENDENCY = 'pdf: "../package/main.roc",'
EXAMPLES = {
    "brand_brief.roc": "brand-brief.pdf",
    "chunked_export.roc": "chunked-export.pdf",
    "field_guide.roc": "field-guide.pdf",
    "letter.roc": "project-letter.pdf",
    "operations_handbook.roc": "operations-handbook.pdf",
    "prepared_invoice.roc": "invoice-1048.pdf",
    "product_brief.roc": "product-brief.pdf",
    "quarterly_report.roc": "quarterly-report.pdf",
    "release_notes.roc": "release-notes.pdf",
}


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


def bundled_source(source: Path, destination: Path, bundle_url: str) -> Path:
    text = source.read_text(encoding="utf-8")
    if text.count(PACKAGE_DEPENDENCY) != 1:
        raise SystemExit(f"{source.name}: expected one local package dependency")
    destination.write_text(
        text.replace(PACKAGE_DEPENDENCY, f'pdf: "{bundle_url}",'),
        encoding="utf-8",
        newline="\n",
    )
    return destination


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
            for source_name, pdf_name in EXAMPLES.items():
                source = GALLERY / source_name
                if server is not None:
                    source = bundled_source(source, temporary_path / source_name, server.url)
                generated_path = output / pdf_name
                if generated_path.exists():
                    generated_path.unlink()
                subprocess.run([ROC, "run", str(source)], cwd=output, check=True)
                generated = generated_path.read_bytes()
                expected = (GALLERY / pdf_name).read_bytes()
                if generated != expected:
                    raise SystemExit(f"{source_name}: generated PDF differs from {pdf_name}")
                generated_path.unlink()
                print(f"PASS {source_name} -> {pdf_name} ({len(expected)} bytes)", flush=True)
            if server is not None and server.get_requests == 0:
                raise SystemExit("gallery never requested the served package bundle")


if __name__ == "__main__":
    main()
