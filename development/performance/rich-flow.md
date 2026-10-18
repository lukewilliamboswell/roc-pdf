# Rich list bodies and continued callouts

Issues #52 and #53 extend the existing flow compiler. Feature evidence is
recorded below as it is run; this change makes no new PDF/UA-2 claim.

## Representation and ownership review

List bodies accept source blocks, figures and tables using their existing
semantic subtrees. `Pdf.callout` is separate from measured `CustomBlock`:
its data-only panel, padding and fragmentation describe a `Div` of ordinary
flow children. Source ActualText and header/caption relationships remain
facts from semantic planning, never inferred from paint order.

Horizontal geometry is calculated after label shaping, before table column
resolution. The line plan transfers its existing dense geometry/offset/end
arenas to pagination; tables, captions, cells, fills, rules, repeated headers
and figure fit share their actual parent frame. No source or resource
payload is copied to calculate frames.

Pagination retains flat paragraph/source/table-row units and scalar unit/line
continuation. Callout spans use dense IDs and prefix transition heights.
Each accepted candidate reserves open containers' bottom padding. Reopening
ancestors precedes repeated headers. A layout-only span accounts for the
outer table row-gap decoration footprint inside a callout. Semantic callout
nesting shares the existing container-depth16 bound; layout span depth is
at most17 because table cells cannot contain flow blocks. Both are checked
before growing their corresponding ancestor arena.

Exact context and ancestor writes, accepted fragment updates and fragment
writes supplement existing metric-read/line/page candidate counts. All
buffers use geometric append or exact one-time capacity, never reserve/concat
per append. No suffix slices, rollback scenes, recursive pagination callbacks,
whole-document accumulator aliases or remeasurement on continuation occur.
Normalized sources, glyphs and resource payloads remain owned once; temporary
context/ancestor arrays die after pagination. Reports retain compact accepted
rectangles and paths, never discarded plans or payloads.

With maximum depth D=17, frame planning and container preparation use
O(blocks + groups + D*containers), pagination retains its existing bounded
candidate scan plus O(D) transition work at a boundary, and panel collection
uses O(D*accepted-unit-fragments). Storage is linear in blocks, containers,
accepted fragments and output commands. Counts are bounded by existing facade
block/node/page limits and the explicit fragment/scene/report budgets.

## Verification

The `rich_flow` harness family covers generated wide list labels and rich
children (10/100), one long rich-paragraph callout (10/100 paragraphs), and
nested callout/list/source/figure/table composition (3/30). Its source rows
include blank lines and trailing spaces; figures retain alternatives and
captions; tables repeat headers. Public output and a compiler work probe use
identical authoring/font/page facts. Existing CustomBlock cases remain
regressions for their measurement and unsplittable diagnostics.

Pinned native metrics, independent checks, negative cases and reviewed
baseline causes are recorded below. The complete native comparison and strict
affected replay, followed by strict Linux integration, close the declared #52
and #53 subsets and establish byte-identical output across targets; see
[manual composition](manual-composition.md#final-integration-closure).

### Initial pinned native observation, 2026-10-18

The pinned `dev`, `arm64mac`, `--no-cache` build was produced through
`scripts/test.py`'s `build_case_sources`. All twelve family cases generated
successfully with exact work vectors recorded in `tests/spec.json`:

This table preserves the initial observations. The default-frame and
repeated-header arena reviews below record subsequent allocation removals;
the accepted exact expectations are maintained in `tests/spec.json`.

| Case | Roc allocations | Allocated bytes | Pages |
| --- | ---: | ---: | ---: |
| rich list items 10 / 100 | 130134 / 1252926 | 73369891 / 743807483 | 12 / 112 |
| paragraph callout 10 / 100 | 35068 / 314682 | 15160221 / 103939473 | 2 / 12 |
| nested callouts 3 / 30 | 107123 / 1013043 | 56007561 / 521559571 | 9 / 81 |
| fresh callout records 10 / 100 | 11051 / 80329 | 6905079 / 33216079 | 1 / 6 |
| deliberately shared callouts 10 / 100 | 11041 / 80229 | 6903879 / 33204079 | 1 / 6 |
| zero-padding filled table | 79855 | 35056637 | 3 |
| eighteen atomic negative checks | 6487 | 19182015 | 1 |

For 10x input, list allocation counts grow 9.63x and allocated bytes 10.14x;
nested composition grows 9.46x and 9.31x. Paragraph and repeated-content
cases amortize the fixed font/profile and output setup. Metric reads, line
and page candidates, context/ancestor writes and accepted container updates
are explicit deterministic counters, rather than inferred from elapsed time.
The nested pair records 294/2940 accepted container updates and 111/1110
unit contexts; it does not rescan or copy preceding page fragments.

These are new-feature observations, not a mechanical acceptance of existing
regression changes. Compared with the initial unregistered fixture drafts,
source foregrounds add two physical paint pieces per coloured source line,
real LF/final LF retain empty logical rows, and typed integer row labels avoid
unintended decimal suffixes. The work probe now carries the same PDF/A-4
metadata/profile facts as public preparation, adding four output objects to
its previous metadata-free probe. These changes explain the draft PDF and
metric differences. Existing-case deltas still require integration review.

The zero-padding case paints actual header/body fills, column rules and a
frame. Its layout-only table span reserves half the row gap at both ends of
each fragment, including a caption on the opening fragment. The independent
oracle checks those explicit decoration bounds even when authored callout
padding is zero. Reports count every Callout reading-order obligation before
allocating entries; an exact one-entry-short budget rejects atomically.

All 586 package unit expectations passed under the pinned native compiler.
The eighteen negative checks cover invalid style and children, impossible
width/fresh-page height, required whole-container/source/figure placement,
callout depth17, list depth5 across callouts, exact report-entry exhaustion,
and an explicit one-page work limit. Every public rejection returns no PDF.
The ten unique family PDFs passed veraPDF 1.30.2 PDF/A-4 with zero failed
checks. The byte oracle reads structure, CID text, original Code ActualText,
font widths, profile-aware colours and artifact rectangles directly; it
uses no Roc report, continuation record or pagination counter as an oracle.

At this initial native observation, `x64musl` fields were provisional mirrors
because local Docker was unavailable. The subsequent strict Linux run verifies
the target expectations; complete integrated closure is recorded in
[manual composition](manual-composition.md#final-integration-closure). No new
PDF/UA-2 claim follows. All twelve final cases pass strict `scripts/test.py`
replay: exact allocation counts, deterministic work, recorded-byte guard,
unchanged snapshots and all registered byte validators. Mutation and whole-file
reader evidence follows below.

The independent self-test passed all eleven positive cases and rejected seven
validly reserialized mutation twins: lost LBody ownership, a replaced callout
Div, an expanded panel edge, a monochrome foreground, changed canonical
source LF, a repeated header changed from Pagination to Layout artifact,
and a table fill expanded outside its zero-padding panel.

The ownership pair retains one immutable callout for the shared path. The
fresh path uses runtime-distinct report-only names, guaranteeing distinct
authoring records while preserving identical visible content, output bytes
and compiler work. The native fresh path costs exactly one extra allocation
and 120 bytes per callout; the corresponding shared path does not clone the
retained record. The initial constant reconstruction helper could be hoisted,
so it was strengthened before treating this pair as ownership evidence.

Whole-file PDFBox 3.0.8 and MuPDF 1.28.2 reader checks passed 54 page renders
across five representative cases. Every page retains its exact decoded
text/order, body geometry and visible ink; both readers retain the purple
source foreground. MuPDF uses explicit glyph/ToUnicode extraction via
`ignore-actualtext`, consistent with the established source-block reader
lane; this is not a new claim about parent-ActualText reader behaviour.

At integrated checkpoint `c3eb5a8`, all twelve cases were rebuilt and strictly
replayed through `scripts/test.py`: recorded allocation counts, deterministic
work and PDF snapshots remained exact. The paragraph/ownership cases retained
their exact requested bytes too. Table/source paths requested at most 0.012%
more bytes after integration, within their existing byte guards; no allocation
or byte baseline was changed. The independent rich-flow self-test still
rejected all seven mutation twins. Combined scope/reference/vector evidence
is recorded in [technical manual](technical-manual.md).

The small integrated table-path byte delta has an exact representation cause:
`KernelFacadeTables.WidthToken` distinguishes scalar ranges from measured
reference-item ranges. Its tag widens both `CellMeasure` and `CacheSlot` by
8 bytes. This fixture builds public preparation and a private work probe, so
the combined cost is `16 * (cell measures + interned-source cache slots)`.
The list pair has `18N` cells and `2N + 20` cache slots: `320N + 320` gives
exactly 3,520 / 32,320 extra bytes at N=10/100. The nested pair has `52N`
cells and 41 cache slots: `16 * (52N + 41)` gives exactly 3,152 / 25,616
bytes at N=3/30. These are explicit token-domain facts needed by reference
measurement, with unchanged allocation/traversal counts and no copied growing
buffer. Existing baselines remain unchanged.

## Default table-frame allocation review

An isolated pinned native allocation-size trace compared the original main
`7cdd4d1` with the rich-flow implementation `71fff41` on the unchanged
`page templates letter x6` fixture. Allocations rose from 31,722 to 31,724;
work and the 23,130-byte PDF were identical. Each of the fixture's two
pipelines allocated one additional 24-byte arena for its single table's
`{ offset, width }` frame. The preexisting group columns, group offsets and
block geometry allocations moved earlier in the pipeline; they were not
additional allocations. The same trace accounted for the remaining
232-byte-per-pipeline increase through widened layout records. This is a
fixed representation cost, not repeated growth or a super-linear traversal.

`KernelFacadeLines` now selects the table kernel's existing empty-frame
contract only when the earlier block geometry proves every table has offset
zero and the full content width. If any table uses a narrower or shifted
parent frame, it builds the complete dense table-indexed arena, including
default frames before and after that table. No frame is inferred from paint.
The default check and optional arena construction take at most two group
traversals; the latter owns one exact-capacity list without a fallible growing
builder. A unit case covers a default/narrow/default sequence.

The three existing letter scales replayed through `scripts/test.py` with
unchanged allocation baselines, deterministic work and exact PDF snapshots:

| Paragraphs | Exact allocations | Observed allocated bytes | PDF bytes |
| ---: | ---: | ---: | ---: |
| 6 | 31,722 | 24,528,826 | 23,130 |
| 20 | 68,405 | 54,467,551 | 30,577 |
| 200 | 534,892 | 426,196,384 | 125,791 |

Their allocated-byte differences stay within the existing guard and retain
the separately reviewed typed table-token and chapter-scope storage costs.
No legacy allocation, work or PDF baseline changed.


Nested-callout x3/x30 replay also retains its exact 107,123 / 1,013,043
allocations, complete work vectors and 27,236 / 149,551-byte PDF snapshots.
Both use nondefault enclosing frames, so their table arenas remain present.
Their observed allocated bytes, 56,010,713 / 521,585,187, include the reviewed
typed table-token cost. All registered independent byte validators pass.

The new zero-padding table case is eligible for the explicit default frame.
Its reviewed allocation count decreases by two, 79,855 to 79,853, for the same
two removed 24-byte arenas; work and the 20,088-byte PDF remain identical.
Its observed 35,060,525 allocated bytes include the existing token-domain
widening, less those 48 bytes. This result is recorded separately from the
unchanged legacy letter baselines rather than concealing the new-case change.

## Repeated-header placement storage

The first container-aware pager retained an explicit lead band for every
continued table header, even when no container consumed that placement fact.
Each 24-byte band stored the accepted page, block and top. Appending the bands
grew a geometric arena: the legacy invoice x50/x500 cases gained 4/10
allocations across their two pipelines, split rows gained 6 and footer carry
gained 2. The counts match the continued-header arena capacities, rather than
the number of text rows. Single-page tables and a whole table moved intact to
its next page had no continued header and retained their exact counts.

Both concrete pagination and source-free row choice now retain these bands
only when the earlier container context is active. Ordinary headers already
consume their selected page frame top and need no separate placement arena.
Accepted rows, page usage, scope facts and deterministic traversal counters
remain unchanged. The check uses indexed container ownership, with no new
traversal or retained per-fragment storage on the common path.

Active containers keep their explicit bands even when their padding is zero:
their painted panel must still include the repeated header. Unit checks cover
this case in both pagination paths and compare their exact panel geometry;
the existing positive-padding check remains in place.

An isolated pinned native replay through `scripts/test.py`, after all 645
canonical kernel tests passed, restored the unchanged legacy baselines:

| Case | Exact allocations | Observed allocated bytes | Exact PDF bytes |
| --- | ---: | ---: | ---: |
| Invoice x50 | 54,207 | 43,584,640 | 28,819 |
| Invoice x500 | 395,154 | 336,059,822 | 122,641 |
| Column spans and two headers | 9,598 | 7,869,116 | 16,113 |
| Split rows | 58,703 | 42,456,530 | 20,863 |
| Footer carry | 24,514 | 20,555,932 | 18,943 |
| Whole-table keep | 27,774 | 12,412,692 | 13,800 |

Every work counter and PDF snapshot remains exact. The small byte differences
retain the previously reviewed typed-token/frame representation costs and stay
within the existing guards; no baseline was changed.

## Default table rejection ordering

Resolving parent frames before table measurement is necessary for tables
inside lists, sources, custom blocks and callouts. Applying that order to
ordinary tables also built three temporary arenas (group columns, group
offsets and block geometry) before rejecting an unbreakable cell or impossible
column widths. The existing fifteen-negative matrix therefore gained six
allocations across its two early table-layout rejections, despite emitting the
same valid carrier and retaining the same diagnostics.

The line stage now defers that geometry only when earlier normalized stores
prove there are no lists or inset containers and the actual shaped block
mapping has no list labels. Those facts establish the table kernel's existing
empty-frame contract: full content width and zero offset. Tables resolve their
intrinsic widths once; only success proceeds to the single existing geometry
pass through `Calculate`. Every other document retains geometry-first
measurement through `Calculated`, including zero-padding containers. No
measurement or validation is duplicated, and positive indent validation stays
before the branch. A unit check covers default, actual-label and zero-padding
container cases.

All 648 canonical kernel tests passed. The pinned native fifteen-negative
case now strictly retains its original 56,677 allocations, work `15,11521`
and exact 11,521-byte carrier PDF; its observed 61,508,120 allocated bytes
remain within the unchanged guard. The same fresh `scripts/test.py` executable
also strictly replays all six ordinary table controls in the preceding table,
with their exact counts, work, bytes and PDF snapshots unchanged from the
lead-band correction. No rejection or success baseline was changed.
