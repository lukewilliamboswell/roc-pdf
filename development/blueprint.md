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
| `rg` | Expected on `PATH` for the `docs` task only |

The package compiler is deliberately not fetched by Blueprint. `.roc-version`
stays its single pin, because the allocation baselines are exact for one build
and the nightly updater (`.github/ROC_NIGHTLY.md`) rewrites only that file.
CI installs the pinned nightly with `roc-lang/setup-roc`; locally, put it on
`PATH` (or set `ROC`). The scripts refuse any other compiler.

Zig is fetched because the test platform hosts need exactly 0.16.0, and a newer
Zig on `PATH` is rejected by the harness. Inside a task the fetched Zig comes
first on `PATH`, so `ZIG` no longer needs to be set.

The renderer oracles (PDFium, MuPDF, veraPDF, PDFBox) and the Arlington service
are not declared. They are manual or service-container evidence and keep their
existing provisioning (`scripts/provision_extended_tools.py`, `vendor/`).

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
blueprint run docs                  # scripts/docs.sh
blueprint workflow check            # test, fuzz smoke, bundle consumer, gallery
blueprint shell                     # a shell with the dev tools on PATH
```

Arguments after `--` are passed to the script unchanged. Every task wraps an
existing script; the scripts still run directly when the tools are already on
`PATH`.

`blueprint workflow check` is what a pull request runs on Linux. The fuzz
campaign is not part of it.

## CI

`ci.yml`, `docs.yml` and `fuzz.yml` install Blueprint with the shared
`roc-automation` `actions/setup-blueprint` action at the reviewed `tools-0.4.0`
commit. It verifies the Blueprint binary against its reviewed digest and reads
the release from the platform URL in `Blueprint.roc`, so no workflow names the
Blueprint version. The `ci.yml` test job caches Blueprint's download store
(`cache-workload: dev`); a cached artifact is rehashed before use.
`release-candidate.yml` is unchanged.

## Maintenance

- To move Zig or add a fetched program, edit `Blueprint.roc`, run
  `blueprint update`, review every URL, size and SHA-256 in the regenerated
  `Blueprint.lock` (compare Zig against
  <https://ziglang.org/download/index.json>), and commit both files.
- To upgrade Blueprint, follow roc-automation's "Upgrade Blueprint" steps: move
  the `setup-blueprint` revision to one that records the release, change the
  platform URL in `Blueprint.roc`, and regenerate the lock if the lock format
  changed.
- `.blueprint/` is generated state and is ignored.
