# contract-definition facade, theme, and builder type slice

This record covers the define-only `Pdf`, `Document`, and `Theme` public type
modules. It does not claim layout, validation, sealing, or PDF emission.

## Representation and ownership contract

- The common facade accepts a simple `List(Document.Block)` authoring value.
  That list remains an ergonomic front end and will normalize exactly once.
- `Document.builder` writes block tags, text IDs, auxiliary scalar values, and
  text payloads into separate flat buffers. The builder never accumulates a
  boxed descriptor union, `List(Document.Block)`, or recursive semantic tree.
- Builder methods consume and return one nominal state. They do not retain an
  alias to either list across append operations. Bullet string references are
  transferred by a direct indexed `while` loop rather than a stored `Iter` or
  adapter chain; string byte payloads are not duplicated.
- `Theme` is a fixed-shape visual/layout record. It contains typed font IDs,
  fixed-point sizes and spacing, margins, and colors, but no semantic role,
  language, metadata, conformance, or serializer policy.
- `Pdf.Options` carries the exact public profile, page size, theme, and chunk
  retention policy. WTPDF and PDF/A-4f remain orthogonal to its profile union.

## Complexity and allocation contract

- Scalar methods append one tag/text/auxiliary tuple and one text reference.
  The large-input `add_paragraphs` operation keeps every dense buffer inside
  one consumed call, performs amortized `O(1)` work per paragraph, and returns
  only the final builder. Adding `n` bullet items is `O(n)` direct visits and
  appends one scalar tuple plus `n` text references.
- Finishing the builder is `O(1)` and transfers the compact state into the
  opaque `Document`; it does not rebuild blocks or copy payload strings.
- No function closure or `Iter` value is stored in a document, builder, theme,
  or options value.
- This contract-definition slice is compile- and unit-tested as a define-only contract.
  Exact optimized allocation, ARC, copied-byte, shared-input, and scaled-work
  baselines are required before the compact builder is claimed as the
  implemented large-document authoring path.

At contract-definition every facade serialization entrypoint returned the typed
`CapabilityUnavailable(Pdf20Generation)` error and no bytes. structural-kernel later
enabled structural blank `Standard` documents; meaningful authoring content
and stricter profiles still fail explicitly instead of producing fallback PDF
output or a profile downgrade. text-layout runtime normalization and its scaled
list/builder allocation evidence are recorded in
[authoring-normalization.md](authoring-normalization.md).
