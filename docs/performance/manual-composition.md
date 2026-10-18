# Bounded manual composition: design and integration record

Issues #49–#53 are independent Gate 6 extension slices, brought forward from
Gate 8 for a technical-manual consumer. This record tracks the implementation and
integration evidence; it is not a closure claim. Gate 7 and `PdfUa2` remain
pending. The integration branch is `integration/manual-composition-49-53`.

## Representation and ownership

- Derive dense parent frames after label shaping and before child measurement.
  Frames contain scalar parent identities, offsets, available width and padding.
  Inputs are consumed once; source/resource payloads remain owned once.
- Keep the flat paginator. Callout spans and typed scalar continuation cursors
  augment existing paragraph/source/row/figure units. Opening and closing
  events charge padding once per fragment; active ancestor bottom padding is
  reserved in every candidate fit. No remaining-content copies or rollback
  scene lists are retained.
- Produce accepted callout rectangles, repeated-header placements and scoped
  page contexts explicitly. Later stages consume these facts rather than
  recovering relationships from paint order, geometry or text.
- Fixed-width reference atoms retain symbolic identity through pagination;
  exact generated Unicode, source ranges and glyph runs finalize before the
  prepared boundary. Literal interned sources are immutable. Final navigation
  and reference values share committed anchor facts.
- Resolve destination names through deterministic indexed lookup and page
  labels through ordered range lookup. Bound formatted text before allocation.
  Cache identities include exact font/style/language, width and resolved value.
- Keep template region spans indexed by dense template ID. No per-page scan of
  all scopes/templates. Native callouts share the 16-level container budget;
  lists retain four levels. Every depth and work exhaustion is an error.
- Preparation reports retain strings/scalars only, preflight entry/text budgets,
  and collect nothing on the ordinary no-report path.

Expected work is linear in normalization inputs, frame/event visits, measured
content and accepted placements, multiplied only by the fixed nesting bound;
name indexing may use worst-case O(n log n). Fragment materialization runs once
per accepted range. Scalable fixtures must measure actual frame/event,
reference-resolution, page-candidate and fragment-write work, including shared
inputs and bounded errors. Accumulators follow the architecture's uniqueness
rules; no growing list is preserved on an error path.

## Coordination

The coordinator owns integration, architecture/roadmap changes, shared
contracts and final baseline/snapshot review. Isolated topic worktrees own
navigation/reference work, rich-flow work and adapter/evidence work. Shared
signature edits are communicated before integration and merged sequentially.
Feature evidence is provisional until the complete integrated suite passes.

## Acceptance obligations

Every slice requires typed public behavior, located atomic rejections, an
independent structure/geometry/extraction checker, applicable profile/reader
checks, exact pinned-build allocations and deterministic work, allocated-byte
guard and small/large growth pairs. A combined manual must exercise destination
references, scoped chapter templates, nested rich list/callout content, continued
tables/source, and prepared vector figures together. Cross-target byte equality
and the full `./scripts/test.py` run are required before final closure.

Snapshot or baseline differences are reviewed by architectural cause before
acceptance. Human reader/AT review is optional and recorded if performed.

## Evidence status

The integrated implementation contains the public fixed-width reference
resolver, explicit chapter scopes, shared rich-list/callout frames, bounded
fragmentation and prepared-vector adapter. Native slice evidence is recorded
in [destination references](destination-page-references.md),
[chapter templates](chapter-templates.md), [rich flow](rich-flow.md), and
[the vector adapter](vector-diagram-adapter.md).

The [combined technical manual](technical-manual.md) 2/20-chapter pair passes
strict native allocation/work/snapshot replay, the independent semantic and
geometry oracle plus four mutation twins, veraPDF PDF/A-4, and whole-file
PDFBox/MuPDF extraction/rendering (180 page renders). All twelve integrated
rich-flow cases retain exact recorded allocations, work and PDF snapshots;
small requested-byte differences remain inside existing guards without
changing baselines. The existing rich-inline 10/100 pair also retains exact
recorded allocations, requested bytes, work and snapshots.

The dedicated reference evidence includes ten strict fixture cases, six
PDF/A-4 validations, seven independent mutation checks and 62 reader renders.
The scaled-text baseline and trailing-space alignment regressions are fixed,
with existing reference allocation counts and snapshots preserved.

The legacy letter fixtures retain their original exact allocation counts
after removing unnecessary default table-frame storage. A final integration
review also identified table fills extending beyond accepted body frames;
preparation now reserves their outer paint footprint before pagination.
Affected decorated-table snapshots are reviewed against that correction.
Repeated-header lead bands now allocate only for active containers, retaining
zero-padding panels while restoring the original exact legacy table counts.
The complete integrated harness run remains pending. Cross-target equality
remains unobserved because
the local Docker daemon does not answer bounded discovery. New x64musl
expectations are explicitly provisional native mirrors required by the
harness schema. Final extension closure remains pending those checks; no
new Gate 7, PDF/UA-2 or cross-target claim is made.

## Gallery paint-footprint review

All thirteen public gallery apps were regenerated with the pinned Roc build
against the corrected paginator. Ten decorated-table PDFs change; the
furniture-typography, source-blocks and prepared-vector examples remain
byte-identical. Every gallery document retains its page count and exact
logical role tree, text, ActualText and alternative-text ownership.

The independent row-origin comparison observes the expected initial half-gap
insets: 1 pt for chunked-export/release-notes, 1.5 pt for the report/invoice/
operations handbook, 2 pt for field-guide/product-brief/warranty-letter, and
2.5 pt for brand-brief/quarterly-report. Later tables can accumulate the
preceding tables' closing and opening reserves. In brand-brief those reserves
move the kept three-item instruction list intact from page 2 to page 3;
its later voice table consequently moves downward by 58 pt. Its three-page
count and complete logical content remain unchanged.

Only business-report, chunked-export, quarterly-report and tax-invoice have
changed first-page rasters; their previews are regenerated at 96 dpi with
Poppler 26.07.0 and attributed accordingly. Product-brief's first-page content
stream is exact and the old/new PDFs render identically with the same tool;
its old committed Poppler 24 preview differs from both current renders, so
that unrelated preview is retained. The other eight previews stay exact.

All thirteen originals pass pinned veraPDF 1.30.2 PDF/A-4 with zero failed
checks and the independent structure checker. PDFBox 3.0.8 and MuPDF 1.28.2
extract and render every page: 35 pages per reader, 70 renders in total.
