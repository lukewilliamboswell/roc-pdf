# Gate 6 custom-block seam and preparation report

This slice (S9) implements `reference-documents-v9`, which it introduces. It
makes `Pdf.custom_block` (with `Pdf.CustomBlock`), `Pdf.prepare_with_report`,
`Pdf.prepare_with_report_budget`, `Pdf.Report`, and `Pdf.ReportBudget`
executable, and exercises the seam with a separately authored extension,
the "Key figures" callout (`tests/custom_block/Callout.roc`). It closes the
custom-block half of the roadmap capability "Bounded image/vector flow
figures and captions … plus one separately authored chart or callout" and
the capability "A bounded read-only preparation report". It makes no
PDF/UA-2 claim: `PdfUa2` stays `defined_only`.

## Scope and non-goals

In scope: a data-only custom block of paragraphs and rich paragraphs with an
extension-measured box, content inset, and a solid-path panel painted behind
the content; `Unsplittable` fragmentation; located diagnostics; the report
with separate mechanical facts and human obligations, an explicit budget, and
byte-identical preparation; an extended structure checker; a harness family;
a ledger row.

Not in scope: continuation of a custom block across pages, nested groups,
lists, figures, or tables inside a custom block, images in the panel, a
public text-measurement API for extensions, and the reference documents
themselves (the final slice).

## Custom block

**Authoring and normalization.** `Document.Block` gains
`Custom(Box(CustomSpec))`. Normalization opens a new group kind
`Custom(k)` at container depth + 1 and records `NormalizedCustom { group,
width, height, inset, name, panel }` in the new `NormalizedAuthoring.customs`
arena; the panel is validated once by `validate_flow_drawing`. Paths are the
container paths (`contents[2].contents[3].contents[0]`).

**Semantics.** A `Custom` group is a `Div` (list-item containment and depth
checks as for containers). `check_customs` rejects, in order: a block in the
lead region or with any non-paragraph child, nested group, decoration,
spacer, or page break (`semantics.custom_block_content`, naming the block and
the child); an empty name (`semantics.custom_block_name`); a non-positive box
or an inset that is not positive and below half of each side
(`layout.custom_block_measure`); a panel that is invalid, holds an image, or
extends beyond the box (`layout.custom_block_drawing`).

**Lines.** `list_geometries` insets a custom group's content by `inset` on
the start side and tracks each group's end edge (only when customs exist) so
lines are requested at `width − 2·inset`; a box wider than its flow region is
`layout.oversize_block`.

**Pagination.** `KernelPageLayout.Block` gains `trailing`: height reserved
below the last line, allowed only on an unsplittable block and counted in
`heights[b]`, group heights, the lead total, and materialization.
`apply_customs` makes every custom leaf unsplittable (the group is a keep
group), adds the top inset to the first leaf's decoration band, proves the
content (lines plus inter-paragraph spacing) fits `height − 2·inset`
(`layout.custom_block_measure`, with both heights), and sets the last leaf's
trailing so the block occupies exactly `height`. `plan_flow` rejects a block
(with decorations above it) taller than the largest frame as
`layout.oversize_block` (REP-A10). `panel_paints` places each panel from its
first leaf's band.

**Scenes.** `FlowPaints.panels` paint first on their page, before any text,
each as one `PageArtifact(Decoration)` group (`/Artifact <</Type /Layout>>`,
no MCID); panel colors are proven convertible before any accumulator grows.

## Preparation report

`KernelFacadeReport` collects compact scalar facts only when a `*_reporting`
pipeline builder asks (`Request.Collect`); ordinary preparation passes
`NoCollect` and allocates nothing for them. Facts: relaxations mapped to
leaf or row units, figure scales, repeated-header pages and continued rows
(new `KernelFacadePages.Plan.repeats`/`splits`, recorded in the table
placement rebuild), panel pages, per-leaf page spans and fragment counts
(from block ownership and final fragments), per-page fragment counts, and
coverage (consecutive final runs merged by leaf, font instance, script).
None holds a plan, scene, object identity, or payload.

`Pdf.build_reporting_plan` normalizes once, runs the reporting builder, and
validates exactly as `build_plan`; `build_report` counts entries from the
scalar facts, rejects above `max_entries` before materializing any string,
materializes paths with the linear `leaf_paths` (proved equal to
`leaf_path` by a package expect), and rejects above `max_text_bytes`. Either
is `report.budget_exceeded` with no report and no prepared document.

## Ownership, copying, retention, and complexity

- Custom blocks add O(customs + custom leaves) validation, geometry, and
  fitting; one band and one panel group per block; no per-document list
  unless customs exist.
- Collection is O(blocks + occurrences + fragments + runs); materialization
  is O(entries × path depth), plus O(line breaks) per inline path segment
  (see open issues).
- Retention: the report holds only strings and scalars; the prepared plan is
  the one `prepare` builds.

## Evidence

**Package expects.** `KernelPageLayout` (trailing moves an unsplittable
block and offsets the next; trailing on a splittable block is rejected) and
`Pdf` (linear `leaf_paths` equals `leaf_path` across lists, legacy bullets,
tables, captioned figures, flow items, and a custom block).

**Harness family** `tests/custom_block` (`custom-block-v1`, pinned
`nightly-2026-09-30-df1f747`, cold cache):

| Case | Pages | Allocations | Allocated bytes | Work |
| --- | ---: | ---: | ---: | --- |
| report | 4 | 98,224 | 32,802,057 | 232 lines, 244 fragments, 224 report blocks, 5 alternatives, 3 outcomes, 229 coverage, 10 obligations, 22 observations |
| callouts x10 | 2 | 35,442 | 9,118,004 | 51 lines, 51 fragments, 10 custom blocks, 41 blocks, 10 outcomes, 12 obligations |
| callouts x100 | 19 | 292,826 | 75,470,482 | 501 lines, 501 fragments, 100 custom blocks, 401 blocks, 100 outcomes, 102 obligations |
| atomic negatives | 1 | 64,089 | 11,785,529 | 17 rejections |

- **Report** prepares the reference report's summary (with the callout),
  a French quotation, a 600 × 900 pt plan scaled to fit (REP-A6b, reported
  as `FigureScale`), and Table 2 of 40 rows that continues with a repeated
  header row. The fixture proves `to_bytes_prepared(prepare_with_report(..))`
  equals `to_bytes_with(..)` and checks 22 named observations, each by its
  authored path (callout paragraphs, figure alternative and scale, the
  expansion and nested languages, the repeated header, the callout
  placement, every obligation kind, coverage).
- **Callouts xN**: N sections of a heading, a paragraph, and a callout.
- **Atomic negatives**: REP-A10 height and an over-wide box
  (`layout.oversize_block`); an under-measured box, a wrapping line, a zero
  inset, and an inset too large (`layout.custom_block_measure`); a heading, a
  nested division, and a spacer inside (`semantics.custom_block_content`);
  an empty name; a panel with an image and one beyond the box
  (`layout.custom_block_drawing`); an empty block
  (`semantics.empty_container`); a callout in the lead region and one in a
  list item; and report budgets exhausted by entries and by text bytes.

**Linear scale pair.** x10 → x100: lines and fragments 9.8×, report entries
~9.8×, pages 9.5×, allocations 8.3×, allocated bytes 8.3×.

**Independent checkers.** `check_structure_semantics.py` adds
`check_custom_blocks` (Divs of only `P` children and Layout artifacts painted
before a page's first marked content, against `paragraph_divs` and
`underlays`), with two twins (a callout Div rewritten as `Art`; decorations
painted after text claimed as underlays). `check_rich_inline.py` passes.

**External lanes.** veraPDF 1.30.2 PDF/A-4 `--cases`: all 62 Archive
snapshots with zero failed checks. veraPDF PDF/UA-2, run manually, fails
only clause 5 (no identification) on the callout snapshots; the report
snapshot also fails 8.2.4 for its `Quote` element, a pre-existing
rich-inline issue (see open issues). Arlington was not run locally (its
Docker service was unavailable); CI's lane covers it.

**Rendering.** MuPDF 1.28.2 renders the tinted rounded panels behind their
lines with a 10 pt inset, whole on one page, and callouts moving whole to
the next page.

## Reviewed rebaselines

No existing snapshot changes. Four table cases allocate slightly more
(`footer carry` +2, `invoice x50` +4, `split rows` +10, `invoice x500` +10):
the table placement rebuild now appends each repeated-header page and each
continued row to the `repeats` and `splits` lists the report reads. 73 cases
change allocated bytes only (total +0.018%, largest +0.5%): the new
`customs` authoring field, the `trailing` block field, `FlowPaints.panels`,
the pages plan's two lists, and the pipeline plan's `facts` field.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: custom groups, trailing reservation, panel underlays, report fact collection |
| Facade | Executable: `Pdf.custom_block`, `Pdf.prepare_with_report(_budget)` with located diagnostics |
| Advanced integration | Exercised by the separately authored `Callout` extension through public modules only |
| Conformance | `ROC-PDF-PDF20-CUSTOM-BLOCK` is `implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Open issues

- **Measurement.** Extensions measure from public theme metrics only; there
  is no public text-measurement API, so content that wraps is rejected as
  under-measured rather than measured.
- **Fragmentation.** Only `Unsplittable`; no continuation, nested groups,
  lists, figures, or images in a panel.
- **Probe coverage.** `KernelFacadePipeline.probe` has no document facts or
  navigation, so the family's work numbers stop at text materialization.
- **Inline paths.** Each inline path segment scans the document's line
  breaks; bounded by the budget but not linear in documents with many line
  breaks and inline links.
- ~~**`Quote`/`Code` roles.**~~ veraPDF PDF/UA-2 8.2.4 reported `Quote` (and
  in `code_face`, `Code`) as outside the PDF 2.0 namespace without a role
  map. Resolved in the reference-documents closure: both roles are now in
  the PDF 1.7 standard namespace (see rich-inline.md, Namespaces).
- **Report scope.** Coverage is by output font instance and script, not by
  caller face name; obligations are a fixed vocabulary.
