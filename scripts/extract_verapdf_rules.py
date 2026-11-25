#!/usr/bin/env python3
"""Extract explicit veraPDF rule catalogs from the pinned vendored installer.

The PDF/A-4, PDF/UA-2 with ISO/TS 32005, and WTPDF Accessibility catalogs
are executable inputs for checking the validator rule inventory. The archive
and embedded profiles can be inspected offline without installing Java.

``--self-test`` re-extracts each catalog and checks byte identity.
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
from dataclasses import dataclass
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
ACCESSIBILITY_RULE_ID = re.compile(r"(?:[0-9]+(?:\.[0-9]+)*|Table 5\. (?:[A-Za-z0-9]+-)+[A-Za-z0-9]+)-[0-9]+\Z")


@dataclass(frozen=True)
class AccessibilityProfile:
    flavour: str
    xml_flavour: str
    file: str
    sha256: str
    specification: str
    name: str
    catalog: Path


ACCESSIBILITY_PROFILES = {
    "ua2": AccessibilityProfile(
        "ua2",
        "PDFUA_2",
        "PDFUA-2-ISO32005.xml",
        "65ae5240f1c19fdbba78992908ffbb7e3c1061a485220bf6024c74eccf397e1f",
        "ISO_14289_2",
        "PDF/UA-2 + Tagged PDF validation profile",
        ROOT / "conformance" / "verapdf-pdfua2-rules.json",
    ),
    "wt1a": AccessibilityProfile(
        "wt1a",
        "WTPDF_1_0_ACCESSIBILITY",
        "WTPDF-1-0-Accessibility.xml",
        "484f009d8ca440f4ecb6811ff5a8e6df0daeec767b269084951982d19de2454f",
        "WTPDF_1_0",
        "WTPDF 1.0 Accessibility validation profile",
        ROOT / "conformance" / "verapdf-wtpdf-accessibility-rules.json",
    ),
}


def fail(message: str) -> None:
    raise SystemExit(message)


def profile_bytes(path: str = PROFILE) -> bytes:
    with zipfile.ZipFile(INSTALLER) as installer:
        with zipfile.ZipFile(io.BytesIO(installer.read(INSTALLER_JAR))) as jar:
            with zipfile.ZipFile(io.BytesIO(jar.read(CLI_PACK))) as pack:
                return pack.read(path)


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


def accessibility_catalog(profile: AccessibilityProfile) -> dict[str, object]:
    path = f"org/verapdf/pdfa/validation/{profile.file}"
    xml = profile_bytes(path)
    digest = hashlib.sha256(xml).hexdigest()
    if digest != profile.sha256:
        fail(f"{path}: expected sha256 {profile.sha256}, got {digest}")

    root = ElementTree.fromstring(xml)
    namespace = {"v": "http://www.verapdf.org/ValidationProfile"}
    if root.get("flavour") != profile.xml_flavour or root.findtext("v:details/v:name", namespaces=namespace) != profile.name:
        fail(f"{path}: profile identity differs")
    rules: list[dict[str, str]] = []
    for element in root.findall("v:rules/v:rule", namespace):
        identifier = element.find("v:id", namespace)
        specification = identifier.get("specification")
        rule_id = f"{identifier.get('clause')}-{identifier.get('testNumber')}"
        if specification not in {profile.specification, "ISO_32005"} or ACCESSIBILITY_RULE_ID.fullmatch(rule_id) is None:
            fail(f"{path}: unexpected rule {specification} {rule_id}")
        rules.append({
            "id": rule_id,
            "specification": specification,
            "object": element.attrib["object"],
            "description": " ".join(element.findtext("v:description", namespaces=namespace).split()),
        })
    ids = {rule["id"] for rule in rules}
    if len(ids) != len(rules) or not ids:
        fail(f"{path}: empty catalog or duplicate rule IDs")
    rules.sort(key=lambda rule: (rule["specification"], rule["id"]))
    return {
        "schema_version": 1,
        "validator": {
            "flavour": profile.flavour,
            "name": "veraPDF",
            "profile": path,
            "profile_sha256": digest,
            "source": INSTALLER.relative_to(ROOT).as_posix(),
            "version": VALIDATOR_VERSION,
        },
        "rules": rules,
    }


def serialize_accessibility(catalog: dict[str, object]) -> str:
    # Keep each rule on one line so the containment inventory is easy to diff.
    remaining = {key: value for key, value in catalog.items() if key != "rules"}
    rules = ",\n".join(
        "    " + json.dumps(rule, sort_keys=True, ensure_ascii=False)
        for rule in catalog["rules"]
    )
    return serialize(remaining).removesuffix("\n}\n") + ',\n  "rules": [\n' + rules + "\n  ]\n}\n"


def serialize(catalog: dict[str, object]) -> str:
    return json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    catalogs = [(CATALOG, serialize(build_catalog(profile_bytes())))]
    catalogs.extend(
        (profile.catalog, serialize_accessibility(accessibility_catalog(profile)))
        for profile in ACCESSIBILITY_PROFILES.values()
    )
    for path, expected in catalogs:
        if args.write:
            path.write_text(expected, encoding="utf-8")
            print(f"wrote {path.relative_to(ROOT)}")
            continue
        actual = path.read_text(encoding="utf-8") if path.is_file() else ""
        if actual != expected:
            fail(f"{path.relative_to(ROOT)} differs from the pinned veraPDF profile; rerun with --write and review")
        print(f"PASS {path.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
