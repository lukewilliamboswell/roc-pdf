# Gate 3 sanitized TrueType subsetting slice

This slice consumes the sealed `KernelFont.Inspection` and
`KernelFontPlan.Plan` facts. It does not reparse glyph semantics, infer use from
serialized content, or accept caller-selected PDF object identities.

Retained glyphs are copied once in ascending original-glyph order. Composite
component IDs are rewritten at the validated component offsets recorded by the
inspection stage. The subset uses long `loca` offsets and one explicit long
horizontal metric per retained glyph. Glyph zero remains the required
`.notdef` entry but is absent from the rebuilt Unicode mapping.

The writer constructs a fresh, deterministic sfnt from an allowlist. It emits
rewritten `cmap`, `glyf`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name`, and
minimal format-3 `post` tables and retains the inspected face's `OS/2`, `cvt `,
`fpgm`, `gasp`, and `prep` tables for the initial hinted TrueType policy. GSUB,
GPOS, GDEF, private, color, and variation tables do not enter the subset.
Directory table order is fixed, every table checksum is rebuilt, and
`checkSumAdjustment` is computed over the completed font.

The format-12 `cmap` is emitted from one contiguous group-byte buffer. The sfnt
directory is planned by bounded passes over a fixed 14-table list, sizes the
result before emission, and appends every payload once. The original font byte
resource remains shared through glyph copying; inspection does not duplicate
it.

## Historical optimized-backend evidence (superseded)

The speed-backend table is retained for its historical subset-representation
review only. It is not a current allocation baseline; use the matching exact
dev-backend scenario in [`tests/spec.json`](../../tests/spec.json), whose mode
transition is reviewed in [the dev-backend rebaseline](dev-backend-allocation-rebaseline-2026-08-09.md).

The built-in face is planned for `A`, `é`, and a duplicate `A` use. Composite
closure produces five glyphs and rewrites two component references. The fresh
5,864-byte font has SHA-256
`356a2888232437badd8417cc4f4043aed7d6214fb54010171e33d0f25aa3a409`.

| Target | Optimization | Retained glyphs | Source glyph bytes | Composite rewrites | Cmap mappings | Subset bytes | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 5 | 992 | 2 | 2 | 5,864 | 104 |
| x64musl | speed | 5 | 992 | 2 | 2 | 5,864 | 104 |

The x64musl row is the accepted same-compiler expectation and is exercised by
the configured cross-target job.

The raw font-program fixture was also checked independently with fontTools
4.61.1 in checksum-verifying mode. It reports the expected five-glyph closure,
`U+0041` and `U+00E9` mappings, metrics, `loca` offsets, subset-prefixed names,
and no checksum failures. The raw bytes were also independently reinspected by
the Roc font inspector under five-glyph, 16-table, and bounded-cmap limits.

This slice does not yet claim arbitrary unhinted TrueType input, shaping, PDF
Type 0/CID font objects, extraction mappings, or Gate 3 closure. Those remain
dependent slices.
