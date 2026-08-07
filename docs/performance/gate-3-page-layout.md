# Gate 3 single-column pagination slice

This slice consumes flat block descriptors and the shaped-cluster line plans
produced by the preceding layout stage. It emits three dense stores: pages,
semantic layout fragments, and placed-line baselines. Every fragment retains
its content occurrence, exact source Unicode range, input-line range, checked
fixed-point geometry, and page identity. Every placed line points to one dense
fragment identity. Scene construction therefore does not need to infer
ownership, reading order, source ranges, or pagination from coordinates.

Page and margin dimensions, leading, baseline offsets, spacing, ranges, and all
configured limits are validated before a plan escapes. Fragmentation implements
explicit break-before, keep-together, transitive keep-with-next chains, and
minimum first/last line counts. Keep chains are precomputed in one reverse pass,
so a long chain does not cause repeated forward lookahead. An impossible keep,
a break that contradicts the preceding keep, invalid source partitions,
arithmetic overflow, and limit crossings fail transactionally with typed
diagnostics.

The planner uses top-down consumption but records ordinary bottom-up PDF page
coordinates. It materializes each accepted fragment and line placement exactly
once. It retains no source substring, list suffix, speculative page scene, or
earlier page candidate. Spacing after a completed block is bounded at the page
edge; checked overflow remains an error rather than being treated as a page
break.

## Pinned optimized evidence

The stress pattern has six lines per block, a ten-line content box,
widow/orphan minima of two, keep-together on every fifth block,
keep-with-next on selected kept blocks, and explicit break-before on every
tenth block.

| Blocks | Input/placed lines | Fragments | Pages | Exact allocations |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 6,000 | 1,400 | 600 | 106 |
| 10,000 | 60,000 | 14,000 | 6,000 | 118 |

All declared work grows by exactly ten times. The tenfold scale adds twelve
allocations under the pinned `release-fast-24f0b476` compiler. The allocation
boundary includes construction of the synthetic line/block inputs, keep-policy
planning, final fragment/page/placement materialization, and deterministic
emission of the 667-byte structural carrier.

This is pagination and fragment-materialization evidence, not useful-facade
completion. The normalized facade still needs to create semantic occurrences,
select styles/fonts, run Unicode analysis and shaping per text source, and lower
the accepted fragments to page scenes and final tagged PDF bytes.
