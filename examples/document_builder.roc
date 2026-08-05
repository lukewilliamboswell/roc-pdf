app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Document

## The public compact builder chains through its nested opaque Builder type.
expect {
	builder : Document.Builder
	builder = Document.builder({ language: "en-AU", title: "Quarterly report" })
		.add_title("Quarterly report")
		.add_heading(1, "Summary")
		.add_paragraph("Typed contract")
		.add_bullets(["Dense block descriptors", "Single-owned text"])

	builder.stats() == { blocks: 4, text_sources: 5 }
}

main! : List(Str) => List(U8)
main! = |_| []
