# Gate 6 ordinary tables

This slice (S6) implements `reference-documents-v5`, which it introduces. It
makes `Pdf.table`, `Pdf.row`, `Pdf.cell`, `Pdf.header_cell`, and
`Pdf.spanning` executable, represents row spans (`Pdf.row_spanning`) so
they reject with a located diagnostic, replaces the `Pdf.simple_table`
placeholder, resolves the ordered-policy Common-run text row, and raises the
facade's content bounds with a located budget diagnostic. It closes no
Gate 6 capability as a whole and makes no PDF/UA-2 claim: `PdfUa2` stays
`defined_only`.

## Scope and non-goals

In scope:

- tables with an optional caption, declared columns (`Fixed`, `Share`,
  `Content`; `Start`, `End`, `Center`), header, body, and footer rows,
  header cells with declared scopes, and column spans;
- `Table > (Caption > P, THead, TBody, TFoot) > TR > TH/TD` structure with
  `Scope`, `ColSpan`, generated element identifiers, and `Headers` derived
  from declared scopes, with the kernel enforcing agreement between
  `Headers` and `HeaderFor`;
- a table geometry layer (measured cell widths, the column-width algorithm,
  cell offsets, padding, alignment, and rules from `Theme`);
- `KeepRows` and `SplitRows` row fragmentation, the table-start unit, the
  footer group with preference R3, and header rows repainted on
  continuation pages as a new `RepeatedHeader` page artifact;
- artifact-owned text through text materialization, fragments, scenes, text
  ownership, and content lowering;
- the ordered-policy rule for runs whose script stays Common;
- raised facade bounds and the located `document.content_limit`;
- an extended independent structure checker, a harness family, and ledger
  rows.

Not in scope: row spans and complex tables (Gate 8), block content inside
cells, header-row shading, a distinct face per cell role, the preparation
report (which will expose relaxations and repeated headers), and the
reference invoice and report documents themselves (a later slice builds
them from these constructors).

## Authoring and normalization

`Document.Block` gains `Table(TableSpec)`. A row is the nominal
`Document.Row` and a cell the nominal `Document.Cell`, holding its inline
content, its kind (`DataCell` or `HeaderCell(Scope)`), and its column and
row spans.

Normalization appends, without a frame stack (tables have fixed depth):

- a `Table(U32)` group whose payload indexes the new `tables` arena
  (columns, row split, caption flag, and per-section row counts);
- the caption, when present, as a `Paragraph` leaf of the table group;
- one `TableRow(TableSection)` group per row, whose `position` is the row's
  index in its section;
- each cell as a rich-paragraph leaf of its row group, with the inline arena
  exactly as a rich paragraph, and a `cells` arena record (leaf, kind, spans)
  in leaf order.

The group payloads stay one byte or a `U32`, so the 56-byte group record and
the allocation profile of documents without tables are unchanged, and those
documents allocate neither arena.

Diagnostic paths name a caption `contents[k].caption`, a row
`contents[k].table.body_rows[r]` (or `header_rows`, `footer_rows`), and a
cell `...cells[c]`, below which rich-inline paths continue.

## Semantic planning

A table plans its whole subtree when its group opens (`plan_table`), then
the block walk resumes after its last group and leaf.

**Validation**, in authored order: a table needs a column and a body row
(`table.empty`); every cell has no row span (`table.row_span`,
`FeatureUnavailable`) and non-empty, valid inline content
(`table.cell_empty`, or the rich-inline codes); every row's spans are
positive and sum to the column count (`table.grid_mismatch`); and the table
has a header cell (`table.header_missing`).

**Nodes** are numbered in preorder: `Table`, the optional `Caption > P`,
each present section before its rows, each `TR` before its cells, each cell
before its inline elements. `place_table` writes the content spine in the
same preorder, reusing `place_rich` for cell content with the cell role
(`TH` or `TD`) instead of `P`.

**Associations.** A data cell's `Headers` are the `Column`- or
`Both`-scoped header cells of earlier rows in the columns it spans (a
per-column list, merged and deduplicated only for spanning cells), then the
`Row`- or `Both`-scoped header cells of its own row. Header cells carry no
`Headers`. Every cell carries the identifier `c` plus its one-based cell
ordinal in six digits, so identifier order is store order and the IDTree
lowers without sorting. Each `Headers` entry is also a `HeaderFor`
relationship, stored grouped by cell in node order.

**Agreement (S3's open issue).** `KernelSemantics` now proves `/Headers`
and `HeaderFor` state the same associations: one forward cursor over the
relationships walks every node's `Headers` values in order, requiring the
cell's own element identifier and the header's identifier value, and no
relationship may remain. It allocates nothing and costs O(nodes + values +
relationships). A mismatch is `HeaderAssociationMismatch`.

**Bounds.** Semantic bound checks now carry the block at which they were
crossed (`BlockLimitExceeded`); a table checks its totals at its first
leaf. The facade maps them to `document.content_limit` (`BudgetExceeded`)
naming the table or block. The facade bounds rise to 16,384 occurrences,
nodes, and sources, 65,536 content-spine items and attributes, and 16,384
leaf blocks; every later stage's bound is at least as large, and the object
store's name, byte-string, value, and array budgets rise so the structure a
16,384-node document lowers stays inside them. The x500 invoice (3,113
structure elements, 2,519 identifiers, 4,010 associations) is well inside.
Page artifacts, which remain unsupported, keep their unlocated rejection.

## Shaping and text

Cells are rich paragraphs, so they take the ranged preparation. Header
cells paint in `Theme.with_table_header_color` when set.

**Common runs.** Script itemization leaves digits, punctuation, and spaces
beside another script as `Zyyy` runs: `1,284`, `+10.0%`, and the spaces in
`Café 中 PDF` all did. The ordered path rejected them as
`UndeclaredScript`. Now `declared_script` admits `Zyyy` and `Zinh`, and
`Font.Registry.plan` selects for a Common or Inherited cluster the first
face in policy order whose coverage holds it, without a script requirement.
The selected shaper already accepts a request whose script equals its run's
script. The single-face path is unchanged.

## Table geometry

`KernelFacadeTables` runs between shaping and line layout, only for
documents with tables.

- **Measurement.** `KernelLineLayout.measure_logical` gives a whole-source
  logical request's max-content width (widest line between mandatory
  breaks) and min-content width (widest piece between opportunities, with
  its trailing space) and that piece's cluster range, in O(clusters) with
  the same boundary and advance validation as line selection. Laying the
  request out at any width of at least its minimum never meets an
  unbreakable piece. Measurements are cached per interned source (with a
  size check), so repeated cell texts measure once.
- **Columns.** The algorithm of `reference-documents-v5`: exact fixed
  widths; content columns at their maxima, reduced in proportion to slack;
  shares divided by weight, with a share below its minimum fixed there and
  the rest redistributed; millipoint remainders left to right.
- **Cells.** Each cell's text box is its spanned columns less the padding
  on both sides. A spanning cell's widest piece is checked against its box.
  Errors are `layout.table_width` and `layout.unbreakable_token`, the
  latter with the piece's scalar range.

`KernelFacadeLines.Plan.build_authoring` lays every cell out at its text
width through the logical batch (the template cache key includes the
width); documents without tables take `build` unchanged.

## Pagination

`KernelFacadePages` builds a table's units instead of one unit per leaf:

- the caption: unsplittable, requiring its next unit;
- one unit per row with `grid` synthetic lines of the cell leading, `grid`
  being its tallest cell's line count. All cells share one leading and
  start at the row top, so every grid line is a line boundary of every
  cell; rows are separated by the theme's row gap;
- header rows: unsplittable, requiring their next unit, so the caption,
  header rows, and the first body row's first placement unit are placed
  together;
- body rows: unsplittable under `KeepRows`, else splittable with the
  orphan and widow minimums on the grid; the last body row prefers to keep
  with the footer (`Preferred(FooterCarry)`, R3);
- footer rows: unsplittable, one required group when there are several.

**Repeated headers.** `KernelPageLayout.Block` gains `lead`, height
reserved at the top of any page on which the block starts or continues.
Body and footer rows carry the header rows' height plus the gap after them.
The page scan and materialization start their used height at the page's
first block's lead, and every fresh-page check of an unsplittable block, a
keep group, or a required chain adds its first block's lead. A row taller
than a page with its lead is `layout.oversize_row`.

**Rebuilt placements.** After page layout, placements are rebuilt page by
page: a leaf's lines keep theirs; a row fragment's cells paint their lines
at their grid lines' baselines, cell by cell, each aligned by its visible
advance (trailing spaces excluded) in its first column's alignment. A page
whose first unit has a lead first repaints the table's header rows at the
top of the page as artifact rows. Rules are rectangles centered in the gap
below the last header row (original and repainted) and above the first
footer row when a body row precedes it on the page.

Page-layout errors of a document with tables name units (a leaf or a row
group) and keep sources (an authored group or a table's footer rows), which
the facade maps to authored paths.

## Artifact text

A repainted header run duplicates the header cell's shaped clusters and
references its occurrence, so its Unicode, ActualText, and ToUnicode facts
are the header's. It is not content:

- `KernelFacadeText` marks the runs of artifact rows and excludes their
  clusters from the once-each coverage proof;
- `KernelFacadeFragments` gives them no fragment (fragment ids stay dense
  over the other runs), and navigation neither anchors nor links them;
- `KernelFacadeScenes` owns them by a `PageArtifact(RepeatedHeader)` group,
  and rules by `PageArtifact(Decoration)` groups with one rectangle path;
- `KernelTextOwnership.Plan.build_with_artifact_text` accepts text owned by
  an artifact group, still exactly once; `build` still rejects it;
- content lowering marks the group `/Artifact <</Type /Pagination>> BDC`.

The `RepeatedHeader` kind has no `/Subtype`: ISO 32000-2's pagination
subtypes name page headers, footers, and page numbers, not a table's header
rows.

## Ownership, copying, retention, and complexity

- **Normalization** is O(cells + inline records + text bytes); planning is
  O(cells + inline records + associations), with one column-header list per
  column and a reused row-header list. Placement finds each cell's ordinal
  by binary search over the leaf-ordered cell arena.
- **Geometry** is O(clusters of distinct cell texts + cells + columns²
  per table): the share redistribution settles at least one column per
  pass.
- **Lines, pages, text, fragments, and scenes** stay linear in lines and
  runs; repeated headers add header lines per continuation page.
- **Allocations.** Documents without tables take the previous code paths
  for semantics, shaping, lines, pages, text, and scenes: the new arenas,
  row lists, artifact lists, and rules are empty and unallocated there. In
  pages, only `End` and `Center` lines ending in a space pay for a byte
  view of their source.
- **Retention.** Nothing new is retained past preparation; the geometry
  plan shares the interned sources.

## Evidence

**Package expects.** `KernelLineLayout` (width measurement),
`KernelPageLayout` (lead reservation and oversize with lead),
`KernelSemantics` (Headers ↔ HeaderFor agreement, both directions),
`KernelFacadeSemantics` (preorder roles, identifiers, associations, and
four rejections), and `Pdf` (lowered roles, attributes, `/Headers` bytes,
and located rejections).

**Harness family** `tests/tables` (`tables-v1`, pinned
`nightly-2026-09-26-d6267b4`, cold cache, full harness order):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| invoice x50 | 4 | 110,221 | 356 nodes, 269 cells, 410 associations, 104 measurements (165 cache hits), 341 lines, 69 candidates, 3 repeated headers, 347 fragments, 21 artifact runs |
| invoice x500 | 27 | 897,797 | 3,113 nodes, 2,519 cells, 4,010 associations, 104 measurements (2,415 cache hits), 3,098 lines, 519 candidates, 26 repeated headers, 3,161 fragments, 182 artifact runs |
| column spans and two header rows | 1 | 15,966 | 47 nodes, 29 cells, 51 associations, 33 lines |
| split rows | 6 | 124,403 | 23 nodes, 12 cells, 263 lines, 254 candidates, 5 repeated headers |
| footer carry | 2 | 50,832 | 216 nodes, 171 cells, 175 lines, 1 repeated header |
| ordered numeric cells | 1 | 6,834 | 19 nodes, 9 cells, 8 associations, 18 fragments on two faces |
| atomic negatives | 1 | 72,700 | 14 rejections |

- **Invoice xN** holds the reference details table (row headers, no header
  rows) and the items table with its caption, one column-header row, N
  body rows cycling the eight reference products and fit-out sites
  (row-header item codes, a French span, end-aligned amounts in fixed
  columns), and three totals rows spanning four columns.
- **Spans** has two header rows (a `Both`-scoped corner, a `Column` header
  spanning two columns), a spanning data cell, U+2212 minus signs, a center
  column, and a themed header color.
- **Split rows** breaks a 150-sentence row under `SplitRows` across six
  pages, repainting the header row on each continuation.
- **Footer carry** has 32 single-line rows: the last body row fits on the
  first page but the three totals rows do not, so R3 moves it to the second
  page with the totals (INV-A5), under the repainted header, relaxing
  nothing.
- **Ordered** paints `1,284`, `+10.0%`, `-2.1%`, and `Café 中 PDF` (in a
  cell and a rich paragraph) through a policy of the packaged Latin face
  registered as a caller face and a Han face.
- **Atomic negatives** each return their stable code and paths and no
  bytes: `table.header_missing`; three `table.grid_mismatch` forms (too
  many spans, an empty row, a zero span); `table.row_span`; two
  `table.empty` forms; `table.cell_empty`; `layout.oversize_row`;
  `layout.unbreakable_token` (a 128-hex-digit serial);
  `layout.table_width`; `layout.keep_conflict` naming the keep, its first
  member, and the table; `semantics.list_item_content` for a table in a list
  item; and `document.content_limit` for a table of 16,503 cells.

**Linear scale pair.** From x50 to x500 (10× the body rows), nodes grow
8.7×, cells 9.4×, associations 9.8×, row visits 8.8×, lines 9.1×, candidate
visits 7.5×, repeated-header paints 8.7×, fragments (MCIDs) 9.1×, and
allocations 8.1×. Column-width passes stay one per table and cell
measurements stay 104, since repeated cell texts hit the per-source cache.
All counters are within the linear bound.

**Independent checkers.**

- `scripts/check_structure_semantics.py` adds table checks derived from the
  bytes: grid regularity (equal column spans per row, no row spans), a
  `/Scope` on every `TH`, `/Headers` targets resolving through the IDTree to
  `TH` elements, `THead` content only on the table's first page, and a
  text-bearing, MCID-free `/Artifact <</Type /Pagination>>` sequence on
  every later page of a continued table. Its self-test adds the spans and footer-carry
snapshots and three mutation twins (an irregular `/ColSpan`, a `/RowSpan`,
and `/Headers` naming a `TD`); it covers 8 snapshots and rejects 17 twins.
- `scripts/check_rich_inline.py` decodes artifact text but excludes it from
  logical text, so structure order still equals paint order on every table
  case except split rows, where a row split across pages necessarily paints
  its later cells before an earlier cell's continuation.
- `scripts/check_pdfa4_structure.py` no longer mistakes the structure type
  `/S /TR` for the excluded transfer-function key `/TR`.

**External lanes.** veraPDF PDF/A-4 `--cases` passes all 45 Archive
snapshots, including the seven tables snapshots, with zero failed checks,
and `--standard-cases` fails only the deliberate omissions. Arlington
`--cases` passes all 191 case files and the gallery. Informationally, the
pinned veraPDF PDF/UA-2 profile reports no table (8.2.5.26) failure on any
tables snapshot; the only failure is the PDF/UA identification the package
does not claim (clause 5).

**Rendering.** PDFium (page 2 of the invoice x50 case, extracted with the
vendored qpdf, because the adapter renders one page) paints the repainted
header row and its rule above the continued rows; MuPDF renders every page
of the invoice, split-rows, and footer-carry cases the same way.

## Reviewed rebaselines

Every delta comes from a cold-cache, full-order run; causes were confirmed by
same-cache A/B builds.

- **Bytes.** No existing snapshot or gallery PDF changed; the six gallery
  examples rebuild byte-identically.
- **Allocations.** No existing case changed. Two intermediate regressions
  were found and removed. Carrying the table specification inline in
  `Document.Block` enlarged every authored block and cost one allocation in
  the x1000 and x10000 simple-list normalization cases; a same-cache A/B
  that boxes the payload restores both exactly. The rich-inline negatives
  cost four more allocations while `table.cell_empty` was decided by
  re-normalizing the document on every empty-paragraph rejection; with
  planning reporting `TableCellEmpty` directly (and the payload boxed), a
  same-cache A/B against the previous commit shows identical counts.
- **Work counters.** The kernel lowering case's `attribute_visits` rises
  from 7 to 8: the new agreement check counts its one `Headers` value.

**Transient failures.** One of four full runs hit a compiler segfault in
`roc check tests/authoring/authoring.roc`; the rerun passed. One run failed
the contracts preflight on an unsorted ledger reference list, fixed before
the next run.

## Pre-existing defects found

- **`/S /TR` in the PDF/A structural checker** (fixed above).
- **Quadratic object-store time.** Structure lowering of large documents
  takes time super-linear in the element count while allocations stay
  linear: 100, 200, and 400 invoice rows take 14.1, 37.2, and 111.0 G
  instructions, and the existing layout-policies groups x50 and x500 cases
  4.9 and 83.5 G. A bisection places it in `KernelTaggedObjects`
  structure-element and IDTree lowering. `KernelObject`'s builder functions
  update a list reached through the builder record (`{ ..builder, store: {
  ..builder.store, values: builder.store.values.append(value) } }`) while
  the record is still live, so the append copies the list. An experiment
  destructuring the builder in `add_value` alone removed 37,000 of 324,000
  allocations at 200 rows and halved the instructions at 400. Every
  object-producing case's allocation count would change, so the fix is left
  to its own reviewed rebaseline (see open issues). **Resolved** by S6b
  ([lowering-uniqueness.md](lowering-uniqueness.md)): the copies came from
  several ownership patterns in lowering, semantic planning, and content
  emission, and from fixtures reusing procedures cached by other fixture
  programs; the x500 invoice now allocates 1.7 GB instead of 35 GB (67 GB in
  harness order) and its instructions grow linearly.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: table normalization, planning, geometry, pagination with repeated headers, artifact text, and rules, with allocation and work evidence |
| Facade | Executable for `Pdf.table` and its constructors with stable located diagnostics |
| Advanced integration | `KernelPageLayout.Block.lead`, `KernelFacadeTables`, and `KernelTextOwnership.Plan.build_with_artifact_text`; no separately authored consumer |
| Conformance | `ROC-PDF-PDF20-TABLE-SEMANTICS`, `ROC-PDF-PDFUA2-8-2-5-26-TABLE-HEADERS`, and `ROC-PDF-PDFUA2-8-2-5-26-TABLE-REGULARITY` are `implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Table styling follow-ups (examples showcase)

These slices close layout gaps found while rewriting the gallery. Each keeps
the stage contracts above: presentation is `Theme` or table policy, cells
keep their `TH`/`TD` semantics, and paint the package adds is an artifact.

### Row header color

`Theme.with_table_header_color` colored every header cell, so a first column
of `Row`-scoped headers took the column header color. `TableStyle` now has a
separate `row_header_color` (`Theme.with_table_row_header_color`): scope
`Row` paints in it, scopes `Column` and `Both` (a corner heads both
directions and sits in a header row) in `header_color`. Both default to
`Inherited`, so a theme that sets neither never searches the cell arena.
The shaping lookup is unchanged: one binary search over the cells per rich
block inside a table row, now taken when either color is set.

Evidence: the spans case themes the column headers blue and the row headers
slate. Its allocation count is unchanged (11,059); allocated bytes grow by 65
(+0.002%) and output by 24 bytes: the row headers' fill-color operands
are the slate value instead of the blue one. Every other table case is unchanged.

### Row and cell fills, zebra stripes, and body rules

`TableStyle` gains `header_fill`, `body_fills` (`{ odd, even }`, counted by
the row's index in the table body so stripes are stable across pages),
`footer_fill`, and `body_rule` (`Theme.with_table_header_fill`,
`with_table_body_fills`, `with_table_footer_fill`, `with_table_body_rule`).
`Pdf.shaded(color, cell)` gives one cell its own fill. All default to
none.

Ownership and paint order. A fill is presentation, not content: it is a
filled rectangle owned by a `Decoration` layout artifact, like the header
rule, and the cell keeps its `TH`/`TD` semantics. `KernelFacadePages.Rule`
gains a `layer`: fills are `Behind`, rules and link underlines `Front`.
Pagination emits every page's fills before its rules (`behind_first`, a
linear page-ordered merge that returns the rule list untouched when a
document has no fills), and the scene loop paints a page's `Behind`
rectangles before its first text placement. A row fill covers the row box
across the table and half the row gap above and below, so filled neighbours
meet; a cell fill covers the cell's spanned columns including padding.
Repeated headers repaint their fills with their text. Fills never move
layout.

The body rule is drawn centered in the gap above each body row that is not
the first body row and not the first unit on its page, so it never
duplicates the header rule on a continuation page. Like the header rule it
must fit the row gap: a wider one is `layout.table_rule`, whose message now
names the body rule.

Normalized storage. The cell's fill is one packed `U64` in the cell arena
(`Document.pack_color`: exact 16-bit sRGB or gray channels). A first
attempt stored `Color.SourceValue` in `NormalizedCell`, which grew the
record from 32 to 40 bytes; under the pinned compiler that alone added one
to four allocations to documents with and without tables (the reference
letter +1, the scaled-code rich-inline case +4). A `U32` field that fit the
record's padding did not, and neither did a document- or table-level fill
list help (a list on `SimpleState` added 60 to 100 allocations). The spans
now keep their authored `U16` width, which keeps the record at 24 bytes
with the packed fill. The smaller cell arena removes one to three
allocations from table-bearing documents: `tables invoice x500` −2, the
reference report family −1, `custom block report` −3, the page-sizes case
−3, `reference variant rejections` −14, and `rich inline shared source
faces x50` −2, all with allocated bytes within 0.2% (these cases are
rebaselined). Every other case keeps its allocation count; the
`KernelFacadePages.Rule` record's new field moves allocated bytes of
link-underline cases by under 0.05%.

Evidence: `tables styled x40` and `x400` (navy header with white column
header text, slate row headers, zebra body, 0.25 pt body rules, a pale
footer, and an amber total cell; continued with the header and its fill
repainted) count fills and rules. x40: 36,247 allocations, 24 fills, 38
rules, 2 pages. x400: 286,176 allocations (7.9×), 214 fills, 388 rules,
12 pages: linear. Each also rejects a 5 pt body rule in a 4 pt gap.

### Whole-table keeps

A table inside `Pdf.keep_together` already moved whole: `unit_groups` maps
an authored keep over leaf ranges onto the table's page-layout units
(caption, header rows, every body row, footer rows), and page layout
places a required group on one page or rejects it as
`layout.keep_conflict`. The gallery split tables only because the facade
never said so. The facade and authoring guide now document the idiom. The
existing evidence covers it: the reference invoice's `KeepItemsWithPayment`
variant keeps its items table with the payment section, and the tables
negatives reject a kept 60-row table as `layout.keep_conflict` at the
group and both its members. A new positive case, `tables whole-table keep`,
places 26 paragraphs and then a kept 12-row captioned table that would
otherwise start near the foot of page 1: the preparation report puts all 27
of its leaves on page 2 (45,294 allocations, 53 lines, 2 pages). Keeps do
not scale with table size beyond the existing unit mapping, so the case has
no scale pair. No package code or existing baseline changes.

### Empty cells

An empty `TD` or `TH` is legal PDF: a data cell with no value, or the blank
corner above a column of row headers. `Pdf.cell([])` and
`Pdf.header_cell(scope, [])` now author one. Every stage after semantics
assumed a cell leaf had text, so the cell is not faked with invisible
content; an explicit contentless-cell fact is created once and every later
stage handles it by name:

- **Normalization** gives a cell with no inlines the leaf kind
  `NormalizedBlockKind.EmptyCell` (text `""`, no rich-paragraph record).
  The cell arena keeps its record, so the cell keeps its grid position,
  spans, fill, kind, and ordinal; row leaf ranges stay one leaf per cell.
- **Semantics** (`plan_table`, `place_table`) counts it as one node and one
  row child and nothing else: no source, no occurrence, no content-spine
  slot of its own. Its `TD`/`TH` node has an empty content range and keeps
  its attributes (`Scope`, `ColSpan`, `Headers`) and generated identifier;
  a data cell below an empty `Column` header still names it in `Headers`.
  Block ownership is `ContentlessCell`. `table.cell_empty` now means
  authored inline content that holds no text (`[Pdf.strong([])]`); a table
  whose every cell is empty is `table.empty`, since it carries nothing
  and would reach shaping with no run.
- **Shaping** writes `BlockRuns.ContentlessCell`: no request, no run.
- **Table geometry** measures it as zero width, so it never widens a
  column, and skips the text-box width check (it has no text box to fit).
- **Line layout** writes `BlockLines.ContentlessCell`: no line request.
- **Pagination** gives it an empty line range in the row (its
  `cell_starts` entry equals the next cell's), so it adds no placements
  and the row's grid is its tallest other cell. The row's leading, line
  size, and unit occurrence come from its first cell with content. A row
  of only empty cells is one line of the body style tall; its unit
  occurrence is never read, because a table row's placements are rebuilt
  from its cells' lines and it has none. Row and cell fills and rules
  paint as for any row.
- **Text, fragments, scenes, and lowering** never see it: they are driven
  by runs and placements. Structure lowering writes a `TD`/`TH` element
  with no `/K` and no `/Pg`.

Complexity is unchanged: each stage does O(1) work per empty cell, and
documents without empty cells take exactly the previous paths (no existing
allocation count changes; allocated bytes of existing cases move by at
most 0.34% through code layout).

Evidence: `tables empty cells x40` and `x400`, a survey tally under the
styled theme with an empty corner `TH`, empty counts and notes, a shaded
empty cell, every fifth row entirely empty, and a footer with two empty
cells, continued with the header (and its empty corner) repainted. The
structure checker counts elements with no kids and requires each to carry
no `/K` and no `/Pg`; its self-test rejects the spans snapshot declared
with one empty cell and the tally declared with one too few.

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| empty cells x40 | 2 | 23,274 | 218 nodes, 168 cells, 75 empty, 246 associations, 95 lines, 1 repeated header, 95 fragments, 31 fills, 38 rules |
| empty cells x400 | 11 | 172,502 | 2,018 nodes, 1,608 cells, 723 empty, 2,406 associations, 887 lines, 10 repeated headers, 887 fragments, 292 fills, 389 rules |

The pair is linear: 10× the rows give 9.6× the empty cells, 9.3× the
nodes and lines, and 7.4× the allocations; cell measurements stay 14
(repeated texts hit the per-source cache). `tables atomic negatives` adds
the all-empty table (`table.empty`) and moves `table.cell_empty` to
`[Pdf.strong([])]`: 15 rejections, +1,045 allocations for the one added
document, allocated bytes +0.18%. veraPDF PDF/A-4 passes both snapshots.

### Column rules, frames, and the column-gap contract

Rules were horizontal only. Vertical rules and an outer frame needed a
decision about the space between columns, which the width algorithm never
reserved: cells abut, and each cell's text box is its columns less the
cell padding on both sides.

**The contract: no separate column gap.** The space between two columns'
text is the two cells' padding (2 × `cell_padding`), the horizontal
counterpart of the row gap between two rows' lines. Widths resolve
exactly as before, so no existing table moves. Rules live in that space:

- `Theme.with_table_column_rule` draws a rule centered on every boundary
  between adjacent cells of a row, from half the row gap below the row to
  half the row gap above it, so the rules of consecutive rows meet. A
  spanning cell has no interior boundary, so no rule crosses it. It must
  be at most 2 × `cell_padding` wide (`layout.table_rule`, "table column
  rule"), so it never reaches a text box.
- `Theme.with_table_frame` outlines each page's contiguous run of a
  table's rows, repeated header rows included and the caption excluded,
  with four rectangles inside the rows' outer boxes (the fill boxes). It
  must fit the cell padding and half the row gap (`layout.table_rule`,
  "table frame").

Both are `Front` layout decoration rectangles like the header and body
rules: painted after the page's text as `Decoration` artifacts, never
changing layout or structure. Header rows repainted on a continuation page
get their column rules and open that page's frame. Pagination tracks the
open frame segment in a tag (`Segment`) across the page's fragments and
closes it when the page ends or a leaf or another table's row follows, so
the frame costs O(1) per row and four rectangles per page segment, and the
rules list stays in page order for `behind_first`.

Evidence: `tables ruled grid x40` and `x400`, the styled register with a
0.5 pt column rule and a 1 pt frame; each also rejects a 9 pt column rule
(padding 4 pt) and a 3 pt frame (half the 4 pt row gap).

| Case | Pages | Allocations | Rules |
| --- | ---: | ---: | ---: |
| ruled grid x40 | 2 | 34,114 | 131 (38 body and header, 85 column, 8 frame) |
| ruled grid x400 | 12 | 238,987 | 1,261 |

The pair is linear (9.6× the rules and 7.0× the allocations for 10× the
rows). Every existing case keeps its allocation count and snapshot; the
two new `TableStyle` fields move allocated bytes by at most 0.001%.
veraPDF PDF/A-4 passes both snapshots.

## Open issues

- ~~**Per-table copies in semantic placement.**~~ (reference-documents
  closure) `place_table` received the document's semantic accumulators
  inside a record parameter it only borrowed, so its first update of the
  node list and of the occurrence list copied each of them, once per table.
  One-table documents never showed it; the reference report-sections pair
  (four-row tables in every section) grew its allocated bytes 14.2× for 10×
  the sections while its allocation counts stayed linear. An
  allocation-size trace found one 800 KB node-list copy per table at 200
  tables. `place_table` now takes each accumulator as its own parameter,
  and `plan_table` builds table-sized buffers that the caller appends
  rather than threading the document's buffers through its `Try`. At 200
  tables the semantic stage allocates 21.5 MB instead of 331 MB; the pair
  now grows 9.3×.

- ~~**Object-store copying**~~: resolved by S6b
  ([lowering-uniqueness.md](lowering-uniqueness.md)), with every case
  rebaselined in one reviewed change.
- **Reference documents.** The invoice and report tables are exercised in
  this family, but the complete reference documents (templates, furniture,
  figures) belong to later slices; `examples/tax-invoice/main.roc` still
  lists its services as bullets.
- **Relaxations and repeated headers are not yet public**; the preparation
  report must map page-layout units to authored paths, as the facade's
  diagnostics already do.
- ~~**Spanning cells**~~ align in their first column's alignment unless
  `Pdf.aligned` gives the cell its own (open-issues slice): the invoice
  totals labels are end-aligned and the spans case centers its spanning
  data cell.
- **SplitRows minimums** apply to the row's grid (its tallest cell), not to
  each cell; paint order of a split row interleaves its cells across pages.
- **Rules** cover the header and footer boundaries and, optionally, the
  gaps between body rows, the boundaries between cells, and a frame. A
  row's column rules follow that row's cells, so rows with different spans
  have different vertical rules; there is no per-column or per-cell rule
  selection.
- **Cell identifiers** are document-wide ordinals; authored identifiers for
  cross-document references are not offered.
- **Column minimums of spanning cells** are checked after resolution rather
  than widening the spanned columns, so a spanning cell whose widest word
  exceeds its span is rejected even when the table has room.
