app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.Path
import Pilot
import pdf.Pdf

main! = |args| {
	document = match args.get(1) {
		Err(OutOfBounds) => Pilot.document(1)
		Ok("keep-together") => Pilot.kept({})
		Ok(_) => return Err(Usage)
	}
	prepared = Pdf.prepare(document, Pilot.options).map_err(|error| PdfFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| PdfFailed(error))?
	target : Path
	target = "pilot-findings.pdf"
	target.write_bytes!(bytes).map_err(|error| WriteFailed(error))
}
