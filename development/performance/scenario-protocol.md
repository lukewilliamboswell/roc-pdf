# contract-definition scenario protocol

## Pinned configuration

- Scenario schema: 2
- Roc-to-host metrics protocol: 1
- Roc toolchain selector and compiler identity: read solely from `.roc-version`;
  the harness requires `roc version` to report that exact release
- Default functional Roc optimization: `dev`
- Allocation-baseline Roc optimization: `dev`
- Zig version: 0.16.0
- Zig host optimization: `ReleaseFast`
- Supported baseline targets: `arm64mac` and `x64musl`

`./scripts/test.py` is the fast functional path: it validates bytes,
independent structural oracles, retention facts, and exact deterministic work
counters with `--opt=dev`. `./scripts/test.py --allocation-baselines` uses the
same pinned dev backend and additionally requires exact allocation counts.
`--compare-baselines` also remains on the dev backend and reports rather than
accepts allocation deltas.

The harness rejects a toolchain, protocol, target, counter shape, or
`.roc-version` mismatch before accepting scenario results. The allocation path
additionally rejects an optimization-mode mismatch.

## Measurement ABI and ownership

A compiled scenario returns one fixed record containing owned PDF bytes and a
flat `List(U64)` whose positions are named per scenario by `tests/spec.json`.
This permits each feature slice to report its actual deterministic operations
without widening the allocation-measurement ABI or mislabelling counters. The host emits
the PDF bytes unchanged, reports the counter values and allocation events in
one versioned line, and then decrements both lists. The metrics ABI contains no
strings, maps, closures, or per-counter records.

The host constructs command-line arguments before resetting the allocation
counter. It resets immediately before calling the Roc fixture entrypoint, so
the declared `before_fixture_main` boundary includes all Roc fixture work and
excludes Python, argument construction, host formatting, snapshot comparison,
and contract validation.

## Deterministic-work self-test

The protocol fixture emits the same 431-byte PDF at two declared input scales.
Both explicit allocation runs retain the exact one-allocation result under the
dev backend. The default path checks the same deterministic work without
treating its allocation count as a baseline. A direct `while` loop reports the
independently checked work:

| Scenario | Passes | Byte visits | Roc allocations |
| --- | ---: | ---: | ---: |
| `placeholder PDF x1` | 1 | 431 | 1 |
| `placeholder PDF x4` | 4 | 1,724 | 1 |

This makes a work-only regression observable even when bytes and allocations
are unchanged. The harness self-test injects one extra allocation and one extra
work unit independently and proves that both reports are rejected.

The CI matrix enforces these exact values on native `arm64mac` and 64-bit
`x64musl` runners. contract-definition cross-host evidence is accepted only when both jobs
succeed for the same commit.

## Complexity and retention

Parsing and comparing metrics is linear in the small fixed counter count.
Snapshot hashing remains linear in output bytes. Each scenario process releases
its Roc result before the host leak check, and each executable lives only for
its case. No protocol value enters the production package or changes the
generated output representation.
