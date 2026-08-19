# text-layout closure review

## Outcome

The searchable-international-text and useful-layout capability is complete. This is
the first genuinely useful public document milestone: `Pdf.document` plus
`Pdf.to_bytes`, `Pdf.to_bytes_with`, and `Pdf.to_chunks_with` produce
deterministic tagged PDF 2.0 output with embedded subset fonts, complete
extraction mappings, and single-column pagination under the `Standard`
profile, from either the packaged face or caller-registered faces selected by
`Theme` — including a finite ordered multi-face policy with per-cluster
coverage selection.

What remains unavailable is unchanged and still fails transactionally rather
than degrading: `Archive` and `AccessibleArchive` return capability errors and
are never silently downgraded; production-visual graphics (form XObjects, transparency,
soft masks) are not present; automatic hyphenation is not accepted, so no
language pattern set is claimed; and shaping beyond the declared boundary is a
typed rejection, never a substituted font, outlined text, or rasterized
fallback. The convenience shaping path's declared script set is `{Latn, Hani}`
and the public facade remains left-to-right; right-to-left and
case-transformation output are advanced-boundary capabilities with their own
fixtures.

## Capability and evidence aggregation

| text-layout boundary | Implementation and focused evidence |
| --- | --- |
| Bounds-checked TrueType parsing, identity, metrics, widths, embedding rights, instances | `KernelFont`, `font-inspection.md`, `font-subsetting.md` |
| Deterministic font planning, coverage, script, language, instance selection | `KernelFontPlan`, `Font.Registry.plan`, `font-planning.md`, `multiface-font-selection.md` |
| Type 0 fonts, CID descendants, embedded programs, whole-font-to-subset, composite closure | `KernelPdfFont`, `KernelFontSubset`, `KernelFontObjects`, `pdf-font-objects.md`, `font-subsetting.md` |
| Positioned glyph runs carrying source Unicode, clusters, language, script, direction, advances, transformations | `KernelShape`, `Text`, `shaping.md`, `logical-physical-runs.md` |
| `ToUnicode` CMaps and explicit `ActualText` where mappings are context-dependent | `KernelPdfText`, `actual-text.md`, `visible-text.md` |
| Combining marks, supplementary plane, CJK subsets, ligatures | `combining-text.md`, `supplementary-text.md`, `cjk-text.md`, `fi-ligature.md` |
| Real UAX #9 right-to-left output with mixed span and mirroring | `KernelBidiBoundary`, `KernelShape.validate_advanced_with_bidi_order`, `rtl-text.md` |
| Case-transformation output with source-range facts | `KernelCaseTransform`, `case-transformation.md` |
| Soft and discretionary hyphen extraction | `KernelDiscretionaryHyphen`, `soft-hyphen.md` |
| Generated list labels | `generated-labels.md` |
| Pinned UAX #9/#14/#29 data and project boundary vectors | `conformance/normative-baseline.json`, `uax-boundary-vectors.md`, `rtl-text.md`, `unicode-4.0.0-adoption.md` |
| One-import authoring, built-in theme, pagination, `Standard` default | `Pdf`, `KernelFacadePipeline`, `public-pdf-facade.md`, `facade-output-oracles.md` |
| Byte-identical buffered and chunked delivery for authored documents | `Pdf.to_chunks_with`, `KernelEmit`, `chunked-facade-output.md` |
| Public caller-resource path: registration, opaque faces, `Theme` selection, ordered policy | `Font.Registry`, `Theme.with_font`, `Theme.with_font_policy`, `caller-font-facade.md`, `multiface-public-facade.md` |
| Bounded caches for parsing, coverage, selection, shaping, measurement; hyphenation inapplicable | `cache-closure.md` |
| Retention across shared versus deliberately unique caller inputs | `caller-font-retention.md`, `multiface-public-facade.md` |
| Adversarial paragraph, line-break, font-selection, shaping, pagination bounds | `authoring-normalization.md`, `line-layout.md`, `page-layout.md`, `facade-*.md`, `multiface-public-facade.md` |
| Independent extraction and rendering oracles | `scripts/check_*.py`, PDFBox 3.0.8, PDFium Chromium 7988, qpdf 12.3.2 |

## Retained fixture statistics

The public authored facade fixture is 12,397 bytes with SHA-256
`8723c2d6ea86a67205f9fc3a5f1ec18acb955af0f259842be2234753d4d4559f` at 1,423
allocations. Its chunked twin produces byte-identical output in 32
plan-derived chunks whose largest is 8,692 bytes, under both the
shared-resource and owned-chunk retention modes, at 2,845 allocations.

The public ordered multi-face fixture is 11,416 bytes at 1,711 allocations,
carrying two dense font resources, two sanitized subsets (5,960 and 940
bytes), and per-font `ToUnicode` rows. Its shared-registry retention mode
authors two complete documents from one registry with 9,920 retained bytes
and zero copied registry bytes; the unique-registries control doubles every
ownership dimension to 19,840 bytes and 4 faces while producing identical
output.

The resolved right-to-left fixture is 7,891 bytes at 1,181 allocations: 14
CIDs painted in the normative visual order `12 13 11 10 9 7 8 6 5 4 3 2 1 0`,
four mirrored brackets, one `ActualText` run of 14 logical scalars, and a
4,380-byte sanitized subset. The case-transformation fixture is 8,875 bytes
at 1,036 allocations: two mapping facts over two source scalars producing
three output scalars, one of which expanded.

The ordered-selection scale fixtures hold their declared bounds at x1000 and
x10000 with exact linearity: worst-case alternating registry selection
records `face_visits = 1.5N` against the `N x policy_len` bound and
`coverage_span_visits = 4N` against `N x total_spans`, while the facade path
plans, shapes, and measures once per unique interned source
(`planned_sources = 1`, `metric_reads = 3`, one line template with
`cache_hits = N-1`) and selects exactly two fonts at either scale.

## Stage and public-boundary audit

Every later stage consumes facts from its predecessor rather than inferring
them. Font selection consumes segmented grapheme clusters and pinned script
itemization, never re-decoding UTF-8; shaping consumes the planner's exact
`FaceRange` and dense instance identity, never re-running coverage; line
layout consumes shaped clusters and UAX #14 boundaries, never reconstructing
clusters from text; text materialization consumes selected lines and splits
paint runs at face boundaries from the recorded physical ranges; PDF lowering
resolves each run's dense instance to its own plan, subset, and resource name
without re-deriving a font from glyph IDs; and reading order stays separate
from paint order throughout — the right-to-left slice keeps logical source
ranges beside the resolved visual sequence, and `ToUnicode` and `ActualText`
are derived from the occurrence source, never from the painted order.

Unsupported requests remain typed rejections that emit no PDF bytes:
restricted embedding rights, unsupported font programs, missing glyphs,
`.notdef`, invalid clusters, uncovered scalars, undeclared scripts, unknown or
built-in-source policies, mismatched bidi facts, unmirrored brackets, case
budgets, and unsupported authoring content each have a registered atomic
negative.

production-visual may now build on this closed boundary.
