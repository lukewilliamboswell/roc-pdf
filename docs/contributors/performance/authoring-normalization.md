# text-layout facade authoring normalization slice

This slice implements the common normalization boundary shared by the simple
`List(Document.Block)` facade and `Document.Builder`. Both paths produce one
flat ordered block/text store before semantic construction or layout. Bullet
lists expand to dense scalar list/item identities; headings retain their level;
page artifacts remain a distinct typed kind. String values are transferred as
shared immutable payloads rather than copied byte-by-byte.

The compact builder stores block tag, text-source ID, and auxiliary value in
three parallel scalar buffers, with text payloads in a fourth flat list. It does
not allocate a boxed union descriptor per block. Ordinary scalar methods remain
ergonomic; `add_paragraphs` is the consumption-shaped large-input path and keeps
all four buffers uniquely owned throughout one direct indexed loop. Only the
final builder escapes that loop.

Normalization is linear in authoring descriptors plus expanded bullet items.
It visits each input descriptor once and writes each normalized block once. It
does not sort, retain list suffixes, rescan text bytes for each output item, or
keep earlier builder/normalization versions. The work vector records authoring
descriptors, normalized blocks, referenced UTF-8 bytes, title/heading/paragraph/
bullet counts, list count, and the structural evidence-carrier bytes.

Image figures use a separate dense normalized figure store; account for its
fixed empty-store cost when reviewing allocation changes.

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
