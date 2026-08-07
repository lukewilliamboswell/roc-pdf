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

Text semantics now cross a dedicated `KernelTextSemantics.Plan` boundary before
tagging. It bounds source bytes, source scalars, text properties, and property
bytes; records every scalar-to-UTF-8 boundary without retaining source slices;
checks that occurrence and fragment scalar ranges name the same UTF-8 span; and
normalizes the occurrence-to-fragment reverse index. Text properties have one
node or occurrence owner. The ordinary Gate 2 semantic plan remains unchanged
and continues to reject text stores rather than silently widening its claim.

`KernelTagged` consumes the validated semantic plan and typed scene plan. The
fixture therefore proves its fragment group, paint edge, MCID, ParentTree row,
and structure `/K` items before either text-content path is built.

`KernelTextOwnership` now builds that tagged plan and joins every scene
`DrawText` to the text store. Each dense run must be painted exactly once by a
fragment-owned group. Counts and prefix sums form a run-to-fragment reverse
index in linear time; scanning runs in their normalized source order then proves
that every text fragment's scalar and UTF-8 ranges are covered exactly without
gaps or overlap. Artifact-owned text is explicitly unsupported until its
generated-text and extraction policy exists. Orphan, duplicate, artifact,
occurrence-mismatched, and incomplete-range twins all fail before lowering.

Scene text lowering now consumes this join and prepares exactly one bounded,
local-coordinate glyph body per run. `KernelContent` combines that body with
the validated scene transform, calibrated fill or stroke colors, text rendering
mode, and fragment MCID. Its evidence fixes the operator order as marked
content, transform, color, `BT`, `Tr`, font selection, glyph operators, `ET`,
and balanced closure. The dependency-free prepared-run carrier lives at the
content boundary, so standalone Gate 2 packages do not acquire the Gate 3
Unicode dependency. A separate Gate 3 object wrapper appends nine stable object
identities per font and moves only xref; the enduring Gate 2 object plan is not
widened. The additive tagged-page path installs each planned Type 0 reference
under its deterministic `F` resource name. The next slice replaces the legacy
untagged object graph by orchestrating these plans and emitting the reserved
font objects.

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
| arm64mac | speed | 8 / 8 | 6,776 | 271 | 9,094 | 221 |
| x64musl | speed | 8 / 8 | 6,776 | 271 | 9,094 | 221 |

The exact work vector records, in order: 166,300 source-font bytes, one run,
eight shaped glyphs; two scene-command visits, one scene color reference, one
scene text placement, and graphics depth two. Semantic work records zero
attributes, two content items, one fragment count and validation, depth two,
one namespace, two nodes, one occurrence, one prefix step, one reverse write,
zero text-property bytes and visits, nine source bytes, eight source scalars,
and one source. Tagged work records zero artifact groups, one fragment group,
two `/K` items, two node ranges, one occurrence-owner edge, one paint edge, one
ParentTree prefix step, and one ParentTree write. The remaining counters are
followed by ownership work: two command visits, one group, one run, one fragment
prefix step, one fragment write, one range check, and one text fragment. The
remaining counters are eleven font-plan entries, 6,776 subset bytes, eight
source scalars, one text run, one placement, eight emitted glyphs, eight
mappings, 271 content bytes, one font, nine font objects, fourteen total
objects, 7,047 uncompressed payload bytes, and 9,094 emitted bytes.

The first four added allocations remain the reviewed dense scene arenas. The
next 25 are bounded scalar-offset/source-fact arrays, semantic ownership and
reverse-index arrays, and tagged MCID/ParentTree/`/K` planning arrays. No font,
text-content, or output bytes change. The ownership join adds five bounded
arrays: run owners, fragment counts, fragment starts/cursors, fragment-run
reverse entries, and the dense run-to-fragment map.
The one-byte snapshot
reduction records the exact OS/2 CapHeight instead of the former hardcoded
descriptor value; glyph data and rendered pixels are unchanged.

This is pipeline evidence, not Gate 3 closure. The public caller-font/theme path
is covered by the subsequent caller-font text slice. Paragraph layout and
pagination, theme-driven text color, the rest of the multilingual script matrix,
scene-driven paint emission, accessibility tagging, facade output, caller
source-refcount evidence, and multi-placement parse reuse remain open.
