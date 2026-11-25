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
Use scaled repeated-source fixtures to verify that semantic-node and content-edge
work grows linearly without one allocation per edge. Dense owner buffers must
remain unique across fallible validation.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
