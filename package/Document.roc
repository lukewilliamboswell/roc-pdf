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
	DestinationHeading({ level : U8, name : Str, text : Str }),
	DestinationParagraph({ name : Str, text : Str }),
	Heading({ level : U8, text : Str }),
	InternalLink({ destination : Str, text : Str }),
	Link({ text : Str, uri : Str }),
	PageArtifact({ kind : PageArtifactKind, text : Str }),
	Paragraph(Str),
	Title(Str),
].{}

PageArtifactKind := [Footer, Header, PageNumber, Watermark]

NormalizedBlockKind := [
	Bullet({ item : U64, list : U64 }),
	DestinationHeading({ level : U8, name : Str }),
	DestinationParagraph({ name : Str }),
	Heading(U8),
	InternalLink({ destination : Str }),
	Link({ uri : Str }),
	PageArtifact(PageArtifactKind),
	Paragraph,
	Title,
]

NormalizedBlock := { kind : NormalizedBlockKind, text : Str }

NormalizedAuthoring := {
	blocks : List(NormalizedBlock),
	language : Str,
	metadata_title : Str,
	outline : List(OutlineEntry),
	page_labels : List(PageLabelRange),
}

## One authored outline entry in dense preorder: the depth below the outline
## root, an explicit open state, and the authored destination name the entry
## navigates to. Outline entries never balance or reorder; the authored
## preorder is the emitted sibling order.
OutlineEntry : { depth : U64, destination : Str, open : Bool, title : Str }

## The closed page-label numbering vocabulary: decimal Arabic, upper and
## lower Roman, upper and lower letters, or a prefix-only range with no
## numeric portion.
PageLabelStyle : [DecimalArabic, LettersLower, LettersUpper, NoNumber, RomanLower, RomanUpper]

## One authored page-label range starting at a physical page index. The
## first range must start at page zero and range starts ascend strictly.
PageLabelRange : { prefix : Str, start_number : U64, start_page : U64, style : PageLabelStyle }

## Stable author-facing navigation rejections: destinations, link
## annotations, outlines, and page labels. Each variant is one distinct
## author-facing failure class with compact scalar locations; validation is
## transactional and no partial navigation data survives a rejection.
## Remote-file destinations, arbitrary actions, rollover/down appearances,
## and non-link annotation types have no representation and therefore no
## runtime rejection here.
NavigationError : [
	AnnotationCountMismatch({ navigation : U64, semantics : U64 }),
	AnnotationLimitExceeded({ attempted : U64, limit : U64 }),
	AnnotationPageOutOfRange({ annotation : U64, attempted : U64, pages : U64 }),
	AppearanceFormOutOfRange({ annotation : U64, attempted : U64, forms : U64 }),
	AppearanceGeometryMismatch({ annotation : U64, form : U64 }),
	AppearanceTextUnsupported({ form : U64 }),
	DescriptionEmpty({ annotation : U64 }),
	DescriptionTooLong({ annotation : U64, attempted : U64, limit : U64 }),
	DestinationAnchorOutOfRange({ attempted : U64, destination : U64, occurrences : U64 }),
	DestinationLimitExceeded({ attempted : U64, limit : U64 }),
	DestinationNameEmpty({ destination : U64 }),
	DestinationNameInvalidByte({ destination : U64, offset : U64 }),
	DestinationNameTooLong({ attempted : U64, destination : U64, limit : U64 }),
	DestinationTargetMismatch({ anchor_owner : U64, destination : U64, target : U64 }),
	DestinationTargetOutOfRange({ attempted : U64, destination : U64, nodes : U64 }),
	DuplicateDestinationName({ first : U64, second : U64 }),
	DuplicateKeyboardOrder({ first : U64, second : U64 }),
	InvalidAnchorGeometry({ destination : U64 }),
	InvalidAnnotationRect({ annotation : U64 }),
	InvalidQuad({ annotation : U64, quad : U64 }),
	KeyboardOrderOutOfRange({ annotation : U64, attempted : U64, page_annotations : U64 }),
	LabelLimitExceeded({ attempted : U64, limit : U64 }),
	LabelNumberWithoutStyle({ range : U64 }),
	LabelPrefixTooLong({ attempted : U64, limit : U64, range : U64 }),
	LabelRangeNotAscending({ range : U64 }),
	LabelStartNumberZero({ range : U64 }),
	LabelStartPageNotZero({ start : U64 }),
	LabelStartPageOutOfRange({ attempted : U64, pages : U64, range : U64 }),
	OutlineDepthJump({ actual : U64, entry : U64, previous : U64 }),
	OutlineDepthLimitExceeded({ attempted : U64, entry : U64, limit : U64 }),
	OutlineDestinationUnknown({ entry : U64 }),
	OutlineEntryLimitExceeded({ attempted : U64, limit : U64 }),
	OutlineFirstDepthNonzero({ depth : U64 }),
	OutlineTitleEmpty({ entry : U64 }),
	OutlineTitleTooLong({ attempted : U64, entry : U64, limit : U64 }),
	QuadLimitExceeded({ attempted : U64, limit : U64 }),
	QuadOutsideRect({ annotation : U64, quad : U64 }),
	QuadsEmpty({ annotation : U64 }),
	UnknownDestinationName({ annotation : U64 }),
	UnresolvedDestinationAnchor({ destination : U64 }),
	UriEmpty({ annotation : U64 }),
	UriInvalidByte({ annotation : U64, offset : U64 }),
	UriInvalidPercentEncoding({ annotation : U64, offset : U64 }),
	UriMissingScheme({ annotation : U64 }),
	UriTooLong({ annotation : U64, attempted : U64, limit : U64 }),
]

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

	## A URI link block: the whole text is the link. The secondary string is
	## interned beside the text; the aux slot records its index.
	add_link : DocumentBuilder, Str, Str -> DocumentBuilder
	add_link = |state, text, uri| append_with_secondary(state, link_tag, text, uri, 1)

	add_internal_link : DocumentBuilder, Str, Str -> DocumentBuilder
	add_internal_link = |state, text, destination| append_with_secondary(state, internal_link_tag, text, destination, 1)

	add_destination_heading : DocumentBuilder, Str, U8, Str -> DocumentBuilder
	add_destination_heading = |state, name, level, text| append_with_secondary(state, destination_heading_tag, text, name, 8 * 1 + level.to_u64())

	add_destination_paragraph : DocumentBuilder, Str, Str -> DocumentBuilder
	add_destination_paragraph = |state, name, text| append_with_secondary(state, destination_paragraph_tag, text, name, 1)

	stats : DocumentBuilder -> Stats
	stats = |state| {
		blocks: state.block_tags.len(),
		text_sources: state.text_sources.len(),
	}

	finish : DocumentBuilder -> Document
	finish = |state| Document.{ authoring: Compact(state), created: Omitted, modified: Omitted, outline: [], page_labels: [] }
}

DocumentAuthoring := [
	Compact(DocumentBuilder),
	Simple({ contents : List(DocumentBlock), language : Str, metadata_title : Str }),
]

Document :: { authoring : DocumentAuthoring, created : Metadata.TimestampInput, modified : Metadata.TimestampInput, outline : List(OutlineEntry), page_labels : List(PageLabelRange) }.{
	Block : DocumentBlock
	Builder : DocumentBuilder
	NavigationError : NavigationError
	NormalizedBlock : NormalizedBlock
	NormalizedBlockKind : NormalizedBlockKind
	NormalizedAuthoring : NormalizedAuthoring
	OutlineEntry : OutlineEntry
	PageArtifactKind : PageArtifactKind
	PageLabelRange : PageLabelRange
	PageLabelStyle : PageLabelStyle

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
			outline: [],
			page_labels: [],
		}

	## Optional explicit metadata timestamps. The package never reads a clock;
	## an author who wants `xmp:CreateDate` or `xmp:ModifyDate` supplies the
	## exact canonical UTC instant, which is validated before generation.
	with_created : Document, Str -> Document
	with_created = |document, timestamp| Document.{
		authoring: document.authoring,
		created: Explicit(timestamp),
		modified: document.modified,
		outline: document.outline,
		page_labels: document.page_labels,
	}

	with_modified : Document, Str -> Document
	with_modified = |document, timestamp| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: Explicit(timestamp),
		outline: document.outline,
		page_labels: document.page_labels,
	}

	## The authored document outline in dense preorder. Entries reference
	## authored destination names; the authored order and open states are
	## preserved exactly through lowering.
	with_outline : Document, List(OutlineEntry) -> Document
	with_outline = |document, entries| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: document.modified,
		outline: entries,
		page_labels: document.page_labels,
	}

	## Authored page-label ranges keyed by physical page index. Ranges are
	## validated against the final page count after pagination.
	with_page_labels : Document, List(PageLabelRange) -> Document
	with_page_labels = |document, ranges| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: document.modified,
		outline: document.outline,
		page_labels: ranges,
	}

	created : Document -> Metadata.TimestampInput
	created = |document| document.created

	modified : Document -> Metadata.TimestampInput
	modified = |document| document.modified

	outline : Document -> List(OutlineEntry)
	outline = |document| document.outline

	page_labels : Document -> List(PageLabelRange)
	page_labels = |document| document.page_labels

	title : Str -> DocumentBlock
	title = |text| DocumentBlock.Title(text)

	heading : U8, Str -> DocumentBlock
	heading = |level, text| DocumentBlock.Heading({ level, text })

	paragraph : Str -> DocumentBlock
	paragraph = |text| DocumentBlock.Paragraph(text)

	bullets : List(Str) -> DocumentBlock
	bullets = |items| DocumentBlock.Bullets(items)

	## A URI link block: the whole block text is the link text and the URI is
	## recorded for the reader; nothing dereferences it.
	link : Str, Str -> DocumentBlock
	link = |text, uri| DocumentBlock.Link({ text, uri })

	## An internal link block referencing an authored destination name.
	internal_link : Str, Str -> DocumentBlock
	internal_link = |text, destination| DocumentBlock.InternalLink({ destination, text })

	## A heading that also declares a named destination: the heading's
	## semantic node is the structure target and its content is the layout
	## anchor.
	destination_heading : Str, U8, Str -> DocumentBlock
	destination_heading = |name, level, text| DocumentBlock.DestinationHeading({ level, name, text })

	destination_paragraph : Str, Str -> DocumentBlock
	destination_paragraph = |name, text| DocumentBlock.DestinationParagraph({ name, text })

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
	normalize = |document| {
		normalized = normalize_authoring(document.authoring)
		{ ..normalized, outline: document.outline, page_labels: document.page_labels }
	}
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
		} else if tag == link_tag {
			$blocks = $blocks.append({ kind: Link({ uri: list_at(compact.text_sources, aux) }), text: list_at(compact.text_sources, text) })
		} else if tag == internal_link_tag {
			$blocks = $blocks.append({ kind: InternalLink({ destination: list_at(compact.text_sources, aux) }), text: list_at(compact.text_sources, text) })
		} else if tag == destination_heading_tag {
			$blocks = $blocks.append({ kind: DestinationHeading({ level: (aux % 8).to_u8_wrap(), name: list_at(compact.text_sources, aux // 8) }), text: list_at(compact.text_sources, text) })
		} else if tag == destination_paragraph_tag {
			$blocks = $blocks.append({ kind: DestinationParagraph({ name: list_at(compact.text_sources, aux) }), text: list_at(compact.text_sources, text) })
		} else {
			crash "compact authoring block tag escaped"
		}
		$block_index = $block_index + 1
	}
	{
		blocks: $blocks,
		language: compact.language,
		metadata_title: compact.metadata_title,
		outline: [],
		page_labels: [],
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
			DestinationHeading({ level, name, text }) => {
				$blocks = $blocks.append({ kind: DestinationHeading({ level, name }), text })
			}
			DestinationParagraph({ name, text }) => {
				$blocks = $blocks.append({ kind: DestinationParagraph({ name: name }), text })
			}
			Heading({ level, text }) => {
				$blocks = $blocks.append({ kind: Heading(level), text })
			}
			InternalLink({ destination, text }) => {
				$blocks = $blocks.append({ kind: InternalLink({ destination: destination }), text })
			}
			Link({ text, uri }) => {
				$blocks = $blocks.append({ kind: Link({ uri: uri }), text })
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
		outline: [],
		page_labels: [],
	}
}

## Blocks with a secondary string (a URI or a destination name) intern it as
## the entry after the block text; the aux slot carries the secondary
## offset relative to the text index — for destination headings multiplied
## by eight with the heading level packed into the low three bits.
append_with_secondary : DocumentBuilder, U8, Str, Str, U64 -> DocumentBuilder
append_with_secondary = |DocumentBuilder.{ block_aux, block_tags, block_texts, language, metadata_title, text_sources }, tag, text, secondary, aux_pattern| {
	text_id = text_sources.len()
	secondary_id = text_id + 1
	aux = if tag == destination_heading_tag {
		secondary_id * 8 + aux_pattern % 8
	} else {
		secondary_id
	}

	DocumentBuilder.{
		block_aux: block_aux.append(aux),
		block_tags: block_tags.append(tag),
		block_texts: block_texts.append(text_id),
		language,
		metadata_title,
		text_sources: text_sources.append(text).append(secondary),
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

link_tag : U8
link_tag = 5

internal_link_tag : U8
internal_link_tag = 6

destination_heading_tag : U8
destination_heading_tag = 7

destination_paragraph_tag : U8
destination_paragraph_tag = 8

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

## Outline entries and page-label ranges are explicit author inputs and
## default to absence.
expect {
	document = Document.from_blocks({ contents: [], language: "en-AU", title: "Report" })
	entries = [{ depth: 0, destination: "intro", open: True, title: "Introduction" }]
	ranges = [{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }]
	navigated = document.with_outline(entries).with_page_labels(ranges)

	document.outline() == [] and
		document.page_labels() == [] and
			navigated.outline() == entries and
				navigated.page_labels() == ranges
}
