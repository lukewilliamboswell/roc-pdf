# Gate 1 structural-emission slice

## Scope and status

`KernelEmit` serializes the current sealed blank-page plan as PDF 2.0. One
explicit transition drives buffered and chunked output. It writes the header,
binary marker, generation-zero indirect objects, indirect stream lengths, an
unfiltered xref stream with fixed-width `[1 8 2]` entries, `startxref`, and the
EOF marker. The facade exposes this slice only for an empty `Standard`
document; meaningful content and stricter profiles fail transactionally rather
than silently producing a blank or downgraded file.

The checked-in one-page snapshot is partial Gate 1 evidence. It does not claim
support for non-empty content, stateful DEFLATE, file identifiers, balanced
large trees, or the later profile gates.

## Ownership, traversal, and bounds

The encoder retains the compact sealed plan and scalar phase state. It walks
the object store in allocation order, records one `U64` offset per indirect
object, and records one emitted length per stream. Direct indexed loops emit
arrays, dictionaries, payloads, and xref entries without `Iter` in the hot
path. Checked arithmetic covers byte positions, xref size, and fixed-width
xref-stream length.

Generated chunks are owned. The transition also distinguishes seamless
unchanged-resource slices from owned copies, but the present blank fixture has
no unchanged resource and therefore does not evidence either retention path.
Xref entries are emitted in batches of at most 256 entries. Page-tree
dictionaries remain bounded by the fixed fanout of 32; other generated segment
bounds still need to be stated and evidenced before Gate 1 completion.

The empty content stream is encoded as the canonical eight-byte zlib-wrapped
DEFLATE stream required by `/FlateDecode`. Non-empty DEFLATE input is rejected
before emission. The pinned `roc-deflate` integration and stateful bounded
compression transition remain a Gate 1 requirement; this empty-stream special
case is not evidence for them.

## Current evidence and remaining work

The pinned optimized one-page scenario records exactly zero Roc allocations
after the fixture measurement boundary and `[1, 527]` deterministic work. That
zero is a whole-fixture result under compiler specialization, not a general
zero-allocation claim for construction or emission. The independent checker
recalculates object offsets, xref entries, direct and indirect stream lengths,
and page facts from the original bytes, and its negative twins corrupt an
offset, a length reference, and the EOF marker. Linux CI additionally runs
qpdf 12.3.2 from its checksum-pinned official binary release.

Gate 1 completion still requires exact scaling and copied-byte counters,
non-empty stateful DEFLATE through `roc-deflate`, file identifiers, stream
dictionary merging, balanced-tree stress over thousands of pages, shared and
owned retention tests against actual backing allocations, a greater-than-4
GiB counting sink, cross-system hash evidence, and the pinned Arlington and
strict-parser validators.
