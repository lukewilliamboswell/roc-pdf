# Gate 6 page templates, furniture, and page fields

This slice (S7) implements `reference-documents-v6`, which it introduces. It
makes `Pdf.with_page_templates`, `Pdf.first_page_template`,
`Pdf.page_template`, `Pdf.region`, `Pdf.no_region`, `Pdf.lead_region`,
`Pdf.no_lead`, `Pdf.furniture_text`, `Pdf.furniture_image`,
`Pdf.page_number`, `Pdf.total_pages`, and `Pdf.reserved_width` executable,
retires the `Pdf.page_header` and `Pdf.page_footer` placeholders, and
resolves page fields through explicit reference stabilization. It closes no
Gate 6 capability as a whole and makes no PDF/UA-2 claim: `PdfUa2` stays
`defined_only`.

## Scope and non-goals

In scope:

- a first-page template (header, lead, and footer regions) and a
  continuation template (header and footer regions), each region of fixed
  height reserved inside the theme's body frame, with a template gap;
- per-page flow frames in page layout, and the first page's lead region of
  semantic blocks laid out once as one unit;
- furniture text (one body-style line of text, page fields, and reserved
  widths) and furniture drawings (images and solid paths) in `start`,
  `center`, and `end` slot stacks, painted as page artifacts;
- page and total-page fields in every `NumberStyle`, resolved by an explicit
  two-pass stabilization with a four-pass budget and cycle detection;
- fit proofs for reserved widths, item widths, and slot overlap on every
  painted page;
- artifact text runs (`Text.RunUnicode`), artifact text sources, and their
  ownership and `ToUnicode` lowering;
- stable located diagnostics, an extended independent structure checker, a
  harness family, and a ledger row.

Not in scope: furniture text under an ordered font policy (it reports
`text.furniture_policy`; furniture drawings work under any policy); a
distinct furniture text style; backgrounds, watermarks, and fixed pages;
grouped, clipped, or translucent furniture drawings; flow-affecting
generated references (Gate 8); the preparation report; and the reference
letter, invoice, and report documents themselves (later slices build them).

## Authoring and normalization

`Document` gains `templates`, and `Document.Inline` gains `PageNumber`,
`TotalPages`, and `ReservedWidth`. A furniture item is the nominal
`Document.Furniture`, a region `Document.Region`, a lead region
`Document.LeadRegion`, and the templates `Document.FirstPageTemplate` and
`Document.PageTemplate`. The field style and the reserved width's alignment
are held in the nominal `Document.PageFieldStyle` and
`Document.ReservedAlign`, converted from `NumberStyle` and `ColumnAlign` by
the constructors (see [Reviewed rebaselines](#reviewed-rebaselines)).

Normalization adds `NormalizedAuthoring.templates`. A lead region's blocks
normalize first, as group 0 of the new kind `LeadRegion` at container depth
one, exactly as a division's children do, so the lead precedes the body in
every arena and in reading order. Regions keep their heights and slots;
each furniture line is flattened (a reserved width becomes `BoxStart`, its
content, and `BoxEnd`) with the authored positions its diagnostics need,
one level deep, so authored nesting never becomes Roc call depth. A page
field or reserved width in body content normalizes to the payload-free
inline kind `FurnitureOnly`, which semantic planning rejects first, with
its inline path, as `document.generated_reference`.

Diagnostics name template paths: `templates.first`,
`templates.first.lead`, `templates.continuation.gap`,
`templates.first.header.start[0]`, or
`templates.continuation.header.end[0].inlines[0].inlines[1]`. Body paths are
unchanged: the lead region is not an authored sibling of the body blocks.

## Template geometry (before flow)

`KernelFacadeFurniture.Static.build` derives every flow frame from region
heights and gaps alone. On each kind of page the flow region starts below
the header region and its gap (and, on the first page, the lead region and
its gap) and ends above the footer region and its gap; `no_region`
reserves no gap. It rejects, in template order, a negative gap
(`layout.spacer_negative`), a region with no height or no furniture
(`layout.template_region_empty`), less than one body line of flow
(`layout.template_body_space`, with every region height and the remaining
height), a templated document without body blocks
(`layout.template_body_empty`), and then, per region and slot, furniture
lines (`layout.furniture_inline`, `semantics.inline_empty`), drawings
(`layout.furniture_drawing`), and slot stacks taller than their region
(`layout.template_region_overflow`). Each item's vertical position is fixed
here: a header stack sits on its region's bottom edge and a footer stack
hangs from its top edge.

Drawings are validated into images and solid paths with their extent from
the item's bottom-left origin; a stroke extends its path's bounds by half
its width on every side, so a stroked line starting at the origin reaches
left of it and is rejected.

## Pagination

`KernelPageLayout.Template` carries a `Frame` (`top` below the body frame
top, `height`) for the first page and for every later page, and optionally
the first page's lead frame with the number of blocks it receives. Page
layout places those blocks first, on page 0, stacked with their spacing,
and fails with `LeadOverflow` (`layout.template_region_overflow` at
`templates.first.lead`) when they exceed it; then the body flows with each
page's own frame height in every scan and fit check. A fresh-page check of
an unsplittable block, keep group, or chain uses the larger frame as its
static bound; the scan itself reports a unit that fits neither.

`KernelFacadePages.Plan.build_with_template` gives the lead's page blocks
neutral policies (no explicit break, no keep, whole-block minimums), drops
keep groups inside the lead, rejects a page break inside or directly after
the lead (`layout.page_break_position`), and repaints a continued table's
header rows at the continuation frame's top.

## Stabilization

`KernelStabilization.stabilize` runs passes from an explicit state
(`{ pages, values }`) with a pass budget, returning a
`Layout.Stabilization` outcome and the last candidate. Each pass consumes
the state and the previous candidate; identical consecutive states are
`Stable`, a repeated earlier state is `Cycle`, and exhausting the budget is
`BudgetExhausted` with the last attempted state. The history holds only
compact states (at most the budget) and never an earlier candidate.

The facade's two passes:

1. From the empty state, paginate the body with the static frames. The
   state becomes the page count.
2. Resolve every page field with that count, shape and prove all
   furniture, and recompute the state from the same pagination.

No pass can change a frame (they are fixed before flow from region heights),
so pass 2 repeats pass 1's state and the driver confirms it by exact
comparison: `Stable({ passes: 2 })`. The budget is four; a cycle or
exhaustion (`layout.reference_cycle`, `layout.budget_exhausted`) is
unreachable with furniture-only fields and is exercised by the driver's
synthetic expects.

## Furniture resolution

`KernelFacadeFurniture.Plan.resolve` walks pages in order and, for each
region of the page's template, each text item: it writes the line with
the page's field values (`KernelFacadeSemantics.number_text`, the list
label formatter without its full stop) and records its segments (the text
outside reserved widths and each reserved width's content, with the first
field in each). All lines intern through `KernelFacadeSources` (one source
per distinct line: a static line is one source for every page) and shape
once through `KernelShape.shape_simple_batch` with the body style. A
furniture run's Unicode is `ArtifactText(source_base + k)`.

The fit proof, per page and region, in this order: a reserved width whose
content is wider is `layout.field_overflow` naming the first field, the
page, the value, the width, and the reserved width (or
`layout.template_region_overflow` when it holds no field); an item wider
than the body frame is the same pair; overlapping slots are
`layout.field_overflow` when a slot holds a field outside a reserved width,
else `layout.template_region_overflow` naming the region and the slots.
Values are never approximated, abbreviated, or shrunk. A template that
paints on no page has only its static checks.

Placement: start items align to the frame's start edge, end items to its
end edge, center items are centered. A text item's pieces (one per
segment) advance from its left edge; a reserved width's content aligns
inside it. Each piece is an exact cluster range of its source's run.

## Text, fragments, scenes, and ownership

`Text.Run.occurrence` becomes `Text.Run.unicode : Text.RunUnicode`
(`OccurrenceText` or `ArtifactText`). This is the architecture's second
text source (`architecture.md`, "Text and font boundary"): an artifact run
names an artifact text source, belongs to no structure element, carries no
text property, and may be painted only by a page-artifact group.

- `KernelFacadeText.Plan.with_furniture` interleaves furniture runs page by
  page: header pieces before the page's body runs and footer pieces after
  them. Body runs keep their clusters and glyphs; furniture clusters and
  glyphs are appended. `artifact_runs` lists repeated-header and furniture
  runs together, with `artifact_kinds` giving each run's kind.
- `KernelFacadeFragments` gives artifact runs no fragment (as for repeated
  headers) and appends the furniture sources to the dense Unicode store
  (`KernelTextSemantics.Plan.attach_artifact_sources`) before the final
  store validates. No occurrence indexes them.
- `KernelFacadeScenes` owns each furniture run by
  `PageArtifact(Header | Footer | PageNumber)` (a line holding a page field
  is `PageNumber`) and paints each drawing, after the page's text and
  rules, as one page-artifact group: a transform to its corner around its
  images (figure images first, then furniture images) and paths.
- `KernelTextOwnership` rejects a fragment that paints artifact text
  (`ArtifactTextInFragment`); `KernelPdfText` maps an artifact run's glyphs
  to Unicode from its source exactly as an occurrence's.
- Content lowering already marked these groups
  `/Artifact <</Type /Pagination /Subtype /Header>>` (and `/Footer`,
  `/PageNum`); no MCID or structure element exists for them.

## Ownership, copying, retention, and complexity

- **Static geometry** is O(template items + furniture inlines + drawing
  commands).
- **Resolution** is O(pages × furniture items + furniture scalars): each
  distinct line is analyzed and shaped once; a static line interns to one
  source. Width and cluster lookups scan one run per segment.
- **Interleaving** copies each body run once and appends furniture glyphs
  and clusters; it runs only for templated documents.
- **Stabilization** retains at most four compact states and the current
  candidate.
- **Documents without templates** take the previous code paths: the new
  plan fields are empty tags, and page layout's frames are scalars.
- **Retention.** Nothing new is retained past preparation beyond the
  furniture sources in the text store.

## Evidence

**Package expects.** `KernelStabilization` (two-pass stability, a cycle,
budget exhaustion, and a failing pass on synthetic reference systems),
`KernelPageLayout` (a lead region, first and continuation frames, and lead
overflow), `KernelTextOwnership`/`KernelShape` (typed artifact rejections
through the existing suites), and `Pdf` (a templated document with a lead
region and page fields, `layout.template_body_space`, and
`document.generated_reference` in body text).

**Harness family** `tests/page_templates` (`page-templates-v1`, pinned
`nightly-2026-09-26-d6267b4`, cold cache, full harness order):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| letter x6 | 3 | 49,482 | 111 lines, 2 passes, 4 field resolutions, 5 furniture lines, 114 fragments, 5 artifact runs |
| letter x20 | 6 | 116,058 | 221 lines, 2 passes, 10 field resolutions, 11 furniture lines, 224 fragments |
| letter x200 | 36 | 967,767 | 1,638 lines, 2 passes, 70 field resolutions, 71 furniture lines, 1,641 fragments |
| report | 7 | 174,295 | 266 lines, 2 passes, 14 field resolutions, 13 furniture lines, 268 fragments |
| number styles | 5 | 9,825 | 5 lines, 2 passes, 50 field resolutions, 25 furniture lines |
| furniture drawings | 3 | 4,713 | 3 lines, 2 passes, 2 field resolutions, 3 furniture lines |
| atomic negatives | 1 | 15,938 | 13 rejections |

- **Letter xN** is the reference letter's templates: a 48 pt header with a
  raster logo in its end slot, a 60 pt lead region with the strong
  letterhead name and a two-line address, a centered 16 pt footer, and a
  continuation header with the recipient and date and `Page N of M` in a
  72 pt end-aligned reserved width (96 pt at 200 paragraphs). The body is
  the date, the recipient block, a spacer, the salutation, the subject, N
  paragraphs (one with a French span), a numbered list, closing
  paragraphs, a kept signature block, the enclosure line, a page break,
  and the schedule table, whose header row repaints below the continuation
  header.
- **Report** has only a `Page N of M` footer on its first page; later pages
  add a running title and a full-width 0.5 pt vector rule on the header's
  bottom edge.
- **Number styles** stacks five `N of M` lines in every number style across
  the center and end slots of a 42 pt footer, on five pages.
- **Furniture drawings** paints a raster logo, a filled rectangle, a stroked
  line, and a gray image mark in both templates.
- **Atomic negatives** each return their stable code and template path and
  no bytes: `layout.template_body_space` (a 700 pt lead region),
  `layout.template_region_overflow` for twelve letterhead lines in a 60 pt
  lead, for overlapping continuation header slots, and for a text line in
  a 10 pt region; `layout.field_overflow` (an 8 pt reserved width that
  holds `9` but not `10`, first failing on page 10);
  `layout.template_region_empty`; `layout.furniture_drawing` (an empty
  drawing); `layout.furniture_inline` (emphasis in furniture);
  `semantics.inline_empty`; `layout.spacer_negative` (a negative gap);
  `layout.template_body_empty`; `layout.page_break_position` (a break in the
  lead); and `document.generated_reference` (a page field in a body
  paragraph).

**Linear scale pair.** From letter x20 to x200 (10× the body paragraphs),
lines grow 7.4×, pages 6.0×, fragments 7.3×, field resolutions 7.0×,
furniture lines 6.5×, allocations 8.3×, and allocated bytes 8.3×.
Stabilization passes stay 2.

**Independent checkers.**

- `scripts/check_structure_semantics.py` adds furniture checks derived from
  the bytes: every `/Artifact <</Type /Pagination /Subtype /Header|/Footer
  |/PageNum>>` sequence carries no MCID, every page-number artifact whose
  ToUnicode-decoded text reads `N of M` names its own page and the page
  count, and the per-subtype artifact counts equal the case dimensions
  (for example 36 header, 1 footer, and 35 page-number artifacts at
  letter x200). Its self-test adds the letter snapshot and four furniture
  twins (an MCID inside furniture, a wrong page number, a wrong total, and
  a missing page-number artifact).
- `scripts/check_rich_inline.py` decodes furniture text through its
  `ToUnicode` maps but keeps it out of the logical text, so structure order
  equals paint order on every page-templates case. Content-stream property
  lists are now parsed without the object serializer's key-order rule,
  since the package writes them as fixed literals
  (`<</Type /Pagination /Subtype /Header>>`).

**External lanes.** veraPDF PDF/A-4 `--cases` passes all 52 Archive
snapshots with zero failed checks, including the seven page-templates
snapshots, and `--standard-cases` fails only the deliberate omissions.
Arlington `--cases` passes all 198 case files and the gallery.

**Rendering.** PDFium (pages extracted with the vendored qpdf) paints
`Page 2 of 3` end-aligned in the continuation header of page 2 of the
letter, the logo and lead letterhead above the body on page 1 with the
centered footer, the schedule's repainted header row under the page 3
continuation header, the report's running title over its rule, and the
drawings' raster, filled, and stroked furniture on every page.

## Reviewed rebaselines

Every delta comes from a cold-cache, full-order run; causes were confirmed by
same-cache A/B builds.

- **Bytes.** No existing snapshot or gallery PDF changed.
- **Allocations.** One existing case changed: `text-layout chunked facade
  atomic negative` allocates 995 fewer (1,000 → 5): its unsupported block
  was `Pdf.page_footer`, which ran the pipeline until the artifact
  rejection, and is now `Pdf.footnote`, which rejects before normalization.
  An intermediate regression was found and removed: `PageNumber` and
  `TotalPages` first carried `NumberStyle` and `ReservedWidth` carried
  `ColumnAlign` directly, and `rich inline atomic negatives`, `rich inline
  ordered multi-face spans`, and `tables ordered numeric cells` allocated
  4, 2, and 1 more. An allocation trace (a test host recording every
  allocation's size) and same-cache A/B builds isolated it to the inline
  union holding a structural enumeration it shares with another authored
  type: adding `Probe(NumberStyle)` alone reproduced the extra 72-byte
  allocation, while a payload-free, `U64`, `Str`, or nominal-enumeration
  alternative did not. The nominal `PageFieldStyle` and `ReservedAlign`
  restore every count exactly.
- **Allocated bytes.** 112 existing cases allocate up to 2.19% more bytes
  (total +0.13%) with unchanged allocation counts: `Text.Run` gains 8 bytes (`unicode` is a tagged
  union where `occurrence` was an identifier), so every run store, run-sized
  map, and copied run grows; a Text.Run-only A/B build reproduces the
  deltas with identical allocation counts. `NormalizedAuthoring` and the
  text plan gain the templates and furniture fields.
- **Work counters.** No existing case changed.

**Transient failures.** `roc check tests/authoring/authoring.roc`
segfaulted in 8 of 14 harness launches during this slice (known, and
investigated separately); every rerun passed, and the final cold-cache
`--allocation-baselines` run passed all 264 cases without one.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: template frames, lead regions, stabilization, furniture shaping, fit proofs, artifact text runs and sources, and drawings, with allocation and work evidence |
| Facade | Executable for `Pdf.with_page_templates` and its constructors with stable located diagnostics; `Pdf.page_header` and `Pdf.page_footer` retired |
| Advanced integration | `Text.RunUnicode`, `KernelPageLayout.Template`, and `KernelStabilization`; no separately authored consumer |
| Conformance | `ROC-PDF-PDF20-PAGE-FURNITURE-ARTIFACTS` is `implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Open issues

- ~~**Ordered font policies.**~~ (open-issues slice) Under an ordered
  policy each distinct furniture line is selected by
  `KernelFacadeShape.select_source` exactly as body text is, becomes one run
  per face and script segment, and reuses the body's dense output faces; a
  face only furniture uses becomes an extra output font after the body's
  (`KernelFacadeFurniture.Plan.extra_fonts`). Widths sum across a line's
  runs and pieces split at run boundaries. Uncovered or undeclared-script
  lines are `text.coverage_missing` or `text.unsupported_script` at their
  item path; `text.furniture_policy` is retired. The `ordered policy` case
  paints `Office中` in the report's continuation header with the Han face
  used only by furniture (18 header artifacts: two text pieces and a rule
  per page), and the rich-inline checker pins one `中` per continuation page
  to that face and none in body text. The single-face path's allocations
  are unchanged.
- **Unused templates.** A continuation template of a one-page document has
  only its static checks; its widths are proven on no page.
- ~~**Unreachable artifact blocks.**~~ Removed by the open-issues slice:
  the normalized `PageArtifact` block kind, `ArtifactBlock` ownership in
  semantics, shaping, lines, pages, and tables, the `max_artifacts` limit,
  the `Artifacts` dimension, and `ArtifactTextPending` no longer exist.
  Allocation counts are unchanged; 79 cases allocate up to 0.4% fewer bytes
  (the smaller semantic plan and limits records).
- **Furniture style and vocabulary.** Furniture text uses the body style;
  a theme furniture style, backgrounds, watermarks, and grouped, clipped,
  or translucent furniture drawings are not offered.
- **Paths per paint.** Each painted furniture path is its own scene path,
  so a rule repeated on every page adds a path per page (linear).
- **Batch identity.** Furniture lines shape through the facade's shaping
  batch, whose requests name an occurrence ordinal; the furniture stage
  replaces it with the artifact source before any run leaves the stage.
- **Gallery.** `examples/warranty-letter/main.roc` does not use templates yet; the
  reference-letter slice will.

## Landscape and custom page sizes (examples showcase)

`Pdf.PageSize` was `[A4, Letter]`. It now adds `A4Landscape`,
`LetterLandscape`, and `Custom({ height, width })`. The facade already laid
out against a `Layout.Size` and wrote each page's boxes from it, so the
change is the size table in `Pdf.layout_page_size` plus two authoring
checks before any stage runs:

- `layout.page_size` (`options.page_size`): a custom side that is not a
  whole number of points from 3 to 14,400 pt (the PDF user-space page
  limits). Whole points keep the blank-document page box
  (`KernelStructure.PageSize.Points`) an integer and give the document
  identifier an exact width and height: a size other than A4 or Letter
  contributes geometry code 3 and both sides to the identifier facts, so
  two documents that differ only in page size never share an identifier.
  A4 and Letter keep codes 0 and 1, so no existing identifier changes.
- `layout.page_margin` (`theme.page_margin`, `options.page_size`): margins
  that leave no positive body frame. Before this change an oversized margin
  reached line layout as the internal `Lines.InvalidGeometry` defect; it is
  now an author-facing rejection. Margins are never reduced to fit.

Evidence (`page templates landscape and custom page sizes`): a landscape A4
report with a running header and `Page N of M`, and a 36-row, eight-column
ledger continuing onto a second page under its repeated header. The work
vector also records the byte lengths of the same document on landscape
Letter, a 432 × 648 pt custom document, and a blank custom document, and
five rejections: 2 pt, 14,401 pt, 432.5 pt, and −432 pt sides
(`layout.page_size`), and a 100 × 100 pt page under 56 pt margins
(`layout.page_margin`). 115,284 allocations; 299 lines, 2 pages. Page size
does not scale work, so the case has no scale pair. No existing baseline
changes.

Per-page sizes and orientations stay Gate 8 fixed-page composition: page
templates and pagination assume one body frame per template.

## Region backdrops (examples showcase)

A full-width rule in a header's start slot made any end-slot furniture a
`layout.template_region_overflow` (the slots overlap), so the brand brief
dropped its first-page header rule. `Pdf.with_backdrop(region, drawing)`
adds a layer separate from the slots. A backdrop is validated exactly like
a furniture drawing, placed as a `BackdropSlot` item on the region's
bottom edge (it may be as tall as the region, so a drawing positions its
marks anywhere inside it), and measured against the frame width, but it
contributes nothing to the slot extents that the overlap check compares.
It paints as a page artifact of the region's kind (`Header` or `Footer`)
before everything else on its page: `DrawingPaint` gains `behind`, the
resolved paints are reordered so each page's backdrops come first
(`backdrops_first`, one linear pass that returns the list untouched when
no region has a backdrop), and the scene loop routes a ready backdrop
through the furniture branch before any panel, fill, text, or rule. A
region may hold only a backdrop. `with_backdrop` on `no_region` produces a
zero-height region, which is `layout.template_region_empty`, never a silent
no-op.

Evidence: `page templates backdrops x3` and `x30`. The continuation
header has a 0.75 pt full-width rule backdrop under start-slot text and
end-slot `Page N of M`; the footer is a tinted 20 pt band behind centered
text; the first page's header is a backdrop only. Each rejects a backdrop
taller than its region and one wider than the frame
(`layout.template_region_overflow` at `templates.first.header.backdrop`),
and a backdrop on `no_region`. x3: 23,412 allocations; x30: 168,863 (7.2×
for 10× pages): linear. No existing baseline changes; the region record's
new field leaves every allocation count unchanged.
