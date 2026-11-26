app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pdf.Pdf
import pf.Path
import pf.Stdout
import Remittance

main! = |_| {
	bytes = Pdf.to_bytes(Remittance.document(2)).map_err(|error| PdfFailed(error))?
	output : Path
	output = "remittance-advice.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote remittance-advice.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
