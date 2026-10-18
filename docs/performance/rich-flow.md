# Rich list bodies and continued callouts

Issues #52 and #53 extend the existing flow compiler. Feature evidence is
recorded below as it is run; this change makes no new PDF/UA-2 claim.

## Representation and ownership review

List bodies accept source blocks, figures and tables using their existing
semantic subtrees. `Pdf.callout` is separate from measured `CustomBlock`:
its data-only panel, padding and fragmentation describe a `Div` of ordinary
flow children. Source ActualText and header/caption relationships remain
facts from semantic planning, never inferred from paint order.

Horizontal geometry is calculated after label shaping, before table column
resolution. The line plan transfers its existing dense geometry/offset/end
arenas to pagination; tables, captions, cells, fills, rules, repeated headers
and figure fit share their actual parent frame. No source or resource
payload is copied to calculate frames.

Pagination retains flat paragraph/source/table-row units and scalar unit/line
continuation. Callout spans use dense IDs and prefix transition heights.
Each accepted candidate reserves open containers' bottom padding. Reopening
ancestors precedes repeated headers. A layout-only span accounts for the
outer table row-gap decoration footprint inside a callout. Semantic callout
nesting shares the existing container-depth16 bound; layout span depth is
at most17 because table cells cannot contain flow blocks. Both are checked
before growing their corresponding ancestor arena.

Exact context and ancestor writes, accepted fragment updates and fragment
writes supplement existing metric-read/line/page candidate counts. All
buffers use geometric append or exact one-time capacity, never reserve/concat
per append. No suffix slices, rollback scenes, recursive pagination callbacks,
whole-document accumulator aliases or remeasurement on continuation occur.
Normalized sources, glyphs and resource payloads remain owned once; temporary
context/ancestor arrays die after pagination. Reports retain compact accepted
rectangles and paths, never discarded plans or payloads.

With maximum depth D=17, frame planning and container preparation use
O(blocks + groups + D*containers), pagination retains its existing bounded
candidate scan plus O(D) transition work at a boundary, and panel collection
uses O(D*accepted-unit-fragments). Storage is linear in blocks, containers,
accepted fragments and output commands. Counts are bounded by existing facade
block/node/page limits and the explicit fragment/scene/report budgets.

## Verification

The `rich_flow` harness family covers generated wide list labels and rich
children (10/100), one long rich-paragraph callout (10/100 paragraphs), and
nested callout/list/source/figure/table composition (3/30). Its source rows
include blank lines and trailing spaces; figures retain alternatives and
captions; tables repeat headers. Public output and a compiler work probe use
identical authoring/font/page facts. Existing CustomBlock cases remain
regressions for their measurement and unsplittable diagnostics.

Pinned native metrics, independent checks, negative cases and reviewed
baseline causes are added after the final harness run. Until those records
are populated, this file describes implementation design rather than gate
closure.
