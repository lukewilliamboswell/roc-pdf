#!/usr/bin/env python3
"""Prove a breaking version boundary or compare APIs within that boundary."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
U64_MAX = (1 << 64) - 1
COMPONENT = r"(?:0|[1-9][0-9]*)"
VERSION = re.compile(rf"({COMPONENT})\.({COMPONENT})\.({COMPONENT})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")


def parse_version(value: str, *, final: bool = False) -> tuple[int, int, int]:
    match = VERSION.fullmatch(value)
    if match is None:
        raise ValueError("versions must contain three canonical numeric components and an optional prerelease")
    prerelease = match[4]
    if final and prerelease is not None:
        raise ValueError("the previous release must be final")
    if prerelease is not None and any(
        part.isascii() and part.isdecimal() and len(part) > 1 and part.startswith("0")
        for part in prerelease.split(".")
    ):
        raise ValueError("numeric prerelease identifiers must not contain leading zeroes")
    parts = tuple(int(match[index]) for index in (1, 2, 3))
    if any(part > U64_MAX for part in parts):
        raise ValueError("version components must fit U64")
    if parts == (0, 0, 0):
        raise ValueError("0.0.0 is reserved and cannot be published")
    return parts


def breaking_suffices(requested: str, previous: str) -> bool:
    next_major, next_minor, next_patch = parse_version(requested)
    old_major, old_minor, old_patch = parse_version(previous, final=True)
    if (next_major, next_minor, next_patch) <= (old_major, old_minor, old_patch):
        raise ValueError("the requested release must move forward from the latest final release")
    return next_major > old_major or (next_major == old_major == 0 and next_minor > old_minor)


def check_version(requested: str, previous: str, previous_url: str, *, run=subprocess.run) -> None:
    breaking = breaking_suffices(requested, previous)
    parsed = urlsplit(previous_url)
    prefix = f"/lukewilliamboswell/roc-pdf/releases/download/{previous}/"
    filename = parsed.path.removeprefix(prefix)
    if (parsed.scheme != "https" or parsed.netloc != "github.com" or parsed.query or parsed.fragment
            or not parsed.path.startswith(prefix)
            or not re.fullmatch(r"[A-Za-z0-9_-]+\.tar\.zst", filename)):
        raise ValueError("the previous bundle URL must identify the selected final release")
    if breaking:
        print(f"PASS {previous} -> {requested}: the breaking boundary satisfies every API-change lower bound")
        return
    run([os.environ.get("ROC", "roc"), "bump", "--old", previous_url,
         "--expect", requested.split("-", 1)[0], "package/main.roc"], check=True, cwd=ROOT)


def self_test() -> None:
    def url(version: str) -> str:
        return f"https://github.com/lukewilliamboswell/roc-pdf/releases/download/{version}/hash.tar.zst"

    calls = []
    def record(*args, **kwargs):
        calls.append((args, kwargs))

    for requested, previous in [("0.3.0", "0.2.0"), ("0.3.0-rc1", "0.2.0"),
                                ("1.0.0", "0.9.9"), ("2.0.0", "1.99.99")]:
        check_version(requested, previous, url(previous), run=record)
    assert not calls, "crossing a breaking boundary must not compile the old bundle"
    for requested, previous in [("0.2.1", "0.2.0"), ("1.2.0", "1.1.0"),
                                ("1.1.1-rc.1", "1.1.0")]:
        check_version(requested, previous, url(previous), run=record)
        args, kwargs = calls[-1]
        assert args[0][1:] == ["bump", "--old", url(previous), "--expect",
                              requested.split("-", 1)[0], "package/main.roc"]
        assert kwargs["check"] is True and kwargs["cwd"] == ROOT
    invalid = ["0.0.0", "0.0.0-rc1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03",
               "1.2.3-", "1.2.3-rc..1", "1.2.3-01", "1.2.3+build", "1.2.3 ",
               "١.2.3", "18446744073709551616.0.0", "0.18446744073709551616.0",
               "0.3.18446744073709551616"]
    for requested, previous in ([(value, "0.2.0") for value in invalid]
                               + [("0.3.0", value) for value in invalid]
                               + [("0.3.0", "0.2.0-rc1"), ("0.2.0", "0.2.0"),
                                  ("0.1.9", "0.2.0"), ("0.99.0", "1.0.0"),
                                  ("1.1.9", "1.2.0")]):
        before = len(calls)
        try:
            check_version(requested, previous, url(previous), run=record)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid version transition accepted: {previous} -> {requested}")
        assert len(calls) == before, "invalid metadata must fail before compiler execution"
    for previous_url in [url("0.1.0"), url("0.2.0") + "?other=1", url("0.2.0").replace("https:", "http:")]:
        try:
            check_version("0.3.0", "0.2.0", previous_url, run=record)
        except ValueError:
            pass
        else:
            raise AssertionError("mismatched bundle identity accepted")
    def failed(*args, **kwargs):
        raise subprocess.CalledProcessError(1, args[0])
    try:
        check_version("0.2.1", "0.2.0", url("0.2.0"), run=failed)
    except subprocess.CalledProcessError:
        pass
    else:
        raise AssertionError("a failed API comparison must remain a failure")
    print("PASS release version proofs: breaking boundaries, mandatory API checks and invalid metadata")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--requested")
    parser.add_argument("--previous")
    parser.add_argument("--previous-url")
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        self_test()
    elif not all((options.requested, options.previous, options.previous_url)):
        parser.error("--requested, --previous and --previous-url are required")
    else:
        check_version(options.requested, options.previous, options.previous_url)


if __name__ == "__main__":
    main()
