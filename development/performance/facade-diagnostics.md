# Specific facade diagnostics for every pipeline failure

The original facade mapped author-facing failures to located diagnostics, but
other failures fell through `pipeline_error` to
`UnsupportedAuthoringContent({ blocks })`. Crossed stage limits, unprepared
style faces, unexplained shaping failures and internal preconditions all
looked the same. The gallery exposed missing subset hinting tables and a
`SplitMismatch`; their separate repairs are recorded in
[font-subsetting.md](font-subsetting.md) and [rich-inline.md](rich-inline.md).
The generic public error has since been removed.

## Typed conversion contract

[KernelFacadeFailure.roc](../../package/KernelFacadeFailure.roc) owns private,
exhaustive conversions from the pipeline's reachable error unions to
`{ category, feature, path, detail }`. Each constructor explicitly selects its
stable feature segment, diagnostic path segment and `Budget` or `Invariant`
category. Owning-stage wrappers add context to that typed result.

For example, the typed constructor path
`Output.Structure.TaggedObjects.Object.LimitExceeded` yields
`pipeline.output.structure.tagged_objects.object.limit_exceeded`, a
`BudgetExceeded` public diagnostic and that exact dotted detail path. A
`Text.InvalidRun` failure yields `pipeline.text.invalid_run` and
`InternalInvariant`. Record-held causes also supply their category through a
typed conversion: a table-layout limit stays `Budget`, while the stable
`pipeline.pages.table_layout` wrapper identity is retained.

New constructors require an explicit decision in the owning exhaustive match.
There is no fallback branch that guesses a budget failure or derives a feature
from a constructor's spelling. Debug text such as `LimitExceeded` inside a
string payload cannot change classification or identity. These private error
types do not enter the common public API.

`Str.inspect` renders explanatory leaf detail only, after the typed decision.
The detail is capped to a 160-byte UTF-8 prefix plus an ellipsis; a prefix that
splits a scalar uses the fixed truncation marker. No parser searches rendered
text for tags, parentheses, punctuation or budget names. A record-held table
error renders its cause rather than its retained unit/group arenas. The
conversion runs only after rejection; a successful preparation does not call
it or build diagnostic strings.

## Public authoring diagnostics

[Pdf.roc](../../package/Pdf.roc) keeps specific authoring mappings where the
failure has an author-facing cause and location:

| Feature | Cause and location |
| --- | --- |
| `semantics.heading_level` | A heading outside levels 1–6, at its authored path |
| `document.language_empty`, `document.title_empty` | Missing required metadata, normally rejected earlier |
| `text.theme_face` | A block style names an unprepared face |
| `text.shaping_failed` | Selected faces cannot shape a run and no individual run was identified |
| `color.unsupported` | A text color cannot be represented by the output intent |
| `image.invalid` | Invalid declared image data, retaining its typed failure identity |

Crossed image limits use `BudgetExceeded` through the typed stage converter.
Other unmapped stage failures use `InternalInvariant`, preserving their typed
stage and cause as a package defect. Page-layout table failures and furniture
failures without a specific authoring mapping follow the same contract.
Located style-availability and coverage diagnostics retain the font resolver's
explicit owner facts; their evidence is in
[default-fonts.md](default-fonts.md).

## Evidence and measurement scope

The current `KernelFacadeFailure` expects cover nested budget identity, payload
strings that resemble error tags, payload-bearing and payload-free invariants,
record-held table causes, image marker limits and bounded long detail. The
`Pdf` expects verify that typed categories become the corresponding public
codes and stable paths. Additional facade regressions retain `image.invalid`
for a bad declared image and `semantics.heading_level` at `contents[1]` for a
level-7 heading. These execute with the package checks in `scripts/test.py`.
The public facade contract in
[tests/contracts/pdf_facade.roc](../../tests/contracts/pdf_facade.roc) retains
the malformed packed-image regression.

The earlier diagnostic slice recorded four facade expects and no case baseline
changes. That historical observation described the preceding parser-based
implementation. The typed conversion likewise adds no success-path call or
storage, but the current integration also changes default font programs and
fixture typography. Its full native and cross-target allocation/work evidence
requires separate review; success-output differences must not be attributed
to diagnostic conversion alone. The reviewed new font-family scale evidence
and changed fixture measurement boundaries are recorded in
[default-fonts.md](default-fonts.md).
