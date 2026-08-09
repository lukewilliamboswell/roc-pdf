# Gate 3 selected soft-hyphen slice

This slice adds the private `KernelDiscretionaryHyphen` boundary between UAX
#14 opportunity facts and later presentation. An opportunity retains exact
scalar and UTF-8 coordinates into its immutable semantic source; selection is
a separate typed decision. Nothing mutates, slices, or reconstructs the source
text.

The positive fixture starts with logical `co` + U+00AD + `operate`. It selects
a visible hyphen only for that explicit U+00AD opportunity. The shaped glyph
for the visible hyphen carries `SelectedSoftHyphen`, which forces `/ActualText`
for the run. The direct `ToUnicode` CMap and `/ActualText` both retain U+00AD;
the visible glyph never silently replaces source Unicode with U+002D. PDFBox
3.0.8's pinned extraction API suppresses that soft hyphen and returns
`cooperate ` plus newline, while the structural oracle proves the retained
source fact directly.

An external hyphenation opportunity is represented as a validated zero-width
source boundary. It is deliberately rejected at selection-to-presentation: the
current advanced glyph boundary requires each painted glyph to own a nonempty
source range. This is not a fallback. A future generated-glyph boundary must
preserve the selected opportunity's identity and logical source range before it
can lower dictionary hyphenation. No dictionary, language heuristic, or system
resource is bundled or consulted.

The atomic negatives independently reject a malformed explicit-SHY range, an
unselected explicit opportunity asked for presentation, and a selected external
zero-width opportunity. Each returns no feature PDF and emits only the common
blank evidence carrier.

Structural inspection verifies the selected Type 0 subset's exact glyph
closure, widths, CMap rows (including U+00AD), canonical `ActualText`, balanced
marked content, and deterministic subset digest. qpdf accepts the original
bytes. At 72 dpi, local original-byte rendering evidence is:

| Renderer | Bounds | Changed pixels | Dark pixels | Grayscale ink |
| --- | --- | ---: | ---: | ---: |
| PDFBox 3.0.8 | `(72, 134, 131, 144)` | 271 | 118 | 32,548 |
| PDFium Chromium 7988 | `(72, 134, 132, 144)` | 352 | 121 | 35,014 |

The renderer bounds agree within the existing two-pixel geometry tolerance;
coverage remains renderer-specific.

## Dev-backend performance review

The positive whole-pipeline boundary is before evidence construction. On the
pinned local x64musl dev backend it allocates 1,122 times and emits 10,115
bytes. Its deterministic work is `[166300, 1, 1, 1, 10, 8, 419, 20, 10115]`:
the built-in font bytes, one opportunity, one selection, one ActualText run,
ten source scalars, eight unique CID mappings, content bytes, objects, and PDF
bytes. The larger bounded scalar/glyph arrays and one 6,868-byte subset are
the architectural cost of exercising the real ten-scalar source path; the
166,300-byte font input remains one payload.

The malformed negative allocates 40 times. After the independently developed
CJK evidence was integrated into the shared advanced-text evidence module, the
dev backend's dead-code/monomorphization layout changed only the other two
early carriers: unselected is 41 allocations and external selection is 40.
Their emitted bytes and deterministic work `[1, 667]` remain unchanged. They
stop before font inspection, shaping, scene planning, or PDF text lowering.
These integrated local dev-backend values were reviewed together; no speed-mode
measurement or cross-platform allocation claim is made.

This closes only the explicit soft-hyphen extraction row and establishes the
typed discretionary-selection blocker. It does not claim automatic
hyphenation, language patterns, generated zero-width glyph presentation, or
Gate 3 closure.
