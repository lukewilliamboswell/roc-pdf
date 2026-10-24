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

from roc_diagnostics import tolerated_warnings_only
from fixture_groups import ENVELOPE_SCHEMA_VERSION, Member, render_group_app
from harness_validators import (
    PREFLIGHT_CHECKS,
    run_validators,
    validate_preflight_ids,
    validate_registry_ids,
)


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
    rb"ROC_METRICS protocol=([0-9]+) allocations=([0-9]+) allocated_bytes=([0-9]+) "
    rb"work=([0-9]+(?:,[0-9]+)*)?\r?\n"
)
RETENTION_REPORT = re.compile(
    rb"ROC_RETENTION protocol=([0-9]+) backing_refs=([0-9]+) source_offset=([0-9]+) owned_capacity=([0-9]+)\r?\n"
    rb"ROC_METRICS protocol=([0-9]+) allocations=([0-9]+) allocated_bytes=([0-9]+) "
    rb"work=([0-9]+(?:,[0-9]+)*)?\r?\n"
)
# A case may allocate at most this many tenths of its recorded allocated
# bytes. The bytes requested by every roc_alloc and roc_realloc grow
# quadratically when a list is copied on every append, which an exact
# allocation count (one event per copy) does not distinguish from linear
# growth; the ceiling absorbs small drift and fails a blow-up.
ALLOCATED_BYTES_CEILING_TENTHS = 11


@dataclass(frozen=True)
class Metrics:
    allocations: int
    allocated_bytes: int
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
    max_build_workers: int


@dataclass(frozen=True)
class TestCase:
    name: str
    scenario_revision: str
    source: Path
    snapshot: Path
    args: tuple[str, ...]
    measurement_boundary: str
    dimensions: dict[str, int]
    validators: tuple[str, ...]
    work_counters: tuple[str, ...]
    expectations: dict[str, Metrics]
    retention: Retention | None
    family_cases: Path | None
    family_row: int | None
    # The family's name, and its fixture group when the family is a local
    # package run through a group application.
    family: str | None = None
    group: str | None = None


@dataclass(frozen=True)
class Family:
    name: str
    source: Path
    cases_jsonl: Path
    group: str
    tag: str


@dataclass(frozen=True)
class Group:
    name: str
    source: Path
    members: tuple[Family, ...]


@dataclass(frozen=True)
class BuildUnit:
    """One fixture executable: a group application, an isolated family, or a source."""

    key: str
    source: Path
    # The application text of a generated (isolated) unit, written before it builds.
    generated: str | None = None


@dataclass(frozen=True)
class TestSuite:
    protocol_version: int
    preflight_checks: tuple[str, ...]
    post_update_checks: tuple[str, ...]
    toolchain: Toolchain
    validation_sources: tuple[Path, ...]
    validation_skips: tuple["ValidationSkip", ...]
    cases: tuple[TestCase, ...]
    groups: tuple[Group, ...] = ()


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
    drift: BaselineDelta | None
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
    if result.returncode == 2 and executable == ROC and tolerated_warnings_only(result.stdout):
        # The only tolerated warnings are located in a downloaded package
        # (see scripts/roc_diagnostics.py).
        detail(f"PASS command with tolerated downloaded-package warnings: {' '.join(values)}")
        return
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
    if set(data) != {
        "schema_version",
        "protocol_version",
        "preflight_checks",
        "post_update_checks",
        "validation",
        "toolchain",
        "groups",
        "families",
        "cases",
    }:
        raise SystemExit(f"{SPEC_PATH}: unexpected top-level schema")
    if data["schema_version"] != 7 or data["protocol_version"] != 2:
        raise SystemExit(f"{SPEC_PATH}: schema_version must be 7 and protocol_version must be 2")

    preflight_checks = string_list(data["preflight_checks"], "preflight_checks")
    validate_preflight_ids(preflight_checks, f"{SPEC_PATH}: preflight_checks")
    post_update_checks = string_list(data["post_update_checks"], "post_update_checks")
    validate_preflight_ids(post_update_checks, f"{SPEC_PATH}: post_update_checks")

    raw_groups = data["groups"]
    if not isinstance(raw_groups, list):
        raise SystemExit(f"{SPEC_PATH}: groups must be a list")
    group_sources: dict[str, Path] = {}
    for group_index, raw_group in enumerate(raw_groups):
        field = f"groups[{group_index}]"
        if not isinstance(raw_group, dict) or set(raw_group) != {"name"}:
            raise SystemExit(f"{SPEC_PATH}: {field} must contain exactly name")
        group_name = non_empty_string(raw_group["name"], f"{field}.name")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", group_name) or group_name in group_sources:
            raise SystemExit(f"{SPEC_PATH}: {field}.name must be a unique snake_case name")
        group_sources[group_name] = group_source_for(group_name)

    raw_families = data["families"]
    if not isinstance(raw_families, list):
        raise SystemExit(f"{SPEC_PATH}: families must be a list")
    families: list[Family] = []
    family_cases_by_name: dict[str, tuple[Family, int, dict[str, object]]] = {}
    for family_index, raw_family in enumerate(raw_families):
        field = f"families[{family_index}]"
        if not isinstance(raw_family, dict) or set(raw_family) != {"name", "group"}:
            raise SystemExit(f"{SPEC_PATH}: {field} must contain exactly name and group")
        family_name = non_empty_string(raw_family["name"], f"{field}.name")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", family_name) or any(
            family.name == family_name for family in families
        ):
            raise SystemExit(f"{SPEC_PATH}: {field}.name must be a unique snake_case name")
        # A family is the local package in its own directory: the package
        # root, its Cases module and its JSONL rows have fixed names, and its
        # tag in the group envelope is the PascalCase of the family name.
        family_source = (ROOT / "tests" / family_name / "package.roc").resolve()
        cases_jsonl = (ROOT / "tests" / family_name / "cases.jsonl").resolve()
        if not family_source.is_file() or not cases_jsonl.is_file():
            raise SystemExit(
                f"{SPEC_PATH}: {field}: tests/{family_name}/package.roc or cases.jsonl does not exist"
            )
        family_group = raw_family["group"]
        if family_group not in group_sources:
            raise SystemExit(f"{SPEC_PATH}: {field}: unknown group {family_group!r}")
        family_tag = family_tag_for(family_name)
        family = Family(family_name, family_source, cases_jsonl, family_group, family_tag)
        families.append(family)
        for row_index, line in enumerate(
            cases_jsonl.read_text(encoding="utf-8").splitlines(), start=1
        ):
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise SystemExit(f"{cases_jsonl}:{row_index}: invalid JSON: {error}") from error
            if not isinstance(row, dict) or set(row) != {"name", "schema_version", "case"}:
                raise SystemExit(
                    f"{cases_jsonl}:{row_index}: row must contain name, schema_version, and case"
                )
            row_name = non_empty_string(row["name"], f"{cases_jsonl}:{row_index}.name")
            if row["schema_version"] != 1:
                raise SystemExit(f"{cases_jsonl}:{row_index}: unsupported schema_version")
            if row_name in family_cases_by_name:
                raise SystemExit(f"{cases_jsonl}:{row_index}: duplicate family case name {row_name}")
            family_cases_by_name[row_name] = (family, row_index, row)

    committed_groups = {path.resolve() for path in (ROOT / "tests" / "groups").glob("*.roc")}
    if committed_groups != set(group_sources.values()):
        stray = ", ".join(sorted(relative(path) for path in committed_groups - set(group_sources.values())))
        raise SystemExit(f"tests/groups holds applications that no spec group lists: {stray or 'none'}")
    groups: list[Group] = []
    for group_name, group_source in group_sources.items():
        members = tuple(family for family in families if family.group == group_name)
        if not members:
            raise SystemExit(f"{SPEC_PATH}: group {group_name} has no families")
        expected = render_group_app(
            group_name,
            group_source,
            TEST_PLATFORM / "main.roc",
            [Member(family.tag, family.source) for family in members],
        )
        if not group_source.is_file() or group_source.read_text(encoding="utf-8") != expected:
            raise SystemExit(
                f"{relative(group_source)} is stale; regenerate it with "
                "`./scripts/test.py --write-groups`"
            )
        groups.append(Group(group_name, group_source, members))
        group_package_root(groups[-1])

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
        "max_build_workers",
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
        max_build_workers=raw_toolchain["max_build_workers"],
    )
    if toolchain.roc_optimization != "dev":
        raise SystemExit(f"{SPEC_PATH}: Roc allocation baselines require the dev backend")
    if toolchain.zig_optimization not in {"ReleaseFast", "ReleaseSafe", "ReleaseSmall"}:
        raise SystemExit(f"{SPEC_PATH}: Zig host baselines require an optimized build")
    if type(toolchain.max_build_workers) is not int or toolchain.max_build_workers < 1:
        raise SystemExit(f"{SPEC_PATH}: toolchain.max_build_workers must be a positive integer")

    raw_cases = data.get("cases")
    if not isinstance(raw_cases, list) or not raw_cases:
        raise SystemExit(f"{SPEC_PATH}: cases must be a non-empty list")

    cases: list[TestCase] = []
    for raw in raw_cases:
        if not isinstance(raw, dict):
            raise SystemExit(f"{SPEC_PATH}: every case must be an object")

        # A family case names its family, which supplies its program and its
        # typed argument; only a standalone application (the retention probe
        # on its own platform) names a source and literal arguments.
        common_fields = {
            "name",
            "scenario_revision",
            "snapshot",
            "measurement_boundary",
            "dimensions",
            "validators",
            "work_counters",
            "expectations",
            "retention",
        }
        if set(raw) not in (common_fields | {"family"}, common_fields | {"source", "args"}):
            raise SystemExit(
                f"{SPEC_PATH}: every case must contain exactly {sorted(common_fields)} "
                "plus either family or source and args"
            )
        name = non_empty_string(raw["name"], "case.name")
        scenario_revision = non_empty_string(raw["scenario_revision"], f"{name}.scenario_revision")
        args = string_list(raw["args"], f"{name}.args") if "args" in raw else ()
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

        validators = string_list(raw["validators"], f"{name}.validators")
        validate_registry_ids(validators, f"{SPEC_PATH}: {name}.validators")
        if ("pages" in dimensions) != bool(validators):
            raise SystemExit(
                f"{SPEC_PATH}: {name}: cases with pages require validators and "
                "cases without pages must not declare them"
            )

        work_counters = string_list(raw["work_counters"], f"{name}.work_counters")
        if not work_counters or len(work_counters) != len(set(work_counters)):
            raise SystemExit(f"{SPEC_PATH}: {name}: work_counters must be non-empty and unique")

        raw_expectations = raw["expectations"]
        if not isinstance(raw_expectations, dict) or set(raw_expectations) != {"arm64mac", "x64musl"}:
            raise SystemExit(f"{SPEC_PATH}: {name}: expectations must cover every supported target")
        expectations: dict[str, Metrics] = {}
        for target, raw_metrics in raw_expectations.items():
            if not isinstance(raw_metrics, dict) or set(raw_metrics) != {"allocations", "allocated_bytes", "work"}:
                raise SystemExit(f"{SPEC_PATH}: {name}.{target}: invalid metrics schema")
            allocations = raw_metrics["allocations"]
            allocated_bytes = raw_metrics["allocated_bytes"]
            work = raw_metrics["work"]
            if type(allocations) is not int or allocations < 0:
                raise SystemExit(f"{SPEC_PATH}: {name}.{target}: allocations must be non-negative")
            if type(allocated_bytes) is not int or allocated_bytes < 0:
                raise SystemExit(f"{SPEC_PATH}: {name}.{target}: allocated_bytes must be non-negative")
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
                allocated_bytes,
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

        family_entry = family_cases_by_name.pop(name, None)
        case_family: Family | None = None
        if "family" not in raw:
            if family_entry is not None:
                raise SystemExit(f"{SPEC_PATH}: {name}: a case with a family JSONL row must name its family")
            source = repository_path(raw.get("source"), f"{name}.source")
            family_cases = None
            family_row = None
        else:
            if family_entry is None:
                raise SystemExit(f"{SPEC_PATH}: {name}: family {raw['family']!r} has no JSONL row for it")
            case_family, family_row, family_case = family_entry
            if raw["family"] != case_family.name:
                raise SystemExit(
                    f"{case_family.cases_jsonl}:{family_row}: {name}: spec family must be {case_family.name}"
                )
            source = case_family.source
            family_cases = case_family.cases_jsonl
            args = (family_case_argument(case_family, family_case),)
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
                validators,
                work_counters,
                expectations,
                retention,
                family_cases,
                family_row,
                None if case_family is None else case_family.name,
                None if case_family is None else case_family.group,
            )
        )

    if family_cases_by_name:
        unused = ", ".join(sorted(family_cases_by_name))
        raise SystemExit(f"Family JSONL rows have no matching spec cases: {unused}")

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
        preflight_checks,
        post_update_checks,
        toolchain,
        tuple(sorted(validation_sources)),
        tuple(validation_skips),
        tuple(cases),
        tuple(groups),
    )


def family_tag_for(name: str) -> str:
    """A family's tag in the group envelope and its module alias in the group app."""
    return "".join(part.capitalize() for part in name.split("_"))


def family_case_argument(family: Family, row: dict[str, object]) -> str:
    """The argv JSON a family case receives: its row's case tagged with the family."""
    envelope = {"case": {family.tag: row["case"]}, "schema_version": ENVELOPE_SCHEMA_VERSION}
    return json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)


def group_source_for(name: str) -> Path:
    return (ROOT / "tests" / "groups" / f"{name}.roc").resolve()


def write_group_apps() -> list[Path]:
    """Regenerate every tests/groups/<group>.roc from tests/spec.json."""
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    written: list[Path] = []
    for raw_group in data["groups"]:
        source = group_source_for(raw_group["name"])
        members = [
            Member(family_tag_for(raw_family["name"]), (ROOT / "tests" / raw_family["name"] / "package.roc").resolve())
            for raw_family in data["families"]
            if raw_family["group"] == raw_group["name"]
        ]
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(
            render_group_app(raw_group["name"], source, TEST_PLATFORM / "main.roc", members),
            encoding="utf-8",
        )
        written.append(source)
    return written


GROUP_MODES = ("group", "isolate", "perturb", "inject")


def group_package_root(group: Group) -> str:
    """Which production package root a group's families build against."""
    roots = set()
    for family in group.members:
        header = family.source.read_text(encoding="utf-8")
        roots.update(re.findall(r'"[./]*package/(main|all)\.roc"', header))
    if len(roots) != 1:
        raise SystemExit(f"group {group.name} must use exactly one of package/main.roc and package/all.roc")
    return roots.pop()


def case_build_units(suite: TestSuite, build_dir: Path, mode: str) -> dict[str, BuildUnit]:
    """The fixture executable each case runs, keyed by case name.

    A grouped case runs its committed group application (`group`), or a
    generated one:

    - `isolate`: only its family, the equivalence oracle for the group;
    - `perturb`: its group's families plus the next group's (cyclically), so a
      count that depends on which families share an executable shows up;
    - `inject`: its group with one known allocation added inside the
      measured window, which every grouped case must then report.

    Every other case runs its own source.
    """
    if mode not in GROUP_MODES:
        raise ValueError(mode)
    units: dict[str, BuildUnit] = {}
    groups = {group.name: group for group in suite.groups}
    ordered = list(suite.groups)
    for case in suite.cases:
        if case.group is None:
            unit = BuildUnit(f"source-{source_key(case.source)}", case.source)
        elif mode == "group":
            unit = BuildUnit(f"group-{case.group}", groups[case.group].source)
        elif mode in ("perturb", "inject"):
            group = groups[case.group]
            members = list(group.members)
            if mode == "perturb":
                # Only a group on the same production package root can join:
                # one program cannot hold both package/main.roc and
                # package/all.roc (the compiler crashes building it).
                position = ordered.index(group)
                for offset in range(1, len(ordered)):
                    neighbour = ordered[(position + offset) % len(ordered)]
                    if group_package_root(neighbour) == group_package_root(group):
                        members.extend(neighbour.members)
                        break
            app = build_dir / f"{mode}_{group.name}.roc"
            unit = BuildUnit(
                f"{mode}-{group.name}",
                app,
                render_group_app(
                    f"{mode}_{group.name}",
                    app,
                    TEST_PLATFORM / "main.roc",
                    [Member(family.tag, family.source) for family in members],
                    inject_allocation=mode == "inject",
                ),
            )
        else:
            family = next(
                member for member in groups[case.group].members if member.name == case.family
            )
            app = build_dir / f"isolate_{family.name}.roc"
            unit = BuildUnit(
                f"isolate-{family.name}",
                app,
                render_group_app(
                    f"isolate_{family.name}",
                    app,
                    TEST_PLATFORM / "main.roc",
                    [Member(family.tag, family.source)],
                ),
            )
        units[case.name] = unit
    return units


def fixture_build_command(
    source: Path, roc_optimization: str, target: str, executable: Path
) -> list[str]:
    """Every flag an evidence executable is built with, in one place."""
    # Evidence executables never reuse compiled procedures from the
    # cache. The pinned compiler reuses a package procedure compiled for
    # an earlier fixture program in a later one, and the later program
    # can then copy lists that it updates in place when built alone: the
    # allocation counts and allocated bytes of a case depended on which
    # fixtures were built before it. Built without the cache, every
    # fixture compiles exactly as a standalone `roc build --no-cache`
    # does, whatever the order or cache state
    # (development/performance/lowering-uniqueness.md).
    # --no-cache works around roc-lang/roc#11826. That issue is closed,
    # but re-tested on nightly-2026-10-18 a cold shared cache still
    # differs in 26 cases: "static PDF/A-4 archived report scaling x400"
    # allocates 13,877 times instead of 13,473 when other fixtures were
    # built into the cache first. On nightly-2026-10-23 cached fixture
    # builds fail outright (the cached compile-time literal regression,
    # roc-lang/roc#12564), so nothing could be compared.
    # Keep it until a cold and a warm cache both match --no-cache for
    # every case.
    return [
        ROC,
        "build",
        source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else str(source),
        f"--opt={roc_optimization}",
        f"--target={target}",
        "--no-cache",
        f"--output={executable}",
    ]


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
    if check_allocations and allocated_bytes_exceeded(expected, actual):
        differences.append(
            f"allocated_bytes {actual.allocated_bytes} exceeds the recorded "
            f"{expected.allocated_bytes} by more than "
            f"{(ALLOCATED_BYTES_CEILING_TENTHS - 10) * 10}%"
        )
    for name, expected_value, actual_value in zip(work_counters, expected.work, actual.work):
        if actual_value != expected_value:
            differences.append(f"{name} expected {expected_value}, got {actual_value}")
    if len(actual.work) != len(expected.work):
        differences.append(f"work counter count expected {len(expected.work)}, got {len(actual.work)}")
    return "; ".join(differences) if differences else None


def allocated_bytes_exceeded(expected: Metrics, actual: Metrics) -> bool:
    return actual.allocated_bytes * 10 > expected.allocated_bytes * ALLOCATED_BYTES_CEILING_TENTHS


def metrics_drift(expected: Metrics, actual: Metrics) -> bool:
    """Any exact difference, including allocated bytes inside the ceiling."""
    return expected != actual


def self_test_metrics(suite: TestSuite) -> None:
    case = suite.cases[0]
    expected = case.expectations["arm64mac"]
    allocation_regression = Metrics(expected.allocations + 1, expected.allocated_bytes, expected.work)
    if metrics_mismatch(expected, allocation_regression, case.work_counters) is None:
        raise SystemExit("Performance baseline self-test accepted an allocation regression")
    changed_work = list(expected.work)
    changed_work[0] += 1
    work_regression = Metrics(expected.allocations, expected.allocated_bytes, tuple(changed_work))
    if metrics_mismatch(expected, work_regression, case.work_counters) is None:
        raise SystemExit("Performance baseline self-test accepted a work regression")
    ceiling = expected.allocated_bytes * ALLOCATED_BYTES_CEILING_TENTHS // 10
    byte_blowup = Metrics(expected.allocations, ceiling + 1, expected.work)
    if metrics_mismatch(expected, byte_blowup, case.work_counters) is None:
        raise SystemExit("Performance baseline self-test accepted allocated bytes above the ceiling")
    for accepted_bytes in (ceiling, expected.allocated_bytes // 2):
        accepted = Metrics(expected.allocations, accepted_bytes, expected.work)
        if metrics_mismatch(expected, accepted, case.work_counters) is not None:
            raise SystemExit(
                "Performance baseline self-test rejected allocated bytes within the ceiling"
            )
    if metrics_mismatch(expected, byte_blowup, case.work_counters, check_allocations=False) is not None:
        raise SystemExit(
            "Performance baseline self-test checked allocated bytes without allocation baselines"
        )
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
    for pin in ("nightly-2026-08-18-e9be50a", "nightly-2026-August-05-24f0b47"):
        if not roc_version_matches_pin(pin, f"Roc compiler version {pin}"):
            raise SystemExit("Roc version verifier rejected the nightly tag identity")
    if not roc_version_matches_pin(
        "nightly-2026-08-18-e9be50a", "Roc compiler version release-fast-e9be50af"
    ):
        raise SystemExit("Roc version verifier rejected the identical release-fast commit")
    if roc_version_matches_pin(
        "nightly-2026-08-18-e9be50a", "Roc compiler version release-fast-deadbeef"
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


LOCAL_IMPORT = re.compile(r"^\s*import\s+([A-Z][A-Za-z0-9_]*)\b", re.MULTILINE)
TOP_LEVEL_EXPECT = re.compile(r"^\s*expect\b", re.MULTILINE)


@dataclass(frozen=True)
class ValidationTask:
    action: str
    sources: tuple[Path, ...]
    # The expect-bearing files this `roc test` root is responsible for, or
    # the reason a root needs no task of its own.
    covers: tuple[Path, ...] = ()

    @property
    def label(self) -> str:
        if self.action == "fmt":
            return f"{len(self.sources)} files"
        return relative(self.sources[0])


@dataclass(frozen=True)
class ValidationPlan:
    tasks: tuple[ValidationTask, ...]
    # Roots whose type checking is provided by another task, with the reason.
    delegated: tuple[tuple[Path, str], ...]


def local_import_closure(root: Path) -> tuple[Path, ...]:
    """The root plus the same-directory modules it reaches through plain imports."""
    seen: list[Path] = [root]
    pending = [root]
    while pending:
        source = pending.pop()
        for name in LOCAL_IMPORT.findall(source.read_text(encoding="utf-8")):
            module = source.parent / f"{name}.roc"
            if module.is_file() and module not in seen:
                seen.append(module)
                pending.append(module)
    return tuple(seen)


LOCAL_PACKAGE_DEPENDENCY = re.compile(r'^\s*[a-z][a-z0-9_]*:\s*"([^"]*/package\.roc)",?\s*$', re.MULTILINE)
PACKAGE_EXPOSES = re.compile(r"^package\s*\[([^\]]*)\]", re.MULTILINE)


def validation_closure(root: Path) -> tuple[Path, ...]:
    """The root's local import closure plus the local family packages it depends on.

    A group application reaches its families through package edges
    (`tables: "../tables/package.roc"`); its `roc test` runs the expects in
    those packages' modules, so they belong to its closure. Only packages
    under tests/ are followed: the production package has its own roots.
    """
    seen = list(local_import_closure(root))
    for dependency in LOCAL_PACKAGE_DEPENDENCY.findall(root.read_text(encoding="utf-8")):
        package = (root.parent / dependency).resolve()
        if not package.is_file() or not package.is_relative_to(ROOT / "tests"):
            continue
        if package not in seen:
            seen.append(package)
        exposes = PACKAGE_EXPOSES.search(package.read_text(encoding="utf-8"))
        names = [] if exposes is None else [name.strip() for name in exposes.group(1).split(",")]
        for name in names:
            module = package.parent / f"{name}.roc"
            if module.is_file():
                for reached in local_import_closure(module):
                    if reached not in seen:
                        seen.append(reached)
    return tuple(seen)


def has_expect(source: Path) -> bool:
    return TOP_LEVEL_EXPECT.search(source.read_text(encoding="utf-8")) is not None


def plan_validation(
    fmt_sources: list[Path],
    roots: list[Path],
    fixture_sources: set[Path],
    jobs: int,
) -> ValidationPlan:
    """Choose the fewest compiler invocations that keep every check and expect.

    Every `roc check`, `roc test`, and `roc build` re-checks the whole package
    (seconds and gigabytes per root), so each root gets at most one of them:

    - `roc test` reports exactly the errors and warnings `roc check` does, with
      the same exit codes, before running expects; a tested root is not also
      checked.
    - `roc build --no-cache` of a fixture source does the same, so a fixture
      root that no `roc test` needs is checked by its evidence build. A group
      application's closure includes its family packages (validation_closure),
      whose own package.roc roots are skipped: the group is their root.
    - `package/all.roc` runs every package-module expect (it exposes every
      module, see verify_all_package_root). An application root's `roc test`
      would re-run them all, so application roots are tested only for the
      expects in their own file and same-directory modules: every root whose
      own file has expects, then, per directory, the fewest roots whose local
      import closures cover the remaining expect-bearing modules.
    - Every other root gets one `roc check`.

    fmt is cheap and takes many files, so it runs as one batch per worker.
    """
    package_all = (ROOT / "package" / "all.roc").resolve()
    tasks: list[ValidationTask] = []
    delegated: list[tuple[Path, str]] = []

    ordered_fmt = sorted(fmt_sources)
    batches = max(1, min(jobs, len(ordered_fmt)))
    for index in range(batches):
        batch = tuple(ordered_fmt[index::batches])
        if batch:
            tasks.append(ValidationTask("fmt", batch))

    closures = {root: validation_closure(root) for root in roots}
    tested: dict[Path, tuple[Path, ...]] = {}
    if package_all in closures:
        tested[package_all] = tuple(
            module for module in sorted((ROOT / "package").glob("*.roc")) if has_expect(module)
        )
    uncovered: set[Path] = set()
    for root, closure in closures.items():
        if root == package_all or root.parent == ROOT / "package":
            continue
        uncovered.update(module for module in closure if has_expect(module))
    for root in sorted(closures):
        if root in uncovered:
            tested[root] = tuple(module for module in closures[root] if module in uncovered)
            uncovered.difference_update(tested[root])
    while uncovered:
        root = min(
            (candidate for candidate in closures if candidate not in tested),
            key=lambda candidate: (
                -len(uncovered.intersection(closures[candidate])),
                relative(candidate),
            ),
        )
        covered = tuple(module for module in closures[root] if module in uncovered)
        if not covered:
            raise SystemExit(f"no validation root reaches {sorted(relative(item) for item in uncovered)}")
        tested[root] = covered
        uncovered.difference_update(covered)

    for root in sorted(closures):
        if root in tested:
            tasks.append(ValidationTask("test", (root,), tested[root]))
        elif root in fixture_sources:
            delegated.append((root, "checked by its fixture build"))
        else:
            tasks.append(ValidationTask("check", (root,)))
    return ValidationPlan(tuple(tasks), tuple(delegated))


def unit_label(unit: BuildUnit) -> str:
    return relative(unit.source)


def build_case_units(
    units: list[BuildUnit],
    build_dir: Path,
    target: str,
    roc_optimization: str,
    jobs: int,
) -> None:
    def build_unit(unit: BuildUnit) -> tuple[BuildUnit, float]:
        executable = build_dir / unit.key
        started = time.monotonic()
        if unit.generated is not None:
            unit.source.write_text(unit.generated, encoding="utf-8")
        detail(f"START BUILD {unit_label(unit)}")
        build = fixture_build_command(unit.source, roc_optimization, target, executable)
        command(build[0], *build[1:])
        return unit, time.monotonic() - started

    executor = concurrent.futures.ThreadPoolExecutor(max_workers=jobs)
    futures = [executor.submit(build_unit, unit) for unit in units]
    try:
        for future in concurrent.futures.as_completed(futures):
            unit, elapsed = future.result()
            progress("PASS", f"BUILD {unit_label(unit)} ({elapsed:.1f}s)")
    except KeyboardInterrupt:
        cancel_parallel(executor, futures)
        raise
    else:
        executor.shutdown()


def run_parallel_roc_tasks(tasks: list[ValidationTask], jobs: int) -> None:
    # A group application compiles several families at once and peaks higher
    # than a single root, so the tasks share a memory budget as well as the
    # worker count.
    budget = MemoryBudget(available_now_bytes())
    groups_dir = ROOT / "tests" / "groups"

    def run_task(task: ValidationTask) -> tuple[ValidationTask, float]:
        if task.action == "fmt":
            return run_one(task)
        weight = GROUP_CHECK_PEAK_BYTES if task.sources[0].parent == groups_dir else ROOT_CHECK_PEAK_BYTES
        with budget.reserve(weight):
            return run_one(task)

    def run_one(task: ValidationTask) -> tuple[ValidationTask, float]:
        started = time.monotonic()
        detail(f"START {task.action.upper():5s} {task.label}")
        try:
            if task.action == "fmt":
                roc("fmt", "--check", *(relative(source) for source in task.sources))
            else:
                # TODO(roc-lang/roc#12564): remove --no-cache. On
                # nightly-2026-10-23-18478ff a shared cache that already holds
                # the package from an earlier root makes every later root's
                # number literals of package types fail compile-time
                # `from_numeral` evaluation with a stack overflow.
                roc(task.action, relative(task.sources[0]), "--no-cache")
        except SystemExit as error:
            if task.action != "test":
                raise
            # A failing expect names its own file and line; also name the
            # family root and every module this root was responsible for.
            covered = ", ".join(relative(module) for module in task.covers)
            raise SystemExit(f"{error}\nTEST root {task.label} covers expects in: {covered}") from None
        return task, time.monotonic() - started

    executor = concurrent.futures.ThreadPoolExecutor(max_workers=jobs)
    futures = [executor.submit(run_task, item) for item in tasks]
    try:
        for future in concurrent.futures.as_completed(futures):
            task, elapsed = future.result()
            progress("PASS", f"{task.action.upper():5s} {task.label} ({elapsed:.1f}s)")
    except KeyboardInterrupt:
        cancel_parallel(executor, futures)
        raise
    else:
        executor.shutdown()


def run_case(
    case: TestCase,
    index: int,
    executable: Path,
    target: str,
    protocol_version: int,
    update_snapshots: bool,
    check_allocations: bool,
    compare_baselines: bool,
    linux_x64_container: str | None,
    injected_allocations: int = 0,
) -> CaseRunResult:
    # Most registered cases differ from another case only in the runtime
    # argument they pass to the same fixture executable, and every case in
    # one run compiles with the same optimization and target. Keying the
    # executable on its build unit (a group application, or a source) builds
    # each fixture exactly once per run instead of once per case, without
    # weakening what is compiled: the unit is still built from the current
    # working tree under the same flags before any case that uses it runs.
    # Each case still runs in its own process.
    if not executable.exists():
        raise SystemExit(f"missing prebuilt fixture executable for {case.name}: {executable.name}")

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
        location = (
            f"{relative(case.family_cases)}:{case.family_row}: "
            if case.family_cases is not None
            else ""
        )
        raise SystemExit(
            f"{location}{case.name}: executable exited with {result.returncode}\n"
            f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )

    if case.retention is None:
        match = METRICS_REPORT.fullmatch(result.stderr)
        protocol_group = 1
        allocations_group = 2
        allocated_bytes_group = 3
        work_group = 4
    else:
        match = RETENTION_REPORT.fullmatch(result.stderr)
        protocol_group = 5
        allocations_group = 6
        allocated_bytes_group = 7
        work_group = 8
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
    actual_metrics = Metrics(
        int(match.group(allocations_group)),
        int(match.group(allocated_bytes_group)),
        actual_work,
    )
    expected_metrics = case.expectations[target]
    if injected_allocations:
        # The injection self-test adds known allocations inside the window;
        # the recorded count plus exactly those is the only passing result.
        # Each injected allocation requests 136 bytes, which alone exceeds
        # the 10% ceiling of a case that otherwise allocates nothing, so the
        # ceiling gets a fixed allowance for them.
        expected_metrics = Metrics(
            expected_metrics.allocations + injected_allocations,
            expected_metrics.allocated_bytes + 1024 * injected_allocations,
            expected_metrics.work,
        )
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
        f"{actual_metrics.allocated_bytes} allocated bytes, "
        + ", ".join(
            f"{name}={value}" for name, value in zip(case.work_counters, actual_metrics.work)
        )
    )

    run_validators(
        case.validators,
        result.stdout,
        case.dimensions,
        lambda message: detail(f"PASS {case.name}: {message}"),
    )

    delta = None if mismatch is None else BaselineDelta(case.name, expected_metrics, actual_metrics)
    drift = (
        BaselineDelta(case.name, expected_metrics, actual_metrics)
        if metrics_drift(expected_metrics, actual_metrics)
        else None
    )
    return CaseRunResult(delta, drift, actual_metrics, len(result.stdout))


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


GROUP_BUILD_PEAK_BYTES = 7 * 1024**3
# `roc check`/`roc test` of one root peaks near 4 GB, and of a group
# application (several families) up to 5.5 GB.
ROOT_CHECK_PEAK_BYTES = 4 * 1024**3
GROUP_CHECK_PEAK_BYTES = 6 * 1024**3


def available_now_bytes() -> int | None:
    """Memory the machine can give now: other processes' resident memory is not available."""
    memory = available_memory_bytes()
    try:
        for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
            if line.startswith("MemAvailable:"):
                current = int(line.split()[1]) * 1024
                memory = current if memory is None else min(memory, current)
    except (OSError, ValueError):
        pass
    return memory


class MemoryBudget:
    """Admit compiler processes while their expected peaks fit the budget.

    One process is always admitted, however large, so a small machine still
    makes progress one compile at a time.
    """

    def __init__(self, total: int | None) -> None:
        self.free = None if total is None else max(0, total - 1024**3)
        self.running = 0
        self.condition = threading.Condition()

    class _Reservation:
        def __init__(self, budget: "MemoryBudget", weight: int) -> None:
            self.budget = budget
            self.weight = weight

        def __enter__(self) -> None:
            budget = self.budget
            with budget.condition:
                while budget.free is not None and budget.running > 0 and budget.free < self.weight:
                    budget.condition.wait()
                if budget.free is not None:
                    budget.free -= self.weight
                budget.running += 1

        def __exit__(self, *_: object) -> None:
            budget = self.budget
            with budget.condition:
                if budget.free is not None:
                    budget.free += self.weight
                budget.running -= 1
                budget.condition.notify_all()

    def reserve(self, weight: int) -> "MemoryBudget._Reservation":
        return MemoryBudget._Reservation(self, weight)


def default_build_jobs() -> int:
    """Parallel fixture builds that fit in memory.

    A fixture group build peaks at up to 6.9 GB resident on
    nightly-2026-10-23 (development/performance/fixture-grouping.md), more
    than a single-source build, so builds get their own memory bound.
    """
    memory = available_now_bytes()
    if memory is None:
        return available_cpu_count()
    return max(1, (max(0, memory - 1024**3)) // GROUP_BUILD_PEAK_BYTES)


def default_jobs() -> int:
    cpu_jobs = available_cpu_count()
    memory = available_memory_bytes()
    if memory is None:
        memory_jobs = cpu_jobs
    else:
        # Each check, test, or build root type-checks the whole package and
        # peaks at 4 to 5.2 GB resident with the pinned compiler; on a 32 GB
        # machine 8 and 10 workers were killed for memory, 6 were not
        # (development/performance/test-suite-speed.md).
        reserve = 2 * 1024**3
        per_job = 5 * 1024**3
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
        "--baseline-report",
        type=Path,
        help=(
            "With --compare-baselines or --update-snapshots, also write every differing case's "
            "expected and observed metrics to this JSON file for review; it never edits the spec"
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
        "--group",
        action="append",
        dest="group_names",
        metavar="NAME",
        help="Run only the cases of the named fixture group; repeatable, and combines with --case",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help=(
            "With --case, build only the selected cases' fixtures and run them, skipping the "
            "preflight self-tests and the fmt/check/test validation phase"
        ),
    )
    parser.add_argument(
        "--isolate",
        action="store_true",
        help=(
            "Build each grouped family as its own generated application instead of its group "
            "application: the equivalence oracle for fixture grouping"
        ),
    )
    parser.add_argument(
        "--group-mode",
        choices=GROUP_MODES,
        default="group",
        help=(
            "How grouped families are built: their committed group application (default), "
            "isolated (as --isolate), perturbed (each group plus the next group's families), "
            "or inject (one known extra allocation in every grouped case, which must be reported)"
        ),
    )
    parser.add_argument(
        "--list-groups",
        action="store_true",
        help="Print the fixture groups, their families and case counts, and exit",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="With --list-groups, print JSON",
    )
    parser.add_argument(
        "--write-groups",
        action="store_true",
        help="Regenerate tests/groups/<group>.roc from tests/spec.json and exit",
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
    if args.baseline_report is not None and not (args.update_snapshots or args.compare_baselines):
        parser.error("--baseline-report requires --compare-baselines or --update-snapshots")
    if args.quick and not (args.case_names or args.group_names):
        parser.error("--quick requires at least one --case or --group")
    if args.quick and args.update_snapshots:
        parser.error("--quick cannot update snapshots: it skips the post-update contract checks")
    if args.json and not args.list_groups:
        parser.error("--json requires --list-groups")
    if args.isolate:
        if args.group_mode not in ("group", "isolate"):
            parser.error("--isolate conflicts with --group-mode")
        args.group_mode = "isolate"
    if args.group_mode != "group" and args.update_snapshots:
        parser.error("snapshots are updated only from the committed group applications")
    if args.write_groups:
        for written in write_group_apps():
            print(relative(written))
        return
    if args.list_groups:
        listed = load_suite()
        listing = [
            {
                "name": group.name,
                "source": relative(group.source),
                "families": [
                    {
                        "name": family.name,
                        "tag": family.tag,
                        "cases": sum(1 for case in listed.cases if case.family == family.name),
                    }
                    for family in group.members
                ],
            }
            for group in listed.groups
        ]
        ungrouped = sorted({relative(case.source) for case in listed.cases if case.group is None})
        if args.json:
            print(json.dumps({"groups": listing, "ungrouped_sources": ungrouped}, indent=2))
        else:
            for group in listing:
                cases = sum(family["cases"] for family in group["families"])
                print(f"{group['name']}: {group['source']} ({len(group['families'])} families, {cases} cases)")
                for family in group["families"]:
                    print(f"  {family['tag']}: {family['name']} ({family['cases']} cases)")
            print(f"ungrouped: {len(ungrouped)} sources")
        return
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
    if args.case_names or args.group_names:
        requested = set(args.case_names or ())
        requested_groups = set(args.group_names or ())
        unknown_groups = requested_groups - {group.name for group in suite.groups}
        if unknown_groups:
            raise SystemExit(f"unknown fixture group(s): {', '.join(sorted(unknown_groups))}")
        selected = tuple(
            case for case in suite.cases if case.name in requested or case.group in requested_groups
        )
        missing = requested - {case.name for case in selected}
        if missing:
            raise SystemExit(f"unknown test case(s): {', '.join(sorted(missing))}")
        suite = TestSuite(
            suite.protocol_version,
            suite.preflight_checks,
            suite.post_update_checks,
            suite.toolchain,
            suite.validation_sources,
            suite.validation_skips,
            selected,
            suite.groups,
        )
    target = "x64musl" if args.linux_x64_container is not None else native_roc_target()

    if args.quick:
        phase("Quick run: skipping preflight self-tests and Roc validation")
        verify_toolchain(suite.toolchain)
        plan = ValidationPlan((), ())
        fmt_sources: list[Path] = []
        skipped_tasks = 0
    else:
        phase("Preflight contract and checker self-tests")
        for check_id in suite.preflight_checks:
            check = PREFLIGHT_CHECKS[check_id]
            if not (args.update_snapshots and check.skip_on_snapshot_update):
                command(sys.executable, f"scripts/{check.script}", "--self-test")
        self_test_metrics(suite)
        self_test_roc_version_pin()
        verify_toolchain(suite.toolchain)
        verify_all_package_root()
        plan, fmt_sources, skipped_tasks = validation_phase_plan(suite, args.jobs)
    run_suite(suite, args, plan, fmt_sources, skipped_tasks, target, check_allocations)


def validation_phase_plan(suite: TestSuite, jobs: int) -> tuple[ValidationPlan, list[Path], int]:
    fmt_sources: list[Path] = []
    roots: list[Path] = []
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
            elif action == "fmt":
                fmt_sources.append(source)
            elif action == "check":
                roots.append(source)
    # Selecting cases never drops validation: every root is still checked by
    # a test, a check, or one of the fixture builds, so delegate a root to a
    # fixture build only when that build runs in this invocation. A group
    # application is delegated only when it is built, which --isolate does not.
    plan = plan_validation(
        fmt_sources,
        roots,
        {case.source for case in suite.cases if case.group is None}
        | {group.source for group in suite.groups if any(case.group == group.name for case in suite.cases)},
        jobs,
    )
    for task in plan.tasks:
        if task.action == "test":
            log(
                f"PLAN test {task.label} (checks it and runs expects in "
                f"{', '.join(relative(module) for module in task.covers)})"
            )
        elif task.action == "check":
            log(f"PLAN check {task.label}")
    for root, reason in plan.delegated:
        log(f"PLAN {relative(root)}: {reason}")
    return plan, fmt_sources, skipped_tasks


def run_suite(
    suite: TestSuite,
    args: argparse.Namespace,
    plan: ValidationPlan,
    fmt_sources: list[Path],
    skipped_tasks: int,
    target: str,
    check_allocations: bool,
) -> None:
    global PROGRESS_TOTAL
    with tempfile.TemporaryDirectory(prefix="test-", dir=TEMP_ROOT) as temporary:
        build_dir = Path(temporary)
        units_by_case = case_build_units(suite, build_dir, args.group_mode)
        units = sorted({unit.key: unit for unit in units_by_case.values()}.values(), key=lambda unit: unit.key)
        if args.group_mode != "group" and not any(case.group is not None for case in suite.cases):
            raise SystemExit(f"--group-mode {args.group_mode} needs at least one grouped case")
        # A generated application is a separate program from the group
        # application: keep the group root checked when its build is skipped.
        validation_tasks = list(plan.tasks)
        if args.group_mode != "group":
            delegated_groups = [root for root, _ in plan.delegated if root.parent == ROOT / "tests" / "groups"]
            validation_tasks.extend(ValidationTask("check", (root,)) for root in delegated_groups)

        PROGRESS_TOTAL = len(validation_tasks) + len(units) + len(suite.cases)

        # The package roots run first and alone so that every later root reads
        # the package's checked modules from a warm cache.
        seed_paths = {
            (ROOT / "package" / "main.roc").resolve(),
            (ROOT / "package" / "all.roc").resolve(),
        }
        seed_tasks = [task for task in validation_tasks if task.action != "fmt" and task.sources[0] in seed_paths]
        other_tasks = [task for task in validation_tasks if task not in seed_tasks]
        if not args.quick:
            counts = {
                action: sum(1 for task in validation_tasks if task.action == action)
                for action in ("fmt", "check", "test")
            }
            phase(
                f"Running {len(validation_tasks)} Roc validation tasks: {counts['fmt']} fmt batches over "
                f"{len(fmt_sources)} files, {counts['test']} test roots, {counts['check']} check roots; "
                f"{len(plan.delegated)} fixture roots are checked by their builds "
                f"({skipped_tasks} documented skips)"
            )
            run_parallel_roc_tasks(seed_tasks, 1)
            run_parallel_roc_tasks(other_tasks, args.jobs)
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

        build_jobs = min(args.jobs, suite.toolchain.max_build_workers, default_build_jobs())
        phase(
            f"Building {len(units)} fixture executables "
            f"({sum(1 for unit in units if unit.key.startswith('group-'))} groups, "
            f"{sum(1 for unit in units if unit.generated is not None)} generated {args.group_mode} apps, "
            f"{sum(1 for unit in units if unit.key.startswith('source-'))} sources) "
            f"with {build_jobs} job{'s' if build_jobs != 1 else ''} "
            f"(toolchain cap {suite.toolchain.max_build_workers})"
        )
        baseline_deltas: list[BaselineDelta] = []
        baseline_drift: list[BaselineDelta] = []
        build_case_units(
            units,
            build_dir,
            target,
            suite.toolchain.roc_optimization if check_allocations else "dev",
            build_jobs,
        )
        phase(f"Executing {len(suite.cases)} evidence cases with {args.jobs} workers")
        unit_use_counts = {
            unit.key: sum(1 for candidate in suite.cases if units_by_case[candidate.name].key == unit.key)
            for unit in units
        }

        def execute_case(item: tuple[int, TestCase]) -> tuple[int, TestCase, CaseRunResult, float]:
            index, case = item
            started = time.monotonic()
            unit = units_by_case[case.name]
            detail(
                f"START CASE {case.name} "
                f"({unit_label(unit)}, {unit_use_counts[unit.key]} "
                f"case{'s' if unit_use_counts[unit.key] != 1 else ''}/build)"
            )
            result = run_case(
                case,
                index,
                build_dir / unit.key,
                target,
                suite.protocol_version,
                args.update_snapshots,
                check_allocations,
                args.compare_baselines,
                args.linux_x64_container,
                1 if args.group_mode == "inject" and case.group is not None else 0,
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
                if result.drift is not None:
                    baseline_drift.append(result.drift)
        except KeyboardInterrupt:
            cancel_parallel(executor, futures)
            raise
        else:
            executor.shutdown()

    if args.baseline_report is not None:
        work_names = {case.name: case.work_counters for case in suite.cases}
        # The report lists every exact difference, including allocated bytes
        # that stay inside the ceiling, so a reviewed rebaseline can lower
        # recorded ceilings as well as accept failing deltas.
        report = [
            {
                "case": delta.case_name,
                "expected": {
                    "allocations": delta.expected.allocations,
                    "allocated_bytes": delta.expected.allocated_bytes,
                    "work": dict(zip(work_names[delta.case_name], delta.expected.work)),
                },
                "actual": {
                    "allocations": delta.actual.allocations,
                    "allocated_bytes": delta.actual.allocated_bytes,
                    "work": dict(zip(work_names[delta.case_name], delta.actual.work)),
                },
            }
            for delta in sorted(baseline_drift, key=lambda item: item.case_name)
        ]
        args.baseline_report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        announce("RUN", f"Wrote {len(report)} baseline differences to {args.baseline_report}")

    if args.update_snapshots:
        phase("Post-update contract validation")
        for check_id in suite.post_update_checks:
            command(
                sys.executable,
                f"scripts/{PREFLIGHT_CHECKS[check_id].script}",
                "--self-test",
            )

    if baseline_deltas:
        announce("FAIL", "Allocation baseline comparison:")
        announce("FAIL", "| Case | Expected | Actual | Delta | Allocated bytes | Work counters |")
        announce("FAIL", "| --- | ---: | ---: | ---: | --- | --- |")
        for delta in baseline_deltas:
            work_status = "unchanged" if delta.expected.work == delta.actual.work else "CHANGED"
            allocation_delta = delta.actual.allocations - delta.expected.allocations
            bytes_status = (
                f"{delta.actual.allocated_bytes} OVER CEILING of {delta.expected.allocated_bytes}"
                if allocated_bytes_exceeded(delta.expected, delta.actual)
                else f"{delta.actual.allocated_bytes} (recorded {delta.expected.allocated_bytes})"
            )
            announce(
                "FAIL",
                f"| {delta.case_name} | {delta.expected.allocations} | "
                f"{delta.actual.allocations} | {allocation_delta:+d} | {bytes_status} | {work_status} |",
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
