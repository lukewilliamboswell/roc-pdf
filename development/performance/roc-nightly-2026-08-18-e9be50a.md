# Roc nightly 2026-08-18 verification

Date: 2026-08-19

## Decision

The package moves from `nightly-2026-08-16-23452ea` to the official
`nightly-2026-08-18-e9be50a` release. This is a compiler-only upgrade. The
package behavior, deterministic work counters, retention evidence, allocation
baselines, and generated PDF snapshots are unchanged.

## Controlled run

- Host and execution target: Linux x86_64, `x64musl`.
- Roc optimization: `dev`; Zig 0.16.0 host built with `ReleaseFast`.
- Measurement boundary: `before_fixture_main`.
- Official Linux x86_64 archive SHA-256:
  `c4aba5691c12bc3b29b3855c35306b15683637ed338af692fe1083354a2e602f`.
- Command: `./scripts/test.py --jobs 16`, with `ROC` selecting the extracted
  official compiler.

The complete 561-step run passed all 217 evidence cases. All allocation
baselines, dimensions, deterministic work counters, retention checks,
structural validators, and PDF snapshot bytes matched without rebaselining.
The run built 44 distinct fixture applications, with every JSONL family root
built exactly once.
