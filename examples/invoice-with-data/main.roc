app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pdf.Pdf
import Invoice

main! = |args| {
	selection = match args.map(OsStr.to_str_try) {
		[] => { output: "invoice-with-data.pdf", profile: Pdf.Profile.AccessibleArchiveWithFiles }
		[Ok("archive-only")] => { output: "invoice-with-data-archive.pdf", profile: Pdf.Profile.ArchiveWithFiles }
		[Ok("reject-static")] => { output: "invoice-with-data-rejected.pdf", profile: Pdf.Profile.Archive }
		_ => return Err(Usage("Use archive-only, reject-static, or no argument."))
	}
	document = Invoice.document
	prepared = Pdf.prepare(document, { profile: selection.profile }).map_err(|error| PdfFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| EmitFailed(error))?
	output : Path
	output = Path.utf8(selection.output)
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote ${selection.output}").map_err(|error| OutputFailed(error))?
	Ok({})
}
