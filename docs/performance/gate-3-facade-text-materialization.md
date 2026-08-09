# Gate 3 facade text materialization

## Boundary

`KernelFacadeText` is the committed-materialization boundary between speculative
line/page layout and the final scene. It consumes validated shaped runs, cached
line ranges, visual rows, and page placements. It produces one dense final text
run for every painted line plus one for each painted list label.

This split is required by tagged-text ownership: every final run is painted and
owned exactly once. A shaped paragraph that wraps across lines therefore cannot
remain one repeatedly placed run. The stage copies each source cluster and glyph
to exactly one final line run, preserves the occurrence-relative Unicode range,
and assigns a new dense run identity in page paint order.

The bullet-body horizontal offset is retained by `KernelFacadeLines` and passed
through `KernelFacadePages.Row`. Materialization consumes that explicit layout
fact. It does not recover indentation from the theme, label presence, glyph
geometry, or coordinates.

## Representation and ownership

The result contains flat `Text.Store` buffers, a parallel dense style list,
page-to-run ranges, and one compact placement per final run. Page and run ranges
follow canonical page paint order. No recursive line, run, or scene object is
allocated.

Clusters retain source ranges. Their glyph-reference ranges are rewritten into
the final flat glyph-index buffer, and referenced glyph records are appended to
the final flat glyph buffer. The completed stage verifies that final cluster,
glyph-index, and glyph counts exactly equal the shaped input counts. Wrapping
changes run boundaries but neither duplicates nor drops glyph payload.

The constrained facade shaper currently produces no substitution or
transformation records. Materialization rejects a run carrying either kind of
advanced evidence instead of silently dropping it. The advanced shaped-run path
will need an explicit range-aware auxiliary-evidence transfer before it can use
this facade adapter.

All output lists reserve their exact validated counts. One preliminary dense
paint-request buffer separates page/row traversal from payload transfer. The hot
cluster/glyph loop then keeps all six output buffers local and unique for the
whole stage. The plan does not retain the speculative line list, page plan, or
original shaped store. Callers that retain those immutable inputs may increase
live memory and ARC work, but do not change the result.

An initial helper-shaped implementation returned all six lists through a
fallible function once per line. Under the pinned optimizer this caused nine
allocations per final line despite exact capacity reservation: the matched
x1000 case used 18,080 allocations and x10000 used 180,085. Flattening the hot
transfer into one dense loop reduced the materialization delta to eight fixed
allocations at both scales. The rejected measurements are not baselines.

## Bounds and work evidence

For `P` pages, `L` visual line placements, `R` final runs, `C` clusters, `I`
glyph references, and `G` glyph records, worst-case work is
`O(P + L + R + C + I + G)`. Every loop advances a dense scalar cursor. There is
no search, sorting, source-text rescan, or per-line scan of unrelated shaped
runs.

The exact deterministic counters are page visits, visual placement visits, run
writes, cluster visits, glyph-index visits, and glyph writes. Typed limits bound
all six output dimensions. Range, identity, source-continuity, glyph-reference,
offset-overflow, and unsupported-evidence failures are atomic and produce no
plan. Dense glyph ownership is an input fact already established by shaping;
materialization preserves it rather than reconstructing it.

The focused phase scenario constructs a flat typed prepared boundary with six
clusters per shaped source run and two final lines per run. A matched control
constructs and observes exactly the same prepared input without materializing
it. This isolates the stage's allocation delta while keeping the harness's
ordinary reset immediately before fixture main. The table preserves the former
speed-backend representation review and is not a current baseline or a command
to rerun. Current validation uses the pinned dev backend and the exact matching
scenarios in [`tests/spec.json`](../../tests/spec.json); their mode transition
is reviewed in [the dev-backend rebaseline](dev-backend-allocation-rebaseline-2026-08-09.md).

| Scenario | Control allocations | Materialized allocations | Stage delta | Planned pages | Visual rows/final runs | Clusters/glyphs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| x1000 | 72 | 80 | 8 | 32 | 2,000 | 6,000 |
| x10000 | 77 | 85 | 8 | 313 | 20,000 | 60,000 |

The current dev-backend control/materialization pairs are 54/62 allocations at
x1000 and 59/67 at x10000. Their unchanged eight-allocation stage delta and
deterministic work vectors, rather than the historical absolute counts above,
are the accepted evidence.

The generated blank structural snapshot remains byte-identical in the control
and materialized cases. Every line, cluster, glyph reference, and glyph counter
scales exactly tenfold while page count follows fixed 64-row page ranges. The
blank snapshot deliberately isolates this phase-specific boundary; visible
facade output belongs to the final whole-pipeline evidence slice.
