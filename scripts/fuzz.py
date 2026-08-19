#!/usr/bin/env python3
"""Build and smoke-run the bounded property fuzz targets in `fuzz/`.

The targets are evidence-only applications on the content-addressed `roc-fuzz`
platform. They are software-quality tests for correctness, determinism, bounded
error handling, and invariant preservation; they do not make a security claim.

This lane exists because compiling a target proves nothing about its property.
`scripts/test.py` already applies `roc fmt --check`, `roc check`, and `roc test`
to every `fuzz/*.roc` source, which runs the `expect`s a target retains but
never executes the property against generated input. A short bounded campaign
per target is what turns a written property into a checked one.

Each target is built with `--fuzz` for libFuzzer coverage instrumentation and
run for a bounded number of executions against its seed corpus. A crash, a
timeout, or a memory-limit breach fails the run. Long campaigns and corpus
accumulation are a separate concern and are not performed here.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
WORK = ROOT / ".roc-pdf-tmp" / "fuzz"
SEEDS = ROOT / ".roc-pdf-tmp" / "fuzz-corpus"

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


def run(command: list[str], *, cwd: Path = ROOT) -> None:
    printable = " ".join(str(part) for part in command)
    try:
        subprocess.run(command, cwd=cwd, check=True)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"fuzz lane failed ({error.returncode}): {printable}")


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


def smoke(target: Target, runs: int, timeout: int, memory_limit: int) -> None:
    source = ROOT / "fuzz" / f"{target.name}.roc"
    if not source.is_file():
        raise SystemExit(f"{target.name}: missing {source.relative_to(ROOT)}")
    binary = WORK / target.name
    run([ROC, "build", "--fuzz", str(source.relative_to(ROOT)), f"--output={binary}"])
    corpus = corpus_for(target)
    run(
        [
            str(binary),
            "run",
            str(corpus),
            f"--runs={runs}",
            f"--max-input-size={target.max_input_size}",
            f"--timeout={timeout}",
            f"--memory-limit={memory_limit}",
        ]
    )
    print(f"PASS {target.name} ({runs} runs)", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runs",
        type=int,
        default=2000,
        help="executions per target (default: 2000)",
    )
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

    if args.runs < 1:
        raise SystemExit("--runs must be positive")

    WORK.mkdir(parents=True, exist_ok=True)
    SEEDS.mkdir(parents=True, exist_ok=True)
    for target in selected:
        smoke(target, args.runs, args.timeout, args.memory_limit)
    print(f"PASS bounded fuzz lane ({len(selected)} targets)", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
