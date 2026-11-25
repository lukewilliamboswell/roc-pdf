# contract-definition canonical emission and metadata policy

## Scope

This define-only slice fixes the policies that later object planning, metadata
construction, compression, and lexical emission must consume. It does not
expose PDF objects, perform compression, derive identifiers, or emit bytes.

## Deterministic contract

- Finite decimal output uses at most nine fractional digits, half-even rounding,
  locale-independent syntax, and normalized negative zero. structural-kernel rejects an
  input that cannot meet the declared error bound; it never delegates PDF
  number syntax to host floating-point formatting.
- Dictionary keys use unsigned-byte lexicographic order. Objects use sealed-plan
  order, resources use kind then dense identity, and balanced structures use a
  fixed-fanout left-packed partition. No hash-map iteration affects bytes.
- Derived document identifiers use SHA-256 over normalized plan facts with the
  domain `roc-pdf:document-id:v1`. The digest input excludes serialized bytes
  containing the identifier itself. Explicit identifiers remain authored input.
- XML is XML 1.0 Fifth Edition; XMP properties sort by namespace URI then local
  name; the authored metadata title and `dc:title` must agree; timestamps are explicit or
  omitted.
- Stream compression uses the versioned canonical DEFLATE policy: a 15-bit
  window, at most 65,535 input bytes per block, dynamic Huffman coding, and at
  most 128 match candidates searched per input position. The initial xref
  stream remains uncompressed.

## Complexity and ownership

For `n` stream bytes, match search is bounded by `O(128 * n)` candidate visits;
window and block state are bounded constants. The structural-kernel implementation records
input bytes, candidate visits, hash inserts, tokens, matches, blocks, emitted
bytes, and maximum chunk size so compression ratio cannot hide a work
regression. It writes statefully into bounded output chunks and never retains
both complete uncompressed and compressed streams.

Canonical ordering operates on dense planned stores. Dictionary sorting is
`O(k log k)` comparisons for `k` unique keys unless the planner constructs them
in canonical order; balanced-tree partition and object/resource traversal are
linear after canonical input ordering. Metadata and identifier inputs are owned
once in the normalized plan.

The common facade does not accept this policy as an option, preventing callers
from accidentally changing deterministic bytes or conformance. A future policy
revision is an explicit package-version and snapshot change with focused
performance evidence.

## Evidence

`tests/contracts/advanced_encode_contract.roc` compiles explicit metadata inputs and
the fixed canonical policy. Package expects pin number, compression, xref, and
identifier choices. structural-kernel now supplies runtime lexical, digest, compression,
and byte-equality evidence; XML evidence belongs to the capability implementing XML.
