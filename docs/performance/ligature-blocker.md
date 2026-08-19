# text-layout ligature-output dependency audit

## Chosen slice and evidence boundary

The next smallest text-layout text-matrix slice would be one end-to-end Latin
ligature: the logical source `fi`, a validated `liga` substitution to one
painted glyph, the exact two-scalar cluster range, a complete one-CID
`ToUnicode` mapping, and `/ActualText` only if the typed presentation facts
require it. Its evidence would include the original-byte PDF structure,
independent PDFBox extraction, independent PDFBox/PDFium rendering, a
deterministic work record, an exact dev-backend allocation baseline, a snapshot,
asset provenance, and an atomic malformed-substitution negative.

That slice is blocked before implementation. It must not be approximated by
assigning an arbitrary glyph ID to a `Ligature` cluster or by treating a raw
font-table name as proof of an OpenType substitution.

## Audit

`vendor/fonts/RocPdfSans-Regular.ttf` does contain a raw `GSUB` directory
entry. Its deterministic builder asks fontTools to retain layout features, so
it is a plausible future fixture source. That is not a validated GSUB boundary:

- `KernelFont.Inspection` validates the sfnt directory, ranges, checksums,
  `cmap`, glyph outlines, metrics, names, and embedding rights, but retains no
  parsed GSUB script, language-system, feature, lookup, coverage, or ligature
  records.
- `KernelShape.validate_advanced` proves only supplied run/cluster/glyph
  partitions and cardinalities. It cannot prove that a proposed `liga`
  substitution is present in the selected face or that the output glyph is the
  lookup result.
- `KernelFontSubset` deliberately omits `GSUB`, `GPOS`, and `GDEF` from the
  sanitized subset. Consequently an emitted PDF cannot be claimed to preserve
  a validated source feature table merely because a manually supplied glyph
  happens to render.

The existing caller fixture is not an alternative: its generator uses
`layout_features = []` and its scalar selection contains `f` but not `i`.
Although its tiny raw GSUB table is retained by fontTools, it cannot establish
an `fi` ligature mapping. The existing `ShapeEvidence` value called
`Ligature` is an `A` plus U+0300 `ccmp` composition carrier that emits a blank
PDF; it is validation-kernel evidence, not ligature output evidence.

## Required prerequisite

The narrowly scoped dependency is a bounded, typed GSUB ligature-substitution
inspection and validation boundary. It must retain the selected script/language
system, feature tag, lookup, input glyph sequence, and resulting glyph as
facts consumed by advanced-run construction and deterministic subsetting. A
fixture then needs a manifest-recorded font with the exact `f`, `i`, and
ligature glyph coverage, a parsed-and-validated `liga` mapping, and a
regenerable provenance recipe. The atomic negative must make that declared
lookup or output-glyph relationship invalid and fail before scene/object
planning with no PDF bytes.

Only after that prerequisite exists can the proposed output slice establish the
required source/cluster mapping, PDF mapping, render/extraction, work, and
dev-backend allocation evidence. This record does not close text-layout or broaden
font/shaping support.
