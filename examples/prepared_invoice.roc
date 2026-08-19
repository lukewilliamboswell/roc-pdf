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
	blue = Color.srgb8({ red: 25, green: 82, blue: 132 })
	base_title = Theme.title_style(Theme.default)
	base_heading = Theme.heading_style(Theme.default)
	theme = Theme.default
		.with_title_style({ ..base_title, color: blue, size: Layout.Unit.points(32), leading: Layout.Unit.points(38) })
		.with_heading_style({ ..base_heading, color: blue, size: Layout.Unit.points(11), leading: Layout.Unit.points(16) })
		.with_page_margin({ top: Layout.Unit.points(54), right: Layout.Unit.points(54), bottom: Layout.Unit.points(54), left: Layout.Unit.points(270) })
		.with_paragraph_spacing(Layout.Unit.points(12))
	document = Pdf.document({
		title: "Invoice 1048",
		language: "en-AU",
		contents: [
			Pdf.title("Invoice 1048"),
			Pdf.paragraph("Bill to: Northstar Cooperative"),
			Pdf.heading(1, "Services"),
			Pdf.bullets(["Design review — AUD 900", "Implementation support — AUD 1,400"]),
			Pdf.heading(1, "Total"),
			Pdf.paragraph("AUD 2,300 due 2 September 2026"),
		],
	})
	prepared = Pdf.prepare(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|err| EmitFailed(err))?
	output : Path
	output = "invoice-1048.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
