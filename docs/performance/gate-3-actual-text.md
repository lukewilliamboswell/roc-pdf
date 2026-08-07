# Gate 3 reordered ActualText slice

This slice lowers advanced glyph/source relationships without reconstructing
logical text from paint order. The text plan requests `ActualText` for
right-to-left or transformed runs, reordered or contextual clusters, and any
cluster that references multiple painted glyphs. Logical Unicode comes only
from the exact semantic occurrence range or an explicit `ActualText` property
owned by that occurrence. Semantic-property IDs outside the occurrence's dense
range, wrong property kinds, and empty values fail atomically.

`ActualText` scalars have a distinct cumulative resource limit. Occurrence
ranges are checked before copying from the once-built source-scalar cache;
semantic overrides check the next scalar before appending it. PDF lowering
emits one canonical `/Span` marked-content sequence around the affected run and
encodes a BOM-prefixed UTF-16BE hex string, including surrogate pairs for valid
supplementary scalars. The ordinary one-to-one fixture takes the unchanged path
and retains its exact bytes and 187-allocation baseline.

Every painted CID still receives a deterministic `ToUnicode` entry. A repeated
CID with incompatible source mappings remains `UnicodeMappingConflict` when no
`ActualText` is present. Where explicit `ActualText` makes per-occurrence
logical extraction unambiguous, lowering retains the first per-CID mapping in
dense traversal order and records each resolved conflict. This preserves a
complete fallback CMap without pretending that a single font-level CID map can
carry occurrence-specific semantics.

## Independent output evidence

The tracked advanced fixture imports the 7,816-byte caller font as `List(U8)`.
Its semantic source is logical `fa`, while the validated advanced store paints
the glyphs in visual order `af` and points its two logical `Reordered` clusters
back to those glyph positions. The content stream therefore shows CIDs whose
direct `ToUnicode` reconstruction is `af`, surrounded by
`/ActualText <FEFF00660061>`, which restores `fa`.

The independent checker reconstructs both orders separately, validates the
balanced marked-content syntax, exact two-row CMap, exact caller-font widths,
5,956-byte sanitized subset and subset digest, and rejects atomic negative
twins for the logical value, marked-content balance, CMap, and page font.
PDFBox 3.0.8 independently extracts exact UTF-8 `fa\n`. PDFBox rendering pins
the 72-dpi ink bounds and CI compares the same file with PDFium Chromium 7988
under the existing explicit renderer tolerances.

Roc evidence separately validates a two-glyph `ManyToMany` cluster through the
advanced shaping boundary. It also accepts an occurrence-owned semantic
override of seven scalars and rejects the same request at a six-scalar limit
before any PDF is returned.

## Pinned optimized evidence

| Target | Optimization | Glyphs/mappings | Subset bytes | Content bytes | PDF bytes | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 2 / 2 | 5,956 | 119 | 8,137 | 174 |
| x64musl | speed | 2 / 2 | 5,956 | 119 | 8,137 | 174 |

The exact work vector records, in order: 7,816 caller-font bytes, one run, two
clusters, two glyphs, two glyph-index visits, three font-plan entries, 5,956
subset bytes, two cached source scalars, one ActualText run, two ActualText
scalars, zero resolved mapping conflicts, two Unicode mappings, 119 content
bytes, fourteen PDF objects, and 8,137 emitted bytes. The whole fixture uses
174 Roc allocations. Retaining the full font inspection in the fixture result
was measured at 181 allocations and rejected; the final phase result keeps only
the facts needed by later stages.

This is a Gate 3 feature slice, not Gate 3 closure. The remaining evidence
matrix still includes combining marks, ligatures, supplementary-plane text,
right-to-left scripts, CJK subsets, discretionary and soft hyphens, generated
text and case transformations, plus public layout, pagination, paint,
ownership, reuse, and facade integration.
