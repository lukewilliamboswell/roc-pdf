# Gate 1 bounded dynamic DEFLATE

## Scope and byte contract

`KernelDeflate` is the package-owned private generated-stream compression
transition used by the sealed structural plan. Non-empty input is wrapped in
zlib and partitioned into blocks of at most 65,535 source bytes. Each block
uses the canonical dynamic-Huffman declaration, a 32 KiB hash-chain match
window, newest-first greedy matching, a maximum match length of 258 bytes, and
at most 128 candidate visits per token. Bit and Adler-32 state cross block
boundaries; the empty stream retains the canonical eight-byte fixed-block
encoding.

The policy is deterministic and package-versioned. Changing the block size,
tree declaration, match order, search limit, or empty-stream special case is a
byte-contract and performance-baseline change, not an interchangeable encoder
choice.

## Bounds, ownership, and traversal

Preparation checks the input limit and the conservative output bound

`6 + ceil((9n + 349b) / 8)`

for non-empty input of `n` bytes and `b = ceil(n / 65535)` blocks. The six-byte
term covers the zlib header and Adler-32 trailer. Nine bits per source byte
covers the literal-only case, while 349 bits per block covers its dynamic tree,
block header, end-of-block symbol, and bit-rounding allowance. Checked
arithmetic rejects an unrepresentable bound before an encoder escapes.

The encoder retains the source allocation until its final generated chunk,
then releases it. Each transition owns at most one bounded compressed chunk
and one fixed-size block-local hash-chain table. It does not materialize a
token list or a whole compressed copy, and candidate search is bounded by
`128n`. Exact counters record source bytes, blocks, candidate visits, hash
inserts, tokens, matches, emitted bytes, and the largest generated chunk.

Document identifiers hash generated content before emission. `KernelSha256`
therefore reuses one 64-word schedule across all digest blocks; otherwise the
integrated compression fixture would hide three allocations per 64 source
bytes in an adjacent stage. The pinned optimized 65,535-byte one-block fixture
records 114 Roc allocation events and the 262,144-byte five-block fixture
records 126. The twelve-event increase is exactly three bounded allocation
events for each additional DEFLATE block, not per byte, token, match, or digest
block.

## Executable evidence

The 262,144-byte fixture emits five generated chunks for compressed data plus
the surrounding structural segments. Its exact DEFLATE work is:

`[262144, 5, 1524, 262134, 1036, 1016, 1864, 456]`

for input bytes, blocks, candidate visits, hash inserts, tokens, matches,
compressed bytes, and maximum compressed-chunk bytes. The complete 2,527-byte
PDF is checked byte-for-byte and has SHA-256
`110215bac723e732b7248e092db3d75e19c7da430c77154f39bd4062c91a30ed`.
The independent checker decompresses the `/FlateDecode` payload with zlib,
compares all 262,144 source bytes, checks its indirect length and xref offset,
and rejects corrupt compressed data and an incorrect generated-content
identity.

Unit tests cover the empty byte contract, input and output limits, dynamic
block type, Adler-32 trailer, the full 32 KiB distance code, a multi-block round
trip, and raw-DEFLATE decompression through pinned `roc-deflate` 0.1.0. The
independent Python checker separately reconstructs the generated source and
decompresses the exact PDF stream with zlib, so neither the owned encoder nor
one decoder is the sole correctness oracle.

## Ownership and replacement seam

The production encoder is intentionally the private `KernelDeflate`
implementation. Pinned `roc-deflate` 0.1.0 exposes only a one-shot fixed-
Huffman compressor, so tests use its decompressor as an independent oracle and
no production compression path calls it.

The replacement seam is the preflighted plan, conservative output bound,
stateful `start`/`next` transition, bounded owned chunks, explicit work facts,
and final-source-release behavior consumed by `KernelEmit`. A future
`roc-deflate` release may replace the implementation when it can provide this
contract. Adoption requires a reviewed byte-policy decision and the complete
determinism, bound, allocation, work, and retention suite; matching a round
trip alone is insufficient. Until then the owned implementation is the Gate 1
production path rather than a temporary fallback.
