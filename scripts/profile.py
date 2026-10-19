#!/usr/bin/env python3
"""Build `fuzz/allocation_profile.roc` and tabulate per-stage Roc allocations.

This is an iteration aid, not acceptance evidence: it gives a quick, targeted
allocation count for each stage of a few representative documents so a change
can be checked in seconds instead of through the end-to-end suite. Exact
baselines remain the job of `scripts/test.py`.

Each workload is replayed as its own input (the selector byte), so one
workload's allocations never include another's. The run is saved as JSON and
compared against the previous saved run, or against `--compare FILE`:

```sh
./scripts/profile.py                 # build, measure, diff against last run
./scripts/profile.py --save baseline # also keep a named snapshot
./scripts/profile.py --compare .roc-pdf-tmp/profile/baseline.json
```

Builds use the dev backend and the compiler cache; pass `--no-cache` to rule
the cache out when a count looks surprising.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
WORK = ROOT / ".roc-pdf-tmp" / "profile"
SOURCE = ROOT / "fuzz" / "allocation_profile.roc"
# Selector order: the documents of fuzz/ProfileWorkloads.roc, then the
# kernels of fuzz/ProfileKernels.roc.
WORKLOADS = (
    "report",
    "report_x10",
    "builtin_paragraphs",
    "builtin_paragraphs_x10",
    "deflate_icc",
    "deflate_content",
    "sha256_content",
    "register_inter",
    "deflate_content_fastest",
    "deflate_content_smallest",
)
LINE = re.compile(r'PROFILE (\S+) (\S+) (\d+)')


def build(binary: Path, opt: str, cache: bool) -> None:
    command = [ROC, "build", f"--opt={opt}", str(SOURCE.relative_to(ROOT)), f"--output={binary}"]
    if not cache:
        command.append("--no-cache")
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode not in (0, 2) or not binary.is_file():
        sys.stdout.write(result.stdout)
        raise SystemExit(f"build failed ({result.returncode})")


def measure(binary: Path) -> dict[str, dict[str, int]]:
    results: dict[str, dict[str, int]] = {}
    for index, name in enumerate(WORKLOADS):
        selector = WORK / f"select-{index}"
        selector.write_bytes(bytes([index]))
        result = subprocess.run([str(binary), "replay", str(selector)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        stages = {stage: int(value) for workload, stage, value in LINE.findall(result.stdout) if workload == name}
        if result.returncode != 0 or "total" not in stages:
            sys.stdout.write(result.stdout)
            raise SystemExit(f"{name}: replay failed ({result.returncode})")
        results[name] = stages
    return results


def table(current: dict[str, dict[str, int]], previous: dict[str, dict[str, int]] | None) -> str:
    stages = ("fonts", "prepare", "emit", "total", "pdf_bytes")
    changed = [
        name
        for name, values in current.items()
        if "pdf_fnv" in values and (previous or {}).get(name, {}).get("pdf_fnv") not in (None, values["pdf_fnv"])
    ]
    lines = [f"{'workload':<24}" + "".join(f"{stage:>22}" for stage in stages)]
    for name, values in current.items():
        cells = []
        for stage in stages:
            value = values.get(stage, 0)
            before = (previous or {}).get(name, {}).get(stage)
            if before is None or before == value:
                cells.append(f"{value:>22}")
            else:
                change = (value - before) * 100 / before if before else 0.0
                cells.append(f"{f'{value} ({change:+.1f}%)':>22}")
        lines.append(f"{name:<24}" + "".join(cells))
    if changed:
        lines.append(f"PDF BYTES CHANGED: {', '.join(changed)}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--opt", default="dev", choices=("dev", "speed", "size"))
    parser.add_argument("--no-cache", action="store_true", help="build without the compiler cache")
    parser.add_argument("--no-build", action="store_true", help="measure the existing binary")
    parser.add_argument("--compare", type=Path, help="compare against this saved run instead of the last one")
    parser.add_argument("--save", metavar="NAME", help="also save this run as .roc-pdf-tmp/profile/NAME.json")
    args = parser.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    binary = WORK / f"allocation_profile-{args.opt}"
    if not args.no_build:
        build(binary, args.opt, not args.no_cache)
    current = measure(binary)

    last = WORK / f"last-{args.opt}.json"
    reference = args.compare or last
    previous = json.loads(reference.read_text()) if reference.is_file() else None
    print(table(current, previous))
    if previous is not None:
        print(f"(compared with {reference.relative_to(ROOT) if reference.is_relative_to(ROOT) else reference})")
    last.write_text(json.dumps(current, indent=1, sort_keys=True) + "\n")
    if args.save:
        (WORK / f"{args.save}.json").write_text(json.dumps(current, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
