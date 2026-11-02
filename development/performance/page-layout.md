# text-layout single-column pagination slice

This slice consumes flat block descriptors and the shaped-cluster line plans
produced by the preceding layout stage. It emits three dense stores: pages,
semantic layout fragments, and placed-line baselines. Every fragment retains
its content occurrence, exact source Unicode range, input-line range, checked
fixed-point geometry, and page identity. Every placed line points to one dense
fragment identity. Scene construction therefore does not need to infer
ownership, reading order, source ranges, or pagination from coordinates.

Page and margin dimensions, leading, baseline offsets, spacing, ranges, and all
configured limits are validated before a plan escapes. Fragmentation implements
explicit break-before, keep-together, transitive keep-with-next chains, and
minimum first/last line counts. Keep chains are precomputed in one reverse pass,
so a long chain does not cause repeated forward lookahead. An impossible keep,
a break that contradicts the preceding keep, invalid source partitions,
arithmetic overflow, and limit crossings fail transactionally with typed
diagnostics.

The planner uses top-down consumption but records ordinary bottom-up PDF page
coordinates. It materializes each accepted fragment and line placement exactly
once. It retains no source substring, list suffix, speculative page scene, or
earlier page candidate. Spacing after a completed block is bounded at the page
edge; checked overflow remains an error rather than being treated as a page
break.

## Allocation validation

The stress pattern combines widow/orphan minima, keep-together, keep-with-next,
and explicit break-before. Check scaled cases for linear work across all input
lines and fragments, including the complete keep-policy planning boundary.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
