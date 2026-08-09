# Gate 3 generated list-label slice

The facade list constructor now carries each visible bullet through the staged
pipeline as a semantic label occurrence with source Unicode `•` and one owned
`SourceToPresentation(GeneratedText)` fact. `KernelFacadeShape` validates that
the label occurrence has exactly that fact, with a source range equal to the
occurrence's owned Unicode range, before it submits the label for shaping.
Later stages retain the same semantic store through shaping, lines, pages,
fragments, scene ownership, tagged lowering, and PDF text lowering; no stage
recognizes a label from indentation, paint position, glyph ID, or CMap bytes.

The positive public facade fixture authors two list items using only
`Pdf.bullets`. It paints the two bullet labels and two bodies as four
fragment-owned text runs. Direct CID/`ToUnicode` reconstruction is exactly
`•First•Second`; the bullet requires no `/ActualText`, because its generated
logical source and visible presentation are the same one-scalar value and the
CID mapping is unambiguous. PDFBox 3.0.8's extraction API deliberately reports
line geometry, so its independently pinned exact expectation is
`• First\n• Second\n`.

The structural oracle verifies the tagged `L -> LI -> (Lbl, LBody)` hierarchy,
two labels, two bodies, balanced marked-content/text scopes, Identity-H Type 0
font/CID closure, and complete direct `ToUnicode` mappings. Its atomic
original-byte negative changes the bullet's CMap row and is rejected. The Roc
atomic negative removes only the owned generated-presentation property from a
validated label occurrence; shape preparation returns
`GeneratedLabelEvidenceInvalid` before font shaping or PDF planning, and the
fixture's blank evidence carrier is not a fallback output.

At 72 dpi, exact local renderer evidence on the original bytes is:

| Renderer | Bounds | Changed pixels | Dark pixels | Grayscale ink |
| --- | --- | ---: | ---: | ---: |
| PDFBox 3.0.8 | `(73, 74, 128, 97)` | 340 | 164 | 41,648 |
| PDFium Chromium 7988 | `(72, 74, 128, 97)` | 458 | 175 | 44,607 |

Their bounds agree within the existing two-pixel cross-renderer geometry bound;
pixel coverage remains renderer-specific.

## Dev-backend performance review

The positive whole-pipeline measurement boundary is before runtime facade
document construction. On the pinned dev backend it allocates 1,703 times and
emits 11,468 bytes. The cost is the bounded list/label semantic graph (five
semantic nodes, four occurrences, two properties), four shaped/laid-out text
runs, four owned fragments/scene groups, and the one built-in font subset. The
bullet source is one immutable deduplicated source value shared by both labels;
it is not copied per placement. Traversals are indexed flat-buffer loops and
the slice adds no cache, resource, or output-retention policy.

The atomic shape-boundary negative allocates 44 times and has deterministic
work `[1, 667]`: one rejected property and the independent blank evidence
carrier. It does not inspect a font, shape a glyph, or create a pipeline PDF.
Both exact allocations and work vectors are registered in `tests/spec.json`
for the pinned dev backend. No other backend result is used or claimed.

This closes only the generated-label row of Gate 3's extraction matrix. It does
not close Gate 3; ligature, supplementary-plane, RTL, CJK, hyphen behavior,
case transformations, and the remaining Gate 3 audit/evidence remain open.
