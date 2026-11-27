app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import Notice
import pf.Path
import pf.Stdout
import pdf.Pdf

main! = |_args| {
	options = Notice.options({})?
	document = Notice.document({})
	bytes = Pdf.to_bytes_with(document, options).map_err(|error| NoticeRejected(error))?
	output : Path
	output = "thai-notice.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote thai-notice.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
