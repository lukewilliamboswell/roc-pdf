# Gate 3 deterministic font planning slice

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

## Historical optimized-backend evidence (superseded)

The speed-backend table remains as historical evidence for rejecting the
adjacency-copy representation. It is not a current allocation baseline; the
matching exact dev-backend expectation is in
[`tests/spec.json`](../../tests/spec.json) and its reviewed mode transition is
recorded in [the dev-backend rebaseline](dev-backend-allocation-rebaseline-2026-08-09.md).

The retained built-in face is planned for `A`, `é`, and a duplicate `A` use.
The plan retains five glyphs including glyph zero and two composite
dependencies. It scans all component edges once to build scalar offsets and
visits only the two edges in the selected closure.

| Target | Optimization | Font glyphs | Component edges indexed | Closure edges | Retained glyphs | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 1,376 | 1,713 | 2 | 5 | 75 |
| x64musl | speed | 1,376 | 1,713 | 2 | 5 | 75 |

An earlier adjacency-copy implementation measured 1,791 allocations for this
case. It was rejected rather than pinned: indexing the existing flat component
store reduced the accepted plan to 75 allocations while preserving linear
work. The current slice does not yet claim sanitized subset-table emission,
PDF font objects, text extraction, or Gate 3 closure.
