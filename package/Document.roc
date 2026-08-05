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

	block_count : Document -> U64
	block_count = |document| match document.authoring {
		Compact(compact) => compact.block_kinds.len()
		Simple(simple) => simple.contents.len()
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

## Prepared documents cannot retain authoring blocks or layout handlers.
expect Document.lifetimes.custom_handlers == ReleaseAfter(LayoutStabilization)
