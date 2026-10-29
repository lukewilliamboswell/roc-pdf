# rc4 existing-fixture metric migration review

This is a causal review of native candidate measurements before existing
baselines are accepted. The first complete diagnostic collection ran 425 cases
under Roc `nightly-2026-10-28-bad769b`, dev backend, arm64mac, Zig 0.16.0.
It collected 422 results, including 251 changed metric vectors, and three
runtime fixture failures: mixed/code-face rich inline probes and source-block
atomic negatives. Those failures require corrected fixtures or diagnostics and
new measurements. Linux measurements, final source corrections, strict full
suite checks and any subsequent baseline acceptance are owned by the integration
record. The numbers below do not claim those checks have completed.

The diagnostic JSON and summary are ignored local artifacts at
`.roc-pdf-tmp/rc4-diagnostic-native-results.json` and
`.roc-pdf-tmp/rc4-metric-summary.txt`. The retained old expectations are in
`tests/spec.json` at the pre-migration checkpoint; final accepted expectations
must preserve the reviewed causes here.

## Metadata costs isolated from typography

These controls retain their existing font programs and algorithmic work.

| Native control | Allocations, old → candidate | Allocated bytes, old → candidate |
| --- | ---: | ---: |
| Caller-font registration | 119 → 119 | 565,658 → 565,674 |
| Sanitized TrueType subset | 151 → 152 | 803,494 → 803,534 |
| Shared font subset, 100 placements | 1,196 → 1,197 | 2,851,512 → 2,851,584 |
| Shared font subset, 1,000 placements | 6,803 → 6,804 | 13,473,881 → 13,473,953 |
| Equivalent authored fonts, 8 entries | 933 → 941 | 2,383,627 → 2,384,203 |
| Equivalent authored fonts, 64 entries | 4,104 → 4,168 | 7,463,523 → 7,468,131 |

Registration adds 16 bytes of inline `StyleFacts` storage with no allocation
event. The direct subset control adds one allocation and 40 bytes: the
source-derived 32-byte `post` header plus its eight-byte Roc reference count.
Previously that header was constant. It does not invoke
`KernelPdfFont.source_descriptor`, so attributing this allocation solely to a
descriptor record is disproved by the control. The constant-header/compiler
evaluation explanation follows the source change; no new per-glyph allocation
is introduced.

Shared font-leaf controls add the same one header allocation and 72 bytes at
both scales. The additional 32 bytes are expanded inline inspection storage.
Equivalent authored-font controls build each authored subset before canonical
deduplication: their extra allocations grow 8 → 64 and bytes 576 → 4,608,
exactly per prepared authored font, while canonical bundles remain one.
Distinct-font controls add 16 → 128 allocations at 8 → 64 entries, with
unchanged planning, hashing, mapping and collision-work vectors.

The shared-font recipe remains 5,747 bytes and retained identity remains 5,796
bytes at both 100 and 1,000 placements. Its font program remains 5,576 bytes,
one bundle and two graph hashes. Recipe schema 2 changes canonical identity
but keeps the same eight-byte raw-angle field width. It introduces no recipe
growth or additional hash traversal.

The ordered selection pair, 1,000 → 10,000 clusters, retains every selection
work count and the same allocation counts (156 → 161). Both sizes add just
48 allocated bytes. The corresponding cached public multiface pair adds 96
bytes at both sizes, keeping 312 → 339 allocations and all work unchanged:
one unique/planned source, three metric reads, one line template, and
999 → 9,999 cache hits. Metadata storage therefore remains independent of
cluster/placement count when inspection facts are shared.

## New programs and demand-driven registration

The legacy regression face is 166,300 bytes with 1,376 glyphs. Default Inter
Regular is 411,640 bytes with 2,937 glyphs; Inter Bold is 420,428 bytes with
2,937 glyphs. Default code adds genuine Fira Code programs, and semantic
strong/emphasis can demand separate genuine static faces. These are deliberate
new source inspections and subsets, not copied input buffers or fallback.

The plain public facade grows from 468 allocations / 1,992,310 bytes to
553 / 2,559,865 bytes. Its PDF changes 10,853 → 10,842 bytes. A title/figure
facade grows 615 / 2,383,880 to 865 / 4,243,528 and its PDF grows
11,678 → 16,295 bytes, because a genuine bold title becomes a separate font
resource. Additional selected faces each carry their own seven-object Type 0
bundle; the rich-flow callout controls consequently gain seven objects at both
small and large sizes.

The resolver marks a fixed ten-face demand set, validates caller handles
against the original registry, registers demanded packaged faces once in
canonical order, and compacts selected candidates. Inline flags propagate
through preorder parents once; dense face indexes avoid source-by-face scans.
The new 10/100-section control confirms five inspections and 1,964,376
inspected bytes at both sizes, inline visits 300 → 3,000, source visits
30 → 300 and zero input-copy bytes. Allocations grow 2,066 → 5,909 and
allocated bytes 10,787,402 → 24,611,441 for tenfold input growth. This is
bounded inspection plus linear document work, not ten-font eager parsing.

Caller-registry retention remains explicit. The shared two-output control
retains 7,816 original bytes; the deliberately unique control retains 15,632
bytes and makes its authored 7,816-byte caller copy. Both retain zero registry
input-copy bytes, the same registration/inspection work, and the same selected
source-byte counts after output. Their metric increases are respectively
50 allocations / 6,202 bytes and 50 / 6,218 bytes. Their 29-allocation
shared/unique difference is preserved.

## Large rejection-case ratios

Contents-entry negatives increase from 1,159 allocations / 178,597 bytes to
2,602 / 11,286,200 bytes (about 63.2 times allocated bytes). All eleven
rejections are retained. Each rejected document also authors a level-one
destination heading, demanding Inter Regular and Bold before the semantic
contents validation. Eleven calls plus the regular-only carrier therefore
demand **23 inspections of 9,564,388 aggregate input bytes**. No single
document inspects all packaged faces.

Figure negatives increase from 1,495 / 2,104,811 to 2,793 / 11,010,001,
retaining fourteen rejections. Fourteen regular-body calls and the two-face
title carrier demand **16 inspections of 6,595,028 input bytes**. These
fixtures measure repeated independent preparations, so the cost includes each
call's demanded validation; it does not demonstrate repeated parsing inside
one completed preparation.

The old facade selected a statically known built-in inspection before
normalization. The new demanded slot depends on runtime authoring. Loss of
compiler constant evaluation of the old inspection is an inference supported
by that source difference and the exceptionally small old rejection baseline;
the raw allocation totals alone do not identify every optimized call. The
larger programs and additional style demands are separately observable facts.
It would be inaccurate to explain the 63-fold ratio solely as a larger font.

The ordering itself did not move semantic validation later: both versions
selected fonts before the semantic pipeline. Basic contents errors could be
rejected before inspection if a future stage-contract refactor constructs and
reuses semantic facts before resolving fonts. A second facade semantic
precheck would duplicate validation passes or rules and charge every valid
document for redundant work. This integration preserves the existing ordering;
it does not use an ad hoc duplicate check to hide the measured cost.

## Existing scale pairs

These native candidates show no super-linear migration in allocated bytes.
The unchanged work counters are stronger evidence than percentage changes
dominated by fixed inspection setup. Values below are allocated bytes at the
small and large sizes.

| Pair | Old small → large | Candidate small → large |
| --- | ---: | ---: |
| Semantic sections, 10 → 100 | 3,628,249 → 18,894,803 | 5,572,256 → 20,838,467 |
| Rich paragraphs, 10 → 100 | 8,150,210 → 62,773,686 | 14,488,036 → 69,608,293 |
| Shared-source faces, 10 → 50 | 7,449,021 → 21,826,847 | 7,454,994 → 21,842,822 |
| Scaled code, 10 → 50 | 14,020,059 → 34,999,700 | 17,532,198 → 38,621,276 |
| Table invoice, 50 → 500 | 17,729,262 → 130,121,056 | 19,704,436 → 132,977,294 |
| Page-template letter, 6 → 200 | 13,150,852 → 239,462,317 | 15,197,397 → 242,584,147 |
| Contents entries, 2 → 80 | 3,399,297 → 34,971,089 | 5,293,493 → 37,025,618 |
| Rich measured callouts, 10 → 50 | 13,330,733 → 52,510,047 | 32,308,691 → 124,583,497 |

Rich measured callouts deliberately call `Pdf.measure_custom_content` once
per callout, then prepare/report/emit the complete document. The demanded
source inspections recur for each independent measurement call; its 5-fold
input increase grows candidate allocated bytes 3.856-fold, compared with the
old 3.939-fold. Report coverage changes 31 → 61 and 151 → 301 because the
selected genuine body, bold and code faces produce separate coverage facts.
These are explicit per-style report entries, not an unbounded traversal.

The first collection's code-hold geometry changes by one line at both scales
(38 → 39 and 290 → 291), with runs/fragments 56 → 53 and 470 → 431.
Those changes follow exact new face metrics; the zero-break-inside-code
assertion remains. Subsequent rich-inline work-probe corrections must be
remeasured rather than accepting these first-collection vectors unchanged.

## Fixture evidence corrections

The custom-block fixture previously emitted the new public fonts but measured
its line/page counters with the legacy regression face. It now resolves the
same family/style choices and feeds those typed facts through existing
semantic, shaping, line-layout and scoped-pagination stages locally in the
fixture. Only its consumed line/page counters are returned. Final report facts
independently retain fragments, outcomes and placements.

Its probe stops before text materialization and intent-dependent paint/PDF
lowering; the former legacy TextReady measurement boundary is deliberately
replaced with selected-font pagination. This changes allocation counts for
fixture setup and needs fresh native/Linux measurements. No package API,
production ordering, emitted PDF behavior, baseline or snapshot is changed by
that correction. The separate rich-inline correction similarly needs full
affected-family measurements under its actual selected fonts and paint-neutral
probe boundary.

The corrected custom-block probe passed all seven focused native case checks
through `scripts/test.py --quick --compare-baselines`, including each case's
independent PDF/A-4, structure and selectable-text validators. The command
exited with the expected unaccepted baseline-difference report; it did not
rewrite expectations or snapshots. The local report is
`.roc-pdf-tmp/custom-block-selected-font-metrics.json`.

| Corrected native case | Allocations | Allocated bytes |
| --- | ---: | ---: |
| Report | 16,994 | 31,866,999 |
| Defaults | 1,494 | 5,836,442 |
| Callouts, 10 | 5,799 | 13,342,521 |
| Callouts, 100 | 27,923 | 55,880,891 |
| Rich callouts, 10 | 9,432 | 33,023,236 |
| Rich callouts, 50 | 36,557 | 123,693,426 |
| Atomic negatives | 7,311 | 17,059,598 |

The corrected callout pair retains 51 → 501 lines and 2 → 19 pages; the
rich pair retains 61 → 301 lines and 2 → 10 pages. Allocated-byte growth
is 4.188-fold for tenfold ordinary callouts and 3.746-fold for fivefold rich
callouts. Public PDF bytes and report facts agree with the first collection;
only the additional work probe's measured setup and stage boundary changed.
Final Linux comparison and strict integrated acceptance remain pending.
