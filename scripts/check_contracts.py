#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
ASSET_MANIFEST_PATH = ROOT / "assets" / "provenance.json"
SOURCE_ID = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
BINARY_ASSET_SUFFIXES = {".a", ".icc", ".icm", ".jar", ".jpeg", ".jpg", ".o", ".otf", ".pdf", ".png", ".tgz", ".ttf", ".zip"}
ASSET_KINDS = {
    "expected_pdf",
    "font",
    "fuzz_seed",
    "hyphenation",
    "icc_profile",
    "image",
    "test_toolchain",
    "unicode_data",
    "validator_corpus",
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


def require_version(document: dict[str, object], path: str) -> None:
    if document["schema_version"] != 1:
        fail(f"{path}.schema_version", "must be 1")


def repository_paths() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return sorted({path.decode("utf-8") for path in result.stdout.split(b"\0") if path})


def validate_portable_paths(paths: list[str]) -> None:
    # Check the Git inventory, not directory entries: a case-insensitive
    # checkout can already have overwritten one of the conflicting files.
    spellings: dict[str, str] = {}
    for path in sorted(set(paths)):
        parts = path.split("/")
        for end in range(1, len(parts) + 1):
            prefix = "/".join(parts[:end])
            folded = prefix.casefold()
            previous = spellings.get(folded)
            if previous is not None and previous != prefix:
                fail("repository paths", f"case-insensitive collision: {previous!r} and {prefix!r}")
            spellings[folded] = prefix


def repository_binary_assets() -> set[str]:
    return {
        path for path in repository_paths()
        if Path(path).suffix.lower() in BINARY_ASSET_SUFFIXES and (ROOT / path).is_file()
    }


def validate_assets(value: object) -> None:
    document = require_object(value, "asset-provenance", {"schema_version", "assets"})
    require_version(document, "asset-provenance")
    raw_assets = document["assets"]
    if not isinstance(raw_assets, list):
        fail("asset-provenance.assets", "must be a list")

    ids: list[str] = []
    paths: list[str] = []
    for index, raw_asset in enumerate(raw_assets):
        path = f"asset-provenance.assets[{index}]"
        required_keys = {
            "id",
            "path",
            "kind",
            "bytes",
            "sha256",
            "license",
            "attribution",
            "modification_permitted",
            "redistribution_permitted",
            "origin",
        }
        if isinstance(raw_asset, dict) and raw_asset.get("kind") == "hyphenation":
            required_keys.add("language")
        asset = require_object(raw_asset, path, required_keys)
        asset_id = require_string(asset["id"], f"{path}.id")
        if SOURCE_ID.fullmatch(asset_id) is None:
            fail(f"{path}.id", "must be a lowercase kebab-case identifier")
        ids.append(asset_id)

        repository_path = require_string(asset["path"], f"{path}.path")
        resolved_path = (ROOT / repository_path).resolve()
        if not resolved_path.is_relative_to(ROOT) or not resolved_path.is_file():
            fail(f"{path}.path", "must name an existing repository file")
        paths.append(repository_path)
        if asset["kind"] not in ASSET_KINDS:
            fail(f"{path}.kind", f"must be one of {sorted(ASSET_KINDS)}")
        if asset["kind"] == "hyphenation":
            language = require_string(asset["language"], f"{path}.language")
            if re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", language) is None:
                fail(f"{path}.language", "must be a syntactically valid BCP 47 tag")

        byte_count = asset["bytes"]
        if type(byte_count) is not int or byte_count < 0:
            fail(f"{path}.bytes", "must be a non-negative integer")
        payload = resolved_path.read_bytes()
        if len(payload) != byte_count:
            fail(f"{path}.bytes", f"expected {byte_count}, found {len(payload)}")
        digest = require_string(asset["sha256"], f"{path}.sha256")
        if SHA256.fullmatch(digest) is None or hashlib.sha256(payload).hexdigest() != digest:
            fail(f"{path}.sha256", "does not match the retained bytes")
        require_string(asset["license"], f"{path}.license")
        attribution = require_string(asset["attribution"], f"{path}.attribution")
        if "/" in attribution:
            attribution_path = (ROOT / attribution).resolve()
            if not attribution_path.is_relative_to(ROOT) or not attribution_path.is_file():
                fail(f"{path}.attribution", "referenced attribution file does not exist")
        for field in ("modification_permitted", "redistribution_permitted"):
            if type(asset[field]) is not bool:
                fail(f"{path}.{field}", "must be a boolean")

        origin = asset["origin"]
        if not isinstance(origin, dict):
            fail(f"{path}.origin", "must be an object")
        if origin.get("kind") == "external":
            external = require_object(
                origin,
                f"{path}.origin",
                {"kind", "source_url", "upstream_revision"},
            )
            source_url = require_string(external["source_url"], f"{path}.origin.source_url")
            revision = require_string(external["upstream_revision"], f"{path}.origin.upstream_revision")
            if not source_url.startswith("https://") or revision not in source_url:
                fail(f"{path}.origin", "external URL must be https and contain its immutable revision")
        elif origin.get("kind") == "generated":
            generated = require_object(origin, f"{path}.origin", {"kind", "generator"})
            generator = (ROOT / require_string(generated["generator"], f"{path}.origin.generator")).resolve()
            if not generator.is_relative_to(ROOT) or not generator.is_file():
                fail(f"{path}.origin.generator", "must name an existing repository file")
        else:
            fail(f"{path}.origin.kind", "must be external or generated")

    if ids != sorted(set(ids)):
        fail("asset-provenance.assets", "asset ids must be sorted and unique")
    if len(paths) != len(set(paths)):
        fail("asset-provenance.assets", "asset paths must be unique")
    tracked_assets = repository_binary_assets()
    if set(paths) != tracked_assets:
        missing = sorted(tracked_assets - set(paths))
        extra = sorted(set(paths) - tracked_assets)
        fail("asset-provenance.assets", f"must cover tracked binary assets; missing={missing}, extra={extra}")


def validate_repository() -> None:
    paths = repository_paths()
    validate_portable_paths(paths)
    for path in paths:
        if path.casefold().startswith(".standards/"):
            fail("repository paths", "licensed standards belong in ignored local storage")
    validate_assets(load(ASSET_MANIFEST_PATH))


def self_test() -> None:
    validate_repository()
    validate_portable_paths([
        "tests/tagged_visual/Stress.roc",
        "tests/tagged_visual/command_stress.roc",
        "tests/another/Stress.roc",
    ])
    for paths in (
        ["tests/tagged_visual/Stress.roc", "tests/tagged_visual/stress.roc"],
        ["tests/TaggedVisual/Fixture.roc", "tests/taggedvisual/main.roc"],
    ):
        try:
            validate_portable_paths(paths)
        except ContractError:
            pass
        else:
            raise ContractError(f"self-test path collision was accepted: {paths}")
    assets = load(ASSET_MANIFEST_PATH)
    changed_assets = copy.deepcopy(assets)
    changed_assets["assets"][0]["sha256"] = "0" * 64
    try:
        validate_assets(changed_assets)
    except ContractError:
        pass
    else:
        raise ContractError("self-test asset digest mutation was accepted")


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
    print("PASS repository contracts")


if __name__ == "__main__":
    main()
