import pdf.Pdf

## The structural_blank family's typed case and its dispatch, run by a fixture
## group app: one blank document through the public facade.
##
## Like the original fixture, the case carries no runtime input. Its explicit
## module value is evaluated at compile time and records zero allocations,
## independently of whether the dev backend inlines closed function calls.
Cases :: [].{
	Case : [
		Blank({}),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Blank({}) => blank
		}
	}
}

blank : { bytes : List(U8), work : List(U64) }
blank = {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(document) ?? []

	{ bytes, work: [1, bytes.len()] }
}
