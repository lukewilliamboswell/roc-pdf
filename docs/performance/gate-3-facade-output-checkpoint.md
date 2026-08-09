# Gate 3 facade output checkpoint

Date: 2026-08-08

Branch: `codex/gate-3`

Draft PR: <https://github.com/lukewilliamboswell/roc-pdf/pull/6>

This is a work-in-progress checkpoint. It does not close Gate 3 or claim that
the high-level facade has completed the remaining multilingual, caller-font,
renderer, extraction, or allocation evidence.

## Completed in this checkpoint

- All package manifests use the immutable `roc-lang/unicode` 3.0.0 release
  instead of a sibling checkout. The imported artifact was built with the same
  pinned Roc nightly as this repository.
- `KernelFacadeScenes.Plan` retains its validated `KernelScene.Plan`, so later
  stages consume the earlier stage's facts rather than rebuilding scene state.
- `KernelFacadeOutput` composes the validated scene through font planning,
  subsetting, resource use, PDF text, content streams, page objects, font
  objects, tagged structure, and deterministic emission.
- The repaired real-authoring path emits a deterministic 12,397-byte PDF for
  `Café PDF generation in pure Roc.`. It is now a regular scenario with exact
  dev-backend work/allocation evidence, direct CID/ToUnicode reconstruction,
  PDFBox extraction, and fixture-local PDFBox/PDFium render metrics.
- `KernelFacadePipeline` connects normalized authoring through semantics,
  shaping, line layout, pagination, text materialization, fragments, scenes,
  and output. A focused evidence executable records the current runtime
  boundary without adding a passing snapshot case prematurely.
- `Pdf.to_bytes` and `Pdf.to_bytes_with` now select that completed pipeline
  for nonblank `Standard` documents. The public one-import fixture is an
  ordinary dev-backend scenario: it records the 12,397-byte snapshot, the
  1,423-allocation construction-inclusive dev baseline, deterministic
  output-byte work,
  and the same structural/CID/ToUnicode oracle as the internal authored path.
  The fixture also retains an atomic unsupported-artifact rejection; blank
  documents retain the structural blank path, while `Archive` and
  `AccessibleArchive` remain unavailable.

The public measurement boundary, allocation cause, no-copy review, and oracle
results are recorded in
[gate-3-public-pdf-facade.md](gate-3-public-pdf-facade.md).

The built-in font is imported as `List(U8)` with Roc's byte-list `import`
syntax. It is not embedded as Roc source.

## Resolved line-layout boundary

The original real-authoring overflow was resolved by the private
`RangeBounds` boundary in `KernelLineLayout`. The complete staged path now
reaches PDF emission. Its positive case has one semantic occurrence, one line,
one page, one fragment, two scene commands, 32 glyph usages, and 20 objects.
The atomic negative lowers the line-run limit to zero, receives the stable
`Lines(LimitExceeded(...Runs...))` rejection before output planning, and emits
no pipeline PDF; the evidence executable returns only its independent blank
measurement artifact.

## Reproduction

Build the focused executable:

```sh
roc build tests/gate3_facade_output/main.roc --opt=dev --output=facade-output-probe
```

Then run the staged probes:

```sh
./facade-output-probe probe 0
./facade-output-probe probe 1
./facade-output-probe probe 2
```

All staged probes and the full path now succeed:

```sh
./facade-output-probe visible 0
```

The repository uses the dev backend for functional and allocation evidence;
do not switch this probe to `--opt=speed`.

## Next steps

1. Complete the remaining multilingual and text-behavior matrix required by
   the roadmap, including RTL, CJK, ligature, hyphenation, and
   case-transformation output. Supplementary-plane and generated-list-label
   output are now recorded evidence.
2. Audit every Gate 3 roadmap row, including caller-font behavior and
   performance bounds, before adding the Gate 3 closure record.

Do not accept allocation or PDF snapshot changes mechanically while completing
these steps. Each change needs an architectural cause and an explicit review.
