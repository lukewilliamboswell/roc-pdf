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
each distinct fixture app once, and executes independent evidence cases in
parallel. Fixture builds also obey `toolchain.max_build_workers` to avoid
memory pressure. Logs are written under `.roc-pdf-tmp/logs/`.

Every `roc check`, `roc test`, or `roc build` re-checks the whole package
(about 4 s and 4 GB per root), so the driver plans validation to give each
root exactly one compiler invocation (`plan_validation` in `scripts/test.py`):

- `package/all.roc` is tested; it exposes every package module, so it runs
  every package `expect`. `package/main.roc` is checked.
- An application root's `roc test` would re-run every package `expect` too,
  so application roots are tested only for the expects in their own file and
  in the same-directory modules they import: every root whose own file has
  expects is tested, then, per directory (family), the fewest roots whose
  local import closures reach the remaining expect-bearing modules.
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
that no root reaches is not tested (`tests/shaping/GsubFixture.roc` is
currently such a module). See `docs/performance/test-suite-speed.md` for the
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
(`docs/performance/lowering-uniqueness.md`). Without the cache each fixture
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
proves nothing about its property, so a separate lane executes each one:

```sh
./scripts/fuzz.py
```

That builds every target with `roc build --fuzz` for libFuzzer coverage
instrumentation and runs a bounded campaign against its seed corpus. A crash, a
timeout, or a memory-limit breach fails the run. Use `--targets NAME`
(repeatable) to select one, and `--runs N` for a longer local campaign:

```sh
./scripts/fuzz.py --targets jpeg_inspector_mutation --runs 200000
```

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

## Family fixtures

Related runtime cases share one directory containing `main.roc`, `Fixture.roc`,
and a deterministically ordered `cases.jsonl`. Each schema-version-1 JSONL row
has exactly `name`, `schema_version`, and `case`. The `case` value is decoded by
`Json.parse` into a closed, family-specific Roc tag union; malformed or unknown
cases fail explicitly.

To add a family case:

1. Add its typed case tag and fields to `main.roc` and implement the scenario
   through the shared fixture pipeline.
2. Add one ordered row to `cases.jsonl`.
3. Add the matching case to `tests/spec.json`, including its snapshot,
   dimensions, work counters, allocation baseline, retention contract, and
   ordered `validators` list.
4. For a new family, register its root and JSONL file in the top-level
   `families` list.

The harness requires a one-to-one match between JSONL rows and spec cases,
passes only `schema_version` and `case` to Roc, builds the family root once,
and reuses that executable for every row. Public-surface fixtures import
`package/main.roc`; internal evidence fixtures import `package/all.roc`.

Validator, preflight, and post-update IDs are resolved through the allowlisted
registry in `scripts/harness_validators.py`. Unknown or duplicate IDs are
schema errors; routing is never inferred from filenames, directories, or
dimension flags.

The test-only Zig platform supports macOS AArch64 and Linux x86-64. It derives
from `roc-platform-template-zig` and retains the upstream notice in
`tests/platform/NOTICE`.
