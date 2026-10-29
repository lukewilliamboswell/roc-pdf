# Contributor documentation

This directory holds repository workflows, implementation contracts and
validation evidence. For supported APIs, examples and migration help, start
with the [user documentation](../docs/README.md).

- [Architecture](../architecture.md) defines enduring package boundaries,
  compiler-stage contracts, ownership and conformance decisions.
- [Feature roadmap](../feature-roadmap.md) defines capability status and the
  evidence needed to claim support.
- [Implementation contracts](implementation-contracts.md) records binding
  representation and harness details.
- [Testing and fixture development](testing.md) explains the pinned toolchain,
  focused tests, snapshot review, exact allocation/work baselines and validators.
- [Contributor tooling with Blueprint](blueprint.md) lists the declared
  tools and the named tasks that wrap the test, fuzz, gallery, bundle and docs
  scripts.
- [Reference-document contract](reference-documents.md) specifies the invoice,
  report and letter fixtures, adverse variants and acceptance obligations.
- [Performance and implementation records](performance/) preserves design
  reviews, scale measurements, compiler investigations and feature validation.
- [PDF comparison trial](benchmarks/pdf-comparison/README.md) separates Python
  and Roc source-to-PDF scripting from Roc/Go executable build and run costs.
- [Publishing a release](releases/publishing.md) explains how the release
  workflow validates and publishes a bundle, and the steps to cut a release.
- [Automation and documentation publication](automation-publication.md) records
  the shared tooling, URL compatibility, independent review and settings audit.
- [Release consumer smoke test](releases/0.1.0-rc1-consumer-smoke-test.md)
  records validation of the first release candidate's distribution boundary.

Evidence records describe the source, compiler and supported subset measured
at the time. Preserve those facts when recording later results; historical
measurements are not current API instructions. Link current capability claims
to the roadmap and user guides.

Write user-facing explanations in `docs/`: show what an author can do, how to
do it, and what limits or diagnostics apply. Keep issue tracking, gate closure,
agent coordination, branch names and implementation diaries here or in the
roadmap. Moving a record must preserve its evidence and update repository,
conformance-ledger and provenance references.
