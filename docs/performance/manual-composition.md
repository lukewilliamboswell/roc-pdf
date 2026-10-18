# Bounded manual composition: design and integration record

Issues #49–#53 are independent Gate 6 extension slices, brought forward from
Gate 8 for a technical-manual consumer. This record initially specifies design
and evidence obligations; it is not a closure claim. Gate 7 and `PdfUa2` remain
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

Implementation and executable evidence pending.
