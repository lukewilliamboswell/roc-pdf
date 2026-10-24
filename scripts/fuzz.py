#!/usr/bin/env python3
"""Build and run the property fuzz targets in `fuzz/`, as a smoke run or a campaign.

The targets are evidence-only applications on the content-addressed `roc-fuzz`
platform. They are software-quality tests for correctness, determinism, bounded
error handling, and invariant preservation; they do not make a security claim.

`scripts/test.py` already applies `roc fmt --check`, `roc check`, and `roc test`
to every `fuzz/*.roc` source, which runs the `expect`s a target retains but
never executes the property against generated input. This lane does that.

Each target is built with `--fuzz` for libFuzzer coverage instrumentation and
run against its seed corpus. A crash, a per-input timeout, a memory-limit
breach, or a run that outlives its hard deadline fails the lane; every target
still runs, and failing inputs are saved under `.roc-pdf-tmp/fuzz-artifacts/`.

`--mode smoke` (the default, and what pull-request CI runs) replays the
committed seed corpus plus a few fixed-seed generated inputs, capped at one
second of workload per target, so every target keeps building and its property
keeps executing. `--mode campaign` is the bounded search that
`.github/workflows/fuzz.yml` runs on a schedule; it never runs on a pull
request.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roc_diagnostics import tolerated_warnings_only  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
WORK = ROOT / ".roc-pdf-tmp" / "fuzz"
SEEDS = ROOT / ".roc-pdf-tmp" / "fuzz-corpus"
ARTIFACTS = ROOT / ".roc-pdf-tmp" / "fuzz-artifacts"

# Smoke runs replay the seed corpus and then a handful of generated inputs
# from a fixed seed. `--time` caps the workload at the one-second smoke budget
# should a large corpus take longer; it ends the run normally. The hard
# deadline is separate: a target still running after it is killed and fails.
SMOKE_RUNS = 64
SMOKE_SECONDS = 1
SMOKE_SEED = 1
CAMPAIGN_RUNS = 2000
SMOKE_DEADLINE_SECONDS = 60
CAMPAIGN_DEADLINE_SECONDS = 1800

# Valid fonts are the only corpus that gets a raw-byte inspector past its
# directory layer, so the font targets are seeded from the tracked faces.
FONT_SEED_SOURCES = (
    "vendor/fonts/*.ttf",
    "tests/assets/*.ttf",
)


@dataclass(frozen=True)
class Target:
    """One fuzz application root and the bounds its smoke run uses."""

    name: str
    max_input_size: int
    corpus: str | None = None
    seed_fonts: bool = False


# `max_input_size` is per target because the generators differ: the raw-byte
# inspectors consume their input directly and need room for a real font or
# image, while the structured generators encode a typed value from far fewer
# bytes and only waste time on a larger bound.
TARGETS = (
    Target("font_inspector_mutation", 524288, seed_fonts=True),
    Target("font_inspector_repair", 512),
    Target("font_subset_roundtrip", 2048),
    Target("jpeg_inspector_mutation", 65536, corpus="tests/assets/jpeg-fuzz-corpus"),
    Target("facade_output_equivalence", 4096),
    Target("facade_structure", 4096),
    Target("navigation_property", 4096),
    Target("registry_property", 4096),
    Target("theme_options", 4096),
)


class LaneFailure(Exception):
    pass


def run(command: list[str], *, cwd: Path = ROOT, deadline: float | None = None) -> None:
    printable = " ".join(str(part) for part in command)
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=deadline,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        sys.stdout.write(output if isinstance(output, str) else output.decode(errors="replace"))
        raise LaneFailure(f"exceeded the {deadline:.0f}s hard deadline: {printable}") from None
    sys.stdout.write(result.stdout)
    if result.returncode == 0:
        return
    # Warnings located in a downloaded package are the only tolerated ones
    # (see scripts/roc_diagnostics.py).
    if result.returncode == 2 and tolerated_warnings_only(result.stdout):
        return
    raise LaneFailure(f"failed ({result.returncode}): {printable}")


def seed_font_corpus() -> Path:
    """Copy the tracked faces into an ignored directory libFuzzer can own.

    libFuzzer writes newly interesting inputs back into the corpus directory it
    is given, so it must never be pointed at tracked files.
    """
    corpus = SEEDS / "fonts"
    if corpus.exists():
        shutil.rmtree(corpus)
    corpus.mkdir(parents=True)
    count = 0
    for pattern in FONT_SEED_SOURCES:
        for source in sorted(ROOT.glob(pattern)):
            shutil.copyfile(source, corpus / source.name)
            count += 1
    if count == 0:
        raise SystemExit(f"no font seeds matched {FONT_SEED_SOURCES}")
    return corpus


def corpus_for(target: Target) -> Path:
    if target.seed_fonts:
        return seed_font_corpus()
    if target.corpus is not None:
        # A tracked corpus is copied for the same reason: the run would
        # otherwise deposit generated inputs beside the manifested assets and
        # break the provenance closure check.
        tracked = ROOT / target.corpus
        if not tracked.is_dir():
            raise SystemExit(f"{target.name}: missing corpus {target.corpus}")
        corpus = SEEDS / target.name
        if corpus.exists():
            shutil.rmtree(corpus)
        shutil.copytree(tracked, corpus)
        return corpus
    corpus = SEEDS / target.name
    corpus.mkdir(parents=True, exist_ok=True)
    return corpus


@dataclass(frozen=True)
class Budget:
    """How long one target searches: a run count and an optional time cap."""

    runs: int
    seconds: int | None
    seed: int | None
    deadline: float


def fuzz_target(target: Target, budget: Budget, timeout: int, memory_limit: int) -> float:
    source = ROOT / "fuzz" / f"{target.name}.roc"
    if not source.is_file():
        raise LaneFailure(f"missing {source.relative_to(ROOT)}")
    binary = WORK / target.name
    run([ROC, "build", "--fuzz", str(source.relative_to(ROOT)), f"--output={binary}"])
    corpus = corpus_for(target)
    artifacts = ARTIFACTS / target.name
    if artifacts.exists():
        shutil.rmtree(artifacts)
    artifacts.mkdir(parents=True)
    command = [
        str(binary),
        "run",
        str(corpus),
        f"--runs={budget.runs}",
        f"--time={budget.seconds if budget.seconds is not None else 0}",
        f"--max-input-size={target.max_input_size}",
        f"--timeout={timeout}",
        f"--memory-limit={memory_limit}",
        f"--artifact-dir={artifacts}",
    ]
    if budget.seed is not None:
        command.append(f"--seed={budget.seed}")
    started = time.monotonic()
    run(command, deadline=budget.deadline)
    return time.monotonic() - started


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--mode",
        choices=("smoke", "campaign"),
        default="smoke",
        help="smoke: replay seeds plus a few fixed-seed inputs within one second per target (default); "
        f"campaign: a bounded search of --runs inputs per target (default {CAMPAIGN_RUNS})",
    )
    parser.add_argument("--runs", type=int, help="campaign executions per target")
    parser.add_argument(
        "--targets",
        action="append",
        metavar="NAME",
        help="run only this target; repeatable",
    )
    parser.add_argument("--timeout", type=int, default=10, help="seconds per target call")
    parser.add_argument("--memory-limit", type=int, default=2048, help="MB per target process")
    args = parser.parse_args()

    known = {target.name: target for target in TARGETS}
    if args.targets:
        unknown = sorted(set(args.targets) - set(known))
        if unknown:
            raise SystemExit(f"unknown targets: {', '.join(unknown)}")
        selected = [known[name] for name in args.targets]
    else:
        selected = list(TARGETS)

    if args.mode == "smoke":
        if args.runs is not None:
            raise SystemExit("--runs applies to --mode campaign; smoke runs are fixed")
        budget = Budget(SMOKE_RUNS, SMOKE_SECONDS, SMOKE_SEED, SMOKE_DEADLINE_SECONDS)
    else:
        runs = CAMPAIGN_RUNS if args.runs is None else args.runs
        if runs < 1:
            raise SystemExit("--runs must be positive")
        budget = Budget(runs, None, None, CAMPAIGN_DEADLINE_SECONDS)

    WORK.mkdir(parents=True, exist_ok=True)
    SEEDS.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    for target in selected:
        try:
            elapsed = fuzz_target(target, budget, args.timeout, args.memory_limit)
        except LaneFailure as error:
            print(f"FAIL {target.name}: {error}", flush=True)
            failures.append(target.name)
        else:
            print(f"PASS {target.name} ({args.mode}, {budget.runs} runs, workload {elapsed:.1f}s)", flush=True)
    if failures:
        raise SystemExit(
            f"fuzz {args.mode} failed for {', '.join(failures)}; inputs are under {ARTIFACTS.relative_to(ROOT)}/"
        )
    print(f"PASS fuzz {args.mode} ({len(selected)} targets)", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
