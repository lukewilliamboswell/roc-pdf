# Unreleased

`AccessibleArchive` becomes the default. Supported documents now include
PDF/A-4 and PDF/UA-2 declarations when you omit the profile, including through
the buffered and chunked convenience functions.

## Migrate profile selection

- To retain the previous static PDF/A-4 profile, set `profile: Archive`.
  Use that profile for intentionally blank archived pages. The new default
  requires tagged semantic content.
- For PDF 2.0 without archival or accessibility declarations, set
  `profile: Standard`.
- To add the WTPDF 1.0 accessibility declaration, use
  `{ profile: AccessibleArchive, wtpdf: DeclareAccessibility }`.

Profile checks run before emission, so handle any new diagnostics in
applications that rely on the default. Standards support is best effort. Use
the preparation report to review author-dependent requirements for combined
output. See the
[output profile guide](authoring.adoc#authoring-output-profiles).

The document builder now reports `semantics.heading_level` for destination
headings outside levels 1–6, matching the block-based API.

## Fixed-page documents

Place titles, headings and paragraphs into explicit frames on each sheet.
Placement order defines reading order, and each page can specify its own
paint order. Fixed pages also support solid rectangle artwork before and after
the text. See the [fixed-page authoring guide](authoring.adoc#authoring-fixed-pages).


## Migrate preparation reports

Pass `{ options: options }` to `Pdf.prepare_with_report(document, props)`
when migrating from the previous `Pdf.prepare_with_report(document, options)`.
Replace `Pdf.prepare_with_report_budget(document, { options, budget })` with
`Pdf.prepare_with_report(document, { options, budget })`. Use `{}` to apply
the existing defaults for both document options and report budget. See the
[preparation report guide](authoring.adoc#authoring-preparation-reports).

## Two-column flow

Flow plain paragraphs through two explicitly sized columns. A paragraph
that spans columns or pages keeps its authored text and logical reading order.
See the [two-column guide](authoring.adoc#authoring-column-flow).

## Compiler

This development branch uses Roc `nightly-2026-11-25-d5a4f1e`.
Text analysis uses `roc-lang/unicode` 4.4.0, with Unicode 18.0.0 data for
segmentation, line breaking, bidirectional analysis, and case mapping.
