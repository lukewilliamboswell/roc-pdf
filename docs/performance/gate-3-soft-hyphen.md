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

An external discretionary opportunity is a validated zero-width source
boundary. The advanced boundary now represents its selected visible U+002D as
`GeneratedDiscretionaryHyphen`, tied by dense transformation and owned
text-property IDs to `InsertedDiscretionaryHyphen`. The positive fixture is
logical `ab` with an explicit boundary between the scalars. Its direct CMap is
the visible `a-b`, while `/ActualText` is exactly `ab`; the former preserves a
complete CID mapping and the latter is authoritative logical extraction. This
is an out-of-band caller fact, not dictionary hyphenation: no language
heuristic, pattern set, or system resource is bundled or consulted.

The atomic negatives independently reject malformed and unselected external
opportunities. Each returns no feature PDF and emits only the common blank
evidence carrier.

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

For the external selected `ab` boundary, the visible `a-b` presentation has
these local original-byte 72-dpi facts:

| Renderer | Bounds | Changed pixels | Dark pixels | Grayscale ink |
| --- | --- | ---: | ---: | ---: |
| PDFBox 3.0.8 | `(72, 134, 90, 142)` | 82 | 36 | 9,433 |
| PDFium Chromium 7988 | `(71, 133, 90, 142)` | 98 | 37 | 10,094 |

Their geometry agrees within the declared two-pixel tolerance. PDFBox extracts
logical `ab` plus its reader newline; structural inspection separately proves
that the inserted U+002D CID remains present for direct presentation mapping.

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
typed external discretionary-selection boundary. It does not claim automatic
hyphenation, language patterns, line-break discovery, or Gate 3 closure.

The external positive whole-pipeline boundary is before evidence construction.
On the pinned local x64musl dev backend it allocates 1,040 times and emits
9,125 bytes. Its deterministic work is `[166300, 1, 1, 1, 2, 3, 205, 20,
9125]`: one retained built-in font payload, one caller-supplied opportunity and
selection, one ActualText run over two logical scalars, three CID mappings,
content bytes, objects, and output bytes. The malformed and unselected
external negatives each allocate 40 times and retain the common `[1, 667]`
blank-carrier work. These are local dev-backend records only; no speed-mode or
cross-platform allocation claim is made.
