# Gate 1 deterministic file identifiers

## Scope and normalized input

The initial structural plan emits the same 32-byte SHA-256 digest in both
members of the PDF file-identifier array. Its exact normalized input is the
UTF-8 domain `roc-pdf:document-id:v1`, a zero byte, the plan-kind tag `blank`,
a zero byte, the page count as one big-endian `U64`, and one page-size byte
(`0` for A4 and `1` for Letter). Those facts uniquely determine every current
blank structural plan without hashing serialized bytes that contain the
identifier itself. Future plan kinds require their own unambiguous fact tags
and complete normalized fields under the versioned domain.

## Ownership and bounded work

`KernelSha256` processes input in 64-byte blocks. It builds one fixed 64-word
message schedule per block, keeps the eight digest words as scalar state, and
produces one 32-byte result. It does not construct a padded copy of the input,
allocate per byte, use `Iter`, or retain views into the caller's input. Work is
exactly 64 compression rounds per padded block with constant auxiliary space
apart from the fixed schedule.

The encoder owns the 32-byte digest once and replays it twice into the xref
dictionary. The optimized one-page whole-fixture allocation count remains zero
under the pinned compiler; that specialized result does not replace a future
focused shared-input and block-scaling allocation record.

## Evidence

Unit tests cover the NIST empty-input and multi-block SHA-256 vectors. The
independent PDF checker requires two canonical uppercase 32-byte identifiers,
requires the initial pair to match, reconstructs the normalized facts from the
page tree and media box, and recalculates the digest with Python's independent
SHA-256 implementation.
