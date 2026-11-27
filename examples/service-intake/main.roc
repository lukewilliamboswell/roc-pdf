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
import Intake

main! = |args| {
	duplicate = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => False
		Ok(Ok("duplicate-id")) => True
		Ok(Ok(_)) => return Err(Usage("Run with no argument or with duplicate-id."))
	}
	prepared = Pdf.prepare(Intake.mixed_document(duplicate), { profile: AccessibleForm }).map_err(|error| PrepareFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| EmitFailed(error))?
	output : Path
	output = if (duplicate) "service-intake-invalid.pdf" else "service-intake.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote service-intake.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose duplicate-id to exercise duplicate field rejection." }),
		{ name: "service-intake", version: "unversioned", authors: [], description: "Generate a fillable service-intake form.", text_style: Plain },
	),
)
