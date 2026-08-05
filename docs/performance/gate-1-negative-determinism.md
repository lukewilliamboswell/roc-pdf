# Gate 1 negative and cross-system evidence

## Atomic negative matrix

Gate 1 invalid inputs are rejected at their typed construction or sealing
boundary before an emission plan can escape. The retained caller value remains
unchanged, and no encoder exists from which partial PDF bytes could be read.
The focused executable twins cover the roadmap categories as follows:

| Required category | Rejection evidence |
| --- | --- |
| Malformed numeric values | `KernelLex.Decimal.from_coefficient` rejects a scale outside the closed exact-decimal policy; floating-point NaN and infinity never enter the representation. |
| Duplicate keys | `KernelObject` rejects duplicate dictionary keys before appending edges; `KernelIndex` separately rejects duplicate byte and number keys. |
| Bad references | `KernelSeal` rejects an indirect reference outside the final dense object range and identifies both source value and target object. |
| Offset/count overflow | `KernelEmit.CountingSink` rejects a position increment above `U64.highest`; `KernelObject` directly exercises checked count and aggregate-size overflow without allocating an impossible collection. |
| Invalid names/strings | `KernelLex.Name` rejects a null byte. Roc `Str` makes malformed UTF-8 unconstructible, while PDF byte strings intentionally accept every byte; explicit aggregate limits reject oversized name, text-string, and byte-string inputs atomically. |
| Non-monotonic tree keys | `KernelIndex` distinguishes descending byte keys and descending number keys from duplicates, including prefix and unsigned-byte ordering cases. |
| Bad limits/counts | Empty page, balanced-tree, index-tree, and outline inputs and their explicit page, entry, and depth limits have named failures. |
| Size limits | Object-store aggregate bytes, index key bytes, generated DEFLATE input/output, structural page count/output bounds, and outline entry/depth limits are checked before their bounded representation escapes. |

The external checker negatives are deliberately separate. They mutate already
serialized bytes to prove that independent zlib reconstruction, offsets,
indirect lengths, identifiers, EOF placement, Arlington report parsing, and
PDFBox strict parsing do not accept their corresponding corrupt evidence.
Those files are never inputs to the package and therefore are not substitutes
for transactional internal rejection.

## Cross-system byte identity

The supported evidence systems are `arm64mac` and `x64musl` under the compiler
pin in `.roc-version`. The CI matrix builds each fixture with the same Roc
optimization and Zig ABI, captures its original stdout bytes, and compares the
entire result to one shared tracked snapshot before running independent
structural checks. A platform-specific hash match is not accepted in place of
that byte-for-byte comparison.

The shared snapshots establish these Gate 1 hashes on both systems:

| Structural fixture | SHA-256 |
| --- | --- |
| blank | `1ead96b196ec598284fc1a127bb390a3f4643f1d848d01dd118aa1b46949ef5d` |
| balanced 4,096 pages | `bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756` |
| one-block DEFLATE | `9c17df59246c2e7bb2d7073057c805aa37b7f21f931a2bb5929f8b7e0e870a95` |
| five-block DEFLATE | `110215bac723e732b7248e092db3d75e19c7da430c77154f39bd4062c91a30ed` |
| unchanged resource | `3ab3cc3e9162be5bfacdfb3012900256a087973484f21e194e2d87516ff18cb8` |

The same matrix asserts the exact allocation and algorithmic-work vectors per
target. Cross-system determinism therefore does not relax the separate
performance contract.
