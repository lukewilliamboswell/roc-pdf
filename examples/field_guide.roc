app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Pdf

main! = |_args| {
	document = Pdf.document({
		title: "Coastal field guide",
		language: "en-AU",
		contents: [
			Pdf.title("Coastal field guide"),
			Pdf.destination_heading("habitat", 1, "Habitat"),
			Pdf.paragraph("Look for sheltered dunes, heath, and tidal wetlands."),
			Pdf.link("Atlas of Living Australia", "https://www.ala.org.au/"),
			Pdf.destination_heading("survey", 1, "Survey notes"),
			Pdf.paragraph("Record weather, location, and observed behaviour."),
			Pdf.internal_link("Return to habitat", "habitat"),
		],
	}).with_outline([
		{ depth: 0, destination: "habitat", open: True, title: "Habitat" },
		{ depth: 0, destination: "survey", open: True, title: "Survey notes" },
	]).with_page_labels([{ prefix: "FG-", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes(document).map_err(|err| PdfFailed(err))?
	output : Path
	output = "field-guide.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
