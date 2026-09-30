# Gate 6 business-authoring closure

This record closes S10, "Reference documents and closure", the last item of
the Gate 6 remaining work. It implements `reference-documents-v10`, which it
introduces, and it reviews every Gate 6 gate-evidence bullet against the
evidence that now exists.

## Decision

Gate 6 is **closed**. Every non-optional gate-evidence bullet below is
satisfied by executable, machine-checked evidence under the pinned toolchain
recorded in `.roc-version` (`nightly-2026-09-30-df1f747`, a local ReleaseFast
build of Roc commit `df1f747ebb`). The optional human and assistive-technology
review was **not performed**; it is optional and never blocks closure.

The decision makes no PDF/UA-2 or combined-profile claim: `PdfUa2` stays
`defined_only`, `AccessibleArchive` still reports `profile.accessible_archive`
(LET-A4), and the combined product is Gate 7. Closing the gate also does not
make the branch mergeable: the pinned tag is not a published nightly, so CI
cannot provision it (see [Open issues](#open-issues)).

## What S10 adds

- **Reference programs.** The three references of
  [docs/reference-documents.md](../reference-documents.md) are gallery
  programs through the public API only: `examples/tax-invoice/main.roc`
  (the multi-page tax invoice, still prepared once and then emitted;
  `tax-invoice.pdf` replaces `invoice-1048.pdf`), `examples/warranty-letter/main.roc` (the
  business letter; `warranty-letter.pdf` replaces `project-letter.pdf`), and
  `examples/business-report/main.roc` (the business report, new;
  `business-report.pdf`). The report's "Key figures" callout is the custom
  block extension of `tests/custom_block/Callout.roc`, copied into the
  example; Figure 2 is a caller-supplied 128 × 69 baseline sRGB JPEG held in
  the program as hexadecimal text.
- **The `tests/reference_documents` family** (`reference-documents-v10`,
  21 cases). `Invoice.roc`, `Report.roc`, and `Letter.roc` author the same
  documents as the examples with the knobs the adverse variants change, and
  `Callout.roc` is the separately authored extension. Every accepted case is
  prepared with `Pdf.prepare_with_report` and checks named observations of
  the report's mechanical facts, each by authored path; placement variants
  also prepare a control that proves the triggering condition. The rejected
  variants run in one case that requires each stable code, `details` paths,
  and no prepared document. `scripts/check_reference_documents.py` proves the
  three ordinary snapshots are byte-identical to the gallery PDFs, and
  `scripts/check_gallery.py` that the programs regenerate them.
- **Two independent checkers**, both preflight checks with self-tests:
  `scripts/check_structure_extraction.py` compares the project's byte-level
  structure tree with a second extraction path through PDFBox 3.0.8's
  logical-structure API (`scripts/PdfBoxStructureExtract.java`);
  `scripts/check_reference_documents.py` checks XMP `dc:title`,
  `DisplayDocTitle`, `/MarkInfo`, and `/Tabs` on the references and resolves
  every `/SD` + `/D` pair to its authored heading's post-layout line.

### Adverse variants

| Variant | Case | Outcome |
| --- | --- | --- |
| INV-A1 | `invoice long text` | Accepted; the Bill-to paragraph and the 380-character description wrap, the grown row stays whole |
| INV-A2a | `invoice wide code` | Accepted; the `Content` column takes the code's max-content width (amended rule), four pages |
| INV-A2b | rejections | `layout.unbreakable_token` at the description cell |
| INV-A2c | rejections | `layout.table_width` at the items table |
| INV-A3 | `invoice rows x500` | Accepted with an 80 pt page field, 24 pages, 23 repeated headers; with the ordinary 64 pt field `layout.field_overflow` (rejections) |
| INV-A4a | rejections | `layout.oversize_row` at the 9,000-character row |
| INV-A4b | `invoice split row` | Accepted under `SplitRows`; the row fragments at line boundaries across the following pages (eight pages in all), each repainting the header row; one `TR`, the long `TD` owning several fragments |
| INV-A5 | `invoice totals carry` | Accepted; the last body row carries to the totals' page; the control without totals keeps it on its page; nothing relaxed |
| INV-A6a | rejections | `text.unsupported_script` at the Arabic text |
| INV-A6b | rejections | `text.coverage_missing` at the Han text |
| INV-A7a | rejections | `layout.keep_conflict` naming the keep and its first and last members |
| INV-A7b | rejections | `layout.keep_conflict` naming the break and the keep |
| INV-A8 | rejections | `table.grid_mismatch` at the row |
| INV-A9 | rejections | `table.row_span` at the cell |
| REP-A1 | `report heading keep` | Accepted; the heading moves with its paragraph; the control proves the heading alone fits; nothing relaxed |
| REP-A2 | `report figure and caption` | Accepted; figure and caption move together; the uncaptioned control fits |
| REP-A3 | `report table break` | Accepted; rows 1–2 on the table's first page, rows 3–4 and the total after a repeated header |
| REP-A4 | rejections | `layout.field_overflow` on page 100, value `100` |
| REP-A5 | `report ordered faces` | Accepted; `zh-Hans` `中` on the Han face, surrounding spaces as Common runs on the Latin face |
| REP-A6a | rejections | `document.figure_oversize` |
| REP-A6b | `report scaled figure` | Accepted; `FigureScale` 733 (thousandths) in the report |
| REP-A6c | rejections | `document.figure_oversize` below the 90% floor |
| REP-A7 | rejections | `semantics.heading_skip` naming both headings |
| REP-A8 | rejections | `InvalidNavigation(UnknownDestinationName)` |
| REP-A9 | rejections | `document.figure_alternative_empty` |
| REP-A10 | rejections | `layout.oversize_block` at the callout |
| LET-A1 | `letter long recipient` | Accepted; the recipient paragraph wraps |
| LET-A2 | `letter x60` | Accepted; exactly 11 pages with exact `Page N of 11` |
| LET-A3a | rejections | `layout.template_body_space` |
| LET-A3b | rejections | `layout.template_region_overflow` at the lead region |
| LET-A3c | rejections | `layout.template_region_overflow` at the continuation header |
| LET-A4 | `letter`; rejections | Accepted under `Archive` with `dc:title` and `DisplayDocTitle` checked; `profile.accessible_archive` under `AccessibleArchive` |
| LET-A5 | rejections | the typed metadata error |
| LET-A6 | rejections | `layout.keep_conflict` naming the signature keep |
| LET-A7 | rejections | `document.generated_reference` at the body field |

## Correctness defects found and fixed

The references exercised paths no earlier fixture had, and four real
defects surfaced. Each is fixed in its own commit.

1. **`Code` and `Quote` were claimed by the PDF 2.0 namespace.** ISO 32000-2
   14.8.6 defines them only in the PDF 1.7 standard structure namespace, and
   veraPDF PDF/UA-2 8.2.4 reported them as unmapped. They now belong to a
   declared PDF 1.7 namespace (`rich-inline.md`, Namespaces); the kernel
   admits that namespace only for those two roles and the structure checker
   checks every element's namespace against its role.
2. **Destination headings did not keep with their next block.** R1 and the
   unsplittable-heading rule matched only plain headings and titles, so the
   report's section headings (all destination headings) could end a page
   with no relaxation reported. Found by REP-A1 and by the Appendix A
   heading of REP-A6b (`layout-policies.md`).
3. **`semantics.heading_skip` was never returned.** The code was recorded
   but nothing checked heading progression; it is now a one-pass check
   before planning (`layout-policies.md`).
4. **Quadratic bytes in table semantics.** Placing each table copied the
   document's semantic node and occurrence lists once, because
   `place_table` received them inside a record parameter it only borrowed.
   The report sections pair showed allocated bytes growing 14.2× for 10×
   the sections (allocation counts stayed linear); a stage probe put the
   whole excess in semantic planning, and an allocation-size trace showed
   one 800 KB node-list copy per table at 200 tables. `place_table` now
   takes each accumulator as its own parameter, and `plan_table` builds
   table-sized buffers that the caller appends, so no document accumulator
   is threaded through its `Try`. At 200 tables the semantic stage now
   allocates 21.5 MB instead of 331 MB.

## Gate evidence review

| Gate 6 evidence bullet | Status | Evidence |
| --- | --- | --- |
| All three references and their content variants execute through the supported release API; composition, typography, wrapping, alignment, image placement, and navigation reviewed as complete documents and atomic fixtures; every variant an acceptable layout or a stable error with no bytes | Satisfied | The gallery programs and `tests/reference_documents` (21 cases, 24 rejections, table above). Every page of the ordinary documents and the accepted variants was rendered with MuPDF 1.28.2 and reviewed; the reviewed break positions are recorded in `reference-documents-v10`. Atomic fixtures remain in the slice families. The REP-A5 fixture registers the packaged face's bytes as its caller Latin face through the public `Font.Registry`; only the bytes come from a test-only module |
| Repeated table headers, row continuation, totals near breaks, oversized rows and figures, incompatible required keeps, permitted relaxation; ownership preserved; no hidden clipping, shrinking, omission, or weaker conformance | Satisfied | INV-A3, INV-A4a/b, INV-A5, REP-A3, REP-A6a/b/c, INV-A7a/b, LET-A6 here; `tests/tables` (split rows, footer carry) and `tests/layout_policies` (`reported relaxations`, relaxations mapped to paths in `custom-block-report.md`). Scaling happens only through an authored `ScaleToFit`, reported as `FigureScale` |
| Templates preserve body bounds and ownership; exact page fields; insufficient field widths, stabilization cycles, and work exhaustion reject deterministically | Satisfied | `page-templates.md` (furniture ownership checks, `layout.reference_cycle` and `layout.budget_exhausted` through `Layout.Stabilization`), REP-A4 and the INV-A3 64 pt negative here, LET-A2's exact `Page N of 11`; the structure checker verifies every `PageNum` artifact's `N of M` |
| A separately authored extension through the public contract; continuation or explicit unsplittable behavior, ownership, and bounded allocation/work exercised | Satisfied | `custom-block-report.md` (`tests/custom_block/Callout.roc`, callouts x10/x100); the same extension in the reference report |
| Preparation-report fixtures map observations to author input and separate facts from obligations; bounded, byte-neutral, no retained stages; budget failures explicit | Satisfied | `custom-block-report.md` (22 path-mapped observations, prepared bytes equal `to_bytes_with`, `report.budget_exceeded`); every reference case prepares through the report; the report type holds only strings and scalars |
| Text matrix evidence for every required row, distinct facade and advanced claims, atomic unsupported-case diagnostics, work bounds | Satisfied | The matrix of `reference-documents-v10` cites each row's record; REP-A5 closes the Common-run row in a complete document; INV-A6a/b are the located unsupported-script and coverage diagnostics |
| Readiness dimensions and exact allocation/work records with a small/large pair per scalable slice | Satisfied | Every slice record; here invoice rows 50/500, report sections 10/100, and letter paragraphs 20/200 (see [Scale pairs](#scale-pairs)) |
| A project-owned normalized structure representation compared independently of object numbers | Satisfied | `check_structure_semantics.py` (object-number-free trees, pinned for `nested.pdf` and `lowering.pdf`), on every tagged case including the 21 new ones |
| Every MCID and object reference reachable both ways through the ParentTree and graph exactly once | Satisfied | `check_structure_semantics.py` (ParentTree ↔ MCR and ↔ OBJR, exactly once, dense MCIDs) with its ParentTree and MCID twins |
| Fixtures separate paint and reading order, split nodes across pages, interleave content and children, reuse resources, repeat artifacts | Satisfied | Header furniture paints before body text and callout panels before their text (`page-templates.md`, `custom-block-report.md`); lead-region letterhead first in reading order; split `TD`s and multi-page paragraphs (INV-A4b, the letters); rich paragraphs interleave text and inline elements (`rich-inline.md`); fonts, ICC profile, and the logo are shared across pages; headers, footers, page fields, and repeated table headers repeat on every page |
| The legal and illegal namespace-containment matrix is tested | Satisfied | Kernel and checker Table 5 transcriptions agree with veraPDF's ISO 32005 profile on all 784 role pairs; containment twins; the new namespace twins (`Quote` in the PDF 2.0 namespace, `P` in the PDF 1.7 namespace) |
| Negative twins: duplicate/orphan MCIDs, missing ParentTree entries, unowned content, artifact-kind confusion, missing IDTree entries, role-map cycles, illegal namespace/containment/attributes, invalid language inheritance, broken table headers, untagged annotations | Satisfied | `negative.md` and `check_tagged_visual.py` (orphan MCID, ParentTree, unowned content, artifact confusion); `check_structure_semantics.py` twins (duplicate MCID, IDTree, namespace, containment, `/Scope`, `/Lang`, `/Headers`); role mappings, and so any role-map cycle, are rejected by the kernel (`UnsupportedStoreContent`, now with an explicit cycle expect) and by the checker (`/RoleMap` present); `check_navigation.py` (`/StructParent` drift, OBJR linkage) |
| Structure-tree extraction agrees across independent inspection paths | Satisfied | `check_structure_extraction.py`: the byte-level checker and PDFBox 3.0.8 derive identical trees on 11 snapshots (the three references, REP-A5, containers, lowering, table spans, flow figures, templates, custom block, rich inline) |
| Structural inspection verifies `dc:title`, `DisplayDocTitle`, `/MarkInfo`, and every page `/Tabs`; atomic twins omit or mismatch each | Satisfied | `check_reference_documents.py` (exact `dc:title` of each reference; twins: mismatched and omitted `dc:title`, `DisplayDocTitle` off, `/MarkInfo` off, a page `/Tabs /R`); `check_structure_semantics.py` twins (`DisplayDocTitle` removed, `/Marked` off, `/Tabs`) |
| For every internal link, `/SD` resolves to its semantic target, `/D` to the post-layout anchor geometry, both the same destination | Satisfied | `check_reference_documents.py`: 45 pairs (named destinations, the summary link, outline items) across the report and two variants, each `/SD` a heading with the destination's authored text, each `/D` on that heading's page at its first line; twins for a wrong page, a moved point, and an `/SD` naming a paragraph; `check_navigation.py` pairing twins |
| Optional human review of reading order, headings, lists, links, figures, tables, language, and artifacts | Not performed | Optional and non-blocking |
| Optional exploratory reader/AT work | Not performed | Optional and non-blocking |
| Human-review protocol pins versions and tasks where performed | Not applicable | No review was performed |
| Negative twins: missing or empty alternatives, misleading relationships, skipped ownership, missing Unicode, bad headings, inaccessible annotation structure, invalid namespace/attribute/language/relationship facts, missing or mismatched destination pairs; each a stable diagnostic with no bytes | Satisfied | REP-A9 and the checker's missing-`/Alt` twin; `/Headers` and `CaptionFor` twins; orphan-MCID and ParentTree twins; ToUnicode-decoding text checkers and located coverage diagnostics; REP-A7 `semantics.heading_skip` and the H7 rejection; navigation twins; the namespace, attribute, and language twins; REP-A8 and the destination twins. Facade negatives return one stable diagnostic and no bytes |

Unsupported semantic constructs stay rejected rather than flattened
(`table.row_span`, `document.generated_reference`, `profile.accessible_archive`,
and the other `FeatureUnavailable` codes).

## Closure sweep

Run on 2026-09-30 against the committed snapshots and gallery.

- **veraPDF 1.30.2 PDF/A-4** (`check_pdfa4.py --cases` and the examples):
  all 83 Archive snapshots and all 10 gallery PDFs compliant with zero failed
  checks.
- **veraPDF 1.30.2 PDF/UA-2** (manual, no claim): the 21 reference
  snapshots and 10 gallery PDFs fail only clause 5 (no PDF/UA
  identification, as expected without a claim). No 8.2.4 finding remains.
- **Arlington 1.30.2** (`check_arlington.py --cases` against the digest-pinned
  `verapdf/arlington` service in Docker, as CI runs it): 230 case files
  compliant with zero failed rules and checks; the one recorded exception
  failed exactly as recorded.
- **Independent structure checkers**: `check_structure_semantics.py`
  (13 snapshots, 21 mutation twins, 4 furniture twins, 2 custom-block
  twins, Table 5 agreement with veraPDF), `check_rich_inline.py`,
  `check_navigation.py`, `check_structure_extraction.py`, and
  `check_reference_documents.py` (8 twins) pass as preflight checks;
  `structure_semantics`, `rich_inline` (except the split-row case, whose
  continued cells paint in row order on each page by design), `navigation`,
  and `pdfa4` validate every reference case.
- **Renderers**: MuPDF 1.28.2 draws every page of the 21 reference snapshots
  and 10 gallery PDFs without a warning. The PDFium adapter renders single
  pages only, so the 11 pages of the three references were split with qpdf
  12.3.2 and rendered one by one; each agrees with MuPDF at 72 dpi to a mean
  absolute difference of at most 0.5/255 and ink counts within 0.5%.
- **Structure extraction agreement**: as above, 11 snapshots, 3,118 tree
  items.
- **`/SD` + `/D`**: as above, 45 destinations resolved to headings.

## Scale pairs

Each pair differs only in the scaled dimension; every counter and the
allocation counts stay within the linear bound (ratio 10).

| Workload | Pages | Fragments | Allocations | Allocated bytes |
| --- | --- | --- | --- | --- |
| Invoice rows 50 / 500 | 4 / 24 | 391 / 3,542 (9.06×) | 70,550 / 570,088 (8.08×) | 19.4 / 153.8 MB (7.93×) |
| Report sections 10 / 100 | 4 / 38 | 251 / 2,501 (9.96×) | 62,385 / 602,285 (9.65×) | 18.1 / 168.3 MB (9.30×) |
| Letter paragraphs 20 / 200 | 5 / 31 | 201 / 1,461 (7.27×) | 98,892 / 799,819 (8.09×) | 23.2 / 166.8 MB (7.19×) |

Before fix 4 the report-sections bytes grew 14.2× (270 MB at 100
sections) while their allocation counts were already linear: only the
allocated-bytes guard exposed the per-table copies.

## Reviewed rebaselines

Every delta comes from a cold-cache, full-order run and is explained in its
commit.

- **Fix 1** (`Code`/`Quote` namespace): the five snapshots holding either
  role gain one `Namespace` object (+157 to +164 bytes, +8 to +13
  allocations, work unchanged).
- **Fixes 2 and 3** change no byte: no committed snapshot placed a
  destination heading at a page end or skipped a heading level. 82 facade
  cases allocate 1 to 12 fewer events and 80 bytes fewer per semantic store,
  because the store's PDF 2.0 namespace list became a shared constant
  instead of a literal allocated per store (an A/B build of the caller-font
  facade case restores 1,001 allocations and 790,157 bytes with the literal).
- **Fix 4** changes no byte. Every case with a table allocates fewer bytes
  (0.05% to 2.9% on existing cases); allocation counts move by −20 to +20,
  the increases being `plan_table`'s fresh table-sized buffers.
- **Gallery.** `invoice-1048.pdf` and `project-letter.pdf` are replaced by
  `tax-invoice.pdf` and `warranty-letter.pdf`, and `business-report.pdf` is
  added, each with a Poppler 24.02.0 preview (`pdftoppm -r 96`, the recipe
  that reproduces the existing previews byte for byte) and provenance.

## Open issues

- **CI pin (merge blocker, not closure evidence).** `.roc-version` names
  `nightly-2026-09-30-df1f747`, a local build that is not a published
  nightly, so CI cannot provision it. The branch cannot merge until a
  published nightly contains Roc commit `df1f747ebb` and the pin moves to it
  with its own re-baseline.
- **Figures are start-aligned** with body-style captions
  (`reference-documents-v7`); centered figures are not offered. The reference
  figures span the full body width, so the policy is invisible there.
- **Han fixture coverage.** The test-only Han face covers only U+4E2D, so
  REP-A5 uses `中` instead of `上海`. The claim that spaces beside Han
  itemize as Han no longer holds: since the tables slice they are Common
  runs, and REP-A5's coverage facts show them on the Latin face.
- **Phoneme, phonetic-alphabet, and replacement text** are represented in
  the semantic model but not exposed through the facade; no reference needs
  them.
- The open issues of each slice record stay open (extension measurement
  without public text measurement, `Unsplittable` only, role faces under
  style faces only, inline report paths scanning line breaks).
