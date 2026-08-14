# Gate 3 ordered multi-face advanced output

This slice consumes the existing ordered `Font.FaceRange` plan at the advanced
shaped-run boundary. It is deliberately not a public `Pdf`-facade claim: the
facade still selects one `Theme` face and its built-in shaping path is Latin
only. The remaining public handoff must carry Unicode cluster facts and the
ordered policy through that convenience authoring path; it must not infer a
face from a glyph ID or silently pick another registered face.

The focused `Gate 3 ordered multi-face advanced output` fixture registers the
7,816-byte caller Latin face and 2,104-byte test-only CJK face, then makes the
ordered policy `[Latin, CJK]`. It supplies already-itemized source clusters for
`C中é`, and planning retains the selected ranges `[Latin, CJK, Latin]`.
`KernelShape.validate_advanced_selected` consumes those exact ranges along with
the once-parsed inspections. Each resulting run must match one selected cluster
range and instance; validation does not repeat coverage selection. The text,
font-plan, subset, CID, ToUnicode, resource, tagged-content, and sealed-object
stages retain those instance facts through two Type 0/CID/ToUnicode resources.

The output structural oracle proves exact two-font page-resource closure,
Identity-H Type 0 descendants, two embedded sanitized TrueType subsets, and
separate CID/ToUnicode maps: Latin `C` and `é` use `F1_0`; Han `中` uses
`F1_1`. Direct CID reconstruction and PDFBox 3.0.8 extraction both produce
`C中é`. qpdf accepts the original bytes without warnings. At 72 dpi, PDFBox
3.0.8 records `(72,132,95,142)`, 130 changed pixels, 52 dark pixels, and
15,844 grayscale ink; PDFium Chromium 7988 records `(72,132,96,142)`, 174,
64, and 17,144. The fixture-specific oracle pins those renderer models
independently and checks their geometry agreement.

The atomic negative supplies Latin `C` falsely itemized as `Hani`. Neither
registered face is eligible under the finite ordered policy, so selection
returns `MissingCoverage` before a shaped store or PDF plan exists. Its
`emitted_pdf_bytes` counter is exactly zero; the tracked 667-byte blank file is
only the test harness carrier and cannot be a fallback result.

On the local pinned dev backend (`release-fast-64c9d73d`, x64musl), the
positive fixture records 196 Roc allocations and work
`[3,4,15,3,7816,2104,3,3,3,5,2,3,2,18,29,6900,11319]`: three graphemes, four
ordered face visits, 15 coverage-span visits, three selected ranges, two
retained source payloads, three validated runs/clusters/glyphs, two subset
plans, three Unicode mappings, two fonts/18 font objects, 29 total objects,
6,900 font-program bytes, and 11,319 output bytes. The negative records 41
allocations and `[1,0,667]`. The extra bounded state is three selection facts,
three run/cluster/glyph records, two global subset plans, and the second font's
nine planned PDF objects; no source payload is copied or reparsed per run.
These are local dev-backend baselines only, not a cross-platform rebaseline.

The public facade integration this advanced boundary anticipated is now
recorded in
[`gate-3-multiface-public-facade.md`](gate-3-multiface-public-facade.md).
