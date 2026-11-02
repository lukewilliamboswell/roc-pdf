# text-layout facade batch shaping

This slice connects normalized facade semantics to the built-in Latin shaper
without materializing one `Text.Store` per authored block. Font inspection is
an explicit earlier-stage input. The evidence facade imports the packaged TTF
as `List(U8)`, inspects it once, and passes the validated inspection into
facade shaping; the shaping kernel neither embeds font source syntax nor
re-parses the font.

Preparation consumes only facts established by earlier stages: normalized
block kinds, semantic block ownership, the validated occurrence store, the
interned source table, and the authored theme. It writes exact-length dense
request, style, and block-to-run stores. List labels are emitted before their
bodies so run order follows the semantic `Lbl`, `LBody` order. A batch-wide
language/script/direction/instance/writing-mode record is retained once;
compact requests carry only source identity, occurrence identity, and size.
Mixed occurrence languages, unsupported theme faces, artifact text, invalid
ownership, and every request limit remain typed failures.

Batch shaping validates cumulative source-byte, scalar, cluster, and glyph
limits before output allocation. It scans each unique Unicode source once into
a dense glyph template table containing exact scalar/UTF-8 ranges, glyph IDs,
and source font widths. Per-occurrence emission then scales the cached width and
writes globally dense runs, clusters, glyph indices, glyphs, and advances. The
six-source fixture therefore performs UTF-8 iteration, cmap lookup, and metric
lookup once per unique source rather than once per repeated paragraph. Final
glyph records remain occurrence-owned; the cache does not share mutable output
ranges or infer semantic ownership.

## Ownership and allocation review

The current design derives exact request cardinality from the validated semantic
occurrence store, checks the bound before allocation, reserves that exact
capacity, and appends requests and styles in occurrence order. The final lengths
must equal the validated cardinality. Block-to-run storage retains indexed
writes because block positions are its explicit key.

Keep the exact-capacity consuming append path and verify its linear scaling
with the current compiler; initialized buffers can lose uniqueness across
fallible indexed writes.

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
