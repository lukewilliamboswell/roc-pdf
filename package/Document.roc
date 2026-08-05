import Semantics

DocumentBlock :: [
	Bullets(List(Str)),
	Heading({ level : U8, text : Str }),
	PageArtifact({ kind : PageArtifactKind, text : Str }),
	Paragraph(Str),
	Title(Str),
].{}

PageArtifactKind := [Footer, Header, PageNumber, Watermark]

CompactBlockKind := [
	Bullets(Semantics.Range),
	Heading({ level : U8, text : U64 }),
	PageArtifact({ kind : PageArtifactKind, text : U64 }),
	Paragraph(U64),
	Title(U64),
]

DocumentBuilder :: {
	block_kinds : List(CompactBlockKind),
	language : Str,
	metadata_title : Str,
	text_sources : List(Str),
}.{
	Stats : {
		blocks : U64,
		text_sources : U64,
	}

	init : { language : Str, title : Str } -> DocumentBuilder
	init = |{ language, title: document_title }|
		DocumentBuilder.{
			block_kinds: [],
			language,
			metadata_title: document_title,
			text_sources: [],
		}

	add_title : DocumentBuilder, Str -> DocumentBuilder
	add_title = |state, text| {
		text_id = state.text_sources.len()

		{
			..state,
			block_kinds: state.block_kinds.append(CompactBlockKind.Title(text_id)),
			text_sources: state.text_sources.append(text),
		}
	}

	add_heading : DocumentBuilder, U8, Str -> DocumentBuilder
	add_heading = |state, level, text| {
		text_id = state.text_sources.len()

		{
			..state,
			block_kinds: state.block_kinds.append(CompactBlockKind.Heading({ level, text: text_id })),
			text_sources: state.text_sources.append(text),
		}
	}

	add_paragraph : DocumentBuilder, Str -> DocumentBuilder
	add_paragraph = |state, text| {
		text_id = state.text_sources.len()

		{
			..state,
			block_kinds: state.block_kinds.append(CompactBlockKind.Paragraph(text_id)),
			text_sources: state.text_sources.append(text),
		}
	}

	add_bullets : DocumentBuilder, List(Str) -> DocumentBuilder
	add_bullets = |state, items| {
		start = state.text_sources.len()
		length = items.len()

		var $text_sources = state.text_sources
		var $index = 0
		while $index < length {
			match items.get($index) {
				Ok(item) => {
					$text_sources = $text_sources.append(item)
				}
				Err(OutOfBounds) => {
					crash "internal builder index invariant failed"
				}
			}
			$index = $index + 1
		}

		{
			..state,
			block_kinds: state.block_kinds.append(CompactBlockKind.Bullets(Semantics.Range.from_start_and_length(start, length))),
			text_sources: $text_sources,
		}
	}

	add_page_header : DocumentBuilder, Str -> DocumentBuilder
	add_page_header = |state, text| append_artifact(state, Header, text)

	add_page_footer : DocumentBuilder, Str -> DocumentBuilder
	add_page_footer = |state, text| append_artifact(state, Footer, text)

	stats : DocumentBuilder -> Stats
	stats = |state| {
		blocks: state.block_kinds.len(),
		text_sources: state.text_sources.len(),
	}

	finish : DocumentBuilder -> Document
	finish = |state| Document.{ authoring: Compact(state) }
}

DocumentAuthoring := [
	Compact(DocumentBuilder),
	Simple({ contents : List(DocumentBlock), language : Str, metadata_title : Str }),
]

Document :: { authoring : DocumentAuthoring }.{
	Block : DocumentBlock
	Builder : DocumentBuilder
	PageArtifactKind : PageArtifactKind

	from_blocks : { contents : List(DocumentBlock), language : Str, title : Str } -> Document
	from_blocks = |{ contents, language, title: document_title }|
		Document.{
			authoring: Simple({ contents, language, metadata_title: document_title }),
		}

	title : Str -> DocumentBlock
	title = |text| DocumentBlock.Title(text)

	heading : U8, Str -> DocumentBlock
	heading = |level, text| DocumentBlock.Heading({ level, text })

	paragraph : Str -> DocumentBlock
	paragraph = |text| DocumentBlock.Paragraph(text)

	bullets : List(Str) -> DocumentBlock
	bullets = |items| DocumentBlock.Bullets(items)

	page_header : Str -> DocumentBlock
	page_header = |text| DocumentBlock.PageArtifact({ kind: Header, text })

	page_footer : Str -> DocumentBlock
	page_footer = |text| DocumentBlock.PageArtifact({ kind: Footer, text })

	builder : { language : Str, title : Str } -> DocumentBuilder
	builder = |metadata| DocumentBuilder.init(metadata)

	metadata_title : Document -> Str
	metadata_title = |document| match document.authoring {
		Compact(compact) => compact.metadata_title
		Simple(simple) => simple.metadata_title
	}

	language : Document -> Str
	language = |document| match document.authoring {
		Compact(compact) => compact.language
		Simple(simple) => simple.language
	}
}

append_artifact : DocumentBuilder, PageArtifactKind, Str -> DocumentBuilder
append_artifact = |builder, kind, text| {
	text_id = builder.text_sources.len()

	{
		..builder,
		block_kinds: builder.block_kinds.append(CompactBlockKind.PageArtifact({ kind, text: text_id })),
		text_sources: builder.text_sources.append(text),
	}
}

## The compact builder stores block descriptors and text payloads in separate flat buffers.
expect {
	builder = Document.builder({ language: "en-AU", title: "Report" })
		.add_title("Report")
		.add_heading(1, "Summary")
		.add_paragraph("Body")
		.add_bullets(["One", "Two"])
		.add_page_footer("Page footer")

	builder.stats() == { blocks: 5, text_sources: 6 }
}

## Finishing a builder preserves required metadata without rebuilding a block list.
expect {
	document = Document.builder({ language: "en-AU", title: "Report" }).finish()

	document.metadata_title() == "Report" and document.language() == "en-AU"
}
