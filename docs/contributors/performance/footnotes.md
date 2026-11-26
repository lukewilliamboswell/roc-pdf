# Whole first-citation footnotes

Each accepted footnote is one PDF 2.0 `FENote` with its text and a visible
return link. The note and its first citation share the physical page.
Later citations use the same target. The note remains in the logical
declaration order and paints at the bottom of that page in first-citation
order.

| Authority | Writer obligation and evidence |
| --- | --- |
| ISO 32000-2:2020+EC3 §14.7.2/Table 355 and §12.3.2.3 | Each citation Link contains its note's structure reference. The FENote contains references to every citation in authored order. Every annotation's `SD` names the expected structure element and its `D` resolves to the same page and coordinates. |
| ISO 14289-2:2024 §§8.2.5.14 and 8.8, WTPDF 1.0 §§8.2.5.14 and 8.8, and ISO/TS 32005:2023 Table 5 | Document owns FENote with marked note text and one return Link. The typed optional `NoteType` attribute appears on the WTPDF form of the fixture. The base PDF/UA-2 profile uses FENote and the required references. |
| Package geometry | The first citing line and each whole note reserve their measured height and a six-point note gap. If the note moves the first citation beyond a candidate cut, the note remains with the next legal occurrence of that line. An impossible placement rejects the document at the note path. |

The owning paginator model exhausts 624 states and 623 steps through depth
four. It independently enumerates cuts over three body lines, two possible
notes and three page heights. Five witnesses cover repetitions, exact fit,
impossible placement, two notes on one line and a forced break. A concrete
layout fixture moves a citation off the first page and checks one millipoint
below the legal height. Solve verifies the checked body-plus-note fit
inequality. The public handbook fixture exercises forced page breaks and
confirms both buffered and chunked output reject absent, repeated, misplaced,
oversized, uncited and malformed declarations atomically.
The dedicated LLVM fuzz suite retains six named inputs, including a
repeated citation after a break and rejection when its whole note cannot fit.

All four PDF snapshots pass Arlington 1.30.2 and veraPDF 1.30.2 explicit
`4` and `ua2`. The declared WTPDF PDF also passes `wt1a`. The independent
PDF decoder checks note order, both directions of the citation graph, the
visible return link, and placement below the first citation's annotation.
It rejects a dropped backlink and a wrong structure destination. Arlington
and `4` accept both mutations. `ua2` detects the omitted reciprocal
reference and accepts the wrong structure destination.
The maintained handbook preview shows the complete note at the foot of
page 2. Poppler extraction shows the later marker on page 3 and a single
painted instance of the note text.

## Allocation and work

Normalization keeps bounded citation metadata and a sorted ID index.
The layout pass walks measured rows by citation order. It builds a sparse
prefix index for unique first citations and finds the maximum note-inclusive
fit by monotone search. After choosing a cut, the paginator writes the
body and note placements once. The normal materializer preserves a separate
paint-order row tape for note documents. Each entry carries its existing
shape range instead of copying source text, and the temporary row order
belongs to preparation. Each reciprocal structure-reference edge occupies
one slot in a flat adjacency tape, bounded by twice the number of citations.

| Notes | Pages | Roc dev allocations | Allocated bytes | Chunks | PDF bytes |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 2 | 1,689 | 6,664,777 | 31 | 18,241 |
| 18 | 7 | 3,879 | 12,948,240 | 46 | 25,750 |

[`tests/spec.json`](../../../tests/spec.json) pins the work and allocation
evidence for the prepared byte and chunk paths.
