app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Layout
import pdf.Pdf
import pdf.Theme

main! = |_args| {
	safety = Color.srgb8({ red: 181, green: 74, blue: 0 })
	base_body = Theme.body_style(Theme.default)
	theme = Theme.default
		.with_title_color(safety)
		.with_heading_color(safety)
		.with_body_style({ ..base_body, size: Layout.Unit.points(9), leading: Layout.Unit.points(12) })
		.with_page_margin({ top: Layout.Unit.points(42), right: Layout.Unit.points(42), bottom: Layout.Unit.points(42), left: Layout.Unit.points(42) })
		.with_paragraph_spacing(Layout.Unit.points(4))
	procedure = "Confirm the owner, record the decision, perform the check, and attach the resulting evidence before hand-off."
	contents = [Pdf.title("Operations handbook"), Pdf.paragraph("Repeatable procedures for the on-call team.")].concat(
		List.repeat(Pdf.paragraph(procedure), 41),
	)
	document = Pdf.document({ title: "Operations handbook", language: "en", contents })
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "operations-handbook.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
