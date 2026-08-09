#!/usr/bin/env python3
"""Build and test the public facade from a locally served Roc package bundle."""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from check_gate3_facade_output import validate_facade_output_pdf


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "tests" / "gate3_pdf_facade" / "main.roc"
TEMP_ROOT = ROOT / ".roc-pdf-tmp"
PINNED_ROC_PATH = ROOT.parent / "roc-worktrees" / "fix-10697" / "zig-out" / "bin" / "roc"
ZIG = os.environ.get("ZIG", "zig")
PACKAGE_DEPENDENCY = 'pdf: "../../package/main.roc",'
PLATFORM_DEPENDENCY = 'pf: platform "../platform/main.roc",'
SERVER_READY_TIMEOUT_SECONDS = 5.0
SERVER_REQUEST_TIMEOUT_SECONDS = 0.5
SERVER_POLL_INTERVAL_SECONDS = 0.05


class TestFailure(RuntimeError):
    pass


def command(*args: str, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(args), flush=True)
    completed = subprocess.run(args, cwd=cwd, env=env, check=False)
    if completed.returncode != 0:
        raise TestFailure(f"command exited {completed.returncode}: {' '.join(args)}")


def default_roc() -> str:
    return str(PINNED_ROC_PATH) if PINNED_ROC_PATH.is_file() else "roc"


def verify_pinned_roc(roc: str) -> None:
    if shutil.which(roc) is None:
        raise TestFailure(f"{roc!r} was not found on PATH")
    result = subprocess.run([roc, "version"], text=True, stdout=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise TestFailure(f"could not read Roc version from {roc!r}")
    actual = result.stdout.strip()
    pinned = (ROOT / ".roc-version").read_text(encoding="utf-8").strip()
    revision = pinned.rsplit("-", 1)[-1]
    if pinned not in actual and revision not in actual:
        raise TestFailure(f"repository requires {pinned}, got {actual!r}")
    print(f"Using {actual}")


def build_bundle(roc: str, output_dir: Path) -> Path:
    env = os.environ.copy()
    env["ROC"] = roc
    command("bash", "scripts/bundle.sh", "--output-dir", str(output_dir), env=env)
    bundles = sorted(output_dir.glob("*.tar.zst"))
    if len(bundles) != 1:
        raise TestFailure(f"expected one .tar.zst bundle in {output_dir}, found {len(bundles)}")
    return bundles[0]


class BundleRequestHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass

    def do_GET(self) -> None:
        self.server.bundle_get_requests += 1  # type: ignore[attr-defined]
        super().do_GET()


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(BundleRequestHandler, directory=str(bundle.parent))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.server.bundle_get_requests = 0  # type: ignore[attr-defined]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> BundleServer:
        self.thread.start()
        deadline = time.monotonic() + SERVER_READY_TIMEOUT_SECONDS
        while True:
            try:
                request = urllib.request.Request(self.url, method="HEAD")
                with urllib.request.urlopen(request, timeout=SERVER_REQUEST_TIMEOUT_SECONDS) as response:
                    if response.status == 200:
                        return self
            except (OSError, urllib.error.URLError):
                if time.monotonic() >= deadline:
                    self.__exit__()
                    raise TestFailure(f"bundle server did not become ready: {self.url}")
                time.sleep(SERVER_POLL_INTERVAL_SECONDS)

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    @property
    def get_requests(self) -> int:
        return int(self.server.bundle_get_requests)  # type: ignore[attr-defined]


def relative(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def consumer_source(destination: Path, bundle_url: str) -> Path:
    source = EXAMPLE.read_text(encoding="utf-8")
    platform_path = os.path.relpath(ROOT / "tests" / "platform" / "main.roc", destination.parent)
    rewritten_platform = f'pf: platform "{platform_path.replace(os.sep, "/")}",'
    if source.count(PACKAGE_DEPENDENCY) != 1 or source.count(PLATFORM_DEPENDENCY) != 1:
        raise TestFailure("public facade fixture no longer has the expected local dependencies")
    source = source.replace(PACKAGE_DEPENDENCY, f'pdf: "{bundle_url}",')
    source = source.replace(PLATFORM_DEPENDENCY, rewritten_platform)
    destination.write_text(source, encoding="utf-8", newline="\n")
    return destination


def isolated_environment(cache_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    cache = str(cache_dir.resolve())
    env["ROC_CACHE_DIR"] = cache
    env["XDG_CACHE_HOME"] = cache
    return env


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default=os.environ.get("ROC", default_roc()))
    parser.add_argument("--bundle-path", type=Path)
    args = parser.parse_args()

    try:
        verify_pinned_roc(args.roc)
        TEMP_ROOT.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="bundle-consumer-", dir=TEMP_ROOT) as temporary:
            temporary_path = Path(temporary)
            bundle = args.bundle_path.resolve() if args.bundle_path is not None else build_bundle(args.roc, temporary_path / "dist")
            if not bundle.is_file():
                raise TestFailure(f"bundle does not exist: {bundle}")
            with BundleServer(bundle) as server:
                source = consumer_source(temporary_path / "pdf_facade.roc", server.url)
                env = isolated_environment(temporary_path / "roc-cache")
                executable = temporary_path / "pdf-facade-consumer"
                command(args.roc, "fmt", "--check", relative(source), env=env)
                command(args.roc, "check", relative(source), "--no-cache", env=env)
                command(ZIG, "build", "-Doptimize=ReleaseFast", cwd=ROOT / "tests" / "platform", env=env)
                command(args.roc, "build", relative(source), "--opt=dev", f"--output={relative(executable)}", "--no-cache", env=env)
                result = subprocess.run([executable, "0"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
                if result.returncode != 0:
                    raise TestFailure(f"bundled consumer exited {result.returncode}: {result.stderr.decode(errors='replace')}")
                validate_facade_output_pdf(result.stdout, "Café PDF generation in pure Roc.")
                if server.get_requests == 0:
                    raise TestFailure("consumer never requested the served package bundle")
    except (OSError, TestFailure) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
