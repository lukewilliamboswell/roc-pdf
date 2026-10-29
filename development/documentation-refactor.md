# Native documentation and release-neutral entry pages

## Reader and scope

The README is a user-facing front door: what roc-pdf does, representative output,
the manual, released downloads and one checked example. Task guides explain the
checkout's supported API without repeating an upcoming/current package version.
Release notes and build metadata own exact package/compiler pins, migration
history and generated publication labels.

This refactor follows roc-automation's
[documentation guidance](https://github.com/lukewilliamboswell/roc-automation/blob/1104294f221bb9571901c7a1a4269cea8516f8e5/docs/documentation.adoc)
at the recorded source revision. The documentation workflow pins that source's
shared actions. Its `build-docs` action interface is byte-identical to the
previous reviewed action. The initial latest-release query selected
`tools-0.7.0`, and its successful candidate is retained under
[tools-0.7.0 history](manual-refactor-review/tools-0.7.0/review.json). A completion
query then selected published `tools-0.8.0`. The official checksum manifest and
GitHub asset digests were checked before a focused Blueprint lock update;
no unpublished download was guessed. All reader and artifact checks were
repeated for the actual new binary.

The exact declared Blueprint CLI was separately checked against its published
release before use. A focused `blueprint update roc-docs` changed only the two
renderer entries, `blueprint check` passed, and the real `blueprint run docs`
task used the new locked executable through the normal PATH handoff. Source
Mermaid is supported by this utility, but this manual has no obsolete diagram
registry to remove. Its three PNGs illustrate checked product examples and
remain required source figures.

Repository instructions keep contributor workflows, implementation reviews and
validation history under `development/`. The user manual links those records;
it does not embed them as user chapters. The existing product compiler pin,
Python/native independent oracles and release controls remain binding. This is
a documentation refactor, not wholesale adoption of conflicting general
repository/tooling guidance.

## Native source and compatibility

Canonical task chapters are top-level `docs/*.adoc`, included by a book
`docs/index.adoc`. The shared utility owns parsing, highlighting, cross-reference
resolution and HTML/PDF/Markdown generation. `prepare_manual.py` now stages
source bytes, exact local PNGs, source-revision links, release metadata and an
input digest inventory. The Markdown-to-AsciiDoc syntax converter is removed.
Historical release-note Markdown remains unchanged; a generated release index
links those source records. A versioned build generates its actual dependency
URL, bundle digest and compiler requirement rather than editing evergreen text.

The old guide `.md` paths remain short landing pages, with their section anchors
linking into canonical chapter sections. Sixteen section destinations were
checked. Existing task HTML filenames and namespaced anchors remain; a first-use
tutorial is added. Compiler-generated API stays at the site root and the manual
stays under `/manual/`. All 18 original API files are byte-identical to the
previous candidate's outputs. Historical release/migration material remains in
its original source paths instead of becoming recurring user-book chapters.

The local task also exposed an existing macOS Bash 3.2 failure: expanding an
empty optional argument array under `set -u` rejected the unreleased build.
Explicit release/unreleased preparation calls now work on that shell without
changing the compiler or weakening the versioned bundle binding.

## Validation and artifact binding

The [retained review](documentation-refactor-review.json) binds manual source
`d266e020f8985263fa992450772121db272d9203` and records every asset hash. The
[sources](manual-refactor-review/sources.json),
[browser](manual-refactor-review/browser.json),
[PDF](manual-refactor-review/pdf.json) and original
[veraPDF report](manual-refactor-review/verapdf.xml) are independent evidence.
Earlier 49-page/c08 records remain historical evidence and are not presented as
validation of the new source.

Both the unreleased and versioned local documentation commands passed:

```sh
blueprint run docs
DOCS_VERSION=<authored-release> DOCS_REVISION=<recorded-sha> blueprint run docs
```

The versioned manual has 10 HTML/Markdown pages, 34 PDF pages, 28 exact source
blocks, three tagged tables and three exact decoded RGB figures. The independent
checker compares authored source whitespace, table row/cell associations and
chapter links/anchors in HTML and Markdown, then uses PDFBox for PDF source, table and image checks. Poppler independently
finds all 25 explicitly authored heading destinations. Desktop/mobile, dark-mode,
transparent code backgrounds and mobile contents controls passed. A changed
Markdown code byte, changed table cell and missing chapter anchor each failed
the appropriate independent check. The original PDF passes veraPDF 1.30.2's
explicit PDF/A-4 profile with zero failed rules/checks and no parser exceptions.
Representative desktop/mobile, table and figure renderings were inspected.

The native manual and docs ZIP were assembled into a fresh four-file release
manifest with current notes and source bindings. The package and examples were
unchanged: their hashes match the previously tested C3/08caa candidate, all 85
archived source/resource members match the recorded checkout, and no package,
example or compiler input differs from c08. Reusing those verified bytes avoids
claiming a new archive test or recording new output as its own expectation.
Stale manual revision, wrong bundle and older examples-archive bindings were
all rejected. No package allocation, work, PDF snapshot or production dependency
changed, and no release or website was published.

## Independent Linux renderer execution

The verified Linux renderer also built the recorded native-book inputs in
`alpine@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce`
with networking disabled, read-only source inputs and a writable output parent
for atomic staging. The independent checker passed all ten HTML/Markdown pages,
28 exact code blocks, table associations and three RGB figures against that
output. Its original PDF passed the pinned veraPDF PDF/A-4 check. The retained
review records the Linux PDF digest and comparison with the native artifact.
This checks manual rendering; it does not claim a second API-extraction run.
