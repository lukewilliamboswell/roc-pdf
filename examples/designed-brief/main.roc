app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Path
import pf.Stdout
import pdf.Pdf
import Brief

main! = |_| {
	bytes = Pdf.to_bytes_with(Brief.document(1), { theme: Brief.theme, wtpdf: DeclareAccessibility }).map_err(|error| PdfFailed(error))?
	output : Path
	output = "designed-brief.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote designed-brief.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
