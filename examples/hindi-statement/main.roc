app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import Statement
import pf.Path
import pf.Stdout
import pdf.Pdf

main! = |_args| {
	options = Statement.options({})?
	document = Statement.document({})
	bytes = Pdf.to_bytes_with(document, options).map_err(|error| StatementRejected(error))?
	output : Path
	output = "hindi-statement.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote hindi-statement.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
