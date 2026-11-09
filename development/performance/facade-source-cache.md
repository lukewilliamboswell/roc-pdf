# text-layout facade text-source cache slice

This slice interns immutable facade text before semantic occurrence creation,
Unicode shaping, or layout. Each input receives a dense `TextSourceId`; equal
text shares one retained string and one complete `KernelUnicode` analysis.
No string bytes are copied into the cache. Later stages consume the stored
analysis instead of rerunning grapheme, line-break, scalar, and script
itemization per occurrence.

The common compact-builder pattern receives a zero-scan adjacent-source fast
path. Repeated consecutive values compare directly with the last unique source
and never instantiate the Unicode scalar iterator. Non-adjacent and unique
values use a flat open-address table sized below 50% load. Its deterministic
xorshift scalar hash uses wrapping shifts and XOR only, avoiding unchecked
integer overflow. Hash probes, equality checks, a conservative equality-byte
bound, table slots, scalar visits, unique bytes, and unique scalars are all
explicit work evidence and limits.

The table stores only dense source indices. Strings and Unicode analyses live
once in their own flat list; the input-to-source mapping is a scalar list.
Empty input text, Unicode analysis failure, arithmetic overflow, table
exhaustion, and every cumulative input/source/probe/slot limit fail
transactionally.

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
