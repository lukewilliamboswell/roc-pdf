#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import re
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
CONFORMANCE = ROOT / "conformance"
BASELINE_PATH = CONFORMANCE / "normative-baseline.json"
MATRIX_PATH = CONFORMANCE / "capability-matrix.json"
LEDGER_PATH = CONFORMANCE / "ledger.json"
DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}\Z")
SOURCE_ID = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
RULE_ID = re.compile(r"ROC-PDF-[A-Z0-9]+(?:-[A-Z0-9]+)*\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")

CAPABILITIES = {
    "Pdf20",
    "PdfA4f",
    "PdfUa2",
    "StaticPdfA4",
    "WtpdfAccessibility",
    "WtpdfReuse",
}
PROFILES = {
    "AccessibleArchive": ["Pdf20", "PdfUa2", "StaticPdfA4"],
    "Archive": ["Pdf20", "StaticPdfA4"],
    "Standard": ["Pdf20"],
}
REQUIRED_SOURCES = {
    "bcp47-rfc5646",
    "deflate-rfc1951",
    "icc-1-2001-04",
    "iso-14289-2-2024",
    "iso-16684-1-2019",
    "iso-19005-4-2020",
    "iso-32000-2-2020-ec3",
    "iso-ts-32005-2023",
    "jpeg-10918-1-1994",
    "opentype-1-9-1",
    "pdf-issues-ec3",
    "uax14-r55",
    "uax29-r47",
    "uax9-r51",
    "ucd-17-0-0",
    "unicode-17-0-0",
    "wtpdf-1-0-0",
    "xml-1-0-fifth-edition",
}


class ContractError(ValueError):
    pass


def fail(path: str, message: str) -> NoReturn:
    raise ContractError(f"{path}: {message}")


def load(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"{path}: {error}") from error


def require_object(value: object, path: str, keys: set[str]) -> dict[str, object]:
    if not isinstance(value, dict):
        fail(path, "must be an object")
    actual = set(value)
    if actual != keys:
        fail(path, f"keys must be exactly {sorted(keys)}; got {sorted(actual)}")
    return value


def require_string(value: object, path: str) -> str:
    if not isinstance(value, str) or not value:
        fail(path, "must be a non-empty string")
    return value


def require_string_list(value: object, path: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        fail(path, "must be a list of non-empty strings")
    if value != sorted(set(value)):
        fail(path, "must be sorted and unique")
    return value


def require_version(document: dict[str, object], path: str) -> None:
    if document["schema_version"] != 1:
        fail(f"{path}.schema_version", "must be 1")


def validate_baseline(value: object) -> set[str]:
    document = require_object(value, "normative-baseline", {"schema_version", "reviewed_on", "sources"})
    require_version(document, "normative-baseline")
    reviewed_on = require_string(document["reviewed_on"], "normative-baseline.reviewed_on")
    if DATE.fullmatch(reviewed_on) is None:
        fail("normative-baseline.reviewed_on", "must be YYYY-MM-DD")

    sources = document["sources"]
    if not isinstance(sources, list) or not sources:
        fail("normative-baseline.sources", "must be a non-empty list")

    ids: list[str] = []
    for index, raw_source in enumerate(sources):
        path = f"normative-baseline.sources[{index}]"
        source = require_object(
            raw_source,
            path,
            {"id", "title", "revision", "url", "retrieved_on", "pin"},
        )
        source_id = require_string(source["id"], f"{path}.id")
        if SOURCE_ID.fullmatch(source_id) is None:
            fail(f"{path}.id", "must be a lowercase kebab-case identifier")
        ids.append(source_id)
        require_string(source["title"], f"{path}.title")
        require_string(source["revision"], f"{path}.revision")
        url = require_string(source["url"], f"{path}.url")
        if not url.startswith("https://"):
            fail(f"{path}.url", "must use https")
        retrieved_on = require_string(source["retrieved_on"], f"{path}.retrieved_on")
        if DATE.fullmatch(retrieved_on) is None or retrieved_on > reviewed_on:
            fail(f"{path}.retrieved_on", "must be a valid date no later than reviewed_on")

        pin = require_object(source["pin"], f"{path}.pin", {"kind", "value"})
        kind = pin["kind"]
        pin_value = require_string(pin["value"], f"{path}.pin.value")
        if kind not in {"publication_identifier", "sha256"}:
            fail(f"{path}.pin.kind", "must be publication_identifier or sha256")
        if kind == "sha256" and SHA256.fullmatch(pin_value) is None:
            fail(f"{path}.pin.value", "must be 64 lowercase hexadecimal digits")

    if ids != sorted(set(ids)):
        fail("normative-baseline.sources", "source ids must be sorted and unique")
    if set(ids) != REQUIRED_SOURCES:
        fail("normative-baseline.sources", "must contain the complete Gate 0 source set")

    by_id = {source["id"]: source for source in sources}
    errata = by_id["pdf-issues-ec3"]
    if errata["revision"] != "8766b0a5f9929be3f29b80981ecc8e671e96151c":
        fail("normative-baseline.pdf-issues-ec3.revision", "unexpected EC3 source revision")
    if errata["pin"] != {
        "kind": "sha256",
        "value": "ebb851cc43f299f4ad0852842802cf75a14a2546cb52f1c771aba0f77dbdea78",
    }:
        fail("normative-baseline.pdf-issues-ec3.pin", "unexpected EC3 archive digest")
    return set(ids)


def validate_matrix(value: object) -> None:
    document = require_object(value, "capability-matrix", {"schema_version", "capabilities", "profiles"})
    require_version(document, "capability-matrix")

    raw_capabilities = document["capabilities"]
    if not isinstance(raw_capabilities, list):
        fail("capability-matrix.capabilities", "must be a list")
    capability_ids: list[str] = []
    dependencies: dict[str, list[str]] = {}
    for index, raw_capability in enumerate(raw_capabilities):
        path = f"capability-matrix.capabilities[{index}]"
        capability = require_object(raw_capability, path, {"id", "requires", "availability"})
        capability_id = require_string(capability["id"], f"{path}.id")
        capability_ids.append(capability_id)
        dependencies[capability_id] = require_string_list(capability["requires"], f"{path}.requires")
        if capability["availability"] not in {"defined_only", "future"}:
            fail(f"{path}.availability", "Gate 0 must not claim executable availability")

    if capability_ids != sorted(CAPABILITIES):
        fail("capability-matrix.capabilities", "must contain every capability sorted by id")
    for capability_id, requirements in dependencies.items():
        unknown = set(requirements) - CAPABILITIES
        if unknown:
            fail(f"capability-matrix.{capability_id}.requires", f"unknown capabilities: {sorted(unknown)}")
        if capability_id in requirements:
            fail(f"capability-matrix.{capability_id}.requires", "must not depend on itself")

    raw_profiles = document["profiles"]
    if not isinstance(raw_profiles, list):
        fail("capability-matrix.profiles", "must be a list")
    actual_profiles: dict[str, list[str]] = {}
    for index, raw_profile in enumerate(raw_profiles):
        path = f"capability-matrix.profiles[{index}]"
        profile = require_object(raw_profile, path, {"id", "claims"})
        profile_id = require_string(profile["id"], f"{path}.id")
        if profile_id in actual_profiles:
            fail(f"{path}.id", "must be unique")
        actual_profiles[profile_id] = require_string_list(profile["claims"], f"{path}.claims")
    if actual_profiles != PROFILES:
        fail("capability-matrix.profiles", f"must equal the facade mapping {PROFILES}")


def validate_ledger(value: object, source_ids: set[str]) -> None:
    document = require_object(value, "ledger", {"schema_version", "requirements"})
    require_version(document, "ledger")
    raw_requirements = document["requirements"]
    if not isinstance(raw_requirements, list) or not raw_requirements:
        fail("ledger.requirements", "must be a non-empty list")

    ids: list[str] = []
    for index, raw_requirement in enumerate(raw_requirements):
        path = f"ledger.requirements[{index}]"
        requirement = require_object(
            raw_requirement,
            path,
            {
                "id",
                "summary",
                "source_ids",
                "references",
                "capabilities",
                "implementation",
                "machine_verification",
                "human_verification",
                "positive_scenarios",
                "negative_scenarios",
                "external_rule_ids",
            },
        )
        rule_id = require_string(requirement["id"], f"{path}.id")
        if RULE_ID.fullmatch(rule_id) is None:
            fail(f"{path}.id", "must be a stable ROC-PDF uppercase identifier")
        ids.append(rule_id)
        require_string(requirement["summary"], f"{path}.summary")
        requirement_sources = require_string_list(requirement["source_ids"], f"{path}.source_ids")
        unknown_sources = set(requirement_sources) - source_ids
        if unknown_sources:
            fail(f"{path}.source_ids", f"unknown sources: {sorted(unknown_sources)}")
        require_string_list(requirement["references"], f"{path}.references")
        capabilities = require_string_list(requirement["capabilities"], f"{path}.capabilities")
        unknown_capabilities = set(capabilities) - CAPABILITIES
        if unknown_capabilities:
            fail(f"{path}.capabilities", f"unknown capabilities: {sorted(unknown_capabilities)}")
        if requirement["implementation"] not in {"defined_only", "planned"}:
            fail(f"{path}.implementation", "Gate 0 must not claim implemented behavior")
        require_string(requirement["machine_verification"], f"{path}.machine_verification")
        require_string(requirement["human_verification"], f"{path}.human_verification")
        for field in ("positive_scenarios", "negative_scenarios", "external_rule_ids"):
            values = require_string_list(requirement[field], f"{path}.{field}")
            if field.endswith("scenarios"):
                for scenario in values:
                    scenario_path = (ROOT / scenario).resolve()
                    if not scenario_path.is_relative_to(ROOT) or not scenario_path.is_file():
                        fail(f"{path}.{field}", f"scenario does not exist: {scenario}")

    if ids != sorted(set(ids)):
        fail("ledger.requirements", "requirement ids must be sorted and unique")
    requirements_by_id = {requirement["id"]: requirement for requirement in raw_requirements}
    issue_rules = {
        "ROC-PDF-PDF20-GOTO-D-DESTINATION": "pdf-issues#140",
        "ROC-PDF-PDF20-NAMED-DESTINATION-SD": "pdf-issues#162",
    }
    for rule_id, issue_reference in issue_rules.items():
        requirement = requirements_by_id.get(rule_id)
        if requirement is None:
            fail("ledger.requirements", f"missing required errata rule {rule_id}")
        if "pdf-issues-ec3" not in requirement["source_ids"] or issue_reference not in requirement["references"]:
            fail(rule_id, f"must independently pin {issue_reference} to the EC3 source")


def validate_documents(baseline: object, matrix: object, ledger: object) -> None:
    source_ids = validate_baseline(baseline)
    validate_matrix(matrix)
    validate_ledger(ledger, source_ids)


def validate_repository() -> None:
    validate_documents(load(BASELINE_PATH), load(MATRIX_PATH), load(LEDGER_PATH))


def expect_rejected(baseline: object, matrix: object, ledger: object, mutate: str) -> None:
    test_baseline = copy.deepcopy(baseline)
    test_matrix = copy.deepcopy(matrix)
    test_ledger = copy.deepcopy(ledger)
    if mutate == "digest":
        test_baseline["sources"][10]["pin"]["value"] = "0" * 64
    elif mutate == "profile":
        test_matrix["profiles"][0]["claims"] = ["Pdf20"]
    elif mutate == "source":
        test_ledger["requirements"][0]["source_ids"] = ["unknown-source"]
    elif mutate == "issue":
        test_ledger["requirements"][1]["references"] = ["ISO 32000-2:2020 12.6.4.2 Table 202"]
    else:
        raise AssertionError(mutate)
    try:
        validate_documents(test_baseline, test_matrix, test_ledger)
    except ContractError:
        return
    raise ContractError(f"self-test mutation was accepted: {mutate}")


def self_test() -> None:
    baseline = load(BASELINE_PATH)
    matrix = load(MATRIX_PATH)
    ledger = load(LEDGER_PATH)
    validate_documents(baseline, matrix, ledger)
    for mutation in ("digest", "profile", "source", "issue"):
        expect_rejected(baseline, matrix, ledger, mutation)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        else:
            validate_repository()
    except ContractError as error:
        raise SystemExit(error) from error
    print("PASS conformance contracts")


if __name__ == "__main__":
    main()
