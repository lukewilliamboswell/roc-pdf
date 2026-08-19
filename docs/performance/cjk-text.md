# text-layout CJK searchable-text slice

## Scope

This closes one text-layout matrix row: one advanced horizontal Han run for U+4E2D
(`中`). It carries exact source byte/scalar ranges, `Hani`, `zh-Hans`, one
validated caller-style glyph, one one-to-one cluster, and positioned advance.
PDF lowering consumes those facts without inferring Unicode from glyph ID.

This is not facade CJK support, automatic shaping, line breaking, vertical
writing, fallback, or a broader multilingual claim. The font is test-only.

## Provenance and regeneration

`tests/assets/NotoSansSC-CJK-Fixture.ttf` is a 2,104-byte static
TrueType-flavoured OFL-1.1 fixture. It derives from Google Fonts Noto Sans SC
at immutable revision `2894aab31764f10f29c421bdfd2340d3b382d384`:

```text
https://raw.githubusercontent.com/google/fonts/2894aab31764f10f29c421bdfd2340d3b382d384/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf
source SHA-256: a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da
fixture SHA-256: 1f62194e8a3890019056cefaccc08bdf0234d8eecbba7581c5aaa959ade3e62f
```

`scripts/build_cjk_font_fixture.py` verifies the source digest, freezes
`wght=400`, subsets U+4E2D with fontTools 4.46.0, and adds empty valid `cvt `
and `fpgm` tables required by the current bounded subsetter. They have no glyph
or presentation data. The fixture has `glyf`/`loca`, no `fvar`, glyph ID 4.

## Evidence

The positive is a 3,957-byte tagged Type 0/CIDFontType2 PDF with exact
`/W [0 [1000 1000]]`, `ToUnicode <0001> <4E2D>`, and a 940-byte sanitized
TrueType subset, SHA-256
`e63604452a131dbaf60dd6baf21017b1ac63e13199c5bd5846dd77ecb97e2175`.
The structural checker reconstructs the CID mapping and verifies resource
closure; PDFBox extracts exactly `中\n`; qpdf accepts the original bytes.

The atomic negative changes only the three-byte source range to two bytes.
`KernelShape.validate_advanced` rejects it as `AdvancedClusterInvalid(SourceRange)`
before scene or object planning; the 667-byte blank carrier is test evidence,
not a fallback PDF.

At 72 dpi, PDFBox reports bounds `(73, 132, 81, 142)`, 47 changed pixels, 20
dark pixels, and 6,866 ink units. PDFium reports `(72, 132, 82, 142)`, 77, 32,
and 7,649; geometry agrees within two pixels.

The dev measurement begins before fixture main. Positive records one each of
source/run/cluster/glyph/glyph-index/scalar/mapping, 109 content bytes, 20
objects, 3,957 output bytes, and 144 allocations. Negative: 46 allocations,
`[1, 667]` work. The source is retained once: no lookup, per-glyph copy, or
substitution. text-layout remains open.
