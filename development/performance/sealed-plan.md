# structural-kernel sealed object-plan slice

## Scope and status

`KernelSeal` consumes the private object builder and returns an opaque compact
plan only after the complete object range is known. It validates object order,
stored-value indices, lexical-value store indices, aggregate spans, forward
references, stream ownership, and the consecutive indirect length-object pair
for every stream. No public type in `package/main.roc` exposes the builder,
store, or sealed plan.

Catalog/page-tree invariants, output bounds, xref dimensions, and the emission
state machine now consume this same sealing transaction before the facade can
return an encoder or bytes.

## Representation and traversal

The sealed plan retains the existing flat stores, exact source-byte totals,
construction work, and sealing work. It drops construction limits and does not
materialize a recursive tree, object map, reference map, token list, or
precompressed stream list.

Sealing performs three direct indexed passes:

- one pass over indirect objects validates contiguous generation-zero order
  and their stored value or stream-length content;
- one pass over values validates all final store ranges and forward indirect
  references;
- one pass over streams validates their object, immediately following length
  object, payload-backed value, and stream identity.

The work is `O(objects + values + streams)` with constant auxiliary state.
Exact object, value, reference, and stream visit counts are retained in the
plan. Counter and span arithmetic is checked; no pass uses `Iter`, recursion,
hash lookup, or an allocation per object or reference.

## Stream allocation and ownership

Stream construction now allocates the stream object and its indirect length
object atomically as one consecutive pair. The length object carries
`LengthOf(StreamId)` rather than a placeholder integer value. The stateful
emitter can therefore write the measured compressed byte length immediately
after the stream without buffering the stream or patching a prior object.

Every stream continues to retain one payload ID. Sealing neither copies nor
coalesces payload bytes, so the later shared/owned chunk policy can make the
retention decision without undoing an intermediate arena.

## Executable evidence

The current blank structural plan stores its checked output bound before
emission, the generated-stream probe adds a checked multi-block compressor
bound, and an independent counting sink covers offsets beyond 4 GiB. qpdf,
Arlington, and strict PDFBox lanes now validate the emitted structural plans.
Shared/owned unchanged-resource retention is checked against actual backing
allocations and final-use release.
