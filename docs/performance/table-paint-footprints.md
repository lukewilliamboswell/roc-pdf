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
| Internal horizontal rules only | 51,600 | 28,740,676 | 4 | 81 | 0 / 0 / 0 |
| All cells span both columns | 28,891 | 17,778,228 | 4 | 81 | 0 / 0 / 0 |
| Source-free reference header | 55,144 | 30,553,757 | 4 | 81 | 82 / 1 / 81 |

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
