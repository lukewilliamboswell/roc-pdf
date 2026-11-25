# text-layout bounded GSUB ligature inspection

## Scope

This slice adds `KernelGsub.validate_ligature`, an internal typed boundary that
proves one declared GSUB Type-4 ligature substitution against an already
validated TrueType font. Its returned `Fact` retains the selected script,
language system, feature tag, lookup index, complete input glyph sequence, and
result glyph. `KernelShape.validate_advanced_with_ligature_fact` consumes that
fact before an advanced ligature run can cross the shaping boundary; it does
not infer a substitution from a cluster kind, a glyph ID, or a raw `GSUB`
directory name. The resulting run's validated output glyph then remains the
ordinary input to deterministic font planning and subsetting.

The accepted subset is deliberately narrow: GSUB 1.0 script/language/feature
selection, direct Type-4 lookups, and ExtensionSubst lookups that resolve to
Type-4. Every relative offset, feature/lookup index, coverage record,
ligature-set record, component count, and glyph ID is bounds checked. Other
lookup types are only skipped while resolving the selected feature; they are
not interpreted as ligatures.

## Evidence boundary

`GsubEvidence` validates the built-in face's `latn` default language
system, `ccmp` feature, lookup 4, and exact glyph sequence `A` plus U+0300 to
glyph 5. The fixture asserts the complete typed fact and deterministic work:

```text
lookup=4, feature-indices=2, language-system feature-indices=37,
lookup records=2, subtable records=2, coverage records=61,
ligature records=23, component reads=19
```

Its atomic negatives prove that a wrong declared output glyph returns
`OutputMismatch` and that a corrupt GSUB version returns
`UnsupportedGsubVersion`. Both fail at the inspection boundary, before an
advanced run, scene, object plan, or PDF bytes can exist.

The shaping evidence also proves that the retained fact is consumed: the valid
fact accepts its matching `Ligature` cluster, while changing only its output
glyph rejects that otherwise-valid advanced store before downstream planning.

`RocPdfSans-Regular.ttf` has no `fi` `liga` mapping. Consequently this slice
does not emit an `fi` PDF, does not manufacture a ligature glyph, and does not
claim the ligature matrix row. That output slice remains blocked on a
manifest-recorded fixture face containing the exact `f`, `i`, and `fi` mapping
with a regenerable provenance recipe.

## Performance and ownership review

The validated font resource remains one immutable `List(U8)` retained by
`KernelFont.Inspection`; GSUB inspection takes bounded offsets into that list
and returns only scalar IDs plus the caller's glyph sequence. It does not copy
the GSUB table, create a per-glyph map, cache a closure, or alter existing font
inspection work/allocation baselines. The selected lookup is scanned with
direct indexed loops. Work is bounded by the selected language-system feature
indices, selected feature lookup indices/subtables, one coverage table, the
selected ligature set, and its component glyphs; each dimension has an explicit
limit. Failure returns no partially constructed `Fact`.

This is inspection-only and introduces no executable PDF scenario, so no new
PDF snapshot, renderer/extraction oracle, or allocation baseline is claimed.
The focused existing dev-backend allocation case remains unchanged; a future
output-facing `fi` slice must add its own exact dev allocation record together
with structural, extraction, rendering, provenance, and atomic-negative
evidence.
