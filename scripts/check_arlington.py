#!/usr/bin/env python3

import argparse
import copy
import json
import time
import urllib.error
import urllib.request
from pathlib import Path


EXPECTED_PROFILE = "Arlington PDF 2.0 profile"
EXPECTED_RELEASES = {
    "core-arlington": "1.30.2",
    "validation-model-arlington": "1.30.2",
    "verapdf-rest-arlington": "1.30.2",
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
    print("PASS Arlington report checker self-test")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", nargs="*", type=Path)
    parser.add_argument("--base-url", default="http://127.0.0.1:18080")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
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
