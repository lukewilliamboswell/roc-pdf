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

Build lists from items that hold blocks. `Pdf.bullet_list` and
`Pdf.numbered_list` become an `L` whose `ListNumbering` states its labels
(`/Disc`, or the number style); each `Pdf.list_item` becomes an `LI` with a
generated `Lbl` and an `LBody` of its blocks. Items hold paragraphs, rich
paragraphs, and nested lists, and begin with a paragraph, whose first line the
label paints beside. Every nesting level is indented by the theme's list
indent (`Theme.with_bullet_indent`):

```roc
Pdf.numbered_list(
    { start: 1, style: Decimal },
    [
        Pdf.list_item([Pdf.paragraph("Extend the certified timber programme.")]),
        Pdf.list_item([
            Pdf.paragraph("Open the second dispatch dock:"),
            Pdf.bullet_list([
                Pdf.list_item([Pdf.paragraph("pour the slab,")]),
                Pdf.list_item([Pdf.paragraph("fit the levellers.")]),
            ]),
        ]),
    ],
)
```

Number styles are `Decimal`, `LowerAlpha`, `UpperAlpha`, `LowerRoman`, and
`UpperRoman`; labels read `1.`, `b.`, `iv.`. The plain-text `Pdf.bullets`
remains and now also declares `ListNumbering /Disc`. Lists nest at most four
deep. Rejections name the list, item, or block path, such as
`contents[3].items[1].contents[0]`: `semantics.list_empty`,
`semantics.list_item_empty`, `semantics.list_item_content` (an item holding
anything else, or not beginning with a paragraph), `semantics.list_depth`,
`semantics.list_numbering` (letters or Roman numerals from 0, or Roman
numerals past 3999), and `layout.list_label_width` (a label wider than the
list indent).

Control the flow explicitly:

- `Pdf.line_break` ends a line inside a rich paragraph without painting a
  glyph; it must separate text (`semantics.line_break_position`).
- `Pdf.page_break` starts the next block on a new page. It must separate two
  blocks, and never asks for an empty page (`layout.page_break_position`).
- `Pdf.spacer(Layout.Unit.points(12))` adds layout-only space after the
  previous block; space at the top of a page is suppressed.
- `Pdf.keep_together(blocks)` keeps blocks on one page. It is a required
  constraint; a group taller than a page body is `layout.keep_conflict`.
- `Pdf.keep_with_next(Required, block)` keeps a block on the same page as
  the next block's first lines (its orphan minimum, or all of an unsplittable
  block). `Preferred` makes the keep a ranked preference instead.

Build ordinary tables from columns and rows of cells. `Pdf.table` becomes a
`Table` with an optional `Caption`, one `THead`, `TBody`, and `TFoot`, a `TR`
per row, and a `TH` or `TD` per cell:

```roc
Pdf.table({
    caption: Pdf.caption("Items supplied under purchase order PO 88213"),
    columns: [
        { width: Content, align: Start },
        { width: Share(1), align: Start },
        { width: Fixed(Layout.Unit.points(80)), align: End },
    ],
    header_rows: [
        Pdf.row([
            Pdf.header_cell(Column, [Pdf.text("Code")]),
            Pdf.header_cell(Column, [Pdf.text("Description")]),
            Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")]),
        ]),
    ],
    body_rows: [
        Pdf.row([
            Pdf.header_cell(Row, [Pdf.text("HF-DSK-140")]),
            Pdf.cell([Pdf.text("Standing desk frame, twin motor")]),
            Pdf.cell([Pdf.text("2,756.00")]),
        ]),
    ],
    footer_rows: [
        Pdf.row([
            Pdf.spanning(2, Pdf.header_cell(Row, [Pdf.text("Total due (AUD)")])),
            Pdf.cell([Pdf.strong([Pdf.text("2,756.00")])]),
        ]),
    ],
    row_split: KeepRows,
})
```

Cells hold inline content that wraps within the column; a header cell
declares its `Scope` (`Column`, `Row`, or `Both`), and `Pdf.spanning(n, cell)`
spans columns. Every cell gets a generated identifier, and each data cell's
`Headers` name the column headers above it and the row headers beside it,
derived from the declared scopes. Column widths resolve once per table:
`Fixed` widths are exact, `Content` columns take their content's width,
reduced toward their widest word only as needed, and `Share` columns divide
the rest. `End` aligns amounts at the column's end edge.

Tables continue across pages. The header rows repaint at the top of every
continuation page as a pagination artifact, never as new rows; the table
start (caption, header rows, first body row) is placed together; footer rows
stay together after the last body row and prefer to carry at least one body
row. `KeepRows` (the default) moves a row that does not fit to the next page
and rejects a row taller than a page body as `layout.oversize_row`;
`SplitRows` lets a row break at a line boundary. Table presentation is theme
policy: `Theme.with_table_cell_padding`, `with_table_row_gap`,
`with_table_rule`, and `with_table_header_color`. Rejections name the table,
row, or cell, such as `contents[4].table.body_rows[17].cells[1]`:
`table.grid_mismatch`, `table.header_missing`, `table.empty`,
`table.cell_empty`, `table.row_span` (row spans are Gate 8),
`layout.table_width`, `layout.unbreakable_token`, and `layout.table_rule`.

Documents are bounded: up to 16,384 content occurrences, structure elements,
and text sources, and 1,024 pages. A document past a bound fails with the
`BudgetExceeded` diagnostic `document.content_limit`, naming the table or
block at which it was crossed.

Mandatory constraints are never relaxed: a conflict between them, or an
unsplittable block taller than a page (`layout.oversize_block`), returns
`InvalidDocument` naming every participating block path. Among the breaks
that satisfy them, pagination prefers, in rank order, heading keeps (R1),
preferred author keeps (R2), a table's footer rows carrying a body row (R3),
the orphan minimum (R4), and the widow minimum (R5), choosing the latest best break on each page. A preference that no legal
break can satisfy is relaxed deterministically and recorded as a layout
outcome for the planned preparation report.

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
| titles, headings, paragraphs, links, destinations | executable |
| sRGB role styling, font selection, page size, spacing and margins | executable |
| prepared and chunked emission | executable |
| one-image figures using typed JPEG/packed raster sources | executable |
| vector/grouped/multi-command drawings | representable; `document.figure` diagnostic |
| parts, sections, and divisions (`Pdf.part`, `Pdf.section`, `Pdf.division`) | executable |
| rich paragraphs: emphasis, strong, code, quote, inline links, language spans, and expansions | executable |
| bulleted and numbered lists with nested blocks, `Pdf.bullets` | executable |
| explicit line and page breaks, spacers, required and preferred keeps | executable |
| ordinary tables with captions, header rows, column spans, footers, and repeated headers | executable |
| page fields and a distinct face per inline role | not yet offered |
| fixed pages, columns, floats, footnotes, row spans, complex tables | representable; Gate 8 diagnostic |
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
