# Gate 1 structural-emission slice

## Scope and status

`KernelEmit` serializes the current sealed blank-page plan as PDF 2.0. One
explicit transition drives buffered and chunked output. It writes the header,
binary marker, generation-zero indirect objects, indirect stream lengths, an
unfiltered xref stream with fixed-width `[1 8 2]` entries, `startxref`, and the
EOF marker. The xref dictionary carries a deterministic SHA-256 file-
identifier pair. Planned stream dictionary entries merge in unsigned-byte order
with generated `/Filter` and `/Length` entries; attempts to override either
generated key fail before emission. The facade exposes this slice only for an
empty `Standard` document; meaningful content and stricter profiles fail
transactionally rather than silently producing a blank or downgraded file.

The public facade remains intentionally limited to blank documents at this
gate, while an internal one-page generated-content probe exercises the same
sealed-plan and chunk transition with non-empty dynamic DEFLATE. Together with
the other evidence aggregated in `gate-1-closure.md`, the snapshots complete
Gate 1; they do not claim meaningful scene content or later profile gates.

## Ownership, traversal, and bounds

The encoder retains the compact sealed plan and scalar phase state. It walks
the object store in allocation order, records one `U64` offset per indirect
object, and records one emitted length per stream. Direct indexed loops emit
arrays, dictionaries, payloads, and xref entries without `Iter` in the hot
path. Checked arithmetic covers byte positions, xref size, and fixed-width
xref-stream length.

Generated chunks are owned. The optimized unchanged-resource fixture proves
both seamless shared slices and bounded owned copies against their actual Roc
backing allocations, including final-use release and the caller-retention
tradeoff described in `gate-1-resource-retention.md`.
Xref entries are emitted in batches of at most 256 entries. Page-tree
dictionaries remain bounded by the fixed fanout of 32. The sealed plan stores
the checked structural bound proved in `gate-1-output-bounds.md`, plus an exact
conservative compressor bound for a non-empty generated stream; each emission
transition checks it as an internal invariant. A counting sink independently
verifies fixed-width xref offsets beyond 4 GiB and checked position overflow.

The empty content stream is encoded as the canonical eight-byte zlib-wrapped
DEFLATE stream required by `/FlateDecode`. Non-empty generated input enters a
preflighted stateful transition that emits one bounded compressed chunk per
65,535-byte block, carries bit and Adler-32 state, records exact compression
work, and releases its source after the last chunk. `gate-1-deflate.md` records
the owned algorithm, replacement seam, bound, allocation evidence, and
independent zlib decompression of the emitted PDF stream.

## Current evidence and remaining work

The pinned optimized one-page scenario records exactly zero Roc allocations
after the fixture measurement boundary and `[1, 667]` deterministic work. That
zero is a whole-fixture result under compiler specialization, not a general
zero-allocation claim for construction or emission. The independent checker
recalculates object offsets, xref entries, direct and indirect stream lengths,
and page facts from the original bytes, and its negative twins corrupt an
offset, a length reference, and the EOF marker. Linux CI additionally runs
qpdf 12.3.2 from its checksum-pinned official binary release and veraPDF
Arlington 1.30.2 from an immutable image digest. Arlington reports zero failed
rules or checks for every structural snapshot within its documented object-
model scope.

Production compression uses the private package-owned stateful implementation,
and no compression package appears in the package dependency graph. The
non-page index and
outline requirements at this gate are sealed builders;
their feature-specific object lowering remains at Gates 2 and 4, where valid
ParentTree, IDTree, named-destination, page-label, and outline payloads exist.
Emitting unreachable or placeholder objects here would violate the stage
contracts rather than complete Gate 1. The complete atomic negative matrix and
byte-identical supported-system evidence are recorded in
`gate-1-negative-determinism.md`; the pinned PDFBox strict-parser lane is
recorded in `gate-1-pdfbox.md`. The non-empty generated-stream probe now covers
stream dictionary
integration, stateful bounded chunks, exact compression work, source release,
and a checked compressor output bound.
