#!/usr/bin/env python3
"""Admit an unchanged published package for ordinary CI; keep release checks strict."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import selectors
import signal
import time

from check_release_version import check_version

REPOSITORY = "lukewilliamboswell/roc-pdf"
MAX_BUNDLE_BYTES = 16 * 1024 * 1024
MAX_METADATA_BYTES = 1024 * 1024
MAX_STDERR_BYTES = 8192


def bounded_api(command, maximum, seconds=60):
    environment = os.environ.copy()
    environment.pop("GH_DEBUG", None)
    process = subprocess.Popen(command, env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    selector = selectors.DefaultSelector()
    streams = {"stdout": bytearray(), "stderr": bytearray()}
    deadline, reason = time.monotonic() + seconds, "exited"
    try:
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                reason = "timeout"
                break
            for key, _ in selector.select(remaining):
                limit = maximum if key.data == "stdout" else MAX_STDERR_BYTES
                chunk = os.read(key.fileobj.fileno(), min(65536, max(1, limit - len(streams[key.data]) + 1)))
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                streams[key.data].extend(chunk)
                if len(streams[key.data]) > limit:
                    reason = key.data + "-limit"
                    break
            if reason != "exited":
                break
        if reason == "exited":
            try:
                process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                reason = "timeout"
    finally:
        # Own the group signal here only. First signal/reap errors remain hard
        # failures; normal exits must also clean descendants with closed pipes.
        try:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
        finally:
            selector.close()
            process.stdout.close()
            process.stderr.close()
    return process.returncode, bytes(streams["stdout"]), bytes(streams["stderr"]), reason


def api_request(endpoint: str, maximum: int, *, binary=False) -> bytes:
    command = ["gh", "api", "--hostname", "github.com", "--method", "GET", endpoint]
    if binary:
        command += ["--header", "Accept: application/octet-stream"]
    code, body, stderr, reason = bounded_api(command, maximum)
    if code != 0 or reason != "exited":
        # Do not echo authentication or arbitrary child diagnostics.
        raise ValueError(f"GitHub API failed: reason={reason} exit={code} stderr_bytes={len(stderr)}")
    return body


def fetch_latest() -> dict:
    return json.loads(api_request(f"repos/{REPOSITORY}/releases/latest", MAX_METADATA_BYTES))


def fetch_asset(asset_id: int, size: int) -> bytes:
    if type(size) is not int or not 0 < size <= MAX_BUNDLE_BYTES:
        raise ValueError("published package length is out of bounds")
    body = api_request(f"repos/{REPOSITORY}/releases/assets/{asset_id}", size, binary=True)
    if len(body) != size:
        raise ValueError("downloaded published bundle has the wrong length")
    return body


def check_ci_release(requested: str, explicit_release: str, latest: dict, candidate: Path,
                     *, strict=check_version, fetch=fetch_asset) -> None:
    previous = latest["tag_name"]
    assets = [asset for asset in latest["assets"] if asset["name"].endswith(".tar.zst")]
    if len(assets) != 1:
        raise ValueError("the selected final release must have exactly one package bundle")
    asset = assets[0]
    url = asset["browser_download_url"]
    if explicit_release and explicit_release != requested:
        raise ValueError("the explicit release input differs from the checked version")
    if explicit_release or requested != previous:
        strict(requested, previous, url)
        return

    # Equality is an ordinary-CI identity proof, never release eligibility.
    if latest.get("immutable") is not True or latest.get("draft") is not False or latest.get("prerelease") is not False:
        raise ValueError("ordinary equality requires an immutable final published release")
    # Validate canonical version metadata and release URL without relaxing the
    # original strict checker's rejection of non-forward release versions.
    from check_release_version import parse_version
    parse_version(previous, final=True)
    name, size, identity = asset["name"], asset["size"], asset["digest"]
    if not re.fullmatch(r"[A-Za-z0-9_-]+\.tar\.zst", name):
        raise ValueError("invalid published package name")
    if url != f"https://github.com/{REPOSITORY}/releases/download/{previous}/{name}":
        raise ValueError("the bundle URL does not identify the selected release")
    if type(asset["id"]) is not int or asset["id"] <= 0 or asset.get("state") != "uploaded":
        raise ValueError("invalid published package asset identity")
    if type(size) is not int or not 0 < size <= MAX_BUNDLE_BYTES or not isinstance(identity, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", identity):
        raise ValueError("invalid published package length or digest")
    if candidate.is_symlink() or not candidate.is_file() or candidate.name != name:
        raise ValueError("fresh candidate must be the named regular package file")
    if candidate.stat().st_size != size:
        raise ValueError("fresh candidate length differs from the published package")
    with candidate.open("rb") as fresh:
        candidate_bytes = fresh.read(size + 1)
    if len(candidate_bytes) != size or "sha256:" + hashlib.sha256(candidate_bytes).hexdigest() != identity:
        raise ValueError("fresh candidate bytes differ from the immutable published package")
    released_bytes = fetch(asset["id"], size)
    if len(released_bytes) != size or "sha256:" + hashlib.sha256(released_bytes).hexdigest() != identity:
        raise ValueError("downloaded published package differs from its asset identity")
    if candidate_bytes != released_bytes:
        raise ValueError("fresh and published package bytes differ")
    print(f"PASS ordinary CI: complete fresh bundle bytes equal immutable {previous} asset {asset['id']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--requested", required=True)
    parser.add_argument("--explicit-release", default="")
    parser.add_argument("--bundle", type=Path, required=True)
    options = parser.parse_args()
    check_ci_release(options.requested, options.explicit_release,
                     fetch_latest(), options.bundle)


if __name__ == "__main__":
    main()
