# text-layout authored chunked facade output

This closes the byte-identical buffered/chunked public contract of
`architecture.md` ("Pure output and chunked delivery", `architecture.md:1215`)
for authored Standard documents. `Pdf.to_chunks_with` now builds the same
standard plan as `Pdf.to_bytes_with` — including validation, the blank
fallback, and profile rejection — and starts the shared `KernelEmit` encoder
over it. The former structural-kernel blank-only request validator is deleted; no caller
remains.

## Byte identity by construction

`KernelEmit.to_bytes` is literally `start(plan, OwnResourceChunks)` followed
by the same `Encoder.next` transition `Pdf.next_chunk` drives, so once both
APIs consume one sealed plan their forms are byte-identical by construction
rather than by comparison. Chunk boundaries come from the encoder's
plan-derived phase machine and are deterministic. The registered fixture
still proves the identity on real bytes: its snapshot is byte-for-byte the
existing `tests/pdf_facade/pdf_facade.pdf` (12,397 bytes, SHA-256
`8723c2d6ea86a67205f9fc3a5f1ec18acb955af0f259842be2234753d4d4559f`), and the
fixture separately buffers `Pdf.to_bytes` output and reports the comparison
in its `byte_identical` counter.

## Registered evidence

`tests/pdf_facade/pdf_facade_chunks.roc` authors the exact
`pdf_facade` document and collects the chunk stream. Two spec cases
share the source and snapshot and select the retention mode by argument:

- Both `share` (ShareUnchangedResources) and `own` (OwnChunks) report
  work `[40, 8692, 324918, 1, 16477]`: 40 chunks, an 8,692-byte largest
  chunk, order-sensitive chunk-offset weight 324,918 (the sum of each
  chunk's one-based index times its length, which changes if equal-length
  chunks reorder), the byte-identity bit, and the 12,397 concatenated bytes.
- The shared mode measures 1,588 dev allocations and the owned mode 1,589.
  The shared encoder can return the already sealed generated chunks directly;
  `OwnChunks` performs the one required ownership copy. Under the pinned dev
  lowering, the pure buffered/chunked identity comparison reuses the sealed
  generation value instead of charging a second full facade allocation path;
  that reviewed ownership effect accounts for the 1,586-allocation reduction
  while bytes and deterministic work remain pinned. Retention modes also
  diverge for caller-resource chunks in the production-visual evidence.

The inline package expects additionally pin authored byte identity with at
least two chunks, the `OwnChunks` concatenation twin, and the atomic
negative through `Pdf.to_chunks`.

`tests/pdf_facade/pdf_facade_chunks_negative.roc` proves the atomic
rejection: a `page_footer` document receives
`UnsupportedAuthoringContent({ blocks: 1 })` from `Pdf.to_chunks` before any
encoder or chunk exists, then emits the blank 667-byte structural carrier
with counted work `[1, 667]` and 4 dev allocations.

The positive snapshot reuses the facade-output structural validator (offsets,
lengths, xref, authored paragraph, Type 0 font, CID, and Unicode mapping
facts) because it is that exact PDF; qpdf and the other snapshot oracles
apply unchanged. arm64mac values are recorded identical to the measured
x64musl values per the established dev-backend convention.
