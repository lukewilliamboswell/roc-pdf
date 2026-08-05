#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "tests" / "spec.json"
TEST_PLATFORM = ROOT / "tests" / "platform"
TEMP_ROOT = ROOT / ".roc-pdf-tmp"
ROC = os.environ.get("ROC", "roc")
ZIG = os.environ.get("ZIG", "zig")
ALLOCATION_REPORT = re.compile(rb"ROC_ALLOCATIONS=([0-9]+)\r?\n")


@dataclass(frozen=True)
class TestCase:
    name: str
    source: Path
    snapshot: Path
    allocations: int


def command(executable: str, *args: str, cwd: Path = ROOT) -> None:
    command = [executable, *args]
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def roc(*args: str) -> None:
    command(ROC, *args)


def repository_path(value: object, field: str) -> Path:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{SPEC_PATH}: {field} must be a non-empty string")

    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT):
        raise SystemExit(f"{SPEC_PATH}: {field} escapes the repository: {value}")
    return path


def load_cases() -> list[TestCase]:
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{SPEC_PATH}: top level must be an object")
    raw_cases = data.get("cases")
    if not isinstance(raw_cases, list) or not raw_cases:
        raise SystemExit(f"{SPEC_PATH}: cases must be a non-empty list")

    cases: list[TestCase] = []
    for raw in raw_cases:
        if not isinstance(raw, dict):
            raise SystemExit(f"{SPEC_PATH}: every case must be an object")

        name = raw.get("name")
        allocations = raw.get("allocations")
        if not isinstance(name, str) or not name:
            raise SystemExit(f"{SPEC_PATH}: every case needs a non-empty name")
        if type(allocations) is not int or allocations < 0:
            raise SystemExit(f"{SPEC_PATH}: {name}: allocations must be a non-negative integer")

        source = repository_path(raw.get("source"), f"{name}.source")
        snapshot = repository_path(raw.get("snapshot"), f"{name}.snapshot")
        if not source.is_file():
            raise SystemExit(f"{SPEC_PATH}: {name}: source does not exist: {source}")
        if not snapshot.is_file():
            raise SystemExit(f"{SPEC_PATH}: {name}: snapshot does not exist: {snapshot}")
        cases.append(TestCase(name, source, snapshot, allocations))

    names = [case.name for case in cases]
    sources = [case.source for case in cases]
    snapshots = [case.snapshot for case in cases]
    if len(names) != len(set(names)):
        raise SystemExit(f"{SPEC_PATH}: case names must be unique")
    if len(sources) != len(set(sources)):
        raise SystemExit(f"{SPEC_PATH}: case sources must be unique")
    if len(snapshots) != len(set(snapshots)):
        raise SystemExit(f"{SPEC_PATH}: case snapshots must be unique")

    discovered_snapshots = set((ROOT / "tests").glob("*/snapshot.pdf"))
    discovered_sources = {snapshot.parent / "main.roc" for snapshot in discovered_snapshots}
    missing_sources = sorted(source for source in discovered_sources if not source.is_file())
    if missing_sources:
        missing = ", ".join(relative(source) for source in missing_sources)
        raise SystemExit(f"Every snapshot needs an adjacent main.roc; missing: {missing}")
    if discovered_sources != set(sources):
        raise SystemExit("Test spec must list every snapshotted test application exactly once")
    if discovered_snapshots != set(snapshots):
        raise SystemExit("Test spec must list every tests/*/snapshot.pdf snapshot exactly once")

    for case in cases:
        if case.source.parent != case.snapshot.parent:
            raise SystemExit(f"{SPEC_PATH}: {case.name}: source and snapshot must be adjacent")
    return cases


def native_roc_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Darwin" and machine in {"arm64", "aarch64"}:
        return "arm64mac"
    if system == "Linux" and machine in {"x86_64", "amd64"}:
        return "x64musl"
    raise SystemExit(
        f"The test host supports only macOS AArch64 and Linux x86-64; got {system} {machine}"
    )


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def describe_bytes(value: bytes) -> str:
    return f"{len(value)} bytes, sha256={hashlib.sha256(value).hexdigest()}"


def first_difference(expected: bytes, actual: bytes) -> str:
    shared = min(len(expected), len(actual))
    offset = next((index for index in range(shared) if expected[index] != actual[index]), shared)
    start = max(0, offset - 8)
    end = offset + 8
    return (
        f"first difference at byte {offset}; "
        f"expected[{start}:{end}]={expected[start:end].hex()}, "
        f"actual[{start}:{end}]={actual[start:end].hex()}"
    )


def run_case(
    case: TestCase,
    index: int,
    build_dir: Path,
    target: str,
    update_snapshots: bool,
) -> None:
    executable = build_dir / f"case-{index}"
    roc(
        "build",
        relative(case.source),
        "--opt=dev",
        f"--target={target}",
        f"--output={executable}",
        "--no-cache",
    )

    print(f"+ {executable}", flush=True)
    result = subprocess.run(executable, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise SystemExit(
            f"{case.name}: executable exited with {result.returncode}\n"
            f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )

    match = ALLOCATION_REPORT.fullmatch(result.stderr)
    if match is None:
        raise SystemExit(
            f"{case.name}: expected only ROC_ALLOCATIONS=<count> on stderr, got "
            f"{result.stderr!r}"
        )

    actual_allocations = int(match.group(1))
    if actual_allocations != case.allocations:
        raise SystemExit(
            f"{case.name}: expected {case.allocations} Roc allocations, got {actual_allocations}"
        )

    expected = case.snapshot.read_bytes()
    if update_snapshots:
        if expected != result.stdout:
            case.snapshot.write_bytes(result.stdout)
            print(f"Updated {relative(case.snapshot)}")
    elif expected != result.stdout:
        raise SystemExit(
            f"{case.name}: PDF snapshot mismatch\n"
            f"expected {describe_bytes(expected)}\n"
            f"actual   {describe_bytes(result.stdout)}\n"
            f"{first_difference(expected, result.stdout)}"
        )

    print(
        f"PASS {case.name}: {describe_bytes(result.stdout)}, "
        f"{actual_allocations} allocations",
        flush=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--update-snapshots",
        action="store_true",
        help="Replace PDF snapshots with the generated output after all other assertions pass",
    )
    args = parser.parse_args()
    cases = load_cases()
    target = native_roc_target()

    roc("version")
    command(ZIG, "version")

    roc_sources = sorted((ROOT / "package").glob("*.roc"))
    compile_fixtures = sorted((ROOT / "examples").glob("*.roc"))
    roc_sources += compile_fixtures
    roc_sources += sorted(case.source for case in cases)
    roc_sources.append(TEST_PLATFORM / "main.roc")
    for source in roc_sources:
        roc("fmt", "--check", relative(source))

    command(
        ZIG,
        "fmt",
        "--check",
        "build.zig",
        "host.zig",
        "roc_platform_abi.zig",
        cwd=TEST_PLATFORM,
    )
    roc("check", "package/main.roc")
    roc("test", "package/main.roc")
    for fixture in compile_fixtures:
        roc("test", relative(fixture))
    command(ZIG, "build", "-Doptimize=ReleaseSafe", cwd=TEST_PLATFORM)

    TEMP_ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="test-", dir=TEMP_ROOT) as temporary:
        build_dir = Path(temporary)
        for index, case in enumerate(cases):
            run_case(case, index, build_dir, target, args.update_snapshots)


if __name__ == "__main__":
    main()
