# Gate 2 independent renderer evidence

## Fixture and oracle

The retained Gate 2 PDF is rendered at 720 dpi by PDFium Chromium 7988 and
Apache PDFBox 3.0.8. PDFium is loaded from the checksum-pinned
`pdfium-linux-x64.tgz` release artifact; PDFBox uses the vendored, provenance-
tracked application JAR. PDFBox is the required non-PDFium renderer.

The expected 100 by 100 RGB raster is constructed directly from the typed
fixture, not from either renderer and not from another PDF generator. One PDF
point is ten pixels at this resolution. The expectation starts as white and
then applies these regions in paint order:

- the one-point gray path fills pixels `[0,10) x [90,100)` with RGB 128;
- the translated two-by-one-point image occupies `[60,80) x [10,20)`;
- its four source samples produce 10-by-5-pixel cells with values 0, 64, 128,
  and 255 in source row order.

All geometry lands on integer pixel boundaries, there are no curves at the
region edges, and every color is grayscale. The declared tolerance is
therefore zero pixels for geometry and zero component values for color. Both
renderers must equal the independent 30,000-byte expectation and each other.

## Pinning and failure boundary

The PDFium Chromium 7988 Linux archive is downloaded from the immutable
`chromium/7988` release and checked against SHA-256
`7358c15e26a746cd67854887ea11b3b807c436056788eee9294fb972b8f8e0be`.
CI compiles the small `pdfium_render.c` adapter with warnings as errors against
that archive. The PDFBox adapter is likewise compiled with all Java lint
warnings as errors. Both adapters emit the same simple binary PPM boundary,
which `check_gate2_renderers.py` parses without image-library dependencies.

The checker self-test changes one channel of one white pixel and proves that
the zero-tolerance comparison rejects it. Renderer setup and buffers are test-
only and are outside Roc allocation measurements and production dependencies.
