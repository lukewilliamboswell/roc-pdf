app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0-rc2/Gj3zVDr3qrQa6aTh7Z1zgUfe9NeBE6R76T5ho3xrc8af.tar.zst",
}

import pf.Path
import pf.Stdout
import pdf.Pdf
import pdf.RocFont

# Family notices accompany applications distributing the packaged font assets.
expect !RocFont.licenses.sans.is_empty() and !RocFont.licenses.serif.is_empty() and !RocFont.licenses.mono.is_empty()

## Named families select exact static faces without loading files or a registry.
main! = |_args| {
	options : Pdf.Options
	options = {
		theme: {
			family: BuiltIn(Sans),
			inline: {
				code: { font: Family(BuiltIn(Mono)) },
				quote: { font: Family(BuiltIn(Serif)) },
			},
		},
	}
	document = Pdf.document({
		title: "Built-in font families",
		language: "en-AU",
		contents: [
			Pdf.title("Built-in font families"),
			Pdf.paragraph("Inter body text supports the Command shortcut ⌘K."),
			Pdf.rich_paragraph([
				Pdf.strong([Pdf.text("Genuine bold. ")]),
				Pdf.emphasis([Pdf.text("Genuine italic. ")]),
				Pdf.strong([Pdf.emphasis([Pdf.text("Genuine bold italic.")])]),
			]),
			Pdf.heading(2, "Explicit serif quotation"),
			Pdf.rich_paragraph([
				Pdf.quote([
					Pdf.text("Merriweather regular. "),
					Pdf.strong([Pdf.text("Serif bold. ")]),
					Pdf.emphasis([Pdf.text("Serif italic. ")]),
					Pdf.emphasis([Pdf.strong([Pdf.text("Serif bold italic.")])]),
				]),
			]),
			Pdf.heading(2, "Code uses its selected family"),
			Pdf.rich_paragraph([
				Pdf.code("Fira Code ⌘K"),
				Pdf.text(" and "),
				Pdf.strong([Pdf.code("genuine mono bold")]),
			]),
			Pdf.source_block({ face: BuiltIn({ family: Mono, style: Regular }), text: "shortcut = \"⌘K\"\nanswer = 42" }),
			Pdf.paragraph("Unavailable styles and characters reject before PDF bytes. Merriweather has no Command symbol; Fira Code has no genuine italic face."),
		],
	})
	bytes = Pdf.to_bytes_with(document, options).map_err(|error| PdfFailed(error))?
	output : Path
	output = "font-families.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote font-families.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
