app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Pdf

make_report : Str -> Try(List(U8), Pdf.Error)
make_report = |summary| {
	document = Pdf.document({
		contents: [
			Pdf.title("Quarterly report"),
			Pdf.heading(1, "Summary"),
			Pdf.paragraph(summary),
			Pdf.bullets(["Searchable text", "Tagged reading order"]),
		],
		language: "en-AU",
		title: "Quarterly report",
	})

	Pdf.to_bytes(document)
}

## The one-import Standard facade emits authored content without exposing
## resources, glyphs, scenes, or PDF objects.
expect {
	bytes = make_report("Typed facade output")?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Nested profile and option modules use current package shorthand syntax.
expect {
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })

	match Pdf.to_bytes_with(document, options) {
		Err(CapabilityUnavailable(PdfA4Generation)) => True
		_ => False
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
