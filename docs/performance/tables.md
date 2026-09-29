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

## Open issues

- ~~**Object-store copying**~~: resolved by S6b
  ([lowering-uniqueness.md](lowering-uniqueness.md)), with every case
  rebaselined in one reviewed change.
- **Reference documents.** The invoice and report tables are exercised in
  this family, but the complete reference documents (templates, furniture,
  figures) belong to later slices; `examples/prepared_invoice.roc` still
  lists its services as bullets.
- **Relaxations and repeated headers are not yet public**; the preparation
  report must map page-layout units to authored paths, as the facade's
  diagnostics already do.
- **Spanning cells** align in their first column's alignment; a separate
  alignment per cell is not offered.
- **SplitRows minimums** apply to the row's grid (its tallest cell), not to
  each cell; paint order of a split row interleaves its cells across pages.
- **Rules** are fixed to the header and footer boundaries; header-row
  shading and body rules are not offered.
- **Cell identifiers** are document-wide ordinals; authored identifiers for
  cross-document references are not offered.
- **Column minimums of spanning cells** are checked after resolution rather
  than widening the spanned columns, so a spanning cell whose widest word
  exceeds its span is rejected even when the table has room.
