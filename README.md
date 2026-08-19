# roc-pdf

An early-development pure [Roc](https://www.roc-lang.org/) package for
deterministic PDF 2.0 generation.

The package offers a usable public authoring path under the `Standard`
profile: `Pdf.to_bytes`, `Pdf.to_bytes_with`, and `Pdf.to_chunks_with` all
produce deterministic tagged PDF 2.0 output, and the buffered and chunked
forms are byte-identical. The built-in theme supports title, heading,
paragraph, and bulleted-list constructors, with either the packaged face or
caller-registered faces selected through `Theme` — including a finite ordered
multi-face policy with per-cluster coverage selection. It does not read, edit,
or repair PDFs, and unsupported requests return typed errors rather than
producing blank output, substituting fonts, outlining text, or rasterizing
content.

This is not a PDF/A-4 or PDF/UA-2 package. `Archive` and `AccessibleArchive`
deliberately return capability errors, so do not make archival or
accessibility-conformance claims from it. Automatic hyphenation is not
accepted, and the convenience shaping path covers a declared script set;
right-to-left and case-transformation output are available at the advanced
integration boundary rather than through the one-import facade.

The package exposes the high-level `Pdf` facade plus the advanced conceptual
`Document`, `Semantics`, `Layout`, `Scene`, `Text`, `Font`, `Image`, `Color`,
`Metadata`, `Encode`, `Conformance`, and `Theme` boundaries. PDF object,
lowering, and serialization internals are not public.

The current candidate scope is recorded in [the 0.1.0-rc1 release
notes](docs/releases/0.1.0-rc1.md). text-layout is closed; its aggregated evidence
is recorded in the [text-layout closure
review](docs/performance/text-layout-closure.md).

## Design

- [Architecture](architecture.md)
- [Feature roadmap](feature-roadmap.md)

## Requirements

- Python 3
- Zig 0.16.0
- The Roc nightly pinned in [`.roc-version`](.roc-version), available as `roc` on `PATH`

## Development

Run all checks through the Python test driver:

```sh
./scripts/test.py
```

Set `ROC` to use a specific compiler executable:

```sh
ROC=/path/to/roc ./scripts/test.py
```

The driver prints timestamped, color-coded status and one global step counter
across validation, fixture builds, and evidence cases. Complete command output
is retained in a plain-text `.roc-pdf-tmp/logs/` file with a timestamp on every
line. The validation inventory in
`tests/spec.json` applies `roc fmt --check`, `roc check`, and `roc test` to every
declared Roc source by default; exceptions require an explicit action-specific
skip and reason. Validation, distinct fixture builds, and independent case
processes use a hardware-aware worker count based on CPU affinity and memory,
up to sixteen workers; use `--jobs N` to override it or `--verbose` to mirror
the detailed log to the console.

Fixture builds additionally obey `toolchain.max_build_workers` from
`tests/spec.json`. This independently reviewed cap prevents several cold,
memory-heavy codegen processes from exhausting the host while validation and
runtime cases retain their requested parallelism.

The spec-driven integration cases in [`tests/spec.json`](tests/spec.json) build
real Roc applications with `--opt=dev` by default. This fast path requires
exact PDF snapshots, structural checks, and deterministic work counters. The
test-only Zig platform supports macOS AArch64 and Linux x86-64.

Exact Roc allocation baselines remain an explicit check, but use the same dev
backend so contributors are never required to wait for `--opt=speed` builds:

```sh
./scripts/test.py --allocation-baselines
```

Use `--compare-baselines` to review dev-backend allocation deltas before
deliberately updating the specification. Each test application's `main!`
receives `List(Str)` process arguments and returns the generated `List(U8)`
PDF; the host writes those bytes to stdout and reports Roc allocation events
separately.

Public contract examples under `examples/` are formatting- and compile-checked
by the same driver. Runtime structural-kernel behavior is exercised by package tests and
the dev-backend structural fixtures.

Integration cases are grouped by capability under `tests/`. Related runtime
cases should use one family `main.roc`, one shared `Fixture.roc`, and an ordered
`cases.jsonl`. Each schema-version-1 JSONL row has exactly `name`,
`schema_version`, and `case`; `case` is the JSON representation of the closed,
family-specific Roc tag union decoded by `Json.parse`. Add the row's snapshot,
dimensions, work counters, allocation baseline, retention contract, and
an explicit ordered `validators` list to `tests/spec.json`, then register the family
app and JSONL file in its top-level `families` list. The harness checks that
every JSONL name has exactly one matching spec case, passes only
`schema_version` and `case` to Roc, builds the app once, and runs its rows in
parallel against that executable.

Validator IDs are resolved through the allowlisted registry in
`scripts/harness_validators.py`; the harness never selects validators from a
source filename, directory, or dimension flag. The top-level
`preflight_checks` and `post_update_checks` lists use the same pattern for
checker self-tests. Unknown or duplicate IDs are schema errors, and spec data
cannot import or execute an arbitrary Python module.

A directory may still contain several genuinely distinct app roots and
snapshots plus a shared fixture module.
Public-surface apps import `package/main.roc`; internal evidence apps import the
repository-only `package/all.roc`. Every case, source, snapshot, and expected
allocation count is registered in [`tests/spec.json`](tests/spec.json).

An allocation event is a call to either `roc_alloc` or `roc_realloc`; host setup and teardown are
not counted. To accept intentional PDF output changes after reviewing them, run:

```sh
./scripts/test.py --update-snapshots
```

Snapshot update mode also requires the exact allocation and named work-counter
baselines in that same run. Family JSON decoding occurs before the test-only
platform resets the allocation counter, so existing `before_fixture_main`
baselines continue to measure the fixture pipeline rather than transport. It
compiles each distinct fixture app once, so a
separate allocation-baseline invocation is not needed after snapshot updates.

The test platform is derived from
[`roc-platform-template-zig`](https://github.com/lukewilliamboswell/roc-platform-template-zig)
and retains its original notice in [`tests/platform/NOTICE`](tests/platform/NOTICE). It is licensed
under the project’s [UPL license](LICENSE).
