#!/usr/bin/env python3
"""Pinned Arlington PDF 2.0 object-model lane (veraPDF Arlington 1.30.2).

The validator runs as the digest-pinned ``verapdf/arlington`` REST service
(default ``http://127.0.0.1:18080``). A report is accepted only when the
pinned releases and profile are reported, the job ended normally with no
parser, encryption, memory, or validator exception, and zero rules and
checks failed.

Modes:

``PDF...``
    Validate the named files.
``--cases``
    Validate every distinct non-empty snapshot referenced by tests/spec.json
    plus every public example in examples/*.pdf. Only the files in
    ``FIXTURE_EXCEPTIONS`` may fail, and each must fail exactly its recorded
    rule set; an exception that no longer fails, or fails differently, is
    itself an error.
``--self-test``
    Exercises report classification, exception matching, and case
    collection with synthetic reports and the local spec (no network).
"""

import argparse
import copy
import json
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PROFILE = "Arlington PDF 2.0 profile"
EXPECTED_RELEASES = {
    "core-arlington": "1.30.2",
    "validation-model-arlington": "1.30.2",
    "verapdf-rest-arlington": "1.30.2",
}


# Files that are not package output and deliberately fall outside the
# Arlington model. Keys are paths relative to the repository root; values are
# the exact failing rule identifiers (``clause#testNumber``) and why.
FIXTURE_EXCEPTIONS: dict[str, tuple[frozenset[str], str]] = {
    "tests/placeholder/snapshot.pdf": (
        frozenset({"FileTrailer-ID#11"}),
        "the harness placeholder is a fixed classic-xref PDF written by the test "
        "platform, not package output; it has no trailer /ID",
    ),
}


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def object_value(value: object, label: str) -> dict[str, object]:
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def list_value(value: object, label: str) -> list[object]:
    require(isinstance(value, list), f"{label} must be a list")
    return value


def integer_value(value: object, label: str) -> int:
    require(type(value) is int, f"{label} must be an integer")
    return value


def validate_report(
    value: object, expected_name: str, expected_size: int
) -> tuple[int, int]:
    root = object_value(value, "response")
    report = object_value(root.get("report"), "report")
    build = object_value(report.get("buildInformation"), "buildInformation")
    releases = list_value(build.get("releaseDetails"), "releaseDetails")
    observed_releases: dict[str, str] = {}
    for index, raw_release in enumerate(releases):
        release = object_value(raw_release, f"releaseDetails[{index}]")
        identifier = release.get("id")
        version = release.get("version")
        require(isinstance(identifier, str), f"releaseDetails[{index}].id must be text")
        require(isinstance(version, str), f"releaseDetails[{index}].version must be text")
        observed_releases[identifier] = version
    for identifier, version in EXPECTED_RELEASES.items():
        require(
            observed_releases.get(identifier) == version,
            f"expected {identifier} version {version}, got {observed_releases.get(identifier)!r}",
        )

    jobs = list_value(report.get("jobs"), "jobs")
    require(len(jobs) == 1, f"expected one Arlington job, got {len(jobs)}")
    job = object_value(jobs[0], "jobs[0]")
    item = object_value(job.get("itemDetails"), "itemDetails")
    require(item.get("name") == expected_name, f"unexpected report item {item.get('name')!r}")
    require(item.get("size") == expected_size, f"unexpected report size {item.get('size')!r}")

    results = list_value(job.get("arlingtonResult"), "arlingtonResult")
    require(len(results) == 1, f"expected one Arlington result, got {len(results)}")
    result = object_value(results[0], "arlingtonResult[0]")
    require(result.get("profileName") == EXPECTED_PROFILE, "unexpected Arlington profile")
    require(result.get("jobEndStatus") == "normal", "Arlington job did not end normally")
    require(result.get("compliant") is True, "Arlington reported a non-compliant PDF")
    require(
        result.get("statement") == "PDF file is compliant with Profile requirements.",
        "Arlington did not report profile compliance",
    )

    details = object_value(result.get("details"), "details")
    passed_rules = integer_value(details.get("passedRules"), "passedRules")
    failed_rules = integer_value(details.get("failedRules"), "failedRules")
    passed_checks = integer_value(details.get("passedChecks"), "passedChecks")
    failed_checks = integer_value(details.get("failedChecks"), "failedChecks")
    require(passed_rules > 0, "Arlington executed no rules")
    require(passed_checks > 0, "Arlington executed no object checks")
    require(failed_rules == 0, f"Arlington reported {failed_rules} failed rules")
    require(failed_checks == 0, f"Arlington reported {failed_checks} failed checks")
    require(details.get("ruleSummaries") == [], "Arlington returned failure summaries")

    summary = object_value(report.get("batchSummary"), "batchSummary")
    for field in [
        "failedEncryptedJobs",
        "failedParsingJobs",
        "outOfMemory",
        "veraExceptions",
    ]:
        require(summary.get(field) == 0, f"Arlington batch summary has nonzero {field}")
    validation = object_value(summary.get("validationSummary"), "validationSummary")
    require(validation.get("totalJobCount") == 1, "Arlington validation total is not one")
    require(validation.get("successfulJobCount") == 1, "Arlington validation did not succeed")
    require(validation.get("failedJobCount") == 0, "Arlington validation job failed")
    require(validation.get("nonCompliantPdfaCount") == 0, "Arlington counted a non-compliant PDF")
    require(validation.get("compliantPdfaCount") == 1, "Arlington did not count one compliant PDF")
    return passed_rules, passed_checks


def failed_rules(value: object) -> frozenset[str]:
    """Return the failing rule identifiers of a report whose job otherwise ran
    normally. Reports that did not run normally raise instead."""
    root = object_value(value, "response")
    report = object_value(root.get("report"), "report")
    summary = object_value(report.get("batchSummary"), "batchSummary")
    for field in [
        "failedEncryptedJobs",
        "failedParsingJobs",
        "outOfMemory",
        "veraExceptions",
    ]:
        require(summary.get(field) == 0, f"Arlington batch summary has nonzero {field}")
    jobs = list_value(report.get("jobs"), "jobs")
    require(len(jobs) == 1, f"expected one Arlington job, got {len(jobs)}")
    job = object_value(jobs[0], "jobs[0]")
    results = list_value(job.get("arlingtonResult"), "arlingtonResult")
    require(len(results) == 1, f"expected one Arlington result, got {len(results)}")
    result = object_value(results[0], "arlingtonResult[0]")
    require(result.get("profileName") == EXPECTED_PROFILE, "unexpected Arlington profile")
    require(result.get("jobEndStatus") == "normal", "Arlington job did not end normally")
    details = object_value(result.get("details"), "details")
    summaries = list_value(details.get("ruleSummaries"), "ruleSummaries")
    rules: set[str] = set()
    for index, raw_rule in enumerate(summaries):
        rule = object_value(raw_rule, f"ruleSummaries[{index}]")
        clause = rule.get("clause")
        number = rule.get("testNumber")
        require(isinstance(clause, str), f"ruleSummaries[{index}].clause must be text")
        require(type(number) is int, f"ruleSummaries[{index}].testNumber must be an integer")
        rules.add(f"{clause}#{number}")
    return frozenset(rules)


def describe_failures(value: object) -> str:
    lines = []
    try:
        result = value["report"]["jobs"][0]["arlingtonResult"][0]  # type: ignore[index]
        for rule in result["details"]["ruleSummaries"]:
            lines.append(
                f"  {rule.get('clause')}#{rule.get('testNumber')}: {rule.get('description')} "
                f"({rule.get('failedChecks')} checks)"
            )
    except (KeyError, IndexError, TypeError):
        pass
    return "".join("\n" + line for line in lines)


def classify_case(value: object, relative: str, expected_size: int) -> str:
    """Accept one case report, or raise with the precise failure."""
    exception = FIXTURE_EXCEPTIONS.get(relative)
    if exception is None:
        try:
            passed_rules, passed_checks = validate_report(value, Path(relative).name, expected_size)
        except ValidationError as error:
            raise ValidationError(f"{relative}: {error}{describe_failures(value)}") from error
        return f"passed_rules={passed_rules}, passed_checks={passed_checks}"
    expected_rules, reason = exception
    observed = failed_rules(value)
    require(
        observed == expected_rules,
        f"{relative}: recorded exception {sorted(expected_rules)} but Arlington failed "
        f"{sorted(observed)}; update or remove the exception",
    )
    return f"recorded exception {sorted(expected_rules)}: {reason}"


def case_paths(root: Path = ROOT) -> list[str]:
    """Distinct non-empty spec snapshots, then the public examples, relative
    to ``root``. Zero-byte snapshots are negative cases that emit no bytes."""
    spec = json.loads((root / "tests" / "spec.json").read_text())
    cases = list_value(spec.get("cases"), "cases")
    snapshots: set[str] = set()
    for index, raw_case in enumerate(cases):
        case = object_value(raw_case, f"cases[{index}]")
        snapshot = case.get("snapshot")
        require(isinstance(snapshot, str), f"cases[{index}].snapshot must be text")
        snapshots.add(snapshot)
    for relative in sorted(snapshots):
        require((root / relative).is_file(), f"spec snapshot {relative} is missing")
    selected = sorted(relative for relative in snapshots if (root / relative).stat().st_size > 0)
    examples = sorted(path.relative_to(root).as_posix() for path in (root / "examples").glob("*.pdf"))
    require(bool(examples), "examples/*.pdf is empty")
    return selected + examples


def wait_ready(base_url: str, timeout_seconds: float = 90.0) -> None:
    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{base_url}/api/info", timeout=5) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError) as error:
            last_error = error
        time.sleep(1)
    raise ValidationError(f"Arlington service did not become ready: {last_error}")


def request_report(base_url: str, pdf: Path) -> object:
    boundary = b"roc-pdf-arlington-boundary"
    data = pdf.read_bytes()
    body = b"".join(
        [
            b"--" + boundary + b"\r\n",
            b'Content-Disposition: form-data; name="file"; filename="'
            + pdf.name.encode("ascii")
            + b'"\r\n',
            b"Content-Type: application/pdf\r\n\r\n",
            data,
            b"\r\n--" + boundary + b"--\r\n",
        ]
    )
    request = urllib.request.Request(
        f"{base_url}/api/validate/arlington2.0",
        data=body,
        headers={
            "Accept": "application/json",
            "Content-Type": f"multipart/form-data; boundary={boundary.decode('ascii')}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            require(response.status == 200, f"Arlington returned HTTP {response.status}")
            return json.loads(response.read())
    except (json.JSONDecodeError, OSError, urllib.error.URLError) as error:
        raise ValidationError(f"Arlington request failed for {pdf}: {error}") from error


def valid_test_report() -> dict[str, object]:
    return {
        "report": {
            "buildInformation": {
                "releaseDetails": [
                    {"id": identifier, "version": version}
                    for identifier, version in EXPECTED_RELEASES.items()
                ]
            },
            "jobs": [
                {
                    "itemDetails": {"name": "fixture.pdf", "size": 10},
                    "arlingtonResult": [
                        {
                            "details": {
                                "passedRules": 10,
                                "failedRules": 0,
                                "passedChecks": 20,
                                "failedChecks": 0,
                                "ruleSummaries": [],
                            },
                            "jobEndStatus": "normal",
                            "profileName": EXPECTED_PROFILE,
                            "statement": "PDF file is compliant with Profile requirements.",
                            "compliant": True,
                        }
                    ],
                }
            ],
            "batchSummary": {
                "outOfMemory": 0,
                "veraExceptions": 0,
                "failedParsingJobs": 0,
                "failedEncryptedJobs": 0,
                "validationSummary": {
                    "compliantPdfaCount": 1,
                    "nonCompliantPdfaCount": 0,
                    "failedJobCount": 0,
                    "totalJobCount": 1,
                    "successfulJobCount": 1,
                },
            },
        }
    }


def self_test() -> None:
    valid = valid_test_report()
    require(validate_report(valid, "fixture.pdf", 10) == (10, 20), "valid report failed")
    mutations = [
        ("non-compliance", ("report", "jobs", 0, "arlingtonResult", 0, "compliant"), False),
        ("failed check", ("report", "jobs", 0, "arlingtonResult", 0, "details", "failedChecks"), 1),
        ("parser recovery", ("report", "batchSummary", "failedParsingJobs"), 1),
        (
            "version drift",
            ("report", "buildInformation", "releaseDetails", 0, "version"),
            "unexpected",
        ),
    ]
    for label, path, replacement in mutations:
        candidate = copy.deepcopy(valid)
        target: object = candidate
        for key in path[:-1]:
            target = target[key]  # type: ignore[index]
        target[path[-1]] = replacement  # type: ignore[index]
        try:
            validate_report(candidate, "fixture.pdf", 10)
        except ValidationError:
            pass
        else:
            raise SystemExit(f"Arlington report checker accepted {label}")

    ## Case classification: a clean file passes, an unrecorded failure is
    ## rejected, and a recorded exception must fail exactly as recorded.
    require(
        classify_case(valid, "tests/example/fixture.pdf", 10).startswith("passed_rules="),
        "clean case was not accepted",
    )
    failing = copy.deepcopy(valid)
    job = failing["report"]["jobs"][0]  # type: ignore[index]
    job["itemDetails"]["name"] = "snapshot.pdf"
    result = job["arlingtonResult"][0]
    result["compliant"] = False
    result["details"]["failedRules"] = 1
    result["details"]["failedChecks"] = 1
    result["details"]["ruleSummaries"] = [
        {
            "clause": "FileTrailer-ID",
            "testNumber": 11,
            "description": "Entry ID in FileTrailer is required",
            "failedChecks": 1,
        }
    ]
    try:
        classify_case(failing, "tests/example/snapshot.pdf", 10)
    except ValidationError:
        pass
    else:
        raise SystemExit("Arlington case checker accepted an unrecorded failure")
    require(
        classify_case(failing, "tests/placeholder/snapshot.pdf", 10).startswith("recorded exception"),
        "recorded exception was not accepted",
    )
    changed = copy.deepcopy(failing)
    changed["report"]["jobs"][0]["arlingtonResult"][0]["details"]["ruleSummaries"][0]["testNumber"] = 12  # type: ignore[index]
    parser_failure = copy.deepcopy(failing)
    parser_failure["report"]["batchSummary"]["failedParsingJobs"] = 1  # type: ignore[index]
    for label, candidate in [
        ("stale exception", valid),
        ("changed exception", changed),
        ("exception with parser recovery", parser_failure),
    ]:
        try:
            classify_case(candidate, "tests/placeholder/snapshot.pdf", 10)
        except ValidationError:
            continue
        raise SystemExit(f"Arlington case checker accepted a {label}")

    ## Case collection is deterministic, distinct, and covers every recorded
    ## exception and the public examples.
    paths = case_paths()
    snapshots = [path for path in paths if not path.startswith("examples/")]
    examples = [path for path in paths if path.startswith("examples/")]
    require(paths == sorted(snapshots) + sorted(examples), "case order is not canonical")
    require(len(paths) == len(set(paths)), "case paths are not distinct")
    require(bool(examples), "no public examples collected")
    require(set(FIXTURE_EXCEPTIONS) <= set(paths), "an Arlington exception names no case file")
    print(
        f"PASS Arlington report checker self-test: {len(snapshots)} snapshots and "
        f"{len(examples)} examples collected"
    )


def run_cases(base_url: str) -> None:
    paths = case_paths()
    wait_ready(base_url)
    failures = 0
    exceptions = 0
    for relative in paths:
        pdf = ROOT / relative
        try:
            outcome = classify_case(request_report(base_url, pdf), relative, pdf.stat().st_size)
        except ValidationError as error:
            failures += 1
            print(f"FAIL Arlington 1.30.2: {error}")
            continue
        if outcome.startswith("recorded exception"):
            exceptions += 1
        print(f"PASS Arlington 1.30.2: {relative}, {outcome}")
    require(failures == 0, f"Arlington failed {failures} of {len(paths)} case files")
    print(
        f"PASS Arlington 1.30.2: {len(paths) - exceptions} case files compliant with zero "
        f"failed rules and checks; {exceptions} recorded exception(s) failed exactly as recorded"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="*", type=Path)
    parser.add_argument("--base-url", default="http://127.0.0.1:18080")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cases", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.cases:
        require(not args.pdf, "--cases takes no PDF paths")
        run_cases(args.base_url)
        return
    if not args.pdf:
        raise SystemExit("at least one PDF path is required")
    wait_ready(args.base_url)
    for pdf in args.pdf:
        report = request_report(args.base_url, pdf)
        passed_rules, passed_checks = validate_report(report, pdf.name, pdf.stat().st_size)
        print(
            f"PASS Arlington 1.30.2: {pdf}, "
            f"passed_rules={passed_rules}, passed_checks={passed_checks}"
        )


if __name__ == "__main__":
    try:
        main()
    except ValidationError as error:
        raise SystemExit(str(error)) from error
