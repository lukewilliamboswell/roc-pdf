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

The fixture's atomic negative mode registers checksum-valid restricted bytes.
Registration returns `EmbeddingRightsProhibited` before any registry can be
passed to `Pdf.Options`, and the mode emits an empty byte list. A separate
unknown-face facade error covers a theme face not present in a registered
source. Neither path falls back to the packaged face.

The fixture is intentionally not yet in `tests/spec.json`: its snapshot and
exact dev-backend allocation record must join the pending reviewed Gate 3
allocation rebaseline as one deliberate change. This document records the
representation, ownership, structural, no-bytes, source-retention, and
multi-placement parse-reuse evidence boundary; it does not claim Gate 3
closure.
