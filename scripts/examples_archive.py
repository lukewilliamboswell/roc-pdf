#!/usr/bin/env python3
"""Build the release examples archive tested by the shared nightly.

The archive follows roc-automation's published-release compatibility contract:
one root `roc-pdf-examples-<tag>/` holding `README.md`, `spec.json` and every
gallery example, each pointing at the release bundle URL. `--test-bundle`
extracts the exact archive, serves the local bundle at that URL's place and
runs every recorded case. Expected stdout is recorded by running each staged
example against the local bundle.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import zipfile
from pathlib import Path

from check_gallery import GALLERY, ROC, BundleServer, bundled_example


REPOSITORY = "lukewilliamboswell/roc-pdf"
FIXED_TIME = (2026, 1, 1, 0, 0, 0)
# Archive every public application, including examples without gallery images.
EXAMPLES = tuple(sorted(path.parent.name for path in GALLERY.glob("*/main.roc")))


def readme(tag: str, url: str) -> str:
    return (
        f"# roc-pdf {tag} examples\n\n"
        f"These runnable examples depend on the published package bundle\n{url}\n\n"
        "Run one from its directory, for example:\n\n"
        "    cd examples/tax-invoice && roc main.roc\n\n"
        "Each example writes its PDF to the current directory. `spec.json` records\n"
        "the expected output for roc-automation's nightly compatibility check.\n"
    )


def spec(tag: str, url: str, stdout: dict[str, str]) -> dict:
    return {
        "schema_version": 1,
        "release": tag,
        "dependencies": [url],
        "apps": [
            {
                "path": f"examples/{name}/main.roc",
                "cases": [
                    {
                        "name": "default",
                        "args": [],
                        "stdin": "",
                        "stdout": stdout[name],
                        "stderr": "",
                        "exit_code": 0,
                    }
                ],
            }
            for name in EXAMPLES
        ],
    }


def add(archive: zipfile.ZipFile, name: str, data: bytes | None) -> None:
    info = zipfile.ZipInfo(name, FIXED_TIME)
    info.create_system = 3
    if data is None:
        info.external_attr = (0o40755 << 16) | 0x10
        archive.writestr(info, b"")
    else:
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)


def run(source: Path, url: str, server_url: str, args: list[str], stdin: str) -> subprocess.CompletedProcess:
    text = source.read_text()
    source.write_text(text.replace(url, server_url))
    try:
        # A fresh package cache makes Roc fetch the served bundle, as the
        # shared runner does.
        with tempfile.TemporaryDirectory() as cwd, tempfile.TemporaryDirectory() as cache:
            env = {**os.environ, "XDG_CACHE_HOME": cache}
            return subprocess.run([ROC, str(source), *args], cwd=cwd, env=env, input=stdin.encode(), capture_output=True)
    finally:
        source.write_text(text)


def record(staged: Path, url: str, bundle: Path) -> dict[str, str]:
    stdout = {}
    with BundleServer(bundle) as server:
        for name in EXAMPLES:
            print(f"Recording release example {name}", flush=True)
            result = run(staged / name / "main.roc", url, server.url, [], "")
            if result.returncode != 0:
                raise SystemExit(f"{name}: exit {result.returncode}\n{result.stderr.decode()}")
            stdout[name] = result.stdout.decode()
    return stdout


def build(bundle: Path, tag: str, output_dir: Path) -> Path:
    url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{bundle.name}"
    root = f"roc-pdf-examples-{tag}"
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"{root}.zip"
    with tempfile.TemporaryDirectory() as temporary:
        staged = Path(temporary)
        for name in EXAMPLES:
            bundled_example(GALLERY / name, staged / name, url)
        stdout = record(staged, url, bundle)
        with zipfile.ZipFile(path, "w") as archive:
            add(archive, f"{root}/", None)
            add(archive, f"{root}/README.md", readme(tag, url).encode())
            add(archive, f"{root}/spec.json", (json.dumps(spec(tag, url, stdout), indent=2) + "\n").encode())
            add(archive, f"{root}/examples/", None)
            for directory, dirnames, filenames in os.walk(staged):
                dirnames.sort()
                relative = Path(directory).relative_to(staged)
                if relative != Path("."):
                    add(archive, f"{root}/examples/{relative.as_posix()}/", None)
                for filename in sorted(filenames):
                    member = (relative / filename).as_posix()
                    add(archive, f"{root}/examples/{member}", (Path(directory) / filename).read_bytes())
    return path


def test(archive_path: Path, bundle: Path) -> None:
    with tempfile.TemporaryDirectory() as temporary, BundleServer(bundle) as server:
        extracted = Path(temporary)
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(extracted)
        (root,) = extracted.iterdir()
        plan = json.loads((root / "spec.json").read_text())
        (url,) = plan["dependencies"]
        for app in plan["apps"]:
            for case in app["cases"]:
                result = run(root / app["path"], url, server.url, case["args"], case["stdin"])
                if result.returncode != case["exit_code"] or result.stdout.decode() != case["stdout"]:
                    raise SystemExit(
                        f"{app['path']} {case['name']}: exit {result.returncode}\n"
                        f"stdout: {result.stdout.decode()!r}\nstderr: {result.stderr.decode()}"
                    )
                print(f"PASS {app['path']} {case['name']}", flush=True)
        if server.get_requests == 0:
            raise SystemExit("examples never requested the served package bundle")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-path", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--test-bundle", action="store_true", help="run the archived cases against the local bundle")
    args = parser.parse_args()
    bundle = args.bundle_path.resolve()
    if not bundle.is_file():
        raise SystemExit(f"bundle does not exist: {bundle}")
    path = build(bundle, args.tag, args.output_dir)
    print(f"Built {path}", flush=True)
    if args.test_bundle:
        test(path, bundle)


if __name__ == "__main__":
    main()
