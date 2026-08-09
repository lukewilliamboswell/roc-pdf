# Gate 3 shaped-cluster line-selection slice

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

## Historical optimized-backend evidence (superseded)

This earlier table remains only as a representation-review record. Current
validation uses the matching exact dev-backend scenario in
[`tests/spec.json`](../../tests/spec.json), not this historical backend.

| Paragraph units | Scalars/clusters/glyphs | Lines | Candidate visits | Exact allocations |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 6,000 | 3,000 | 11,998 | 97 |
| 10,000 | 60,000 | 30,000 | 119,998 | 105 |

The tenfold scale adds eight allocations under the pinned
`release-fast-24f0b476` compiler. The allocation boundary includes construction
of all synthetic prior-stage facts, planning, and deterministic emission of the
667-byte structural carrier. Exact work also records all 6,001/60,001 Unicode
boundaries, every cluster and glyph-index reference, and every written line.

This is line-selection evidence, not useful-facade completion. Pagination,
widow/orphan and keep policy, final semantic fragment mapping, scene
materialization, and `Pdf.to_bytes` integration remain later Gate 3 slices.
