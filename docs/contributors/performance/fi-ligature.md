# text-layout parsed `fi` ligature output

This closes the ligature row of the text-layout extraction/rendering matrix only.
It uses a test-only 3,424-byte static TrueType fixture derived from IBM Plex
Serif 6.4.0 (`IBM/plex` tag `v6.4.0`), not a packaged production face. The
immutable source URL is
`https://github.com/IBM/plex/raw/v6.4.0/IBM-Plex-Serif/fonts/complete/ttf/IBMPlexSerif-Regular.ttf`;
its source SHA-256 is
`3764f5ddda8c687a765d0105e2a31cd311fca244239b878cb59fedb069a14dbb`.
`scripts/build_ligature_font_fixture.py` pins fontTools 4.61.1, retains only
U+0066/U+0069 plus `liga`, renames the font, verifies the source digest, and
reproduces fixture SHA-256
`c5fc094129c765da42264142f8a78c4979d11338e294c028e870e97b766047ba`.

The fixture's selected `latn` default language system contains a direct GSUB
Type-4 `liga` lookup proving `f` glyph 4 plus `i` glyph 5 maps to glyph 6.
`KernelGsub` retains that exact fact, and
`KernelShape.validate_advanced_with_ligature_fact` consumes it alongside the
two-scalar source range, one-glyph `Ligature` cluster, substitution range, and
painted glyph. No stage infers a substitution from a glyph ID.

The tagged Type 0 output has one painted CID, canonical `<0001> <00660069>`
ToUnicode mapping, and required `/ActualText <FEFF00660069>`. The structural
checker verifies the embedded sanitized subset (2,144 bytes, SHA-256
`e99ef53b60c53e5252f0f4ffc0b30c6406766244dae663bf7b147020d326e07b`),
CID width 633, original bytes, and PDFBox extraction `fi\n`; qpdf accepts the
original bytes. The atomic negative changes only the retained fact's output to
the `i` glyph. It is rejected at advanced shaping before scene/object planning
and emits no feature PDF.

The dev measurement boundary is before fixture main. Positive work is
`[3424, 1, 1, 1, 1, 2, 1, 2, 1, 154, 20, 5210]` with 144 allocations;
the negative is `[1, 667]` with 46 allocations. The source fixture remains one
immutable inspection allocation; GSUB inspection scans bounded table ranges,
and the post-shaping pipeline retains only dense run/glyph facts and the one
sanitized subset. text-layout remains open for its other criteria.
