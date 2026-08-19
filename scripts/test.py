#!/usr/bin/env python3
from __future__ import annotations

import argparse
import atexit
import concurrent.futures
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from dataclasses import dataclass
from pathlib import Path

from check_tagged_visual import validate_tagged_visual_pdf
from check_actual_text import EXPECTED_CONTENT as ACTUAL_TEXT_CONTENT
from check_actual_text import validate_actual_text_pdf
from check_caller_text import validate_caller_text_pdf
from check_caller_facade import validate_caller_facade_pdf
from check_facade_output import fixture_oracle, validate_facade_output_pdf
from check_supplementary_text import EXPECTED_CONTENT as SUPPLEMENTARY_TEXT_CONTENT
from check_supplementary_text import validate_supplementary_text_pdf
from check_cjk_text import EXPECTED_CONTENT as CJK_TEXT_CONTENT
from check_cjk_text import validate_cjk_text_pdf
from check_combining import validate_combining_pdf
from check_ligature import EXPECTED_CONTENT as LIGATURE_CONTENT
from check_ligature import validate_ligature_pdf
from check_multiface_facade import validate_multiface_facade_pdf
from check_multiface_text import validate_multiface_text_pdf
from check_case_text import validate_case_pdf
from check_rtl import validate_rtl_pdf
from check_soft_hyphen import EXPECTED_CONTENT as SOFT_HYPHEN_CONTENT
from check_soft_hyphen import validate_soft_hyphen_pdf
from check_external_discretionary_hyphen import EXPECTED_CONTENT as EXTERNAL_DISCRETIONARY_HYPHEN_CONTENT
from check_external_discretionary_hyphen import validate_external_discretionary_hyphen_pdf
from check_generated_labels import validate_generated_labels_pdf
from check_text import EXPECTED_CONTENT as TEXT_CONTENT
from check_text import validate_text_pdf
from check_color_images import validate_color_images_pdf
from check_shadings import validate_shadings_pdf
from check_soft_masks import validate_soft_masks_pdf
from check_transparency import validate_transparency_pdf
from check_fonts import validate_fonts_pdf
from check_forms import validate_forms_pdf
from check_metadata import validate_metadata_pdf
from check_navigation import validate_navigation_pdf
from check_pdf_structure import validate_pdf


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "tests" / "spec.json"
TEST_PLATFORM = ROOT / "tests" / "platform"
TEMP_ROOT = ROOT / ".roc-pdf-tmp"
LOG_ROOT = TEMP_ROOT / "logs"

ROC = os.environ.get("ROC", "roc")
ZIG = os.environ.get("ZIG", "zig")
RUN_LOG: Path | None = None
VERBOSE = False
LOG_LOCK = threading.Lock()
PROGRESS_LOCK = threading.Lock()
PROGRESS_STEP = 0
PROGRESS_TOTAL = 0
PROCESS_LOCK = threading.Lock()
ACTIVE_PROCESSES: set[subprocess.Popen[object]] = set()
SNAPSHOT_LOCKS: dict[Path, threading.Lock] = {}
UPDATED_SNAPSHOT_BYTES: dict[Path, bytes] = {}
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
    validation_sources: tuple[Path, ...]
    validation_skips: tuple["ValidationSkip", ...]
    cases: tuple[TestCase, ...]


@dataclass(frozen=True)
class ValidationSkip:
    pattern: str
    actions: frozenset[str]
    reason: str


@dataclass(frozen=True)
class BaselineDelta:
    case_name: str
    expected: Metrics
    actual: Metrics


@dataclass(frozen=True)
class CaseRunResult:
    delta: BaselineDelta | None
    metrics: Metrics
    output_bytes: int


def timestamp() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def log(message: str) -> None:
    if RUN_LOG is not None and message:
        with LOG_LOCK:
            with RUN_LOG.open("a", encoding="utf-8") as stream:
                lines = message.splitlines() or [""]
                for line in lines:
                    stream.write(f"[{timestamp()}] {line}\n")


def detail(message: str) -> None:
    log(message)
    if VERBOSE:
        print(f"[{timestamp()}] {message}", flush=True)


def colored(label: str) -> str:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR") is not None:
        return label
    colors = {
        "PASS": "\033[32m",
        "FAIL": "\033[31m",
        "SKIP": "\033[33m",
        "RUN": "\033[36m",
    }
    color = colors.get(label)
    return label if color is None else f"{color}{label}\033[0m"


def progress(label: str, message: str) -> None:
    global PROGRESS_STEP
    with PROGRESS_LOCK:
        PROGRESS_STEP += 1
        step = PROGRESS_STEP
        total = PROGRESS_TOTAL
    rendered = f"[{timestamp()}] [{step:04d}/{total:04d}] {colored(label):4s} {message}"
    print(rendered, flush=True)
    log(f"[{step:04d}/{total:04d}] {label:4s} {message}")


def announce(label: str, message: str, *, stderr: bool = False) -> None:
    stream = sys.stderr if stderr else sys.stdout
    for line in message.splitlines() or [""]:
        print(f"[{timestamp()}] {colored(label)} {line}", file=stream, flush=True)
    log(f"{label} {message}")


def phase(message: str) -> None:
    announce("RUN", message)


def snapshot_lock(path: Path) -> threading.Lock:
    with LOG_LOCK:
        return SNAPSHOT_LOCKS.setdefault(path, threading.Lock())


def managed_run(
    values: list[str | Path],
    *,
    cwd: Path,
    text: bool = False,
    stderr: int | None = subprocess.PIPE,
) -> subprocess.CompletedProcess:
    process = subprocess.Popen(
        values,
        cwd=cwd,
        text=text,
        stdout=subprocess.PIPE,
        stderr=stderr,
        start_new_session=True,
    )
    with PROCESS_LOCK:
        ACTIVE_PROCESSES.add(process)
    try:
        stdout, stderr_output = process.communicate()
        return subprocess.CompletedProcess(values, process.returncode, stdout, stderr_output)
    finally:
        with PROCESS_LOCK:
            ACTIVE_PROCESSES.discard(process)


def terminate_active_processes() -> None:
    with PROCESS_LOCK:
        processes = tuple(ACTIVE_PROCESSES)
    for process in processes:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def cancel_parallel(
    executor: concurrent.futures.ThreadPoolExecutor,
    futures: list[concurrent.futures.Future],
) -> None:
    terminate_active_processes()
    for future in futures:
        future.cancel()
    executor.shutdown(wait=False, cancel_futures=True)


def command(executable: str, *args: str, cwd: Path = ROOT) -> None:
    values = [executable, *args]
    rendered = "+ " + " ".join(values)
    log(rendered)
    started = time.monotonic()
    result = managed_run(values, cwd=cwd, text=True, stderr=subprocess.STDOUT)
    log(result.stdout)
    if result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-30:])
        raise SystemExit(f"command failed ({result.returncode}): {rendered}\n{tail}\nFull log: {RUN_LOG}")
    detail(f"PASS command ({time.monotonic() - started:.1f}s): {' '.join(values)}")


def command_output(executable: str, *args: str, cwd: Path = ROOT) -> str:
    command = [executable, *args]
    log("+ " + " ".join(command))
    result = managed_run(command, cwd=cwd, text=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, command, result.stdout, result.stderr)
    log(result.stdout)
    if VERBOSE:
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
    if set(data) != {"schema_version", "protocol_version", "validation", "toolchain", "cases"}:
        raise SystemExit(f"{SPEC_PATH}: unexpected top-level schema")
    if data["schema_version"] != 4 or data["protocol_version"] != 1:
        raise SystemExit(f"{SPEC_PATH}: schema_version must be 4 and protocol_version must be 1")

    raw_validation = data["validation"]
    if not isinstance(raw_validation, dict) or set(raw_validation) != {"sources", "skips"}:
        raise SystemExit(f"{SPEC_PATH}: validation must contain exactly sources and skips")
    source_patterns = string_list(raw_validation["sources"], "validation.sources")
    if not source_patterns or tuple(sorted(set(source_patterns))) != source_patterns:
        raise SystemExit(f"{SPEC_PATH}: validation.sources must be sorted and unique")
    validation_sources: set[Path] = set()
    for pattern in source_patterns:
        matches = {source.resolve() for source in ROOT.glob(pattern) if source.is_file()}
        if not matches:
            raise SystemExit(f"{SPEC_PATH}: validation source pattern matches nothing: {pattern}")
        validation_sources.update(matches)

    raw_skips = raw_validation["skips"]
    if not isinstance(raw_skips, list):
        raise SystemExit(f"{SPEC_PATH}: validation.skips must be a list")
    validation_skips: list[ValidationSkip] = []
    skip_keys: set[tuple[str, str]] = set()
    for index, raw_skip in enumerate(raw_skips):
        field = f"validation.skips[{index}]"
        if not isinstance(raw_skip, dict) or set(raw_skip) != {"pattern", "actions", "reason"}:
            raise SystemExit(f"{SPEC_PATH}: {field} must contain pattern, actions, and reason")
        pattern = non_empty_string(raw_skip["pattern"], f"{field}.pattern")
        actions = frozenset(string_list(raw_skip["actions"], f"{field}.actions"))
        reason = non_empty_string(raw_skip["reason"], f"{field}.reason")
        if not actions or not actions <= {"check", "fmt", "test"}:
            raise SystemExit(f"{SPEC_PATH}: {field}.actions contains an unknown action")
        matched = [source for source in validation_sources if Path(relative(source)).match(pattern)]
        if not matched:
            raise SystemExit(f"{SPEC_PATH}: stale validation skip matches nothing: {pattern}")
        for action in actions:
            key = (pattern, action)
            if key in skip_keys:
                raise SystemExit(f"{SPEC_PATH}: duplicate validation skip: {pattern} {action}")
            skip_keys.add(key)
        validation_skips.append(ValidationSkip(pattern, actions, reason))

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
    if toolchain.roc_optimization != "dev":
        raise SystemExit(f"{SPEC_PATH}: Roc allocation baselines require the dev backend")
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
                not isinstance(work, dict)
                or set(work) != set(work_counters)
                or any(type(value) is not int or value < 0 for value in work.values())
            ):
                raise SystemExit(
                    f"{SPEC_PATH}: {name}.{target}: work must contain exactly the "
                    "non-negative named counters declared by work_counters"
                )
            expectations[target] = Metrics(
                allocations,
                tuple(work[counter] for counter in work_counters),
            )

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

    discovered_snapshots = set((ROOT / "tests").glob("*/*.pdf"))
    if discovered_snapshots != {case.snapshot for case in cases}:
        raise SystemExit("Test spec must cover every capability snapshot under tests/*")

    for case in cases:
        if case.source.parent != case.snapshot.parent:
            raise SystemExit(f"{SPEC_PATH}: {case.name}: source and snapshot must be adjacent")
    return TestSuite(
        data["protocol_version"],
        toolchain,
        tuple(sorted(validation_sources)),
        tuple(validation_skips),
        tuple(cases),
    )


def verify_all_package_root() -> None:
    package_dir = ROOT / "package"
    expected = {
        source.stem
        for source in package_dir.glob("*.roc")
        if source.name not in {"all.roc", "main.roc"}
    }
    root_source = (package_dir / "all.roc").read_text(encoding="utf-8")
    exposed = set(re.findall(r"^\s*([A-Z][A-Za-z0-9_]*),$", root_source, re.MULTILINE))
    if exposed != expected:
        missing = ", ".join(sorted(expected - exposed)) or "none"
        extra = ", ".join(sorted(exposed - expected)) or "none"
        raise SystemExit(f"package/all.roc export mismatch; missing: {missing}; extra: {extra}")


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


def source_key(source: Path) -> str:
    """Filename-safe identity of a fixture source within one build directory."""
    return relative(source).replace("/", "_").removesuffix(".roc")


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


def metrics_mismatch(
    expected: Metrics,
    actual: Metrics,
    work_counters: tuple[str, ...],
    check_allocations: bool = True,
) -> str | None:
    differences: list[str] = []
    if check_allocations and actual.allocations != expected.allocations:
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
    detail("PASS performance baseline self-test")


def roc_version_matches_pin(pinned_roc: str, actual_roc: str) -> bool:
    expected_roc = f"Roc compiler version {pinned_roc}"
    if actual_roc == expected_roc:
        return True

    pin_match = re.fullmatch(
        r"nightly-[0-9]{4}-(?:[0-9]{2}|[A-Za-z]+)-[0-9]{2}-([0-9a-f]+)",
        pinned_roc,
    )
    build_match = re.fullmatch(r"Roc compiler version release-fast-([0-9a-f]+)", actual_roc)
    if pin_match is None or build_match is None:
        return False

    pinned_commit = pin_match.group(1)
    build_commit = build_match.group(1)
    return len(pinned_commit) >= 7 and build_commit.startswith(pinned_commit)


def self_test_roc_version_pin() -> None:
    for pin in ("nightly-2026-08-16-23452ea", "nightly-2026-August-05-24f0b47"):
        if not roc_version_matches_pin(pin, f"Roc compiler version {pin}"):
            raise SystemExit("Roc version verifier rejected the nightly tag identity")
    if not roc_version_matches_pin(
        "nightly-2026-08-16-23452ea", "Roc compiler version release-fast-23452eaf"
    ):
        raise SystemExit("Roc version verifier rejected the identical release-fast commit")
    if roc_version_matches_pin(
        "nightly-2026-08-16-23452ea", "Roc compiler version release-fast-deadbeef"
    ):
        raise SystemExit("Roc version verifier accepted a different compiler commit")
    if roc_version_matches_pin("nightly-invalid", "Roc compiler version release-fast-24f0b476"):
        raise SystemExit("Roc version verifier accepted a malformed nightly pin")
    detail("PASS Roc compiler pin self-test")


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
    if dimensions.get("external_discretionary_hyphen", 0) == 1:
        return EXTERNAL_DISCRETIONARY_HYPHEN_CONTENT
    if dimensions.get("soft_hyphen", 0) == 1:
        return SOFT_HYPHEN_CONTENT
    if dimensions.get("supplementary_text", 0) == 1:
        return SUPPLEMENTARY_TEXT_CONTENT
    if dimensions.get("cjk_text", 0) == 1:
        return CJK_TEXT_CONTENT
    if dimensions.get("ligature_text", 0) == 1:
        return LIGATURE_CONTENT
    if dimensions.get("actual_text", 0) == 1:
        return ACTUAL_TEXT_CONTENT
    if dimensions.get("visible_text", 0) == 1 or dimensions.get("caller_text", 0) == 1:
        return TEXT_CONTENT
    if dimensions.get("minimal_content", 0) == 1:
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


def build_case_sources(
    cases: tuple[TestCase, ...],
    build_dir: Path,
    target: str,
    roc_optimization: str,
    jobs: int,
) -> None:
    sources = sorted({case.source for case in cases})

    def build_source(source: Path) -> tuple[Path, float]:
        executable = build_dir / f"source-{source_key(source)}"
        started = time.monotonic()
        detail(f"START BUILD {relative(source)}")
        roc(
            "build",
            relative(source),
            f"--opt={roc_optimization}",
            f"--target={target}",
            f"--output={executable}",
        )
        return source, time.monotonic() - started

    executor = concurrent.futures.ThreadPoolExecutor(max_workers=jobs)
    futures = [executor.submit(build_source, source) for source in sources]
    try:
        for future in concurrent.futures.as_completed(futures):
            source, elapsed = future.result()
            progress("PASS", f"BUILD {relative(source)} ({elapsed:.1f}s)")
    except KeyboardInterrupt:
        cancel_parallel(executor, futures)
        raise
    else:
        executor.shutdown()


def run_parallel_roc_tasks(tasks: list[tuple[str, Path]], jobs: int) -> None:
    def run_task(item: tuple[str, Path]) -> tuple[str, Path, float]:
        action, source = item
        started = time.monotonic()
        detail(f"START {action.upper():5s} {relative(source)}")
        if action == "fmt":
            roc("fmt", "--check", relative(source))
        else:
            roc(action, relative(source))
        return action, source, time.monotonic() - started

    executor = concurrent.futures.ThreadPoolExecutor(max_workers=jobs)
    futures = [executor.submit(run_task, item) for item in tasks]
    try:
        for future in concurrent.futures.as_completed(futures):
            action, source, elapsed = future.result()
            progress("PASS", f"{action.upper():5s} {relative(source)} ({elapsed:.1f}s)")
    except KeyboardInterrupt:
        cancel_parallel(executor, futures)
        raise
    else:
        executor.shutdown()


def run_case(
    case: TestCase,
    index: int,
    build_dir: Path,
    target: str,
    protocol_version: int,
    update_snapshots: bool,
    check_allocations: bool,
    compare_baselines: bool,
    linux_x64_container: str | None,
) -> CaseRunResult:
    # Half the registered cases differ from another case only in the runtime
    # arguments they pass to the same fixture, and every case in one run
    # compiles with the same optimization and target. Keying the executable
    # on the source therefore builds each fixture exactly once per run
    # instead of once per case, without weakening what is compiled: the
    # source is still built from the current working tree under the same
    # flags before any case that uses it runs.
    executable = build_dir / f"source-{source_key(case.source)}"
    if not executable.exists():
        raise SystemExit(f"missing prebuilt fixture executable for {relative(case.source)}")

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
    log("+ " + " ".join(str(value) for value in invocation))
    result = managed_run(invocation, cwd=ROOT)
    log(result.stderr.decode("utf-8", errors="replace"))
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
    mismatch = metrics_mismatch(
        expected_metrics,
        actual_metrics,
        case.work_counters,
        check_allocations,
    )
    if mismatch is not None:
        if not compare_baselines and not update_snapshots:
            raise SystemExit(f"{case.name}: performance baseline mismatch: {mismatch}")
        detail(f"DELTA {case.name}: {mismatch}")

    with snapshot_lock(case.snapshot):
        expected = case.snapshot.read_bytes()
        if update_snapshots:
            prior_output = UPDATED_SNAPSHOT_BYTES.get(case.snapshot)
            if prior_output is not None and prior_output != result.stdout:
                raise SystemExit(
                    f"{case.name}: cases sharing {relative(case.snapshot)} produced different bytes"
                )
            UPDATED_SNAPSHOT_BYTES[case.snapshot] = result.stdout
            if expected != result.stdout:
                case.snapshot.write_bytes(result.stdout)
                detail(f"Updated {relative(case.snapshot)}")
        elif expected != result.stdout:
            raise SystemExit(
                f"{case.name}: PDF snapshot mismatch\n"
                f"expected {describe_bytes(expected)}\n"
                f"actual   {describe_bytes(result.stdout)}\n"
                f"{first_difference(expected, result.stdout)}"
            )

    detail(
        f"PASS {case.name}: {describe_bytes(result.stdout)}, "
        f"{actual_metrics.allocations} allocations, "
        + ", ".join(
            f"{name}={value}" for name, value in zip(case.work_counters, actual_metrics.work)
        )
    )

    expected_pages = case.dimensions.get("pages")
    if expected_pages is not None:
        if case.dimensions.get("facade_output", 0) == 1:
            expected_text, _ = fixture_oracle()
            validate_facade_output_pdf(result.stdout, expected_text)
            detail(f"PASS {case.name}: independent offsets, lengths, xref, page, authored facade paragraph, Type 0 font, CID, and Unicode mapping facts")
        elif case.dimensions.get("multiface_text", 0) == 1:
            validate_multiface_text_pdf(result.stdout)
            detail(f"PASS {case.name}: exact selected Latin/CJK Type 0 resources, CID maps, and Unicode mappings")
        elif case.dimensions.get("generated_label", 0) == 1:
            validate_generated_labels_pdf(result.stdout)
            detail(f"PASS {case.name}: independent offsets, lengths, xref, typed list ownership, labels, Type 0 font, CID, and Unicode mapping facts")
        elif case.dimensions.get("combining_text", 0) == 1:
            validate_combining_pdf(result.stdout)
            detail(f"PASS {case.name}: exact decomposed combining CID and two-scalar ToUnicode facts")
        elif case.dimensions.get("case_text", 0) == 1:
            validate_case_pdf(result.stdout)
            detail(f"PASS {case.name}: resolved case presentation, logical ActualText, CID, and Unicode mapping facts")
        elif case.dimensions.get("rtl_text", 0) == 1:
            validate_rtl_pdf(result.stdout)
            detail(f"PASS {case.name}: resolved visual order, mirrored presentation, logical ActualText, CID, and Unicode mapping facts")
        elif case.dimensions.get("multiface_facade", 0) == 1:
            validate_multiface_facade_pdf(result.stdout)
            detail(f"PASS {case.name}: independent offsets, lengths, xref, dense two-font resources, visual-order paint segments, CID, and per-font Unicode mapping facts")
        elif case.dimensions.get("caller_facade", 0) == 1:
            validate_caller_facade_pdf(result.stdout)
            detail(f"PASS {case.name}: independent offsets, lengths, xref, public caller source identity, three placements, Type 0 font, CID, and Unicode mapping facts")
        elif case.source.parent.name == "font_leaves":
            validate_fonts_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: canonical Type 0 bundles, verified embedded subsets, identity CID maps, ToUnicode facts, exact per-stream /Font dictionaries, and placement-site ownership")
        elif case.source.parent.name in {"forms", "form_text"}:
            validate_forms_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: exact Form XObject dictionaries, per-stream direct resources, Do resolution, sharing, and placement-site MCID/ParentTree ownership facts")
        elif case.source.parent.name == "color_images":
            validate_color_images_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: canonical ICC/color-space/image objects, exact leaf payload equality, soft-mask wiring, and deduplicated direct dictionaries")
        elif case.source.parent.name == "transparency":
            validate_transparency_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: canonical ExtGState objects, exact per-stream /ExtGState dictionaries, balanced opacity groups, transparency-group and blending-space wiring, and placement-site ownership facts")
        elif case.source.parent.name == "soft_masks":
            validate_soft_masks_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: canonical Alpha mask states, direct /SMask /G wiring to isolated mask forms outside every resource dictionary, balanced mask groups, and placement-site ownership facts")
        elif case.source.parent.name == "shading_patterns":
            validate_shadings_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: canonical shading/function/pattern objects, exact per-stream /Shading and /Pattern dictionaries, re-derived stop models, ownership-neutral pattern streams, and sh/scn operand resolution")
        elif case.source.parent.name == "navigation":
            validate_navigation_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: paired /SD + /D actions, keyboard-ordered /Annots, OBJR/ParentTree linkage, named destinations, outline preorder, page labels, and appearance geometry verified structurally")
        elif case.source.parent.name == "metadata":
            validate_metadata_pdf(result.stdout, case.dimensions)
            detail(f"PASS {case.name}: catalog /Lang, canonical XMP metadata stream, GTS_PDFA1 output intent, and the single shared sRGB2014 profile stream verified structurally")
        else:
            validate_pdf(
                result.stdout,
                expected_pages,
                expected_content(case.dimensions),
                case.dimensions.get("normalized_plan_identity", 0) == 1,
            )
            detail(f"PASS {case.name}: independent offsets, lengths, xref, and page facts")
            if case.dimensions.get("minimal_content", 0) == 1:
                validate_tagged_visual_pdf(result.stdout)
                detail(f"PASS {case.name}: exact normalized tagged structure and resources")
            if case.dimensions.get("visible_text", 0) == 1:
                validate_text_pdf(result.stdout)
                detail(f"PASS {case.name}: exact font, CID, Unicode mapping, and visible text facts")
            if case.dimensions.get("caller_text", 0) == 1:
                validate_caller_text_pdf(result.stdout)
                detail(f"PASS {case.name}: exact caller font identity, CID, Unicode mapping, and visible text facts")
            if case.dimensions.get("actual_text", 0) == 1:
                validate_actual_text_pdf(result.stdout)
                detail(f"PASS {case.name}: exact visual reordering and logical ActualText facts")
            if case.dimensions.get("supplementary_text", 0) == 1:
                validate_supplementary_text_pdf(result.stdout)
                detail(f"PASS {case.name}: exact supplementary-plane UTF-16BE, CID, Unicode mapping, and sanitized subset facts")
            if case.dimensions.get("cjk_text", 0) == 1:
                validate_cjk_text_pdf(result.stdout)
                detail(f"PASS {case.name}: exact CJK CID widths, Unicode mapping, and sanitized subset facts")
            if case.dimensions.get("ligature_text", 0) == 1:
                validate_ligature_pdf(result.stdout)
                detail(f"PASS {case.name}: parsed GSUB fact, ligature CID, ActualText, Unicode mapping, and sanitized subset facts")
            if case.dimensions.get("soft_hyphen", 0) == 1:
                validate_soft_hyphen_pdf(result.stdout)
                detail(f"PASS {case.name}: explicit U+00AD source, selected presentation, ActualText, CID, and subset facts")
            if case.dimensions.get("external_discretionary_hyphen", 0) == 1:
                validate_external_discretionary_hyphen_pdf(result.stdout)
                detail(f"PASS {case.name}: external zero-width source boundary, selected visible hyphen, ActualText, CID, and subset facts")

    delta = None if mismatch is None else BaselineDelta(case.name, expected_metrics, actual_metrics)
    return CaseRunResult(delta, actual_metrics, len(result.stdout))


def available_cpu_count() -> int:
    if hasattr(os, "sched_getaffinity"):
        return max(1, len(os.sched_getaffinity(0)))
    return max(1, os.cpu_count() or 1)


def available_memory_bytes() -> int | None:
    limits: list[int] = []
    try:
        limits.append(os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES"))
    except (OSError, ValueError):
        pass
    cgroup_limit = Path("/sys/fs/cgroup/memory.max")
    try:
        value = cgroup_limit.read_text(encoding="ascii").strip()
        if value != "max":
            limits.append(int(value))
    except (OSError, ValueError):
        pass
    return min(limits) if limits else None


def default_jobs() -> int:
    cpu_jobs = available_cpu_count()
    memory = available_memory_bytes()
    if memory is None:
        memory_jobs = cpu_jobs
    else:
        reserve = 2 * 1024**3
        per_job = 2 * 1024**3
        memory_jobs = max(1, (max(0, memory - reserve)) // per_job)
    # Beyond sixteen simultaneous compiler/linker processes, filesystem and
    # cache contention tends to dominate even on large build machines.
    return max(1, min(cpu_jobs, memory_jobs, 16))


def main() -> None:
    global PROGRESS_TOTAL, RUN_LOG, VERBOSE
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--update-snapshots",
        action="store_true",
        help=(
            "Replace PDF snapshots with generated output while requiring the exact allocation "
            "and work baselines in the same build"
        ),
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
        "--allocation-baselines",
        action="store_true",
        help="Use the pinned dev backend and require exact Roc allocation baselines",
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
    parser.add_argument(
        "--jobs",
        type=int,
        default=default_jobs(),
        help=(
            "Maximum parallel validation, build, and case workers "
            "(default: hardware-aware, up to 16)"
        ),
    )
    parser.add_argument(
        "--log",
        type=Path,
        help="Detailed run log path (default: .roc-pdf-tmp/logs/test-<timestamp>.log)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Mirror detailed commands and evidence output to the console",
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if args.update_snapshots and args.compare_baselines:
        parser.error("--update-snapshots and --compare-baselines cannot be combined")
    TEMP_ROOT.mkdir(exist_ok=True)
    LOG_ROOT.mkdir(exist_ok=True)
    RUN_LOG = (args.log or LOG_ROOT / f"test-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{os.getpid()}.log").resolve()
    RUN_LOG.parent.mkdir(parents=True, exist_ok=True)
    RUN_LOG.write_text("", encoding="utf-8")
    VERBOSE = args.verbose
    print(f"[{timestamp()}] Detailed log: {RUN_LOG}", flush=True)
    atexit.register(lambda: print(f"[{timestamp()}] Detailed log: {RUN_LOG}", flush=True))
    log(
        f"roc-pdf test run\nstarted_utc={datetime.now(timezone.utc).isoformat()}\n"
        f"pid={os.getpid()}\ncommand={' '.join(sys.argv)}\nROC={ROC}\nZIG={ZIG}\njobs={args.jobs}\n"
    )
    announce("RUN", f"Using {args.jobs} parallel workers")
    # Snapshot acceptance is a complete evidence run, not the first half of a
    # two-invocation workflow. Checking metrics here lets one compiled fixture
    # set both update bytes and prove the registered performance contract.
    check_allocations = (
        args.allocation_baselines or args.compare_baselines or args.update_snapshots
    )
    suite = load_suite()
    if args.case_names:
        requested = set(args.case_names)
        selected = tuple(case for case in suite.cases if case.name in requested)
        missing = requested - {case.name for case in selected}
        if missing:
            raise SystemExit(f"unknown test case(s): {', '.join(sorted(missing))}")
        suite = TestSuite(
            suite.protocol_version,
            suite.toolchain,
            suite.validation_sources,
            suite.validation_skips,
            selected,
        )
    target = "x64musl" if args.linux_x64_container is not None else native_roc_target()

    phase("Preflight contract and checker self-tests")
    if not args.update_snapshots:
        command(sys.executable, "scripts/check_contracts.py", "--self-test")
    command(sys.executable, "scripts/check_arlington.py", "--self-test")
    command(sys.executable, "scripts/check_pdfbox.py", "--self-test")
    command(sys.executable, "scripts/check_tagged_visual.py", "--self-test")
    command(sys.executable, "scripts/check_visual_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_text.py", "--self-test")
    command(sys.executable, "scripts/check_caller_text.py", "--self-test")
    command(sys.executable, "scripts/check_caller_facade.py", "--self-test")
    command(sys.executable, "scripts/check_facade_output.py", "--self-test")
    command(sys.executable, "scripts/check_generated_labels.py", "--self-test")
    command(sys.executable, "scripts/check_actual_text.py", "--self-test")
    command(sys.executable, "scripts/check_supplementary_text.py", "--self-test")
    command(sys.executable, "scripts/check_cjk_text.py", "--self-test")
    command(sys.executable, "scripts/check_ligature.py", "--self-test")
    command(sys.executable, "scripts/check_multiface_facade.py", "--self-test")
    command(sys.executable, "scripts/check_case_text.py", "--self-test")
    command(sys.executable, "scripts/check_combining.py", "--self-test")
    command(sys.executable, "scripts/check_rtl.py", "--self-test")
    command(sys.executable, "scripts/check_multiface_text.py", "--self-test")
    command(sys.executable, "scripts/check_soft_hyphen.py", "--self-test")
    command(sys.executable, "scripts/check_external_discretionary_hyphen.py", "--self-test")
    command(sys.executable, "scripts/check_text_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_forms.py", "--self-test")
    command(sys.executable, "scripts/check_form_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_color_images.py", "--self-test")
    command(sys.executable, "scripts/check_color_image_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_transparency.py", "--self-test")
    command(sys.executable, "scripts/check_transparency_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_soft_masks.py", "--self-test")
    command(sys.executable, "scripts/check_soft_mask_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_shadings.py", "--self-test")
    command(sys.executable, "scripts/check_shading_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_fonts.py", "--self-test")
    command(sys.executable, "scripts/check_font_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_metadata.py", "--self-test")
    command(sys.executable, "scripts/check_metadata_renderers.py", "--self-test")
    command(sys.executable, "scripts/check_navigation.py", "--self-test")
    command(sys.executable, "scripts/check_navigation_renderers.py", "--self-test")
    if not args.update_snapshots:
        command(sys.executable, "scripts/check_pdf_structure.py", "--self-test")
    self_test_metrics(suite)
    self_test_roc_version_pin()
    verify_toolchain(suite.toolchain)
    verify_all_package_root()

    validation_tasks: list[tuple[str, Path]] = []
    skipped_tasks = 0
    for source in suite.validation_sources:
        source_name = Path(relative(source))
        for action in ("fmt", "check", "test"):
            matching_skips = [
                skip
                for skip in suite.validation_skips
                if action in skip.actions and source_name.match(skip.pattern)
            ]
            if len(matching_skips) > 1:
                raise SystemExit(
                    f"{SPEC_PATH}: overlapping {action} skips for {relative(source)}"
                )
            if matching_skips:
                skipped_tasks += 1
                log(
                    f"SKIP {action} {relative(source)}: {matching_skips[0].reason}"
                )
            else:
                validation_tasks.append((action, source))

    PROGRESS_TOTAL = (
        len(validation_tasks)
        + len({case.source for case in suite.cases})
        + len(suite.cases)
    )

    phase(
        f"Running {len(validation_tasks)} spec-defined Roc validation tasks with "
        f"{args.jobs} workers ({skipped_tasks} documented skips)"
    )
    run_parallel_roc_tasks(validation_tasks, args.jobs)
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
    command(
        ZIG,
        "build",
        f"-Doptimize={suite.toolchain.zig_optimization}",
        cwd=TEST_PLATFORM,
    )

    phase(
        f"Building {len({case.source for case in suite.cases})} distinct fixture apps "
        f"with {args.jobs} job{'s' if args.jobs != 1 else ''}"
    )
    baseline_deltas: list[BaselineDelta] = []
    with tempfile.TemporaryDirectory(prefix="test-", dir=TEMP_ROOT) as temporary:
        build_dir = Path(temporary)
        build_case_sources(
            suite.cases,
            build_dir,
            target,
            suite.toolchain.roc_optimization if check_allocations else "dev",
            args.jobs,
        )
        phase(f"Executing {len(suite.cases)} evidence cases with {args.jobs} workers")
        source_use_counts = {
            source: sum(1 for candidate in suite.cases if candidate.source == source)
            for source in {candidate.source for candidate in suite.cases}
        }

        def execute_case(item: tuple[int, TestCase]) -> tuple[int, TestCase, CaseRunResult, float]:
            index, case = item
            started = time.monotonic()
            detail(
                f"START CASE {case.name} "
                f"({relative(case.source)}, {source_use_counts[case.source]} "
                f"case{'s' if source_use_counts[case.source] != 1 else ''}/build)"
            )
            result = run_case(
                case,
                index,
                build_dir,
                target,
                suite.protocol_version,
                args.update_snapshots,
                check_allocations,
                args.compare_baselines,
                args.linux_x64_container,
            )
            return index, case, result, time.monotonic() - started

        executor = concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)
        futures = [
            executor.submit(execute_case, item)
            for item in enumerate(suite.cases)
        ]
        try:
            for future in concurrent.futures.as_completed(futures):
                index, case, result, elapsed = future.result()
                progress(
                    "PASS",
                    f"CASE {case.name} "
                    f"({elapsed:.2f}s, {result.output_bytes} bytes, "
                    f"{result.metrics.allocations} allocations)",
                )
                if result.delta is not None:
                    baseline_deltas.append(result.delta)
        except KeyboardInterrupt:
            cancel_parallel(executor, futures)
            raise
        else:
            executor.shutdown()

    if args.update_snapshots:
        phase("Post-update contract validation")
        command(sys.executable, "scripts/check_contracts.py", "--self-test")
        command(sys.executable, "scripts/check_pdf_structure.py", "--self-test")

    if baseline_deltas:
        announce("FAIL", "Allocation baseline comparison:")
        announce("FAIL", "| Case | Expected | Actual | Delta | Work counters |")
        announce("FAIL", "| --- | ---: | ---: | ---: | --- |")
        for delta in baseline_deltas:
            work_status = "unchanged" if delta.expected.work == delta.actual.work else "CHANGED"
            allocation_delta = delta.actual.allocations - delta.expected.allocations
            announce(
                "FAIL",
                f"| {delta.case_name} | {delta.expected.allocations} | "
                f"{delta.actual.allocations} | {allocation_delta:+d} | {work_status} |",
            )
        raise SystemExit(
            "Performance baselines differ; review and update tests/spec.json deliberately"
        )

    announce("PASS", f"Complete: {len(suite.cases)} cases")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        terminate_active_processes()
        announce("FAIL", "Interrupted", stderr=True)
        raise SystemExit(130) from None
    except SystemExit as error:
        if error.code not in (None, 0):
            message = str(error)
            announce("FAIL", message, stderr=True)
        raise
