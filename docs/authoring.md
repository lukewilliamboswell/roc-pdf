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

Theme colors can use familiar 8-bit channels with
`Color.srgb8({ red, green, blue })`, or exact 16-bit channels with
`Color.srgb16`. Role colors, complete text styles, page margins, paragraph
spacing, and bullet indentation can be changed through `Theme`; every color is
resolved through the packaged sRGB profile and output intent.

The `Standard` profile is the only executable profile in rc2. `Archive` and
`AccessibleArchive` reject with an `InvalidDocument` diagnostic batch. The
package does not read, repair, sign, encrypt, outline, or rasterize PDFs.

## Images, figures, and forward authoring

Packed grayscale, packed sRGB, and validated sRGB JPEG sources can be placed
without leaking PDF objects or caller-assigned resource IDs. The first
executable figure slice accepts exactly one image command, requires non-empty
alternative text, and accepts an optional visible caption:

```roc
image = Image.Source.rgb8({
    alpha: NoAlpha,
    dimensions: { width: 2, height: 2 },
    pixels: [24, 94, 134, 240, 180, 40, 40, 160, 90, 245, 245, 240],
    row_stride: 6,
})
drawing = Scene.drawing({}).image(image, Layout.rect(0, 0, 240, 120))

figure = Pdf.figure(drawing, "A four-color information panel", Pdf.caption("Figure 1"))
```

Image pixel dimensions and layout placement are independent. Packed planes
must have valid dimensions, row stride, byte length, and supported alpha;
JPEGs additionally pass the bounded marker and orientation-policy inspector.
Invalid resources fail transactionally. Vector paths, grouped drawings,
multi-command figures, and fixed pages remain forward API: they report
`document.figure` or `layout.custom` and emit no bytes or chunks.

| Authoring surface | Status |
| --- | --- |
| titles, headings, paragraphs, bullets, links, destinations | executable |
| sRGB role styling, font selection, page size, spacing and margins | executable |
| prepared and chunked emission | executable |
| one-image figures using typed JPEG/packed raster sources | executable |
| vector/grouped/multi-command drawings | representable; `document.figure` diagnostic |
| semantic containers, rich inline content, simple tables | representable; Gate 6 diagnostic |
| fixed pages, columns, floats, footnotes, complex tables | representable; Gate 8 diagnostic |
| `Archive` and `AccessibleArchive` profiles | representable; profile diagnostic |

Capability diagnostics carry a stable dotted feature code, a human-facing
roadmap explanation, validation stage, and deterministic location. Branch on
the code and display the message.

## Advanced modules

The lower-level modules expose public authoring values and the typed vocabulary
used between compiler stages. Raw stores are not a shortcut around validation.
The common path uses opaque `Scene.Drawing`, `Image.Source`, and `Pdf.Prepared`
values; PDF object and serialization internals remain private.
