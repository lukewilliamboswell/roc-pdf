app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
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

## Navigation authoring is typed: links, named destinations, an outline, and
## page labels flow through the same one-import facade.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Field guide"),
			Pdf.destination_heading("habitat", 1, "Habitat"),
			Pdf.paragraph("Wetlands and coastal heath."),
			Pdf.link("Atlas of Living Australia", "https://www.ala.org.au/"),
			Pdf.internal_link("See the habitat notes", "habitat"),
		],
		language: "en-AU",
		title: "Field guide",
	})
	navigated = document
		.with_outline([{ depth: 0, destination: "habitat", open: True, title: "Habitat" }])
		.with_page_labels([{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes(navigated)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 4717
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
