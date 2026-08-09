#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from check_gate2 import validate_gate2_pdf
from check_gate3_actual_text import EXPECTED_CONTENT as GATE3_ACTUAL_TEXT_CONTENT
from check_gate3_actual_text import validate_gate3_actual_text_pdf
from check_gate3_caller_text import validate_gate3_caller_text_pdf
from check_gate3_facade_output import validate_facade_output_pdf
from check_gate3_text import EXPECTED_CONTENT as GATE3_TEXT_CONTENT
from check_gate3_text import validate_gate3_text_pdf
from check_pdf_structure import validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "tests" / "spec.json"
TEST_PLATFORM = ROOT / "tests" / "platform"
TEMP_ROOT = ROOT / ".roc-pdf-tmp"
ROC = os.environ.get("ROC", "roc")
ZIG = os.environ.get("ZIG", "zig")
METRICS_REPORT = re.compile(
    rb"ROC_METRICS protocol=([0-9]+) allocations=([0-9]+) work=([0-9]+(?:,[0-9]+)*)?\r?\n"
)
RETENTION_REPORT = re.compile(
    rb"ROC_RETENTION protocol=([0-9]+) backing_refs=([0-9]+) source_offset=([0-9]+) owned_capacity=([0-9]+)\r?\n"
    rb"ROC_METRICS protocol=([0-9]+) allocations=([0-9]+) work=([0-9]+(?:,[0-9]+)*)?\r?\n"
)


@dataclass(frozen=True)
class Metrics:
    allocations: int
    work: tuple[int, ...]


@dataclass(frozen=True)
class Retention:
    backing_refs: int
    source_offset: int
    owned_capacity: int


@dataclass(frozen=True)
class Toolchain:
    roc_optimization: str
    zig_version: str
    zig_optimization: str


@dataclass(frozen=True)
class TestCase:
    name: str
    scenario_revision: str
    source: Path
    snapshot: Path
    args: tuple[str, ...]
    measurement_boundary: str
    dimensions: dict[str, int]
    work_counters: tuple[str, ...]
    expectations: dict[str, Metrics]
    retention: Retention | None


@dataclass(frozen=True)
class TestSuite:
    protocol_version: int
    toolchain: Toolchain
    cases: tuple[TestCase, ...]


@dataclass(frozen=True)
class BaselineDelta:
    case_name: str
    expected: Metrics
    actual: Metrics


def command(executable: str, *args: str, cwd: Path = ROOT) -> None:
    command = [executable, *args]
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def command_output(executable: str, *args: str, cwd: Path = ROOT) -> str:
    command = [executable, *args]
    print("+", " ".join(command), flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    print(result.stdout, end="", flush=True)
    return result.stdout.strip()


def roc(*args: str) -> None:
    command(ROC, *args)


def repository_path(value: object, field: str) -> Path:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{SPEC_PATH}: {field} must be a non-empty string")

    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT):
        raise SystemExit(f"{SPEC_PATH}: {field} escapes the repository: {value}")
    return path


def non_empty_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{SPEC_PATH}: {field} must be a non-empty string")
    return value


def string_list(value: object, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise SystemExit(f"{SPEC_PATH}: {field} must be a list of strings")
    return tuple(value)


def load_suite() -> TestSuite:
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{SPEC_PATH}: top level must be an object")
    if set(data) != {"schema_version", "protocol_version", "toolchain", "cases"}:
        raise SystemExit(f"{SPEC_PATH}: unexpected top-level schema")
    if data["schema_version"] != 3 or data["protocol_version"] != 1:
        raise SystemExit(f"{SPEC_PATH}: schema_version must be 3 and protocol_version must be 1")

    raw_toolchain = data["toolchain"]
    toolchain_fields = {
        "roc_optimization",
        "zig_version",
        "zig_optimization",
    }
    if not isinstance(raw_toolchain, dict) or set(raw_toolchain) != toolchain_fields:
        raise SystemExit(f"{SPEC_PATH}: toolchain must contain exactly {sorted(toolchain_fields)}")
    toolchain = Toolchain(
        roc_optimization=non_empty_string(
            raw_toolchain["roc_optimization"], "toolchain.roc_optimization"
        ),
        zig_version=non_empty_string(raw_toolchain["zig_version"], "toolchain.zig_version"),
        zig_optimization=non_empty_string(
            raw_toolchain["zig_optimization"], "toolchain.zig_optimization"
        ),
    )
    if toolchain.roc_optimization not in {"speed", "size"}:
        raise SystemExit(f"{SPEC_PATH}: Roc allocation baselines require an optimized backend")
    if toolchain.zig_optimization not in {"ReleaseFast", "ReleaseSafe", "ReleaseSmall"}:
        raise SystemExit(f"{SPEC_PATH}: Zig host baselines require an optimized build")

    raw_cases = data.get("cases")
    if not isinstance(raw_cases, list) or not raw_cases:
        raise SystemExit(f"{SPEC_PATH}: cases must be a non-empty list")

    cases: list[TestCase] = []
    for raw in raw_cases:
        if not isinstance(raw, dict):
            raise SystemExit(f"{SPEC_PATH}: every case must be an object")

        required_fields = {
            "name",
            "scenario_revision",
            "source",
            "snapshot",
            "args",
            "measurement_boundary",
            "dimensions",
            "work_counters",
            "expectations",
            "retention",
        }
        if set(raw) != required_fields:
            raise SystemExit(f"{SPEC_PATH}: every case must contain exactly {sorted(required_fields)}")
        name = non_empty_string(raw["name"], "case.name")
        scenario_revision = non_empty_string(raw["scenario_revision"], f"{name}.scenario_revision")
        args = string_list(raw["args"], f"{name}.args")
        measurement_boundary = non_empty_string(
            raw["measurement_boundary"], f"{name}.measurement_boundary"
        )
        if measurement_boundary != "before_fixture_main":
            raise SystemExit(f"{SPEC_PATH}: {name}: unsupported measurement boundary")

        dimensions = raw["dimensions"]
        if (
            not isinstance(dimensions, dict)
            or not dimensions
            or any(not isinstance(key, str) or not key for key in dimensions)
            or any(type(value) is not int or value < 0 for value in dimensions.values())
        ):
            raise SystemExit(f"{SPEC_PATH}: {name}: dimensions must be non-negative integer fields")

        work_counters = string_list(raw["work_counters"], f"{name}.work_counters")
        if not work_counters or len(work_counters) != len(set(work_counters)):
            raise SystemExit(f"{SPEC_PATH}: {name}: work_counters must be non-empty and unique")

        raw_expectations = raw["expectations"]
        if not isinstance(raw_expectations, dict) or set(raw_expectations) != {"arm64mac", "x64musl"}:
            raise SystemExit(f"{SPEC_PATH}: {name}: expectations must cover every supported target")
        expectations: dict[str, Metrics] = {}
        for target, raw_metrics in raw_expectations.items():
            if not isinstance(raw_metrics, dict) or set(raw_metrics) != {"allocations", "work"}:
                raise SystemExit(f"{SPEC_PATH}: {name}.{target}: invalid metrics schema")
            allocations = raw_metrics["allocations"]
            work = raw_metrics["work"]
            if type(allocations) is not int or allocations < 0:
                raise SystemExit(f"{SPEC_PATH}: {name}.{target}: allocations must be non-negative")
            if (
                not isinstance(work, list)
                or len(work) != len(work_counters)
                or any(type(value) is not int or value < 0 for value in work)
            ):
                raise SystemExit(
                    f"{SPEC_PATH}: {name}.{target}: work must match the non-negative counter schema"
                )
            expectations[target] = Metrics(allocations, tuple(work))

        raw_retention = raw["retention"]
        if raw_retention is None:
            retention = None
        else:
            retention_fields = {"backing_refs", "source_offset", "owned_capacity"}
            if (
                not isinstance(raw_retention, dict)
                or set(raw_retention) != retention_fields
                or any(type(value) is not int or value < 0 for value in raw_retention.values())
            ):
                raise SystemExit(
                    f"{SPEC_PATH}: {name}.retention must contain exactly "
                    f"{sorted(retention_fields)}"
                )
            retention = Retention(
                backing_refs=raw_retention["backing_refs"],
                source_offset=raw_retention["source_offset"],
                owned_capacity=raw_retention["owned_capacity"],
            )

        source = repository_path(raw.get("source"), f"{name}.source")
        snapshot = repository_path(raw.get("snapshot"), f"{name}.snapshot")
        if not source.is_file():
            raise SystemExit(f"{SPEC_PATH}: {name}: source does not exist: {source}")
        if not snapshot.is_file():
            raise SystemExit(f"{SPEC_PATH}: {name}: snapshot does not exist: {snapshot}")
        cases.append(
            TestCase(
                name,
                scenario_revision,
                source,
                snapshot,
                args,
                measurement_boundary,
                dimensions,
                work_counters,
                expectations,
                retention,
            )
        )

    names = [case.name for case in cases]
    if len(names) != len(set(names)):
        raise SystemExit(f"{SPEC_PATH}: case names must be unique")
    retention_cases = [case for case in cases if case.retention is not None]
    if len(retention_cases) != 1:
        raise SystemExit(f"{SPEC_PATH}: exactly one backing-allocation retention case is required")

    discovered_snapshots = set((ROOT / "tests").glob("*/snapshot.pdf"))
    discovered_sources = {snapshot.parent / "main.roc" for snapshot in discovered_snapshots}
    missing_sources = sorted(source for source in discovered_sources if not source.is_file())
    if missing_sources:
        missing = ", ".join(relative(source) for source in missing_sources)
        raise SystemExit(f"Every snapshot needs an adjacent main.roc; missing: {missing}")
    if discovered_sources != {case.source for case in cases}:
        raise SystemExit("Test spec must cover every snapshotted test application")
    if discovered_snapshots != {case.snapshot for case in cases}:
        raise SystemExit("Test spec must cover every tests/*/snapshot.pdf")

    for case in cases:
        if case.source.parent != case.snapshot.parent:
            raise SystemExit(f"{SPEC_PATH}: {case.name}: source and snapshot must be adjacent")
    return TestSuite(data["protocol_version"], toolchain, tuple(cases))


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


def metrics_mismatch(expected: Metrics, actual: Metrics, work_counters: tuple[str, ...]) -> str | None:
    differences: list[str] = []
    if actual.allocations != expected.allocations:
        differences.append(
            f"allocations expected {expected.allocations}, got {actual.allocations}"
        )
    for name, expected_value, actual_value in zip(work_counters, expected.work, actual.work):
        if actual_value != expected_value:
            differences.append(f"{name} expected {expected_value}, got {actual_value}")
    if len(actual.work) != len(expected.work):
        differences.append(f"work counter count expected {len(expected.work)}, got {len(actual.work)}")
    return "; ".join(differences) if differences else None


def self_test_metrics(suite: TestSuite) -> None:
    case = suite.cases[0]
    expected = case.expectations["arm64mac"]
    allocation_regression = Metrics(expected.allocations + 1, expected.work)
    if metrics_mismatch(expected, allocation_regression, case.work_counters) is None:
        raise SystemExit("Performance baseline self-test accepted an allocation regression")
    changed_work = list(expected.work)
    changed_work[0] += 1
    work_regression = Metrics(expected.allocations, tuple(changed_work))
    if metrics_mismatch(expected, work_regression, case.work_counters) is None:
        raise SystemExit("Performance baseline self-test accepted a work regression")
    print("PASS performance baseline self-test", flush=True)


def roc_version_matches_pin(pinned_roc: str, actual_roc: str) -> bool:
    expected_roc = f"Roc compiler version {pinned_roc}"
    if actual_roc == expected_roc:
        return True

    pin_match = re.fullmatch(r"nightly-[0-9]{4}-[A-Za-z]+-[0-9]{2}-([0-9a-f]+)", pinned_roc)
    build_match = re.fullmatch(r"Roc compiler version release-fast-([0-9a-f]+)", actual_roc)
    if pin_match is None or build_match is None:
        return False

    pinned_commit = pin_match.group(1)
    build_commit = build_match.group(1)
    return len(pinned_commit) >= 7 and build_commit.startswith(pinned_commit)


def self_test_roc_version_pin() -> None:
    pin = "nightly-2026-August-05-24f0b47"
    if not roc_version_matches_pin(pin, f"Roc compiler version {pin}"):
        raise SystemExit("Roc version verifier rejected the nightly tag identity")
    if not roc_version_matches_pin(pin, "Roc compiler version release-fast-24f0b476"):
        raise SystemExit("Roc version verifier rejected the identical release-fast commit")
    if roc_version_matches_pin(pin, "Roc compiler version release-fast-deadbeef"):
        raise SystemExit("Roc version verifier accepted a different compiler commit")
    if roc_version_matches_pin("nightly-invalid", "Roc compiler version release-fast-24f0b476"):
        raise SystemExit("Roc version verifier accepted a malformed nightly pin")
    print("PASS Roc compiler pin self-test", flush=True)


def verify_toolchain(toolchain: Toolchain) -> None:
    pinned_roc = (ROOT / ".roc-version").read_text(encoding="utf-8").strip()
    if not pinned_roc:
        raise SystemExit(".roc-version must contain the pinned Roc release")
    actual_roc = command_output(ROC, "version")
    expected_roc = f"Roc compiler version {pinned_roc}"
    if not roc_version_matches_pin(pinned_roc, actual_roc):
        raise SystemExit(
            f".roc-version expects {expected_roc!r} or an identical release-fast commit, "
            f"got {actual_roc!r}"
        )
    actual_zig = command_output(ZIG, "version")
    if actual_zig != toolchain.zig_version:
        raise SystemExit(
            f"{SPEC_PATH}: expected Zig {toolchain.zig_version}, got {actual_zig}"
        )


def expected_content(dimensions: dict[str, int]) -> bytes:
    if dimensions.get("gate3_actual_text", 0) == 1:
        return GATE3_ACTUAL_TEXT_CONTENT
    if dimensions.get("gate3_visible_text", 0) == 1 or dimensions.get("gate3_caller_text", 0) == 1:
        return GATE3_TEXT_CONTENT
    if dimensions.get("gate2_minimal_content", 0) == 1:
        return (
            b"/P <</MCID 0>> BDC\n"
            b"/CS1_0 cs\n"
            b"0.50000763 scn\n"
            b"0 0 1 1 re\n"
            b"f\n"
            b"EMC\n"
            b"/Artifact <</Type /Background>> BDC\n"
            b"q\n"
            b"1 0 0 1 2 3 cm\n"
            b"q\n"
            b"2 0 0 1 4 5 cm\n"
            b"/Im1_0 Do\n"
            b"Q\n"
            b"Q\n"
            b"EMC\n"
        )
    length = dimensions.get("content_stream_bytes", 0)
    period = dimensions.get("content_pattern_period")
    if length == 0 and period is None:
        return b""
    if period != 4:
        raise SystemExit("content_stream_bytes requires the versioned four-byte q/Q pattern")
    pattern = b"q Q\n"
    return (pattern * ((length + len(pattern) - 1) // len(pattern)))[:length]


def run_case(
    case: TestCase,
    index: int,
    build_dir: Path,
    target: str,
    protocol_version: int,
    roc_optimization: str,
    update_snapshots: bool,
    compare_baselines: bool,
    linux_x64_container: str | None,
) -> BaselineDelta | None:
    executable = build_dir / f"case-{index}"
    roc(
        "build",
        relative(case.source),
        f"--opt={roc_optimization}",
        f"--target={target}",
        f"--output={executable}",
        "--no-cache",
    )

    if linux_x64_container is None:
        invocation = [executable, *case.args]
    else:
        invocation = [
            "docker",
            "run",
            "--rm",
            "--platform",
            "linux/amd64",
            "--volume",
            f"{ROOT}:{ROOT}:ro",
            "--workdir",
            str(ROOT),
            linux_x64_container,
            executable,
            *case.args,
        ]
    print("+", " ".join(str(value) for value in invocation), flush=True)
    result = subprocess.run(invocation, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise SystemExit(
            f"{case.name}: executable exited with {result.returncode}\n"
            f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )

    if case.retention is None:
        match = METRICS_REPORT.fullmatch(result.stderr)
        protocol_group = 1
        allocations_group = 2
        work_group = 3
    else:
        match = RETENTION_REPORT.fullmatch(result.stderr)
        protocol_group = 5
        allocations_group = 6
        work_group = 7
    if match is None:
        raise SystemExit(
            f"{case.name}: expected its versioned evidence report on stderr, got "
            f"{result.stderr!r}"
        )
    if case.retention is not None:
        retention_protocol = int(match.group(1))
        actual_retention = Retention(
            backing_refs=int(match.group(2)),
            source_offset=int(match.group(3)),
            owned_capacity=int(match.group(4)),
        )
        if retention_protocol != protocol_version or actual_retention != case.retention:
            raise SystemExit(
                f"{case.name}: retention evidence mismatch: "
                f"expected {case.retention}, got {actual_retention}"
            )

    actual_protocol = int(match.group(protocol_group))
    if actual_protocol != protocol_version:
        raise SystemExit(
            f"{case.name}: expected protocol {protocol_version}, got {actual_protocol}"
        )
    work_text = match.group(work_group)
    actual_work = () if not work_text else tuple(int(value) for value in work_text.split(b","))
    actual_metrics = Metrics(int(match.group(allocations_group)), actual_work)
    expected_metrics = case.expectations[target]
    mismatch = metrics_mismatch(expected_metrics, actual_metrics, case.work_counters)
    if mismatch is not None:
        if not compare_baselines:
            raise SystemExit(f"{case.name}: performance baseline mismatch: {mismatch}")
        print(f"DELTA {case.name}: {mismatch}", flush=True)

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
        f"{actual_metrics.allocations} allocations, "
        + ", ".join(
            f"{name}={value}" for name, value in zip(case.work_counters, actual_metrics.work)
        ),
        flush=True,
    )

    expected_pages = case.dimensions.get("pages")
    if expected_pages is not None:
        validate_pdf(
            result.stdout,
            expected_pages,
            expected_content(case.dimensions),
            case.dimensions.get("normalized_plan_identity", 0) == 1,
        )
        print(f"PASS {case.name}: independent offsets, lengths, xref, and page facts", flush=True)
        if case.dimensions.get("gate2_minimal_content", 0) == 1:
            validate_gate2_pdf(result.stdout)
            print(f"PASS {case.name}: exact normalized tagged structure and resources", flush=True)
        if case.dimensions.get("gate3_visible_text", 0) == 1:
            validate_gate3_text_pdf(result.stdout)
            print(f"PASS {case.name}: exact font, CID, Unicode mapping, and visible text facts", flush=True)
        if case.dimensions.get("gate3_caller_text", 0) == 1:
            validate_gate3_caller_text_pdf(result.stdout)
            print(f"PASS {case.name}: exact caller font identity, CID, Unicode mapping, and visible text facts", flush=True)
        if case.dimensions.get("gate3_facade_output", 0) == 1:
            validate_facade_output_pdf(result.stdout, "Café PDF generation in pure Roc.")
            print(f"PASS {case.name}: authored facade paragraph, Type 0 font, CID, and Unicode mapping facts", flush=True)
        if case.dimensions.get("gate3_actual_text", 0) == 1:
            validate_gate3_actual_text_pdf(result.stdout)
            print(f"PASS {case.name}: exact visual reordering and logical ActualText facts", flush=True)

    if mismatch is None:
        return None
    return BaselineDelta(case.name, expected_metrics, actual_metrics)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--update-snapshots",
        action="store_true",
        help="Replace PDF snapshots with the generated output after all other assertions pass",
    )
    parser.add_argument(
        "--compare-baselines",
        action="store_true",
        help=(
            "Run every case and report baseline differences after validating snapshots and "
            "structural evidence; this mode never accepts changed baselines"
        ),
    )
    parser.add_argument(
        "--linux-x64-container",
        metavar="IMAGE",
        help=(
            "Cross-compile x64musl cases and execute them in the named local linux/amd64 "
            "container image"
        ),
    )
    parser.add_argument(
        "--case",
        action="append",
        dest="case_names",
        metavar="NAME",
        help="Run only the exact named case; repeat to select multiple cases",
    )
    args = parser.parse_args()
    if args.update_snapshots and args.compare_baselines:
        parser.error("--update-snapshots and --compare-baselines cannot be combined")
    suite = load_suite()
    if args.case_names:
        requested = set(args.case_names)
        selected = tuple(case for case in suite.cases if case.name in requested)
        missing = requested - {case.name for case in selected}
        if missing:
            raise SystemExit(f"unknown test case(s): {', '.join(sorted(missing))}")
        suite = TestSuite(suite.protocol_version, suite.toolchain, selected)
    target = "x64musl" if args.linux_x64_container is not None else native_roc_target()

    if not args.update_snapshots:
        command(sys.executable, "scripts/check_contracts.py", "--self-test")
    command(sys.executable, "scripts/check_arlington.py", "--self-test")
    command(sys.executable, "scripts/check_pdfbox.py", "--self-test")
    command(sys.executable, "scripts/check_gate2.py", "--self-test")
    command(sys.executable, "scripts/check_gate2_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_gate3_text.py", "--self-test")
    command(sys.executable, "scripts/check_gate3_caller_text.py", "--self-test")
    command(sys.executable, "scripts/check_gate3_facade_output.py", "--self-test")
    command(sys.executable, "scripts/check_gate3_actual_text.py", "--self-test")
    command(sys.executable, "scripts/check_gate3_renderers.py", "--self-test")
    if not args.update_snapshots:
        command(sys.executable, "scripts/check_pdf_structure.py", "--self-test")
    self_test_metrics(suite)
    self_test_roc_version_pin()
    verify_toolchain(suite.toolchain)

    roc_sources = sorted((ROOT / "package").glob("*.roc"))
    compile_fixtures = sorted((ROOT / "examples").glob("*.roc"))
    roc_sources += compile_fixtures
    roc_sources += sorted((ROOT / "tests").rglob("*.roc"))
    for source in roc_sources:
        roc("fmt", "--check", relative(source))

    command(
        ZIG,
        "fmt",
        "--check",
        "build.zig",
        "host.zig",
        "retention_host.zig",
        "roc_platform_abi.zig",
        cwd=TEST_PLATFORM,
    )
    roc("check", "package/main.roc")
    roc("test", "package/main.roc")
    roc("test", "package/evidence.roc")
    for fixture in compile_fixtures:
        roc("test", relative(fixture))
    command(
        ZIG,
        "build",
        f"-Doptimize={suite.toolchain.zig_optimization}",
        cwd=TEST_PLATFORM,
    )

    TEMP_ROOT.mkdir(exist_ok=True)
    baseline_deltas: list[BaselineDelta] = []
    with tempfile.TemporaryDirectory(prefix="test-", dir=TEMP_ROOT) as temporary:
        build_dir = Path(temporary)
        for index, case in enumerate(suite.cases):
            delta = run_case(
                case,
                index,
                build_dir,
                target,
                suite.protocol_version,
                suite.toolchain.roc_optimization,
                args.update_snapshots,
                args.compare_baselines,
                args.linux_x64_container,
            )
            if delta is not None:
                baseline_deltas.append(delta)

    if args.update_snapshots:
        command(sys.executable, "scripts/check_contracts.py", "--self-test")
        command(sys.executable, "scripts/check_pdf_structure.py", "--self-test")

    if baseline_deltas:
        print("\nAllocation baseline comparison:", flush=True)
        print("| Case | Expected | Actual | Delta | Work counters |", flush=True)
        print("| --- | ---: | ---: | ---: | --- |", flush=True)
        for delta in baseline_deltas:
            work_status = "unchanged" if delta.expected.work == delta.actual.work else "CHANGED"
            allocation_delta = delta.actual.allocations - delta.expected.allocations
            print(
                f"| {delta.case_name} | {delta.expected.allocations} | "
                f"{delta.actual.allocations} | {allocation_delta:+d} | {work_status} |",
                flush=True,
            )
        raise SystemExit(
            "Performance baselines differ; review and update tests/spec.json deliberately"
        )


if __name__ == "__main__":
    main()
