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

Sealing uses direct indexed passes:

- The object pass validates contiguous generation-zero order, stored values,
  and stream ownership in object order. It checks that each stream-bearing
  object owns its stream and each length object follows that stream's owner.
- The value pass validates final store ranges and forward indirect references.
- The stream pass checks each declared owner's object, length object and
  payload use. The payload pass verifies each recorded final stream points
  back to the payload.

The work is `O(objects + values + streams + payloads)` with constant auxiliary
state. The object pass tracks the next stream ID in a scalar. Exact object,
value, reference, and stream visit counts remain in the plan. Counter and
span arithmetic is checked.

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

## Bounded stream-pair model

Run `roc test fuzz/stream_seal_model.roc --no-cache` with the pinned compiler.
The model applies the same authored commands to the object builder and a
plain ledger. After each command it compares the seal result with the
ledger's ordered objects, reference targets, and payload readers. The
ledger represents each stream pair directly and finds a payload's last
reader by scanning the authored sources backwards.

The bounded world uses up to five commands per trace, two payloads and
reference targets 1 and 3. The search exhausts 2,379 states and 2,378
transitions. Three named goals require a resolved forward reference, an
attempt to reuse a stream value as a second object, and interleaved payload
uses. A check against the previous sealer fails on the shortest witness
`[AddPayload, AddStream(0), ReuseStreamValue(0)]`. The fixed sealer returns
`StreamObjectMismatch` with the extra object and its stream before an
encoder can start. Separate negative twins exercise a second length object
and two self-consistent stream pairs in reversed stream order. Returning the
first stream as every used payload's last reader also fails the ledger at
`[AddPayload, AddStream(0), AddStream(0)]`.

This finite search covers ownership and order at the sealing boundary.
The canonical PDF byte comparisons, reader checks and retained-chunk cases
continue to validate emission and backing-allocation behavior. Running the
ledger as a Roc expectation keeps it outside the release package and the
allocation measurement window.
