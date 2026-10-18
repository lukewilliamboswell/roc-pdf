# Dev-backend allocation rebaseline

Date: 2026-08-09

This reviewed, atomic baseline update moves the scenario suite to the pinned
Roc dev backend selected by `tests/spec.json`. It is not a text-layout closure
record.

## Scope and method

The local `x64musl` allocation comparison ran all 63 scenarios with the pinned
`release-fast-64c9d73d` compiler, `--opt=dev`, Zig 0.16.0 ReleaseFast host,
and the declared `before_fixture_main` measurement boundary. Every snapshot,
structural oracle, retention fact, and deterministic-work vector matched.
The two new authored-facade scenarios measured 1,422 allocations for the
positive path and 98 for its line-run-limit atomic negative.

The expectation schema keeps the paired native-target records together. This
local text-layout work does not claim a new cross-platform performance result; its
accepted values retain the suite's existing target-parity contract and need
the normal supported-host CI confirmation before release evidence is claimed.

## Delta review

All 61 changed pre-existing baselines are allocation-only. No byte snapshot,
operation counter, retained-resource fact, or source implementation changed in
the rebaseline slice.

- The PDF kernel's page/index/object cases increased by 3 allocations (11 for
  the balanced index plan); the two DEFLATE cases and unchanged-resource
  retention each increased by one. Their identical work and output prove that
  object planning, compression traversal, and retained ranges did not change.
- Unicode analysis increased by one allocation at both scale points, while its
  input, scalar, grapheme, line-boundary, and script-run work remained exact.
- tagged-visual scene and image-reuse scenarios decreased by 20 allocations with the
  million-command direct-loop work vector unchanged.
- The text-layout authoring/facade families show consistent fixed-cost reductions
  (for example -18 for normalization/layout, -25 for font/shaping, and -14
  for fragment arenas). The unique-source cache reductions scale with the
  input count (-1,018 at 1,000 and -10,018 at 10,000), while its hash/probe/
  equality and retained-byte counters are exact. This is a backend allocation
  lowering change, not source deduplication or algorithmic work removal.
- Complete visible-text pipeline cases fall to 144 allocations from their
  former 306–318 values, with unchanged PDF bytes, font/subset sizes,
  ownership traversal, CID/Unicode checks, and extraction evidence.

The mixed small increases and broad reductions are therefore attributable to
the deliberate dev-backend measurement transition, not to an unreviewed
feature change. The exact changed values are the atomic records in
`tests/spec.json`; this document records the cause and the invariant evidence
used to accept them.

## Remaining boundary

This update enables exact dev-backend allocation checking for the current
suite. It does not complete text-layout, establish cross-platform allocation
evidence, or discharge the remaining roadmap capabilities.
