# Gate 1 balanced byte-key and number-key plans

## Sealed representation

`KernelIndex` provides two opaque plan families over the shared fanout-32,
left-packed `KernelBalanced.Shape`:

- `ByteTree`, branded as either `NameTree` or `IDTree`, compares keys as
  unsigned byte strings;
- `NumberTree`, branded as either `NumberTree` or `ParentTree`, compares signed
  PDF integer keys, with the ParentTree policy additionally rejecting negative
  keys.

The node contract follows ISO 32000-2:2020 7.9.6 Tables 36 and 7.9.7 Table 37,
including Errata Collection 3: a root contains entries if it is also the only
leaf, otherwise it contains child nodes; every non-root intermediate or leaf
node carries `/Limits`. Byte keys use unsigned ascending byte order, with a
shorter key before a longer key having the same prefix; number keys use
ascending integer order.

Callers provide a dense entry list in final key order. Sealing checks the entry
limit before any shape allocation, checks every byte-key size and value ID
against the earlier object-value count, and verifies strict monotonicity and
uniqueness in one pass. It does not sort or recover malformed input. The sealed
plan retains the original entry list and one shared shape; it creates no per-
node entry lists, child lists, or limit-key copies.

A node is an arithmetic view. Leaf nodes expose one contiguous entry span and
internal nodes expose one contiguous breadth-first child span. The root omits
`/Limits`; every non-root node identifies the first and last entries in its
complete descendant span. Tree-specific object lowering can therefore consume
sealed ordering and limit facts without rescanning keys or inferring ranges
from object order.

## Complexity and executable evidence

For `n` entries and `b` total byte-key bytes, sealing is `O(n + b)` plus the
adjacent common prefixes actually compared. Shape storage is `O(log32(n))`;
entry storage is caller-owned and retained unchanged. Enumerating emitted nodes
is `O(nodes)` and requires only constant-size arithmetic views.

Focused tests cover:

- the 33-entry depth transition and exact non-root limits;
- distinct NameTree and IDTree brands;
- 4,096-entry number-tree topology and linear work;
- duplicate and descending byte and number keys as distinct failures;
- byte-key size, unresolved value ID, empty-entry, entry-count, and negative
  ParentTree failures.

The pinned optimized stress fixture builds 4,096-entry NameTree, IDTree,
NumberTree, and ParentTree plans together. It verifies 16,384 total leaf
entries, 532 nodes, 528 non-root limit pairs, a 2,162,160 limit-index checksum,
16,384 entry validations, 32,768 key-byte visits, and 49,110 ordering steps.
The builders are exercised beside the unchanged 4,096-page output, so its
1,084,927 bytes and SHA-256
`bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756`
remain independently checked.

The combined fixture records exactly 138,385 Roc allocations, 4,111 above the
page-only fixture. Of those, 4,096 are the evidence caller's four-byte key
lists. The remaining fixed 15 cover the two dense input entry lists and four
compact shapes; there is no allocation per output node or second allocation
per retained key. CI applies the same exact count and work vector on arm64mac
and x64musl. The shared compiler-caused increase from the original 117,904
count is reviewed in `roc-nightly-2026-August-05-24f0b47.md`.

This slice seals reusable index topology and ordering facts. It does not claim
the separate outline hierarchy builder or optional feature-specific object
lowering.
