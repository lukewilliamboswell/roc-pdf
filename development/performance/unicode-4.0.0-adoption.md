# text-layout `roc-lang/unicode` 4.0.0 adoption record

Date: 2026-08-14

This records the reviewed dependency bump from release `3.0.0` (commit
`f5cd8d6a9a345f0a589ed46625ee865e70f48e35`, asset
`ACj5ceJnEY6vaejuQArN1naVzcxeThATZrKYYgzJCZJ5.tar.zst`, 161,147 bytes,
SHA-256 `343e175400a2d5ca5c32cd47dbe9f81a517b2f6f6c2ec47024e615db0228fff9`)
to release `4.0.0`.

## Pinned 4.0.0 identity

- Tag `4.0.0` resolves to commit `b689986172679aa9fbdcd7890e3031a48b1c582f`.
- Immutable release asset
  `https://github.com/roc-lang/unicode/releases/download/4.0.0/3DGC3M4b2pxaRLg4i8cmxWkm2E2WbCPCLntQzf2mkbUV.tar.zst`,
  228,087 bytes, SHA-256
  `4343719be2d54e73dc1f138a4527d828220acb1f21b9f79d8a319a611fbc7930`
  (asset size and digest re-verified locally against the downloaded archive
  before adoption).
- The release is built and tested upstream with Roc
  `nightly-2026-08-08-195c9e7` — the identical compiler this repository pins
  in `.roc-version`.
- The dependency continues to report Unicode 17.0.0, UAX #9 revision 51,
  UAX #14 revision 55, UAX #29 revision 47, and the `ConservativeScxV1`
  script-itemization policy — identical to
  `conformance/normative-baseline.json`, so no normative pin changes and the
  registered `unicode_vectors` seam evidence remains valid unchanged.

## What changed upstream

A byte-level comparison of the extracted 3.0.0 and 4.0.0 bundles shows:

- Every module this package imports (`BidiClass`, `ByteRange`, `Grapheme`,
  `LineBreak`, `Scalar`, `Script`, `ScriptItemization`, `TextPosition`,
  `TextRange`, `UnicodeVersion`) is **byte-identical** across the releases.
- The only pre-existing file that changed is the package manifest
  (`main.roc`), which now exposes the three new modules.
- The release adds `Bidi` (UAX #9 revision 51 paragraph analysis and line
  reordering), `Case` (source-mapped Unicode 17 case conversion), `Word`
  (UAX #29 word segmentation), and their internal data modules
  (`InternalBidiProperties` was already present; `InternalCase`,
  `InternalCaseData`, `InternalWord`, `InternalWordData` are new).

`Bidi` and `Case` resolve the upstream blockers recorded in
`rtl-blocker.md` (`roc-lang/unicode#39`) and
`case-transformation-blocker.md` (`roc-lang/unicode#52`); their
adoption into output slices is separate reviewed work with its own evidence.

## Zero-delta verification

Because no imported module changed, the bump alone must not change any
snapshot byte, structural fact, work counter, or dev-backend allocation
count. This was proven, not assumed: the full `./scripts/test.py
--compare-baselines` suite (fmt/check/package tests, zig host build, and all
registered cases with byte-exact snapshots, structural validators, exact work
counters, and exact dev allocation baselines) passed against the pinned
`nightly-2026-08-08-195c9e7` compiler with **zero reported deltas** after
the pin change.
