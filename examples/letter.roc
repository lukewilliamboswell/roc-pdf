app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Pdf

main! = |_args| {
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
	options = Pdf.Options.default.with_page_size(Letter)
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "project-letter.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
