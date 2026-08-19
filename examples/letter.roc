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
	ink = Color.srgb8({ red: 63, green: 52, blue: 92 })
	base_body = Theme.body_style(Theme.default)
	base_title = Theme.title_style(Theme.default)
	theme = Theme.default
		.with_text_color(ink)
		.with_body_style({ ..base_body, color: ink, size: Layout.Unit.points(12), leading: Layout.Unit.points(19) })
		.with_title_style({ ..base_title, color: ink, size: Layout.Unit.points(14), leading: Layout.Unit.points(20) })
		.with_page_margin({ top: Layout.Unit.points(108), right: Layout.Unit.points(72), bottom: Layout.Unit.points(72), left: Layout.Unit.points(108) })
		.with_paragraph_spacing(Layout.Unit.points(18))
	document = Pdf.document({
		title: "Project letter",
		language: "en-US",
		contents: [
			Pdf.title("19 August 2026"),
			Pdf.paragraph("Dear project team,"),
			Pdf.paragraph("The release candidate is ready for focused evaluation. Thank you for testing real documents and reporting exact inputs."),
			Pdf.paragraph("Regards,"),
			Pdf.paragraph("The roc-pdf maintainers"),
		],
	}).with_created("2026-08-19T00:00:00Z").with_modified("2026-08-19T00:00:00Z")
	options = Pdf.Options.default.with_page_size(Letter).with_theme(theme)
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "project-letter.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
