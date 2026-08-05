# Gate 1 unchanged-resource chunk retention

## Representation and release point

Each payload records the ID of its final stream use. The consumption-shaped
builder updates that scalar when a stream is added, and sealing independently
validates that the recorded stream exists, uses the payload, and occurs no
earlier than any other use. Emission therefore consumes a fact produced by an
earlier stage rather than scanning future objects or inferring ownership from
byte equality.

For an unchanged unfiltered payload, `ShareResourceChunks` returns the payload
list itself as a `SharedResource` segment. `OwnResourceChunks` copies only that
range into an `OwnedResource` segment. Immediately after the final range, the
next encoder state replaces the plan's payload bytes with the empty list. The
segment remains valid through its own reference, while later length, xref, and
trailer emission no longer pins the source allocation. Generated syntax and
compressed bytes are always generated segments.

The evidence-only structural fixture places validated whitespace in an
unfiltered content stream. It exercises the unchanged-byte transition without
exposing raw content operators through the package facade or claiming a later
image, font, or color capability.

## Backing-allocation evidence

The optimized fixture constructs one runtime-filled 8,192-byte caller list and
passes a 64-byte seamless slice beginning at offset 4,096. A dedicated Zig test
host inspects the returned Roc list representations directly and requires:

- the source and shared segment are seamless slices with the same element and
  allocation pointers as the caller's 8,192-byte backing list;
- the owned segment has a distinct allocation whose capacity is exactly 64
  bytes;
- all three 64-byte ranges are byte-identical;
- the caller backing allocation has exactly three references at the ABI
  boundary: the returned backing list, source slice, and shared segment.

The exact reference count proves that neither a completed encoder nor its
sealed plan still owns the source after the final range. Pointer identity proves
that sharing did not route bytes through a package-created resource arena. The
source offset and backing length make the caller tradeoff explicit: retaining
the small shared segment pins the caller's entire 8,192-byte allocation.

The buffered, shared-chunk, and owned-chunk paths each emit 703 byte-identical
bytes with SHA-256
`3ab3cc3e9162be5bfacdfb3012900256a087973484f21e194e2d87516ff18cb8`.
The fixture records one shared range, one owned range, and an exact 194 Roc
allocation events under the pinned optimized arm64mac build. Encoder counters
record zero shared-resource copied bytes and exactly 64 owned-resource copied
bytes. The ordinary 4,096-page fixture now records 113,793 allocations. One
fixed event remains attributable to the final-use fact's copy-on-write
transition for the payload store; later SHA-256 schedule reuse removed two
unrelated digest events. Deterministic object, edge, reference, and byte work
is unchanged, so there is no allocation per payload or emitted range.

The same pointer, capacity, reference-count, allocation-count, work, hash, and
independent structural assertions run on x64musl CI. qpdf checks the original
retention snapshot alongside the other structural fixtures.
