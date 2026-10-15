#!/usr/bin/env python3
"""Classify Roc compiler output for the harness's warnings-are-failures policy.

`roc check`, `roc test`, and `roc build` exit with status 2 when they report
warnings but no errors. The harness treats every warning in this repository's
own sources as a failure. Exactly one warning is tolerated: the
`roc version mismatch` warning emitted for a *downloaded package's* header
(`packages { roc: "<nightly>" }`) when the pinned compiler is newer than the
nightly that package was released against. That header lives in the Roc
package cache, outside this repository, so it cannot be updated here; the
compiler still checks and builds normally.

`tolerated_warnings_only(output)` returns True only when the output reports
zero errors, at least one warning, and every warning is a version mismatch
located in a Roc package cache (a path containing `/roc/packages/`). Any other
warning, any error, or any unparseable summary keeps the command failing.
"""
from __future__ import annotations

import argparse
import re
import sys

WARNING_HEADER = re.compile(r"^── ● (?P<title>.+?) ─+ (?P<location>\S+?):\d+:\d+\s*$", re.M)
ERROR_HEADER = re.compile(r"^── ✗ ", re.M)
SUMMARY = re.compile(r"(?P<errors>\d+) errors? and (?P<warnings>\d+) warnings?")
# `roc test` reports no diagnostic summary; its success line stands in for one.
TESTS_PASSED = re.compile(r"^All \(\d+\) tests passed\b", re.M)
TESTS_FAILED = re.compile(r"\b\d+ failed\b|^Ran \d+ tests", re.M)
TOLERATED_TITLE = "roc version mismatch"
PACKAGE_CACHE_SEGMENT = "/roc/packages/"


def tolerated_warnings_only(output: str) -> bool:
    if ERROR_HEADER.search(output):
        return False
    headers = list(WARNING_HEADER.finditer(output))
    summaries = SUMMARY.findall(output)
    if summaries:
        if any(int(errors) != 0 for errors, _ in summaries):
            return False
        if sum(int(warnings) for _, warnings in summaries) != len(headers):
            return False
    elif not TESTS_PASSED.search(output) or TESTS_FAILED.search(output):
        return False
    if not headers:
        return False
    return all(
        header.group("title") == TOLERATED_TITLE and PACKAGE_CACHE_SEGMENT in header.group("location")
        for header in headers
    )


MISMATCH = """── ● roc version mismatch ─ /tmp/cache/roc/packages/FfSwk/main.roc:9:13
This header pins Roc version nightly-2026-09-26-d6267b4, but you are running
nightly-2026-09-28-9927ba8.
── 0 errors and 1 warning ─────────────────────────────── fuzz/theme_options.roc
"""


def self_test() -> None:
    test_output = MISMATCH.split("── 0 errors")[0] + "All (465) tests passed in 4335.3 ms. (cached)\n"
    accepted = [MISMATCH, test_output]
    rejected = [
        MISMATCH.replace("/tmp/cache/roc/packages/FfSwk/main.roc", "package/Pdf.roc"),
        MISMATCH.replace("roc version mismatch", "unused variable"),
        MISMATCH.replace("0 errors and 1 warning", "1 error and 1 warning"),
        MISMATCH.replace("0 errors and 1 warning", "0 errors and 2 warnings"),
        MISMATCH + "── ✗ type mismatch ── package/Pdf.roc:1:1\n",
        "no summary at all",
        test_output.replace("All (465) tests passed", "Ran 465 tests: 464 passed, 1 failed"),
        test_output.replace("/tmp/cache/roc/packages/FfSwk/main.roc", "tests/archive/archive_facade.roc"),
    ]
    for sample in accepted:
        if not tolerated_warnings_only(sample):
            raise SystemExit(f"roc_diagnostics rejected a tolerated sample:\n{sample}")
    for sample in rejected:
        if tolerated_warnings_only(sample):
            raise SystemExit(f"roc_diagnostics accepted an intolerable sample:\n{sample}")
    print(f"PASS roc_diagnostics self-test: {len(accepted)} tolerated, {len(rejected)} rejected samples")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    if parser.parse_args().self_test:
        self_test()
    else:
        sys.exit(0 if tolerated_warnings_only(sys.stdin.read()) else 1)


if __name__ == "__main__":
    main()
