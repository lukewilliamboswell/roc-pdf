# Roc nightly compatibility

`.roc-version` is the compiler pin. This repository pins the compiler because
its allocation baselines are exact for one build, so pin updates are manual
pull requests: bump `.roc-version`, run `./scripts/test.py`, and diagnose any
change. Do not weaken tests or mechanically replace baselines to accept a
compiler.

`.github/workflows/nightly.yml` runs the shared
[published-release compatibility](https://github.com/lukewilliamboswell/roc-automation/blob/dd30a5dd576973b6e224db70d96e3e12c96bcc95/docs/nightly-compatibility.adoc)
check daily at 13:17 UTC. It tests the latest final release's
`roc-pdf-examples-<tag>.zip` against the latest Roc nightly and opens or closes
one tracking issue. The release workflow builds that archive with
`scripts/examples_archive.py`.

The nightly caller pins shared code to `dd30a5dd576973b6e224db70d96e3e12c96bcc95`.
Dependabot proposes reviewed updates to Actions/workflow references.

Follow the shared [repository settings](https://github.com/lukewilliamboswell/roc-automation/blob/dd30a5dd576973b6e224db70d96e3e12c96bcc95/docs/settings.adoc)
for action allowlists at full SHAs, required checks and signed commits. Keep
default token permissions read-only.
