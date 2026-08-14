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
notes](docs/releases/0.1.0-rc1.md). Gate 3 is closed; its aggregated evidence
is recorded in the [Gate 3 closure
review](docs/performance/gate-3-closure.md).

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
