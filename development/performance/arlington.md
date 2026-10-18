# structural-kernel Arlington object-model validation

## Checker pin and scope

The `arlington` Linux CI job runs the official veraPDF Arlington service
version 1.30.2 as a service container from the immutable image
`verapdf/arlington@sha256:1543368902c393771557e2a1da69e64ad72b69db32e6efebd38a09a7b86eacbc`.
The report parser requires the `core-arlington`, `validation-model-arlington`,
and `verapdf-rest-arlington` components all to identify themselves as 1.30.2
and explicitly requests the `arlington2.0` profile.

Arlington checks the PDF object model derived from ISO 32000-2:2020. Its own
documented limitations exclude lexical dialect rules, content-stream operators
and operands, and file-layout rules such as xref data, incremental updates, and
linearization. The independent structural checker, qpdf, and strict PDFBox
parser lane remain separate evidence for those claims. Arlington is not treated
as the source of truth or as a repair step.

## Enforced report contract

`scripts/check_arlington.py` posts each original file without rewriting it
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

## Case lane

`scripts/check_arlington.py --cases` validates every distinct non-empty
snapshot referenced by `tests/spec.json` and every public example in
`examples/*/*.pdf`. Zero-byte snapshots are negative cases that deliberately emit
no bytes. The only permitted failure is an explicit, reasoned entry in
`FIXTURE_EXCEPTIONS`, and that file must fail exactly its recorded rule set; an
exception that starts passing, fails a different rule, or hits a parser
failure is itself an error. The single exception is
`tests/placeholder/snapshot.pdf`, a fixed classic-xref PDF written by the test
platform rather than package output, which has no trailer `/ID`
(`FileTrailer-ID#11`).

The `--self-test` stays offline: it adds synthetic checks that a clean case
passes, an unrecorded failure is rejected, a recorded exception is accepted
only when it fails exactly as recorded, and that case collection is
deterministic and distinct and covers every exception.

CI runs the lane in the `arlington` job after the Linux test job has proven
that the committed snapshots are exactly the package output. Service
containers need a Linux runner, so macOS does not run it.

## structural-kernel results

All five structural snapshots report 9,022 passed rules and zero failures. The
blank, unchanged-resource, one-block DEFLATE, and five-block DEFLATE snapshots
each execute 246 object checks. The 4,096-page snapshot executes 359,415 object
checks. Every job ends normally with no parser recovery or exception.

These structural results were recorded when the checker was pinned, and CI
then ran it over those five Gate 1 snapshots. That step was removed when CI
was trimmed to public smoke tests (commit `3605516`), after which no CI job
ran Arlington, despite this record, until the case lane below was added.

## Case lane results

When the case lane was added, it collected 157 snapshots and 9 gallery
examples. Before the `CIDSystemInfo` correction, 55 of them failed exactly
`CIDSystemInfo-Registry#8` and `CIDSystemInfo-Ordering#8` (every font-bearing
file), and the placeholder failed `FileTrailer-ID#11`. After the correction,
all 165 package files report zero failed rules and checks (1,488,630 passed
rules and 798,668 object checks in total), and the placeholder fails exactly
its recorded rule. See [cid-system-info-ascii.md](cid-system-info-ascii.md).

The image digest, profile, report contract, input set, exception map, and
expected zero-failure result are part of CI. A validator upgrade requires an
explicit pin and evidence review rather than following `latest`.
