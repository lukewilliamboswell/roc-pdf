# Gate 1 Arlington object-model validation

## Checker pin and scope

Linux CI runs the official veraPDF Arlington service version 1.30.2 from the
immutable image
`verapdf/arlington@sha256:1543368902c393771557e2a1da69e64ad72b69db32e6efebd38a09a7b86eacbc`.
The report parser requires the `core-arlington`, `validation-model-arlington`,
and `verapdf-rest-arlington` components all to identify themselves as 1.30.2
and explicitly requests the `arlington2.0` profile.

Arlington checks the PDF object model derived from ISO 32000-2:2020. Its own
documented limitations exclude lexical dialect rules, content-stream operators
and operands, and file-layout rules such as xref data, incremental updates, and
linearization. The independent structural checker, qpdf, and the pending strict
parser lane remain separate evidence for those claims. Arlington is not treated
as the source of truth or as a repair step.

## Enforced report contract

`scripts/check_arlington.py` posts each original snapshot without rewriting it
and rejects a report unless:

- the pinned component versions and PDF 2.0 profile match exactly;
- the service reports normal completion and profile compliance;
- at least one rule and object check ran;
- failed rules, failed checks, rule summaries, parser failures, encrypted-file
  failures, exceptions, out-of-memory jobs, non-compliant jobs, and failed jobs
  are all zero; and
- the report names the submitted file and exact byte length.

The parser has negative self-tests for non-compliance, a failed object check,
parser failure, and validator version drift. HTTP success alone is never
accepted as conformance evidence.

## Gate 1 results

All five structural snapshots report 9,022 passed rules and zero failures. The
blank, unchanged-resource, one-block DEFLATE, and five-block DEFLATE snapshots
each execute 246 object checks. The 4,096-page snapshot executes 359,415 object
checks. Every job ends normally with no parser recovery or exception.

The image digest, profile, report contract, input snapshots, and expected zero-
failure result are part of CI. A validator upgrade requires an explicit pin and
evidence review rather than following `latest`.
