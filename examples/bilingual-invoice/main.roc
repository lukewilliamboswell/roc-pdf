app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import Invoice
import pf.Path
import pf.Stdout
import pdf.Pdf

main! = |_args| {
	options = Invoice.options({})?
	document = Invoice.document({})
	bytes = Pdf.to_bytes_with(document, options).map_err(|error| InvoiceRejected(error))?
	output : Path
	output = "bilingual-invoice.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote bilingual-invoice.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
