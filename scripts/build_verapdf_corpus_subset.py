#!/usr/bin/env python3
"""Build the vendored veraPDF PDF/A-4 corpus subset from the pinned upstream archive.

The upstream veraPDF corpus is CC BY 4.0 and is pinned to the commit its
1.30 validation profiles were released against. The full archive is larger
than a single repository blob may be, so the repository vendors only its
``PDF_A-4`` tree plus the upstream README (which carries the license), repacked
deterministically: sorted entries, fixed ownership and timestamps, and a
zero-mtime gzip header. ``conformance/verapdf-corpus-pdfa4.json`` records
every retained file's SHA-256, so the subset can be checked against any copy
of the pinned upstream archive.

    build_verapdf_corpus_subset.py --archive UPSTREAM.tar.gz   # write
    build_verapdf_corpus_subset.py --archive UPSTREAM.tar.gz --check
    build_verapdf_corpus_subset.py --self-test                  # manifest vs vendored subset
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_COMMIT = "49de56cd987929932c9e4fbbbe67d052bf44ef83"
UPSTREAM_URL = f"https://github.com/veraPDF/veraPDF-corpus/archive/{UPSTREAM_COMMIT}.tar.gz"
UPSTREAM_SHA256 = "5c1a138e0fd89fafa51d03a23a1a0bf0a9bcb028430e1d5dd125364e19b87f57"
PREFIX = f"veraPDF-corpus-{UPSTREAM_COMMIT}/"
RETAINED = ("PDF_A-4/", "README.md")
SUBSET = ROOT / "vendor" / "verapdf-corpus" / "verapdf-corpus-pdfa4-49de56c.tgz"
MANIFEST = ROOT / "conformance" / "verapdf-corpus-pdfa4.json"


def fail(message: str) -> None:
    raise SystemExit(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def retained_files(archive: Path) -> list[tuple[str, bytes]]:
    data = archive.read_bytes()
    if sha256(data) != UPSTREAM_SHA256:
        fail(f"{archive}: expected upstream sha256 {UPSTREAM_SHA256}")
    files: list[tuple[str, bytes]] = []
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as upstream:
        for member in upstream.getmembers():
            if not member.isfile() or not member.name.startswith(PREFIX):
                continue
            relative = member.name[len(PREFIX):]
            if relative == RETAINED[1] or relative.startswith(RETAINED[0]):
                extracted = upstream.extractfile(member)
                if extracted is None:
                    fail(f"cannot read {member.name}")
                files.append((relative, extracted.read()))
    files.sort()
    if not any(name.startswith(RETAINED[0]) for name, _ in files):
        fail("upstream archive has no PDF_A-4 tree")
    return files


def pack(files: list[tuple[str, bytes]]) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as subset:
        for name, data in files:
            info = tarfile.TarInfo(f"verapdf-corpus-pdfa4/{name}")
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            subset.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0, compresslevel=9) as stream:
        stream.write(raw.getvalue())
    return compressed.getvalue()


def manifest(files: list[tuple[str, bytes]], subset: bytes) -> str:
    document = {
        "schema_version": 1,
        "upstream": {"commit": UPSTREAM_COMMIT, "sha256": UPSTREAM_SHA256, "url": UPSTREAM_URL, "license": "CC-BY-4.0"},
        "subset": {"path": SUBSET.relative_to(ROOT).as_posix(), "sha256": sha256(subset), "retained": list(RETAINED)},
        "files": [{"path": name, "sha256": sha256(data)} for name, data in files],
    }
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


def vendored_files() -> list[tuple[str, bytes]]:
    files: list[tuple[str, bytes]] = []
    with tarfile.open(SUBSET, mode="r:gz") as subset:
        for member in subset.getmembers():
            if member.isfile():
                extracted = subset.extractfile(member)
                if extracted is None:
                    fail(f"cannot read {member.name}")
                files.append((member.name.removeprefix("verapdf-corpus-pdfa4/"), extracted.read()))
    return sorted(files)


def self_test() -> None:
    recorded = json.loads(MANIFEST.read_text(encoding="utf-8"))
    subset_bytes = SUBSET.read_bytes()
    if sha256(subset_bytes) != recorded["subset"]["sha256"]:
        fail("vendored corpus subset digest does not match its manifest")
    files = vendored_files()
    if [{"path": name, "sha256": sha256(data)} for name, data in files] != recorded["files"]:
        fail("vendored corpus subset contents do not match the per-file manifest")
    if pack(files) != subset_bytes:
        fail("vendored corpus subset is not the deterministic repack of its files")
    pdfs = sum(1 for name, _ in files if name.endswith(".pdf"))
    print(f"PASS veraPDF PDF/A-4 corpus subset: {len(files)} files ({pdfs} PDFs) match the pinned manifest")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.archive is None:
        parser.error("--archive UPSTREAM.tar.gz is required unless --self-test")
    files = retained_files(args.archive)
    subset = pack(files)
    text = manifest(files, subset)
    if args.check:
        if SUBSET.read_bytes() != subset or MANIFEST.read_text(encoding="utf-8") != text:
            fail("vendored corpus subset differs from the pinned upstream archive")
        print("PASS vendored corpus subset reproduces from the pinned upstream archive")
        return
    SUBSET.parent.mkdir(parents=True, exist_ok=True)
    SUBSET.write_bytes(subset)
    MANIFEST.write_text(text, encoding="utf-8")
    print(f"wrote {SUBSET.relative_to(ROOT)} ({len(subset)} bytes) and {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
