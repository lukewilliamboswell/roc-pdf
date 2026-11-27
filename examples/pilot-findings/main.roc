app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import pf.Path
import pf.OsStr
import pf.Stderr
import pf.Stdout
import weaver.Cli
import weaver.Param
import Pilot
import pdf.Pdf

main! = |args| {
	document = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => Pilot.document(1)
		Ok(Ok("keep-together")) => Pilot.kept({})
		Ok(Ok(_)) => return Err(Usage)
	}
	prepared = Pdf.prepare(document, Pilot.options).map_err(|error| PdfFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| PdfFailed(error))?
	target : Path
	target = "pilot-findings.pdf"
	target.write_bytes!(bytes).map_err(|error| WriteFailed(error))
}

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose keep-together to exercise the required keep." }),
		{ name: "pilot-findings", version: "unversioned", authors: [], description: "Generate a two-column pilot report.", text_style: Plain },
	),
)
