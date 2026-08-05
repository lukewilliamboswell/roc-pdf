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

## The one-import facade compiles while Gate 0 reports unavailable generation transactionally.
expect {
	match make_report("Typed contract only") {
		Err(CapabilityUnavailable(Pdf20Generation)) => True
		_ => False
	}
}

## Nested profile and option modules use current package shorthand syntax.
expect {
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })

	match Pdf.to_bytes_with(document, options) {
		Err(CapabilityUnavailable(Pdf20Generation)) => True
		_ => False
	}
}

main! : List(Str) => List(U8)
main! = |_| []
