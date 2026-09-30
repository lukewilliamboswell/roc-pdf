# Gate 6 lists, explicit breaks, keeps, and ranked layout policies

This slice (S5) implements `reference-documents-v4`, which it introduces. It
makes `Pdf.bullet_list`, `Pdf.numbered_list`, `Pdf.list_item`,
`Pdf.page_break`, `Pdf.keep_together`, `Pdf.keep_with_next`, `Pdf.spacer`,
and the inline `Pdf.line_break` executable, gives `Pdf.bullets` its
`ListNumbering`, and replaces page layout's all-mandatory policy with typed
mandatory constraints and ranked preferences. It closes no Gate 6 capability
as a whole and makes no PDF/UA-2 claim: `PdfUa2` stays `defined_only`.

## Scope and non-goals

In scope:

- lists whose items hold paragraphs, rich paragraphs, and nested lists, with
  generated `Lbl` labels, `LBody` bodies, and `ListNumbering` on every `L`;
- explicit line breaks inside rich paragraphs, explicit page breaks, and
  spacers;
- required keep-together groups, required and preferred keep-with-next, and
  the ranked R1–R5 preference model with deterministic tie breaks, recorded
  relaxations, and structured conflict diagnostics;
- a new `Conformance.DiagnosticCode.LayoutConstraintViolated` family;
- an independent `ListNumbering` rule in the structure checker, a harness
  family, and ledger rows.

Not in scope: the preparation report that will expose the recorded
relaxations; tables (R3 is reserved); list items holding headings, figures,
containers, or keeps; right-aligned or content-sized label columns; page
templates and furniture.

## Authoring and normalization

`Document.Block` gains `ListBlock`, `KeepTogether`, `KeepWithNext`,
`PageBreak`, and `Spacer`, and `Document.Inline` gains `LineBreak`. A list
item is the nominal `Document.ListItem`.

Normalization generalizes the S3 container walk into one explicit frame
stack over every grouping block. The group arena's `kind` becomes
`NormalizedGroupKind`: `Container(ContainerKind)`, `ItemList(U32)` (an index
into the new `lists` arena of item counts and markers), `ListItem(U32)` (the
item ordinal), `KeepTogether`, and `KeepWithNext(Keep)`. The `U32` payloads
keep the group record at 56 bytes, so the arena's growth steps, and the
allocation counts of container documents, are unchanged. Page breaks and
spacers go to their own `page_breaks` and `spacers` arenas, keyed by the next
leaf and located by parent and position. Documents without these constructs
allocate none of the new arenas.

A rich paragraph with line breaks is split into **segments**. The block text
is the first segment and each `NormalizedLineBreak` record carries the
segment after it. A leaf's byte range is relative to its segment. A line
break has no inline record and no content-spine slot, so an inline's
`position` is its spine slot; diagnostics add back the authored positions of
sibling breaks.

## Semantic planning

`KernelFacadeSemantics` walks groups and leaves in one preorder loop:

- **Keeps** produce no node. Their children resolve to the nearest semantic
  ancestor through `semantic_code`, which walks only keep groups, so other
  documents pay one kind check per block.
- **`ItemList`** produces `L` with a List-owned `ListNumbering` attribute:
  `/Disc`, `/Decimal`, `/LowerAlpha`, `/UpperAlpha`, `/LowerRoman`, or
  `/UpperRoman`. Legacy `Pdf.bullets` lists gain `/Disc`.
- **`ListItem`** produces `LI`, `Lbl`, and `LBody`. `LI` owns
  `[Lbl, LBody]`; `Lbl` owns the generated label occurrence with its
  source-to-presentation property; and the item's children join the `LBody`
  span. The label becomes the `label` of the item's first paragraph, rich or
  plain.
- Labels are `•`, or the number in its style followed by `.`. Letters are
  bijective base 26 and Roman numerals subtractive.
- **Segments.** Each segment of a rich paragraph is its own source input, and
  each leaf occurrence names its segment's source.

Block ownership gains `level`, the list nesting level that decides
indentation. `RichTextBlock` also gains the generated `label`.

The rejections are:

| Code | Family | Cause |
| --- | --- | --- |
| `semantics.list_empty` | `InvalidRelationship` | A list has no items |
| `semantics.list_item_empty` | `InvalidRelationship` | An item has no blocks |
| `semantics.list_item_content` | `InvalidRelationship` | An item holds another block kind, a container, a keep, a page break, or a spacer, or does not begin with a paragraph |
| `semantics.list_depth` | `BudgetExceeded` | Lists nest more than 4 deep |
| `semantics.list_numbering` | `InvalidRelationship` | A number is not representable in its style |
| `semantics.line_break_position` | `InvalidRelationship` | A break begins or ends its paragraph, or follows another break |
| `layout.keep_empty` | `LayoutConstraintViolated` | A keep holds no leaf |
| `layout.spacer_negative` | `LayoutConstraintViolated` | A spacer is negative |

**Bounds.** Four list levels (`L > LI > LBody` each), 16 containers, the
paragraph, and 8 inline elements need a semantic depth of 38. The facade's
kernel bound rises from 32 to 48.

## Shaping, lines, and text

- **Labels.** Generated-label evidence was hard-coded to `•`. It now requires
  the property's presentation to equal the label occurrence's non-empty
  source text. A rich list-item paragraph prepares its label request before
  its leaves. The request helper runs only when a label exists; routing the
  three request buffers through it unconditionally cost six allocations per
  rich paragraph, which a same-cache A/B identified and removed.
- **Segments.** The ranged shaper restarts its cluster and script cursors
  when a leaf's source changes. The ordered expansion restarts its segment
  cursor the same way. The logical line batch receives one request per
  segment, each covering its whole segment source, so UAX #14 and the line
  cache never see a break position. The block's line range spans its
  segments' contiguous lines.
- **Geometry.** A block at level *L* has its body offset by *L* indents and
  its width reduced by the same amount. Its label paints at *L* − 1 indents
  (`Label.offset`). A label wider than the indent is
  `layout.list_label_width`: every label run's advance is summed before line
  layout. Legacy bullets are level 1 with a zero label offset, which is
  exactly their previous geometry.
- **Rows.** A row names its segment's logical run; the text materializer's
  per-run source bounds hold within one segment.

## Page layout

`KernelPageLayout.Policy.keep_with_next` becomes
`Keep : [NoKeep, Preferred(Rank), Required]`, with
`Rank : [HeadingKeep, AuthorKeep, FooterCarry, Orphan, Widow]` (R1–R5).
`Plan.build_with_groups` adds required keep-together groups, and
`Plan.relaxations` reports every relaxation as `{ rank, block, page }`.

**Static validation.** Before any page is scanned, validation checks:

- block shape;
- unsplittable blocks taller than a page (`Oversize`);
- group nesting (`InvalidGroup`);
- explicit breaks strictly inside a group (`BreakInsideGroup`);
- groups taller than a page (`GroupTooTall`);
- required keeps with no next block (`RequiredKeepAtEnd`) or followed by a
  break (`BreakAfterRequiredKeep`);
- required chains taller than a page (`ChainTooTall`), computed by a
  backward pass over the same two per-block lists the old validation
  allocated.

**Scan.** Each page is one forward scan from its start. It keeps scalar
state only: the running height, the best candidate, its score, and the last
required keep that made a candidate illegal.

- A candidate is a block boundary or a line inside a splittable block. Its
  score is the bit vector R1..R5.
- A required keep makes a candidate illegal. Groups and unsplittable blocks
  are atomic.
- A reachable explicit break ends the page. The best candidate wins, and a
  tie goes to the latest.
- If a fresh page has no legal candidate, the unit at its start is the
  error.

After the scan, the page is materialized once, exactly as the old loop
placed it: fragments, placements, spacing, and clamping are unchanged.

**Equivalence.** Wherever the old algorithm succeeded, it took the latest
break that satisfied every keep and both line minimums, since any violation
was an error. The latest all-satisfied candidate is exactly what the scan
chooses. Documents that paginated before therefore paginate
byte-identically, and no existing snapshot's page composition changed.
Documents that failed only because a heading chain was taller than a page,
or because a paragraph could not meet both its orphan and widow minimums,
now succeed with a recorded relaxation.

**Complexity.** Each page scans at most one page of positions past its
chosen break. Candidate visits are therefore bounded by the placed lines
plus one page of look-back per page, and nothing is re-laid-out or
backtracked across pages. The new `candidate_visits` counter proves this in
the scale pairs.

**Facade policy.** `KernelFacadePages` derives each block's policy:

- headings and titles are unsplittable and keep with the next block
  (`Preferred(HeadingKeep)`); figures are unsplittable;
- an authored keep-with-next binds the last leaf of its group. `Required`
  outranks the theme keep, and `Preferred(AuthorKeep)` applies only where
  the theme sets none;
- a page break sets the next leaf's `break_before`;
- spacers add to the previous leaf's spacing;
- consecutive leaves of one outermost list have no paragraph spacing;
- keep-together groups become required groups.

Page breaks at either end of the flow, or doubled, are
`layout.page_break_position`. Page-layout errors map to
`layout.keep_conflict`, `layout.oversize_block`, or
`document.figure_oversize`, with every participating source's authored
path.

## Diagnostics

Located layout and list diagnostics use `located_batch`: the dotted code in
`FeatureReference`, and the ordered paths in `details`. Paths name list
items `items[k]` and a keep-with-next's block `block`. A leaf's path is
recovered on the rejection path from the normalized arenas, by counting the
siblings before it: leaves (a legacy bullet list once), groups, page breaks,
and spacers.

The path builders reproduce the previous container-path allocation profile.
Building every path from a tuple list cost one allocation per located
rejection. A same-cache A/B found this in the rich-inline and container
negatives, and the builders now collect group codes exactly as before.

## Ownership, copying, retention, and complexity

- **Normalization** stays O(blocks + groups + inline records + text bytes),
  with one frame stack per top-level grouping block.
- **Planning** is O(blocks + groups + records). `semantic_code` is O(keep
  nesting), and the label, numbering, and break checks are O(1) per item or
  break.
- **Build.** The build loop is now one flat loop over group openings and
  blocks. The previous inner `while` over group openings was the only nested
  loop updating the store buffers. With list items writing into those
  buffers it cost three allocations per block; flattening it restores the
  exact previous count.
- **Lines and pages** are O(runs + lines), with one forward segment cursor
  per block.
- **Page layout** is O(blocks + lines + pages × page capacity). It allocates
  the same two validation lists as before, plus an atomic-group list only
  when groups exist and the relaxation list only when a relaxation occurs.
- **Retention.** Nothing new is retained past preparation. Relaxations live
  in the page plan, and the new arenas share authored strings.

## Evidence

**Package expects.**

- `KernelPageLayout`: the old cases on the new model; a paragraph moved
  whole; widow relaxation; heading relaxation; a group moved; group, break,
  and chain conflicts.
- `KernelFacadePages`: list continuity for legacy and nested lists.
- `KernelFacadeSemantics`: nested containers and inline records in the
  group kind.
- `Pdf`: public lists, the attribute bytes, two pages from a break, and seven
  located rejections.

**Harness family** `tests/layout_policies` (`layout-policies-v1`, pinned
`nightly-2026-09-26-d6267b4`, cold cache, full harness order):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| nested lists | 1 | 15,709 | 66 nodes, 5 lists, 14 items, depth 11, 34 lines, 19 candidates |
| explicit breaks and spacers | 2 | 14,740 | 19 nodes, 25 lines (segments), 22 candidates |
| keeps across page boundaries | 5 | 10,739 | 12 candidates; R1 and R2 each relaxed once |
| reported relaxations | 4 | 5,841 | one-line flow; R2, R4, and R5 each relaxed once |
| keep groups and lists x50 | 5 | 70,540 | 352 nodes, 50 lists, 201 lines, 100 candidates |
| keep groups and lists x500 | 48 | 685,972 | 3,502 nodes, 500 lists, 2,001 lines, 1,000 candidates |
| adversarial heading chain x50 | 2 | 16,554 | 51 lines, 50 candidates, 1 R1 relaxation |
| adversarial heading chain x500 | 19 | 135,627 | 501 lines, 500 candidates, 18 R1 relaxations |
| atomic negatives | 1 | 33,852 | 25 rejections; 4-deep list boundary accepted |

- **Nested lists** nests a decimal list, a bullet list, and a lower-alpha
  list three deep. Its items hold a rich paragraph, a continuation
  paragraph, and nested lists. It also has an upper-Roman list and the legacy
  bullets.
- **Explicit breaks** reproduces the letter's letterhead and address blocks
  with `⏎`, a link wrapping across a line break, 12 pt and 36 pt spacers, a
  kept signature block, and a page break before the schedule section.
- **Keeps** moves a signature group whole to page 2, moves a three-block
  required chain to page 3, relaxes a preferred keep before an explicit
  break (R2), and places a heading alone before a group that cannot share
  its page (R1).
- **Atomic negatives** each return their stable code and ordered paths with
  no bytes:
  - four `layout.keep_conflict`s: a tall group, a break inside a group, a
    required keep before a break, and a required keep at the end;
  - a required keep before a too-tall group;
  - a 150-sentence heading (`layout.oversize_block`);
  - both `layout.keep_empty` forms and `layout.spacer_negative`;
  - three page-break positions;
  - an empty list and an empty item;
  - three `semantics.list_item_content` forms and a page break inside an
    item;
  - a 5-deep list (`semantics.list_depth`);
  - `semantics.list_numbering` for a Roman list past 3999 and for letters
    from 0;
  - `layout.list_label_width` for a label reading `1000.`;
  - three line-break positions.

**Linear scale pairs.**

- **Keep groups and lists** (10× the units): nodes grow 9.95×, lines 9.96×,
  candidate visits 10×, and allocations 9.72×.
- **Heading chain** (10× the headings): candidate visits grow 10× and
  allocations 8.19×.

Every page of the heading chain relaxes R1 once and never rescans earlier
content. All counters are within the linear bound.

**Independent checkers.**

- `scripts/check_structure_semantics.py` now requires every `L` with
  labelled items to declare a `ListNumbering` other than `/None`. Its pinned
  nested tree includes the attribute, and a new mutation twin (`/Disc` to
  `/None`) is rejected. The self-test rejects all 14 twins.
- Every family snapshot passes `pdfa4`, `structure_semantics`, and
  `rich_inline`, which confirms logical text in structure order equals paint
  order across line breaks and segments.

**External lanes.**

- veraPDF PDF/A-4 `--cases` passes all 38 Archive snapshots with zero failed
  checks, and `--standard-cases` fails only the deliberate omissions.
- Arlington `--cases` passes all 184 case files and the gallery.
- The six regenerated gallery PDFs render pixel-identically in PDFium and
  MuPDF, so the previews are unchanged.

## Reviewed rebaselines

Every delta comes from a cold-cache, full-order run. Causes were confirmed by
same-cache A/B builds.

**Bytes: 7 snapshots and 6 gallery PDFs.** Every document with a
`Pdf.bullets` list gains exactly `/A << /ListNumbering /Disc /O /List >> ` on
its `L` (39 bytes per list), plus the dependent xref and trailer `/ID`:

- `tests/archive/archive_report.pdf` and `archive_report_400.pdf`;
- `tests/containers/nested.pdf`;
- `tests/generated_label/generated_label.pdf`;
- `tests/rich_inline/mixed.pdf`;
- the report bytes inside the profile twins and chunked cases;
- brand-brief, chunked-export, invoice-1048, product-brief,
  quarterly-report, and release-notes.

No other snapshot changed, and no page composition changed.

**Allocations: 17 existing cases, all carrying one bullet list per
document.**

- **+3 per semantic planning pass.** One attribute list, plus the kernel's
  attribute validation. This covers the authoring fixtures' semantic,
  shaping, line, and pagination cases at both sizes, and the generated-label
  negative.
- **+36 per emitted document.** The attribute plus the `/A` dictionary
  lowering: its names, a direct dictionary, and its entry. This covers the
  archived report and timestamps cases, the generated-label text, twice for
  twins and chunked outputs, and +75 for `mixed` (bytes, planning, and a
  pipeline build).
- `nested` records +40 in full harness order. A same-cache A/B that removes
  only the attribute restores both it and the authoring cases to their
  previous counts exactly.

**Intermediate regressions found and removed.**

- +3 per block from the nested build loop (see
  [complexity](#ownership-copying-retention-and-complexity)).
- +6 per rich paragraph from the label-request helper.
- +1 per located rejection from the path builders.

**Work counters.** Only `output_bytes` and derived byte totals change, by 39
per list.

**Transient failures.** The pinned compiler segfaulted in about one in three
interactive `roc check` and `roc test` invocations of `package/all.roc`
during development; every retry passed. No harness run hit a compiler
segfault. One run failed on a transient package download (`roc-fuzz`), and
its rerun passed.

## Pre-existing defects found and fixed

- **Documents longer than 32 pages failed preparation.** A non-root page-tree
  node built its `/Parent` reference in one object builder and its
  dictionary from the previous one. The dictionary then named a value its
  builder did not hold (`IndexOutOfRange … ValueIndex`), surfacing as
  `UnsupportedAuthoringContent`. A probe of plain paragraphs reproduced it at
  a166158: 340 paragraphs (32 pages) succeed, and 350 fail. The x500 scale
  case (48 pages) now exercises the two-level tree.
- **Facade name-byte budget.** Every structure element interns its role name
  and every attribute dictionary its keys, so name bytes grow with the tree.
  The facade's 8,192-byte budget failed near 1,000 list items. It is now
  1 MiB.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: typed mandatory constraints and ranked preferences, keep groups, explicit breaks, relaxation records, list geometry, and segmented paragraphs, with allocation and work evidence |
| Facade | Executable for the list, break, spacer, and keep constructors and `line_break`, with stable located diagnostics |
| Advanced integration | `KernelPageLayout.Plan.build_with_groups` and `relaxations`; no separately authored consumer |
| Conformance | `ROC-PDF-PDFUA2-8-2-5-25-LIST-NUMBERING` and `ROC-PDF-PDF20-LIST-SEMANTICS` are `implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Open issues

- **Relaxations are not yet public.** They are recorded in
  `KernelFacadePages.Plan.relaxations` for the preparation-report slice; the
  report must also map block indexes to authored paths.
- ~~**Line breaks in the logical text.**~~ (open-issues slice) Each
  explicit line break's separator is a U+0020 appended at normalization to
  the text leaf before it (unless that text already ends in a space), so it
  is painted, invisibly, at the end of the pre-break line inside that
  leaf's occurrence, and structure-order text reads `Wharf Street Hobart`.
  The separator counts toward the line's fit exactly like the trailing
  space of a soft-wrapped line, and a link wrapped across a break covers it
  in its quad. `check_rich_inline.py --self-test` pins the two address
  blocks of the `breaks` snapshot. The breaks, letter, and invoice
  snapshots gain one space glyph per break (about nine allocation events
  each, the existing per-glyph placement and content-writer cost).
- ~~**List labels**~~ (open-issues slice): a list whose widest generated
  label does not fit the theme indent widens its whole label column to that
  label's width plus half the label size, so all its items' bodies stay
  aligned, and nested bodies indent by the sum of their lists' columns.
  `layout.list_label_width` now reports only a column that leaves its body
  no width. The `nested lists` case adds a list from 98 (`100.` widens its
  column to 27.0 pt) with a nested `VIII.`/`IX.` list (25.1 pt); the
  negative is four nested lists of `MMMDCCCLXXXVIII.` labels. The dense
  per-block geometry costs one to six allocation events per document and
  32 bytes per block (+1.4% bytes at most, on the x1000 facade pairs).
- **List item content** is limited to paragraphs, rich paragraphs, and lists,
  and must begin with a paragraph. Keeps inside items are rejected.
- **Page-break edges.** A page break at the edge of a `keep_together` is
  accepted because it does not split the group. The record documents this
  interpretation of INV-A7b.
- **Name interning.** Role and attribute names are interned once per use
  rather than deduplicated; the raised budget treats the symptom.
- **Facade ceilings.** The facade still rejects documents beyond 2,048
  occurrences or 4,096 nodes (about 500 one-paragraph list items) with
  `UnsupportedAuthoringContent`.
