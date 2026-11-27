app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import pf.OsStr
import pf.Stderr
import pf.Path
import pf.Stdout
import weaver.Cli
import weaver.Param
import pdf.Pdf
import Invoice

main! = |args| {
	selection = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => { output: "invoice-with-data.pdf", profile: Pdf.Profile.AccessibleArchiveWithFiles }
		Ok(Ok("archive-only")) => { output: "invoice-with-data-archive.pdf", profile: Pdf.Profile.ArchiveWithFiles }
		Ok(Ok("reject-static")) => { output: "invoice-with-data-rejected.pdf", profile: Pdf.Profile.Archive }
		Ok(Ok(_)) => return Err(Usage("Use archive-only, reject-static, or no argument."))
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

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose archive-only or reject-static." }),
		{ name: "invoice-with-data", version: "unversioned", authors: [], description: "Generate an invoice with an associated XML file.", text_style: Plain },
	),
)
