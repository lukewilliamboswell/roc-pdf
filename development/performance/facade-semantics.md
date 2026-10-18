# text-layout facade semantic planning

This slice consumes `Document.NormalizedAuthoring` and constructs the explicit
semantic facts required before layout. Title, heading, paragraph, and list
roles are authored facts rather than geometry-derived guesses. Lists become a
PDF 2.0 `L -> LI -> (Lbl, LBody)` hierarchy; generated bullet labels retain a
`SourceToPresentation(GeneratedText)` fact. Page artifacts stay in a separate
typed store and never enter the logical content spine.

Planning is a bounded two-pass traversal over the compact normalized authoring
store. The first pass validates list identity and heading levels, checks every
node, occurrence, content, property, artifact, and source limit before append,
and interns source Unicode through the facade source cache. The second pass
writes exact-capacity node, occurrence, mixed-content, property, artifact, and
block-ownership stores. It recomputes only dense scalar cursors established by
the first pass; it does not retain a boxed planning union per block, infer
reading order later, sort identities, or copy source strings.

The plan transfers the compact normalized authoring store forward because
layout still requires authored block kinds and order, while metadata emission
requires the authored title. Those facts are not reconstructed from semantic
roles. Its string references share the immutable payloads already owned by the
normalized/source stores.

The preliminary semantic store is validated through `KernelTextSemantics` and
`KernelSemantics` before layout fragments exist. Empty fragment ranges are an
explicit stage state, not missing ownership. Later layout must attach fragments
to these stable occurrence identities and revalidate the completed store.

## Ownership and allocation review

The scaled fixture starts from compact-builder construction and includes
normalization, source interning and Unicode analysis, semantic construction,
preliminary text/semantic validation, and the deterministic evidence carrier.
Repeated paragraph text retains one immutable source and one Unicode analysis.
The tenfold scale adds 37 allocations, not one allocation per semantic node or
content edge.

During review, helper-shaped ownership marking returned dense owner buffers
through `Try`. That prevented the optimized build from preserving uniqueness
and caused copy-on-write allocation per semantic edge: the rejected draft
measured 4,287 allocations at 1,000 paragraphs and 40,324 at 10,000. Direct
consumption-shaped validation updates reduced those counts to 256 and 293 with
identical bytes and deterministic work. The same fix reduced the tagged-visual
million-command fixture from 136 to 131 allocations; its bytes and work counters
remain unchanged.

## Historical optimized-backend evidence (superseded)

This table remains as historical semantics-store review evidence. The current
exact allocation baseline is the matching dev-backend scenario in
[`tests/spec.json`](../../tests/spec.json).

| Paragraphs | Normalized blocks | Nodes | Occurrences | Content items | Unique sources | Exact allocations |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1,004 | 1,010 | 1,006 | 2,015 | 6 | 256 |
| 10,000 | 10,004 | 10,010 | 10,006 | 20,015 | 6 | 293 |

Both cases contain one title, one level-one heading, the repeated paragraphs,
and one two-item bullet list. They retain two generated-text properties, visit
every node/content/occurrence exactly once, reach semantic depth four, and
retain 26 UTF-8 bytes / 24 Unicode scalars across the six unique sources.
