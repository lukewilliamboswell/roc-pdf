# text-layout UAX boundary-vector seam evidence

This project owns a compact regression seam for the Unicode facts consumed by
source normalization, grapheme-cluster font selection, and line layout. It
does not vendor or duplicate the upstream package's full conformance corpus.
That corpus belongs to `roc-lang/unicode`; this evidence protects the PDF
pipeline's exact UTF-8/scalar coordinate handoff against a dependency upgrade
or an accidental loss of a fact between stages.

The dependency is `roc-lang/unicode` 4.0.0 at reviewed source revision
`b689986172679aa9fbdcd7890e3031a48b1c582f`: Unicode 17.0.0, UAX #14 revision
55, and UAX #29 revision 47. The selected inputs are independently transcribed
from `GraphemeBreakTest-17.0.0.txt` (GB3 `CR × LF`; GB9c `0915 × 094D × 0915`)
and `LineBreakTest-17.0.0.txt` (`1B05 ÷ 1F1E6`; `2757 × 0020 ÷ 1F1E6`). The
test source itself is only 26 UTF-8 bytes and records no upstream corpus bytes.

The positive fixture asserts these exact source facts:

- CRLF is one grapheme at UTF-8 `[0, 2)` and scalar `[0, 2)`.
- the Indic conjunct is one grapheme at UTF-8 `[0, 9)` and scalar `[0, 3)`.
- the UAX #14 vectors retain every project boundary, including initial
  `Prohibited` and final `Mandatory` entries: AK/RI `[0, 3, 7]` and
  AI/SP/RI `[0, 3, 4, 8]`, with matching scalar coordinates and decisions.

The atomic-negative twin independently sets the grapheme limit below the CRLF
cluster count and the line-boundary limit below the AK/RI boundary count. Both
must reject at their first crossing with the stable bounded error; no partial
Unicode analysis is accepted. The fixture emits the standard blank structural
carrier only after proving the two errors, so the common harness can inspect
deterministic PDF bytes without treating it as successful text output.

## Dev-backend performance review

The allocation boundary is before fixture main and includes source creation,
four independent bounded Unicode analyses, the two negative probes where
applicable, and the blank structural carrier. It excludes Python and external
inspection. The representation owns UTF-8 once per vector and retains flat
ranges/boundaries only; it creates no substrings, glyphs, scenes, or PDF text.
All work is direct linear traversal inside the pinned Unicode package; the
project makes no `Iter` or cache choice in this seam.

| Scenario | Work | Exact dev allocations |
| --- | --- | ---: |
| Four UAX seam vectors | 26 bytes, 10 scalars, 7 graphemes, 14 boundaries, 4 script runs | 44 |
| Two atomic limit rejections | 2 rejections | 46 |

These are local pinned-dev baselines for both declared targets in
`tests/spec.json`; the present execution evidence is x64musl. The counts are
new fixture costs, not a rebaseline of any existing scenario. This slice does
not claim full Unicode conformance, bidi, shaping, layout completion, or Gate
3 closure.
