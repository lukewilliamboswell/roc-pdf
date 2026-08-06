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

## The one-import facade rejects meaningful content until the visual gates land.
expect {
	match make_report("Typed contract only") {
		Err(UnsupportedAuthoringContent({ blocks })) => blocks == 4
		_ => False
	}
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
