app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf

facade_document = Pdf.document({
	contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
	language: "en-AU",
	title: "text-layout public facade output",
})

## This is the public one-import positive boundary. Its emitted bytes are
## checked structurally by scripts/check_facade_output.py.
expect {
	bytes = Pdf.to_bytes(facade_document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Page artifacts have no text-layout facade renderer. The typed error carries no
## bytes, so the failure is atomic rather than a blank-output fallback.
expect {
	document = Pdf.document({
		contents: [Pdf.page_footer("Not implemented")],
		language: "en-AU",
		title: "Atomic negative",
	})

	match Pdf.to_bytes(document) {
		Err(UnsupportedAuthoringContent({ blocks })) => blocks == 1
		_ => False
	}
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	title = if list_at(args, 1) == "0" {
		"text-layout public facade output"
	} else {
		crash "text-layout public facade runtime guard is invalid"
	}
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF generation in pure Roc.")],
		language: "en-AU",
		title,
	})
	bytes = Pdf.to_bytes(document) ?? []

	{ bytes, work: [bytes.len()] }
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "text-layout public facade argument missing"
	Ok(value) => value
}
