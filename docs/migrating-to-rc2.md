# Migrating to 0.1.0-rc2

This guide describes the changes from rc1 to rc2. For the current API and
profile defaults, see the [authoring guide](authoring.md) and
[0.1.0 release notes](releases/0.1.0.md).

rc2 adds an explicit prepare/emit lifecycle and sRGB theme-color output.
Existing `Pdf.to_bytes*` and `Pdf.to_chunks*` calls remain valid.

- Use `Pdf.prepare(document, options)` to validate once before choosing an
  output strategy.
- Use `Pdf.to_bytes_prepared` or `Pdf.to_chunks_prepared` to emit that plan.
- In rc2, configure colors through `Theme.with_body_color`,
  `with_heading_color`, `with_title_color`, or `with_text_color`. Its `Theme`
  value is opaque.
- Use the opaque `Pdf.Prepared` returned by preparation. The earlier open
  `Document.Prepared` description is not a supported output API.
- rc2 supports the `Standard` profile only. Its `Archive` and
  `AccessibleArchive` selectors return capability errors; do not claim
  PDF/A-4 or PDF/UA-2 from rc2 output.

The [rc1 notes](releases/0.1.0-rc1.md) describe that earlier release.
