# Gate 3 Type 0 PDF font object slice

This slice lowers earlier inspected, planned, and subset font facts into a
sealed PDF object graph. It assigns nine consecutive indirect objects for the
embedded `FontFile2` stream, explicit `CIDToGIDMap` stream, `ToUnicode` CMap,
font descriptor, CIDFontType2 descendant, and Type 0 parent. Stream length
objects are assigned by the shared object kernel and validated by sealing.

The lowering consumes the dense subset plan directly: CID equals the subset
glyph ID, the explicit CID map records every retained glyph, and `/W` contains
one checked 1,000-unit width for every CID. Descriptor and width metrics are
scaled once from the inspected units-per-em. The subset prefix and validated
PostScript name form the PDF BaseFont name; caller-controlled whitespace,
delimiters, non-ASCII bytes, `#`, and the subset separator are rejected.

Every content CID must have exactly one ordered Unicode mapping before any
object is added. Empty, missing, unexpected, duplicate, surrogate, and
out-of-range mappings are typed errors. The CMap writes at most 100 `bfchar`
entries per block and emits supplementary scalars as UTF-16 surrogate pairs.
Its exact byte count is checked against the configured limit before allocation.
Context-dependent mappings and `ActualText` remain facts supplied by later text
lowering; this module does not infer them from glyph identity.

## Direct and optimized evidence

The focused fixture subsets the built-in face for `A`, `é`, and repeated `A`.
Direct inspection proves the exact ten-byte CID map, the `U+0041` and `U+00E9`
ToUnicode entries, object identities 1 through 9, three streams, three payloads,
and successful closure sealing. A negative twin omits CID 3's mapping and proves
atomic `IncompleteUnicodeMapping` rejection.

| Target | Optimization | Subset bytes | CID map bytes | ToUnicode bytes | Objects/streams | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 5,864 | 10 | 352 | 9 / 3 | 271 |
| x64musl | speed | 5,864 | 10 | 352 | 9 / 3 | 271 |

The x64musl row is the accepted same-compiler expectation exercised by the
configured cross-target job. The fixture returns the common blank PDF only as
the scenario-protocol carrier; these object facts are inspected before that
independent carrier is emitted. Therefore this slice does not claim visible PDF
text, extraction through a reader, page-resource integration, `ActualText`, the
public font/theme API, layout, or Gate 3 closure.
