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
from datetime import datetime, timezone

import fuzz as fuzz_lane
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


def build(binary: Path, opt: str, cache: bool, host: str) -> None:
    command = [ROC, "build", f"--opt={opt}", f"--target={host}", str(SOURCE.relative_to(ROOT)), f"--output={binary}"]
    if not cache:
        command.append("--no-cache")
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode not in (0, 2) or not binary.is_file():
        sys.stdout.write(result.stdout)
        raise SystemExit(f"build failed ({result.returncode})")


def measure(binary: Path, report_root: Path, container: str | None) -> dict[str, dict[str, int]]:
    results: dict[str, dict[str, int]] = {}
    for index, name in enumerate(WORKLOADS):
        selector = report_root / f"select-{index}"
        selector.write_bytes(bytes([index]))
        report_dir = report_root / name
        command = fuzz_lane.invocation(binary, ["measure", str(selector), f"--report-dir={report_dir}"], container)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
        if result.returncode != 0:
            sys.stdout.write(result.stdout + result.stderr)
            raise SystemExit(f"{name}: supervised measurement failed ({result.returncode})")
        observations = json.loads(result.stdout)
        report = json.loads((report_dir / "report.json").read_text())
        if report.get("outcome") != "passed" or report.get("metric_version") != "roc-fuzz-allocations/1":
            raise SystemExit(f"{name}: incomplete or failed supervisor report")
        named = {region["name"]: region["stats"]["allocs"] + region["stats"]["reallocs"] for region in observations if region["name"] != "$property"}
        if index < 4:
            expected = {"fonts", "author", "prepare", "emit"}
            if set(named) != expected:
                raise SystemExit(f"{name}: expected named phase observations, got {sorted(named)}")
            stages = {**named, "total": sum(named.values())}
        else:
            if set(named) != {name}:
                raise SystemExit(f"{name}: missing named kernel observation")
            stages = {"total": named[name]}
        # The debug protocol supplies output metadata only. Allocation evidence
        # comes directly from the supervisor's typed named observations.
        metadata = (report_dir / "run.log").read_text()
        stages.update({stage: int(value) for workload, stage, value in LINE.findall(metadata)
                       if workload == name and stage in {"pdf_bytes", "pdf_fnv", "output"}})
        if index < 4 and not {"pdf_bytes", "pdf_fnv"} <= stages.keys():
            raise SystemExit(f"{name}: missing PDF output metadata")
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
    parser.add_argument("--linux-x64-container", metavar="IMAGE", help="cross-build and measure the Linux x64musl profile")
    parser.add_argument("--no-cache", action="store_true", help="build without the compiler cache")
    parser.add_argument("--no-build", action="store_true", help="measure the existing binary")
    parser.add_argument("--compare", type=Path, help="compare against this saved run instead of the last one")
    parser.add_argument("--save", metavar="NAME", help="also save this run as .roc-pdf-tmp/profile/NAME.json")
    args = parser.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    host = fuzz_lane.host_target(args.linux_x64_container)
    binary = WORK / f"allocation_profile-{host}-{args.opt}-roc-fuzz-{fuzz_lane.PLATFORM_RELEASE}"
    if not args.no_build:
        build(binary, args.opt, not args.no_cache, host)
    report_root = WORK / f"measure-{host}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}-{os.getpid()}"
    report_root.mkdir()
    current = measure(binary, report_root, args.linux_x64_container)
    identity = {"format": "roc-pdf-profile/1", "metric_version": "roc-fuzz-allocations/1",
                "platform_release": fuzz_lane.PLATFORM_RELEASE, "platform_sha256": fuzz_lane.PLATFORM_SHA256,
                "allocation_count": "roc_alloc+roc_realloc",
                "compiler": subprocess.check_output([ROC, "version"], text=True).strip(), "host": host, "backend": args.opt}
    record = {**identity, "workloads": current}
    last = WORK / f"last-{host}-{args.opt}-roc-fuzz-{fuzz_lane.PLATFORM_RELEASE}.json"
    reference = args.compare or last
    previous_record = json.loads(reference.read_text()) if reference.is_file() else None
    if previous_record is not None and {k: previous_record.get(k) for k in identity} != identity:
        raise SystemExit("Profile instrumentation identity differs; keep the old evidence and make a fresh profile reference")
    previous = previous_record["workloads"] if previous_record is not None else None
    print(table(current, previous))
    if previous is not None:
        print(f"(compared with {reference.relative_to(ROOT) if reference.is_relative_to(ROOT) else reference})")
    last.write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")
    if args.save:
        (WORK / f"{args.save}.json").write_text(json.dumps(record, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
