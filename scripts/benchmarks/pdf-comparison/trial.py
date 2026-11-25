#!/usr/bin/env python3
"""Optional source/build/run comparison; not a product performance gate."""
from __future__ import annotations

import argparse
import ctypes
import fcntl
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MARKER = "PDF_BENCH "
URL = re.compile(r'https://[^\s"<>]+/([^/\s"]+)\.tar\.zst')


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def executable(value: str) -> str:
    # Preserve virtualenv symlinks: resolving one changes Python's environment.
    found = shutil.which(value)
    if found is None:
        raise SystemExit(f"Executable unavailable: {value}")
    return os.path.abspath(found)


def hardware() -> dict:
    info = {"cpu_model": platform.processor() or None, "logical_cpus": os.cpu_count(), "physical_memory_bytes": None}
    if sys.platform == "darwin":
        library = ctypes.CDLL(None)
        for name, field in [(b"machdep.cpu.brand_string", "cpu_model"), (b"hw.memsize", "physical_memory_bytes")]:
            buffer = ctypes.create_string_buffer(256)
            length = ctypes.c_size_t(len(buffer))
            if library.sysctlbyname(name, buffer, ctypes.byref(length), None, 0) == 0:
                raw = buffer.raw[:length.value]
                info[field] = raw.rstrip(b"\0").decode() if field == "cpu_model" else int.from_bytes(raw, sys.byteorder)
    elif sys.platform == "linux":
        cpuinfo = Path("/proc/cpuinfo").read_text()
        match = re.search(r"^model name\s*:\s*(.+)$", cpuinfo, re.M)
        if match:
            info["cpu_model"] = match.group(1)
        match = re.search(r"^MemTotal:\s+(\d+) kB", Path("/proc/meminfo").read_text(), re.M)
        if match:
            info["physical_memory_bytes"] = int(match.group(1)) * 1024
    return info


def capture(command: list[str], *, cwd: Path, env: dict[str, str]) -> str:
    return subprocess.run(command, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def measure(command: list[str], cwd: Path, env: dict[str, str], log: Path,
            timeout: float) -> dict:
    """One direct child, separate process group, real wait4 resource usage.

    Files avoid pipe backpressure and unbounded compiler diagnostic buffers.
    os.posix_spawn avoids inheriting the Python parent's RSS high-water mark.
    """
    out_path, err_path = log.with_suffix(".stdout"), log.with_suffix(".stderr")
    started_utc = datetime.now(timezone.utc).isoformat()
    started = time.perf_counter_ns()
    with out_path.open("wb") as out, err_path.open("wb") as err:
        previous = Path.cwd()
        os.chdir(cwd)
        try:
            pid = os.posix_spawn(command[0], command, env, setpgroup=0, file_actions=[
                (os.POSIX_SPAWN_DUP2, out.fileno(), 1),
                (os.POSIX_SPAWN_DUP2, err.fileno(), 2),
            ])
        finally:
            os.chdir(previous)
        expired = False
        old_handler = signal.getsignal(signal.SIGALRM)
        def alarm(_signal, _frame):
            raise TimeoutError("command timeout")
        signal.signal(signal.SIGALRM, alarm)
        signal.setitimer(signal.ITIMER_REAL, timeout)
        try:
            _, status, usage = os.wait4(pid, 0)
        except TimeoutError:
            expired = True
            os.killpg(pid, signal.SIGKILL)
            _, status, usage = os.wait4(pid, 0)
        except BaseException:
            try:
                os.killpg(pid, signal.SIGKILL)
                os.wait4(pid, 0)
            except ProcessLookupError:
                pass
            raise
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old_handler)
    elapsed = time.perf_counter_ns() - started
    return {
        "command": command, "cwd": str(cwd),
        "started_utc": started_utc,
        "wall_ns": elapsed, "user_cpu_ns": round(usage.ru_utime * 1e9),
        "system_cpu_ns": round(usage.ru_stime * 1e9),
        "wait4_maxrss_bytes": int(usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024)),
        "exit_code": os.waitstatus_to_exitcode(status), "timed_out": expired,
        "stdout": str(out_path), "stderr": str(err_path),
    }


def generate(directory: Path, workload: dict, edited: bool) -> None:
    values = {key: workload[key] for key in ("title", "paragraphs", "headers", "rows", "footer")}
    values["revision"] = workload["edited_revision" if edited else "revision"]
    quoted = lambda value: json.dumps(value, ensure_ascii=True)
    roc = ["Workload :: [].{"]
    for key, value in values.items():
        typ = "List(List(Str))" if key == "rows" else "List(Str)" if isinstance(value, list) else "Str"
        roc += [f"\t{key} : {typ}", f"\t{key} = {quoted(value)}"]
    (directory / "Workload.roc").write_text("\n".join(roc + ["}", ""]))
    (directory / "workload.py").write_text("\n".join(f"{key.upper()} = {value!r}" for key, value in values.items()) + "\n")
    go = ["package main", ""]
    for key, value in values.items():
        name = "footerText" if key == "footer" else key
        if key == "rows":
            literal = "[][]string{" + ",".join("{" + ",".join(map(quoted, row)) + "}" for row in value) + "}"
        elif isinstance(value, list):
            literal = "[]string{" + ",".join(map(quoted, value)) + "}"
        else:
            literal = quoted(value)
        go.append(f"var {name} = {literal}")
    (directory / "workload.go").write_text("\n".join(go) + "\n")


def dependencies(workspace: Path, source: Path) -> list[dict]:
    """Seed immutable packages only, never the compiler's procedure cache."""
    destination = workspace / "dependency-cache/roc/packages"
    destination.mkdir(parents=True)
    pending = [HERE / "main.roc.in", ROOT / "package/main.roc"]
    copied: set[str] = set()
    records = []
    while pending:
        for match in URL.finditer(pending.pop().read_text()):
            url, identity = match.group(0), match.group(1)
            if identity in copied:
                continue
            cached = source / identity
            if not (cached / "main.roc").is_file():
                raise SystemExit(f"Missing provisioned Roc dependency: {url}\nExpected {cached}; install dependencies before preparing the trial.")
            shutil.copytree(cached, destination / identity)
            sidecar = source / f"{identity}.deps.json"
            if sidecar.exists():
                shutil.copy2(sidecar, destination / sidecar.name)
            archive = cached / f"{identity}.tar.zst"
            records.append({"url": url, "archive_sha256": digest(archive) if archive.exists() else None})
            copied.add(identity)
            pending.append(cached / "main.roc")
    return records


def environments(workspace: Path, track: str, language: str) -> dict[str, str]:
    env = dict(os.environ)
    env["XDG_CACHE_HOME"] = str(workspace / "dependency-cache")
    env["ROC_CACHE_DIR"] = str(workspace / "caches" / f"{track}-{language}")
    env["GOCACHE"] = str(workspace / "caches" / f"{track}-{language}")
    env["GOMODCACHE"] = str(workspace / "go-modules")
    env["GOPATH"] = str(workspace / "go-path")
    env["GOTOOLCHAIN"] = "local"
    # Dependency acquisition belongs to prepare; measurements must work offline.
    env["GOPROXY"] = "off"
    env["GOSUMDB"] = "off"
    return env


def prepare(args: argparse.Namespace) -> None:
    workspace = args.workspace.absolute()
    workspace.mkdir(parents=True, exist_ok=False)
    (workspace / "logs").mkdir()
    begin = time.perf_counter_ns()
    tools = {"roc": executable(args.roc), "python": executable(args.python), "go": executable(args.go)}
    roc_version = capture([tools["roc"], "version"], cwd=ROOT, env=dict(os.environ))
    pin = (ROOT / ".roc-version").read_text().strip()
    if not roc_version.endswith(pin):
        raise SystemExit(f"Compiler must match .roc-version ({pin}); got {roc_version}")
    workload = json.loads((HERE / "workload.json").read_text())
    manifest = {
        "schema": 1, "created_utc": datetime.now(timezone.utc).isoformat(),
        "repository": str(ROOT), "git_head": capture(["git", "rev-parse", "HEAD"], cwd=ROOT, env=dict(os.environ)),
        "platform": platform.platform(), "machine": platform.machine(), "hardware": hardware(), "tools": tools,
        "versions": {"roc": roc_version, "go": capture([tools["go"], "version"], cwd=ROOT, env=dict(os.environ))},
        "workload": workload, "workload_sha256": digest(HERE / "workload.json"),
        "font_source": "package/RocPdfSans-Regular.ttf", "font_sha256": digest(ROOT / "package/RocPdfSans-Regular.ttf"),
        "font_bytes": (ROOT / "package/RocPdfSans-Regular.ttf").stat().st_size,
        "sources_sha256": {p.name: digest(p) for p in sorted(HERE.iterdir()) if p.is_file()},
        "package_sources_sha256": {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / "package").rglob("*")) if p.is_file()},
        "roc_dependencies": dependencies(workspace, args.roc_packages),
        "setup_commands": [],
    }
    for track, language in [("script", "python"), ("script", "roc"), ("compiled", "roc"), ("compiled", "go")]:
        directory = workspace / track / language
        directory.mkdir(parents=True)
        for filename in ("report.py", "main.go", "go.mod"):
            shutil.copy2(HERE / filename, directory / filename)
        if (HERE / "go.sum").exists():
            shutil.copy2(HERE / "go.sum", directory / "go.sum")
        template = (HERE / "main.roc.in").read_text()
        (directory / "main.roc").write_text(template.replace("@PDF_PACKAGE@", json.dumps(str(ROOT / "package/main.roc"))))
        shutil.copy2(ROOT / "package/RocPdfSans-Regular.ttf", directory / "font.ttf")
        generate(directory, workload, False)
    python = tools["python"]
    if not args.existing_python:
        subprocess.run([python, "-m", "venv", str(workspace / "venv")], check=True)
        python = str(workspace / "venv/bin/python")
        command = [python, "-m", "pip", "install", "--disable-pip-version-check", "--no-cache-dir", "-r", str(HERE / "requirements.txt")]
        subprocess.run(command, check=True)
        manifest["setup_commands"].append(command)
    manifest["tools"]["python"] = python
    manifest["versions"]["python"] = json.loads(capture([python, "-c", "import sys,reportlab,PIL,charset_normalizer,json; print(json.dumps({'python':sys.version,'reportlab':reportlab.Version,'pillow':PIL.__version__,'charset_normalizer':charset_normalizer.__version__}))"], cwd=ROOT, env=dict(os.environ)))
    env = environments(workspace, "setup", "go")
    env.pop("GOPROXY")
    env.pop("GOSUMDB")
    command = [tools["go"], "mod", "download", "all"]
    subprocess.run(command, cwd=workspace / "compiled/go", env=env, check=True)
    manifest["setup_commands"].append(command)
    manifest["go_sum_sha256"] = digest(workspace / "compiled/go/go.sum")
    manifest["prepared_sources_sha256"] = {
        str(p.relative_to(workspace)): digest(p)
        for track in ("script", "compiled")
        for p in sorted((workspace / track).rglob("*"))
        if p.is_file() and p.name not in ("Workload.roc", "workload.py", "workload.go")
    }
    manifest["setup_wall_ns"] = time.perf_counter_ns() - begin
    dump(workspace / "manifest.json", manifest)
    print(f"Prepared {workspace}\nDependency setup: {manifest['setup_wall_ns'] / 1e9:.2f}s (excluded from trial timings)", flush=True)


def metrics(stdout: Path) -> dict:
    lines = [line[len(MARKER):] for line in stdout.read_text().splitlines() if line.startswith(MARKER)]
    if len(lines) != 1:
        raise ValueError(f"Expected exactly one application metric record: {stdout}")
    value = json.loads(lines[0])
    if (type(value.get("schema")) is not int or value["schema"] != 1
            or type(value.get("pdf_bytes")) is not int or value["pdf_bytes"] <= 0
            or type(value.get("application_ns")) is not int or value["application_ns"] < 0):
        raise ValueError(f"Invalid metrics schema: {stdout}")
    phases = [v for k, v in value.items() if k.endswith("_ns") and k != "application_ns"]
    if not phases or any(type(v) is not int or v < 0 for v in phases):
        raise ValueError(f"Invalid durations: {value}")
    if sum(phases) != value.get("application_ns"):
        raise ValueError(f"Application phases do not reconcile: {value}")
    return value


def validate(pdf: Path, workload: dict, edited: bool) -> dict:
    def tool(name: str, *arguments: str) -> str:
        result = subprocess.run([executable(name), *arguments], check=True, capture_output=True, text=True)
        if result.stderr.strip():
            raise ValueError(f"{name} diagnostic: {result.stderr}")
        return result.stdout
    info = tool("pdfinfo", str(pdf))
    if not re.search(r"^Pages:\s+1$", info, re.M) or not re.search(r"^Page size:\s+595 x 842 pts", info, re.M):
        raise ValueError(f"Expected one 595 x 842 pt page: {pdf}\n{info}")
    text = " ".join(tool("pdftotext", str(pdf), "-").split())
    expected = [workload["title"], *workload["paragraphs"], "Completed requests by team", *workload["headers"], workload["footer"], workload["edited_revision" if edited else "revision"]]
    expected += [cell for row in workload["rows"] for cell in row]
    for snippet in expected:
        if snippet not in text:
            raise ValueError(f"Missing text {snippet!r}: {pdf}")
    missing = Counter(" ".join(expected).split()) - Counter(text.split())
    if missing:
        raise ValueError(f"Missing expected text occurrences: {dict(missing)}: {pdf}")
    fonts = tool("pdffonts", str(pdf)).splitlines()[2:]
    if not fonts or any(not re.search(r"\s+yes\s+(yes|no)\s+(yes|no)\s+\d+\s+\d+\s*$", line) for line in fonts):
        raise ValueError(f"Expected every font to be embedded: {fonts}")
    return {"pages": 1, "dimensions_points": [595, 842], "expected_text": "passed", "embedded_fonts": "passed", "pdfinfo": info, "pdffonts": fonts, "sha256": digest(pdf)}


def report(workspace: Path, results: dict) -> None:
    groups = defaultdict(list)
    for sample in results["samples"]:
        if sample.get("valid"):
            groups[(sample["track"], sample["language"], sample["cache_state"], sample["operation"])].append(sample)
    lines = ["# PDF comparison trial", "", "Diagnostic trial; no numeric acceptance targets. Medians below exclude failed or unvalidated samples.", "", "Same one-page report and runtime-loaded font. Roc uses its default Archive profile; ReportLab and fpdf produce ordinary PDFs without equivalent tagging/archival claims.", "", f"Retained failed attempts: {len(results['failures'])}. Raw commands, diagnostics, versions, hashes and hardware are in results.json and manifest.json.", "", "| Track | Language | Cache state | Operation | n | Wall ms | CPU ms | wait4 max RSS MiB | PDF bytes | Executable bytes |", "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    med = lambda values: statistics.median(values)
    for key, samples in groups.items():
        fields = [*key, str(len(samples)), f"{med(s['wall_ns'] for s in samples)/1e6:.2f}", f"{med(s['user_cpu_ns']+s['system_cpu_ns'] for s in samples)/1e6:.2f}", f"{med(s['wait4_maxrss_bytes'] for s in samples)/1048576:.2f}", str(samples[-1].get("pdf_bytes", "—")), str(samples[-1].get("executable_bytes", "—"))]
        lines.append("| " + " | ".join(fields) + " |")
    lines += ["", "RSS is the OS wait4 high-water value, not sampled aggregate process-tree memory. Build CPU/RSS scope is OS-dependent; see the trial README. Timings include write and close, without fsync. Source-run residual includes compilation, startup and teardown; it is not a compilation-only timer.", "", "## Application phases (median ms)", ""]
    for key, samples in groups.items():
        if "application" not in samples[0]:
            continue
        phases = samples[0]["application"].keys()
        values = [f"{phase.removesuffix('_ns')}={med(s['application'][phase] for s in samples)/1e6:.3f}" for phase in phases if phase.endswith("_ns")]
        values.append(f"outside_application={med(s['outside_application_ns'] for s in samples)/1e6:.3f}")
        lines.append("- " + "/".join(key) + ": " + ", ".join(values))
    lines += ["", "## Paired build plus first execution (ms)", "", "Build and execution CPU/wall times add; their peak RSS values do not add.", ""]
    pairs = defaultdict(dict)
    for sample in results["samples"]:
        if sample.get("valid") and sample["track"] == "compiled" and sample["sample"] == 0:
            pairs[(sample["language"], sample["cache_state"])][sample["operation"]] = sample
    for key, pair in pairs.items():
        if "build" in pair and "run" in pair:
            total = pair["build"]["wall_ns"] + pair["run"]["wall_ns"]
            cpu = sum(s["user_cpu_ns"] + s["system_cpu_ns"] for s in pair.values())
            lines.append(f"- {'/'.join(key)}: wall {total/1e6:.2f} (build {pair['build']['wall_ns']/1e6:.2f} + run {pair['run']['wall_ns']/1e6:.2f}); CPU {cpu/1e6:.2f}")
    (workspace / "summary.md").write_text("\n".join(lines) + "\n")


def run(args: argparse.Namespace) -> None:
    workspace = args.workspace.absolute()
    manifest = json.loads((workspace / "manifest.json").read_text())
    result_path = workspace / "results.json"
    results = json.loads(result_path.read_text()) if result_path.exists() else {"schema": 1, "samples": [], "failures": []}
    tools, workload = manifest["tools"], manifest["workload"]
    for filename, expected in manifest["sources_sha256"].items():
        if digest(HERE / filename) != expected:
            raise SystemExit(f"Trial source changed since preparation: {filename}; prepare a new workspace")
    workload_path = ROOT / "package/RocPdfSans-Regular.ttf"
    if digest(workload_path) != manifest["font_sha256"]:
        raise SystemExit("Font changed since preparation; prepare a new workspace")
    for relative, expected in manifest["package_sources_sha256"].items():
        if digest(ROOT / relative) != expected:
            raise SystemExit(f"Package source changed since preparation: {relative}")
    for relative, expected in manifest.get("prepared_sources_sha256", {}).items():
        if digest(workspace / relative) != expected:
            raise SystemExit(f"Prepared authoring source changed: {relative}; prepare a new workspace")
    for name in ("pdfinfo", "pdftotext", "pdffonts"):
        executable(name)
    if results.get("runtime_samples", args.runtime_samples) != args.runtime_samples:
        raise SystemExit("Use the same runtime-samples when resuming; prepare a new workspace to change it")
    results["runtime_samples"] = args.runtime_samples
    completed = {(s["track"], s["language"], s["cache_state"], s["operation"], s["sample"]) for s in results["samples"] if s.get("valid")}
    for track, language in [("script", "python"), ("script", "roc"), ("compiled", "go"), ("compiled", "roc")]:
        if track not in args.tracks or language not in args.languages:
            continue
        directory = workspace / track / language
        env = environments(workspace, track, language)
        for state in args.states:
            operations = [("source", 1)] if track == "script" else [("build", 1), ("run", args.runtime_samples)]
            if all((track, language, state, operation, index) in completed for operation, count in operations for index in range(count)):
                continue
            if state != "unchanged":
                generate(directory, workload, state == "edited")
            for operation, count in operations:
                for sample_index in range(count):
                    key = (track, language, state, operation, sample_index)
                    if key in completed:
                        continue
                    if state == "first" and operation != "run":
                        cache = workspace / "caches" / f"{track}-{language}"
                        if cache.exists() and any(cache.iterdir()):
                            raise SystemExit(f"First-use cache is already populated: {cache}; prepare a new workspace")
                        if language == "python" and (directory / "__pycache__").exists():
                            raise SystemExit("First-use Python bytecode is already populated; prepare a new workspace")
                    binary = directory / "report"
                    if operation == "build":
                        command = [tools["roc"], "build", "main.roc", f"--output={binary}"] if language == "roc" else [tools["go"], "build", "-o", str(binary), "."]
                        # Normal rebuilds keep the existing output artifact. A
                        # failed build is rejected before running it, and the
                        # revision check catches an incorrectly reused binary.
                        if state == "first":
                            binary.unlink(missing_ok=True)
                        existing_output = binary.exists()
                    elif operation == "run":
                        command = [str(binary)]
                    else:
                        command = [tools["python"], "report.py"] if language == "python" else [tools["roc"], "run", "main.roc"]
                    pdf = directory / "report.pdf"
                    pdf.unlink(missing_ok=True)
                    attempt = 1 + sum((s["track"], s["language"], s["cache_state"], s["operation"], s["sample"]) == key for s in results["samples"])
                    label = "-".join(map(str, key)) + f"-attempt-{attempt}"
                    print(f"START {label}", flush=True)
                    sample = measure(command, directory, env, workspace / "logs" / label, args.timeout)
                    sample.update(dict(zip(("track", "language", "cache_state", "operation", "sample"), key)))
                    try:
                        if sample["exit_code"] or sample["timed_out"]:
                            raise ValueError(f"Command failed: exit={sample['exit_code']}, timeout={sample['timed_out']}; see {sample['stderr']}")
                        if operation == "build":
                            if not binary.is_file() or not os.access(binary, os.X_OK):
                                raise ValueError("Build did not produce an executable")
                            sample["executable_bytes"] = binary.stat().st_size
                            sample["existing_output_before_build"] = existing_output
                            sample["executable_sha256"] = digest(binary)
                        else:
                            sample["application"] = metrics(Path(sample["stdout"]))
                            sample["validation"] = validate(pdf, workload, state == "edited")
                            if language == "roc":
                                for prior in results["samples"]:
                                    if (prior.get("valid") and prior["language"] == "roc" and "validation" in prior
                                            and (prior["cache_state"] == "edited") == (state == "edited")
                                            and prior["validation"]["sha256"] != sample["validation"]["sha256"]):
                                        raise ValueError("Identical Roc report inputs produced different PDF bytes")
                            sample["pdf_bytes"] = pdf.stat().st_size
                            if sample["application"]["pdf_bytes"] != sample["pdf_bytes"]:
                                raise ValueError("Reported PDF size differs from written file")
                            sample["outside_application_ns"] = sample["wall_ns"] - sample["application"]["application_ns"]
                            if sample["outside_application_ns"] < 0:
                                raise ValueError("Application duration exceeds command duration")
                            artifacts = workspace / "artifacts"
                            artifacts.mkdir(exist_ok=True)
                            shutil.copy2(pdf, artifacts / f"{label}.pdf")
                            if operation == "run":
                                sample["executable_bytes"] = binary.stat().st_size
                        sample["valid"] = True
                    except Exception as error:
                        sample["valid"] = False
                        if pdf.exists():
                            artifacts = workspace / "artifacts"
                            artifacts.mkdir(exist_ok=True)
                            shutil.copy2(pdf, artifacts / f"{label}-invalid.pdf")
                        results["failures"].append({"label": label, "error": str(error)})
                        results["samples"].append(sample)
                        dump(result_path, results)
                        report(workspace, results)
                        raise
                    results["samples"].append(sample)
                    dump(result_path, results)
                    report(workspace, results)
                    print(f"PASS {label}: {sample['wall_ns']/1e6:.2f} ms; RSS {sample['wait4_maxrss_bytes']/1048576:.2f} MiB", flush=True)
    print(f"Results: {result_path}\nSummary: {workspace / 'summary.md'}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    prep = sub.add_parser("prepare", help="Provision sources, font and dependencies outside measured commands")
    prep.add_argument("workspace", type=Path)
    prep.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    prep.add_argument("--python", default=sys.executable)
    prep.add_argument("--go", default="go")
    prep.add_argument("--roc-packages", type=Path, default=Path.home() / ".cache/roc/packages")
    prep.add_argument("--existing-python", action="store_true", help="Use the supplied Python environment without installing dependencies")
    trial = sub.add_parser("run", help="Run serial source/build/run trials; resume completed samples")
    trial.add_argument("workspace", type=Path)
    trial.add_argument("--tracks", nargs="+", choices=["script", "compiled"], default=["script", "compiled"])
    trial.add_argument("--languages", nargs="+", choices=["python", "roc", "go"], default=["python", "roc", "go"])
    trial.add_argument("--runtime-samples", type=int, default=5)
    trial.add_argument("--states", nargs="+", choices=["first", "unchanged", "edited"], default=["first", "unchanged", "edited"], help="Use --states first for a short smoke run; normal trials use all three in order")
    trial.add_argument("--timeout", type=float, default=1800)
    args = parser.parse_args()
    if args.action == "run" and (args.runtime_samples < 1 or args.timeout <= 0):
        parser.error("runtime-samples and timeout must be positive")
    if args.action == "run" and args.states not in (["first"], ["first", "unchanged", "edited"]):
        parser.error("states must be 'first' or 'first unchanged edited'")
    if args.action == "prepare":
        prepare(args)
    else:
        with (args.workspace / "trial.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise SystemExit("Another trial is running in this workspace; run trials serially")
            run(args)


if __name__ == "__main__":
    main()
