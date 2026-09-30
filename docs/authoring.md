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
`with_quote_color`) or give them a caller-registered face with
`Theme.with_inline_font(theme, Code, face)` (a monospace face for code, say):
the innermost role with a face decides a run's face, at the paragraph's size
and leading. The face must be in the options' font registry
(`InvalidFontResource` otherwise), must cover the role's text
(`text.coverage_missing`), and applies to style faces only: a theme with an
ordered font policy reports `text.inline_font_policy`. The package ships one
regular face and never synthesizes bold or italic. To use the packaged face
beside a caller face, put it in the registry with
`Font.Registry.register_built_in(registry, Font.ValidationLimits.default)`
and select the returned face with `Theme.with_font`; it validates and embeds
exactly as the unregistered default does. Titles and headings take any
registered face through their styles, for example a bold face:
`Theme.with_title_style` and `Theme.with_heading_style` (all levels), or
`Theme.with_heading_level_style(theme, H2, style)` for one level's face,
size, leading, and color. Under an ordered font policy a title or heading
face reports `text.block_font_policy`. A role face often looks larger than
the body face at the same size; `Theme.with_inline_scale(theme, Code, 85)`
paints that role at 85% of its paragraph size (50 to 100 percent, else
`text.inline_scale`), on the paragraph's baseline and leading. Links take
their own color with `Theme.with_link_color` and an underline with
`Theme.with_link_underline(theme, Underline({ offset, thickness }))`, a
decoration artifact below each painted line of the link that must fit
below the body text inside its leading (`text.link_underline`). To color
one group of blocks differently, such as a warning callout's label in
amber and a note's in teal, wrap them in
`Pdf.scoped(Theme.Scope.empty.with_color(Strong, amber), blocks)`: the
innermost scope that colors a role wins, then the theme. A scope adds no
structure element and keeps nothing together.

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
numerals past 3999), and `layout.list_label_width` (a list label column,
widened for a label wider than the list indent, that leaves its body no
width). A wide label such as `100.` widens its whole list's label column
instead of being rejected.

Control the flow explicitly:

- `Pdf.line_break` ends a line inside a rich paragraph; it must separate
  text (`semantics.line_break_position`). The text before it gains a
  trailing space (unless it already ends in one) so extracted text keeps
  the word boundary.
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
spans columns. A cell aligns like the first column it spans unless
`Pdf.aligned(align, cell)` gives it its own alignment, such as an
end-aligned totals label spanning start-aligned columns. Every cell gets a generated identifier, and each data cell's
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
`SplitRows` lets a row break at a line boundary. Wrap a table in
`Pdf.keep_together([table])` to keep it whole on one page instead; a kept
table taller than a page body is `layout.keep_conflict`. Table presentation is theme
policy: `Theme.with_table_cell_padding`, `with_table_row_gap`,
`with_table_rule`, `with_table_header_color` (column header cells, scope
`Column` or `Both`), and `with_table_row_header_color` (row header cells,
scope `Row`). Rows can be shaded with `with_table_header_fill`,
`with_table_body_fills` (`{ odd, even }` for zebra stripes), and
`with_table_footer_fill`, and separated with `with_table_body_rule`;
`Pdf.shaded(color, cell)` shades one cell. Fills paint behind the text as
layout artifacts and never change layout. Rejections name the table,
row, or cell, such as `contents[4].table.body_rows[17].cells[1]`:
`table.grid_mismatch`, `table.header_missing`, `table.empty`,
`table.cell_empty`, `table.row_span` (row spans are Gate 8),
`layout.table_width`, `layout.unbreakable_token`, and `layout.table_rule`.

Give pages running headers, footers, and page numbers with page templates.
The first page and every later page each have a template; each template
reserves a header and a footer region of fixed height inside the body frame,
separated from the body by its gap, and the first page may also reserve a
lead region for semantic letterhead content:

```roc
page_of = Pdf.reserved_width(Layout.Unit.points(72), End, [
    Pdf.text("Page "),
    Pdf.page_number(Decimal),
    Pdf.text(" of "),
    Pdf.total_pages(Decimal),
])

letter = Pdf.with_page_templates(document, {
    first: Pdf.first_page_template({
        header: Pdf.region({ height: Layout.Unit.points(48), start: [], center: [], end: [Pdf.furniture_image(logo)] }),
        lead: Pdf.lead_region(Layout.Unit.points(60), [
            Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
            Pdf.paragraph("Level 3, 18 Wharf Street, Hobart TAS 7000"),
        ]),
        footer: Pdf.region({ height: Layout.Unit.points(16), start: [], center: [Pdf.furniture_text([Pdf.text("harbourfinch.example")])], end: [] }),
        gap: Layout.Unit.points(12),
    }),
    continuation: Pdf.page_template({
        header: Pdf.region({
            height: Layout.Unit.points(16),
            start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative Ltd · 21 September 2026")])],
            center: [],
            end: [Pdf.furniture_text([page_of])],
        }),
        footer: Pdf.no_region,
        gap: Layout.Unit.points(12),
    }),
})
```

Body text flows only in what the regions leave, so the first page and later
pages can hold different body heights. Each slot (`start`, `center`, `end`)
stacks its furniture: a header's stack sits on the region's bottom edge and a
footer's hangs from its top edge. `Pdf.furniture_text` is one line of text,
page fields, and reserved widths in the body style; `Pdf.furniture_image`
paints a drawing of images and solid paths (`Scene.rectangle`,
`Scene.solid_fill`, `Scene.solid_stroke`) whose origin is the item's
bottom-left corner. Furniture is a page artifact (`Header`, `Footer`, or
`PageNum` when a line holds a page field): it repeats on every page of its
template and never enters the structure tree or the logical text. The lead
region's blocks are semantic: a `Div` that comes first in reading order.

`Pdf.page_number` and `Pdf.total_pages` take a number style (`Decimal`,
`LowerAlpha`, `UpperAlpha`, `LowerRoman`, or `UpperRoman`) and resolve after
pagination: the first pass paginates the body, the second resolves every
field with the final page count and proves it fits. Because regions have
fixed heights, furniture never changes pagination and two passes always
suffice. Put a field in `Pdf.reserved_width(width, align, inlines)` to keep
its position fixed; its resolved content must fit the width on every page.
Page fields are furniture only; in body content they report
`document.generated_reference`. Rejections name template paths, such as
`templates.continuation.header.end[0].inlines[0].inlines[1]`:
`layout.template_body_space` (regions leave less than one body line),
`layout.template_region_overflow` (furniture or lead content taller or wider
than its region, or overlapping slots), `layout.field_overflow` (a resolved
field that does not fit, with the first page it fails on),
`layout.template_region_empty`, `layout.template_body_empty`,
`layout.furniture_inline`, `layout.furniture_drawing`, and
`semantics.inline_empty`. Furniture text is shaped through the theme's face,
or, under an ordered font policy, selects each cluster's face exactly as body
text does; a face only furniture uses becomes an extra font. Text no policy
face covers is `text.coverage_missing`, and text in an undeclared script
`text.unsupported_script`, at its furniture item path.

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

`Pdf.Options.with_page_size` selects one size for every page: `A4` (the
default), `Letter`, `A4Landscape`, `LetterLandscape`, or `Custom({ width,
height })` in whole points from 3 to 14,400 pt a side (`layout.page_size`
otherwise). Margins and templates apply unchanged, so the body frame of a
landscape page is wider; margins that leave no body frame are
`layout.page_margin`. Mixing sizes or orientations within one document is
fixed-page composition (Gate 8).

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
without leaking PDF objects or caller-assigned resource IDs. A figure's
drawing holds any number of images and solid paths, grouped with
`Scene.Drawing.group`, and requires non-empty alternative text; a visible
caption is optional:

```roc
image = Image.Source.rgb8({
    alpha: NoAlpha,
    dimensions: { width: 2, height: 2 },
    pixels: [24, 94, 134, 240, 180, 40, 40, 160, 90, 245, 245, 240],
    row_stride: 6,
})
drawing = Scene.drawing({}).image(image, Layout.rect(0, 0, 240, 120))

figure = Pdf.figure(drawing, "A four-color information panel", Pdf.caption("Figure 1"))

## A grouped vector chart: each bar pair is a group translated into place.
bars = Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 36, 120), blue), Layout.rect(40, 0, 36, 150), orange)
chart = Scene.drawing({})
    .path(Scene.path({}).move_to(Layout.point(24, 20)).line_to(Layout.point(480, 20)).finish(), Scene.solid_stroke(ink, Layout.Unit.points(1)))
    .group(Layout.point(48, 21), bars)
    .group(Layout.point(156, 21), bars)
plan = Pdf.figure_fit(Pdf.figure(site_plan, "Plan of the yard", Pdf.no_caption), ScaleToFit({ minimum_percent: 50 }))
rule = Pdf.decoration(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 6, 483, 1), ink))
```

Image pixel dimensions and layout placement are independent. Packed planes
must have valid dimensions, row stride, byte length, and supported alpha;
JPEGs additionally pass the bounded marker and orientation-policy inspector.
Invalid resources fail transactionally.

A figure is placed start-aligned in the flow at its authored size, as one
unsplittable unit with its caption below it; a caption becomes a `Caption`
beside the `Figure` in a `Sect`, so assistive technology reads it
independently of the alternative text. A figure that does not fit the flow
region is `document.figure_oversize` unless `Pdf.figure_fit` selects
`ScaleToFit({ minimum_percent })`, which scales the drawing (never its
caption) by the largest fitting factor down to the floor. `Pdf.decoration`
paints a drawing as a `Decoration` artifact that occupies its height
immediately above the next flow block and moves with it. Drawings are
validated at their authored path (`document.figure_drawing`,
`layout.decoration_drawing`). Fixed pages remain forward API: they report
`layout.custom` and emit no bytes or chunks.

An extension can contribute a block through `Pdf.custom_block` without any
PDF object or operator: it supplies ordinary paragraphs, its own
measurement of the block (`size` and a content `inset`), and a panel of
solid paths drawn behind the content, and declares it `Unsplittable`:

```roc
callout = Pdf.custom_block({
    contents: [Pdf.paragraph("Revenue: AUD 9.22 m (+5.0%)"), Pdf.paragraph("On-time delivery: 96.4%")],
    fragmentation: Unsplittable,
    inset: Layout.Unit.points(10),
    name: "Key figures",
    panel: Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 320, 70), tint),
    size: { height: Layout.Unit.points(70), width: Layout.Unit.points(320) },
})
```

The paragraphs become a `Div`; the package lays them out inside the box and
proves they fit (`layout.custom_block_measure` otherwise), and the block
moves whole to the next page. `tests/custom_block/Callout.roc` is a complete
extension that measures itself from the theme's public metrics.

`Pdf.prepare_with_report` returns the prepared document together with a
bounded, read-only `Pdf.Report`: pages, leaf blocks in reading order with
their pages, alternatives and nested languages, layout outcomes (relaxed
preferences, figure scales, repeated table headers, continued rows, placed
custom blocks), text coverage, and, separately, the human-review
obligations. Every entry names the authored path diagnostics use. The
prepared bytes are identical to `Pdf.prepare`'s, and a report over its
budget is `report.budget_exceeded` rather than a shorter report.

| Authoring surface | Status |
| --- | --- |
| titles, headings, paragraphs, links, destinations | executable |
| sRGB role styling, font selection, page size, spacing and margins | executable |
| prepared and chunked emission | executable |
| figures of typed JPEG/packed raster images and solid vector paths, grouped and multi-command, with captions and `ScaleToFit` | executable |
| in-flow decorations (`Pdf.decoration`) | executable |
| extension blocks (`Pdf.custom_block`, unsplittable) | executable |
| preparation report (`Pdf.prepare_with_report`) | executable |
| clip, opacity, and soft-mask groups and non-solid paint in flow drawings | not yet offered |
| parts, sections, and divisions (`Pdf.part`, `Pdf.section`, `Pdf.division`) | executable |
| rich paragraphs: emphasis, strong, code, quote, inline links, language spans, and expansions | executable |
| bulleted and numbered lists with nested blocks, `Pdf.bullets` | executable |
| explicit line and page breaks, spacers, required and preferred keeps | executable |
| ordinary tables with captions, header rows, column spans, footers, and repeated headers | executable |
| page templates: header, footer, and lead regions, furniture text and drawings, page and total-page fields | executable |
| a caller-registered face per inline role (style faces) | executable |
| furniture text under an ordered font policy | executable |
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
