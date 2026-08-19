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
  work `[32, 8692, 208253, 1, 12397]`: 32 chunks, an 8,692-byte largest
  chunk, order-sensitive chunk-offset weight 208,253 (the sum of each
  chunk's one-based index times its length, which changes if equal-length
  chunks reorder), the byte-identity bit, and the 12,397 concatenated bytes.
- Both modes measure 2,845 dev allocations. The modes are identical here
  because every authored segment is `Generated`: retention modes only
  diverge for the caller-resource chunk sharing of production-visual resource
  documents, which authored text-layout output does not carry.

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
