# Test-suite speed

This record covers the changes that cut a cold `./scripts/test.py` run from
about six minutes to about three and a half without removing any evidence.

## Where the time went

Every `roc check`, `roc test`, and `roc build` of a root re-checks the whole
package. With the pinned compiler (`nightly-2026-09-30-df1f747`) that costs
about 3 to 5 s and 4 to 5.2 GB resident per root, warm cache or not: a second
`roc check package/all.roc` still took 2.9 s and 3.9 GB. Before this change the
harness ran `roc check` and `roc test` on each of the 86 validation roots, so
the package was checked 172 times before the 55 fixture builds checked it again.
Each application root's `roc test` also re-ran every package `expect`, which
`package/all.roc` already runs.

## Changes

1. **Byte-imported package data.** `package/KernelBuiltInFont.roc` was a
   generated 166,300-element `List(U8)` literal (166k lines), and
   `package/KernelSrgbProfile.roc` carried a 3,024-element literal. Both now use
   `import "<file>" as ... : List(U8)` of `package/RocPdfSans-Regular.ttf` and
   `package/sRGB2014.icc`, which moved into `package/` so the imports never
   escape the package. `roc bundle` omits byte-imported files
   (roc-lang/roc#11907), so `scripts/bundle.sh` reads the byte imports from the
   package modules and names the files on the command line, and
   `scripts/test_bundle_consumer.py` checks that the archive carries each file
   byte-identical to its provenance record. This removed about 0.1 to 0.5 s and
   0.1 to 0.5 GB per root: small, because checking the package, not parsing the
   literal, dominates.
2. **One test root per family.** `plan_validation` in `scripts/test.py` tests
   `package/all.roc` for the package expects, every root whose own file has
   expects, and per directory the fewest roots whose local import closures reach
   the remaining expect-bearing modules. The log records which modules each test
   root covers, and a failing test names them.
3. **No duplicated checks.** `roc test` and `roc build` report the same errors
   and warnings as `roc check`, with the same exit codes. This was verified
   with the pinned compiler: exit 1 for an injected type error in `main!`, in an
   unused definition in a local module, and inside an `expect`, and exit 2 with
   the identical diagnostic for an unused variable in a root, in a local
   module, and in a package module (the last via `package/all.roc`). A tested
   root is therefore not also checked, and a fixture root that no test needs is
   checked by its `roc build --no-cache` evidence build, which the harness
   fails on any non-tolerated warning exactly as it fails a check.
4. `roc fmt --check` runs as one batch per worker instead of 226 processes.
5. The default worker count now assumes 5 GB per worker instead of 2 GB.

The fixture builds keep `--no-cache` (roc-lang/roc#11826). The 55 fixture
programs were not merged: each case's allocation and allocated-bytes baseline
belongs to one program, and the lowering of shared package procedures depends
on the program they are compiled into
(`docs/performance/lowering-uniqueness.md`), so merging programs could change
what every case measures.

Validation now runs 40 `roc test` roots, 16 `roc check` roots (package
`main.roc`, examples, fuzz targets without their own test, and the two
platforms), and 6 `fmt` batches; 30 fixture roots are checked by their builds.

## Measurements

Full cold-cache runs (`--allocation-baselines`, a fresh `XDG_CACHE_HOME`, 6
workers, fixture builds capped at 4) on a 16-thread, 32 GB Linux machine. Two
runs of each. Peak memory is the largest sum of resident set sizes of the
harness's concurrent `roc` processes, sampled every 0.5 s.

| | Before | After |
| --- | ---: | ---: |
| Wall time | 370 s, 345 s | 195 s, 205 s |
| Preflight | 15 s, 5 s | 5 s, 4 s |
| Validation phase | 242 s, 228 s | 81 s, 88 s |
| Fixture builds (55) | 97 s, 96 s | 93 s, 97 s |
| Case execution (295) | 16 s, 16 s | 16 s, 16 s |
| `roc check` tasks, CPU-s | 86, 760 / 722 | 16, 187 / 232 |
| `roc test` tasks, CPU-s | 86, 600 / 587 | 40, 217 / 239 |
| `roc build` tasks, CPU-s | 55, 380 / 377 | 55, 366 / 380 |
| Peak `roc` resident sum | 27.2 GB | 24.5 GB |

Per-root memory did not fall materially, so the worker count cannot rise: runs
with `--jobs 8` and `--jobs 10` had a `roc check` killed for memory during
validation. Six workers remain the ceiling on 32 GB, and the previous default
(2 GB per worker, 14 workers here) would have been killed the same way. The
fixture builds are now the longest phase.

## Allocation baselines

A cold `--compare-baselines --baseline-report` run over all 295 cases
reported zero differences: every allocation count, allocated-bytes value, and
work counter is identical, so no baseline changed. Both the literal and the
byte import are compile-time `List(U8)` constants that the dev backend emits
as static data; neither is materialized inside the `before_fixture_main`
measurement boundary, so the representation change is invisible to it.
