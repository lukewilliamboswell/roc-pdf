# Gate 6 flow figures and decorations

This slice (S8) implements `reference-documents-v7`, which it introduces. It
makes `Pdf.figure` accept bounded vector, grouped, and multi-command
drawings, and makes `Pdf.figure_fit` (with `Pdf.FigureFit`), `Pdf.decoration`,
and `Scene.Drawing.group` executable. A caption becomes a visible `Caption`
related to its figure by `CaptionFor`. It closes the roadmap capability
"Bounded image/vector flow figures and captions through validated drawings"
except for its custom-block half (the separately authored chart or callout
belongs to the custom-block slice). It makes no PDF/UA-2 claim: `PdfUa2`
stays `defined_only`.

## Scope and non-goals

In scope:

- figure drawings of any number of images and solid paths, grouped by
  translated groups nested at most eight deep, validated at normalization
  and flattened, with an extent from the drawing's bottom-left origin;
- a figure as one unsplittable unit with its caption, placed start-aligned
  at its authored size, or scaled uniformly by an explicit
  `ScaleToFit({ minimum_percent })`;
- `document.figure_oversize` for a figure that does not fit (no hidden
  clipping, shrinking, or omission), and the floor diagnostic of
  `ScaleToFit`;
- captions as `Sect > (Figure, Caption > P)` with a `CaptionFor`
  relationship from the caption to the figure;
- in-flow decorations: `Decoration` page artifacts that occupy their
  drawing's height immediately above the next flow block;
- located diagnostics, an extended independent structure checker, a
  harness family, and a ledger row.

Not in scope: clip, opacity, soft-mask, and matrix groups (the reserved
`AuthorGroup` vocabulary still rejects); non-solid paint (shadings and
patterns) in flow drawings; centered or end-aligned figures; figures inside
list items or table cells; a theme caption style (captions use the body
style); decorations painted behind text (the custom-block slice's panel);
the preparation report, which will expose the applied scales; and the
reference report itself.

## Authoring and normalization

`Scene.AuthorCommand` gains `AuthorTranslate({ commands, offset })`, which
`Scene.Drawing.group(drawing, offset, child)` appends before the child's
commands: the next `commands` commands form one group translated by
`offset`. Nesting stays flat data. Furniture drawings still reject groups
(`layout.furniture_drawing`).

`Document.Block.Figure` gains a nominal `FigurePolicy` (`ExactFit` or
`ScaleFit(floor)`), converted from the structural `FigureFit` by
`Document.figure_fit`; `figure_fit` on any other block becomes an
`Unavailable` block that preparation rejects before normalization as
`document.figure_fit` (`InvalidRelationship`). `Document.Block` gains
`Decoration(Scene.Drawing)`.

Normalization validates every figure and decoration drawing once
(`validate_flow_drawing`) into a `ValidatedDrawing`:
`ValidDrawing(FlowDrawing)` holds flattened `FlowImage` and `FlowPath`
commands (each group's accumulated offset applied to every point and
placement), the drawing's image sources in command order, and its extent;
`InvalidDrawing(reason)` keeps the reason for a located rejection. A drawing
needs at least one painting command; images need a positive size and paths
a solid fill, a stroke of positive width, or both, beginning with a move or
a rectangle; every command lies at or beyond the origin (a stroke extending
its path by half its width); coordinates, sizes, and accumulated offsets
stay within 10^9 pt, so no later arithmetic can overflow.

- An uncaptioned figure is one `Figure(k)` leaf whose text is one space:
  the anchor line its drawing occupies.
- A captioned figure is a new `FigureGroup(k)` group holding the `Figure(k)`
  leaf and a `FigureCaption(k)` leaf with the caption text.
- `NormalizedFigure` is `{ alternative, captioned, drawing, fit }`; the
  single image and placement it held before are gone.
- A decoration is a `NormalizedDecoration` in the new
  `NormalizedAuthoring.decorations` arena, like a spacer: it names the next
  leaf (`block`) and keeps its authored `parent` and `position`.

Paths: a figure's leaves are named by the figure's own path
(`contents[3]`), its caption `contents[3].caption`, and a decoration by its
authored position, exactly as a spacer.

## Semantic planning

Validation, in document order: a figure has non-empty alternative text
(`document.figure_alternative_empty`), a valid drawing
(`document.figure_drawing`, with the reason), and a fit floor of at most
100 (`document.figure_fit`); a caption is non-empty
(`document.figure_caption_empty`). A decoration may not be in a list item
(`semantics.list_item_content`) or in the lead region, needs a following
flow block (`layout.decoration_position`), and needs a valid drawing
(`layout.decoration_drawing`).

Structure: a `FigureGroup` is a `Sect` holding the `Figure` (with `/Alt`,
owning the anchor occurrence) and `Caption > P` (owning the caption
occurrence). One `CaptionFor({ caption, target })` relationship per
captioned figure joins the store; the kernel's existing validation proves
the caption role, that a `Figure` may contain a `Caption`, and that the two
are siblings. `header_association_edges` still counts `HeaderFor` edges
only.

**Why a `Sect`.** `reference-documents-v6` left the caption's placement to
this slice: a child of the `Figure`, or a sibling in a grouping element.
PDF 2.0 `/Alt` replaces the element and its children for assistive
technology, so a caption inside the figure would be hidden behind the
alternative text; the caption is therefore a sibling. The first executable
form used a `Div`, and veraPDF 1.30.2's PDF/UA-2 profile then failed 8.2.5.27
("the Caption element shall be the first or the last child") on the
enclosing `Sect`: it treats `Div` and `Part` as transparent grouping
elements, so the caption counted as a middle child of the section around
the figure. Rewriting the same bytes with `Part` failed identically and with
`Sect` passed. A `Sect` is not transparent; with it every case passes
8.2.5.27, and the only remaining PDF/UA-2 failure is the absent PDF/UA
identification (clause 5), which is expected while no PDF/UA-2 claim exists.

## Layout

**Anchor line.** Shaping gives the figure's one-space leaf the body style;
pagination gives its page-layout block one line whose leading is the
figure's (scaled) drawing height and whose baseline offset equals it, so the
baseline is the drawing's bottom edge. The figure is unsplittable and,
when captioned, keeps with its caption with a `Required` keep; the caption
is unsplittable too, so figure and caption always move together (REP-A2).
The paragraph spacing separates them.

**Fit, before pagination** (`KernelFacadePages.plan_flow`). A figure's
unit is the decoration above it, its drawing, and (when captioned) the
paragraph spacing and its caption's lines at the body leading. The flow
width is the body frame's; the flow heights are the smallest and largest
page flow frames (equal without templates):

- `Exact`: the drawing must be no wider than the flow width and the unit no
  taller than the largest frame, else `document.figure_oversize` with the
  drawing size and the frame. The scale is 1000.
- `ScaleToFit({ minimum_percent })`: the scale `s` (thousandths) is the
  largest value at most 1000 with `w·s/1000` within the flow width and
  `⌈h·s/1000⌉` within the smallest frame less the rest of the unit, so the
  scaled unit fits a fresh page of either kind. No positive scale is
  `document.figure_oversize`; `s` below `10 × minimum_percent` is
  `document.figure_oversize` reporting the scale and the floor. The anchor
  line's height is `⌈h·s/1000⌉`, and the painted drawing (`h·s/1000`) lies
  inside it.

Only the drawing is scaled; its caption and every other block keep their
size.

**Decorations.** `KernelPageLayout.Block` gains `decoration`: the height of
the in-flow decorations above the block's first line. It is part of the
block's first placement unit and of every height that includes the block's
start (`heights[b]`, keep-together groups, required-keep chains, the first
unit of a split block, and the lead region), and the scan adds it before a
starting block's lines, so a decoration is never separated from, or
clipped away from, the line it precedes. Materialization records a
`Band { block, page, top }` for each block with a decoration. Pages attach
each leaf's decorations to its unit (a table's first unit for a decoration
before a table) and, after pagination, stack each band's decorations from
its top in authored order, giving each a page and a bottom-left origin
(`DecorationPaint`). A decoration wider than the flow region or taller than
the largest frame is `layout.oversize_block` at the decoration's path.

`KernelFacadePages.Plan.flow` carries `FlowPaints { decorations,
figure_scales }` to text materialization, which passes it through unchanged
(`KernelFacadeText.Plan.flow`), and on to scenes.

## Scenes and ownership

`KernelFacadeScenes.flow_facts` gathers each figure's and decoration's
flattened commands with the image identity of its first image, the images
in resource order (figures, then decorations, then furniture images), and
the commands, paths, segments, and colors they add. Every flow path's paint
is proven convertible before any scene accumulator grows, so painting never
exits on an error.

- A figure paints inside the group of its anchor line's run, owned by that
  run's fragment: the group has two roots, a transform `s 0 0 s x y` (the
  scale about the drawing's bottom-left corner on the baseline) around the
  drawing's images and paths, then the anchor text's transform. Its
  content is therefore the `Figure`'s one marked-content sequence.
- A decoration paints after the page's text and table rules as one
  `PageArtifact(Decoration)` group: a transform to its origin around its
  commands, lowered as `/Artifact <</Type /Layout>>` with no MCID.

## Ownership, copying, retention, and complexity

- **Validation** is O(commands + segments + group depth) per drawing, once,
  at normalization. Flattening copies each translated path once; an
  ungrouped path is shared, not copied.
- **Fit** is O(blocks + figures + decorations) and allocates only for
  documents with figures or decorations (a per-leaf decoration list only
  when decorations exist).
- **Pagination** adds a scalar per block and one band record per decorated
  block; decoration placement is one merge over bands and decorations.
- **Scenes** add one transform per figure and per decoration placement plus
  their commands, paths, and segments; the counts are exact and the scene
  lists are preallocated.
- **Retention.** Nothing new is retained past preparation: the validated
  drawings live in the normalized authoring, which is released after the
  scene stage, and image sources reach the resource store exactly as before.

## Evidence

**Package expects.** `Document` (flattened nested groups with accumulated
offsets and extent; depth nine, content left of the origin after
translation, and an empty drawing rejected), `KernelPageLayout` (a
decoration band above a block that moves with it to the next page), and
`KernelFacadePages` (`ScaleToFit` scale, floor, and `Exact` oversize).
`tests/contracts/pdf_facade.roc` now accepts a vector-only figure and
expects `document.figure_alternative_empty` at `contents[0]`.

**Harness family** `tests/flow_figures` (`flow-figures-v1`, pinned
`nightly-2026-09-30-df1f747`, cold cache, full harness order):

| Case | Pages | Allocations | Allocated bytes | Work |
| --- | ---: | ---: | ---: | --- |
| report | 4 | 24,523 | 9,248,588 | 39 lines, 39 fragments, 126 scene commands, 4 figures (3 captioned, 1 scaled), 2 decorations |
| sections x10 | 4 | 32,506 | 8,824,691 | 66 lines, 66 fragments, 262 scene commands, 10 figures, 10 decorations |
| sections x100 | 34 | 293,465 | 70,126,735 | 651 lines, 651 fragments, 2,602 scene commands, 100 figures, 100 decorations |
| atomic negatives | 1 | 15,701 | 4,660,705 | 14 rejections |

- **Report** is the reference report's figures under page templates (a
  first-page `Page N of M` footer and a continuation running title): a
  483 × 219.5 pt grouped vector bar chart (two axes and four translated
  groups of paired bars) with its caption, an uncaptioned 48 pt vector mark,
  a 320 × 160 pt raster photograph whose caption does not fit at the foot
  of page 1 so both move to page 2 (REP-A2), and a 600 × 900 pt site plan of
  twelve grouped cells scaled to fit at 743‰ (`ScaleToFit({
  minimum_percent: 50 })`, REP-A6b) on page 3; two decoration rules divide
  the sections.
- **Sections xN** repeats a decoration rule, a heading, a paragraph, and a
  captioned grouped bar chart N times.
- **Atomic negatives** each return their stable code and path and no bytes:
  `document.figure_oversize` for a 600 × 900 pt figure (REP-A6a), for the
  same with a 90% floor (REP-A6c), and for a 500 pt wide figure inside a
  section; `document.figure_alternative_empty` (REP-A9);
  `document.figure_drawing` for an empty drawing and for nine nested
  groups; `document.figure_caption_empty` at `.caption`;
  `document.figure_fit` for a 101% floor and for `figure_fit` on a
  paragraph; `layout.decoration_position` for a trailing decoration and one
  in a lead region; `layout.decoration_drawing`; `semantics.list_item_content`
  for a decoration in a list item; and `layout.oversize_block` for a
  900 pt decoration.

**Linear scale pair.** From sections x10 to x100 (10× the figures and
decorations), lines and fragments grow 9.9×, scene commands 9.9×, pages
8.5×, allocations 9.0×, and allocated bytes 7.9×.

**Independent checkers.** `scripts/check_structure_semantics.py` adds
`check_figures`, derived from the bytes: every `Figure` has a non-empty
`/Alt` and owns exactly one marked-content sequence, which begins with a
uniform scale of at most 1 (`s 0 0 s x y cm`); a `Caption` beside a
`Figure` is the last child of a `Sect` holding only the two, with one `P`;
and the counts of figures, captioned figures, scaled figures, and
`/Artifact <</Type /Layout>>` sequences equal the case dimensions. Its
self-test adds the report and sections snapshots and two twins (the
figure's `Sect` rewritten as a transparent `Part`, and a `Figure` without
`/Alt`). `scripts/check_rich_inline.py` passes unchanged: structure order
equals paint order on every page, with decorations outside the logical
text.

**External lanes.** veraPDF 1.30.2 PDF/A-4 `--cases` passes all 56 Archive
snapshots with zero failed checks, including the four flow-figures
snapshots. Arlington `--cases` passes all 202 case files and the gallery
(one recorded exception, unchanged). veraPDF's PDF/UA-2 profile, run
manually on every flow-figures snapshot, fails only clause 5 (no PDF/UA
identification, as no PDF/UA-2 claim exists); 8.2.5.27 and every Figure,
Alt, and containment rule pass.

**Rendering.** MuPDF 1.28.2 renders the report's chart with both axes and
four bar pairs, the photograph and its caption together at the top of page
2 with the continuation header above them, the site plan filling page 3 at
its reduced scale with its caption below, and each divider rule 6 pt above
its section heading; sections x10 shows a rule above every region heading,
including one at the top of a page. PDFium's adapter renders single-page
fixtures only, so the multi-page snapshots were not rendered with it.

## Reviewed rebaselines

Every delta comes from a cold-cache, full-order run.

- **Bytes.** Three snapshots change by design: `image_figure` (one captioned
  figure), `archive_figures`, and its Standard twin (four figures, three
  captioned). Captions now paint below their figures as separate `Caption >
  P` elements inside a `Sect`, instead of one text line above the image
  inside the `Figure`, where the caption was hidden behind `/Alt`. Rendering
  confirms the images and captions; veraPDF and Arlington pass. The gallery's
  `field-guide`, `product-brief`, and `quarterly-report` (the examples with
  figures) are regenerated with their previews for the same reason.
- **Allocations.** Four existing cases change. `image_figure` allocates 101
  more (2,744 → 2,845) and the two archive figure cases 239 more (3,047 →
  3,286; 3,045 → 3,284). An A/B build of the image figure authored as an
  uncaptioned figure followed by an ordinary paragraph with the caption text
  allocates 2,822: 78 of the 101 are the caption becoming its own shaped,
  laid-out, and tagged block, and the remaining 23 are the figure's `Sect`,
  the `Caption` element, and the `CaptionFor` relationship. `semantic
  foundation container atomic negatives` allocates 3 fewer (7,445 →
  7,442): its figure negative (an empty alternative, formerly an unlocated
  `document.figure`) is now `document.figure_fit` on a paragraph nested in a
  part, which still rejects before normalization.
- **Allocated bytes.** 75 further cases allocate more bytes with unchanged
  counts (total +0.08%; the largest, the tiny simple-list normalization
  cases of 84 and 93 allocations, +9.8% and +8.2%, inside the 10% guard):
  `NormalizedAuthoring` gains `decorations`, `KernelPageLayout.Block` gains
  `decoration` and its plan `bands`, and the pages and text plans carry
  `FlowPaints`.
- **Work counters.** Only the three figure cases' output bytes change.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: validated flow drawings with groups, figure fit and scale, decoration bands, figure and decoration painting, with allocation and work evidence |
| Facade | Executable for `Pdf.figure` (vector, raster, grouped, multi-command), `Pdf.figure_fit`, `Pdf.FigureFit`, `Pdf.decoration`, and `Scene.Drawing.group` with stable located diagnostics |
| Advanced integration | `Scene.Drawing.group` and `Document.FlowDrawing`; no separately authored consumer (the custom-block slice supplies one) |
| Conformance | `ROC-PDF-PDF20-FLOW-FIGURES` is `implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Open issues

- **Applied scales.** The scale a `ScaleToFit` figure receives is a layout
  fact (`KernelFacadePages.FlowPaints.figure_scales`) but is not yet
  reported to the author; the preparation report (next slice) exposes it.
- **Alignment and caption style.** Figures are start-aligned and captions
  use the body style with paragraph spacing; centered figures and a theme
  caption style are not offered.
- **Group vocabulary.** Only translated groups exist; clip, opacity, soft
  mask, and matrix groups (`AuthorGroup`) still reject, and flow paths are
  solid-paint only.
- **Decoration placement.** A decoration always binds to the next flow
  block, so one authored before a page break lands on the next page above
  that block, and a document cannot end with a decoration. Decorations do
  not paint behind text (the custom-block slice's panel needs that).
- **Smallest frame.** Under templates whose first and continuation frames
  differ, `ScaleToFit` fits the smaller frame, which can scale a figure
  more than the page it lands on requires.
- **Furniture drawings** keep their own validator and command type; they
  could share `validate_flow_drawing` (rejecting groups) in a cleanup.
- **Anchor text.** A figure's anchor line paints one space glyph inside the
  `Figure`; it is invisible, and its text is replaced by `/Alt` for
  assistive technology.

## Decoration spacing and paint layer (examples showcase)

A decoration occupied exactly its drawing's height above the next block
and painted after the page's text, so the gallery padded dividers with an
empty drawing area and could not put a band behind a heading.
`Pdf.spaced_decoration(drawing, { above, below, behind })` records the
spacing and layer on the block. Normalization applies the spacing to the
validated drawing (`Document.space_decoration`): the height grows by
`above + below` and every command is lifted by `below`, so pagination,
decoration stacking, and `DecorationOversize` see one ordinary drawing
height and no later stage changes. A negative `below` lowers the commands
into the next block; an overlap deeper than the drawing, or negative space
above, is `layout.decoration_drawing` at the block's path. `behind` is
carried on the normalized decoration and its paint; each page's behind
decorations are ordered first (`behind_decorations_first`, linear, and a
no-op without them), and the scene loop paints them before panels, fills,
and text, after region backdrops. Decorations still take no text labels,
so no label ordering depends on the paint order.

The decoration block's payload became a record of the drawing, spacing,
and layer, unboxed: a boxed payload cost one allocation per decoration
(+2 on `flow figures report`), while the record still fits inside the
block union's largest alternative. `NormalizedDecoration` gains `behind`.
No existing allocation count changes.

Evidence: `flow figures spaced decorations x10` and `x100`: each section
has a divider with 12 pt above and 6 pt below it and a heading over a
22 pt band that overlaps it fully and paints behind its text. Each also
rejects negative space above and an overlap deeper than the drawing.
x10: 28,308 allocations, 2 pages; x100: 232,986 (8.2×), 15 pages: linear.
