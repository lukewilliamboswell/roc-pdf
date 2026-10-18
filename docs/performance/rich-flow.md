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
baseline causes are recorded below. Cross-target observations and the full
integrated regression suite remain separate completion evidence.

### Pinned native observation, 2026-10-18

The pinned `dev`, `arm64mac`, `--no-cache` build was produced through
`scripts/test.py`'s `build_case_sources`. All twelve family cases generated
successfully with exact work vectors recorded in `tests/spec.json`:

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

`x64musl` entries currently mirror native observations only to satisfy the
suite's two-target schema. They are **provisional, not observed evidence**:
the local Docker daemon does not answer even an escalated bounded discovery
request. No cross-target, fully integrated-suite or new PDF/UA-2 conformance
claim follows from this native record. All twelve final cases passed strict
`scripts/test.py` harness replay: exact allocation counts, deterministic
work, recorded-byte guard, unchanged snapshots, and all registered byte
validators. Mutation and whole-file reader evidence follows below.

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
