# Engineering evidence

Use the [architecture](../../../architecture.md) for the compiler-stage
contracts and the [testing chapter](../../testing.adoc) for choosing
and running checks. These records explain the bounds, ownership and
fixture design behind individual subsystems.

| Task | References |
| --- | --- |
| Review allocation or copying changes | [Lowering and uniqueness](lowering-uniqueness.md), [emission linearity](emission-linearity.md), [pinned toolchain baselines](toolchain-profile.md) |
| Change pagination or text fitting | [Page breaking](layout-policies.md), [frames and furniture](page-templates.md), [line layout](line-layout.md), [reference wrapping](destination-page-references.md) |
| Change semantic output | [Semantic identity](semantic-identity.md), [structure lowering](structure-lowering.md), [table associations](tables.md), [navigation](navigation-annotations.md) |
| Change object or resource planning | [Resource graph](resource-graph.md), [balanced indexes](balanced-indexes.md), [sealed plan](sealed-plan.md), [object store](object-store.md) |
| Change a profile or review output | [Archive checks](static-pdfa4.md), [author review](../accessibility-review.md), [optional local tools](../testing.md#optional-local-pdf-review) |
| Add an evidence fixture | [Scenario protocol](scenario-protocol.md), [fixture grouping](fixture-grouping.md), [test validation plan](test-suite-speed.md), [fuzz suites](fuzz-suites.md) |
