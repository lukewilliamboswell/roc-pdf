app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Pdf

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_args| {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(document) ?? []

	{ bytes, work: [1, bytes.len()] }
}
