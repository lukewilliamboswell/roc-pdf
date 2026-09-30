# roc-pdf

An early-development pure [Roc](https://www.roc-lang.org/) package for
deterministic PDF 2.0 generation.

The package offers a stable public authoring path whose default profile is
`Archive`: `Pdf.to_bytes`, `Pdf.to_bytes_with`, and `Pdf.to_chunks_with` all
produce deterministic tagged PDF 2.0 output that also claims static PDF/A-4,
and the buffered and chunked forms are byte-identical. `Standard` (PDF 2.0
only) remains available through `Pdf.Options.with_profile`. The built-in theme supports title, heading,
paragraph, and bulleted-list constructors, with either the packaged face or
caller-registered faces selected through `Theme` — including a finite ordered
multi-face policy with per-cluster coverage selection. Theme text colors use
the packaged sRGB profile. Documents can be prepared once into an opaque,
validated plan and then emitted as buffered bytes or chunks. It does not read,
edit, or repair PDFs, and unsupported requests return typed errors rather than
producing blank output, substituting fonts, outlining text, or rasterizing
content.

Default output claims static PDF/A-4 (`Pdf20 + StaticPdfA4`): the package
validates a closed whitelist before emitting any byte, and every Archive
fixture passes the pinned veraPDF PDF/A-4 profile with zero failed checks. A
document that cannot meet the claim returns a structured error; it is never
downgraded to `Standard`. PDF/UA-2 is not claimed yet: `AccessibleArchive`
deliberately returns a structured feature diagnostic, so do not make
accessibility-conformance claims from it. Automatic hyphenation is not
accepted, and the convenience shaping path covers a declared script set;
right-to-left and case-transformation output are available at the advanced
integration boundary rather than through the one-import facade.

The package exposes the high-level `Pdf` facade plus the advanced conceptual
`Document`, `Semantics`, `Layout`, `Scene`, `Text`, `Font`, `Image`, `Color`,
`Metadata`, `Encode`, `Conformance`, and `Theme` boundaries. PDF object,
lowering, and serialization internals are not public.

Typed packed-raster and JPEG sources can now be placed as a meaningful
single-image `Pdf.figure` with required alternative text and an optional
caption. Broader drawings and content-first fixed pages remain available for
early integration; `Pdf.prepare` rejects their unsupported forms atomically
with a stable feature code and roadmap explanation. See the
[authoring support matrix](docs/authoring.md#forward-authoring-api).

The current candidate scope is recorded in [the 0.1.0-rc2 release
notes](docs/releases/0.1.0-rc2.md), and the pending default-profile change in
the [draft 0.1.0-rc3 notes](docs/releases/0.1.0-rc3.md). Gate 4 is closed; its
aggregated evidence is recorded in the [production-visual closure
review](docs/performance/production-visual-closure.md). Gate 5 (static
PDF/A-4) is closed on the pinned veraPDF profile basis; see the [static PDF/A-4
record](docs/performance/static-pdfa4.md).

## Start here

- [Authoring guide](docs/authoring.md)
- [Example gallery](examples/README.md)
- [Reference business documents](docs/reference-documents.md) (the planned
  Gate 6 contract; not yet executable)
- [Generated API documentation](https://lukewilliamboswell.github.io/roc-pdf/)
- [Migrating to rc2](docs/migrating-to-rc2.md)

## Examples

Click a preview to open the generated PDF, or its caption to view the complete
runnable Roc source.

<table>
<tr>
<td><a href="examples/quarterly-report.pdf"><img src="examples/previews/quarterly-report.png" alt="Quarterly report preview"></a><br><a href="examples/quarterly_report.roc">Quarterly report source</a></td>
<td><a href="examples/brand-brief.pdf"><img src="examples/previews/brand-brief.png" alt="Brand brief preview"></a><br><a href="examples/brand_brief.roc">Brand brief source</a></td>
<td><a href="examples/field-guide.pdf"><img src="examples/previews/field-guide.png" alt="Field guide preview"></a><br><a href="examples/field_guide.roc">Field guide source</a></td>
</tr>
<tr>
<td><a href="examples/operations-handbook.pdf"><img src="examples/previews/operations-handbook.png" alt="Operations handbook preview"></a><br><a href="examples/operations_handbook.roc">Operations handbook source</a></td>
<td><a href="examples/warranty-letter.pdf"><img src="examples/previews/warranty-letter.png" alt="Reference business letter preview"></a><br><a href="examples/letter.roc">Business letter source</a></td>
<td><a href="examples/release-notes.pdf"><img src="examples/previews/release-notes.png" alt="Release notes preview"></a><br><a href="examples/release_notes.roc">Release notes source</a></td>
</tr>
<tr>
<td><a href="examples/tax-invoice.pdf"><img src="examples/previews/tax-invoice.png" alt="Reference tax invoice preview"></a><br><a href="examples/prepared_invoice.roc">Tax invoice source</a></td>
<td><a href="examples/chunked-export.pdf"><img src="examples/previews/chunked-export.png" alt="Chunked export preview"></a><br><a href="examples/chunked_export.roc">Chunked export source</a></td>
<td><a href="examples/product-brief.pdf"><img src="examples/previews/product-brief.png" alt="Product brief preview"></a><br><a href="examples/product_brief.roc">Product brief source</a></td>
</tr>
</table>

[See what each application demonstrates and how to run it.](examples/README.md)

## Design

- [Architecture](architecture.md)
- [Feature roadmap](feature-roadmap.md)

## Requirements

- Python 3
- Zig 0.16.0
- The Roc nightly pinned in [`.roc-version`](.roc-version), available as `roc` on `PATH`

## Development

Run the complete test suite with the pinned Roc compiler:

```sh
./scripts/test.py
```

See [Testing and fixture development](docs/testing.md) for focused runs,
compiler selection, allocation and snapshot workflows, and the family-fixture
schema.

## License

This project is licensed under the [Universal Permissive License](LICENSE).
