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
import concurrent.futures
import copy
import hashlib
import json
import platform
import re
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roc_diagnostics import tolerated_warnings_only  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")
WORK = ROOT / ".roc-pdf-tmp" / "fuzz"
SEEDS = ROOT / ".roc-pdf-tmp" / "fuzz-corpus"
ARTIFACTS = ROOT / ".roc-pdf-tmp" / "fuzz-artifacts"
BASELINES = ROOT / "fuzz" / "baselines"
PLATFORM_RELEASE = "0.5.0"
PLATFORM_SHA256 = "aed4032105af1cc910604949f43636b7bff6aec4a82184631213153b8e2dd23f"
PLATFORM_URL = "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst"
PROFILE = "llvm-fuzz"


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


def validate_platform_header(source: str) -> None:
    declared = re.findall(r'\bfuzz\s*:\s*platform\s*"([^"]+)"', source)
    if declared != [PLATFORM_URL]:
        raise LaneFailure("application platform header differs from the verified release")


def validate_build_identity(recorded: dict, expected: dict, binary_sha256: str) -> None:
    if recorded != {**expected, "binary_sha256": binary_sha256}:
        raise LaneFailure("recorded executable is stale or modified; rebuild before measuring, checking or accepting")


def run(command: list[str], *, cwd: Path = ROOT, deadline: float | None = None, log_path: Path | None = None) -> None:
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
    if log_path is not None:
        log_path.write_text(result.stdout)
    sys.stdout.write(result.stdout)
    sys.stdout.flush()
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


def host_target(container: str | None) -> str:
    if container is not None or (sys.platform.startswith("linux") and platform.machine() == "x86_64"):
        return "x64musl"
    if sys.platform == "darwin" and platform.machine() == "arm64":
        return "arm64mac"
    raise SystemExit("roc-fuzz evidence supports Apple Silicon macOS and Linux x86-64")


def source_digest(target: Target) -> str:
    """Include the package and the target's actual local source/asset closure."""
    paths = set((ROOT / "package").rglob("*.roc"))
    pending = [ROOT / "fuzz" / f"{target.name}.roc", *paths]
    paths = {ROOT / ".roc-version"}
    while pending:
        path = pending.pop().resolve()
        if path in paths:
            continue
        paths.add(path)
        if path.suffix != ".roc":
            continue
        source = path.read_text()
        for relative in re.findall(r'^import "([^"]+)"', source, re.MULTILINE):
            pending.append(path.parent / relative)
        for module in re.findall(r'^import ([A-Z][A-Za-z0-9_]*)(?:\s|$)', source, re.MULTILINE):
            local = path.parent / f"{module}.roc"
            if local.is_file():
                pending.append(local)
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode() + b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def build_target(target: Target, host: str, compiler: str, no_build: bool, *, log_dir: Path) -> Path:
    source = ROOT / "fuzz" / f"{target.name}.roc"
    validate_platform_header(source.read_text())
    directory = WORK / host
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / target.name
    stamp = directory / f"{target.name}.build.json"
    identity = {"source_sha256": source_digest(target), "compiler": compiler, "target": host,
                "platform_sha256": PLATFORM_SHA256, "profile": PROFILE}
    if no_build:
        if not binary.is_file() or not stamp.is_file():
            raise LaneFailure(f"{target.name}: --no-build needs a prior recorded build")
        validate_build_identity(json.loads(stamp.read_text()), identity, hashlib.sha256(binary.read_bytes()).hexdigest())
    else:
        print(f"BUILD {target.name} ({host})", flush=True)
        run([ROC, "build", "--fuzz", str(source.relative_to(ROOT)), f"--target={host}", f"--output={binary}"], log_path=log_dir / f"{target.name}.build.log")
        if source_digest(target) != identity["source_sha256"]:
            raise LaneFailure(f"{target.name}: source changed during compilation; rebuild before checking or accepting")
        stamp.write_text(json.dumps({**identity, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}, indent=2) + "\n")
    return binary


def invocation(binary: Path, arguments: list[str], container: str | None) -> list[str]:
    command = [str(binary), *arguments]
    if container is None:
        return command
    return ["docker", "run", "--rm", "--platform", "linux/amd64", "--volume", f"{ROOT}:{ROOT}",
            "--workdir", str(ROOT), container, *command]


def validate_report(report: dict, target: Target, host: str, command: str, *, provenance: dict, configuration: dict, baseline: str) -> None:
    """Project policy supplements the supervisor: an unbaselined check cannot pass."""
    expected = {"format": "roc-fuzz-quality/1", "metric_version": "roc-fuzz-allocations/1",
                "target": "roc-pdf-" + target.name.replace("_", "-"), "host_target": host,
                "profile": PROFILE, "command": command, "outcome": "passed",
                "baseline_status": "accepted" if command == "accept" else "matched"}
    for key, value in expected.items():
        if report.get(key) != value:
            raise LaneFailure(f"{target.name}: report {key}: expected {value!r}, got {report.get(key)!r}")
    for key, value in {"provenance": provenance, "configuration": configuration, "baseline_path": baseline}.items():
        if report.get(key) != value:
            raise LaneFailure(f"{target.name}: report {key} differs from the requested invocation")
    if report.get("preparation", {}).get("status") != "passed":
        raise LaneFailure(f"{target.name}: example preparation did not complete")
    examples = report.get("examples", [])
    if not examples:
        raise LaneFailure(f"{target.name}: declared regression inventory is empty")
    for example in examples:
        if example.get("outcome") != "passed" or any(example.get(key) is not True for key in
                                                   ("metric_valid", "trace_rules_passed", "capture_complete")):
            raise LaneFailure(f"{target.name}: incomplete or failed example {example.get('name')}")
        if not example.get("observations"):
            raise LaneFailure(f"{target.name}: example has no allocator observations")
    if report.get("configuration", {}).get("leak_detection") is not True:
        raise LaneFailure(f"{target.name}: invocation leak checking is disabled")
    if command == "run":
        exploration = report.get("exploration", {})
        if exploration.get("status") != "passed" or exploration.get("accepted", 0) == 0:
            raise LaneFailure(f"{target.name}: exploration did not exercise any accepted input")


def fuzz_target(target: Target, binary: Path, budget: Budget, timeout: int, memory_limit: int,
                *, host: str, container: str | None, command: str, report_root: Path,
                compiler: str, revision: str) -> float:
    report_dir = report_root / target.name
    arguments = [command, f"--report-dir={report_dir}", f"--baseline={BASELINES / (target.name + '.json')}",
                 f"--profile={PROFILE}", f"--timeout={timeout}", f"--source-revision={revision}",
                 f"--roc-version={compiler}", f"--platform-release={PLATFORM_RELEASE}",
                 f"--platform-sha256={PLATFORM_SHA256}"]
    provenance = {"source_revision": revision, "roc_version": compiler,
                  "platform_release": PLATFORM_RELEASE, "platform_sha256": PLATFORM_SHA256}
    configuration = {"invocation_deadline_ms": timeout * 1000, "campaign_deadline_ms": None,
                     "leak_detection": True, "detailed_capture": False, "corpus": None, "exploration_options": []}
    if command == "run":
        corpus = corpus_for(target)
        configuration["corpus"] = str(corpus)
        configuration["campaign_deadline_ms"] = (budget.seconds + timeout + 5) * 1000 if budget.seconds else None
        native_options = [f"-timeout={timeout}", f"-runs={budget.runs}",
                          f"-max_total_time={budget.seconds if budget.seconds is not None else 0}",
                          f"-max_len={target.max_input_size}", f"-rss_limit_mb={memory_limit}"]
        if budget.seed is not None:
            native_options.append(f"-seed={budget.seed}")
        # The pinned supervisor explicitly records its default timeout in addition
        # to the supplied timeout option. Preserve that actual effective inventory.
        if timeout == 10:
            native_options.append("-timeout=10")
        configuration["exploration_options"] = native_options
        arguments.extend([str(corpus), f"--runs={budget.runs}",
                          f"--time={budget.seconds if budget.seconds is not None else 0}",
                          f"--max-input-size={target.max_input_size}", f"--memory-limit={memory_limit}"])
        if budget.seed is not None:
            arguments.append(f"--seed={budget.seed}")
    started = time.monotonic()
    run(invocation(binary, arguments, container), deadline=budget.deadline)
    path = report_dir / "report.json"
    if not path.is_file():
        raise LaneFailure(f"{target.name}: supervisor returned without report.json")
    try:
        report = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise LaneFailure(f"{target.name}: unreadable supervisor report: {error}") from error
    validate_report(report, target, host, command, provenance=provenance, configuration=configuration,
                    baseline=str(BASELINES / (target.name + ".json")))
    return time.monotonic() - started


def self_test() -> None:
    target = TARGETS[0]
    passed = {"format": "roc-fuzz-quality/1", "metric_version": "roc-fuzz-allocations/1",
              "target": "roc-pdf-font-inspector-mutation", "host_target": "arm64mac", "profile": PROFILE,
              "command": "run", "outcome": "passed", "baseline_status": "matched",
              "preparation": {"status": "passed"}, "configuration": {"leak_detection": True},
              "examples": [{"name": "valid", "outcome": "passed", "metric_valid": True,
                            "trace_rules_passed": True, "capture_complete": True, "observations": [{"name": "$property"}]}],
              "exploration": {"status": "passed", "accepted": 1}}
    provenance = {"source_revision": "checked-source", "roc_version": "pinned-compiler",
                  "platform_release": PLATFORM_RELEASE, "platform_sha256": PLATFORM_SHA256}
    configuration = {"invocation_deadline_ms": 10000, "campaign_deadline_ms": 16000,
                     "leak_detection": True, "detailed_capture": False, "corpus": "selected-corpus",
                     "exploration_options": ["-runs=64", "-max_len=524288"]}
    passed["configuration"] = configuration
    baseline = "example-baseline.json"
    passed.update(provenance=provenance, baseline_path=baseline)
    validate = lambda value: validate_report(value, target, "arm64mac", "run", provenance=provenance,
                                            configuration=configuration, baseline=baseline)
    validate(passed)
    mutations = [("baseline_status", "unbaselined"), ("outcome", "baseline_changed"),
                 ("host_target", "x64musl"), ("examples", []),
                 ("exploration", {"status": "passed", "accepted": 0}),
                 ("configuration", {**configuration, "leak_detection": False}),
                 ("configuration", {**configuration, "invocation_deadline_ms": 0}),
                 ("configuration", {**configuration, "exploration_options": ["-runs=999999"]}),
                 ("provenance", {**provenance, "platform_release": "wrong"}),
                 ("provenance", {**provenance, "platform_sha256": "0" * 64}),
                 ("provenance", {**provenance, "source_revision": "unchecked"}),
                 ("provenance", {**provenance, "roc_version": "other-compiler"}),
                 ("baseline_path", "other-baseline.json")]
    for key, value in mutations:
        broken = {**passed, key: value}
        try:
            validate(broken)
        except LaneFailure:
            pass
        else:
            raise SystemExit(f"report self-test failed to reject {key}")
    for key in ("metric_valid", "trace_rules_passed", "capture_complete"):
        broken = copy.deepcopy(passed)
        broken["examples"][0][key] = False
        try:
            validate(broken)
        except LaneFailure:
            pass
        else:
            raise SystemExit(f"report self-test failed to reject {key}")
    validate_platform_header('app [target] { fuzz: platform "' + PLATFORM_URL + '" }')
    for source in ('app [target] { fuzz: platform "other" }',
                   '# fuzz: platform "' + PLATFORM_URL + '"\napp [target] { fuzz: platform "other" }',
                   'app [target] {}'):
        try:
            validate_platform_header(source)
        except LaneFailure:
            pass
        else:
            raise SystemExit("platform binding self-test accepted an unverified header")
    build = {"source_sha256": "source", "compiler": "compiler", "target": "arm64mac",
             "platform_sha256": PLATFORM_SHA256, "profile": PROFILE}
    recorded = {**build, "binary_sha256": "binary"}
    validate_build_identity(recorded, build, "binary")
    for key in (*build, "binary_sha256"):
        broken = {**recorded, key: "different"}
        try:
            validate_build_identity(broken, build, "binary")
        except LaneFailure:
            pass
        else:
            raise SystemExit(f"build identity self-test failed to reject {key}")
    print("PASS fuzz report/build identity policy self-test", flush=True)


def default_build_jobs() -> int:
    """Parallel `roc build --fuzz` processes the machine's memory allows.

    An LLVM fuzz build of a facade target peaks at about 5.6 GB resident on
    nightly-2026-10-23, so each build is budgeted 6 GB with 2 GB held back.
    """
    cpus = max(1, os.cpu_count() or 1)
    try:
        memory = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except (OSError, ValueError):
        return 1
    cgroup_limit = Path("/sys/fs/cgroup/memory.max")
    try:
        value = cgroup_limit.read_text(encoding="ascii").strip()
        if value != "max":
            memory = min(memory, int(value))
    except (OSError, ValueError):
        pass
    by_memory = max(1, (memory - 2 * 1024**3) // (6 * 1024**3))
    return max(1, min(cpus, by_memory))


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
    parser.add_argument("--self-test", action="store_true", help="check report rejection policy without compiling targets")
    parser.add_argument("--no-build", action="store_true", help="reuse only an executable whose source/compiler stamp still matches")
    parser.add_argument("--linux-x64-container", metavar="IMAGE", help="cross-build x64musl and execute in the named Linux container")
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--check-only", action="store_true", help="check declared examples/baselines without exploration")
    operation.add_argument("--accept-baselines", action="store_true", help="explicit maintainer acceptance of reviewed named-example observations")
    parser.add_argument(
        "--targets",
        action="append",
        metavar="NAME",
        help="run only this target; repeatable",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        help="parallel target builds (default: as many as memory allows at 6 GB each); runs stay sequential",
    )
    parser.add_argument("--timeout", type=int, default=10, help="seconds per target call")
    parser.add_argument("--memory-limit", type=int, default=2048, help="MB per target process")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return
    if args.timeout < 1 or args.memory_limit < 1:
        parser.error("--timeout and --memory-limit must be positive")
    host = host_target(args.linux_x64_container)
    compiler = subprocess.check_output([ROC, "version"], text=True).strip()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        revision += "-dirty"
    command = "accept" if args.accept_baselines else "check" if args.check_only else "run"
    BASELINES.mkdir(exist_ok=True)
    report_root = ARTIFACTS / f"{host}-{command}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}-{os.getpid()}"
    report_root.mkdir(parents=True)
    print(f"Supervisor evidence: {report_root.relative_to(ROOT)}", flush=True)

    known = {target.name: target for target in TARGETS}
    if args.targets:
        unknown = sorted(set(args.targets) - set(known))
        if unknown:
            raise SystemExit(f"unknown targets: {', '.join(unknown)}")
        selected = [known[name] for name in dict.fromkeys(args.targets)]
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
    jobs = default_build_jobs() if args.jobs is None else args.jobs
    if jobs < 1:
        raise SystemExit("--jobs must be positive")
    print(f"Building {len(selected)} targets with {jobs} parallel builds", flush=True)
    (report_root / "invocation.json").write_text(json.dumps({
        "format": "roc-pdf-fuzz-lane/1", "source_revision": revision, "compiler": compiler,
        "platform_release": PLATFORM_RELEASE, "platform_sha256": PLATFORM_SHA256, "profile": PROFILE,
        "host_target": host, "command": command, "mode": args.mode,
        "runs": budget.runs, "seconds": budget.seconds, "seed": budget.seed,
        "hard_deadline_seconds": budget.deadline, "timeout_seconds": args.timeout,
        "memory_limit_mb": args.memory_limit, "targets": [target.name for target in selected],
    }, indent=2) + "\n")
    failures: list[str] = []
    binaries: dict[str, Path] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(build_target, target, host, compiler, args.no_build, log_dir=report_root): target for target in selected}
        for future in concurrent.futures.as_completed(futures):
            target = futures[future]
            try:
                binaries[target.name] = future.result()
            except LaneFailure as error:
                print(f"FAIL {target.name}: build {error}", flush=True)
                failures.append(target.name)
    # Runs are sequential so that each target's workload and memory limit are
    # its own.
    for target in selected:
        if target.name not in binaries:
            continue
        try:
            elapsed = fuzz_target(target, binaries[target.name], budget, args.timeout, args.memory_limit,
                                  host=host, container=args.linux_x64_container, command=command,
                                  report_root=report_root, compiler=compiler, revision=revision)
        except LaneFailure as error:
            print(f"FAIL {target.name}: {error}", flush=True)
            failures.append(target.name)
        else:
            print(f"PASS {target.name} ({command}, {args.mode}, {budget.runs} run cap, workload {elapsed:.1f}s)", flush=True)
    (report_root / "lane-summary.json").write_text(json.dumps({"failed_targets": failures,
        "passed_targets": [target.name for target in selected if target.name not in failures]}, indent=2) + "\n")
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
