# text-layout facade semantic-fragment materialization

The facade fragment stage consumes the preliminary validated text-semantic plan
and the final per-line text plan. It does not infer occurrence identity, source
ranges, page identity, content-stream identity, or paint order from geometry.
Each final run already carries its occurrence-relative Unicode range, and each
placement already carries its accepted page.

The stage writes exactly one dense `LayoutFragment` per final run. Fragment ID
equals run ID, the page's one content-stream ID equals its page ID, and the
fragment source range is the checked sum of the occurrence's absolute range and
the run's relative range. One dense counter per occurrence assigns continuation
indices in final page-paint order. Invalid page coverage, non-text occurrences,
out-of-range source spans, resource limits, or a preliminary plan that already
contains fragments fail atomically.

After arena construction, `KernelTextSemantics.Plan.attach_fragments` rebuilds
the occurrence-to-fragment reverse index through the existing semantic
validator. It reuses the preliminary plan's exact scalar/UTF-8 source facts and
text-property work instead of rescanning immutable source strings. The final
semantic store therefore has validated absolute fragment ranges and normalized
occurrence spans without duplicating Unicode analysis.

## Complexity and ownership

For `p` pages, `r` final runs/fragments, and `o` occurrences, arena construction
uses `O(p + r)` time and `O(r + o)` storage. It performs one page visit, one
placement visit, one fragment write, and one continuation counter read/write
per applicable input. Semantic attachment uses the existing `O(o + r)`
count/prefix/write reverse-index algorithm.

The fragment list and continuation counter list are created once with exact
capacities. The hot loop consumes and returns unique accumulators, retains no
source substrings, and stores only dense IDs and scalar ranges. The successful
plan retains the final text plan required by the scene successor and the final
semantic plan; it does not retain alternate fragment arenas or speculative page
scenes.

## Evidence

`tests/facade_fragments` separates the flat fragment hot loop from final
semantic attachment so optimized compilation remains a practical evidence
boundary. Its prepared-input control and arena scenarios use the same source,
semantic, glyph, run, placement, and page construction.

| Scenario | Control allocations | Arena allocations | Delta | Pages | Fragments |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 occurrences | 95 | 97 | +2 | 32 | 2,000 |
| 10,000 occurrences | 105 | 107 | +2 | 313 | 20,000 |

The constant two-allocation delta is the exact fragment arena and occurrence
counter storage; it does not grow per fragment. Work counters scale by ten for
placements, fragments, and continuation operations, while page visits follow
the explicit 64-run page partition.

A focused composed case attaches six fragments to three occurrences and proves
six count visits, six validation visits, three prefix steps, six reverse writes,
and six reverse entries. Its `reused_source_analysis` dimension records that
attachment crosses the cached `TextSourceFact` boundary rather than calling the
Unicode scanner again. Atomic negative evidence covers an invalid placement
page, an occurrence-relative range outside its source, the fragment limit, and
attempted reuse of a plan whose fragments were already attached.

The fixture emits the same small blank PDF as its matched measurement control;
that PDF is only a deterministic allocation-report carrier. Visible facade PDF
evidence belongs to the later scene, font-resource, and public `Pdf.to_bytes`
composition slice.
