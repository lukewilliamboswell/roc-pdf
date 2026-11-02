# roc-pdf

Generate searchable PDF 2.0 reports, invoices and letters from pure
[Roc](https://www.roc-lang.org/). Author text, tables and figures with the `Pdf`
facade; roc-pdf owns pagination, font embedding and deterministic output.

**[Read the manual](https://lukewilliamboswell.github.io/roc-pdf/manual/)** ·
[API reference](https://lukewilliamboswell.github.io/roc-pdf/) ·
[Latest release](https://github.com/lukewilliamboswell/roc-pdf/releases/latest)

Default `Archive` output claims static PDF/A-4. Unsupported content returns
structured diagnostics without font substitution or profile downgrade.
PDF/UA-2 is not currently claimed. See the
[authoring guide](docs/authoring.adoc#authoring-supported-features) for supported
content, profiles and limits.

<table>
<tr>
<td><a href="examples/tax-invoice/tax-invoice.pdf"><img src="examples/tax-invoice/preview.png" alt="Tax invoice preview"></a><br><a href="examples/tax-invoice/main.roc">Tax invoice source</a></td>
<td><a href="examples/business-report/business-report.pdf"><img src="examples/business-report/preview.png" alt="Business report preview"></a><br><a href="examples/business-report/main.roc">Business report source</a></td>
<td><a href="examples/warranty-letter/warranty-letter.pdf"><img src="examples/warranty-letter/preview.png" alt="Business letter preview"></a><br><a href="examples/warranty-letter/main.roc">Business letter source</a></td>
</tr>
</table>

[Browse the complete example gallery.](examples/README.md)

## Install

Copy the package dependency URL and compiler requirement from the
[release you choose](https://github.com/lukewilliamboswell/roc-pdf/releases),
then follow its linked authoring guide. The manual explains
[how to create your first document](docs/getting-started.adoc).

To run an example from this checkout, use the compiler named in
[`.roc-version`](.roc-version) and run:

```sh
roc examples/tax-invoice/main.roc
```

This writes `tax-invoice.pdf` in the current directory. For contributor setup,
testing and release procedures, start with the
[contributor documentation](development/README.md).

[Release notes](https://github.com/lukewilliamboswell/roc-pdf/releases) ·
[Universal Permissive License](LICENSE)
