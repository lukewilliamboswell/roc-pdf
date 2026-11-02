# rc4 and public API integration

This record tracks the integration of the open library, example and publication
work reviewed against `dc17df46c12ca7a139208667cd0ded0a9106132a`.
It is not a capability-closure claim until final validation below is complete.

## Changes and evidence boundaries

- #71 replaces inspection-string classification with typed stage conversions.
  Existing feature identities are explicit; nested budget causes determine the
  category, including record-held causes. Debug text is bounded detail only.
- #72 rejects incomplete or inconsistent figure report facts. Scalar checks
  validate scale cardinality and dense figure identities before materialization;
  empty authoring retains its one-page report.
- #74 names public argument roles while preserving consuming receivers.
  Equality/comparison hooks retain their compiler-required signatures. This
  refactor is intended to preserve successful document bytes.
- #73 passes font-validation limits explicitly and retains registration errors.
- #69/#75 migrate exact static bytes and family/style selection. This deliberate
  typography change requires its own layout, extraction, rendering, allocation,
  work and retention review; API-only expectations do not approve its deltas.
- #40 preserves independent product validation while adding native manual
  publication, exact-commit reusable checks and artifact-only release upload.

## Toolchain

The package pin remains `nightly-2026-10-28-bad769b`. Local validation uses that
exact compiler and Zig 0.16.0. Shared documentation tooling is an independently
digest-verified executable and does not replace the package compiler pin.

## Intermediate validation

The first public API compile identified five old positional range constructors
in font-owned code. Initial affected harness runs were blocked by the
prepared-vector adapter's source digest changing after the named-argument
migration, followed by incomplete family-selection branches during concurrent
integration. A direct compiler test crashed during that incomplete state.
These runs do not establish successful validation, and no snapshot or allocation
baseline was accepted from them. Logs remain in the ignored local harness log
directory; final reproducible evidence must supersede them.

The first complete native harness attempt passed all existing checker
self-tests, then stopped at the module inventory because the new typed failure
module was missing from the repository-only package export list. The export
was added; no case snapshots or performance evidence were accepted by that run.

A preliminary bundle of the integrated source contained 104 members,
10,117,080 uncompressed bytes and 3,971,839 compressed bytes. It fits the pinned
compiler's default 10 MiB package limit without an override. The final bundle
consumer must recheck this bound after the remaining changes.

The drawing-label missing-glyph witness changes from U+0180 to U+A7B0:
rc4 Inter contains U+0180 (glyph 579), so retaining it as a negative would
incorrectly reject newly supported coverage. U+A7B0 is a single Latin scalar
absent from that exact static face. Its exclusion remains explicit under the
per-face coverage policy and the existing upstream coverage tracker
[roc-font #13](https://github.com/lukewilliamboswell/roc-font/issues/13).

Independent review found that the original subset writer cleared `post` angle
and fixed-pitch metadata, while the facade supplied upright descriptor defaults
for every face. The correction retains validated source style facts through
subsetting and lowering. Exact signed 16.16 angles use a separate bounded
numeric primitive; the existing decimal precision contract is unchanged.
The private font identity recipe advances to version 2 because its angle field
now explicitly represents raw 16.16 units. Consequently, even otherwise
unchanged upright font resources may receive different canonical identities;
this is an intentional representation migration, not a layout change.

The descriptor oracle first reproduced the cleared-angle defect on an Inter
Italic subset, then was extended to compare exact source/subset angles,
fixed-pitch fields and descriptor flags. Preliminary new-fixture metrics showed
constant five packaged inspections and 1,964,376 registered input bytes from
10 to 100 sections, with zero input-byte copies and linear inline/source visits.
These preliminary figures do not establish final allocation baselines; both
targets are measured again after the metadata correction.

The complete fixture run also caught a lost source-face diagnostic: the new
resolver rejected an explicit face absent from the original caller registry as
an unlocated resource error. A typed `UnknownSourceFace` now carries its source
group and face through the facade, preserving the documented `source.face`
feature and authored path before any packaged faces are appended. The existing
source-block negative assertions remain intact. This changes the bundle source
identity and requires rebuilding the publication consumers; it does not change
successful document rendering.

## Independent review and additional tooling

The requested style review used the author's
[typed design and API notes](https://gist.github.com/lukewilliamboswell/241a4e8adb7c89c7e0e02f1d303a8fa1).
It found a drawing diagnostic that lost its requesting owner, ambiguous private
configuration arguments and a structural public family configuration. The
integration fixes all three and adds located figure/panel regressions. Public
family configuration is nominal; consuming receivers and compiler-required
comparison signatures retain their established form.

The initial [roc-fuzz review](roc-fuzz-0.4.5.md) adopted compatible 0.4.5
and preserved corpus interpretation. The subsequently requested
[complete supervised-runner migration](roc-fuzz-0.5.0.md) implements the new
codecs, declared examples, report guards and explicit per-host baselines. All
nine native and Linux smokes pass. All ten profiling workloads preserve their
previous allocation-event totals and PDF fingerprints; 75 retained corpus
records preserve their interpretation.

## Final validation

The seven new default-family cases passed strict native and Linux checks,
including exact matching PDF bytes, allocation counts, allocated bytes and work.
[Their evidence](performance/default-fonts.md) includes genuine style metadata,
all ten packaged programs, atomic diagnostics and a 10/100-section scale pair.
The public gallery and extracted examples passed all fourteen applications;
[publication evidence](automation-publication.md) records independent manual
PDF/A-4 validation and the final default-size-cap bundle consumer.

The complete fixture set now has 425 successful measurements on each target,
with identical PDFs, allocations, allocated bytes and work vectors. The
[existing-fixture causal review](performance/rc4-existing-fixtures.md) records
metadata controls, all 96 complete scale groups, runtime inspection costs,
sharing/retention and corrected work-probe boundaries. Its
[retained before/after record](performance/rc4-baseline-review.json) accounts
for 254 changed metric vectors and 171 unchanged vectors. Generated provenance
pins all 160 deliberately changed PDF snapshots; byte guards remain at 10%.

Independent veraPDF 1.30.2 checks passed 206 Archive snapshots and 139 Standard
snapshots with only documented omissions/negative exceptions. The upstream
corpus produced the correct verdict on 129 pass and 358 fail files, including
326 failures in their named clause and no recorded exceptions. Arlington
checked 345 snapshots plus 14 public examples: 358 were compliant and the
placeholder failed exactly its recorded rule. The three repaired rich-inline
and source-negative PDFs then passed PDF/A-4 and Arlington again.

The full strict native invocation completed successfully on 2026-10-29:
46 source-validation tasks (including formatting of 315 files), 13 fresh fixture
builds and all 425 cases passed with allocation/byte/work guards enabled. The
strict Linux 425-case step and its public bundle consumer also passed at
`57666af850682277e4eeab7c824ffc6172793617` in the
[recorded Linux job](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/40829868219/job/123301442361).

Final acceptance is the full strict native invocation
`./scripts/test.py --allocation-baselines --jobs 3` and the checks bound to the
latest source revision on [PR #76](https://github.com/lukewilliamboswell/roc-pdf/pull/76).
Those checks include the Linux strict suite, fuzz execution, independent
conformance, manual/API builds and release artifact consumers. A skipped job or
failed aggregate does not satisfy closure. The PR is kept draft until the
applicable checks are successful; no release or site publication is performed.

## Documentation and fuzz follow-up

The requested [documentation refactor](documentation-refactor.md) replaces the
Markdown converter with authored AsciiDoc chapters, keeps existing reader
routes and source links, and makes evergreen README/guide text release-neutral.
The verified released renderer builds the native book on both supported hosts;
the Linux and macOS manual PDFs are byte-identical. Fresh source, browser,
Markdown, PDF, API and artifact-binding evidence is retained separately from
the earlier candidates.

The combined refactor passed `./scripts/test.py --allocation-baselines --jobs 2`
on 2026-10-29: 45 source-validation tasks, 13 fresh fixture executables and all
425 strict cases. Production package code, the compiler pin and every product
allocation/byte/work baseline remain unchanged by this follow-up. Independent
review verified the new report/baseline guards and profiler build identities;
there are no remaining blocking findings.

## 2026-11-02 triage follow-up

The final style review fixes the obsolete positional `Pdf.expansion` example
and gives all six typed-failure regressions `##` names and labelled comparisons.
`KernelBuiltInFonts` now owns the packaged face count, canonical family/style
mapping, opaque bounded slots and byte selection. The resolver consumes those
facts instead of maintaining its own numeric mapping. Structural family/style
input keeps the asset module independent of its `Font` caller. Numeric indexes
remain private dense-storage facts; the opaque slot adds no payload ownership,
resource acquisition or per-content allocation. A unit witness checks all ten
selections against exact source bytes and canonical dense replay. Existing
unavailable-style fixtures still reject before slot construction.

The downstream scope is corrected against roc-automation #98's current
2026-11-02 description: it owns the inline-code Command-symbol defect and
explicitly excludes a general migration project. Local #69 closure covers
style-role support, not downstream adoption. The earlier candidate bundle,
source/digest pins and migration checks remain in the
[retained proposal](roc-font.md#retained-migration-proposal) as historical evidence.
Architecture and roadmap wording reflect this boundary.

Validation on Linux x86-64 used Roc `nightly-2026-10-28-bad769b`, the dev backend
and Zig 0.16.0 ReleaseFast test hosts:

- `./scripts/test.py --allocation-baselines --jobs 3` passed all 46 source
  validation tasks, including 686 package expects and all public examples,
  all 13 fresh fixture builds and all 425 cases.
- Exact comparison of every case's logged measurements with the `x64musl`
  expectations found zero allocation-count, allocated-byte or work-vector
  differences. Every PDF snapshot matched; no baseline, snapshot or guard
  was changed.
- `python3 scripts/test_bundle_consumer.py` passed with the isolated served
  bundle, private-import rejection and independent facade-output checks.
- `bash scripts/docs.sh` passed using the locked tools-0.8.0 renderer and
  pinned API compiler. The unreleased manual has 10 pages and 27 exact source
  blocks; links, Markdown, source/asset digests, PDFBox extraction, tagged
  tables, exact RGB figures and the private-type audit passed.

The required CI checks rerun against the pushed commit. This follow-up makes
no new font, shaping or conformance claim.
