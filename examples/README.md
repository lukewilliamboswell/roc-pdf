# Example gallery

Each example is a complete [basic-cli 0.23.0](https://github.com/roc-lang/basic-cli/releases/tag/0.23.0)
application that imports the local package and writes a PDF beside the source.
Run one from the repository root with `roc examples/<name>.roc`.

<table>
<tr>
<td><a href="quarterly-report.pdf"><img src="previews/quarterly-report.png" alt="Quarterly report preview"></a><br><a href="quarterly_report.roc">Quarterly report source</a></td>
<td><a href="brand-brief.pdf"><img src="previews/brand-brief.png" alt="Brand brief preview"></a><br><a href="brand_brief.roc">Brand brief source</a></td>
<td><a href="field-guide.pdf"><img src="previews/field-guide.png" alt="Field guide preview"></a><br><a href="field_guide.roc">Field guide source</a></td>
</tr>
<tr>
<td><a href="operations-handbook.pdf"><img src="previews/operations-handbook.png" alt="Operations handbook preview"></a><br><a href="operations_handbook.roc">Operations handbook source</a></td>
<td><a href="warranty-letter.pdf"><img src="previews/warranty-letter.png" alt="Reference business letter preview"></a><br><a href="letter.roc">Business letter source</a></td>
<td><a href="release-notes.pdf"><img src="previews/release-notes.png" alt="Release notes preview"></a><br><a href="release_notes.roc">Release notes source</a></td>
</tr>
<tr>
<td><a href="tax-invoice.pdf"><img src="previews/tax-invoice.png" alt="Reference tax invoice preview"></a><br><a href="prepared_invoice.roc">Tax invoice source</a></td>
<td><a href="chunked-export.pdf"><img src="previews/chunked-export.png" alt="Chunked export preview"></a><br><a href="chunked_export.roc">Chunked export source</a></td>
<td><a href="product-brief.pdf"><img src="previews/product-brief.png" alt="Product brief preview"></a><br><a href="product_brief.roc">Product brief source</a></td>
</tr>
</table>

| Application | What it demonstrates |
| --- | --- |
| [Quarterly report](quarterly_report.roc) | a generated KPI chart, compact typography, tight margins, sections, and lists |
| [Brand brief](brand_brief.roc) | display-scale type, asymmetric margins, and role-specific sRGB colors |
| [Field guide](field_guide.roc) | a generated coastal illustration, navigation, page labels, and compact page rhythm |
| [Operations handbook](operations_handbook.roc) | dense typography and deterministic multi-page pagination |
| [Business letter](letter.roc) | the reference business letter: a semantic letterhead in the first-page lead region, a vector logo and centered footer, continuation headers with `Page N of M`, an unsplittable signature block, and an explicit break before the covered-items schedule; no visible title, with the metadata title displayed |
| [Release notes](release_notes.roc) | compact builder authoring with a narrow editorial measure |
| [Tax invoice](prepared_invoice.roc) | the reference multi-page invoice: first and continuation page templates with a vector logo and exact `Page N of M`, a key/value table, a 32-row items table with a repeated header and a totals group, and prepare-once emission |
| [Chunked export](chunked_export.roc) | incremental output, wide measure, and explicit list indentation |
| [Product brief](product_brief.roc) | a generated product illustration, oversized display type, whitespace, links, and lists |

The applications vary information architecture, lifecycle, navigation, page
format, and visual theme. Three applications create packed raster artwork in
pure Roc and place it as an accessible figure with authored alternative text
and a caption. Broader vector/grouped drawings and fixed layouts remain
forward API and return feature-specific diagnostics instead of degrading.
