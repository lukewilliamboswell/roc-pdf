# roc-pdf

An early-development pure [Roc](https://www.roc-lang.org/) package for
deterministic PDF 2.0 generation.

The package currently offers a usable public, single-face `Pdf.to_bytes`
authoring path under the `Standard` profile. The built-in theme supports title,
heading, paragraph, and bulleted-list constructors. It does not read, edit, or
repair PDFs, and unsupported requests return typed errors rather than producing
blank output, substituting fonts, outlining text, or rasterizing content.

This is not yet a PDF/A-4 or PDF/UA-2 package. `Archive` and
`AccessibleArchive` deliberately return capability errors, and `Pdf.to_chunks`
is not yet a delivery path for authored nonblank documents. Full bidirectional
text, public multi-face coverage selection, and case-transformation support are
also incomplete. Do not make archival or accessibility-conformance claims from
this release candidate.

The package exposes the high-level `Pdf` facade plus the advanced conceptual
`Document`, `Semantics`, `Layout`, `Scene`, `Text`, `Font`, `Image`, `Color`,
`Metadata`, `Encode`, `Conformance`, and `Theme` boundaries. PDF object,
lowering, and serialization internals are not public.

The current candidate scope is recorded in [the 0.1.0-rc1 release
notes](docs/releases/0.1.0-rc1.md). Gate 3 remains open; its remaining closure
boundaries are tracked in the [closure-readiness
audit](docs/performance/gate-3-closure-readiness-audit.md).

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
by the same driver. Runtime Gate 1 behavior is exercised by package tests and
the dev-backend structural fixtures.

Each integration case lives in its own directory under `tests/`, with its `main.roc` application
and `snapshot.pdf` adjacent to one another. The case and expected allocation count are registered
in [`tests/spec.json`](tests/spec.json).

An allocation event is a call to either `roc_alloc` or `roc_realloc`; host setup and teardown are
not counted. To accept intentional PDF output changes after reviewing them, run:

```sh
./scripts/test.py --update-snapshots
```

The test platform is derived from
[`roc-platform-template-zig`](https://github.com/lukewilliamboswell/roc-platform-template-zig)
and retains its original notice in [`tests/platform/NOTICE`](tests/platform/NOTICE). It is licensed
under the project’s [UPL license](LICENSE).
