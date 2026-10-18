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

An authored break after an atom retains its semantic space through explicit
occurrence-owned ActualText. When separators exist, materialization builds a
dense optional separator index and walks positioned physical runs once. Each
participating run receives a boxed UTF-8 byte interval of its owned override;
only the final font run includes the separator. Lowering validates and decodes
that interval, so a mixed-face label neither duplicates its whole logical value
nor changes its shaped Unicode. `separator_run_visits` and
`separator_override_writes` count this work. Without separators, the original
text plan returns unchanged and ordinary run storage keeps its previous size.

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

## Focused item-arena evidence

The `reference_layout` pair exercises only the symbolic item builder, intrinsic
measurement, wrapping and exact row coverage. Its blank PDF is a common output
carrier for the harness, explicitly documented by the fixture; it does not
paint symbolic atoms or claim that they are resolved references. Metadata and
emission add fixed overhead to both measurements.

Pinned native `arm64mac`, dev optimization, 2026-10-18:

| Atoms | Exact allocations | Allocated bytes | Intrinsic item visits | Wrap visits | Rows |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 632 | 2,010,648 | 100 | 165 | 66 |
| 1,000 | 640 | 2,219,985 | 1,000 | 1,665 | 666 |

Validation also visits exactly each input item once per operation, and wrapping
visits fewer than twice the input items. Row coverage is contiguous, nonempty,
within the reserved width, and complete. Only eight additional allocations at
ten times the input are consistent with the geometrically growing item and row
arenas; the roughly 209 KB byte increase pays for their additional capacity.
There is no per-append retained builder or source suffix.

The ordinary rich-inline x10/x100 regression pair remains byte-identical and
matches its previous exact allocations and work: 27,369 / 241,905 allocations,
15,039,698 / 136,208,228 allocated bytes, and 18,003 / 52,739 PDF bytes. Both
independent semantic/paint validators pass. The new symbolic branch therefore
does not introduce a second shaping path into ordinary rich authoring.

## Shared table token domain

Table intrinsic-width errors now distinguish `Scalars(Range)` from
`Items(Range)`. The latter identifies source-free measured atoms without
claiming a Unicode interval. The discriminant widens `CellMeasure` and its
interning `CacheSlot` by 8 bytes. In fixtures that generate a public PDF and
perform a separate work probe, the resulting byte difference is exactly
`16 * (cells + interned sources)`. The unchanged rich-flow list cases have
18N cells and 2N + 20 interned sources, giving 3,520 / 32,320 additional bytes
at N=10/100; the nested small case has 52N cells and 41 sources, giving
3,152 additional bytes at N=3. Allocations, work and PDF bytes remain exact,
and these small representation costs stay inside the existing 10% byte guard.
No existing baseline was changed for them.

## Visible configured-label evidence

The furniture pair is the ordinary template pipeline with the new page-label
field. Its glyph strings are checked independently against emitted
`/PageLabels`, including Unicode prefixes, Roman front matter, repeated PDF
alphabetic labels and a decimal restart. Labels remain page artifacts and do
not enter body reading order. The pair uses 4,518 / 19,105 allocations and
6,458,019 / 27,978,223 allocated bytes at 3/30 pages. Field resolutions are
exactly 9/90 and artifact runs 9/90; output is 12,101 / 24,991 bytes.

## Target boundary

These tables record pinned `arm64mac` dev observations. Both native and
`x64musl` target expectations are verified by the complete native comparison
and strict affected replay followed by strict Linux integration. Each target
passes its exact allocation/work expectations and retained allocated-byte
guards, and the generated PDFs match the same immutable snapshots. The
integration, pinned Arlington and external PDF/A-4 evidence in
[manual composition](manual-composition.md#final-integration-closure) closes
the declared #49 subset without a new PDF/UA-2 claim. Requested-byte values
remain native observations rather than an assertion of cross-target equality.

## End-to-end body reference evidence

The `destination_references` native family generates each PDF through the
public facade, then performs a separate `KernelFacadeReferences` phase probe
for work counters. Both operations are inside `before_fixture_main`; these
allocation totals describe that complete fixture boundary, not one isolated
preparation call.

| Case | Exact allocations | Allocated bytes | Atoms | Measured items | Rows | PDF bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 sections | 8,480 | 8,977,811 | 15 | 258 | 18 | 15,743 |
| 20 sections | 30,512 | 34,409,599 | 87 | 1,180 | 72 | 29,082 |
| Inherited role, language and 75% scale | 4,408 | 7,246,410 | 1 | 55 | 3 | 14,450 |
| Ordered Latin/CJK policy | 5,047 | 7,390,088 | 2 | 58 | 4 | 12,639 |
| 13 atomic rejections | 4,531 | 4,988,492 | — | — | — | 10,642 |
| Scaled body and table alignment | 20,210 | 25,107,095 | 43 | 1,384 | 169 | 20,365 |

The section pair contains 4N + 7 references, 10N + 13 normalization chunks,
3N + 12 rows and 11N + 19 positioned pieces. Both wrap and placement visit
each measured item exactly once (258 / 1,180); literal cluster and glyph maps
visit 243 / 1,093 each. Field fit visits exactly one run per reference in the
pair (15 / 87), while name lookup uses the bounded registry search (24 / 342
steps). The one authored separator writes one override after walking the
41 / 239 positioned pieces. The ordered case proves the same separator is
partitioned into two actual font runs, with two override writes and no
replicated logical label. The inherited-role case has no separator and does
zero separator work.

Independent PDF inspection derives reference values from actual named target
pages and emitted `/PageLabels`; it checks reference-only paragraphs, cells
and links, list/callout semantic ownership, adjacent fixed advances, explicit
break positions, annotation rectangles/quads, inherited selected font, scale
and language, and artifact-only visible page labels. Seven rewritten PDF twins
(label rule, field position, logical separator, scaled baseline, wrapped End
alignment, Center reference advance and repeated header alignment) must fail
that oracle. All ten
new native cases (body family, visible-label pair and item-arena pair) passed
strict exact allocation/work and immutable snapshot replay through
`scripts/test.py` helpers. All six body-family PDFs pass pinned veraPDF
1.30.2 PDF/A-4 with zero failed checks, warnings or parser logs. PDFBox 3.0.8
and MuPDF 1.28.2 also extract and render the five successful reference PDFs as
whole original files: 62 page renders with exact glyph/ToUnicode text order.

Numeric furniture fields retain the formatter's explicit ASCII scalar-count
fact: their byte length already equals their scalar length. Only configured
page labels and running labels count Unicode prefix scalars. This avoids
allocating UTF-8 lists for short numeric strings. A focused native replay
restored the previous exact allocations for every numeric style, typography
and chapter sample; the new visible-label pair improves by 12 / 120
allocations (two numeric fields per page, public output plus work probe).
The field strings, geometry, deterministic work and PDF snapshots are unchanged.

The ordered-policy error audit consumes the policy rejection's explicit
source/cluster identity. It visits only the failing source and exact authored
contexts, decodes at most the rejected grapheme, and returns the existing
located coverage/script diagnostic with source-local scalar bounds. It does
not select a replacement face. The dedicated rejection fixture now has 13
checks, including a Common punctuation cluster for which the declared policy
has no covering face and an undeclared Arabic script in a resolved label.
Their additional font registration and two rejected preparations explain the
negative-only allocation increase from 3,104 to 4,531; successful ordered and
inherited-role reference counts remain unchanged. Numeric footer work removes
exactly one short-string allocation per public PDF page from the body pair
(3 / 21), with identical PDF bytes, fields and geometry.

## Measured typography and alignment parity

Measured blocks retain the maximum actual body-leaf font size before
pagination, including the authored style of pending reference leaves and
excluding generated list labels. That maximum is collected during the existing
literal/pending merge and stored beside each block's item span; it needs no
second leaf traversal or guessed reference value. Paragraph leading remains
its existing inherited value.

Table alignment consumes a separate visible advance that trims only terminal
literal U+0020 clusters. The fixed advance of every reference atom remains
part of the row. Exact source IDs and shaped cluster byte intervals identify
literal spaces; no resolved label is inspected or reshaped. A row whose last
item is an atom or a non-space returns immediately. When trimming is needed,
source byte views live only for that row and cover the whole source, never a
retained suffix. The backward walk stops at the first atom or non-space, so
alignment item visits are bounded by row count plus measured items, including
repeated-header reuse of the same visible-width fact.

The independent three-page geometry PDF uses a 10-point body theme, 75% code
and emphasis styles, and a registered 600-unit monospace font. Its emitted
glyph baselines prove that literal-only and reference-only paragraphs and
table cells use the actual 7.5-point maximum body size. A 10-point generated
list label shares its 7.5-point body's baseline without affecting that maximum.
Fixed 100-point End and Center columns contain wrapped literal spaces,
reference-only rows, and mixed rows. The oracle checks visible edges and
centers against those declared columns, preserves each 24-point reserved atom,
and repeats the checks on the continued header. An authored break after a
header reference retains its logical separator only on semantic body paint;
the repeated artifact carries no ActualText override.

This fixture has 1,384 measured items, 169 measured rows and 173 committed
row visits including repeated header reuse. Its backward alignment walks
visit 286 items. The existing section pair visits only four alignment items
at both scales; the inherited and ordered paragraphs do none. The per-block
size fact widens the dense `BlockItems` record by eight bytes, and the fixture
work list adds one eight-byte counter. The section pair's observed byte
increases are therefore `16 * blocks + 8` across its public preparation and
separate work probe: 264 / 1,128 bytes for 16 / 70 blocks. Inherited and ordered
cases add 56 bytes each. Allocation counts and all previous PDF snapshots are
unchanged. Existing allocated-byte baselines remain unchanged because these
reviewed representation costs are well within their 10% guard; only the new
counter and new geometry case receive new exact expectations.

## Repeated headers without container bands

An ordinary unpainted table needs no per-page container lead-band arena. The
measured reference path now retains the validated global continuation-frame
offset as one scalar on its existing plan. Header placement uses that default
when the scoped page-frame arena is empty, the committed scoped frame when it
is present, and the accepted padding-aware band when a container is active.
No header position is recovered from paint or changed after page selection.

The three focused kernel regressions cover no template, a global continuation
frame with a nonzero top, and a scope whose continuation top differs from the
global default. Each has an unpainted continued table and no lead-band arena;
its repeated header must use the exact selected frame. The public Geometry
PDF additionally checks every repeated glyph baseline and cell alignment.
This keeps the no-container arena elision and the original ordinary-table
allocation counts while carrying the geometry fact its measured consumer
needs.

All 651 canonical kernel tests pass. A fresh pinned native Geometry run
retains its exact 20,365-byte PDF and complete work vector, including 173
committed row visits and 286 alignment item visits. Its observed allocation
count falls from 20,212 to 20,210 and requested bytes from 25,107,207 to
25,107,095: the two preparation/probe pipelines each omit one 56-byte
geometrically allocated lead-band arena. The new scalar adds no arena.
Only this reviewed allocation improvement updates the exact expectation;
the existing allocated-byte ceiling remains unchanged.

All ten reference, visible-label and item-arena cases and all seven scoped
table-paint controls then passed strict `scripts/test.py` replay using the
same retained cold-built executables: exact allocations and work, unchanged
snapshots, the existing byte guards and every registered independent byte
validator. The other sixteen cases retain their previous exact counts and
work vectors. No PDF snapshot changes in this correction, so the recorded
original-file conformance, mutation and reader evidence still applies.
