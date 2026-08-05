# Gate 0 optimized scenario protocol

## Pinned configuration

- Scenario schema: 1
- Roc-to-host metrics protocol: 1
- Roc toolchain selector: `nightly-2026-August-04-1cb06bc`
- Roc compiler identity: `Roc compiler version debug-8d15ae62`
- Roc optimization: `speed`
- Zig version: 0.16.0
- Zig host optimization: `ReleaseFast`
- Supported baseline targets: `arm64mac` and `x64musl`

The harness rejects a toolchain, optimization mode, protocol, target, counter
shape, or `.roc-version` mismatch before accepting scenario results.

## Measurement ABI and ownership

A compiled scenario returns one fixed record containing owned PDF bytes and a
flat `List(U64)` whose positions are named by `tests/spec.json`. The host emits
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
Both optimized runs retain the exact one-allocation result. A direct `while`
loop reports the independently checked work:

| Scenario | Passes | Byte visits | Roc allocations |
| --- | ---: | ---: | ---: |
| `placeholder PDF x1` | 1 | 431 | 1 |
| `placeholder PDF x4` | 4 | 1,724 | 1 |

This makes a work-only regression observable even when bytes and allocations
are unchanged. The harness self-test injects one extra allocation and one extra
work unit independently and proves that both reports are rejected.

The values above were measured on `arm64mac`. The same one-allocation baseline
is declared for the 64-bit `x64musl` ABI and is enforced when the suite runs on
that host; Gate 0 should not be reported as cross-host evidenced until that run
is retained in CI.

## Complexity and retention

Parsing and comparing metrics is linear in the small fixed counter count.
Snapshot hashing remains linear in output bytes. Each scenario process releases
its Roc result before the host leak check, and each executable lives only for
its case. No protocol value enters the production package or changes the
generated output representation.
