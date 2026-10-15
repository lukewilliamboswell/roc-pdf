# Specific facade diagnostics for every pipeline failure

`Pdf.to_bytes_with` and the other facade entry points mapped the pipeline's
author-facing failures to located diagnostics, but every other failure fell
through `pipeline_error`'s last arm to `UnsupportedAuthoringContent({
blocks })`: a crossed stage limit, an unsupported heading level, a style
face the font selection had not prepared, a shaping failure no text run
explained, a color the output intent cannot paint, and every internal
precondition of every later stage all looked the same, with no location.
The gallery hit it twice: the subsetter's missing hinting tables and the
selected shaper's `SplitMismatch` (both fixed separately; see
`font-subsetting.md` and `rich-inline.md`).

## Contract

`UnsupportedAuthoringContent` is removed from `Pdf.Error`; no failure maps
to it. The facade now answers:

- **Author causes with their own code**, located where the failure carries
  a location:
  - `semantics.heading_level` at the heading: a level outside 1 to 6
    (`InvalidRelationship`).
  - `document.language_empty` and `document.title_empty` (normally caught
    earlier by metadata validation).
  - `text.theme_face` at the block: a style face the font selection did
    not prepare.
  - `text.shaping_failed`: the selected faces could not shape the text and
    no single run was identified (`FontCoverageMissing`; no face is
    substituted).
  - `color.unsupported`: a text color the output intent cannot represent.
  - `image.invalid`: an image whose data does not match its declaration
    (a packed plane of the wrong length or row stride, out-of-range
    dimensions, a JPEG the package does not accept), with the image
    failure's tag and payload, which names its dense resource index. A
    crossed image limit is a `BudgetExceeded` stage error instead.
- **Every other failure keeps its exact stage and failure.** The failure's
  nested tag path (for example
  `Output.Structure.TaggedObjects.Object.LimitExceeded`) becomes a stable
  feature code, `pipeline.output.structure.tagged_objects.object.limit_exceeded`,
  and the diagnostic's detail. A crossed limit (`LimitExceeded`,
  `CmapLimitExceeded`) is `BudgetExceeded`, with the attempted value and the
  limit from the failure in the message. Any other failure is the new
  `Conformance.DiagnosticCode.InternalInvariant`: a package defect, reported
  as such instead of as an authoring error. Page-layout failures of a table
  document and furniture failures without an author mapping take the same
  path (the furniture arm previously returned `InternalGenerationFailure`).

The tag path is read from the inspected failure value, one byte at a time
over its leading tags only, and the innermost payload is shown up to its
matching parenthesis and at most 160 bytes, so a failure that carries a
long list (a table layout's units) never floods the message. This runs only
on the rejection path; a successful preparation does no extra work.

## Evidence

- Four `Pdf.roc` expects: a nested limit failure yields its snake-case
  feature, `BudgetExceeded` classification, dotted path, and bounded
  payload; an internal failure yields `text.invalid_run` without the limit
  classification; a payload-free tag has no payload view; and a level-7
  heading through `Pdf.to_bytes` is `semantics.heading_level` at
  `contents[1]` (previously `UnsupportedAuthoringContent({ blocks: 2 })`).
- The facade contract test `tests/contracts/pdf_facade.roc` rejects a
  packed RGB plane of 3 bytes declared as 2 x 2 pixels as `image.invalid`
  with detail `DecodedLengthMismatch` (previously
  `UnsupportedAuthoringContent({ blocks: 1 })`).
- No case baseline changes: the success path is untouched.
