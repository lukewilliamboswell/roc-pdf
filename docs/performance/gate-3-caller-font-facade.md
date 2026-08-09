# Gate 3 caller-font facade composition

This slice closes the missing public connection between `Font.Registry`,
`Theme.with_font`, and `Pdf.to_bytes_with` for the constrained built-in Latin
facade path. `Pdf.Options.FontSource` is either `BuiltIn` or
`Registered(Font.Registry)`. The latter contains the opaque registry returned
by transactional registration; `Theme` still names only its returned opaque
`FaceId`.

At facade preparation, the selected source yields one `KernelFont.Inspection`.
The caller branch obtains the inspection through `Registry.prepared_face`, so
the exact original byte allocation and once-produced parse facts move into the
same semantic, shaping, line-layout, scene, font-plan, subset, embedding, and
sealed-object path used by the packaged face. `KernelFacadePipeline` and all
later stages receive no provenance flag, registry, caller resource ID, or PDF
object identity. They cannot substitute a packaged font or reparse caller
bytes as a fallback.

The focused public fixture `tests/gate3_caller_facade/main.roc` registers the
external 7,816-byte fixture, applies its returned face to `Theme`, supplies the
registry through `Pdf.Options.with_font_registry`, and generates three text
placements. Its work carrier records the registration input/retained/copied
bytes, inspection visits, one resource/face/instance/policy, and three authored
placements. The structural facade-output checker proves the emitted Type 0
font, sanitized TrueType subset, CID map, ToUnicode mappings, tagged content,
and no external font reference from the original bytes. Three placements use
the one selected inspection and one embedded font resource; no per-placement
registration, parse, source-payload copy, or PDF font object is constructed.

The registered fixture is now `Gate 3 caller-font facade output` in
`tests/spec.json`. On the pinned dev backend it emits a 10,348-byte snapshot
with 1,576 Roc allocations. Its deterministic work record is 7,816 input and
retained bytes, zero copied input bytes, 17 table, 15 glyph, nine cmap, and
four component-edge inspection visits; exactly one resource, face, instance,
and policy; three authored placements; and 7,816 selected source bytes. The
three placements prove that one
registered inspection and source payload feed the full facade pipeline rather
than repeating registration, parse, or source-payload copies per placement.
The source-specific subset names and OS/2 CapHeight are structurally checked,
and fixture-local oracles pin PDFBox 3.0.8 and PDFium Chromium 7988 72-dpi
metrics separately. PDFBox extraction is the expected three line-separated
`Café PDF` placements; direct CID/ToUnicode reconstruction retains the
paint-order concatenation.

`Gate 3 caller-font facade restricted-rights atomic negative` supplies
checksum-valid restricted bytes. Registration returns
`EmbeddingRightsProhibited` before any registry can be passed to `Pdf.Options`,
emits exactly zero PDF bytes, and records 26 dev-backend allocations with work
`[1, 0]`. Its tracked zero-byte `snapshot.pdf` is solely the independent
harness expected-output carrier; it is not a PDF emitted on this rejection
path, whose `emitted_pdf_bytes` remains zero. It therefore cannot fall back to
the packaged face. A separate unknown-face facade error continues to cover a
theme face absent from a registered source.

This is public caller-font composition evidence, not Gate 3 closure. The
current constrained facade resolves one selected `FaceId` to one inspection.
Although `Font.Registry` stores dense face/instance/policy collections, the
facade has not yet lifted that one-face selection into the roadmap's finite
ordered multi-face font policy and per-cluster coverage selection. Mixed-face
or broader multilingual caller-font output remains an explicit unmet Gate 3
dependency.

The local ordered-policy planning seam is now recorded in
[`gate-3-multiface-font-selection.md`](gate-3-multiface-font-selection.md).
It validates and selects finite ordered caller/test faces per supplied grapheme
cluster, but the facade still has its one-face shaping and output handoff.
Accordingly, this record remains a single-face facade checkpoint rather than a
claim of public mixed-face output.
