app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0-rc2/Gj3zVDr3qrQa6aTh7Z1zgUfe9NeBE6R76T5ho3xrc8af.tar.zst",
}

import pdf.Color
import pdf.Pdf
import pdf.Theme
import pf.Path
import pf.Stdout

## Body text at 11/15 pt and quiet running furniture at 8/10 pt.
main! = |_args| {
	options : Pdf.Options
	options = { theme: theme }
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "furniture-typography.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote furniture-typography.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

theme : Theme
theme = { body: { size: 11, leading: 15 }, furniture: Own({ size: 8, leading: 10, color: Color.srgb8({ red: 80, green: 80, blue: 80 }) }) }

header = Pdf.region({ height: 10, start: [Pdf.furniture_text([Pdf.text("Operations manual")])] })

footer = Pdf.region({ height: 10, end: [Pdf.furniture_text([Pdf.reserved_width(70, End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])])] })

document = Pdf.document({ title: "Independent furniture typography", language: "en", contents: [Pdf.paragraph("Body text uses eleven points with fifteen-point leading."), Pdf.page_break, Pdf.paragraph("The running furniture repeats with its own typography.")], page_templates: Templates({ first: Pdf.first_page_template({ header, footer }), continuation: Pdf.page_template({ header, footer }) }) })
