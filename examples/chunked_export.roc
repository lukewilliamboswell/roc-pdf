app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Layout
import pdf.Pdf
import pdf.Theme

collect = |encoder, bytes| match Pdf.next_chunk(encoder) {
	Done => bytes
	Emit(chunk, next) => collect(next, bytes.concat(chunk))
}

main! = |_args| {
	plum = Color.srgb8({ red: 111, green: 45, blue: 105 })
	base_body = Theme.body_style(Theme.default)
	theme = Theme.default
		.with_title_color(plum)
		.with_heading_color(plum)
		.with_body_style({ ..base_body, size: Layout.Unit.points(12), leading: Layout.Unit.points(18) })
		.with_page_margin({ top: Layout.Unit.points(54), right: Layout.Unit.points(90), bottom: Layout.Unit.points(54), left: Layout.Unit.points(90) })
		.with_bullet_indent(Layout.Unit.points(28))
	document = Pdf.document({
		title: "Data export",
		language: "en",
		contents: [
			Pdf.title("Data export"),
			Pdf.paragraph("Chunked delivery uses the same sealed plan and produces byte-identical output."),
			Pdf.bullets(["No partial document on validation failure", "Explicit chunk-retention policy", "Deterministic ordering"]),
		],
	})
	prepared = Pdf.prepare(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	encoder = Pdf.to_chunks_prepared(prepared, ShareUnchangedResources).map_err(|err| EmitFailed(err))?
	output : Path
	output = "chunked-export.pdf"
	output.write_bytes!(collect(encoder, [])).map_err(|err| WriteFailed(err))?
	Ok({})
}
