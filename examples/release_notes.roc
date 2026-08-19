app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Theme

main! = |_args| {
	indigo = Color.srgb8({ red: 66, green: 60, blue: 145 })
	base_heading = Theme.heading_style(Theme.default)
	theme = Theme.default
		.with_title_color(indigo)
		.with_heading_style({ ..base_heading, color: indigo, size: Layout.Unit.points(12), leading: Layout.Unit.points(15) })
		.with_page_margin({ top: Layout.Unit.points(36), right: Layout.Unit.points(126), bottom: Layout.Unit.points(36), left: Layout.Unit.points(54) })
		.with_paragraph_spacing(Layout.Unit.points(5))
	builder = Document.builder({ title: "Release notes", language: "en" })
		.add_title("roc-pdf 0.1.0-rc2")
		.add_paragraph("A deterministic PDF 2.0 generator written in pure Roc.")
		.add_heading(1, "Highlights")
		.add_bullets(["Opaque prepared plans", "sRGB theme colors", "Generated public docs"])
		.add_heading(1, "Compatibility")
		.add_paragraph("The Standard profile is available. Archive profiles remain explicit capability errors.")
	document = builder.finish()
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "release-notes.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
