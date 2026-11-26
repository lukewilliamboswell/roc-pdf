app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import pdf.Pdf
import Intake

main! = |args| {
	duplicate = match args.map(OsStr.to_str_try) {
		[] => False
		[Ok("duplicate-id")] => True
		_ => return Err(Usage("Run with no argument or with duplicate-id."))
	}
	prepared = Pdf.prepare(Intake.document(duplicate), { profile: AccessibleForm }).map_err(|error| PrepareFailed(error))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|error| EmitFailed(error))?
	output : Path
	output = if (duplicate) "service-intake-invalid.pdf" else "service-intake.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote service-intake.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
