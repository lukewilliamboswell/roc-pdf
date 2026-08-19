# Authoring with roc-pdf

Use `Pdf` for ordinary documents. It owns normalization, layout, font
planning, tagging, resource planning, and deterministic PDF 2.0 emission.

```roc
document = Pdf.document({
    title: "Quarterly report",
    language: "en-AU",
    contents: [
        Pdf.title("Quarterly report"),
        Pdf.heading(1, "Summary"),
        Pdf.paragraph("Revenue and customer retention improved this quarter."),
        Pdf.bullets(["Searchable text", "Deterministic bytes"]),
    ],
})

bytes = Pdf.to_bytes(document)?
```

For deferred or repeated emission, prepare once. `Pdf.Prepared` is opaque: a
successful value has completed document validation and object planning.

```roc
prepared = Pdf.prepare(document, Pdf.Options.default)?
buffered = Pdf.to_bytes_prepared(prepared)?
encoder = Pdf.to_chunks_prepared(prepared, Pdf.ChunkRetention.ShareUnchangedResources)?
```

Theme colors are explicit 16-bit sRGB channel values. Use the `Theme` setters;
the facade resolves them through the packaged sRGB profile and output intent.

The `Standard` profile is the only available profile in rc2. `Archive` and
`AccessibleArchive` reject with a capability error. The package does not read,
repair, sign, encrypt, outline, or rasterize PDFs.

## Advanced modules

The lower-level modules expose the typed vocabulary used between compiler
stages. They are useful for understanding or integrating with the package, but
raw stores are not a shortcut around validation. PDF object and serialization
internals remain private. Stable custom scene authoring will arrive only with
an executable validated preparation boundary; do not construct incidental
dense stores and assume they are accepted output.

Gate 4 closes the production visual compiler and its evidence. Meaningful
figure authoring requires the semantic and author-obligation work assigned to
Gate 6; broad custom layout belongs to Gate 8. This separation prevents an
image API that paints pixels while losing ownership or alternative text.
