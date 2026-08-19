# text-layout case-transformation output

This closes the case-transformation row of the text-layout extraction matrix: one
source-to-presentation transformation whose visible text differs from the
authored Unicode, positioned and shaped from the transformed presentation,
while `/ActualText` preserves the unchanged logical source.

## Dependency boundary

`roc-lang/unicode` 4.0.0 (`unicode-4.0.0-adoption.md`) supplies `Case`,
whose result carries the transformed text plus one ordered mapping fact per
input scalar (input range, output range, shape, contextual flag).
`package/KernelCaseTransform.roc` owns no case data. It requests
`Case.to_upper` under the explicit `unicode_default` profile with finite
budgets for input bytes and scalars, output bytes and scalars, and mapping
facts, then validates the returned facts locally before any later stage may
consume them:

- each fact covers exactly one input scalar, and the facts' input and output
  coordinates are contiguous and in order;
- the facts together partition the source and the output exactly, with no
  gap or overlap at either end;
- each fact's lengths agree with its declared shape — `Unchanged` keeps one
  output scalar and the same byte length, `Simple` keeps one output scalar,
  `Expanded` produces more than one, `Removed` produces none;
- the reported Unicode version is the pinned 17.0.0, and the profile
  revision is recorded rather than assumed.

Failure is transactional: no partial text or fact buffer escapes. The module
retains one transformed `Str` and one flat fact buffer; the source stays
owned by its occurrence and mapping records use scalar and byte coordinates
only, so no substring is retained.

## Lowering

The transformation lowers into plumbing that already existed:
`Semantics.SourceToPresentation { kind: CaseMapping, presentation, source }`
is the semantic text property, and one `Text.TransformationEvidence` per
resolved mapping carries that mapping's exact source range beside the glyphs
it produced, so later lowering never infers the relation from glyph IDs or
visible bytes. `KernelPdfText` is unchanged: a run with transformation
evidence already forces `/ActualText`, and that text is derived from the
occurrence source rather than from a second run-local string.

## Output slice

The fixture authors `aß` and requests full Unicode default uppercase. The
dependency resolves two facts — a `Simple` mapping `a` to `A` and an
`Expanded` mapping `ß` to `SS` — which the fixture asserts rather than
hard-codes; the presentation `ASS` is never written as a literal expectation
of the mapping itself. The built-in RocPdfSans face covers `A` and `S`, so
this row adds no font asset.

The advanced store keeps two clusters over the two source scalars: a
`OneToOne` cluster for `a` and a `OneToMany` cluster whose single source
scalar `ß` owns the expansion's two glyphs. The 8,875-byte snapshot paints
CIDs `0001 0002 0002`, carries `/ActualText <FEFF006100DF>` — exactly the
authored `aß` — and maps CID 1 to `a` and CID 2 to `ß`. The two identical
output scalars legitimately share one CID, so the per-CID map alone cannot
reconstruct the source, which is precisely why `/ActualText` is mandatory
for this row; `scripts/check_case_text.py` asserts both halves and
rejects four mutations. PDFBox 3.0.8 extracts `aß`, recovering the authored
source through `ActualText`. PDFBox and PDFium 72-dpi ink metrics are pinned
per engine in `check_text_renderers.py` (`--case`). The embedded sanitized
subset is 5,800 bytes, SHA-256
`aea5b021187971fd57d34562eae236065d1c77e466b7a47e31b0f00529681717`.

Registered positive work is
`[166300, 2, 2, 3, 1, 1, 2, 3, 2, 2, 1, 2, 2, 213, 20, 8875]` at 1,036
allocations: one 166,300-byte font payload, two mapping facts over two input
scalars producing three output scalars of which one mapping expanded, one run
of two clusters and three glyphs, two transformation visits, two source
scalars, one `ActualText` run of two scalars, two mappings, 213 prepared text
bytes, twenty objects.

The atomic negative proves two independent rejections: an output-scalar
budget too small for the expansion is rejected by `KernelCaseTransform` with
a typed limit error and no text, and a cluster whose cardinality contradicts
the resolved expansion (claiming the two-glyph expansion is `OneToOne`) is
rejected at advanced validation. Both fail before any scene, object plan, or
PDF exists; the fixture emits the standard 667-byte blank carrier with work
`[2, 667]` at 54 allocations.

## Boundary

This row covers the Unicode default uppercase profile only. Contextual final
sigma, Turkic and Lithuanian profiles, and titlecase word boundaries are
explicitly out of scope and remain future rows: `KernelCaseTransform` exposes
only `to_upper` under `unicode_default`, so no locale-sensitive behavior can
be requested and then silently ignored. The public facade does not request
case transformation; this is the advanced boundary.
