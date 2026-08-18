import Color
import Conformance
import Font
import Image
import Layout
import Metadata
import Scene
import Semantics
import Text

DocumentBlock :: [
	Bullets(List(Str)),
	Heading({ level : U8, text : Str }),
	PageArtifact({ kind : PageArtifactKind, text : Str }),
	Paragraph(Str),
	Title(Str),
].{}

PageArtifactKind := [Footer, Header, PageNumber, Watermark]

NormalizedBlockKind := [
	Bullet({ item : U64, list : U64 }),
	Heading(U8),
	PageArtifact(PageArtifactKind),
	Paragraph,
	Title,
]

NormalizedBlock := { kind : NormalizedBlockKind, text : Str }

NormalizedAuthoring := {
	blocks : List(NormalizedBlock),
	language : Str,
	metadata_title : Str,
}

DocumentBuilder :: {
	block_aux : List(U64),
	block_tags : List(U8),
	block_texts : List(U64),
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
			block_aux: [],
			block_tags: [],
			block_texts: [],
			language,
			metadata_title: document_title,
			text_sources: [],
		}

	add_title : DocumentBuilder, Str -> DocumentBuilder
	add_title = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, text| {
		text_id = text_sources.len()

		DocumentBuilder.{
			block_aux: block_aux.append(0),
			block_tags: block_tags.append(title_tag),
			block_texts: block_texts.append(text_id),
			language,
			metadata_title,
			text_sources: text_sources.append(text),
		}
	}

	add_heading : DocumentBuilder, U8, Str -> DocumentBuilder
	add_heading = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, level, text| {
		text_id = text_sources.len()

		DocumentBuilder.{
			block_aux: block_aux.append(level.to_u64()),
			block_tags: block_tags.append(heading_tag),
			block_texts: block_texts.append(text_id),
			language,
			metadata_title,
			text_sources: text_sources.append(text),
		}
	}

	add_paragraph : DocumentBuilder, Str -> DocumentBuilder
	add_paragraph = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, text| {
		text_id = text_sources.len()

		DocumentBuilder.{
			block_aux: block_aux.append(0),
			block_tags: block_tags.append(paragraph_tag),
			block_texts: block_texts.append(text_id),
			language,
			metadata_title,
			text_sources: text_sources.append(text),
		}
	}

	## The large-document path appends a batch while all dense buffers stay
	## uniquely owned inside one call; no intermediate builder versions escape.
	add_paragraphs : DocumentBuilder, List(Str) -> DocumentBuilder
	add_paragraphs = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, paragraphs| {
		var $block_aux = block_aux
		var $block_tags = block_tags
		var $block_texts = block_texts
		var $text_sources = text_sources
		var $index = 0
		while $index < paragraphs.len() {
			text_id = $text_sources.len()
			$block_aux = $block_aux.append(0)
			$block_tags = $block_tags.append(paragraph_tag)
			$block_texts = $block_texts.append(text_id)
			$text_sources = $text_sources.append(list_at(paragraphs, $index))
			$index = $index + 1
		}
		DocumentBuilder.{
			block_aux: $block_aux,
			block_tags: $block_tags,
			block_texts: $block_texts,
			language,
			metadata_title,
			text_sources: $text_sources,
		}
	}

	add_bullets : DocumentBuilder, List(Str) -> DocumentBuilder
	add_bullets = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, items| {
		start = text_sources.len()
		length = items.len()

		var $text_sources = text_sources
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

		DocumentBuilder.{
			block_aux: block_aux.append(length),
			block_tags: block_tags.append(bullets_tag),
			block_texts: block_texts.append(start),
			language,
			metadata_title,
			text_sources: $text_sources,
		}
	}

	add_page_header : DocumentBuilder, Str -> DocumentBuilder
	add_page_header = |state, text| append_artifact(state, Header, text)

	add_page_footer : DocumentBuilder, Str -> DocumentBuilder
	add_page_footer = |state, text| append_artifact(state, Footer, text)

	stats : DocumentBuilder -> Stats
	stats = |state| {
		blocks: state.block_tags.len(),
		text_sources: state.text_sources.len(),
	}

	finish : DocumentBuilder -> Document
	finish = |state| Document.{ authoring: Compact(state), created: Omitted, modified: Omitted }
}

DocumentAuthoring := [
	Compact(DocumentBuilder),
	Simple({ contents : List(DocumentBlock), language : Str, metadata_title : Str }),
]

Document :: { authoring : DocumentAuthoring, created : Metadata.TimestampInput, modified : Metadata.TimestampInput }.{
	Block : DocumentBlock
	Builder : DocumentBuilder
	NormalizedBlock : NormalizedBlock
	NormalizedBlockKind : NormalizedBlockKind
	NormalizedAuthoring : NormalizedAuthoring
	PageArtifactKind : PageArtifactKind

	## Reusable resource identity is independent of the scene group that uses
	## it. Placements carry only this scalar edge, never another payload copy.
	Resource : [
		ColorSpace(Color.SpaceId),
		Font(Font.InstanceId),
		IccProfile(Color.ProfileId),
		Image(Image.Id),
	]
	ResourceUse : { group : Scene.GroupId, resource : Resource }

	PreparedLayout : {
		placements : List(Layout.Placement),
		references : Layout.ResolvedReferences,
	}

	ResourceInspectionWork : {
		color : Color.InspectionWork,
		image : Image.InspectionWork,
	}
	PreparationWork : {
		copied_payload_bytes : U64,
		font_planning : Font.PlanWork,
		layout : Layout.Work,
		reference_passes : U64,
		retained_payload_bytes : U64,
		resource_edges : U64,
		resource_inspection : ResourceInspectionWork,
		scene_commands : U64,
		semantic_nodes : U64,
	}

	## The prepared boundary contains only stable data. All layout-affecting
	## references have exact values; custom handlers and speculative caches are
	## absent. The semantics store owns the single Document root and content spine.
	Prepared : {
		blend_space : Color.BlendSpace,
		claims : Conformance.ClaimSet,
		colors : Color.Store,
		fonts : Font.Store,
		images : Image.Store,
		layout : PreparedLayout,
		metadata : Metadata.Logical,
		output_intent : Color.OutputIntent,
		policy : Conformance.ResourcePolicy,
		resource_uses : List(ResourceUse),
		scenes : Scene.Store,
		semantics : Semantics.Store,
		text : Text.Store,
		work : PreparationWork,
	}
	PreparationResult : Try(Prepared, Conformance.DiagnosticBatch)

	Phase : [
		Authoring,
		ConformanceAndLowering,
		Emission,
		FontPlanning,
		LayoutStabilization,
		NormalizedInput,
		PreparedBoundary,
		SealedPlan,
	]
	Lifetime : [ReleaseAfter(Phase), RetainThroughEmission]
	LifetimePolicy : {
		authoring_blocks : Lifetime,
		custom_handlers : Lifetime,
		decoded_image_intermediates : Lifetime,
		layout_caches : Lifetime,
		prepared_scenes : Lifetime,
		resource_inspection_intermediates : Lifetime,
		validated_resource_bytes : Lifetime,
	}

	lifetimes : LifetimePolicy
	lifetimes = {
		authoring_blocks: ReleaseAfter(NormalizedInput),
		custom_handlers: ReleaseAfter(LayoutStabilization),
		decoded_image_intermediates: ReleaseAfter(PreparedBoundary),
		layout_caches: ReleaseAfter(PreparedBoundary),
		prepared_scenes: ReleaseAfter(ConformanceAndLowering),
		resource_inspection_intermediates: ReleaseAfter(PreparedBoundary),
		validated_resource_bytes: RetainThroughEmission,
	}

	from_blocks : { contents : List(DocumentBlock), language : Str, title : Str } -> Document
	from_blocks = |{ contents, language, title: document_title }|
		Document.{
			authoring: Simple({ contents, language, metadata_title: document_title }),
			created: Omitted,
			modified: Omitted,
		}

	## Optional explicit metadata timestamps. The package never reads a clock;
	## an author who wants `xmp:CreateDate` or `xmp:ModifyDate` supplies the
	## exact canonical UTC instant, which is validated before generation.
	with_created : Document, Str -> Document
	with_created = |document, timestamp| Document.{
		authoring: document.authoring,
		created: Explicit(timestamp),
		modified: document.modified,
	}

	with_modified : Document, Str -> Document
	with_modified = |document, timestamp| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: Explicit(timestamp),
	}

	created : Document -> Metadata.TimestampInput
	created = |document| document.created

	modified : Document -> Metadata.TimestampInput
	modified = |document| document.modified

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

	block_count : Document -> U64
	block_count = |document| match document.authoring {
		Compact(compact) => compact.block_tags.len()
		Simple(simple) => simple.contents.len()
	}

	## Both authoring front ends lower once to the same flat text/block store.
	## String payloads remain shared values; block and list identity are scalar facts.
	normalize : Document -> NormalizedAuthoring
	normalize = |document| normalize_authoring(document.authoring)
}

normalize_authoring : DocumentAuthoring -> NormalizedAuthoring
normalize_authoring = |authoring| match authoring {
	Compact(compact) => normalize_compact(compact)
	Simple(simple) => normalize_simple(simple)
}

normalize_compact : DocumentBuilder -> NormalizedAuthoring
normalize_compact = |compact| {
	var $blocks = []
	var $block_index = 0
	var $list_index = 0
	while $block_index < compact.block_tags.len() {
		tag = list_at(compact.block_tags, $block_index)
		text = list_at(compact.block_texts, $block_index)
		aux = list_at(compact.block_aux, $block_index)
		if tag == bullets_tag {
			var $item = 0
			while $item < aux {
				text_index = text + $item
				$blocks = $blocks.append({ kind: Bullet({ item: $item, list: $list_index }), text: list_at(compact.text_sources, text_index) })
				$item = $item + 1
			}
			$list_index = $list_index + 1
		} else if tag == heading_tag {
			$blocks = $blocks.append({ kind: Heading(aux.to_u8_wrap()), text: list_at(compact.text_sources, text) })
		} else if tag == artifact_tag {
			$blocks = $blocks.append({ kind: PageArtifact(decode_artifact(aux)), text: list_at(compact.text_sources, text) })
		} else if tag == paragraph_tag {
			$blocks = $blocks.append({ kind: Paragraph, text: list_at(compact.text_sources, text) })
		} else if tag == title_tag {
			$blocks = $blocks.append({ kind: Title, text: list_at(compact.text_sources, text) })
		} else {
			crash "compact authoring block tag escaped"
		}
		$block_index = $block_index + 1
	}
	{
		blocks: $blocks,
		language: compact.language,
		metadata_title: compact.metadata_title,
	}
}

normalize_simple : { contents : List(DocumentBlock), language : Str, metadata_title : Str } -> NormalizedAuthoring
normalize_simple = |simple| {
	var $blocks = []
	var $block_index = 0
	var $list_index = 0
	while $block_index < simple.contents.len() {
		match list_at(simple.contents, $block_index) {
			Bullets(items) => {
				var $item = 0
				while $item < items.len() {
					$blocks = $blocks.append({ kind: Bullet({ item: $item, list: $list_index }), text: list_at(items, $item) })
					$item = $item + 1
				}
				$list_index = $list_index + 1
			}
			Heading({ level, text }) => {
				$blocks = $blocks.append({ kind: Heading(level), text })
			}
			PageArtifact({ kind, text }) => {
				$blocks = $blocks.append({ kind: PageArtifact(kind), text })
			}
			Paragraph(text) => {
				$blocks = $blocks.append({ kind: Paragraph, text })
			}
			Title(text) => {
				$blocks = $blocks.append({ kind: Title, text })
			}
		}
		$block_index = $block_index + 1
	}
	{
		blocks: $blocks,
		language: simple.language,
		metadata_title: simple.metadata_title,
	}
}

append_artifact : DocumentBuilder, PageArtifactKind, Str -> DocumentBuilder
append_artifact = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, kind, text| {
	text_id = text_sources.len()

	DocumentBuilder.{
		block_aux: block_aux.append(encode_artifact(kind)),
		block_tags: block_tags.append(artifact_tag),
		block_texts: block_texts.append(text_id),
		language,
		metadata_title,
		text_sources: text_sources.append(text),
	}
}

encode_artifact : PageArtifactKind -> U64
encode_artifact = |kind| match kind {
	Footer => 0
	Header => 1
	PageNumber => 2
	Watermark => 3
}

decode_artifact : U64 -> PageArtifactKind
decode_artifact = |value| match value {
	0 => Footer
	1 => Header
	2 => PageNumber
	3 => Watermark
	_ => {
		crash "compact page artifact kind escaped"
	}
}

bullets_tag : U8
bullets_tag = 0

heading_tag : U8
heading_tag = 1

artifact_tag : U8
artifact_tag = 2

paragraph_tag : U8
paragraph_tag = 3

title_tag : U8
title_tag = 4

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "normalized authoring index escaped"
	}
	Ok(value) => value
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

## Simple and compact authoring normalize to identical scalar/list identities.
expect {
	simple = Document.from_blocks({
		contents: [Document.title("Report"), Document.heading(2, "Details"), Document.bullets(["One", "Two"]), Document.paragraph("Done")],
		language: "en-AU",
		title: "Report",
	})
	compact = Document.builder({ language: "en-AU", title: "Report" })
		.add_title("Report")
		.add_heading(2, "Details")
		.add_bullets(["One", "Two"])
		.add_paragraph("Done")
		.finish()
	simple_store = Document.normalize(simple)
	compact_store = Document.normalize(compact)
	first = list_at(simple_store.blocks, 0)
	second = list_at(simple_store.blocks, 1)
	third = list_at(simple_store.blocks, 2)
	fourth = list_at(simple_store.blocks, 3)
	fifth = list_at(simple_store.blocks, 4)
	first_kind = match first.kind {
		Title => True
		_ => False
	}
	second_kind = match second.kind {
		Heading(2) => True
		_ => False
	}
	third_kind = match third.kind {
		Bullet({ item: 0, list: 0 }) => True
		_ => False
	}
	fourth_kind = match fourth.kind {
		Bullet({ item: 1, list: 0 }) => True
		_ => False
	}
	fifth_kind = match fifth.kind {
		Paragraph => True
		_ => False
	}

	simple_store.blocks.len() == compact_store.blocks.len() and
		simple_store.language == compact_store.language and
			simple_store.metadata_title == compact_store.metadata_title and
				first_kind and first.text == "Report" and
					second_kind and second.text == "Details" and
						third_kind and third.text == "One" and
							fourth_kind and fourth.text == "Two" and
								fifth_kind and fifth.text == "Done"
}

## Finishing a builder preserves required metadata without rebuilding a block list.
expect {
	document = Document.builder({ language: "en-AU", title: "Report" }).finish()

	document.metadata_title() == "Report" and document.language() == "en-AU"
}

## Prepared documents cannot retain authoring blocks or layout handlers.
expect Document.lifetimes.custom_handlers == ReleaseAfter(LayoutStabilization)

## Metadata timestamps are explicit author inputs and default to omission.
expect {
	document = Document.from_blocks({ contents: [], language: "en-AU", title: "Report" })
	stamped = document.with_created("2026-01-02T03:04:05Z").with_modified("2026-01-02T03:04:06Z")

	document.created() == Omitted and document.modified() == Omitted and stamped.created() == Explicit("2026-01-02T03:04:05Z") and stamped.modified() == Explicit("2026-01-02T03:04:06Z")
}
