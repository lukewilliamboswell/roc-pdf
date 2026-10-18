# Combined technical manual evidence

The `tests/technical_manual` 2/20-chapter pair exercises issues #49–#53
through public facade preparation and byte emission. Both original PDFs
pass the independent combined oracle and veraPDF 1.30.2 PDF/A-4 validation
with zero failed checks. PDFBox 3.0.8 and MuPDF 1.28.2 extract and render
both whole files: 180 page renders, including purple source foregrounds,
prepared vector ink and exact printed/furniture text. MuPDF's glyph lane
uses `ignore-actualtext`; semantic ActualText is checked independently.

Each manual has a printed TOC with forward physical/label references,
repeated references to the last chapter, named structured destinations and
an outline. Explicit full-page scopes declare different opening and
continuation frames, short running labels and page-label/physical/total
furniture. Every chapter contains an outer callout and a numbered item with
exact LF/final-LF source and purple foreground, a scaled prepared vector
figure, and an inner callout containing a 40-row filled/framed table. Its
repeated header contains a configured-page-label reference. Inter is the
same explicitly registered face used to prepare the diagram.

The fixture deliberately prepares the public document and an identical
private pipeline work probe. Allocation measurements include both; the
work vector records one pipeline's actual stage counters. The test-only
`examples/vector-diagrams/all.roc` entry gives the prepared diagram the
same package identity as that probe. Instantiating `package/main.roc` and
`package/all.roc` together triggered a pinned compiler compile-time font
inspection failure in an existing package self-check. Production examples
continue to use the ordinary public entry.

| Chapters | Pages | Exact Roc allocations | Allocated bytes | PDF bytes |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 9 | 125,868 | 70,509,264 | 31,510 |
| 20 | 81 | 1,181,381 | 670,031,777 | 183,074 |

| Actual stage work | 2 chapters | 20 chapters |
| --- | ---: | ---: |
| Shaped runs | 245 | 2,441 |
| Measured rows | 305 | 3,041 |
| Shape metric reads, measurement and final shaping | 17,114 | 171,250 |
| Wrapped-item visits | 9,199 | 92,007 |
| Page candidates | 256 | 2,560 |
| Container contexts / ancestors | 109 / 12 | 1,081 / 120 |
| Container updates / fragments | 274 / 14 | 2,740 / 140 |
| Scope visits | 12 | 120 |
| Template region visits | 30 | 282 |
| Committed reference resolution phases | 1 | 1 |
| Furniture field resolutions / shaped items | 33 / 15 | 303 / 141 |

The tenfold authoring increase grows allocations 9.39 times and requested
bytes 9.50 times. Candidate visits and bounded ancestor work grow exactly
tenfold; fixed overhead accounts for the smaller page/allocation factors.
No repeated reflow or reference stabilization loop is used for these body
references. Each chapter reuses one prepared vector's source commands;
the public preparation stages still assign every semantic occurrence and
source slice separately. No shared append buffer escapes through a `Try`.

The independent byte oracle derives each chapter page from its heading's
actual MCR, checks exact printed TOC/body values, physical and structured
GoTo/name-tree targets, and outline titles/targets, and verifies declared
fixed-width alignment. It checks the exact semantic child tree and source
ActualText, live parent widths, scoped body frames, nested artifact panel
padding, table decoration bounds, repeated reference/header artifacts and
prepared vector labels/path ownership. It reads no report or new pager or
reference facts. Four reserialized mutation twins reject a changed printed
label, a wrong structured destination owner, misclassified running header,
and expanded callout border.

Native `arm64mac` expectations are observed with the repository-pinned Roc
and Zig. The corresponding `x64musl` fields are provisional native mirrors
required by the current harness schema; Docker.app's daemon did not answer
bounded discovery. They are not cross-target evidence. No PDF/UA-2 or human
reader review is claimed by this feature slice.

The final numeric-field review removed a needless Unicode scalar-count
allocation for each ASCII page-number/total field. These formatters already
produce an exact ASCII length; configured labels still count their Unicode
scalars. Under this fixture's two-pipeline boundary, the reviewed fix removes
exactly four allocations per accepted page: 36 / 324 at 9 / 81 pages. The
observed baselines above include that improvement; work and PDF snapshots
remain exact. Requested bytes fall by 324 / 3,222, matching the removed
UTF-8 list header and numeric payload storage.
