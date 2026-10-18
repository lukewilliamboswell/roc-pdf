# Bounded manual composition: design and closure record

Issues #49–#53 are closed for the declared bounded Gate 6 extension subsets
brought forward from Gate 8 for a technical-manual consumer. This record
collects their implementation and final integration evidence. Gate 7 and
`PdfUa2` remain pending; `Archive` remains the default profile. The integration
branch is `integration/manual-composition-49-53`.

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
The final integrated and cross-target results below complete the slice evidence.

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
rich-flow cases pass strict allocation, work and snapshot replay. Accepted
list and zero-padding counts reflect the reviewed removal of unnecessary
frame/header arenas; allocated-byte guards remain unchanged. The existing
rich-inline 10/100 pair also retains exact
recorded allocations, requested bytes, work and snapshots.

The dedicated reference evidence includes ten strict fixture cases, six
PDF/A-4 validations, seven independent mutation checks and 62 reader renders.
The scaled-text baseline and trailing-space alignment regressions are fixed.
The geometry case now retains its original PDF and work with two fewer
allocations, after carrying the continuation-frame fact explicitly instead
of retaining an unnecessary header arena. The other reference counts remain
unchanged.

The existing page-template letter scale cases retain their original exact allocation counts
after removing unnecessary default table-frame storage. A final integration
review also identified table fills extending beyond accepted body frames;
preparation now reserves their outer paint footprint before pagination.
Affected decorated-table snapshots are reviewed against that correction.
Repeated-header lead bands now allocate only for active containers, retaining
zero-padding panels while restoring the original exact legacy table counts.
The complete native comparison and strict affected replay, followed by the
independent strict Linux run, establish integrated allocation/work/snapshot
evidence and cross-target PDF byte equality. The previously provisional
`x64musl` expectations are now observed. The [final integration closure](#final-integration-closure)
below records source identity and the pinned conformance checks. This closes
the declared extensions only; no Gate 7 or PDF/UA-2 claim is made.

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


## Final integration closure

The 2026-10-18 pinned native run at production source `8c5af2e` completes all
61 validation tasks, 62 cold fixture builds and 409 cases. Every PDF snapshot,
deterministic work vector and registered independent validator passes. Its
final comparison reports one allocation expectation reduction: the source-block
negative carrier drops from 8,267 to 8,264 by avoiding three arenas before
excessive-padding rejection. The
[exact cause](source-blocks.md#manual-composition-integration-review) is reviewed
and the changed expectation passes strict harness replay from the same retained
cold-built executable. The complete comparison and affected strict replay
together establish the native allocation/work/snapshot evidence; the initial
comparison itself exits nonzero for that reviewed expectation.

The comparison also records 123 byte-only differences; all remain within their
existing guards, with a maximum increase of 0.876%. No requested-byte ceiling
changes. Pinned veraPDF 1.30.2 with explicit PDF/A-4 flavour validates all 193
Archive snapshots with zero failed checks; a retained manifest records their
accepted SHA-256 hashes. The thirteen gallery originals independently retain
the zero-failure profile and whole-file reader evidence above.

The [strict Linux CI run](https://github.com/lukewilliamboswell/roc-pdf/actions/runs/39103555113)
at `75e09c8` passes all 409 cases with exact per-target allocation/work
expectations, immutable PDF snapshots, retained allocated-byte guards and all
registered independent validators. The native measurements were collected at
`8c5af2e`; all 224 Roc source SHA-256 values in the retained native manifest
remain identical at `75e09c8`. The intervening commits change only the reviewed
allocation expectation, conformance-ledger traceability and documentation.
Thus both runs exercise identical production and fixture source; Linux matches
the same accepted snapshots and establishes cross-target PDF byte equality.
This does not assert equal requested-byte observations across targets.

The same CI run's Arlington job uses the digest-pinned veraPDF Arlington
1.30.2 service over 345 distinct snapshot and gallery files.
344 files have zero failed rules and checks, covering all package and gallery
output; the platform-written
`tests/placeholder/snapshot.pdf` retains only its already recorded
`FileTrailer-ID#11` exception. The CI checker-contract, nine bounded fuzz targets at 2,000 runs each,
release-bundle consumer and all thirteen gallery lanes also pass.

Together with the per-slice semantic/geometry and mutation oracles, atomic
negative cases, original-file readers, ownership review and scale pairs, this
closes the declared bounded #49–#53 extensions. General generated TOCs,
flow-changing references, midpage chapter changes, general custom pagination
and browser SVG/HTML rendering remain outside these subsets. Gate 7,
`PdfUa2` and `AccessibleArchive` remain pending; `Archive` stays the default.
Human reader and assistive-technology review were not performed and remain
optional.
