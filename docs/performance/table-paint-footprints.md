# Table paint footprints

Table rows previously reserved their text and inter-row gaps during page
selection. Fills, column rules and frames also occupy the outer half row gaps.
Outside a callout that extra painted area could enter a scoped header/footer
reservation even though the row text fit. Moving paint after pagination or
clipping it would violate the accepted-frame contract.

Preparation now creates a layout-only `NoPaint` span for an ordinary table
when an applicable row/cell fill, positive column rule with an actual adjacent
cell boundary, or positive frame occupies that outer area. The span reserves
half the row gap, rounded upward to the layout unit, at each fragment's ends, over the table rows (excluding the caption).
It participates in the same candidate-fit test as existing callout/table
spans, including repeated header lead under the selected opening or
continuation frame. Painters consume the resulting accepted row positions.
No semantic container, repeated semantic row, clipping path or fallback is
introduced. Existing table spans inside callouts retain their behavior.
Internal horizontal rules alone fit inside the row gaps and add no span.
Zero-gap tables have no additional outer vertical footprint.

`KernelFacadePages.callout_containers` determines applicability before
pagination from normalized authoring/style facts. A monotonic cell cursor
visits each cell once; the optional early any-fill check adds at most one
linear cell pass. A column-rule-only table scans its own row groups to check
for a real adjacent-cell boundary; tables with one spanning cell per row add
no span. Empty sections, a single row with only an even stripe, and zero-width
rules add none. Table groups do not nest, so those row scans total O(rows).
Parent searches retain the existing bounded callout depth. No growing
accumulator is returned through `Try` and then reused; the span accumulator
stays uniquely owned. New storage is one fixed-size span per applicable table
and the paginator's existing dense context facts. There is no per-table
whole-cell rescan, text decoding, paint-derived inference, or retained source
slice.

The focused `ScopedTables` fixture deliberately has no furniture gap. On A4
with 72 pt margins the opening body is `[106,746]` vertically; continuation
bodies are `[126,726]`. One 14 pt text row plus its 6 pt inter-row spacing and
outer half gaps gives exactly 32 physical rows on an opening page and 30 on a
continuation page. Each table has one header and 80 body rows, exercising
three pages and two repeated headers. The source-free variant places a
forward physical page reference in the repeated header. A final unscoped
heading confirms the explicit scope exit.

The independent emitted-byte checker derives those bounds from the authored
fixture constants. It verifies every fill/frame/column rectangle, exact row
baselines and text, one logical `Table` with one `THead`, repeated pagination
artifacts, scope furniture, and the resolved forward reference. Its mutation
twins move actual paint beyond both body edges or change repeated-header and
furniture ownership. It consumes no paginator/report geometry facts.

| Native case | Allocations | Allocated bytes | Pages | Page candidates | Contexts / ancestors / updates |
| --- | ---: | ---: | ---: | ---: | --- |
| Decorated scopes 2 | 106,032 | 57,961,159 | 7 | 162 | 163 / 2 / 162 |
| Decorated scopes 20 | 1,025,525 | 568,307,410 | 61 | 1,620 | 1,621 / 20 / 1,620 |
| Cell fill only | 52,612 | 28,853,813 | 4 | 81 | 82 / 1 / 81 |
| Column rule only | 51,674 | 28,750,812 | 4 | 81 | 82 / 1 / 81 |
| Internal horizontal rules only | 51,598 | 28,740,564 | 4 | 81 | 0 / 0 / 0 |
| All cells span both columns | 28,889 | 17,778,116 | 4 | 81 | 0 / 0 / 0 |
| Source-free reference header | 55,144 | 30,556,365 | 4 | 81 | 82 / 1 / 81 |

These are pinned arm64mac native observations. The x64musl schema entries are
provisional mirrors until the independent Linux run observes them. All cases
retain exact allocation/work expectations and the allocated-byte guard.

The pre-fix native control was built from the prior accepted `Pages` module
with the exact same public fixture. It emitted a first header fill at
`[729,749]` while the selected opening body ends at 746 pt. The independent
oracle rejected that original geometry; the correction emits `[726,746]`
and passes. The repaired small/large pair retains 162/1,620 candidate visits,
with the expected linear 2/20 table ancestor records; there is no extra
page or semantic node. All seven corrected PDFs pass pinned veraPDF 1.30.2
PDF/A-4 with zero failed checks. Canonical package tests include the two
applicability/cell-cursor regressions.

The final source-free observation includes the separately reviewed typed
maximum-body-size fact in `ReferenceLines.BlockItems`: 163 records widened
by 8 bytes across the fixture's two preparation/probe pipelines add exactly
2,608 requested bytes compared with the initial draft, with identical
allocation count, work and PDF bytes.

## Reviewed existing snapshots

The impact audit ran all 35 existing `tables` and `reference_documents`
cases through the pinned native apps before changing a snapshot. The exact
logical signature (roles, child order, owned Unicode, `ActualText`, `Alt`)
is unchanged in every PDF. Eight default table/negative carrier PDFs and
the reference negative carrier stay byte-identical. The six decorated table
PDFs and all twenty positive reference PDFs require the corrected geometry.
All existing adverse Roc observations still pass, including totals carry,
kept heading/figure captions and a controlled repeated-header table break.

For the 40-row styled, empty-cell and ruled tables every occupied row stays
on its original page and moves down exactly 2 pt. At 400 rows the corrected
fit moves 18 styled/ruled rows and 36 occupied empty-cell rows onto their next
physical page; cumulative placement changes are expected, with the same
12/11/12 total pages. Ordinary reference invoice/report rows move down
1.5 pt per applicable table boundary; reference letter rows reserve 2 pt.
Captions stay outside the new layout-only row span. These are accepted-fit
changes, not painter offsets.

The 100-section report has 100 separately painted tables. Its cumulative
outer reservations add 300 pt of row footprint before continuation effects,
so the document grows from 37 to 38 pages. Repeated headers grow from 9 to
12 and the associated coverage facts from 2,028 to 2,037. All 2,401 logical
fragments and 2,001 reported blocks remain unchanged. The independently
parsed geometry confirms the resulting row redistribution, and all existing
validators pass using the reviewed 38-page dimension. Every other existing
case keeps its page count; apart from that report, all deterministic work
stays exact except the serialized output byte count.

The reviewed exact allocation counts below include the necessary layout
span/context arenas and the changed serialization/buffer growth caused by
new accepted coordinates and breaks. Counts may rise or fall because PDF
operands and fragment boundaries change; shape, cell measurement and row
work do not gain traversals. Earlier allocated-byte ceilings remain in the
specification: every new observation stays inside its 10% guard.

| Existing painted case | Pages before / after | Observed allocations |
| --- | ---: | ---: |
| tables styled x40 | 2 / 2 | 27,447 |
| tables styled x400 | 12 / 12 | 207,997 |
| tables empty cells x40 | 2 / 2 | 20,817 |
| tables empty cells x400 | 11 / 11 | 160,578 |
| tables ruled grid x40 | 2 / 2 | 30,831 |
| tables ruled grid x400 | 12 / 12 | 229,134 |
| reference invoice | 2 / 2 | 35,714 |
| reference report | 4 / 4 | 47,916 |
| reference letter | 3 / 3 | 22,808 |
| reference invoice long text (INV-A1) | 3 / 3 | 37,966 |
| reference invoice wide code (INV-A2a) | 3 / 3 | 36,927 |
| reference invoice split row (INV-A4b) | 7 / 7 | 60,332 |
| reference invoice totals carry (INV-A5) | 3 / 3 | 70,095 |
| reference invoice rows x50 | 3 / 3 | 47,177 |
| reference invoice rows x500 (INV-A3) | 21 / 21 | 343,240 |
| reference report heading keep (REP-A1) | 5 / 5 | 50,552 |
| reference report figure and caption (REP-A2) | 5 / 5 | 51,962 |
| reference report table break (REP-A3) | 5 / 5 | 50,323 |
| reference report ordered faces (REP-A5) | 4 / 4 | 47,192 |
| reference report scaled figure (REP-A6b) | 5 / 5 | 46,875 |
| reference report sections x10 | 4 / 4 | 38,281 |
| reference report sections x100 | 37 / 38 | 312,172 |
| reference letter long recipient (LET-A1) | 3 / 3 | 23,422 |
| reference letter x60 (LET-A2) | 11 / 11 | 82,472 |
| reference letter x20 | 5 / 5 | 38,142 |
| reference letter x200 | 31 / 31 | 236,431 |

Default unpainted table expectations are deliberately retained. The separate
per-fragment lead-band arena audit must restore their earlier counts rather
than attributing those allocations to this paint correction. Negative carrier
expectations are reviewed separately because their measured preparations
include rejected/accepted intermediate documents even when their final PDF
contains no table.

All seven new originals also pass whole-file PDFBox 3.0.8 and MuPDF 1.28.2
Unicode extraction and rendering: 176 page renders across 88 pages, with
explicit page-count, A4 raster-size and visible-ink checks. The checker
compares complete extracted text against emitted semantic and artifact text,
including every repeated header/reference and scoped furniture item; it
removes only temporary raster outputs after checking them.

After the explicit snapshot review, all 26 changed legacy cases pass the
strict `scripts/test.py` runner with exact allocations, work, snapshots and
the retained byte ceilings. All 26 are Archive outputs; pinned veraPDF
1.30.2 validates them as PDF/A-4 with zero failed checks, parser logs or
warnings. They do not use the Standard lane's deliberate identification/
metadata omissions.

The final no-active-container lead-band optimization was replayed against
the same rich-flow app. The two new unpainted controls each remove two
allocations and 112 requested bytes, with exact work and PDF bytes. The
existing rich list 10/100 cases remove two/ten allocations and 112/3,056
requested bytes (one/five geometric arena-growth events in each of the
fixture's two pipelines). Their exact counts are now 130,132/1,252,916;
original byte ceilings remain. These are removed unused accepted-header
band records, not changed measurements or page breaks. Painted contexts
continue to retain their bands, including a zero-padding panel, so the
painted scope and nested-callout snapshots remain exact.

The final reference rejection matrix was rebuilt after the lead-band
optimization and observed at 162,065 allocations (previously 161,990),
115,105,578 requested bytes, with exactly 24 rejections, two report
obligations and the byte-identical 15,428-byte carrier. Its measured work
includes intermediate painted invoices/reports, including the 100-table
report whose overflow is rejected during furniture resolution after layout.
Those paths now construct the bounded outer-paint span/context facts even
though the failed document emits no PDF. Its exact count is recorded;
the earlier allocated-byte guard remains. The separate default-table
15-rejection carrier still has an unexplained six-allocation difference
under independent error-path review; its earlier expectation is retained.
