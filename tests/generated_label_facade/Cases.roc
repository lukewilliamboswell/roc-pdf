import pdf.Pdf

## The generated_label_facade family's typed case and its dispatch, run by a
## fixture group app.
##
## `context` is the runtime zero that selects the authored title, so the
## compiler cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Labels({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Labels({ context }) => labels(context)
		}
	}
}

make_document = |title| Pdf.document({
	contents: [Pdf.bullets(["First", "Second"])],
	language: "en-AU",
	title,
})

# The facade owns the logical bullet source and carries an explicit
# GeneratedText presentation fact into the private text pipeline.
expect {
	bytes = Pdf.to_bytes(make_document("text-layout generated labels"))?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

labels : U64 -> { bytes : List(U8), work : List(U64) }
labels = |context| {
	title = if context == 0 {
		"text-layout generated labels"
	} else {
		crash "text-layout generated-label argument is invalid"
	}
	document = make_document(title)
	bytes = Pdf.to_bytes(document) ?? []

	{ bytes, work: [bytes.len()] }
}
