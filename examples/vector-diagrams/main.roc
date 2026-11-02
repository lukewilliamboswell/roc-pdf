app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0-rc2/Gj3zVDr3qrQa6aTh7Z1zgUfe9NeBE6R76T5ho3xrc8af.tar.zst",
}

import Diagram
import pdf.Font
import pdf.Pdf
import pf.Path
import pf.Stdout

## PDF generation consumes prepared Roc data and exact font bytes only.
main! = |_args| {
	options = Diagram.options(Font.ValidationLimits.default).map_err(|err| FontRejected(err))?
	bytes = Pdf.to_bytes_with(Diagram.document(1), options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "vector-diagrams.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote vector-diagrams.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}
