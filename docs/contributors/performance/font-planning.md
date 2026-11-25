# text-layout deterministic font planning slice

This slice consumes `KernelFont.Inspection` facts without reparsing font bytes.
Content glyph use is accumulated in one dense marker list. Glyph zero is
retained only as the subset's required `.notdef` entry and is rejected if a run
attempts to use it as content. Duplicate use does not duplicate plan entries.

The inspection-stage component edges are already grouped by parent glyph.
Planning builds one dense parent-offset index over that retained flat list,
then follows only edges reachable from used glyphs. It does not copy component
edges or allocate a node per glyph/component. Composite closure is computed
once and fails transactionally if its explicit retained-glyph limit would be
exceeded.

Retained original glyph IDs are scanned in ascending order. That order defines
both subset glyph IDs and initial CIDs, with original glyph zero fixed at subset
glyph/CID zero but unavailable to content. Each entry retains its exact source
advance width and whether it was directly used or included only for composite
closure. The dense original-to-subset mapping is carried forward for glyph-data
rewriting and content lowering.

The six-letter subset-prefix candidate hashes the full inspected font digest
and ordered retained original glyph IDs. It is deterministic input to the
later document-level resource planner, which remains responsible for proving
name uniqueness across all subsets in one output.

## Validation

The focused fixture plans repeated `A` and `é` use, retains glyph zero and the
required composite dependencies, and visits only the selected closure after
indexing the component edges. The flat index must preserve linear work without
allocating a node per component.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
