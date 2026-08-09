# Gate 3 facade output checkpoint

Date: 2026-08-08

Branch: `codex/gate-3`

Draft PR: <https://github.com/lukewilliamboswell/roc-pdf/pull/6>

This is a work-in-progress checkpoint. It does not close Gate 3 or claim that
the high-level `Pdf` facade emits visible text yet.

## Completed in this checkpoint

- All package manifests use the immutable `roc-lang/unicode` 3.0.0 release
  instead of a sibling checkout. The imported artifact was built with the same
  pinned Roc nightly as this repository.
- `KernelFacadeScenes.Plan` retains its validated `KernelScene.Plan`, so later
  stages consume the earlier stage's facts rather than rebuilding scene state.
- `KernelFacadeOutput` composes the validated scene through font planning,
  subsetting, resource use, PDF text, content streams, page objects, font
  objects, tagged structure, and deterministic emission.
- Synthetic fragment evidence emits a non-blank, 9,888-byte PDF through that
  output composition. Its diagnostic work record was
  `1,2,6,7,6716,4,2,6,172,4,316,9,20,9888` with 1,164 allocations. These are
  observations only, not accepted test baselines.
- `KernelFacadePipeline` connects normalized authoring through semantics,
  shaping, line layout, pagination, text materialization, fragments, scenes,
  and output. A focused evidence executable records the current runtime
  boundary without adding a passing snapshot case prematurely.

The built-in font is imported as `List(U8)` with Roc's byte-list `import`
syntax. It is not embedded as Roc source.

## Confirmed blocker

The smallest current real-authoring example is one paragraph:
`Café PDF generation in pure Roc.` Semantics and shaping complete, but entering
the line-layout stage traps with:

```text
[ROC CRASHED] Integer subtraction overflowed
```

The staged probe gives this boundary:

| Stage | Result | Observed work prefix |
| --- | --- | --- |
| Semantics | succeeds | `0,1,0,0,0,0,0,0,0` |
| Shape | succeeds | `1,1,1,0,0,0,0,0,0` |
| Lines | integer-subtraction trap | no result |
| Pages through output | not reached | no result |

This places the first failure in `KernelFacadeLines`/`KernelLineLayout`, before
pagination, scene construction, font subsetting, or PDF emission. Blank PDFs
from older structural snapshot fixtures are not evidence that the visible-text
pipeline succeeds.

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

Stages `0` and `1` succeed. Stage `2` reproduces the subtraction overflow. The
full path reproduces it with:

```sh
./facade-output-probe visible 0
```

The repository uses the dev backend for functional and allocation evidence;
do not switch this probe to `--opt=speed`.

## Next steps

1. Add a minimal shape-to-line diagnostic using the same source and call
   `KernelLineLayout.Plan.build_simple` directly. This will distinguish the
   core line breaker from the facade batch wrapper.
2. Identify the exact unchecked subtraction and fix the violated invariant at
   its owning stage. Invalid input or bounds must return a stable typed error;
   the fix must not use saturation or silent fallback.
3. Add an atomic negative case for the invariant and run its exact allocation,
   deterministic-work, and snapshot evidence through `./scripts/test.py`.
4. Re-run the real-authoring visible path. Once it succeeds, remove or convert
   the temporary stage-probe API and add a dedicated non-blank PDF fixture with
   reviewed allocation and work baselines.
5. Complete the Gate 3 output evidence: structural font/CID/ToUnicode/content
   assertions, PDFBox extraction, renderer checks, and independent PDF
   validation oracles required by the roadmap.
6. Wire the completed pipeline into the Standard-profile `Pdf.to_bytes` facade,
   keeping advanced object details out of the common path.
7. Audit every Gate 3 roadmap row, including caller-font behavior and
   performance bounds, before adding the Gate 3 closure record.

Do not accept allocation or PDF snapshot changes mechanically while completing
these steps. Each change needs an architectural cause and an explicit review.
