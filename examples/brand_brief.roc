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
	ink = Color.srgb8({ red: 27, green: 70, blue: 152 })
	accent = Color.srgb8({ red: 202, green: 35, blue: 70 })
	base_title = Theme.title_style(Theme.default)
	base_heading = Theme.heading_style(Theme.default)
	theme = Theme.default
		.with_text_color(ink)
		.with_title_style({ ..base_title, color: accent, size: Layout.Unit.points(38), leading: Layout.Unit.points(44) })
		.with_heading_style({ ..base_heading, color: accent, size: Layout.Unit.points(13), leading: Layout.Unit.points(18) })
		.with_page_margin({ top: Layout.Unit.points(96), right: Layout.Unit.points(54), bottom: Layout.Unit.points(72), left: Layout.Unit.points(108) })
		.with_paragraph_spacing(Layout.Unit.points(14))
	document = Pdf.document({
		title: "Lumen brand brief",
		language: "en",
		contents: [
			Pdf.title("Lumen"),
			Pdf.paragraph("A practical identity for calm, precise software."),
			Pdf.heading(1, "Voice"),
			Pdf.bullets(["Direct, never abrupt", "Technical, never opaque", "Warm, never ornamental"]),
		],
	})
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "brand-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
