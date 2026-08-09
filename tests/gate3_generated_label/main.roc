app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/main.roc",
}

import pdf.Pdf

make_document = |title| Pdf.document({
	contents: [Pdf.bullets(["First", "Second"])],
	language: "en-AU",
	title,
})

## The facade owns the logical bullet source and carries an explicit
## GeneratedText presentation fact into the private text pipeline.
expect {
	bytes = Pdf.to_bytes(make_document("Gate 3 generated labels"))?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	title = if list_at(args, 1) == "0" {
		"Gate 3 generated labels"
	} else {
		crash "Gate 3 generated-label argument is invalid"
	}
	document = make_document(title)
	bytes = Pdf.to_bytes(document) ?? []

	{ bytes, work: [bytes.len()] }
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "Gate 3 generated-label argument missing"
	Ok(value) => value
}
