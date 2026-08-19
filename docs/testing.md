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

The driver applies `roc fmt --check`, `roc check`, and `roc test` to the
validation inventory in `tests/spec.json`, builds each distinct fixture app
once, and executes independent evidence cases in parallel. Fixture builds also
obey `toolchain.max_build_workers` to avoid cold-cache memory pressure. Logs are
written under `.roc-pdf-tmp/logs/`.

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
