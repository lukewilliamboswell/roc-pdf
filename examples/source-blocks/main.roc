app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0-rc2/Gj3zVDr3qrQa6aTh7Z1zgUfe9NeBE6R76T5ho3xrc8af.tar.zst",
}

import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Font
import pdf.Pdf
import pdf.RocFont
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## One locally styled source block continues over pages. Body paragraphs
## keep their own face, size, leading, and spacing throughout the document.
main! = |_args| {
	body = RocFont.register(Font.Registry.empty, Font.ValidationLimits.default).map_err(|error| FontFailed(error))?
	theme = RocFont.theme(body, {})
	mono = body.registry.register({ bytes: mono_bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }).map_err(|error| FontFailed(error))?
	options : Pdf.Options
	options = { fonts: Registered(mono.registry), theme }
	text = Str.join_with(["# Deployment recipe\nservice = billing\n\n    data = /var/lib/harbour/production/billing/exports/archive\n", Str.repeat("    workers = 4\n", 90), "\n# End of recipe\n"], "")
	document = Pdf.document({
		title: "Deployment recipe",
		language: "en",
		contents: [
			Pdf.title("Deployment recipe"),
			Pdf.paragraph("The source block has its own monospace face and presentation. Its indentation and blank lines survive page continuation."),
			Pdf.source_block({ text, face: Face(mono.face), size: 9, leading: 12, padding: 8, color: Color.srgb8({ red: 25, green: 60, blue: 50 }), background: Background(Color.srgb8({ red: 242, green: 246, blue: 244 })) }),
			Pdf.paragraph("The body text resumes with the original typography after the source block."),
		],
	})
	bytes = Pdf.to_bytes_with(document, options).map_err(|error| PdfFailed(error))?
	output : Path
	output = "source-blocks.pdf"
	output.write_bytes!(bytes).map_err(|error| WriteFailed(error))?
	Stdout.line!("Wrote source-blocks.pdf").map_err(|error| OutputFailed(error))?
	Ok({})
}
