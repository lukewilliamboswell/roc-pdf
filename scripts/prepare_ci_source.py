#!/usr/bin/env python3
"""Bind the verified runner-installed nightly to the clean measured source."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess


def git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=root)


def prepare(root: Path, compiler: Path, runner_temp: Path, expected_sha: str,
            receipt: dict) -> None:
    root = root.resolve()
    compiler = compiler.resolve(strict=True)
    runner_temp = runner_temp.resolve(strict=True)
    revision = git(root, "rev-parse", "HEAD").decode().strip()
    status = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all").decode()
    diff = git(root, "diff", "HEAD", "--binary", "--").decode()
    tracked = [name.decode() for name in git(root, "ls-files", "-z").split(b"\0") if name]
    receipt.update(
        format="roc-pdf-ci-source/1", source_revision=revision,
        requested_source_revision=expected_sha,
        status_before=[entry for entry in status.split("\0") if entry],
        tracked_diff_before=diff,
    )
    receipt["tracked_sha256"] = {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        if (root / name).is_file() else None for name in tracked
    }
    if revision != expected_sha:
        raise ValueError("checkout differs from the requested source revision")
    tag = (root / ".roc-version").read_text().strip()
    if not re.fullmatch(r"nightly-\d{4}-\d{2}-\d{2}-[0-9a-f]{7,40}", tag):
        raise ValueError("invalid pinned nightly tag")
    system = {("Linux", "x86_64"): "linux_x86_64",
              ("Darwin", "arm64"): "macos_apple_silicon"}.get(
                  (platform.system(), platform.machine()))
    expected_name = f"roc_nightly-{system}-{tag.removeprefix('nightly-')}"
    install = compiler.parent
    if (system is None or compiler.name != "roc" or install.name != expected_name
            or not compiler.is_relative_to(runner_temp) or compiler.is_relative_to(root)):
        raise ValueError("installed compiler is not the exact pinned nightly outside the checkout")
    if diff:
        raise ValueError("tracked source changed before measurement")
    if receipt["status_before"]:
        raise ValueError("unexpected checkout state before measurement")
    compiler_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
    version = subprocess.check_output([str(compiler), "version"], text=True).strip()
    receipt["compiler"] = {"original_path": str(compiler), "version": version,
                           "sha256": compiler_hash}
    if version != "Roc compiler version " + tag:
        raise ValueError("installed compiler differs from the pinned nightly")
    receipt["compiler"]["path"] = str(compiler)
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != compiler_hash:
        raise ValueError("compiler bytes changed while recording identity")
    status_after = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all").decode()
    receipt["status_after"] = [entry for entry in status_after.split("\0") if entry]
    receipt["tracked_diff_after"] = git(root, "diff", "HEAD", "--binary", "--").decode()
    if receipt["status_after"] or receipt["tracked_diff_after"]:
        raise ValueError("checkout changed while recording compiler identity")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    receipt: dict = {}
    output = root / ".roc-pdf-tmp" / "ci-source.json"
    output.parent.mkdir(exist_ok=True)
    try:
        installed = Path(os.environ["INSTALLED_ROC"]).resolve(strict=True)
        compiler = shutil.which("roc")
        if compiler is None or Path(compiler).resolve(strict=True) != installed:
            raise ValueError("the verified runner installation must be the Roc on PATH")
        prepare(root, installed, Path(os.environ["RUNNER_TEMP"]),
                os.environ["SOURCE_SHA"], receipt)
        receipt["outcome"] = "passed"
    except Exception as error:
        receipt.update(outcome="failed", error=str(error))
        raise
    finally:
        output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"PASS clean source {receipt['source_revision']}; verified compiler outside checkout")


if __name__ == "__main__":
    main()
