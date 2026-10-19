#!/usr/bin/env python3
"""Attribute Roc allocations in one `allocation_profile` workload to functions.

Builds `fuzz/allocation_profile.roc` with `--opt=speed --debug` (the dev
backend emits no debug info for Roc procedures), replays one workload under
gdb with a breakpoint on `roc_alloc`/`roc_realloc`, and reports:

- self: allocations whose innermost Roc frame is the function,
- inclusive: allocations with the function anywhere on the stack.

Frames include inlined functions. Counts cover the whole replay, including
the fuzz runner's own few allocations, so compare them with the stage totals
from `scripts/profile.py` rather than expecting an exact match.

```sh
./scripts/alloc_trace.py --workload 2            # builtin_paragraphs
./scripts/alloc_trace.py --workload 0 --top 60 --filter KernelLineLayout
```
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
WORK = ROOT / ".roc-pdf-tmp" / "profile"
SOURCE = ROOT / "fuzz" / "allocation_profile.roc"
# Frames that only forward an allocation: builtins, the host, and the runner.
NOISE = (
    "roc_", "allocImpl", "list.", "str.", "utils.", "dev_wrappers.", "?",
    "Fuzz.", "Target.", "main", "fuzzer::", "LLVMFuzzer", "__libc", "_start",
)


def build(binary: Path, cache: bool) -> None:
    command = [ROC, "build", "--opt=speed", "--debug", str(SOURCE.relative_to(ROOT)), f"--output={binary}"]
    if not cache:
        command.append("--no-cache")
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode not in (0, 2) or not binary.is_file():
        sys.stdout.write(result.stdout)
        raise SystemExit(f"build failed ({result.returncode})")


def symbol_names(binary: Path) -> dict[str, str]:
    """Map `roc__p<hash>` linkage names to their Roc procedure names."""
    dump = subprocess.run(["llvm-dwarfdump-18", "--debug-info", str(binary)], stdout=subprocess.PIPE, text=True).stdout
    names: dict[str, str] = {}
    linkage = None
    for line in dump.splitlines():
        line = line.strip()
        if line.startswith("DW_AT_linkage_name"):
            linkage = line.split('("', 1)[1].rstrip('")')
        elif line.startswith("DW_AT_name") and linkage is not None:
            names.setdefault(linkage, line.split('("', 1)[1].rstrip('")'))
            linkage = None
        elif line.startswith("0x"):
            linkage = None
    return names


BUILTINS: set[str] = set()


def is_builtin(label: str) -> bool:
    return label.startswith("Builtin.") or label in BUILTINS


def frame_label(frame: str, names: dict[str, str], lines: bool) -> str:
    symbol, _, where = frame.partition("@")
    label = names.get(symbol, symbol)
    label = f"{label} ({where})" if lines and where else label
    if "<roc-generated>" in where:
        BUILTINS.add(label)
    return label


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--workload", type=int, default=0, help="selector byte (see fuzz/ProfileWorkloads.roc)")
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument("--filter", default="", help="only report functions containing this text")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--stacks", type=int, default=0, help="also print this many heaviest call stacks")
    parser.add_argument("--lines", action="store_true", help="attribute to call-site lines, not just functions")
    args = parser.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    binary = WORK / "allocation_profile-trace"
    if not args.no_build:
        build(binary, not args.no_cache)
    selector = WORK / f"select-{args.workload}"
    selector.write_bytes(bytes([args.workload]))
    out = WORK / f"trace-{args.workload}.json"
    env = dict(os.environ, ALLOC_TRACE_OUT=str(out))
    result = subprocess.run(
        ["gdb", "-batch", "-nx", "-x", str(ROOT / "scripts" / "alloc_trace_gdb.py"), "--args", str(binary), "replay", str(selector)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if not out.is_file():
        sys.stdout.write(result.stdout[-4000:])
        raise SystemExit("trace failed")
    records = json.loads(out.read_text())
    names = symbol_names(binary)

    self_counts: collections.Counter[str] = collections.Counter()
    inclusive: collections.Counter[str] = collections.Counter()
    stacks: collections.Counter[tuple[str, ...]] = collections.Counter()
    total = 0
    for record in records:
        labels = [frame_label(frame, names, args.lines) for frame in record["stack"]]
        roc = [name for name in labels if not any(name.startswith(prefix) for prefix in NOISE)]
        count = record["count"]
        total += count
        if roc:
            # Attribute to the first package frame, naming the builtin it
            # allocated through: `caller [Builtin.List.append]`. Builtins
            # are compiler-generated frames (no package source file).
            generated = [name for name in roc if is_builtin(name)]
            owner = next((name for name in roc if not is_builtin(name)), roc[0])
            inner = generated[0] if generated and roc.index(generated[0]) < roc.index(owner) else None
            self_counts[f"{owner} [{inner}]" if inner else owner] += count
        for name in set(roc):
            inclusive[name] += count
        stacks[tuple(roc[:8])] += count

    def show(title: str, counter: collections.Counter[str]) -> None:
        print(f"\n{title}")
        shown = 0
        for name, count in counter.most_common():
            if args.filter in name:
                print(f"{count:>8}  {name}")
                shown += 1
                if shown >= args.top:
                    break

    print(f"{total} allocation events in workload {args.workload}")
    show("self (innermost Roc frame)", self_counts)
    show("inclusive", inclusive)
    if args.stacks:
        print()
        for stack, count in stacks.most_common(args.stacks):
            print(f"{count:>8}  " + " <- ".join(stack))


if __name__ == "__main__":
    main()
