# Gate 3 visible searchable text slice

This slice joins the earlier Unicode analysis, bounded shaping, deterministic
font plan, sanitized subset, and Type 0 font-object stages into one real PDF 2.0
page. The page content selects the exact planned font resource and run size,
positions each glyph with checked layout arithmetic, and emits 16-bit CIDs. The
page resource dictionary references the Type 0 font produced from the same font
plan; later stages do not rediscover font identity from serialized operators.

The fixture now also enters text through the typed scene boundary. A fragment-
owned group contains one translation transform and one `DrawText` command. Scene
validation checks the dense run identity, calibrated fill-color identity,
opaque paint policy, page ownership, command ownership, and graphics depth
before text lowering starts. Fill-only paint cannot carry a stroke;
fill-and-stroke paint must carry a positive-width calibrated stroke. Non-opaque
text remains a typed error until the later ExtGState capability exists.

Logical Unicode remains owned by the semantic occurrence. Text lowering builds
one bounded scalar cache for the semantic sources, walks each placed run once,
and derives each CID mapping from the run's explicit cluster range. Every run
must be placed exactly once and every content CID must receive one mapping.
Conflicting mappings, missing retained glyphs, absent occurrences, invalid
ranges, and unplaced or duplicate runs are typed errors before a PDF structure
is returned.

This fixture exercises the simple no-`ActualText` path and remains byte-stable.
The subsequent
[reordered ActualText slice](gate-3-actual-text.md) expands the same lowering
boundary to reordered, context-dependent, multi-glyph, right-to-left, and
transformed runs, plus occurrence-owned semantic overrides. Unsupported or
missing evidence remains an error rather than an inferred mapping.

## Independent output evidence

The fixture renders and extracts `Café PDF` on one A4 page. It embeds a fresh
6,776-byte sanitized TrueType subset, an identity CID-to-GID map for eleven
planned entries, eight exact `ToUnicode` rows, one CIDFontType2 descendant, and
one Type 0 parent. The tracked PDF is 9,094 bytes and contains fourteen
non-xref objects; unlike the earlier Gate 3 protocol carriers, it is visibly
nonblank in ordinary readers.

The independent structural checker reconstructs the displayed string from the
content CIDs and `ToUnicode`, verifies the exact widths and subset digest, and
rejects same-length negative twins for a changed Unicode row, wrong page font,
wrong CID map, and wrong embedded-font length. PDFBox 3.0.8 must independently
extract the exact UTF-8 bytes `Café PDF\n`. PDFBox and PDFium also render at 72
dpi and must each match an independently pinned ink region within explicit
tolerances: two pixels per bound, 60 antialiased pixels, 40 dark pixels, and
6,000 grayscale-ink units. The same tolerances bound agreement between the two
engines.

## Pinned optimized evidence

| Target | Optimization | Glyphs/mappings | Subset bytes | Content bytes | PDF bytes | Exact allocations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| arm64mac | speed | 8 / 8 | 6,776 | 271 | 9,094 | 191 |
| x64musl | speed | 8 / 8 | 6,776 | 271 | 9,094 | 191 |

The exact work vector records, in order: 166,300 source-font bytes, one run,
eight shaped glyphs; two scene-command visits, one scene color reference, one
scene text placement, and graphics depth two; eleven font-plan entries, 6,776
subset bytes, eight source scalars, one text run, one placement, eight emitted
glyphs, eight mappings, 271 content bytes, one font, nine font objects, fourteen
total objects, 7,047 uncompressed payload bytes, and 9,094 emitted bytes. The
four-allocation increase is the reviewed cost of the dense command, group,
page-group-edge, and page arenas; no font, text-content, or output bytes change.
The one-byte snapshot
reduction records the exact OS/2 CapHeight instead of the former hardcoded
descriptor value; glyph data and rendered pixels are unchanged.

This is pipeline evidence, not Gate 3 closure. The public caller-font/theme path
is covered by the subsequent caller-font text slice. Paragraph layout and
pagination, theme-driven text color, the rest of the multilingual script matrix,
scene-driven paint emission, accessibility tagging, facade output, caller
source-refcount evidence, and multi-placement parse reuse remain open.
