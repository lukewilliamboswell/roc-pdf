app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Document
import pdf.Pdf

main! = |_args| {
	builder = Document.builder({ title: "Release notes", language: "en" })
		.add_title("roc-pdf 0.1.0-rc2")
		.add_paragraph("A deterministic PDF 2.0 generator written in pure Roc.")
		.add_heading(1, "Highlights")
		.add_bullets(["Opaque prepared plans", "sRGB theme colors", "Generated public docs"])
		.add_heading(1, "Compatibility")
		.add_paragraph("The Standard profile is available. Archive profiles remain explicit capability errors.")
	document = builder.finish()
	bytes = Pdf.to_bytes(document).map_err(|err| PdfFailed(err))?
	output : Path
	output = "release-notes.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
