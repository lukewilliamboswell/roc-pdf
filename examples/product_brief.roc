app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Pdf
import pdf.Theme

main! = |_args| {
	green : Color.SourceValue
	green = Srgb(Rgb({ red: 4000, green: 33000, blue: 21000 }))
	theme = Theme.default.with_heading_color(green).with_title_color(green)
	document = Pdf.document({
		title: "Sprout product brief",
		language: "en",
		contents: [
			Pdf.title("Sprout"),
			Pdf.paragraph("Planning software for small teams that prefer clarity over ceremony."),
			Pdf.heading(1, "The problem"),
			Pdf.paragraph("Important decisions disappear across chat, tickets, and meeting notes."),
			Pdf.heading(1, "The approach"),
			Pdf.bullets(["One visible decision log", "Typed ownership", "Exports that remain useful offline"]),
			Pdf.heading(1, "Learn more"),
			Pdf.link("Visit the product site", "https://example.com/sprout"),
		],
	})
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "product-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
