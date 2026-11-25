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
interns the five label sources and selected font, then shapes each label into
a separate content occurrence owned by the Figure. Page placement preserves
its authored geometry and the structure spine preserves its authored order.
The visible caption retains its own structure element.

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

The one- and fifty-figure cases select `AccessibleArchive` with a WTPDF
Accessibility declaration. The ten-figure case explicitly selects `Archive`.
`tests/spec.json` records the exact allocation, allocated-byte and work
baselines on both supported targets. Each consumer regenerates the same
committed PDFs. The figures add five label fragments each, alongside the
drawing and caption. The allocated-byte ceilings use the same 110% guard
as the rest of the pinned harness.

`check_vector_diagrams.py` checks original emitted bytes, exact Unicode labels,
Figure label order and ownership, alternative text, visible captions, cubic
and arrowhead paths, input/font/tool hashes, and source Chrome versus
independent PDFBox rendering. A targeted mutation exchanges two label
references while preserving their paint and Figure ownership. The checker
requires the authored order. Visual comparison allows one
pixel for antialiasing, bounds unmatched dark pixels, and compares integrated
ink within 10%; a one-pixel stroke straddles pixel centers differently in the two
engines, so thresholded dark-pixel counts alone are not a stable measure.

## Font validation

`Diagram.options` accepts explicit `Font.ValidationLimits`. The runnable
example and scale cases use the named default. A restrictive byte limit has
an atomic `expect` that checks the original `LimitExceeded` dimension,
attempted bytes and limit. Registration errors retain `Font.ResourceError`
through the adapter.
