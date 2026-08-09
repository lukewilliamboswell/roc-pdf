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
prepares one canonical `/Span` marked-content sequence around the affected run
and encodes a BOM-prefixed UTF-16BE hex string, including surrogate pairs for
valid supplementary scalars. Scene content lowering nests that span inside the
fragment MCID and transform, then adds validated calibrated paint and text
rendering mode. The ordinary one-to-one fixture takes the no-`ActualText` path.

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
`/ActualText <FEFF00660061>`, which restores `fa`. The fragment-owned scene
group, text ownership join, MCID, ParentTree entry, structure `/K` items,
calibrated Gray resource, and Type 0 font now form one tagged 20-object graph;
the legacy untagged carrier is no longer built.

The independent checker reconstructs both orders separately, validates the
balanced marked-content syntax, exact two-row CMap, exact caller-font widths,
5,956-byte sanitized subset and subset digest, and rejects atomic negative
twins for the logical value, marked-content balance, CMap, and page font.
PDFBox 3.0.8 independently extracts exact UTF-8 `fa\n`. PDFBox and PDFium
each pin their own 72-dpi ink metrics, while their geometry must agree within
the explicit bound tolerance. Pixel coverage and grayscale ink remain
renderer-specific because the two independent rasterizers antialias glyph edges
differently.

| Renderer | Bounds | Changed pixels | Dark pixels | Grayscale ink |
| --- | --- | ---: | ---: | ---: |
| PDFBox 3.0.8 | `(72, 133, 81, 142)` | 60 | 27 | 6,883 |
| PDFium Chromium 7988 | `(71, 133, 82, 142)` | 78 | 27 | 7,350 |

Roc evidence separately validates a two-glyph `ManyToMany` cluster through the
advanced shaping boundary. It also accepts an occurrence-owned semantic
override of seven scalars and rejects the same request at a six-scalar limit
before any PDF is returned.

## Pinned optimized evidence

| Target | Optimization | Glyphs/mappings | Subset bytes | Content bytes | PDF bytes | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 2 / 2 | 5,956 | 179 | 9,035 | 306 |
| x64musl | speed | 2 / 2 | 5,956 | 179 | 9,035 | 306 |

The exact work vector begins with 7,816 caller-font bytes, one run, two
clusters, two glyphs, and two glyph-index visits. It then records the same scene,
semantic, tagged, ownership, resource, and content traversals as the ordinary
tagged text fixture: two scene commands, one text placement, one fragment and
occurrence, one ownership range check, one calibrated color reference, and a
179-byte final content stream. The remaining counters record a three-entry font
plan, 5,956 subset bytes, two cached source scalars, one prepared run, zero
parallel placements, two text glyphs, one ActualText run, two ActualText
scalars, zero resolved mapping conflicts, two Unicode mappings, 103 prepared
text bytes, one font, nine font objects, twenty objects, 6,135 font/content
payload bytes, and 9,035 emitted bytes.

The whole fixture uses 306 Roc allocations, an increase of 132 over the earlier
protocol carrier. The increase is reviewed as the bounded semantic/source
arrays, scene and ownership arenas, tagged MCID/ParentTree/structure plans,
calibrated color and resource plans, prepared-run carrier, tagged content/page
objects, reserved font identities, and final sealed tagged structure. The
7,816-byte source and 5,956-byte subset remain single payloads rather than being
copied per placement.

This is a Gate 3 feature slice, not Gate 3 closure. The remaining evidence
matrix still includes combining marks, ligatures, supplementary-plane text,
right-to-left scripts, CJK subsets, discretionary and soft hyphens, generated
text and case transformations, plus public layout, pagination, paint,
ownership, reuse, and facade integration.
