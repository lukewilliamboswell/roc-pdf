app [main!] {
	pdf: "../../package/main.roc",
	pf: platform "../platform/main.roc",
}

import pdf.Document
import pdf.Pdf

# The public compact builder chains through its nested opaque Builder type.
expect {
	builder : Document.Builder
	builder = Document.builder({ language: "en-AU", title: "Quarterly report" })
		.add_title("Quarterly report")
		.add_heading({ level: 1, text: "Summary" })
		.add_paragraph("Typed contract")
		.add_bullets(["Dense block descriptors", "Single-owned text"])

	builder.stats() == { blocks: 4, text_sources: 5 }
}

# Level 9 must reach the facade's diagnostic in both authoring paths.
heading_error : Document -> Bool
heading_error = |document| match Pdf.to_bytes_with(document, { profile: Standard }) {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature("semantics.heading_level"), details: ["contents[0]"], .. }], .. })) => True
	_ => False
}

expect {
	metadata = { language: "en-AU", title: "Quarterly report" }
	heading = { level: 9, name: "section", text: "Section" }
	compact = Document.builder(metadata).add_destination_heading(heading).finish()
	direct = Pdf.document({ language: metadata.language, title: metadata.title, contents: [Pdf.destination_heading(heading)] })
	heading_error(compact) and heading_error(direct)
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
