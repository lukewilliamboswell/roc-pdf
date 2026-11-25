# text-layout Type 0 PDF font object slice

This slice lowers earlier inspected, planned, and subset font facts into a
sealed PDF object graph. It assigns seven consecutive indirect objects for the
embedded FlateDecode `FontFile2` stream, the FlateDecode `ToUnicode` CMap,
font descriptor, CIDFontType2 descendant, and Type 0 parent. Stream length
objects are assigned by the shared object kernel and validated by sealing.

The lowering consumes the dense subset plan directly: CID equals the subset
glyph ID, which is validated for every retained glyph so the descendant can
declare `/CIDToGIDMap /Identity` (ISO 32000-2 Table 115), and `/W` contains
one checked 1,000-unit width for every CID. Descriptor and width metrics are
scaled once from the inspected units-per-em. The subset prefix and validated
PostScript name form the PDF BaseFont name; caller-controlled whitespace,
delimiters, non-ASCII bytes, `#`, and the subset separator are rejected.

Every content CID must have exactly one ordered Unicode mapping before any
object is added. Empty, missing, unexpected, duplicate, surrogate, and
out-of-range mappings are typed errors. A destination over 512 UTF-16BE bytes
is rejected before CMap construction. The CMap writes at most 100 entries per
block and emits supplementary scalars as UTF-16 surrogate pairs. Its exact
serialized byte count is checked against the configured limit before allocation.
Context-dependent mappings and `ActualText` remain facts supplied by later text
lowering; this module does not infer them from glyph identity.

## Validation

The focused fixture covers repeated glyph use, ToUnicode entries, object
identity, stream closure and atomic rejection of incomplete Unicode mappings.
It inspects BMP and supplementary destinations of exactly 512 decoded bytes
in a sealed stream and rejects 514- and 516-byte destinations. The advanced
text fixture also rejects a shaped cluster that would assign an oversized
mapping to a CID. Integrated fixtures cover reader extraction and page output.

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
