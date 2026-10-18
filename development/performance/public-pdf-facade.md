# text-layout public built-in `Pdf` facade evidence

This is a narrow public-boundary slice, not a text-layout closure record. Its
single authored paragraph is created inside `main!` after a runtime guard, so
the test host's `before_fixture_main` reset includes facade document
construction as well as `Pdf.to_bytes`. The guard prevents constant folding
from turning an all-literal public example into a zero-allocation measurement.

The dev-backend `x64musl` result with Roc
`release-fast-64c9d73d`, Zig 0.16.0 ReleaseFast, and the public fixture's
`["0"]` argument is 1,423 Roc allocation events and one deterministic
`output_bytes=12397` counter. The PDF hash is
`8723c2d6ea86a67205f9fc3a5f1ec18acb955af0f259842be2234753d4d4559f`.
The paired target record is retained in `tests/spec.json`; this local result
does not claim cross-platform release evidence.

The fixture is intentionally byte-identical to the existing internal authored
pipeline scenario. It has one document block, one semantic occurrence and
line, one page and fragment, two scene commands, one planned embedded font,
and twenty PDF objects. It consumes the facade document into the normal
normalization/pipeline path. No PDF object, glyph, scene, or font internal is
exposed by the public fixture, and it adds no cache, resource payload, output
slice, or alternate serialization representation. Its 1,423 count is one
higher than the 1,422 internal pipeline case because public construction uses
a runtime title guard in the measured region; this is a measurement-boundary
cost, not a changed PDF plan, copied font payload, or per-glyph allocation.

The snapshot is checked before the facade-output structural checker reconstructs
the text from the original content CIDs and `ToUnicode` CMap. The same original
bytes pass exact PDFBox 3.0.8 extraction and independently pinned 72-dpi
PDFBox/PDFium metrics. The fixture's `Pdf.page_footer` twin receives
`UnsupportedAuthoringContent({ blocks: 1 })` with no `List(U8)` result; it does
not select the blank path or substitute page-artifact output.
