# Contents, indexes and reference layout

Consecutive `Pdf.contents_entry` blocks under one authored parent normalize
to a single PDF 1.7 `TOC`. Each `TOCI` owns the rich paragraph with its two
internal links and logical separator. The normalized arena records each entry's
block, reference identity, indentation, gap and leader choice. The page field
is the final reference. Reference resolution carries the target's semantic node
alongside the page value, providing the `TOCI /Ref` independently of paint.

Measurement wraps only the title clusters at the available frame width less its
indentation, field width and gap. The normalizer's separator and reference atom
are attached to the final title row. A sparse terminal-row record fixes the
reference's offset at the common right edge before pagination. Existing page
flow may split the title rows across pages. Resolution shapes final numbers and
proves field fit against these committed rows; it never wraps a resolved value.

Final-row intervals generate 0.6-point decorative squares at 3-point spacing,
with clearance from both title and reference column. The rectangle arena is
bounded by the existing item budget and then consumed through the existing
Decoration-artifact scene path. Dots have no Unicode, semantic nodes, MCIDs,
font resources or annotations. Both title and number retain their own internal
link annotation ownership, including a title continued across pages.

All scans use forward cursors or dense row/item indexes. A temporary title view
is copied only to set its mandatory final boundary, so total copied title items
is linear in authored title size. The terminal metadata is proportional to entry
count, and the dot arena is proportional to painted dots under explicit budgets.
Growing accumulators remain uniquely owned; merging leaders with ordinary
page-ordered rules writes a new arena once.

## Acceptance evidence

The `destination_references` fixture family includes 2- and 80-entry cases with
Unicode titles, three indentation depths, styled titles, wrapped subsection
labels, two separate links and optional leaders. A single 700-phrase title
continues across pages. Eleven negative cases cover empty titles, references
inside titles, negative spacing, non-End fields, exhausted geometry, unknown
destinations and exact field overflow; rejection returns no PDF bytes.

The independent `check_contents_entries.py` reads emitted glyph coordinates,
PDF structure, destination arrays, annotations and artifact path rectangles. It
checks a common 545-point right edge with a 0.5-point tolerance, hanging wraps,
final-title-line number placement, complete logical text, target equality and
leader clearance/ownership. Displacing a page-number origin by two points must
fail its mutation self-test. The ordinary PDF/A-4 and structure validators remain
part of each fixture's registered acceptance set.

The accepted files are registered for explicit PDF/A-4 and PDF/UA-2
validation. The structural oracle also removes one entry's `/Ref` and checks
that the missing relationship fails even when both of its annotations still
point to the correct destination.

The pinned allocation and determinism harness records the exact work vector
in [tests/spec.json](../../../tests/spec.json). The semantic wrappers and
`/Ref` values add a linear number of nodes and references. Normalization
processes each entry once, and one indexed target per entry moves through
resolution and object lowering. Line measurement, wrapping, page field and
leader counters are unchanged. The negative case measures the same eleven
public rejections under the same authored locations. Its larger count comes
from preparing the TOC and item nodes for the rejected requests.

| Entries | Exact arm64mac allocations | Allocated bytes | Measured items | Wrapped item visits | Contents rows | Dots |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 1,606 | 4,315,250 | 317 | 331 | 2 | 125 |
| 80 | 11,218 | 37,060,186 | 8,657 | 8,983 | 80 | 6,322 |
| 1 tall | 2,226 | 22,162,693 | 11,916 | 12,494 | 1 | 0 |

The pair varies title lengths and leader intervals. Wrap visits stay below
twice the measured items and the terminal row count equals the entry count.
The tall entry retains one title link and one structure item across three
contents pages. Its page reference occurs on the final title line.

## Generated navigation

Generated contents reuses the same terminal-field path after selection.
Each selected heading contributes one entry and its stable destination key.
An index sorts at most 256 retained UTF-8 keys for each authored block.
Each term checks at most 16 destinations for duplicates. The resulting
reference atoms retain authored target order, including when terms share a
destination.

The flow-changing field keeps the shared literal shape and symbolic spine
through stabilization. Each history entry owns a compact word buffer, with
at most eight buffers of 500,000 words apiece. Earlier candidates do not enter
the history. The latest candidate supplies geometry at convergence.

`GeneratedNavigationModel` exhausts 341 transition histories, 65 heading
histories, and 85 index histories. In its transition model the page count
stays constant while anchor positions change. Comparing only page counts
causes the production stabilization check to fail that model.
`generated_navigation` fuzzes one- and two-level selection, duplicate titles,
field widths, missing scopes and index duplicates before measurement.
The public fixture lane verifies both a label that moves its own destination
and a physical pagination cycle. The emitted-PDF checker also replaces one
index `/Ref` with a different valid target and verifies that the mutation fails.
