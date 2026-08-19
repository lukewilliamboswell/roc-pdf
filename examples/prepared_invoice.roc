app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Pdf

main! = |_args| {
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
	prepared = Pdf.prepare(document, Pdf.Options.default).map_err(|err| PdfFailed(err))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|err| EmitFailed(err))?
	output : Path
	output = "invoice-1048.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}
