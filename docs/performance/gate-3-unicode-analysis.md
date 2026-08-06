# Gate 3 Unicode analysis slice

This slice pins the temporary local `roc-lang/unicode` dependency at commit
`f9b23ae87b1655d7c2b1c6fe049ccbf02f6e2fe5`. Both repositories use Roc
`nightly-2026-August-05-24f0b47`. The dependency reports Unicode 17.0.0,
UAX #14 revision 55, UAX #29 revision 47, and the independently versioned
`ConservativeScxV1` script-itemization policy. The relative source dependency
in `package/main.roc` and `package/evidence.roc` is temporary; replacing it
with a release requires a reviewed archive revision and digest without changing
the pinned Unicode semantics implicitly.

## Representation and ownership

- One source `Str` owns UTF-8 once. Retained analysis contains only scalar
  coordinates, byte coordinates, line decisions, and static script aliases;
  no substring or seamless slice retains the source.
- Grapheme analysis temporarily retains one flat `ByteRange` buffer, then
  consumes a scalar walk to create the final fixed-shape range buffer. This
  duplicates descriptors during the phase, not text payload bytes.
- Line boundaries and script runs are separate flat buffers because they are
  distinct earlier-stage facts consumed by line selection and font planning.
- Every output buffer is checked against a dimension-specific limit before
  append. Failure is transactional and exposes no partial analysis.
- The source and temporary grapheme buffer are released after analysis unless
  the caller deliberately retains an earlier immutable value.

The complete-string analysis performs four bounded linear walks: grapheme
segmentation, scalar-coordinate attachment, exhaustive line-boundary analysis,
and shaping-oriented script itemization. Every scalar is visited a constant
number of times. There is no paragraph-candidate rescan, comparison sort,
recursive node, per-scalar substring, or stored `Iter`.

## Pinned optimized evidence

The focused fixture resets the Roc allocation counter before source
construction. It constructs repetitions of `a é漢 `, performs the full
analysis, releases it into scalar work counters, and emits the unchanged Gate 1
blank PDF solely to use the common scenario protocol. Counts exclude Python
and validators.

| Target | Optimization | Repetitions | UTF-8 bytes | Scalars | Graphemes | Line boundaries | Script runs | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 1,000 | 9,000 | 6,000 | 5,000 | 6,001 | 2,999 | 176 |
| arm64mac | speed | 10,000 | 90,000 | 60,000 | 50,000 | 60,001 | 29,999 | 191 |
| x64musl | speed | 1,000 | 9,000 | 6,000 | 5,000 | 6,001 | 2,999 | 176 |
| x64musl | speed | 10,000 | 90,000 | 60,000 | 50,000 | 60,001 | 29,999 | 191 |

The exact work counters scale with source structure. The 10x input adds 15
allocations from deterministic list-capacity growth, not one allocation per
scalar, grapheme, boundary, or script run. The x64musl rows are accepted as the
same pinned-compiler expectation and remain to be executed by the configured
cross-target job.

This evidence establishes the Unicode analysis substrate only. It does not
claim font parsing, shaping, layout, PDF text emission, or Gate 3 closure.
