# text-layout facade pagination

This slice connects cached facade line ranges to the existing single-column
pagination kernel. The adapter materializes one compact visual-row record per
body line. Each row retains the original body run and global line index; the
first row of a list item additionally retains its label run and line index.
Labels therefore share the body's baseline and page without being flattened
into a preceding visual line or merged into the body's semantic occurrence.

Pagination consumes a dense body-line view because vertical breaking operates
on visual rows, not semantic child count. Copying these small fixed-shape line
records does not copy glyphs, clusters, source Unicode, font bytes, or shaped
runs. The row map is the explicit bridge used by the later fragment/scene
stage; it never recovers label ownership from coordinates.

Title and heading blocks are kept together and with the following block when
one exists. Other multi-line blocks use a two-line minimum at both fragment
ends when possible, falling back to one for a one-line block. Consecutive items
in one authored list have zero inter-item spacing; the final item receives the
theme paragraph spacing. Page breaking uses compact cursors and materializes
each accepted body fragment and row placement once.

## Ownership and complexity review

The adapter makes two direct dense block passes. The first validates all
label/body ranges and computes the exact row count before allocation. The
second writes exact-capacity row, visual-line, and page-block buffers. The page
kernel then performs linear validation, keep-policy planning, fragmentation,
and placement. No authoring suffix, speculative page scene, prior accumulator
version, or per-row glyph/source payload is retained.

All block, row, page, fragment, line, and placement counts are independently
bounded. Arithmetic and invalid label/run/range relationships are typed
failures. The two bullet labels in the scaled fixture remain two explicit row
attachments at every scale.

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
