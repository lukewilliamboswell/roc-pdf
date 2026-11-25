# text-layout advanced supplementary-plane text slice

This slice closes the supplementary-plane row of the text-layout advanced shaped-run
matrix. It uses U+1F12F (`🄯`) from the complete Inter 4.1 source retained under
`vendor/fonts/` only as a test/caller asset. The built-in facade font remains
the small Latin-oriented `RocPdfSans-Regular.ttf`; this fixture neither expands
its coverage nor makes the full Inter source a core production dependency.

The advanced input supplies one exact source scalar and its four-byte UTF-8
range, one validated nonzero glyph selected from the inspected caller asset,
and one `OneToOne` cluster. The source relationship remains an occurrence fact;
the PDF stage consumes it to write the direct `ToUnicode` row
`<0001> <D83CDD2F>`. This is canonical UTF-16BE surrogate-pair output for
U+1F12F, not a glyph-ID inference or a serializer-created fallback.

The positive fixture validates the full source font under explicit 500,000-byte,
5,000-glyph, 10,000-cmap, and 32-table bounds, performs deterministic planning
and subsetting, then emits a tagged 20-object Type 0/CIDFontType2 PDF. The
structural checker proves the identity CMap, exact inspected width sequence,
tagged page ownership, calibrated gray paint, exact surrogate-pair mapping,
and the 5,732-byte sanitized TrueType subset with SHA-256
`b3da4f6fc464d0561dd2d747649fbbe72529db8ec77443bfd68a6a67274b4317`.
PDFBox 3.0.8 independently extracts the exact UTF-8 source plus newline.

The atomic negative truncates the advanced cluster's UTF-8 range from four
bytes to three while retaining its scalar range. `KernelShape.validate_advanced`
rejects it as `AdvancedClusterInvalid(SourceRange)` before a scene, font plan,
or PDF plan is produced. Its only emitted bytes are the independent 667-byte
blank evidence carrier.

## Dev-backend performance evidence

The measurement resets before fixture main and uses the pinned dev backend on
the local x64musl target. The 411,640-byte source allocation is retained once
through deterministic subset emission; there is one run, cluster, glyph,
glyph-index visit, source scalar, mapping, 109-byte content stream, 20 objects,
and 8,723 emitted bytes. The positive case records 144 Roc allocations; the
atomic negative records 46. These are reviewed fixture baselines, not a claim
of cross-platform allocation equality.

At 72 dpi, PDFBox 3.0.8 measures `(72, 133, 81, 142)`, 65 changed pixels, 30
dark pixels, and 7,884 grayscale-ink units; PDFium Chromium 7988 measures the
same bounds, 77, 30, and 8,280. The two engines retain separate raster facts
while their geometry agrees exactly. Run the focused checks with:

```sh
./scripts/test.py --case 'text-layout supplementary-plane searchable text' --case 'text-layout supplementary-plane text atomic negative'
python3 scripts/check_supplementary_text.py --pdfbox-extraction
python3 scripts/check_text_renderers.py --supplementary --pdfium-renderer /home/lbw/.local/bin/pdfium-render
```

This closes one matrix row only. Ligature output, real right-to-left
logical/visual output, CJK subsets, discretionary and soft hyphens, generated
labels, case transformations, and the remaining layout/cache/retention evidence
still block text-layout closure. The public and caller-facade baseline promotion
completed concurrently on the integration branch and is not an outstanding
blocker for this slice.
