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
import pdf.Font
import pdf.Pdf
import pdf.RocFont
import "fonts/ReceivingHan-Regular.ttf" as han_bytes : List(U8)

main! = |args| {
	with_han = match Cli.parse_or_display_message(cli, args, OsStr.to_raw) {
		Err(Help(message)) | Err(Version(message)) => return Stdout.line!(message).map_err(|error| OutputFailed(error))
		Err(InvalidUsage(message)) => {
			Stderr.line!(message).map_err(|error| OutputFailed(error))?
			return Err(Exit(2))
		}
		Ok(Err(NoValue)) => True
		Ok(Ok("latin-only")) => False
		Ok(Ok(_)) => {
			Stderr.line!("Usage: roc run main.roc [latin-only]").map_err(|err| OutputFailed(err))?
			return Err(Exit(2))
		}
	}
	limits = Font.ValidationLimits.default
	packaged = RocFont.register(Font.Registry.empty, limits).map_err(|err| FontRejected(err))?
	latin = packaged.body
	ordered = if with_han {
		han = packaged.registry.register({ bytes: han_bytes, registration: { provision: BuiltIn, scripts: ["Hani"] }, limits }).map_err(|err| FontRejected(err))?
		han.registry.with_policy([latin, han.face]).map_err(|err| InvalidPolicy(err))?
	} else packaged.registry.with_policy([latin]).map_err(|err| InvalidPolicy(err))?

	options : Pdf.Options
	options = { page_size: Custom({ width: 432, height: 288 }), fonts: Registered(ordered.registry), theme: { font_selection: Policy(ordered.policy) } }
	bytes = match Pdf.to_bytes_with(document, options) {
		Ok(value) => value
		Err(error) => {
			Stderr.line!(Pdf.Error.to_inspect(error)).map_err(|err| OutputFailed(err))?
			return Err(Exit(1))
		}
	}
	output : Path
	output = "ordered-han.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote ordered-han.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

handover = "仓库交接"

header = Pdf.region({ height: 18, start: [Pdf.furniture_text([Pdf.text("Receiving${handover}")])] })

document = Pdf.document({
	title: "Receiving handover",
	language: "en-AU",
	page_templates: Templates({ first: Pdf.first_page_template({ header: header }), continuation: Pdf.page_template({ header: header }) }),
	contents: [
		Pdf.title("Receiving handover"),
		Pdf.rich_paragraph([Pdf.text("Refer to the handover note "), Pdf.in_language("zh-Hans", [Pdf.text(handover)]), Pdf.text(" before unloading.")]),
		Pdf.table({
			caption: Pdf.caption("Pallets awaiting receiving"),
			columns: [{ width: Share(1), align: Start }, { width: Fixed(72), align: End }],
			header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Bay")]), Pdf.header_cell(Column, [Pdf.text("Pallets")])])],
			body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.text("Bay 4")]), Pdf.cell([Pdf.text("28")])])],
		}),
		Pdf.page_break,
		Pdf.paragraph("Confirm the handover after inspecting the remaining pallets."),
	],
})

cli = Cli.assert_valid(
	Cli.finish(
		Param.maybe_str({ name: "mode", help: "Choose latin-only to omit Han text." }),
		{ name: "ordered-han", version: "unversioned", authors: [], description: "Generate a receiving note with ordered font coverage.", text_style: Plain },
	),
)
