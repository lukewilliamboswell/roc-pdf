# Testing and fixture development

Run all checks through the Python test driver:

```sh
./scripts/test.py
```

Set `ROC` to use a specific compiler executable, `--jobs N` to override the
hardware-aware worker count, or `--verbose` to mirror the detailed log:

```sh
ROC=/path/to/roc ./scripts/test.py --jobs 8 --verbose
```

The driver applies `roc fmt --check` to the validation inventory in
`tests/spec.json`, type-checks every root in it and runs every `expect`, builds
each fixture group application once (see [Family fixtures and fixture
groups](#family-fixtures-and-fixture-groups)), and executes independent
evidence cases in parallel, one process per case. Fixture builds obey
`toolchain.max_build_workers` and run as many at once as available memory
allows at 7 GB each; validation tasks share a memory budget of 4 GB per root
and 6 GB per group application. Logs are written under `.roc-pdf-tmp/logs/`.

To iterate on one group or case without the preflight and validation phases:

```sh
./scripts/test.py --quick --group layout
./scripts/test.py --quick --case "tables invoice x50" --compare-baselines
```

The Zig build installs the ordinary host into `tests/platform/targets/`
and the retention host into `tests/retention_platform/targets/`. It also
copies the pinned Linux startup object and libc archive into the retention
platform's generated target directory. Each platform's `inputs_dir` stays
inside its own directory, as required by the pinned compiler.

Every `roc check`, `roc test`, or `roc build` re-checks the whole package
(about 4 s and 4 GB per root), so the driver plans validation to give each
root exactly one compiler invocation (`plan_validation` in `scripts/test.py`):

- `package/all.roc` is tested; it exposes every package module, so it runs
  every package `expect`. `package/main.roc` is checked.
- An application root's `roc test` would re-run every package `expect` too,
  so application roots are tested only for the expects in their own file and
  in the same-directory modules they import: every root whose own file has
  expects is tested, then, per directory, the fewest roots whose local import
  closures reach the remaining expect-bearing modules. A group application's
  closure also follows its package edges into its family packages, whose
  expects its `roc test` runs; the families' own `package.roc` files are not
  roots.
- `roc test` and `roc build` report the same errors and warnings as `roc
  check`, with the same exit codes, so a tested root is not also checked, and
  a fixture root that no test needs is checked by its evidence build.
- Every other root (examples, fuzz targets, platforms) gets one `roc check`.
- `roc fmt --check` runs as one batch of files per worker.

The detailed log records the plan (`PLAN test <root> (checks it and runs
expects in ...)`, `PLAN check <root>`, `PLAN <root>: checked by its fixture
build`). A failing `expect` names its own file and line, and the driver adds
the test root and every module that root covers. A new expect-bearing module
needs no registration, but it is only run if some root imports it: a module
that no root reaches is not tested. (`tests/shaping/GsubFixture.roc` was such
a module until the shaping family's package made it part of the `core` group's
closure.) See `development/performance/test-suite-speed.md` for the
measurements.

Integration cases use the dev backend and require exact PDF snapshots,
dimensions, allocation baselines, deterministic work counters, retention
contracts, and explicit structural validators. Review allocation changes with:

```sh
./scripts/test.py --compare-baselines
```

After reviewing an intentional PDF change, update snapshots with:

```sh
./scripts/test.py --update-snapshots
```

Snapshot updates still require the exact allocation and work-counter baselines
in the same run. An allocation event is a call to `roc_alloc` or `roc_realloc`;
host setup, teardown, and family-case JSON decoding are outside the
`before_fixture_main` measurement boundary.

The test hosts report metrics protocol 2:

```text
ROC_METRICS protocol=2 allocations=N allocated_bytes=B work=W1,W2,...
```

`allocated_bytes` sums the size of every `roc_alloc` and the new size of every
`roc_realloc` inside the same boundary. It is deterministic for the pinned dev
backend. Each case records it per target beside `allocations`, and the harness
fails a case whose allocated bytes exceed the recorded value by more than 10%
(`ALLOCATED_BYTES_CEILING_TENTHS` in `scripts/test.py`). The ceiling exists to
catch quadratic copying: a list copied on every append adds one allocation
event per append, so the exact count grows linearly and can look reasonable,
while the copied bytes grow with the square of the list. Decreases and drift
inside the ceiling pass; a reviewed rebaseline lowers the recorded value. The
ceiling is checked wherever allocation baselines are (`--allocation-baselines`,
`--compare-baselines`, `--update-snapshots`), and from the same cold cache.
`--baseline-report` lists every case whose allocations, allocated bytes, or
work differ exactly, so a rebaseline can also lower ceilings that did not
fail.

Fixture executables are built with `roc build --no-cache`. With the cache, the
pinned compiler reused package procedures compiled for an earlier fixture
program in later ones, and a later program could then copy lists that it
updates in place when built alone: a case's allocation count and allocated
bytes depended on which fixtures were built before it and on the local cache
(`development/performance/lowering-uniqueness.md`). Without the cache each fixture
compiles exactly as a standalone `roc build --no-cache --opt=dev` does, so a
case can be reproduced outside the harness. The flag works around
roc-lang/roc#11826 and should be removed once that is fixed. Validation (`roc
check`, `roc test`) still uses the cache. Still measure a delta you intend to review from a
cold cache, as CI does, by running the full suite against an empty cache
directory:

```sh
XDG_CACHE_HOME="$PWD/.roc-pdf-tmp/cold-cache" ./scripts/test.py \
    --compare-baselines --baseline-report .roc-pdf-tmp/baselines.json
```

`--baseline-report` (with `--compare-baselines` or `--update-snapshots`) writes
each differing case's expected and observed metrics as JSON for review. It
never edits `tests/spec.json`: accepting a delta remains a deliberate, recorded
change with an identified cause.

## Static PDF/A-4 lanes

Every `Archive` snapshot declares the `pdfa4` validator
(`scripts/check_pdfa4_structure.py`), which re-derives the static profile
facts from the bytes. The external lanes run on demand, after
`scripts/provision_extended_tools.py` has laid down veraPDF, MuPDF, and the
vendored upstream corpus:

```sh
python3 scripts/check_pdfa4.py --cases           # Archive snapshots: zero failed checks
python3 scripts/check_pdfa4.py --standard-cases  # Standard snapshots: only deliberate omissions
python3 scripts/check_pdfa4.py --corpus          # upstream veraPDF PDF/A-4 corpus verdicts
python3 scripts/check_archive_renderers.py --pdfium-renderer PATH --mutool PATH
```

The veraPDF lane always passes the explicit `--flavour 4`. Parser warnings or
task exceptions in package output are failures. Corpus validator defects may
only be recorded in `conformance/verapdf-exceptions.json`, with an upstream
reference. The ledger must map every rule of the pinned profile
(`conformance/verapdf-pdfa4-rules.json`, extracted from the vendored
installer) exactly once; `scripts/check_contracts.py` enforces this.

## Property fuzz targets

The bounded property targets in `fuzz/` are evidence-only applications on the
content-addressed `roc-fuzz` platform. `./scripts/test.py` formats every
`fuzz/*.roc` source, checks every target, and tests the fewest targets that
reach every helper module's `expect`s, which run against the committed corpus. Compiling a target
proves nothing about its property, so a separate lane executes each one. It
has two modes.

The smoke mode is the default and is what every pull request runs:

```sh
./scripts/fuzz.py            # or: blueprint run fuzz
```

It builds every target with `roc build --fuzz` for libFuzzer coverage
instrumentation, then replays the target's seed corpus and 64 further inputs
from a fixed seed, with `--time=1` capping the workload at one second per
target. Targets build in parallel (`--jobs`, by default as many 6 GB builds as
memory allows) and run one at a time. Its purpose is that every target keeps building and its property keeps
executing between campaigns; it makes no claim about search coverage.

The campaign mode is the bounded search, 2000 executions per target by default:

```sh
./scripts/fuzz.py --mode campaign                        # or: blueprint run fuzz-campaign
./scripts/fuzz.py --mode campaign --targets jpeg_inspector_mutation --runs 200000
```

Pull requests run the smoke mode in the `Fuzz smoke` job of `ci.yml`, beside
the test job. `.github/workflows/fuzz.yml` runs the campaign daily and on manual dispatch, on the
default branch only; it never runs on a pull request.

In both modes a crash, a per-input timeout (`--timeout`, 10 s), a memory-limit
breach (`--memory-limit`, 2048 MB), or a target still running at the hard
deadline (60 s for a smoke run, 30 min for a campaign target) fails the lane.
Every selected target still runs, and each target's failing inputs are written
to `.roc-pdf-tmp/fuzz-artifacts/<target>/`, which `fuzz.yml` uploads when the
campaign fails. Reproduce one with `.roc-pdf-tmp/fuzz/<target> replay <input>`.

Seed corpora are copied into the ignored `.roc-pdf-tmp/fuzz-corpus/` before a
run, because libFuzzer writes newly interesting inputs back into the directory
it is given and must never own tracked files. The JPEG corpus is tracked under
`tests/assets/jpeg-fuzz-corpus/` and regenerated by
`scripts/build_jpeg_fuzz_corpus.py`; the font targets are seeded from the faces
in `vendor/fonts/` and `tests/assets/`.

A target's corpus is what decides whether its property is exercised at all. An
inspector reached only by raw byte mutation will spend an entire campaign in
its reject paths unless valid inputs are seeded, leaving the accept-path
invariants unevaluated.

Minimized reproductions are retained as `fuzz_seed` assets under `tests/assets/`
with provenance, and promoted to atomic regression tests beside the code they
exercise.

## Family fixtures and fixture groups

Every evidence case belongs to a case family. The only exception is the
retention probe, which runs on its own platform. A family is a local package
in its own directory under `tests/`:

- `package.roc` exposes `Cases`. Public-surface families depend on
  `package/main.roc` and internal evidence families on `package/all.roc`;
  one directory, and one program, never mixes the two.
- `Cases.roc` holds the family's closed `Case` tag union and its `run`
  dispatch.
- `cases.jsonl` is a deterministically ordered file. Each schema-version-1
  row has exactly `name`, `schema_version`, and `case`.
- `Fixture.roc` and any other modules hold the shared scenario pipeline.

Families run in fixture groups. `tests/groups/<group>.roc` is generated from
`tests/spec.json`, and the driver refuses a stale or unlisted copy. It
decodes one argv envelope,
`{"case":{"<FamilyTag>":<row case>},"schema_version":2}`, into the union of
its families' `Case` types and checks that it round-trips canonically.
Malformed or unknown cases fail explicitly. It then resets the allocation
counters and calls the family's `run`. The family tag is the PascalCase of
the family name. Each case still runs in its own process. The harness
builds each group once.

To add a family case:

1. Add its typed case tag and fields to the family's `Cases.roc` and
   implement the scenario through the shared fixture pipeline. Pass runtime
   guards as typed fields (for example `context : U64`). A payload-less
   case, or a constant computed in a `match` arm, can be evaluated at
   compile time and measure nothing. A JSON-decoded `Str` field does not
   allocate like an argv string; see
   [fixture grouping](performance/fixture-grouping.md).
2. Add one ordered row to `cases.jsonl`.
3. Add the matching case to `tests/spec.json` with its `family`, snapshot,
   dimensions, work counters, allocation baseline, retention contract, and
   ordered `validators` list. The snapshot lives in the family directory.

To add a family:

1. Create `tests/<family>/package.roc`, `Cases.roc` and `cases.jsonl`.
2. Add `{"name": "<family>", "group": "<group>"}` to `families`.
3. Run `./scripts/test.py --write-groups`.
4. Keep each group's build under 7 GB peak RSS. Facade families cost 5 to
   6 GB alone and kernel families 2.5 to 3 GB. Check with
   `/usr/bin/time -v roc build tests/groups/<group>.roc --opt=dev --no-cache`.

Before landing a change to group membership, run the equivalence modes on
the affected groups from an empty `XDG_CACHE_HOME`. Each must report no
exact difference:

```sh
./scripts/test.py --quick --group <group> --compare-baselines --baseline-report group.json
./scripts/test.py --quick --group <group> --isolate --compare-baselines --baseline-report isolate.json
./scripts/test.py --quick --group <group> --group-mode perturb --compare-baselines --jobs 2
./scripts/test.py --quick --group <group> --group-mode inject --compare-baselines
```

`--group-mode inject` must pass with exactly one extra allocation in every
grouped case. `./scripts/test.py --list-groups` lists the groups and their
families.

The harness requires a one-to-one match between JSONL rows and spec cases.

Validator, preflight, and post-update IDs are resolved through the allowlisted
registry in `scripts/harness_validators.py`. Unknown or duplicate IDs are
schema errors; routing is never inferred from filenames, directories, or
dimension flags.

The test-only Zig platform supports macOS AArch64 and Linux x86-64. It derives
from `roc-platform-template-zig` and retains the upstream notice in
`tests/platform/NOTICE`.
