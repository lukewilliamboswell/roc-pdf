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

Group related blocks with `Pdf.part`, `Pdf.section`, and `Pdf.division`. They
become PDF 2.0 `Part`, `Sect`, and `Div` structure elements around their
children, in authored order; headings inside keep their explicit `H1`..`H6`
levels, and grouping never changes layout:

```roc
contents = [
    Pdf.title("Operations handbook"),
    Pdf.part([
        Pdf.section([
            Pdf.heading(1, "Receiving"),
            Pdf.paragraph("Deliveries arrive between 7 am and 3 pm."),
            Pdf.division([Pdf.bullets(["Count the cartons", "Check each seal"])]),
        ]),
    ]),
]
```

A container must hold at least one semantic block, and containers nest at most
16 levels. Violations return `InvalidDocument` with the dotted codes
`semantics.empty_container` or `semantics.container_depth` and the container's
block path, such as `contents[1].contents[0]`, as the diagnostic detail. Every
tagged document also asks readers to display its metadata title
(`/ViewerPreferences << /DisplayDocTitle true >>`).

Write paragraphs with inline structure through `Pdf.rich_paragraph`. Each
inline constructor fixes the PDF 2.0 role its content becomes, and the
paragraph wraps as one text, breaking lines across inline boundaries:

```roc
Pdf.rich_paragraph([
    Pdf.text("Revenue rose "),
    Pdf.strong([Pdf.text("5.0%")]),
    Pdf.text(", reported net of "),
    Pdf.expansion("GST", "Goods and Services Tax"),
    Pdf.text(". Our supplier "),
    Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
    Pdf.text(" keeps stock code "),
    Pdf.code("WMS-7"),
    Pdf.text("; see "),
    Pdf.inline_link([Pdf.emphasis([Pdf.text("the audit")])], "https://example.org/audit"),
    Pdf.text("."),
])
```

`emphasis`, `strong`, `code`, and `quote` become `Em`, `Strong`, `Code`, and
`Quote`; `in_language` a `Span` with `/Lang`; `expansion` a `Span` with `/E`;
and `inline_link` or `inline_internal_link` a `Link` whose annotation covers
its painted text, one quadrilateral per line. Quotation marks are authored
text. Inline roles paint like the surrounding text unless the theme colors
them (`Theme.with_emphasis_color`, `with_strong_color`, `with_code_color`,
`with_quote_color`); the package ships one regular face and never
synthesizes bold or italic.

Rejections name the inline's authored path below its block, such as
`contents[2].inlines[1].inlines[0]`: `semantics.inline_empty` (no text, or an
empty inline), `semantics.link_text_empty`, `semantics.nested_link`,
`semantics.inline_depth` (more than 8 nested inline elements),
`semantics.language_tag`, `semantics.link_uri`, and, for unsupported text in a
span, `text.unsupported_script` and `text.unsupported_cluster`.

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

`Pdf.Options.default` selects the `Archive` profile, which claims PDF 2.0 plus
static PDF/A-4. The canonical XMP declares `pdfaid:part` 4 and `pdfaid:rev`
2020, the packaged sRGB output intent characterizes every color, and every
font is embedded. Profile and lowered-plan validation run before any byte is
emitted. A document that cannot meet the claim fails with an `InvalidDocument`
batch whose `ProfileRequirementViolated` diagnostic names the ledger
requirement and the ISO 19005-4 clause. It is never silently emitted as
`Standard`.

To produce plain PDF 2.0 deliberately, opt out explicitly:

```roc
options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Standard)
```

`AccessibleArchive` still rejects with an `InvalidDocument` diagnostic batch
until PDF/UA-2 closes. The package does not read, repair, sign, encrypt,
outline, or rasterize PDFs.

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
| parts, sections, and divisions (`Pdf.part`, `Pdf.section`, `Pdf.division`) | executable |
| rich paragraphs: emphasis, strong, code, quote, inline links, language spans, and expansions | executable |
| explicit line breaks, page fields, and a distinct face per inline role | not yet offered |
| simple tables | representable; Gate 6 diagnostic |
| fixed pages, columns, floats, footnotes, complex tables | representable; Gate 8 diagnostic |
| `Archive` profile (static PDF/A-4, the default) and `Standard` | executable |
| `AccessibleArchive` profile | representable; profile diagnostic |

Capability diagnostics carry a stable dotted feature code, a human-facing
roadmap explanation, validation stage, and deterministic location. Branch on
the code and display the message.

## Advanced modules

The lower-level modules expose public authoring values and the typed vocabulary
used between compiler stages. Raw stores are not a shortcut around validation.
The common path uses opaque `Scene.Drawing`, `Image.Source`, and `Pdf.Prepared`
values; PDF object and serialization internals remain private.
