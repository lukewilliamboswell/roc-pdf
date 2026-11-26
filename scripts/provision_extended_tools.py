#!/usr/bin/env python3
"""Explicitly provision the pinned independent PDF test oracles.

Archives are cached under .roc-pdf-tmp/extended-tools/downloads. Verify a
warm cache and install any selected tools without network access using
--offline. Import archive_path for a cache path without file or network I/O,
or require_archive to verify that the cached bytes match their pin.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import multiprocessing
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener
from xml.sax.saxutils import escape
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGET = ROOT / ".roc-pdf-tmp" / "extended-tools"
PINS = ROOT / "assets" / "local-oracles.json"
ARCHIVE_FILENAMES = {
    "mupdf": "mupdf-1.28.2-source.tgz",
    "pdfbox": "pdfbox-app-3.0.8.jar",
    "pdfium": "pdfium-linux-x64-7988.tgz",
    "qpdf": "qpdf-12.3.2-bin-linux-x86_64.zip",
    "verapdf": "verapdf-greenfield-1.30.2-installer.zip",
}
MUPDF_SOURCE_DIR = "mupdf-1.28.2-source"
VERAPDF_INSTALLER = "verapdf-greenfield-1.30.2/verapdf-izpack-installer-1.30.2.jar"
CHUNK_BYTES = 1024 * 1024

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



class ProvisionError(RuntimeError):
    pass


@dataclass(frozen=True)
class ArchivePin:
    url: str
    size: int
    sha256: str
    version: str


class HttpsRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(newurl).scheme != "https":
            raise ProvisionError("oracle source redirected away from HTTPS")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def archive_path(tool: str, target: Path = DEFAULT_TARGET) -> Path:
    """Return the expected local archive path without checking the cache."""
    return target / "downloads" / ARCHIVE_FILENAMES[tool]


def read_pins() -> dict[str, ArchivePin]:
    document = json.loads(PINS.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("schema_version") != 1:
        raise ProvisionError(f"{PINS}: unexpected oracle pin format")
    records = document.get("oracles")
    if not isinstance(records, dict) or records.keys() != ARCHIVE_FILENAMES.keys():
        raise ProvisionError(f"{PINS}: unexpected oracle inventory")
    pins = {}
    for tool, record in records.items():
        if not isinstance(record, dict):
            raise ProvisionError(f"{PINS}: invalid record for {tool}")
        version = record["upstream_revision"]
        url = record["url"]
        size = record["bytes"]
        digest = record["sha256"]
        if not isinstance(url, str):
            raise ProvisionError(f"{PINS}: {tool} must identify an HTTPS release source")
        source = urlsplit(url)
        if source.scheme != "https" or not source.hostname or source.username is not None:
            raise ProvisionError(f"{PINS}: {tool} must identify an HTTPS release source")
        if type(size) is not int or size <= 0 or not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise ProvisionError(f"{PINS}: {tool} must pin its byte length and SHA-256")
        if not isinstance(version, str) or not version:
            raise ProvisionError(f"{PINS}: {tool} must identify its upstream revision")
        pins[tool] = ArchivePin(url, size, digest, version)
    return pins


def verify_archive(path: Path, pin: ArchivePin) -> None:
    if path.stat().st_size != pin.size:
        raise ProvisionError(f"{path}: byte length differs from pin {pin.size}")
    with path.open("rb") as file:
        actual = hashlib.file_digest(file, "sha256").hexdigest()
    if actual != pin.sha256:
        raise ProvisionError(f"{path}: expected SHA-256 {pin.sha256}, got {actual}")


def require_archive(tool: str, target: Path = DEFAULT_TARGET) -> Path:
    """Return a verified cached archive or fail without downloading."""
    path = archive_path(tool, target)
    if not path.is_file():
        raise ProvisionError(f"{path} is missing. Run scripts/provision_extended_tools.py --only {tool}.")
    verify_archive(path, read_pins()[tool])
    return path


def fetch_archive(path: Path, pin: ArchivePin) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{path.name}-", dir=path.parent) as directory:
        candidate = Path(directory) / path.name
        opener = build_opener(HttpsRedirects())
        print(f"Downloading {pin.url}", flush=True)
        with opener.open(pin.url, timeout=60) as source, candidate.open("wb") as target:
            remaining = pin.size
            while chunk := source.read(min(CHUNK_BYTES, remaining + 1)):
                remaining -= len(chunk)
                if remaining < 0:
                    raise ProvisionError(f"{pin.url}: download exceeds pinned length {pin.size}")
                target.write(chunk)
        verify_archive(candidate, pin)
        candidate.replace(path)


def prepare_archive(tool: str, target: Path, pin: ArchivePin, offline: bool) -> Path:
    path = archive_path(tool, target)
    if path.is_file():
        verify_archive(path, pin)
    elif offline:
        raise ProvisionError(f"{path} is missing. Explicitly provision {tool} before using --offline.")
    else:
        fetch_archive(path, pin)
    print(f"Verified {path} sha256={pin.sha256}", flush=True)
    return path


def publish_install(staged: Path, destination: Path, binary: Path) -> Path:
    """Expose the complete installation in one rename, including on retries."""
    if not staged.joinpath(binary.relative_to(destination)).is_file():
        raise ProvisionError(f"Installation did not produce {binary.name}")
    try:
        staged.rename(destination)
    except OSError:
        if not binary.is_file():
            raise
    return binary


def provision_mutool(archive_path: Path, target: Path, jobs: int) -> Path:
    build_root = target / "mupdf"
    destination = build_root / MUPDF_SOURCE_DIR
    mutool = destination / "build" / "release" / "mutool"
    if mutool.is_file():
        return mutool
    if destination.exists():
        raise ProvisionError(f"{destination} is an incomplete MuPDF installation. Move it aside or choose another --target.")
    build_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".mupdf-", dir=build_root) as directory:
        staged = Path(directory) / MUPDF_SOURCE_DIR
        with tarfile.open(archive_path, "r:gz") as archive:
            archive.extractall(directory, filter="data")
        print(f"Building mutool with {jobs} jobs", flush=True)
        subprocess.run(
            ["make", f"-j{jobs}", "HAVE_X11=no", "HAVE_GLUT=no", "tools"],
            cwd=staged, check=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
        )
        return publish_install(staged, destination, mutool)


def provision_verapdf(archive_path: Path, target: Path) -> Path:
    destination = target / "verapdf"
    verapdf = destination / "verapdf"
    if verapdf.is_file():
        return verapdf
    if destination.exists():
        raise ProvisionError(f"{destination} is an incomplete veraPDF installation. Move it aside or choose another --target.")
    with tempfile.TemporaryDirectory(prefix=".verapdf-", dir=target) as directory:
        staging = Path(directory)
        install_dir = staging / "verapdf"
        with zipfile.ZipFile(archive_path) as archive:
            archive.extract(VERAPDF_INSTALLER, staging)
        auto_install = staging / "auto-install.xml"
        auto_install.write_text(AUTO_INSTALL_TEMPLATE.format(install_path=escape(str(install_dir))), encoding="utf-8")
        print("Running the veraPDF automated installer", flush=True)
        subprocess.run(
            ["java", "-jar", str(staging / VERAPDF_INSTALLER), str(auto_install)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
        )
        return publish_install(install_dir, destination, verapdf)


def report(path: Path, argument: str, version: str) -> None:
    result = subprocess.run([path, argument], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    first, *_ = result.stdout.splitlines() or [""]
    if version not in first.split():
        raise ProvisionError(f"{path}: expected version {version}, got {first!r}")
    print(f"{path}: {first}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--only", action="append", choices=tuple(ARCHIVE_FILENAMES), help="select one tool (repeatable)")
    parser.add_argument("--offline", action="store_true", help="require selected archives to be cached and verified")
    parser.add_argument("--jobs", type=int, default=max(1, multiprocessing.cpu_count() - 1))
    parser.add_argument("--skip-mupdf", action="store_true")
    parser.add_argument("--skip-verapdf", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    target = args.target.resolve()
    selected = set(args.only or ARCHIVE_FILENAMES)
    if args.skip_mupdf:
        selected.discard("mupdf")
    if args.skip_verapdf:
        selected.discard("verapdf")
    if not selected:
        parser.error("select at least one oracle")

    try:
        pins = read_pins()
        for tool in ARCHIVE_FILENAMES:
            if tool not in selected:
                continue
            pin = pins[tool]
            archive = prepare_archive(tool, target, pin, args.offline)
            if tool == "mupdf":
                report(provision_mutool(archive, target, args.jobs), "-v", pin.version)
            elif tool == "verapdf":
                report(provision_verapdf(archive, target), "--version", pin.version)
    except (OSError, KeyError, ValueError, URLError, subprocess.CalledProcessError, ProvisionError) as error:
        raise SystemExit(f"Oracle provisioning failed: {error}") from error


if __name__ == "__main__":
    main()
