app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import weaver.Cli
import weaver.Param
import pdf.Document
import pdf.Pdf

main! = |args| {
	{ profile, heading_level } = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => { profile: AccessibleArchive, heading_level: 1 }
		Ok(Ok("archive")) => { profile: Archive, heading_level: 1 }
		Ok(Ok("standard")) => { profile: Standard, heading_level: 1 }
		Ok(Ok("invalid")) => { profile: Archive, heading_level: 7 }
		Ok(Ok(_)) => {
			Stderr.line!("Usage: roc run main.roc [archive|standard|invalid]").map_err(|err| OutputFailed(err))?
			return Err(Exit(2))
		}
	}
	title = "Dispatch audit log"
	var $builder = Document.builder({ language: "en-AU", title }).add_title(title)
	$builder = $builder.add_heading({ level: heading_level, text: "Incoming batches" })
	for batch in ["Morning", "Afternoon", "Evening"] {
		$builder = $builder.add_paragraphs(batch_entries(batch))
	}

	# Finish and validate before opening the output file.
	bytes = match Pdf.to_bytes_with($builder.finish(), { profile: profile }) {
		Ok(value) => value
		Err(error) => {
			Stderr.line!(Pdf.Error.to_inspect(error)).map_err(|err| OutputFailed(err))?
			return Err(Exit(1))
		}
	}
	output : Path
	output = "audit-log.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote audit-log.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

# The application supplies each batch as ordinary text.
batch_entries : Str -> List(Str)
batch_entries = |batch| {
	var $entries = List.with_capacity(24)
	var $shift_index = 1
	while $shift_index <= 24 {
		$entries = $entries.append("${batch} dispatch ${$shift_index.to_str()} — pallet seal checked and recorded.")
		$shift_index = $shift_index + 1
	}
	$entries
}

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose archive, standard, or invalid." }),
		{ name: "audit-log", version: "unversioned", authors: [], description: "Generate a dispatch audit log.", text_style: Plain },
	),
)
