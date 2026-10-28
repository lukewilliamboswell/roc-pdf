# Roc nightly compatibility

`.roc-version` is the compiler pin. This repository pins the compiler because
its allocation baselines are exact for one build, so pin updates are manual
pull requests: bump `.roc-version`, run `./scripts/test.py`, and diagnose any
change. Do not weaken tests or mechanically replace baselines to accept a
compiler.

`.github/workflows/nightly.yml` runs the shared
[published-release compatibility](https://github.com/lukewilliamboswell/roc-automation/blob/a25b5129340b9b2ad1744d20330b8ee4d38a1849/docs/nightly-compatibility.adoc)
check daily at 13:17 UTC. It tests the latest final release's
`roc-pdf-examples-<tag>.zip` against the latest Roc nightly and opens or closes
one tracking issue. The release workflow builds that archive with
`scripts/examples_archive.py`.

The caller workflows pin shared code to `a25b5129340b9b2ad1744d20330b8ee4d38a1849`.
Dependabot proposes reviewed updates to Actions/workflow references.

Follow the shared [repository settings](https://github.com/lukewilliamboswell/roc-automation/blob/a25b5129340b9b2ad1744d20330b8ee4d38a1849/docs/settings.adoc)
for action allowlists at full SHAs, required checks and signed commits. Keep
default token permissions read-only.
