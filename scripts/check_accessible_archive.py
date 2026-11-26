#!/usr/bin/env python3
"""Compare roc-pdf output with the pinned veraPDF profiles in a local run."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from check_gallery import EXAMPLES, GALLERY
from check_pdfa4 import DEFAULT_VERAPDF, ROOT, SPEC, VERSION, OracleError, check_compliant, require, run_verapdf

REPORT_ROOT = ROOT / ".roc-pdf-tmp" / "accessible-archive-oracles"


def case_paths() -> tuple[list[Path], list[Path]]:
    cases = json.loads(SPEC.read_text(encoding="utf-8"))["cases"]
    flags: dict[Path, tuple[bool, bool]] = {}
    for case in cases:
        path = ROOT / case["snapshot"]
        validators = case["validators"]
        ua = "pdfua2" in validators
        wt = "wtpdf_accessibility" in validators
        require(not ua or "pdfa4" in validators, f"{path}: PDF/UA-2 requires the PDF/A-4 checker")
        require(not wt or ua, f"{path}: WTPDF accessibility requires the PDF/UA-2 checker")
        require(flags.setdefault(path, (ua, wt)) == (ua, wt), f"{path}: cases sharing a snapshot disagree on declared profiles")
    for name in EXAMPLES:
        path = GALLERY / name / f"{name}.pdf"
        ua, wt = True, name == "vector-diagrams"
        require(flags.setdefault(path, (ua, wt)) == (ua, wt), f"{path}: fixture and gallery profiles disagree")
    combined = sorted(path for path, (ua, _) in flags.items() if ua)
    wtpdf = sorted(path for path, (_, wt) in flags.items() if wt)
    return combined, wtpdf


def validate_cases(verapdf: Path, combined: list[Path], wtpdf: list[Path]) -> None:
    require(combined, "no registered PDF/UA-2 fixtures")
    for flavour, paths in (("4", combined), ("ua2", combined), ("wt1a", wtpdf)):
        if paths:
            results = run_verapdf(verapdf, paths, flavour=flavour, report_dir=REPORT_ROOT)
            check_compliant(results, flavour)
            print(f"veraPDF {VERSION} {flavour}: {len(results)} original PDFs accepted")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verapdf", type=Path, default=DEFAULT_VERAPDF)
    parser.add_argument("--cases", action="store_true")
    parser.add_argument("--wtpdf", action="store_true", help="also run the WTPDF accessibility profile")
    parser.add_argument("pdfs", nargs="*", type=Path)
    args = parser.parse_args()
    try:
        if args.cases:
            require(not args.pdfs and not args.wtpdf, "--cases takes no PDF paths or --wtpdf")
            combined, wtpdf = case_paths()
        else:
            require(args.pdfs, "supply PDF paths or choose --cases")
            combined, wtpdf = args.pdfs, args.pdfs if args.wtpdf else []
        validate_cases(args.verapdf, combined, wtpdf)
    except OracleError as error:
        raise SystemExit(f"FAIL {error}") from error


if __name__ == "__main__":
    main()
