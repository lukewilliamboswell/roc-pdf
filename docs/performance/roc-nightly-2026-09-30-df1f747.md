# Roc df1f747 local-build allocation review

## Scope and pin

This change moves the pinned compiler from `nightly-2026-09-28-9927ba8` to a
local `ReleaseFast` build of roc-lang/roc commit `df1f747ebb`
(`roc version`: `release-fast-df1f747e`), 50 upstream commits later. The
September 28 nightly still crashes in places, so this build is used for now.

`.roc-version` reads `nightly-2026-09-30-df1f747`. **This is not a published
nightly tag.** It names the compiler commit in the `nightly-<date>-<commit>`
form that `scripts/test.py`, `scripts/bundle.sh`, and
`scripts/test_bundle_consumer.py` accept for a `release-fast-<commit>` build.
CI provisions the compiler by downloading the `.roc-version` tag from
roc-lang/nightlies, so `ci.yml`, `docs.yml`, and `release-candidate.yml` cannot
run until a nightly that contains `df1f747ebb` is published and the pin moves
to that real tag. This pin must not merge before then.

No source or formatting change is needed: `roc fmt --check` passes on
`package`, `tests`, `fuzz`, and `examples`.

## Measurement

Same method as the [September 28 record](roc-nightly-2026-09-28-9927ba8.md):
Linux x86_64 (`x64musl`), `--opt=dev`, the `before_fixture_main` boundary,
fixtures built with `--no-cache`, and `ROC=<build> XDG_CACHE_HOME=<empty>
./scripts/test.py --compare-baselines --baseline-report <report> --jobs 6`.
No elapsed-time claim is made.

- All PDF snapshots are byte-identical and all work vectors are unchanged.
- 255 of 264 cases change. Every change is in the
  [allocation comparison](roc-nightly-2026-09-30-allocations.csv).
- Allocations: 245 decrease, 10 increase, 9 are unchanged. The per-case delta
  ranges from -770 to +4 (median over changed cases: -4); -10.8% to +3.5%.
  The suite total falls from 5,562,613 to 5,556,358 (-0.11%).
- Allocated bytes: 154 decrease, 101 increase. The per-case delta ranges from
  -8,768,544 to +1,997,064 bytes (-18.9% to +19.0%). The suite total falls by
  32,927,866 bytes (-1.23%).
- Two cases exceed the 10% allocated-bytes ceiling against the old values:
  compact-builder authoring normalization x1000 and x10000 (+19.0%, +18.6%).

## Outliers investigated

Each was traced by recording every `roc_alloc`/`roc_realloc` size in a copy
of the test host and diffing the sequences from the two compilers.

**Compact builder: all four builder buffers are copied once (compiler
regression).** Every case built through `Document.builder(...)
.add_paragraphs(...)` then `.add_bullets(...)` gains 4 allocations and
77,899 bytes at x1000, 890,923 at x10000: compact-builder normalization and
the facade batch-shaping, cached line layout, row pagination, and semantic
planning cases. The new allocations are fresh copies of exactly the four
dense buffers at the `add_bullets` call (text sources: 24,088 bytes then a
growth realloc; block aux and block texts: 8,032 each; block tags: 1,011),
so the cost is one linear copy per document, not per block. Work counters
are unchanged and the copy does not repeat, so there is no super-linear
growth.

`ROC_LIR_DUMP=build_with_builder` shows the cause. The old compiler lowers
`add_bullets`'s record-destructuring parameter by increfing every field and
then decrefing the builder record before the appends, so each list is unique
at its append. The new compiler projects each field lazily at its use
(`ref.field ... incref`) and decrefs the record only after the final
`struct(...)`, so every list has two references at `append` and is copied.
Building the compiler at `19408eecdd` ("Fuse range iterator pipelines and
forward calls through procedure aliases", merged in #11811) reproduces the
+4; its parent `b3321c577f` does not. The package code already follows the
uniqueness rules in [lowering uniqueness](lowering-uniqueness.md) (the
builder is consumed once; no accumulator stays live), so this is recorded as
an upstream uniqueness regression rather than worked around. It should be
filed upstream and the baseline lowered again when fixed.

**Small fixed shifts: -1 allocation, +600 bytes.** Many small cases (UAX
atomic limits, resource-graph families at both x100 and x1000, tagged
million-command image reuse) change by exactly this. The trace shows one
small list near program start whose growth sequence changes: two fresh
allocations and three reallocs become four reallocs ending at a larger
capacity. It is identical at both scales, so it is a per-program constant.

**Tables invoice x500: -3 allocations, +1,997,064 bytes (+1.26%).** Invoice
x50 falls by 90,928 bytes. The trace shows the reallocation growth sequence
of one large list changes (new: 157,472 -> 314,936 -> 629,864 -> 1,259,720 ->
2,519,432 bytes); `allocated_bytes` counts every realloc's new size, so a
different geometric capacity schedule counts more bytes while doing three
fewer reallocs. The growth stays geometric, so the total stays linear.

**Linear decreases in production-visual.** Nested forms, masks, patterns,
and per-form opacity fall by up to 770 allocations and 8.8 MB (distinct mask
forms x64), growing with the scale, and the fixed-shape production-visual
families lose 1 to 138 allocations. No work counter changes.

## Baseline update

The report was applied to both `x64musl` and `arm64mac` in `tests/spec.json`.
The macOS values are Linux measurements, as before.

## Gates run with the new compiler

- `./scripts/test.py --jobs 6` from a fresh cache: all cases pass.
