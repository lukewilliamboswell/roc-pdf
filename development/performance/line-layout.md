# text-layout shaped-cluster line-selection slice

This slice adds the bounded single-column line-selection kernel between shaping
and pagination. Its public internal entry points accept either the built-in
`KernelShape.Shape` result or an advanced `KernelShape.Validated` result. The
planner consumes the shaped cluster-to-source and cluster-to-glyph-index facts
directly. It does not reconstruct clusters from Unicode text, assume one glyph
per scalar, or infer source ownership from glyph order.

The planner first validates the dense UAX #14 boundary coordinates and requires
every allowed or mandatory boundary to coincide with a shaped cluster end. It
then visits each cluster and its glyph-index references once to build checked
prefix advances. Negative advances, overflowing ranges or advances, incomplete
source partitions, invalid glyph references, breaks inside multi-scalar
clusters, and an over-width span with no legal break all fail with typed errors.
No partial line plan escapes.

Line selection retains scalar and UTF-8 source ranges plus cluster ranges. This
preserves the information needed for later per-line bidirectional ordering,
extraction, accessibility, and tagged scene lowering. It deliberately does not
flatten a line to an assumed contiguous glyph range: advanced shaped clusters
can refer to reordered glyph indices.

The implementation uses flat cluster, glyph-index, glyph, boundary, prefix, and
line buffers. It keeps no source substrings or list suffixes. Boundary
validation, cluster measurement, and line writes are linear. Candidate visits
are explicitly limited; the evidence pattern exercises the restart after every
selected break and records exactly `2 * clusters - 2` candidate visits.

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
