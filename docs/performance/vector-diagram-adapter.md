# Prepared vector diagram adapter

The adapter is an example over the closed public `Scene.Drawing`/`Pdf.figure`
seam, not a new SVG feature or production dependency. Mermaid/browser work is
explicit authoring-time preparation. Its pin and bounded accepted input profile
are documented in `examples/vector-diagrams/README.md`.

The generated drawing consumes and reassigns one uniquely owned accumulator for
every path and label. Each path builder is finished once; fixed-point source
geometry is owned by that command. There are no closures, copied suffixes,
rollback scenes or repeated measurements. Each of N figures constructs its own
18-command drawing (white viewport, 12 paths, five labels). The normal facade
interns the five label sources and selected font, shapes labels through the
existing artifact path, and preserves their explicit figure placement. Source
Unicode is never recovered from geometry. Figure and caption semantics use the
existing machinery unchanged.

The preparation tool has explicit input, node, depth and paint-order work
budgets. Browser CSS resolution is preparation input, not a later Roc stage's
semantic inference. Transforms and marker geometry are resolved before emission;
unsupported paint, text or external inputs reject. Native preparation output
uses 0.001 pt units, at most 0.000501 pt error per emitted coordinate (rounding plus bounded browser-number arithmetic). Browser
font metrics place each complete label's anchor; Roc shapes the exact source
with the same registered bytes and independently checks its bounds.

The scale cases run from allocation reset through font registration,
construction, public preparation report and byte emission. Work counts are
figures, authored commands, label placements, final report pages/fragments and
output bytes. They describe actual accepted inputs/output facts; no private
compiler probe or timing target is introduced.

| Figures | Allocations | Allocated bytes | Commands | Labels | Pages | Fragments | PDF bytes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 4,733 | 5,449,647 | 18 | 5 | 1 | 2 | 12,068 |
| 10 | 13,516 | 9,591,741 | 180 | 50 | 3 | 20 | 15,140 |
| 50 | 52,470 | 33,080,663 | 900 | 250 | 13 | 100 | 29,586 |

These are initial arm64mac baselines under `.roc-version`'s pinned dev build;
no existing allocation, work or PDF baseline changes. For 5× the diagrams,
allocations grow 3.88× and allocated bytes 3.45×, consistent with linear retained
scene/text/structure work plus fixed font/package costs. Each case retains the
10% allocated-byte ceiling. The final strict Linux run verifies the registered
target expectations and the same immutable PDF bytes; complete closure evidence
is recorded in [manual composition](manual-composition.md#final-integration-closure).

A final integration replay through `scripts/test.py --compare-baselines`, using
the registered canonical JSON cases, retains all three original allocation
counts, complete work vectors and exact PDF snapshots. Observed requested bytes
are 5,449,655 / 9,591,821 / 33,081,063: eight bytes per figure above the initial
observations, inside the unchanged byte ceilings. The default figure-frame
selection does not imply a net allocation-target reduction relative to this
slice's earlier isolated baseline; no vector allocation or byte target changes.

`check_vector_diagrams.py` checks original emitted bytes, exact Unicode labels,
Alt/caption/artifact ownership, cubic/arrowhead paths, input/font/tool hashes and
source Chrome versus independent PDFBox rendering. Visual comparison allows one
pixel for antialiasing, bounds unmatched dark pixels, and compares integrated
ink within 10%; a one-pixel stroke straddles pixel centers differently in the two
engines, so thresholded dark-pixel counts alone are not a stable measure.
