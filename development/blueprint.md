# Contributor tooling with Blueprint

`Blueprint.roc` and `Blueprint.lock` at the repository root declare the tools
the contributor checks need and name those checks as tasks. They use
[Blueprint](https://github.com/lukewilliamboswell/roc-blueprint) 0.8.0 with no
package provider: no Nix and no flake. Downloads are checked against the
digests committed in `Blueprint.lock`, and everything else is expected from the
machine.

## What comes from where

| Tool | Source |
| --- | --- |
| Zig 0.16.0 | Fetched from ziglang.org for `x86_64-linux` and `aarch64-darwin`, checked against `Blueprint.lock` |
| `roc` | Expected on `PATH`; it must be the nightly named in `.roc-version` |
| `python3`, `bash`, `tar` | Expected on `PATH` |
| ripgrep 15.2.0 (`rg`) | Fetched from its GitHub release for the `docs` task, checked against `Blueprint.lock` |
| roc-docs tools-0.7.0 | Native manual renderer, fetched per system with reviewed release size/SHA-256 in `Blueprint.lock` |
| Temurin JDK 21.0.13+9 and Python 3.14.0 | Explicit CI setup-action inputs; local independent checks may use an installed compatible JDK/Python and record their identities |

The package compiler is deliberately not fetched by Blueprint. `.roc-version`
stays its single pin, because the allocation baselines are exact for one build
and compiler-pin updates (`.github/ROC_NIGHTLY.md`) change only that file.
CI installs the pinned nightly with `roc-lang/setup-roc`; locally, put it on
`PATH` (or set `ROC`). The scripts refuse any other compiler.

Zig is fetched because the test platform hosts need exactly 0.16.0, and a newer
Zig on `PATH` is rejected by the harness. ripgrep is fetched because the docs
audit for private `Kernel` types needs it and the Ubuntu runners do not ship
it; `scripts/docs.sh` now refuses to run without it. Inside a task the fetched Zig comes
first on `PATH`, so `ZIG` no longer needs to be set.

PDFBox 3.0.8 and veraPDF 1.30.2 remain independent vendored test oracles.
CI provisions veraPDF and its corpus from verified bytes without a network
fallback. Arlington runs in its digest-pinned service container. PDFium and
MuPDF extended reader lanes retain their existing provisioning; see the
[tool and publication audit](automation-publication.md). These are test tools,
never production dependencies.

## Tasks

Install the `blueprint` 0.8.0 binary for your system from the
[release](https://github.com/lukewilliamboswell/roc-blueprint/releases/tag/0.8.0)
and check its SHA-256 against `blueprint.sha256` there. Then:

```sh
blueprint check                     # validate Blueprint.roc
blueprint tasks                     # list the tasks
blueprint run test                  # ./scripts/test.py
blueprint run test -- --compare-baselines --jobs 6
blueprint run fuzz                  # fuzz smoke run (what pull requests run)
blueprint run fuzz-campaign         # bounded fuzz campaign (scheduled in CI)
blueprint run gallery               # scripts/check_gallery.py
blueprint run bundle                # scripts/bundle.sh
blueprint run bundle-consumer       # scripts/test_bundle_consumer.py
blueprint run docs                  # native user manual, separate API and checks
blueprint run docs-path             # verified persistent renderer path
blueprint workflow check            # test, fuzz smoke, bundle consumer, gallery
blueprint shell                     # a shell with the dev tools on PATH
```

Arguments after `--` are passed to the script unchanged. Every task wraps an
existing script; the scripts still run directly when the tools are already on
`PATH`.

Gallery checks compare the generated PDFs byte for byte. After reviewing the
architectural cause of an intentional change, regenerate PDFs and the retained
96 dpi previews with Poppler 26.07.0:

```sh
blueprint run gallery -- --update --update-reason 'Reviewed cause of the changed output'
blueprint run gallery
```

The update preserves a before/after hash report and the old artifacts under
`.roc-pdf-tmp/`, checks that tagged semantic characters survive typography and
wrapping changes, and updates the exact asset provenance. Review changed
previews and the report before committing them. An update does not change
test-case allocation, byte, work or snapshot baselines.

`blueprint workflow check` is the local package-check sequence. The reusable
GitHub checks workflow additionally validates independent profiles/Arlington,
the native manual/API and the exact bundle/examples/docs archives. The fuzz
campaign remains separate.

## CI

The check, documentation and fuzz workflows install Blueprint with the shared
`roc-automation` `actions/setup-blueprint` action at the reviewed `tools-0.7.0`
commit, `8acff758d5d73210f1731bed75adb9322f5e773d`. It verifies the Blueprint binary against its reviewed digest and reads
the release from the platform URL in `Blueprint.roc`, so no workflow names the
Blueprint version. The reusable test job caches Blueprint's download store
(`cache-workload: dev`); a cached artifact is rehashed before use.
Release dispatch runs the same checks at its recorded SHA before an
artifact-consuming publication job; it never publishes from a branch build
that tested different bytes. See [publishing](releases/publishing.md).

## Maintenance

- To move Zig or add a fetched program, edit `Blueprint.roc`, run
  `blueprint update`, review every URL, size and SHA-256 in the regenerated
  `Blueprint.lock` (compare Zig against
  <https://ziglang.org/download/index.json> and ripgrep against the digests on
  its GitHub release), and commit both files.
- To upgrade Blueprint, follow roc-automation's "Upgrade Blueprint" steps: move
  the `setup-blueprint` revision to one that records the release, change the
  platform URL in `Blueprint.roc`, and regenerate the lock if the lock format
  changed.
- `.blueprint/` is generated state and is ignored.
