# roc-pdf

A pure [Roc](https://www.roc-lang.org/) package for generating PDF/UA-2 documents.

The Gate 1 PDF 2.0 structural kernel is implemented and cross-host evidenced.
The package exposes the high-level `Pdf` facade plus the
advanced conceptual `Document`, `Semantics`, `Layout`, `Scene`, `Text`, `Font`,
`Image`, `Color`, `Metadata`, `Encode`, `Conformance`, and `Theme` boundaries.
PDF object, lowering, and serialization internals are not public.

The facade currently generates deterministic blank, single-page PDF 2.0
documents under the `Standard` profile. Meaningful authoring content belongs
to later visual and text gates and returns `UnsupportedAuthoringContent`;
`Archive` and `AccessibleArchive` remain explicitly unavailable until their
profile gates close. No request is silently downgraded or replaced with blank
output.

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
real Roc applications with `--opt=dev`. The test-only Zig platform supports macOS AArch64 and
Linux x86-64. Each test application's `main!` receives `List(Str)` process arguments and returns
the generated `List(U8)` PDF; the host writes those bytes to stdout and reports the number of Roc
allocation events separately. The driver requires both the PDF snapshot and allocation count to
match the case specification.

Public contract examples under `examples/` are formatting- and compile-checked
by the same driver. Runtime Gate 1 behavior is exercised by package tests and
the optimized structural fixtures.

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
