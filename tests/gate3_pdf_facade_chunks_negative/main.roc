app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf

## Unsupported authored content must reject before any chunk exists; the
## blank structural carrier is the transactional test result, not a fallback.
main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	title = if args.len() == 1 {
		"Chunk rejection"
	} else {
		crash "Gate 3 chunked facade negative runtime guard is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.page_footer("Not implemented")],
		language: "en-AU",
		title,
	})
	rejected = match Pdf.to_chunks(document) {
		Err(UnsupportedAuthoringContent({ blocks })) => if blocks == 1 1 else 0
		_ => 0
	}
	if rejected != 1 {
		crash "Gate 3 chunked facade negative was accepted"
	}
	blank = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(blank) ?? []

	{ bytes, work: [rejected, bytes.len()] }
}
