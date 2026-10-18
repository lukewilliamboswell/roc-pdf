# Destination page references

## Stage and representation review

`Pdf.page_reference` is a boxed authored inline leaf with a destination name,
positive fixed width, alignment and physical/page-label numbering choice. Its
normalized leaf and global occurrence identity exist before its Unicode value.
No guessed text, padding characters, font substitution or layout-dependent
width participates in measurement.

`Document.normalize` records dense reference and chunk arenas only for rich
paragraphs containing references. Literal chunks end at each atom and authored
mandatory break. Text leaves keep byte ranges relative to their actual chunk;
Unicode analysis and shaping cannot cross the symbolic gap. A break following
an atom records `separator_after`: final semantic ActualText includes a space,
while the label's source, shaping, fit and alignment remain the exact label.

`KernelFacadeSemantics.Symbolic` holds semantic components and explicit literal
and pending contexts. It exposes no `Semantics.Store` or validated text plan.
Nodes, content-spine entries, ownership, language, source-chunk identity and
occurrence ids are retained across resolution. Literal ids have explicit gaps
where references belong; a reference-only segment needs no literal source or
shaping request. Mandatory segment ids are authored occurrence identities.

`KernelFacadeReferenceShape` shapes exact literals using the facade's existing
face/style policy. `KernelFacadeReferenceLines` measures literal-cluster items
and atomic fixed advances, including list columns, table intrinsic widths,
code holds and source blocks. Its row spans name item ids, never provisional
Unicode coordinates. `KernelFacadePages.Measured` commits page geometry through
the same policy, scope and container engine as ordinary flow. Its paint facts
supply accepted row origins, repeated-header artifacts and decoration geometry.

`KernelFacadeReferences` builds one destination registry, commits literal
anchors from accepted rows, and resolves names against those anchors. One
validated page-label plan serves visible references, furniture and final
navigation. Formatting checks its 128-byte facade bound before constructing a
label, and an explicitly empty label rejects. There is one pagination choice:
resolved text cannot alter atom width or trigger another wrap/pagination pass.

Finalization extends source interning, preserving existing source ids and
Unicode analyses. It merges exact reference occurrences into the stable semantic
spine and validates the first complete text-semantic store. All final exact
contexts shape under the same policy. A dense map verifies each literal's
source ranges, cluster ranges, glyph ids, offsets and advances against its
measurement facts. Font instance ids may change when a newly resolved label is
the first use of a face, so incidental dense font ids are not used as identity.

Each field fits once against the shaping stage's exact run advances. Its cached
run span and alignment inset are reused by every paint, including repeated
table headers. Consecutive literal items in one final run and accepted row
coalesce into one positioned piece. Reference items expand to their exact final
font runs. `KernelFacadeText.Plan.build_positioned` materializes those real
clusters without wrapping, outlining or rasterization.

## Ownership, storage and complexity

Normalization captures every original state projection before growing inline or
reference arenas; the old state record is never read after an append. Chunk
text is joined once per finished literal chunk, rather than concatenated once
per leaf. Paragraph-to-chunk routing uses a bounded binary lookup over the
reference-paragraph index, and each chunk/leaf traversal uses a monotonic cursor.

Measured item builders use plain consuming `Open | Failed` state. Failure drops
the arenas; growing builders do not return through `Try` for a caller to extend.
Measurement, source interning, mapping and positioning freeze their results
before returning them through `Try`. Source extension rebuilds its interning
index once and charges every hash/probe to explicit limits; it reuses literal
Unicode analysis rather than analyzing literals again. A shared source arena
may require one copy before its first append, followed by owned growth.

The anchor arena used by label resolution is frozen evidence. Positioning makes
one owned linear copy before filling final reference anchors. It does not
mutate a builder returned through `Try`. Literal and final shape stores coexist
only through their explicit verification/materialization phase. Contexts retain
whole immutable source facts, not per-line source suffixes or discarded scenes.

The normalizers, context merge, item construction, accepted row traversal,
cluster mapping and materialization are linear in their visited input/items or
painted output. Name ordering and lookup retain their existing bounded registry
cost; per-reference lookup is logarithmic in destination count. Reference
formatting is bounded by its checked output bytes. Field-fit work scales with
logical reference font runs, independently of header repaint count. Repeated
headers add work proportional to their actual painted items and glyphs.

Deterministic evidence includes reference atom count, normalization chunks,
literal requests, measured/wrapped items, boundaries, row items, committed row
visits, anchor item visits, name lookup steps, label count/bytes, mapped clusters
and glyphs, field-fit run visits, positioned pieces and metric reads from both
literal and final shaping. Final navigation consumes the same registry, label
plan and accepted anchor proof rather than independently resolving them again.

## Verification boundary

Canonical `package/all.roc` tests run through `scripts/test.py` cover stable
semantic ids, reference-only paragraphs and mandatory segments, explicit
ActualText separators, adjacent references, source interning, table cells and
list labels. Orchestration tests exercise physical and configured Roman labels,
exact width overflow, unknown targets, empty labels and format-byte bounds.
The registered small/large PDF cases and independent PDF checks provide the
allocation, allocated-byte, work and final-output evidence for gate closure.
