# Example gallery

Each example is a complete [basic-cli](https://github.com/roc-lang/basic-cli)
application that imports the local package. Every example has its own
directory:

```text
examples/<name>/
  main.roc      the application
  <name>.pdf    the PDF it writes
  preview.png   the first page, rendered by pdftoppm at 96 dpi
  fonts/        the fonts it registers, with their license texts
```

Use the Roc compiler named in [`.roc-version`](../.roc-version) for a checkout.
If you use a published bundle, follow its [release instructions](https://github.com/lukewilliamboswell/roc-pdf/releases).

Run an example from its directory, where it writes its PDF:

```sh
cd examples/product-brief
roc run main.roc
```

An example imports only files inside its own directory, so the directory
works unchanged against the released package bundle once the `pdf`
dependency names the bundle URL. `scripts/check_gallery.py` regenerates
the default and variant PDFs and checks their committed bytes. Use
`--bundle-path` to check the same programs against a served bundle.

## Run a variant

- [Operations handbook](operations-handbook/README.md) links authored contents
  to chapter and appendix page labels, and keeps rich blocks inside a
  continued numbered rollback step.
- [Source highlighting](source-blocks/README.md) colors original UTF-8 ranges
  without changing selectable YAML or pagination.
- [Tax invoice](tax-invoice/README.md) compares `KeepRows` and `SplitRows` on
  the same long description.
- [Business report](business-report/README.md) prints a preparation report and
  checks the fit of a packed RGB heat map.
- [Ordered Latin and Han fonts](ordered-han/README.md) covers tagged body
  text, running furniture, and a numeric cell.
- [Chunked export](chunked-export/README.md) streams to a file and compares
  compression and retention choices.
- [Pocket field guide](field-guide/README.md) uses custom pages and contrasts
  a preferred species note keep with a required survey sheet.
- [Audit log](audit-log/README.md) appends compact text batches and selects
  PDF output profiles.

<table>
<tr>
<td><a href="quarterly-report/quarterly-report.pdf"><img src="quarterly-report/preview.png" alt="Quarterly report preview"></a><br><a href="quarterly-report/main.roc">Quarterly report source</a></td>
<td><a href="brand-brief/brand-brief.pdf"><img src="brand-brief/preview.png" alt="Brand brief preview"></a><br><a href="brand-brief/main.roc">Brand brief source</a></td>
<td><a href="field-guide/field-guide.pdf"><img src="field-guide/preview.png" alt="Field guide preview"></a><br><a href="field-guide/main.roc">Field guide source</a></td>
</tr>
<tr>
<td><a href="operations-handbook/operations-handbook.pdf"><img src="operations-handbook/preview.png" alt="Operations handbook preview"></a><br><a href="operations-handbook/main.roc">Operations handbook source</a></td>
<td><a href="warranty-letter/warranty-letter.pdf"><img src="warranty-letter/preview.png" alt="Reference business letter preview"></a><br><a href="warranty-letter/main.roc">Business letter source</a></td>
<td><a href="release-notes/release-notes.pdf"><img src="release-notes/preview.png" alt="Release notes preview"></a><br><a href="release-notes/main.roc">Release notes source</a></td>
</tr>
<tr>
<td><a href="tax-invoice/tax-invoice.pdf"><img src="tax-invoice/preview.png" alt="Reference tax invoice preview"></a><br><a href="tax-invoice/main.roc">Tax invoice source</a></td>
<td><a href="chunked-export/chunked-export.pdf"><img src="chunked-export/preview.png" alt="Chunked export preview"></a><br><a href="chunked-export/main.roc">Chunked export source</a></td>
<td><a href="product-brief/product-brief.pdf"><img src="product-brief/preview.png" alt="Product brief preview"></a><br><a href="product-brief/main.roc">Product brief source</a></td>
</tr>
<tr>
<td><a href="business-report/business-report.pdf"><img src="business-report/preview.png" alt="Reference business report preview"></a><br><a href="business-report/main.roc">Business report source</a></td>
<td><a href="furniture-typography/furniture-typography.pdf"><img src="furniture-typography/preview.png" alt="Independent furniture typography preview"></a><br><a href="furniture-typography/main.roc">Furniture typography source</a></td>
<td><a href="source-blocks/source-blocks.pdf"><img src="source-blocks/preview.png" alt="Preformatted source block preview"></a><br><a href="source-blocks/main.roc">Source blocks source</a></td>
</tr>
<tr>
<td><a href="font-families/font-families.pdf"><img src="font-families/preview.png" alt="Built-in font families preview"></a><br><a href="font-families/main.roc">Built-in font families source</a></td>
<td><a href="vector-diagrams/vector-diagrams.pdf"><img src="vector-diagrams/preview.png" alt="Prepared vector diagrams preview"></a><br><a href="vector-diagrams/main.roc">Prepared vector diagrams source</a></td>
<td><a href="ordered-han/ordered-han.pdf"><img src="ordered-han/preview.png" alt="Ordered Latin and Han handover note preview"></a><br><a href="ordered-han/main.roc">Ordered Latin and Han source</a></td>
</tr>
<tr>
<td><a href="audit-log/audit-log.pdf"><img src="audit-log/preview.png" alt="Dispatch audit log preview"></a><br><a href="audit-log/main.roc">Audit log source</a></td>
</tr>
</table>

| Example | Typefaces | What it demonstrates |
| --- | --- | --- |
| [Quarterly report](quarterly-report/main.roc) | Noto Serif | a members' report for a regional cooperative: a cover band in the first-page header with its mark placed as a group, a navy key-figures callout in white text and a tinted diary callout, both measured by the package, a striped KPI scorecard with tinted status cells, a monthly revenue table beside its chart, and a segment table with a shaded totals footer, two labelled vector charts built from `Scene` groups (the targets chart kept with its notes), and running headers inset above a hairline backdrop with `Page N of M` |
| [Brand brief](brand-brief/main.roc) | Public Sans, Source Code Pro | brand guidelines: headers inset above a region backdrop rule beside the mark and edition line, a palette strip and section bands as spaced decorations, measured "At a glance" callouts on a Mist panel and in white on Indigo, vector figures of named colour swatches and logo placements, tables with shaded headers, hairline body rules, and shaded spanning group rows, rich inline content, lists, links, and an outline over named destinations |
| [Field guide](field-guide/main.roc) | Literata | an estuary shorebird guide: a labelled vector habitat cross-section and named bird plates, species accounts that are outline destinations and cross-reference one another, identification lists, a survey sheet kept whole on one page (a details table and a checklist, ruled between columns and framed, whose blank cells are empty `TD`s for the surveyor), measured callouts whose lines wrap, spaced dividers, page labels, and running furniture inset above a ruled backdrop |
| [Built-in font families](font-families/main.roc) | Inter, Merriweather, Fira Code | Inter kerning and selectable arrow spellings, all ten packaged static faces through explicit family choices, genuine bold/italic/combined emphasis, a four-style serif quotation, exact Command-K in sans/mono roles and default-source typography without file loading or registry setup |
| [Furniture typography](furniture-typography/main.roc) | Packaged face | a two-page document with an 11/15 pt body, independent 8/10 pt gray running text, and current/total-page fields in a reserved footer width |
| [Prepared vector diagrams](vector-diagrams/main.roc) | Inter | an authoring-time Mermaid/SVG adapter producing public drawing commands, curved connectors, arrowheads, multiline searchable labels, exact registered font bytes and explicit Figure alternative text/caption |
| [Source blocks](source-blocks/main.roc) | Packaged face, Source Code Pro | a YAML deployment recipe with independent source typography and a padded background that continues across pages |
| [Operations handbook](operations-handbook/main.roc) | Source Sans 3, Source Code Pro | an on-call runbook with an outline, severity and escalation tables, nested numbered procedures, a vector topology diagram, and appendices of commands and procedure drills |
| [Business letter](warranty-letter/main.roc) | Literata | the reference business letter: a letterhead whose mark sits above a navy and brass rule as furniture, with the sender's name in Bold and address in slate as semantic blocks in the first-page lead region, a centered footer below a hairline, continuation headers with `Page N of M` inset above a hairline, an unsplittable signature block, an italic enclosure title, and an explicit break before a shaded, ruled covered-items schedule; no visible title, with the metadata title displayed |
| [Release notes](release-notes/main.roc) | Noto Sans, Source Code Pro | release notes on US Letter: a decorative version banner spaced from the title, a night-blue highlights callout and a breaking-change callout, both measured by the package, versioned sections in the outline, change lists with inline code and underlined issue links, a labelled latency chart, a striped compatibility table with strong new versions and a table of changed flags, both leaving a release's missing entry as an empty cell, and running furniture |
| [Business report](business-report/main.roc) | Source Sans 3, Source Code Pro | the reference business report: a navy cover band with the reversed mark, outline and link destinations for numbered sections, rich inline content with expansions, code, and a French quotation, nested lists, a "Key figures" callout with Bold labels through the custom-block seam (measured by the extension), a captioned bar chart whose axis values, bar values, region names, and legend are real drawing labels, a captioned JPEG photograph, a revenue table with a shaded total, and a striped 40-row register that continues with its header repeated |
| [Invoice with associated data](invoice-with-data/README.md) | Inter | document-level XML embedding under explicit PDF/A-4f and combined PDF/UA-2 profiles |
| [Tax invoice](tax-invoice/main.roc) | Source Sans 3 | the reference multi-page invoice: a vector logo over a navy and brass masthead rule, continuation headers inset above a hairline and footers below one with exact `Page N of M`, a striped key/value table, a 32-row items table with white-on-navy column headers, striped and ruled rows, a repeated header, and a totals group on a brass tint, and prepare-once emission |
| [Chunked export](chunked-export/main.roc) | Source Code Pro | a cold-chain telemetry export emitted incrementally with `Pdf.to_chunks_prepared`: a measured summary callout, a generated temperature chart with axis labels, a legend, and its safe band, and a 48-row readings table with zebra rows and shaded excursions that continues across pages with its header repeated and a shaded summary footer |
| [Product brief](product-brief/main.roc) | Inter, Source Code Pro | a US Letter launch brief: a vector hero illustration with labelled columns, a narrow shaped decision-workflow paragraph, a measured key-figures callout and a customer quote in white on forest green, a labelled line chart with its data table, a plan comparison table kept whole on one page with shaded group rows, empty cells for capabilities a plan lacks, and a price footer, a support table, rich inline content with code, lists, links, `Page N of M` furniture over ruled backdrops, and an outline |

The applications vary information architecture, lifecycle, navigation, page
format, and visual theme. Use the business report, business letter and tax
invoice as complete starting points for those document types.
The font-families example uses named packaged choices without registration.
Other examples register their fonts through the public font
registry (`Font.Registry.register`) and selects a Bold, Italic, or monospace
face per inline role through the theme's `inline` record, a Bold face for
the title and headings through `title` and `headings` (level-1 and level-2
headings are `Own` styles in several), and scale inline code to the body
text with `inline: { code: { scale: Percent(90) } }`. Each example's theme
is one record, `theme(faces)`, that names only what differs from the
built-in values, with sizes as literal points. Links take a colour and an
underline from the theme's `link` record. Their charts,
illustrations, and diagrams are vector drawings built from `Scene` groups
with real, searchable text labels (`Scene.Drawing.text`, or
`Scene.Drawing.text_in` for a label in the bold or code face, such as the
brand brief's swatch names and hex values), and the business
report places a JPEG photograph as an accessible figure with authored
alternative text and a caption. Tables are shaded and ruled through
the theme's `table` record (`header_fill`, `body_fills`, `footer_fill`,
`body_rule`, and, in the field guide, `column_rule` and `frame`), with
single cells tinted by `cell.shaded(color)`, and row header cells keep the
body colour unless `row_header_color` sets one. A cell the table leaves
blank is `Pdf.cell([])`, an empty `TD` with no content, never a dash.
Code spans keep their words whole, so a hyphenated flag never breaks
across lines. Callouts size themselves with
`Pdf.measure_custom_content`, so their paragraphs may wrap, and a scope's
`Text` colour sets light text on a dark panel. Header rules sit in a
region `backdrop` beside the slots' furniture, with the header text
lifted clear of the rule by the region's `slot_inset`, and dividers and
banners keep their gaps through a decoration's `above` and `below`.

The [font notices](../vendor/README.md) and [asset manifest](../assets/provenance.json)
record the OFL fonts, including the small derived Han face.
