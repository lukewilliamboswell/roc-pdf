# text-layout visible searchable text slice

This slice joins the earlier Unicode analysis, bounded shaping, deterministic
font plan, sanitized subset, and Type 0 font-object stages into one real PDF 2.0
page. The scene transform places a local-coordinate run; the page content
selects the exact planned font resource and run size, positions each glyph with
checked layout arithmetic, and emits 16-bit CIDs. The
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
node or occurrence owner. The ordinary tagged-visual semantic plan remains unchanged
and continues to reject text stores rather than silently widening its claim.
The text-layout text path additionally accepts only the PDF 2.0 block roles needed
by the facade (`P`, headings, and list structure); the tagged-visual path remains
restricted to `Document` and `P`, and unsupported inline or later-capability roles
still fail before tagging.

`KernelTagged` consumes the validated semantic plan and typed scene plan. The
fixture therefore proves its fragment group, paint edge, MCID, ParentTree row,
and structure `/K` items before text content is built.

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
content boundary, so standalone tagged-visual packages do not acquire the text-layout
Unicode dependency. A separate text-layout object wrapper appends nine stable object
identities per font and moves only xref; the enduring tagged-visual object plan is not
widened. The additive tagged-page path installs each planned Type 0 reference
under its deterministic `F` resource name. `KernelTaggedTextStructure`
now composes tagged objects, scene content, ordinary resources, and the reserved
font families into one sealed structure and verifies their planned identities
before xref. The visible fixture consumes this path; no parallel legacy text or
object graph is built.

Logical Unicode remains owned by the semantic occurrence. Text lowering builds
one bounded scalar cache for the semantic sources, walks each placed run once,
and derives each CID mapping from the run's explicit cluster range. Every run
must be placed exactly once and every content CID must receive one mapping.
Conflicting mappings, missing retained glyphs, absent occurrences, invalid
ranges, and unplaced or duplicate runs are typed errors before a PDF structure
is returned.

This fixture exercises the simple no-`ActualText` path and remains byte-stable.
The subsequent
[reordered ActualText slice](actual-text.md) expands the same lowering
boundary to reordered, context-dependent, multi-glyph, right-to-left, and
transformed runs, plus occurrence-owned semantic overrides. Unsupported or
missing evidence remains an error rather than an inferred mapping.

## Independent output evidence

The fixture renders and extracts `Café PDF` on one A4 page. It embeds a fresh
6,776-byte sanitized TrueType subset, an identity CID-to-GID map for eleven
planned entries, eight exact `ToUnicode` rows, one CIDFontType2 descendant, and
one Type 0 parent. The tracked PDF is 10,000 bytes and contains twenty non-xref
objects, including the tagged structure, calibrated Gray resource, and
scene-owned content stream; unlike the earlier text-layout protocol carriers, it is
visibly nonblank in ordinary readers.

The independent structural checker reconstructs the displayed string from the
content CIDs and `ToUnicode`, verifies the exact widths and subset digest, and
rejects same-length negative twins for a changed Unicode row, wrong page font,
wrong CID map, and wrong embedded-font length. PDFBox 3.0.8 must independently
extract the exact UTF-8 bytes `Café PDF\n`. PDFBox and PDFium also render at 72
dpi. Each renderer has its own pinned ink metrics within explicit tolerances:
two pixels per bound, 60 antialiased pixels, 40 dark pixels, and 6,000
grayscale-ink units. Their ink bounds must also agree within two pixels. The
renderers use different antialiasing coverage rules, so pixel count and
grayscale ink are checked against their respective measurements rather than
treated as a cross-renderer conformance vote.

| Renderer | Bounds | Changed pixels | Dark pixels | Grayscale ink |
| --- | --- | ---: | ---: | ---: |
| PDFBox 3.0.8 | `(72, 133, 120, 142)` | 241 | 100 | 29,490 |
| PDFium Chromium 7988 | `(72, 133, 120, 142)` | 313 | 109 | 31,149 |

## Allocation validation

Current exact allocation and work expectations live in the matching scenarios
in [`tests/spec.json`](../../tests/spec.json). Review changes with the
[allocation baseline protocol](../testing.md#allocation-baselines).
