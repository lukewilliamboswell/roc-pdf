# Contributor documentation

Use these guides to change, test and release roc-pdf. For supported APIs and
examples, start with the [user manual](../docs/README.md).

- [Architecture](../architecture.md): enduring package and compiler-stage contracts.
- [Feature roadmap](../feature-roadmap.md): capability boundaries and acceptance requirements.
- [Implementation contracts](implementation-contracts.md): binding representation and harness details.
- [Testing](testing.md): focused tests, snapshot review, exact allocation/work baselines and validators.
- [Blueprint setup](blueprint.md): declared tools and test, fuzz, gallery, bundle and docs tasks.
- [Property fuzzing](../fuzz/README.md): bounded searches, reports, witnesses and explicit baseline review.
- [Reference documents](reference-documents.md): invoice, report and letter fixture contracts.
- [Packaged fonts](roc-font.md): source provenance, selection and ownership.
- [Engineering contracts](performance/): subsystem invariants, resource bounds and fixture rationale.
- [PDF comparison](benchmarks/pdf-comparison/README.md): reproducible Roc/Go/Python workloads.
- [Publishing](releases/publishing.md): release validation and publication steps.
- [Automation and documentation](automation-publication.md): source/artifact boundaries and manual checks.

## Write documentation

Every paragraph must help a current user or contributor task. Follow the
[shared documentation guidance](https://lukewilliamboswell.github.io/roc-automation/documentation.html#write-project-documentation).
Delete superseded guidance; preserve required anchors without narrating their
history. Implementation history belongs in Git, pending work in issues and
release changes in the release record.

Commit executable baselines, provenance, locks and current engineering contracts.
Keep generated reports, benchmark transcripts, before/after dumps and screenshots
under ignored `.roc-pdf-tmp/` or CI artifacts. A test result is evidence for its
recorded source and toolchain, not an evergreen product instruction.
