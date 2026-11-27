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
import pdf.Color
import pdf.Font
import pdf.Pdf
import pdf.RocFont
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## One locally styled source block continues over pages. Body paragraphs
## keep their own face, size, leading, and spacing throughout the document.
main! = |args| {
	mode = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => Highlighted
		Ok(Ok("plain")) => Plain
		Ok(Ok("bad-range")) => InvalidRange
		Ok(Ok(_)) => {
			Stderr.line!("Usage: roc run main.roc [plain|bad-range]").map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
	}
	body = RocFont.register(Font.Registry.empty, Font.ValidationLimits.default).map_err(|error| FontFailed(error))?
	theme = RocFont.theme(body, {})
	mono = body.registry.register({ bytes: mono_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }).map_err(|error| FontFailed(error))?
	options : Pdf.Options
	options = { fonts: Registered(mono.registry), theme }
	{ text, foregrounds } = recipe(mode)
	document = Pdf.document({
		title: "Deployment recipe",
		language: "en",
		contents: [
			Pdf.title("Deployment recipe"),
			Pdf.paragraph("The source block has its own monospace face and presentation. Its indentation and blank lines survive page continuation."),
			Pdf.source_block({ text, foregrounds, tabs: ExpandTo(4), face: Face(mono.face), size: 9, leading: 12, padding: 8, color: Color.srgb8({ red: 25, green: 60, blue: 50 }), background: Background(Color.srgb8({ red: 242, green: 246, blue: 244 })) }),
			Pdf.paragraph("The body text resumes with the original typography after the source block."),
		],
	})
	bytes = match Pdf.to_bytes_with(document, options) {
		Ok(value) => value
		Err(error) => {
			Stderr.line!(Pdf.Error.to_inspect(error)).map_err(|err| OutputFailed(err))?
			return Err(Exit(1))
		}
	}
	output : Path
	output = "source-blocks.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote source-blocks.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}

# Adjacent source pieces also give the caller's colorizer its original UTF-8
# offsets. The long storage value keeps one range across a visual wrap.
recipe : [Highlighted, Plain, InvalidRange] -> { text : Str, foregrounds : List(Pdf.SourceForeground) }
recipe = |mode| {
	head = "# Deployment recipe\nservice: billing\nprofile: "
	profile = "café"
	storage_key = "\nstorage: "
	storage = "\"Archive completed shipment reports under /var/lib/harbour/production/billing/exports/archive before the next dispatch window.\""
	tail = Str.join_with(["\n# Worker slots\t4 per zone\nworkers:\n", Str.repeat("  - 4\n", 90), "\n# End of recipe\n"], "")
	text = Str.join_with([head, profile, storage_key, storage, tail], "")
	profile_start = head.count_utf8_bytes()
	profile_end = profile_start + profile.count_utf8_bytes()
	storage_start = profile_end + storage_key.count_utf8_bytes()
	value : Color.SourceValue
	value = "#0050A0"
	foregrounds = match mode {
		Highlighted => [
			{ start: 0, end: "# Deployment recipe".count_utf8_bytes(), color: Color.srgb8({ red: 0, green: 110, blue: 75 }) },
			{ start: profile_start, end: profile_end, color: value },
			{ start: storage_start, end: storage_start + storage.count_utf8_bytes(), color: value },
		]
		Plain => []
		InvalidRange => [{ start: profile_end - 1, end: profile_end, color: value }]
	}
	{ text, foregrounds }
}

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose plain or bad-range." }),
		{ name: "source-blocks", version: "unversioned", authors: [], description: "Generate a highlighted deployment recipe.", text_style: Plain },
	),
)
