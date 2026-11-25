# Bounded authored contents entries

Issue [#65](https://github.com/lukewilliamboswell/roc-pdf/issues/65) adds a terminal
page column to the existing exact destination-reference path. This is an authored
layout primitive, not automatic heading collection, an index or general reference
stabilization.

`Pdf.contents_entry` lowers once into an ordinary rich paragraph with two internal
links and one real logical separator. A sparse normalized arena records each
entry's block, reference identity, indentation, gap and leader choice. The title
cannot contain another reference or link; the page field is the entry's final
reference. No semantics are recovered from geometry.

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

Exact allocation and deterministic work observations under the pinned dev
compiler are recorded in `tests/spec.json`; existing reference snapshots are
retained as regressions. The new `contents_rows` and `leader_dots` counters make
entry and decoration scale visible alongside existing item, row, mapping and
reference-fit work counters.

Initial native arm64mac observations on `nightly-2026-10-27-de79a0f`, dev
optimization, Zig 0.16.0 ReleaseFast host:

| Entries | Exact allocations | Allocated bytes | Measured items | Wrapped item visits | Contents rows | Dots |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 1,204 | 3,399,297 | 317 | 331 | 2 | 125 |
| 80 | 10,092 | 34,971,089 | 8,657 | 8,983 | 80 | 6,322 |
| 1 tall | 1,845 | 21,919,647 | 11,916 | 12,494 | 1 | 0 |

The scale pair has different title lengths and leader intervals; its explicit
item/dot counts describe the work more precisely than entry count alone. Wrap
visits remain below twice the input items, the terminal-row count is exactly
the entry count, and the many-dot case pays for its bounded decoration arena.
The tall entry retains one semantic title link across three contents pages;
its reference occurs once on the last title line. All eleven atomic negatives
use 1,159 allocations and 178,597 allocated bytes.

All six pre-existing destination-reference cases retain exact allocation/work
values and byte-identical PDFs under the same build. The empty sparse metadata
and no-leader branch add no allocations to those cases. New x64musl expectations
use the native exact-event/work values and await the normal Linux CI replay;
these native observations are not a claim that cross-target requested bytes
were measured locally.
