# Example gallery

Each example is a complete [basic-cli 0.23.0](https://github.com/roc-lang/basic-cli/releases/tag/0.23.0)
application that imports the local package and writes a PDF beside the source.
Run one from its directory with `roc main.roc`.

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

| Application | What it demonstrates |
| --- | --- |
| [Quarterly report](quarterly-report/main.roc) | a generated KPI chart, compact typography, tight margins, sections, and lists |
| [Brand brief](brand-brief/main.roc) | display-scale type, asymmetric margins, and role-specific sRGB colors |
| [Field guide](field-guide/main.roc) | a generated coastal illustration, navigation, page labels, and compact page rhythm |
| [Operations handbook](operations-handbook/main.roc) | dense typography and deterministic multi-page pagination |
| [Business letter](warranty-letter/main.roc) | the reference business letter: a semantic letterhead in the first-page lead region, a vector logo and centered footer, continuation headers with `Page N of M`, an unsplittable signature block, and an explicit break before the covered-items schedule; no visible title, with the metadata title displayed |
| [Release notes](release-notes/main.roc) | compact builder authoring with a narrow editorial measure |
| [Business report](business-report/main.roc) | the reference business report: outline and link destinations for numbered sections, rich inline content with expansions, code, and a French quotation, nested lists, a separately authored "Key figures" callout through the custom-block seam, a vector bar chart and a JPEG photograph as captioned figures, and a 40-row register that continues with its header repeated |
| [Tax invoice](tax-invoice/main.roc) | the reference multi-page invoice: first and continuation page templates with a vector logo and exact `Page N of M`, a key/value table, a 32-row items table with a repeated header and a totals group, and prepare-once emission |
| [Chunked export](chunked-export/main.roc) | incremental output, wide measure, and explicit list indentation |
| [Product brief](product-brief/main.roc) | a generated product illustration, oversized display type, whitespace, links, and lists |

The applications vary information architecture, lifecycle, navigation, page
format, and visual theme. The business report, business letter, and tax
invoice are the reference documents of
[docs/reference-documents.md](../docs/reference-documents.md); the
`tests/reference_documents` family prepares the same documents and checks
that their bytes equal the committed PDFs here. Three other applications
create packed raster artwork in pure Roc and place it as an accessible figure
with authored alternative text and a caption. Fixed-position layouts and
general composition remain forward API and return feature-specific
diagnostics instead of degrading.
