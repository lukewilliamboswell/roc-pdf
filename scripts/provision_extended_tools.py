#!/usr/bin/env python3
"""Provision the vendored extended test oracles from their pinned bytes.

The repository retains MuPDF and veraPDF as exact upstream release artifacts
under ``vendor/`` (see each ``NOTICE.md`` and ``assets/provenance.json``).
This script turns those pinned bytes into runnable tools without any network
access:

- ``mutool`` is compiled from ``vendor/mupdf/mupdf-1.28.2-source.tgz``;
- veraPDF greenfield is laid down from
  ``vendor/verapdf/verapdf-greenfield-1.30.2-installer.zip`` through its
  izpack automated installer.

Every artifact's SHA-256 is verified against ``assets/provenance.json``
before it is used, matching the vendored-tool contract. The default target
directory is ``.roc-pdf-tmp/extended-tools`` (ignored by git); pass
``--target`` to choose another location. The resulting binaries are the ones
to hand to ``check_gate4_form_renderers.py --mutool`` and to future veraPDF
evidence lanes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "assets" / "provenance.json"
MUPDF_ARCHIVE = ROOT / "vendor" / "mupdf" / "mupdf-1.28.2-source.tgz"
MUPDF_SOURCE_DIR = "mupdf-1.28.2-source"
VERAPDF_ARCHIVE = ROOT / "vendor" / "verapdf" / "verapdf-greenfield-1.30.2-installer.zip"
VERAPDF_INSTALLER = "verapdf-greenfield-1.30.2/verapdf-izpack-installer-1.30.2.jar"
DEFAULT_TARGET = ROOT / ".roc-pdf-tmp" / "extended-tools"

AUTO_INSTALL_TEMPLATE = """<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<AutomatedInstallation langpack="eng">
    <com.izforge.izpack.panels.htmlhello.HTMLHelloPanel id="welcome"/>
    <com.izforge.izpack.panels.target.TargetPanel id="install_dir">
        <installpath>{install_path}</installpath>
    </com.izforge.izpack.panels.target.TargetPanel>
    <com.izforge.izpack.panels.packs.PacksPanel id="sdk_pack_select">
        <pack index="0" name="veraPDF GUI" selected="true"/>
        <pack index="1" name="veraPDF Mac and *nix Scripts" selected="true"/>
        <pack index="2" name="veraPDF Corpus and Validation model" selected="false"/>
        <pack index="3" name="veraPDF Documentation" selected="false"/>
        <pack index="4" name="veraPDF Sample Plugins" selected="false"/>
    </com.izforge.izpack.panels.packs.PacksPanel>
    <com.izforge.izpack.panels.install.InstallPanel id="install"/>
    <com.izforge.izpack.panels.finish.FinishPanel id="finish"/>
</AutomatedInstallation>
"""


def fail(message: str) -> None:
    raise SystemExit(message)


def pinned_sha256(path: Path) -> str:
    manifest = json.loads(PROVENANCE.read_text(encoding="utf-8"))
    relative = path.relative_to(ROOT).as_posix()
    for asset in manifest["assets"]:
        if asset["path"] == relative:
            return asset["sha256"]
    fail(f"{relative} has no provenance entry")
    raise AssertionError


def verify_digest(path: Path) -> None:
    if not path.is_file():
        fail(f"vendored artifact does not exist: {path}")
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(chunk)
    actual = hasher.hexdigest()
    expected = pinned_sha256(path)
    if actual != expected:
        fail(f"{path} digest mismatch: expected {expected}, got {actual}")
    print(f"verified {path.relative_to(ROOT)} sha256={actual}")


def provision_mutool(target: Path, jobs: int) -> Path:
    verify_digest(MUPDF_ARCHIVE)
    build_root = target / "mupdf"
    mutool = build_root / MUPDF_SOURCE_DIR / "build" / "release" / "mutool"
    if mutool.is_file():
        print(f"mutool already provisioned at {mutool}")
        return mutool
    build_root.mkdir(parents=True, exist_ok=True)
    print("extracting MuPDF source ...")
    with tarfile.open(MUPDF_ARCHIVE, "r:gz") as archive:
        archive.extractall(build_root, filter="data")
    print(f"building mutool with {jobs} jobs (a few minutes) ...")
    subprocess.run(
        ["make", f"-j{jobs}", "HAVE_X11=no", "HAVE_GLUT=no", "tools"],
        cwd=build_root / MUPDF_SOURCE_DIR,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    if not mutool.is_file():
        fail("mutool build completed without producing the binary")
    return mutool


def provision_verapdf(target: Path) -> Path:
    verify_digest(VERAPDF_ARCHIVE)
    install_dir = target / "verapdf"
    verapdf = install_dir / "verapdf"
    if verapdf.is_file():
        print(f"veraPDF already provisioned at {verapdf}")
        return verapdf
    staging = target / "verapdf-staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with zipfile.ZipFile(VERAPDF_ARCHIVE) as archive:
        archive.extract(VERAPDF_INSTALLER, staging)
    auto_install = staging / "auto-install.xml"
    auto_install.write_text(AUTO_INSTALL_TEMPLATE.format(install_path=install_dir), encoding="utf-8")
    print("running the veraPDF automated installer ...")
    subprocess.run(
        ["java", "-jar", str(staging / VERAPDF_INSTALLER), str(auto_install)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    shutil.rmtree(staging)
    if not verapdf.is_file():
        fail("veraPDF installation completed without producing the launcher")
    return verapdf


def report(tool: str, path: Path, arguments: list[str]) -> None:
    result = subprocess.run([str(path), *arguments], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    first_line = result.stdout.decode("utf-8", errors="replace").splitlines()[0]
    print(f"{tool}: {path}")
    print(f"    {first_line}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--jobs", type=int, default=max(1, multiprocessing.cpu_count() - 1))
    parser.add_argument("--skip-mupdf", action="store_true")
    parser.add_argument("--skip-verapdf", action="store_true")
    args = parser.parse_args()
    target = args.target.resolve()
    target.mkdir(parents=True, exist_ok=True)
    if not args.skip_mupdf:
        mutool = provision_mutool(target, args.jobs)
        report("mutool", mutool, ["-v"])
    if not args.skip_verapdf:
        verapdf = provision_verapdf(target)
        report("veraPDF", verapdf, ["--version"])
    print("extended tools provisioned from vendored pinned bytes")


if __name__ == "__main__":
    sys.exit(main())
