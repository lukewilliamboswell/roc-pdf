app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf

## Unavailable authored content must reject before any chunk exists; the
## blank structural carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	title = if args.len() == 1 {
		"Chunk rejection"
	} else {
		crash "text-layout chunked facade negative runtime guard is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.footnote("Not implemented")],
		language: "en-AU",
		title,
	})
	rejected = match Pdf.to_chunks(document) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, .. }], .. })) => 1
		_ => 0
	}
	if rejected != 1 {
		crash "text-layout chunked facade negative was accepted"
	}
	blank = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(blank) ?? []

	{ bytes, work: [rejected, bytes.len()] }
}
