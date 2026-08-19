app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Pdf
import pdf.Theme

main! = |_args| {
	ink : Color.SourceValue
	ink = Srgb(Rgb({ red: 7000, green: 18000, blue: 39000 }))
	accent : Color.SourceValue
	accent = Srgb(Rgb({ red: 52000, green: 9000, blue: 18000 }))
	theme = Theme.default.with_text_color(ink).with_title_color(accent).with_heading_color(accent)
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
