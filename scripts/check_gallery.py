#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GALLERY = ROOT / "examples"
ROC = os.environ.get("ROC", "roc")
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


def main() -> None:
    output = ROOT / ".roc-pdf-tmp" / "gallery-output"
    output.mkdir(parents=True, exist_ok=True)
    for source_name, pdf_name in EXAMPLES.items():
        source = GALLERY / source_name
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


if __name__ == "__main__":
    main()
