# Gate 3 facade text-source cache slice

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

## Pinned optimized evidence

| Pattern | Inputs | Unique analyses | Table slots | Exact allocations |
| --- | ---: | ---: | ---: | ---: |
| shared `Body` | 1,000 | 1 | 2,048 | 83 |
| shared `Body` | 10,000 | 1 | 32,768 | 89 |
| unique indexed text | 1,000 | 1,000 | 2,048 | 16,976 |
| unique indexed text | 10,000 | 10,000 | 32,768 | 187,980 |

The shared tenfold scale adds six allocations and performs one Unicode
analysis in both cases; its input mappings and equality work grow linearly.
The deliberately unique cases pay for 1,000/10,000 retained strings and full
Unicode analyses. Their probe counts remain close to input count at the pinned
load factor. The higher allocation slope is reviewed as source/analysis
ownership, not accepted as the repeated-source path.

All measurements include input construction, cache construction, Unicode
analysis, and deterministic emission of the 667-byte structural carrier under
`release-fast-24f0b476`.

This is a source/cache boundary, not facade completion. Semantic graph
construction, style/font selection, shaping-cache keys, page scenes, and final
public `Pdf.to_bytes` integration remain subsequent Gate 3 slices.
