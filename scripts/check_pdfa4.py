#!/usr/bin/env python3
"""Pinned veraPDF PDF/A-4 validation lane for the static Archive profile.

Every invocation runs the provisioned veraPDF 1.30.2 greenfield validator
with the explicit PDF/A-4 flavour (``--flavour 4``; metadata autodetection is
never relied upon) on the original bytes, in JSON form with parser logs. A
report is accepted only when the validator version and PDF/A-4 profile are
the pinned ones, the job ended normally, and no parser log or warning was
recorded; tool warnings are failures, not advice.

Modes:

``--cases``
    Every tests/spec.json case with the ``pdfa4`` validator (the Archive
    snapshots) must be compliant with zero failed rules and checks.
``--standard-cases``
    Every other snapshot is Standard (``Pdf20``) output. It must never declare
    PDF/A identification, and veraPDF may fail only the metadata and
    identification rules a Standard file deliberately omits (6.7.2.1-1 and
    6.7.3-1) plus the per-fixture exceptions below, each of which is a
    deliberate negative input rather than a construct the Archive whitelist
    admits. This shows every Gate 4 construct the kernel emits (forms,
    transparency, soft masks, shadings, colour images, fonts, navigation) is
    otherwise PDF/A-4 eligible.
``--corpus DIR``
    Every file of the vendored upstream PDF/A-4 corpus subset must produce
    the verdict its filename encodes: ``-pass-`` files compliant and
    ``-fail-`` files non-compliant. Recorded validator defects live in
    conformance/verapdf-exceptions.json with an upstream reference.
``--self-test``
    Exercises report classification with synthetic reports (no Java) and
    validates the exception ledger against the pinned rule catalog.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VERAPDF = ROOT / ".roc-pdf-tmp" / "extended-tools" / "verapdf" / "verapdf"
DEFAULT_CORPUS = ROOT / ".roc-pdf-tmp" / "extended-tools" / "verapdf-corpus" / "verapdf-corpus-pdfa4" / "PDF_A-4"
SPEC = ROOT / "tests" / "spec.json"
CATALOG = ROOT / "conformance" / "verapdf-pdfa4-rules.json"
EXCEPTIONS = ROOT / "conformance" / "verapdf-exceptions.json"
VERSION = "1.30.2"
PROFILE_NAME = "PDF/A-4 validation profile"
STANDARD_OMISSIONS = frozenset({"6.7.2.1-1", "6.7.3-1"})
# Deliberate kernel inputs that the Archive whitelist rejects; each is a
# negative fact of its own slice, never Archive output.
_SCREEN_ONLY_LINK = (
    frozenset({"6.3.2-2"}),
    "the kernel navigation showcase deliberately carries one screen-only /F 0 annotation",
)
STANDARD_FIXTURE_EXCEPTIONS: dict[str, tuple[frozenset[str], str]] = {
    "tests/navigation/navigation.pdf": _SCREEN_ONLY_LINK,
    "tests/navigation/navigation_negative.pdf": _SCREEN_ONLY_LINK,
    "tests/navigation/navigation_retained.pdf": _SCREEN_ONLY_LINK,
    "tests/navigation/navigation_unique.pdf": _SCREEN_ONLY_LINK,
    "tests/placeholder/snapshot.pdf": (
        frozenset({"6.1.2-2", "6.1.3-1"}),
        "the harness placeholder is a fixed PDF written by the test platform, not package output",
    ),
}
CORPUS_NAME = re.compile(r"veraPDF test suite (6(?:-[0-9]+)+)-t([0-9]+)-(pass|fail)-[a-z]+\.pdf\Z")
BATCH = 64


class OracleError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise OracleError(message)


@dataclass(frozen=True)
class Result:
    path: str
    compliant: bool
    failed_rules: frozenset[str]
    failed_checks: int


def rule_id(summary: dict[str, object]) -> str:
    return f"{summary['clause']}-{summary['testNumber']}"


def classify(report: dict[str, object], strict: bool = True) -> list[Result]:
    """Classify a veraPDF JSON report.

    Package output is classified strictly: parser logs, warnings, and task
    exceptions are failures. Corpus inputs are deliberately malformed, so a
    non-strict classification records a task exception as a non-compliant
    result with no rule outcome instead of aborting.
    """
    body = report["report"]
    versions = {detail["id"]: detail["version"] for detail in body["buildInformation"]["releaseDetails"]}
    require(versions.get("core") == VERSION and versions.get("validation-model") == VERSION, f"veraPDF must be {VERSION}; got {versions}")
    summary = body["batchSummary"]
    require(summary["veraExceptions"] == 0 and summary["outOfMemory"] == 0, "veraPDF raised an exception or ran out of memory")
    if strict:
        require(summary["failedParsingJobs"] == 0 and summary["failedEncryptedJobs"] == 0, "veraPDF could not parse a file")
    results: list[Result] = []
    for job in body["jobs"]:
        path = job["itemDetails"]["name"]
        if not strict and ("taskException" in job or "validationResult" not in job):
            results.append(Result(path, False, frozenset({"task-exception"}), 0))
            continue
        require("taskException" not in job and "taskResult" not in job, f"{path}: veraPDF task failed")
        logs = job.get("logs")
        require(not strict or not logs or not logs.get("logs"), f"{path}: veraPDF recorded parser logs or warnings: {logs}")
        validations = job["validationResult"]
        require(len(validations) == 1, f"{path}: expected exactly one validation result")
        validation = validations[0]
        require(validation["profileName"] == PROFILE_NAME, f"{path}: validated against {validation['profileName']!r}")
        require(validation["jobEndStatus"] == "normal", f"{path}: validation did not end normally")
        details = validation["details"]
        failed = frozenset(rule_id(rule) for rule in details["ruleSummaries"] if rule["status"] == "failed")
        require(len(failed) == details["failedRules"], f"{path}: failed-rule summary is inconsistent")
        results.append(Result(path, bool(validation["compliant"]), failed, int(details["failedChecks"])))
    return results


def run_verapdf(verapdf: Path, paths: list[Path], strict: bool = True) -> list[Result]:
    require(verapdf.is_file(), f"veraPDF is not provisioned at {verapdf}; run scripts/provision_extended_tools.py")
    results: list[Result] = []
    for start in range(0, len(paths), BATCH):
        batch = paths[start:start + BATCH]
        completed = subprocess.run(
            [str(verapdf), "--flavour", "4", "--format", "json", "--addlogs", "--maxfailuresdisplayed", "1", *map(str, batch)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        require(completed.stdout.strip() != b"", f"veraPDF produced no report: {completed.stderr.decode(errors='replace')[-2000:]}")
        results.extend(classify(json.loads(completed.stdout), strict))
    require(len(results) == len(paths), "veraPDF did not report every file")
    return results


def spec_snapshots() -> tuple[list[Path], list[Path]]:
    cases = json.loads(SPEC.read_text(encoding="utf-8"))["cases"]
    archive = sorted({ROOT / case["snapshot"] for case in cases if "pdfa4" in case["validators"]})
    # Zero-byte snapshots are negative cases that deliberately emit no bytes.
    standard = sorted(path for path in {ROOT / case["snapshot"] for case in cases} - set(archive) if path.stat().st_size > 0)
    return archive, standard


def check_archive(results: list[Result]) -> None:
    for result in results:
        require(result.compliant and not result.failed_rules and result.failed_checks == 0, f"{result.path}: PDF/A-4 failures {sorted(result.failed_rules)}")


def check_standard(results: list[Result], paths: list[Path]) -> dict[str, int]:
    tally: dict[str, int] = {}
    for result, path in zip(results, paths):
        relative = path.relative_to(ROOT).as_posix()
        require(b"pdfaid" not in path.read_bytes(), f"{relative}: Standard output declares PDF/A identification")
        allowed = STANDARD_OMISSIONS | STANDARD_FIXTURE_EXCEPTIONS.get(relative, (frozenset(), ""))[0]
        unexpected = result.failed_rules - allowed
        require(not unexpected, f"{relative}: unexpected PDF/A-4 failures {sorted(unexpected)}")
        require(not result.compliant and result.failed_rules & STANDARD_OMISSIONS, f"{relative}: Standard output must fail the omitted metadata or identification rule")
        for rule in result.failed_rules:
            tally[rule] = tally.get(rule, 0) + 1
    return tally


def load_exceptions(catalog_ids: set[str]) -> dict[str, dict[str, str]]:
    document = json.loads(EXCEPTIONS.read_text(encoding="utf-8"))
    require(set(document) == {"schema_version", "validator", "exceptions"}, "exception ledger keys are invalid")
    require(document["schema_version"] == 1, "exception ledger schema_version must be 1")
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["validator"]
    require(document["validator"] == {"name": "veraPDF", "profile_sha256": catalog["profile_sha256"], "version": VERSION}, "exception ledger is not pinned to the catalog's validator")
    by_file: dict[str, dict[str, str]] = {}
    fields = {"file", "expected", "observed", "reason", "upstream_reference", "reviewed_on"}
    for index, exception in enumerate(document["exceptions"]):
        require(set(exception) == fields, f"exception {index}: keys must be exactly {sorted(fields)}")
        require(exception["expected"] in ("pass", "fail") and exception["observed"] in ("pass", "fail") and exception["expected"] != exception["observed"], f"exception {index}: invalid outcome")
        require(exception["upstream_reference"].startswith("https://"), f"exception {index}: upstream reference must be a URL")
        require(re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", exception["reviewed_on"]) is not None, f"exception {index}: reviewed_on must be a date")
        require(exception["file"] not in by_file, f"exception {index}: duplicate file")
        by_file[exception["file"]] = exception
    return by_file


def corpus_expectation(name: str) -> tuple[str, str]:
    """The clause and verdict a corpus file name encodes.

    Upstream names read ``veraPDF test suite <clause>-t<NN>-<pass|fail>-<x>``;
    ``tNN`` numbers test files within the clause and is not the validation
    profile's rule test number, so the verdict is the whole-file expectation.
    """
    match = CORPUS_NAME.fullmatch(name)
    require(match is not None, f"unrecognized corpus file name {name!r}")
    return match.group(1).replace("-", "."), match.group(3)


def check_corpus(results: list[Result], root: Path, exceptions: dict[str, dict[str, str]]) -> tuple[int, int, int, int]:
    passed = failed = excepted = same_clause = 0
    used: set[str] = set()
    for result in results:
        relative = Path(result.path).relative_to(root).as_posix()
        clause, expected = corpus_expectation(Path(result.path).name)
        observed = "pass" if result.compliant else "fail"
        exception = exceptions.get(relative)
        if exception is not None:
            require(observed != expected, f"{relative}: recorded exception no longer reproduces; remove it")
            require(exception["expected"] == expected and exception["observed"] == observed, f"{relative}: exception does not match the observed defect")
            used.add(relative)
            excepted += 1
            continue
        require(observed == expected, f"{relative}: expected {expected}, observed {observed} ({sorted(result.failed_rules)})")
        if expected == "pass":
            passed += 1
        else:
            failed += 1
            if any(rule.rsplit("-", 1)[0] == clause for rule in result.failed_rules):
                same_clause += 1
    require(used == set(exceptions), f"unused corpus exceptions: {sorted(set(exceptions) - used)}")
    return passed, failed, excepted, same_clause


def synthetic(compliant: bool, failed: list[str], *, version: str = VERSION, profile: str = PROFILE_NAME, logs: object = None) -> dict[str, object]:
    job: dict[str, object] = {
        "itemDetails": {"name": "synthetic.pdf", "size": 1},
        "validationResult": [{
            "details": {
                "passedRules": 109 - len(failed),
                "failedRules": len(failed),
                "passedChecks": 10,
                "failedChecks": len(failed),
                "ruleSummaries": [{"clause": rule.rsplit("-", 1)[0], "testNumber": int(rule.rsplit("-", 1)[1]), "status": "failed"} for rule in failed],
            },
            "jobEndStatus": "normal",
            "profileName": profile,
            "compliant": compliant,
        }],
    }
    if logs is not None:
        job["logs"] = logs
    return {"report": {
        "buildInformation": {"releaseDetails": [{"id": "core", "version": version}, {"id": "validation-model", "version": version}]},
        "jobs": [job],
        "batchSummary": {"veraExceptions": 0, "outOfMemory": 0, "failedParsingJobs": 0, "failedEncryptedJobs": 0},
    }}


def self_test() -> None:
    catalog_ids = {rule["id"] for rule in json.loads(CATALOG.read_text(encoding="utf-8"))["rules"]}
    load_exceptions(catalog_ids)
    check_archive(classify(synthetic(True, [])))
    rejected = [
        ("failed rule", lambda: check_archive(classify(synthetic(False, ["6.7.3-1"])))),
        ("wrong version", lambda: classify(synthetic(True, [], version="1.28.2"))),
        ("wrong profile", lambda: classify(synthetic(True, [], profile="PDF/A-2B validation profile"))),
        ("parser warning", lambda: classify(synthetic(True, [], logs={"logsCount": 1, "logs": [{"level": "WARNING", "message": "x"}]}))),
    ]
    for label, action in rejected:
        try:
            action()
        except OracleError:
            continue
        raise SystemExit(f"check_pdfa4 accepted {label}")
    require(corpus_expectation("veraPDF test suite 6-2-10-7-t01-fail-a.pdf") == ("6.2.10.7", "fail"), "corpus name parsing")
    require(corpus_expectation("veraPDF test suite 6-12-t01-pass-b.pdf") == ("6.12", "pass"), "corpus name parsing")
    archive, standard = spec_snapshots()
    require(archive and all(path.is_file() for path in archive + standard), "spec snapshots are missing")
    for path in archive:
        require(b"<pdfaid:part>4</pdfaid:part>" in path.read_bytes(), f"{path}: Archive snapshot lacks PDF/A identification")
    for path in standard:
        require(b"pdfaid" not in path.read_bytes(), f"{path}: Standard snapshot declares PDF/A identification")
    print(f"PASS check_pdfa4 self-test: report classification, {len(rejected)} rejected reports, exception ledger, and identification on {len(archive)} Archive / {len(standard)} Standard snapshots")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verapdf", type=Path, default=DEFAULT_VERAPDF)
    parser.add_argument("--cases", action="store_true")
    parser.add_argument("--standard-cases", action="store_true")
    parser.add_argument("--corpus", nargs="?", const=DEFAULT_CORPUS, type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("pdfs", nargs="*", type=Path)
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return
        ran = False
        archive, standard = spec_snapshots()
        if args.cases:
            check_archive(run_verapdf(args.verapdf, archive))
            print(f"PASS veraPDF {VERSION} PDF/A-4: {len(archive)} Archive snapshots compliant with zero failed checks")
            ran = True
        if args.standard_cases:
            tally = check_standard(run_verapdf(args.verapdf, standard), standard)
            print(f"PASS veraPDF {VERSION} PDF/A-4 on {len(standard)} Standard snapshots: only deliberate omissions failed {dict(sorted(tally.items()))}")
            ran = True
        if args.corpus is not None:
            catalog_ids = {rule["id"] for rule in json.loads(CATALOG.read_text(encoding="utf-8"))["rules"]}
            files = sorted(args.corpus.rglob("*.pdf"))
            require(files, f"no corpus files under {args.corpus}")
            passed, failed, excepted, same_clause = check_corpus(run_verapdf(args.verapdf, files, strict=False), args.corpus, load_exceptions(catalog_ids))
            print(f"PASS veraPDF {VERSION} PDF/A-4 corpus: {passed} pass files compliant, {failed} fail files non-compliant ({same_clause} within their named clause), {excepted} recorded exceptions")
            ran = True
        if args.pdfs:
            check_archive(run_verapdf(args.verapdf, args.pdfs))
            print(f"PASS veraPDF {VERSION} PDF/A-4: {len(args.pdfs)} files compliant")
            ran = True
        if not ran:
            parser.error("choose --cases, --standard-cases, --corpus, --self-test, or PDF paths")
    except OracleError as error:
        raise SystemExit(f"FAIL {error}") from error


if __name__ == "__main__":
    main()
