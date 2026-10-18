# text-layout case-transformation output dependency audit

## Chosen slice and evidence boundary

The missing text-layout extraction-matrix row is one source-to-presentation case
transformation whose visible text differs from authored Unicode: an explicit
full Unicode uppercase mapping, positioned and shaped from the transformed
presentation, while `/ActualText` preserves the unchanged logical source. The
smallest useful positive case must exercise a mapping that is not a scalar
identity and must carry an exact source/output range relationship. U+00DF
(`ß`) to `SS` is a suitable future expansion case; it is not permission to
hard-code that one mapping.

The eventual case needs a version-pinned Unicode mapping policy, compact
source-to-presentation facts, a caller or packaged face that covers the exact
presentation scalars, an exact snapshot and dev-backend allocation baseline,
deterministic transformation/shaping/layout work counters, direct
CID/`ToUnicode`/`ActualText` inspection, PDFBox extraction, separately pinned
PDFBox/PDFium raster facts, and an atomic invalid mapping-fact or output-limit
negative that emits no PDF. It must additionally cover the mapping's source
range in the `Text.TransformationEvidence` record so later PDF lowering never
infers it from glyph IDs or visible bytes.

This audit implements no output and does not claim case mapping support or Gate
3 closure. A manually authored `CaseMapping` tag, an ASCII-only conversion,
or a fixture-specific `ß -> SS` table would only make the presentation appear
to work; none proves the required Unicode source relationship.

## Current local boundary

The pinned dependency is `roc-lang/unicode` 3.0.0, resolved by this package to
source revision `f5cd8d6a9a345f0a589ed46625ee865e70f48e35`. Its public surface
used by `KernelUnicode` supplies Unicode 17.0.0 scalar iteration, grapheme
ranges, UAX #14 boundaries, scripts and script itemization. A source audit of
that release finds no public case-conversion or case-folding module, no
generated `UnicodeData.txt`/`SpecialCasing.txt`/`CaseFolding.txt` mapping data,
no locale policy, no title word-boundary input, and no transformed-text result
that maps output byte/scalar spans back to input byte/scalar spans.

The local pipeline already has the correct *consumer* boundary but not a
producer:

- `Semantics.PresentationTransformation.CaseMapping` distinguishes case
  presentation from source Unicode.
- `Semantics.SourceToPresentation` carries a presentation string and exact
  source range; `Text.TransformationEvidence` connects it to painted glyphs.
- `KernelShape.validate_advanced` checks only that supplied ranges and glyph
  ranges are bounded and contained. It cannot validate that a supplied string
  is a correct Unicode case result.
- `KernelPdfText` requires `/ActualText` whenever a run has transformation
  evidence, but it deliberately derives that text from the occurrence source,
  not a second run-local string.

Those local facts make a hand-authored presentation claim serializable; they
do not make it an honest case-transformation result. Implementing the mapping
locally would duplicate the Unicode-data dependency and evade the package's
version/provenance and reusable-boundary policy.

## Required upstream and local handoff

[`roc-lang/unicode#52`](https://github.com/roc-lang/unicode/issues/52) defines
the prerequisite: Unicode 17 default full lower/upper/title mapping and case
folding with explicit locale policy, explicit title word boundaries, no
implicit normalization, checked limits, deterministic generation provenance,
and ordered source/output byte-and-scalar range facts. In particular, expansion
(`ß`), contextual final sigma, Turkic and Lithuanian policy, combining-mark
context, and titlecase rules show why scalar replacement is insufficient.

After that package is released, adoption is a separate reviewed slice:

1. Pin the exact Unicode release archive, source revision, digest, Unicode-data
   provenance, and any new policy/API revision; do not float a dependency.
2. Lower the returned compact mapping records into the existing semantic
   `SourceToPresentation` and shaped-run transformation buffers without
   retaining source substrings or reconstructing ranges from glyphs.
3. Validate complete source coverage, sorted scalar-aligned ranges, selected
   policy, transformed-output limits, and face coverage before layout. A
   requested unsupported locale/policy, malformed mapping, limit crossing, or
   uncovered presentation scalar is a typed failure with no PDF bytes.
4. Add the U+00DF expansion fixture plus policy/contextual and atomic-negative
   cases. Verify source logical extraction, transformed visual glyphs, CID and
   `ToUnicode` rows, required `/ActualText`, deterministic work, ownership,
   and dev-backend allocation evidence. Expansion, contextual, and titlecase
   cases need independent rows; the first output fixture does not close the
   complete Unicode case-mapping surface.

The transformation result should own its one transformed UTF-8 allocation and
flat mapping buffer. The source remains owned once by the occurrence store;
mapping records use scalar and byte coordinates only. The planned whole-input
scan and output emission are `O(n + output)` with explicit input, output, and
mapping limits. No test command is applicable to this documentation-only audit;
the required executable evidence begins with the dependency-valid adoption
slice and uses `./scripts/test.py`'s default dev backend.

## Closing pointer (2026-08-14)

This dependency audit is closed. `roc-lang/unicode` 4.0.0 shipped the
version-pinned full case mapping with source-to-output range facts this
document required, and the resulting adoption — `KernelCaseTransform` with
its local coverage, ordering, and shape validation, the lowering into the
existing `SourceToPresentation`/`TransformationEvidence` plumbing, and the
registered `aß` expansion fixture with its atomic negatives — is recorded in
[`case-transformation.md`](case-transformation.md). Contextual
sigma, Turkic and Lithuanian profiles, and titlecase remain future rows, as
this audit anticipated.
