# Migrating to 0.1.0-rc2

rc2 adds an explicit prepare/emit lifecycle and completes sRGB theme-color
output. Existing `Pdf.to_bytes*` and `Pdf.to_chunks*` calls remain valid.

- Use `Pdf.prepare(document, options)` when the same validated plan feeds more
  than one output strategy.
- Use `Pdf.to_bytes_prepared` or `Pdf.to_chunks_prepared` after preparation.
- Use `Theme.with_body_color`, `with_heading_color`, `with_title_color`, or
  `with_text_color`; the opaque `Theme` representation is not public state.
- Do not depend on the conceptual open `Document.Prepared` record. It was never
  executable and is not the supported prepared-output boundary.
- Do not claim PDF/A-4 or PDF/UA-2. Their profile selectors remain deliberate
  transactional errors.

The rc1 notes remain available as the historical description of that release.
