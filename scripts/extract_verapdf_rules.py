#!/usr/bin/env python3
"""Extract the pinned veraPDF PDF/A-4 rule catalog from vendored bytes.

The conformance ledger maps every rule of the pinned validator's PDF/A-4
profile to exactly one ledger requirement. This script reads that profile
directly out of ``vendor/verapdf/verapdf-greenfield-1.30.2-installer.zip``
(installer zip -> izpack jar -> CLI pack -> ``PDFA-4.xml``) in memory, with
no network access and no installed tool, and writes the normalized rule list
to ``conformance/verapdf-pdfa4-rules.json``.

``--self-test`` re-extracts the catalog and requires the checked-in file to
be byte-identical, so a validator upgrade cannot silently change the rule
set the ledger claims to cover.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import sys
import xml.etree.ElementTree as ElementTree
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "vendor" / "verapdf" / "verapdf-greenfield-1.30.2-installer.zip"
INSTALLER_JAR = "verapdf-greenfield-1.30.2/verapdf-izpack-installer-1.30.2.jar"
CLI_PACK = "resources/packs/pack-veraPDF CLI"
PROFILE = "org/verapdf/pdfa/validation/PDFA-4.xml"
CATALOG = ROOT / "conformance" / "verapdf-pdfa4-rules.json"
VALIDATOR_VERSION = "1.30.2"
PROFILE_SHA256 = "7c1d9450d6f39c957586463354bccbf57a12713caad9a85db83dc6bd4851a07b"
RULE_ID = re.compile(r"6(?:\.[0-9]+)+-[0-9]+\Z")


def fail(message: str) -> None:
    raise SystemExit(message)


def profile_bytes() -> bytes:
    with zipfile.ZipFile(INSTALLER) as installer:
        jar = zipfile.ZipFile(io.BytesIO(installer.read(INSTALLER_JAR)))
    pack = zipfile.ZipFile(io.BytesIO(jar.read(CLI_PACK)))
    return pack.read(PROFILE)


def clause_key(rule_id: str) -> tuple[int, ...]:
    clause, test = rule_id.rsplit("-", 1)
    return (*(int(part) for part in clause.split(".")), int(test))


def build_catalog(profile: bytes) -> dict[str, object]:
    digest = hashlib.sha256(profile).hexdigest()
    if digest != PROFILE_SHA256:
        fail(f"{PROFILE}: expected sha256 {PROFILE_SHA256}, got {digest}")
    root = ElementTree.fromstring(profile)
    if root.get("flavour") != "PDFA_4":
        fail(f"{PROFILE}: expected flavour PDFA_4, got {root.get('flavour')!r}")
    rules: list[dict[str, str]] = []
    for element in root.iter():
        if not element.tag.endswith("}rule"):
            continue
        identifier = next(child for child in element if child.tag.endswith("}id"))
        if identifier.get("specification") != "ISO_19005_4":
            fail(f"{PROFILE}: unexpected specification {identifier.get('specification')!r}")
        rule_id = f"{identifier.get('clause')}-{identifier.get('testNumber')}"
        if RULE_ID.fullmatch(rule_id) is None:
            fail(f"{PROFILE}: malformed rule id {rule_id!r}")
        description = next(child for child in element if child.tag.endswith("}description")).text or ""
        rules.append({
            "description": " ".join(description.split()),
            "id": rule_id,
            "object": element.get("object") or "",
        })
    ids = [rule["id"] for rule in rules]
    if len(ids) != len(set(ids)):
        fail(f"{PROFILE}: duplicate rule ids")
    rules.sort(key=lambda rule: clause_key(rule["id"]))
    return {
        "schema_version": 1,
        "validator": {
            "flavour": "4",
            "name": "veraPDF",
            "profile": PROFILE,
            "profile_sha256": digest,
            "source": INSTALLER.relative_to(ROOT).as_posix(),
            "version": VALIDATOR_VERSION,
        },
        "rules": rules,
    }


def serialize(catalog: dict[str, object]) -> str:
    return json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    expected = serialize(build_catalog(profile_bytes()))
    if args.write:
        CATALOG.write_text(expected, encoding="utf-8")
        print(f"wrote {CATALOG.relative_to(ROOT)}")
        return
    actual = CATALOG.read_text(encoding="utf-8") if CATALOG.is_file() else ""
    if actual != expected:
        fail(f"{CATALOG.relative_to(ROOT)} differs from the pinned veraPDF profile; rerun with --write and review")
    print("PASS veraPDF PDF/A-4 rule catalog")


if __name__ == "__main__":
    sys.exit(main())
