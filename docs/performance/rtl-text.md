# text-layout resolved right-to-left output

This closes the real UAX #9 right-to-left row of the text-layout
extraction/rendering matrix: one right-to-left paragraph with a
mixed-direction span and mirrored paired punctuation, whose paint order and
mirrored presentation come from the pinned dependency's revision-51
bidirectional algorithm and whose extraction recovers the untouched logical
source.

## Dependency boundary

`roc-lang/unicode` 4.0.0 (`unicode-4.0.0-adoption.md`) supplies
`Bidi`. `package/KernelBidiBoundary.roc` owns no bidi rules: it calls
`Bidi.analyze_paragraph` once per source, projects the per-scalar resolution
into flat project-typed facts (resolved level, matched bracket, mirroring
scalar, non-rendering flag), and resolves a selected line with
`Bidi.reorder_line` into a dense visual cluster-ID sequence plus per-cluster
mirror decisions. The paint sequence omits exactly the clusters X9 removes
and counts them in `removed_clusters`; any other unpainted cluster is a typed
rejection, so text cannot silently vanish. A cluster that reordering would
split is rejected rather than painted in an invented order, and a mirrored
scalar inside a multi-scalar cluster is rejected rather than silently
unmirrored. The retained upstream analysis holds coordinates and properties
only — the dependency documents that it never retains the source `Str` — and
the project's work counters cover the project's own walks, because the
dependency exposes none.

## Pinned conformance vectors

`BidiEvidence.uax9_vectors` transcribes seven expectations from the
normative Unicode 17.0.0 `BidiCharacterTest.txt`: resolved paragraph level,
per-scalar levels (`x` becomes `RemovedByX9`), and display order. They cover
an isolate with an X9-removed embedding, a right-to-left isolate reaching
resolved level 4, European numbers with a common separator, and the UAX #9
bracket-pair example in both paragraph directions. The multi-line rows are
the only computed expectations: they apply L1/L2 to the same normative levels
over each sub-line range, because the conformance file pins whole-paragraph
lines only, and their concatenation reproduces the pinned whole-line order.
Three atomic rejections accompany them — a mutated paragraph fact, a line
range outside the paragraph, and a crossed cluster bound. Registered work is
`[7, 108, 55, 53, 2, 18, 4, 3, 667]` at 40 allocations. This is a seam over
the pipeline's handoff, not a re-hosting of the upstream corpus; the
dependency owns full conformance.

## Fixture font

`tests/assets/IBMPlexSansHebrew-Rtl-Fixture.ttf` is a test-only 5,084-byte
static TrueType subset of IBM Plex Sans Hebrew Regular (`IBM/plex` tag
`v6.4.0`, source SHA-256
`98cd8ca13fef47fb57c20faed17a346639bb418b7abeb096fd9693ea3eecc445`).
`scripts/build_rtl_font_fixture.py` pins fontTools 4.61.1, verifies the
source digest, retains only the fourteen scalars the fixture text uses —
including *both* members of each mirrored pair, because an odd-level bracket
paints its partner's glyph — clears `fsType`, renames the face, and
reproduces fixture SHA-256
`0b35f7c30ea82df7e3e2773bcf06f96456e83285f9c41b47ec1e01688a2214aa` under
`--check`. No OpenType layout feature is retained: the Hebrew letters are
non-joining and mirroring is a resolved fact, never a GSUB substitution.

## Output slice

The fixture text is the UAX #9 bracket-pair example `אב(גד[&ef].)gh`, whose
right-to-left resolution is the normative row: paragraph level 1, levels
`1 1 1 1 1 1 1 2 2 1 1 1 2 2`, display order
`12 13 11 10 9 7 8 6 5 4 3 2 1 0`, four visual runs. The advanced store keeps
clusters in logical order and the glyph buffer in resolved paint order;
`KernelShape.validate_advanced_with_bidi_order` proves that the painted
sequence is exactly the resolved order, that the run's declared direction is
the direction the resolution gives its scalars (the containing directional
run's direction, or the paragraph direction for a run spanning several), and
that each of the four mirrored brackets paints its mirrored partner's glyph
from the same face — a missing mirrored glyph is a typed error, never an
unmirrored fallback. `KernelPdfText` is unchanged: it already forces
`/ActualText` for right-to-left runs.

The 7,891-byte snapshot paints fourteen CIDs in the resolved visual order and
carries `/ActualText <FEFF05D005D1002805D205D3005B002600650066005D002E002900670068>`,
the exact logical source. Each mirrored bracket's CID maps back through
`ToUnicode` to its **logical** character rather than to the character its
glyph draws (`(` and `)` map to CIDs whose glyphs are each other's), which is
the direct evidence that mirroring is a resolved presentation fact and that
extraction still recovers reading order. The embedded sanitized subset is
4,380 bytes, SHA-256
`9ede12f9cb952e570feb4161f3951a3245116236f88da3511bdb01674d46705c`.
`scripts/check_rtl.py` verifies all of this on the original bytes with
four mutation self-tests. PDFBox 3.0.8 extraction is pinned separately as
`hg).]fe&[אב)גד`: PDFBox applies its own bidi normalization and bracket
mirroring to extracted text, so that string is an empirically pinned
PDFBox-specific normalization of the painted sequence, not a second opinion
on reading order — the authoritative logical recovery is the `ActualText` and
`ToUnicode` evidence above. PDFBox and PDFium 72-dpi ink metrics are pinned
per engine in `check_text_renderers.py` (`--rtl`).

The registered positive work vector is
`[5084, 1, 14, 14, 4, 4, 1, 14, 14, 14, 1, 14, 14, 590, 20, 7891]` at 1,181
allocations: one font payload, paragraph level 1, fourteen bidi cluster
visits and visual writes, four visual runs, four mirrored brackets, one run
of fourteen clusters and glyphs, fourteen source scalars, one `ActualText`
run of fourteen scalars, fourteen mappings, 590 prepared text bytes, twenty
objects.

The atomic negative proves both halves of the handoff independently: swapping
two painted glyph references (every logical fact intact, a paint sequence the
resolution never produced) is rejected as `PaintPosition`, and painting a
bracket's own glyph instead of its mirrored partner — the classic unmirrored
fallback — is rejected as `MirrorGlyphMismatch`. Both fail before any scene,
object plan, or PDF exists; the fixture emits the standard 667-byte blank
carrier with work `[2, 667]` at 57 allocations.

## Boundary

This is the advanced-boundary row. The public facade stays left-to-right:
`KernelFacadeShape` has no bidi path and no `Theme` option requests one, so
authored facade documents are unaffected. Arabic joining shaping, vertical
writing, and automatic shaping beyond the declared boundary remain out of
scope, as does facade-path bidi.
