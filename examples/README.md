# Example gallery

Each example is a complete [basic-cli 0.23.0](https://github.com/roc-lang/basic-cli/releases/tag/0.23.0)
application that imports the local package. Every example has its own
directory:

```text
examples/<name>/
  main.roc      the application
  <name>.pdf    the PDF it writes
  preview.png   the first page, rendered by pdftoppm at 96 dpi
  fonts/        the fonts it registers, with their license texts
```

Run an example from its directory, where it writes its PDF:

```sh
cd examples/product-brief
roc main.roc
```

An example imports only files inside its own directory, so the directory
works unchanged against the released package bundle once the `pdf`
dependency names the bundle URL. `scripts/check_gallery.py` regenerates
every PDF and checks that it equals the committed bytes, and with
`--bundle-path` it does the same against a served bundle.

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
</tr>
</table>

| Example | Typefaces | What it demonstrates |
| --- | --- | --- |
| [Quarterly report](quarterly-report/main.roc) | Noto Serif | a members' report for a regional cooperative: a cover band in the first-page header, a tinted "at a glance" callout through the custom-block seam, a KPI scorecard and a segment table with a totals footer, two labelled vector charts built from `Scene` groups, callouts whose labels take their own accent colour through `Pdf.scoped`, and running headers with `Page N of M` |
| [Brand brief](brand-brief/main.roc) | Public Sans, Source Code Pro | brand guidelines: running headers and footers, a palette strip and section bands as decorations, an "At a glance" callout, vector figures of named colour swatches and logo placements, tables with spanning group rows, rich inline content, lists, links, and an outline over named destinations |
| [Field guide](field-guide/main.roc) | Literata | a pocket guide to estuary shorebirds: a labelled vector habitat cross-section and named bird plates, species accounts that are outline destinations and cross-reference one another, identification lists, a survey checklist table, a field-etiquette callout, page labels, and running furniture |
| [Operations handbook](operations-handbook/main.roc) | Source Sans 3, Source Code Pro | an on-call runbook: `Page N of M` furniture, an outline over numbered sections, severity and escalation tables, numbered procedures with nested steps and inline commands, warning, note, and command-panel callouts with labels in each callout's colour, and a vector service-topology diagram with named tiers |
| [Business letter](warranty-letter/main.roc) | built-in RocPdfSans | the reference business letter: a semantic letterhead in the first-page lead region, a vector logo and centered footer, continuation headers with `Page N of M`, an unsplittable signature block, and an explicit break before the covered-items schedule; no visible title, with the metadata title displayed |
| [Release notes](release-notes/main.roc) | Noto Sans, Source Code Pro | release notes on US Letter: a decorative version banner, highlights and breaking-change callouts, versioned sections in the outline, change lists with inline code and underlined issue links, a labelled latency chart, a compatibility table with strong new versions, and running furniture |
| [Business report](business-report/main.roc) | built-in RocPdfSans | the reference business report: outline and link destinations for numbered sections, rich inline content with expansions, code, and a French quotation, nested lists, a "Key figures" callout through the custom-block seam, a vector bar chart and a JPEG photograph as captioned figures, and a 40-row register that continues with its header repeated |
| [Tax invoice](tax-invoice/main.roc) | built-in RocPdfSans | the reference multi-page invoice: first and continuation page templates with a vector logo and exact `Page N of M`, a key/value table, a 32-row items table with a repeated header and a totals group, and prepare-once emission |
| [Chunked export](chunked-export/main.roc) | Source Code Pro | a cold-chain telemetry export emitted incrementally with `Pdf.to_chunks_prepared`: a summary callout, a generated temperature chart with axis labels, a legend, and its safe band, and a 48-row readings table that continues across pages with its header repeated and a summary footer |
| [Product brief](product-brief/main.roc) | Inter, Source Code Pro | a US Letter launch brief: a vector hero illustration with labelled columns, a key-figures callout, a labelled line chart with its data table, a plan comparison table with spanning group rows and a price footer, rich inline content with code, lists, links, `Page N of M` furniture, and an outline |

The applications vary information architecture, lifecycle, navigation, page
format, and visual theme. The business report, business letter, and tax
invoice are the reference documents of
[docs/reference-documents.md](../docs/reference-documents.md); the
`tests/reference_documents` family prepares the same documents and checks
that their bytes equal the committed PDFs here, so they keep the built-in
face. The other examples register their fonts through the public font
registry (`Font.Registry.register`) and select a Bold, Italic, or monospace
face per inline role with `Theme.with_inline_font`, a Bold face for the
title and headings through `Theme.with_title_style` and
`Theme.with_heading_level_style` (level-1 and level-2 headings differ in
several), and scale inline code to the body text with
`Theme.with_inline_scale`. Links take a colour and an underline from
`Theme.with_link_color` and `Theme.with_link_underline`. Their charts,
illustrations, and diagrams are vector drawings built from `Scene` groups
with real, searchable text labels (`Scene.Drawing.text`), and the business
report places a JPEG photograph as an accessible figure with authored
alternative text and a caption.

Fonts are retained byte-for-byte from their upstream releases under OFL-1.1;
[vendor/README.md](../vendor/README.md) records each archive, and
`assets/provenance.json` records each file.
