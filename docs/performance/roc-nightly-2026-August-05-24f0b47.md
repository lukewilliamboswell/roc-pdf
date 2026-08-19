# Roc nightly 2026-08-05 bulk re-baseline

## Decision

The package moves from `nightly-2026-August-04-1cb06bc` to
`nightly-2026-August-05-24f0b47`. This is a compiler-only change: no package
implementation, scenario, target, optimization, snapshot, or deterministic
work expectation changed during the comparison.

The new compiler has a known ARC mode-specialization regression tracked as
[roc-lang/roc#10635](https://github.com/roc-lang/roc/issues/10635). The
allocation increases below are accepted as one reviewed toolchain delta, not
as feature-caused representation changes. The issue identifies `24f0b476` as
the first bad merge and the requested nightly as the affected release.

## Controlled configuration

- Host: macOS 26.3.1 build 25D771280a, Apple Silicon.
- Roc optimization: `speed`.
- Zig host: 0.16.0, `ReleaseFast`.
- Measurement boundary: `before_fixture_main` for every scenario.
- Targets: native `arm64mac` and cross-compiled `x64musl`.
- Linux execution: the same host, using
  `alpine@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce`
  (`linux/amd64`). Container startup and emulation are outside Roc's allocation
  counter, so Linux timing is not used as performance evidence.
- Old official macOS Apple Silicon archive SHA-256:
  `ea55d8a5f00f7067711810636a8a47cb1bd9438e65091a8905b99c113c78821b`.
- New official macOS Apple Silicon archive SHA-256:
  `8d4b2c81e95e03f8eb5a28a50f5cad791b4acb86702ae7d1f13ca2df0d4bf947`.

Both official compilers reported the exact identity named by their nightly
tag. The full suite was first run unchanged under the old compiler on each
target. `--compare-baselines` then ran every case under the proposed compiler,
continued after allocation differences, and still enforced snapshots,
retention evidence, deterministic work, and structural checks.

To isolate the nightly interval, Roc revision
`c5d662a07287e6d4c7b280fe7760124e89a5af9f`, the immediate parent of the
first-bad merge named by #10635, was also built from source with
`ReleaseFast`. Representative probes reproduced the old nightly counts exactly
before those same probes changed under `24f0b476`.

## Full allocation distribution

The old and new counts below were identical on `arm64mac` and `x64musl`.

| Scenario | Old | New | Delta | Deterministic work |
| --- | ---: | ---: | ---: | --- |
| structural-kernel blank PDF | 0 | 0 | 0 | unchanged |
| structural-kernel balanced 4,096-page PDF | 113,793 | 134,274 | +20,481 | unchanged |
| structural-kernel balanced index plans | 117,904 | 138,385 | +20,481 | unchanged |
| structural-kernel linked outline plan | 113,797 | 134,278 | +20,481 | unchanged |
| structural-kernel stable resource names | 113,797 | 134,278 | +20,481 | unchanged |
| structural-kernel bulk lexical values x2,048 | 113,797 | 134,278 | +20,481 | unchanged |
| structural-kernel bulk lexical values x4,096 | 113,797 | 134,278 | +20,481 | unchanged |
| structural-kernel one-block dynamic DEFLATE | 114 | 120 | +6 | unchanged |
| structural-kernel stateful dynamic DEFLATE | 126 | 132 | +6 | unchanged |
| Placeholder PDF x1 | 1 | 1 | 0 | unchanged |
| Placeholder PDF x4 | 1 | 1 | 0 | unchanged |
| tagged-visual minimal tagged visual PDF | 662 | 662 | 0 | unchanged |
| tagged-visual million-command image reuse | 129 | 136 | +7 | unchanged |
| structural-kernel unchanged-resource retention | 194 | 200 | +6 | unchanged |

All PDF snapshots remained byte-identical. Their independent xref, length,
page, tagged-structure, and resource checks passed. The retention fixture also
kept its exact three backing references, 4,096-byte source offset, 64-byte
owned capacity, zero shared copied bytes, and 64 owned copied bytes.

## Outlier investigation

The 4,096-page family shares the same page-generation pipeline, so the common
20,481 increase is one outlier shape rather than six independent feature
changes. A separately compiled 2,048-page probe changed from 56,935 to 67,176,
a delta of 10,241. The two results are exactly:

```text
delta = 5 * page_count + 1
```

`KernelStructure` consumes a builder record whose nested lists are updated
through retained helper calls while adding pages. That is the aggregate-field
ownership shape described in #10635: after the new SpecConstr work budget
retains calls, ARC does not request the owned mode-specialized variant that
would enable existing owned-only field takes. The unchanged work vectors and
bytes rule out extra pages, objects, edges, references, or emission work.

The immediate-parent compiler reproduced 113,793 allocations at 4,096 pages
and 56,935 at 2,048 pages. It also reproduced 126 allocations for stateful
DEFLATE and 129 for the million-command tagged-visual case. The proposed compiler
changed those representatives to 134,274, 67,176, 132, and 136 respectively.
This directly isolates all three observed delta shapes to merge `24f0b476`,
rather than merely correlating them with the wider nightly interval.

The `+6` cases and the tagged-visual `+7` case are fixed shifts rather than input-
proportional changes. The million-command case still records only 136 total
allocations for one million commands, and the two lexical scales remain equal.
They therefore do not hide a new per-byte, per-token, or per-command package
allocation. The immediate-parent probes above confirm that the fixed shifts
also begin at the same first-bad merge. This establishes the same compiler
change boundary, but does not by itself prove that the fixed shifts traverse
the page path's missing-owned-variant mechanism. There is no separate
feature-caused delta in this upgrade.

## Timing, memory, and ownership evidence

Native optimized executables were benchmarked on the controlled host after
three warmups. Page and tagged-visual results use ten samples; DEFLATE uses one hundred
because the case is short.

| Representative scenario | Old mean | New mean | Old peak RSS | New peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 4,096-page PDF | 1.589 s | 1.908 s | 6,750,208 B | 8,224,768 B |
| Stateful DEFLATE | 9.2 ms | 9.0 ms | not sampled | not sampled |
| Million-command tagged-visual | 175.0 ms | 172.3 ms | 187,809,792 B | 187,793,408 B |

The page-time and peak-RSS increase aligns with the linear allocation
regression and is not attributed to package work. The other representative
subsystems show no material runtime or retained-memory regression. Current
host instrumentation counts allocation events but does not report allocated
bytes or ARC increments/decrements, so this review makes no unsupported numeric
claim for those measures.

## Acceptance boundary

`.roc-version`, both target baselines in `tests/spec.json`, and the affected
performance records change atomically. The deterministic work vectors and PDF
snapshots do not change. `scripts/test.py --compare-baselines` remains a
report-only mode: it validates all other evidence, prints the complete delta
table, and exits unsuccessfully until reviewed baselines are updated.

This acceptance does not redefine the page-path allocation behavior as
desirable. The compiler issue remains open, and a future compiler containing a
fix must run this same bulk protocol; the expected allocation decreases will
then be reviewed rather than silently retained.
