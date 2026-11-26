# text-layout Unicode analysis slice

Text analysis uses `roc-lang/unicode` 4.4.0 at commit
`37ac0b869ad4bbb8427ebe80499b2b95e4ade93a`. The archive and its digest are
recorded in [dependency provenance](../../../vendor/README.md).
The [upstream data manifest](https://github.com/roc-lang/unicode/blob/37ac0b869ad4bbb8427ebe80499b2b95e4ade93a/vendor/unicode/manifest.json)
(SHA-256 `ba7b69f46268f546b2d9eb3012cc5c9d42f488de2c6db7ee1d07df9c0d296935`)
identifies Unicode 18.0.0, UAX #9 revision 52, UAX #14 revision 57, UAX #24
revision 41, and UAX #29 revision 49. Script itemization retains the separately
versioned `ConservativeScxV1` policy. The bidi and case adapters pass explicit
options and retain their existing limits and source-coordinate contracts.
`.roc-version` selects the product compiler independently.

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

## Pinned dev-backend evidence

The focused fixture resets the Roc allocation counter before source
construction. It constructs repetitions of `a é漢 `, performs the full
analysis, releases it into scalar work counters, and emits the unchanged structural-kernel
blank PDF solely to use the common scenario protocol. Counts exclude Python
and validators.

| Target | Backend | Repetitions | UTF-8 bytes | Scalars | Graphemes | Line boundaries | Script runs | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arm64mac | dev | 1,000 | 9,000 | 6,000 | 5,000 | 6,001 | 2,999 | 177 |
| arm64mac | dev | 10,000 | 90,000 | 60,000 | 50,000 | 60,001 | 29,999 | 192 |
| x64musl | dev | 1,000 | 9,000 | 6,000 | 5,000 | 6,001 | 2,999 | 177 |
| x64musl | dev | 10,000 | 90,000 | 60,000 | 50,000 | 60,001 | 29,999 | 192 |

The exact work counters scale with source structure. The 10x input adds 15
allocations from deterministic list-capacity growth, not one allocation per
scalar, grapheme, boundary, or script run. The x64musl rows are accepted as the
same pinned-compiler expectation and remain to be executed by the configured
cross-target job. This reviewed record replaces the obsolete speed-backend
table with the current dev-only allocation policy; it does not accept any
implementation or work-counter change.

This evidence establishes the Unicode analysis substrate only. It does not
claim font parsing, shaping, layout, PDF text emission, or text-layout closure.
