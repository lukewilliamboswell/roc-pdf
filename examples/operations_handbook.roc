app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Pdf

main! = |_args| {
	procedure = "Confirm the owner, record the decision, perform the check, and attach the resulting evidence before hand-off."
	contents = [Pdf.title("Operations handbook"), Pdf.paragraph("Repeatable procedures for the on-call team.")].concat(
		List.repeat(Pdf.paragraph(procedure), 41),
	)
	document = Pdf.document({ title: "Operations handbook", language: "en", contents })
	bytes = Pdf.to_bytes(document).map_err(|err| PdfFailed(err))?
	output : Path
	output = "operations-handbook.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
