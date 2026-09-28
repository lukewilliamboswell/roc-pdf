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
	Container({ contents : List(DocumentBlock), kind : ContainerKind }),
	DestinationHeading({ level : U8, name : Str, text : Str }),
	DestinationParagraph({ name : Str, text : Str }),
	Heading({ level : U8, text : Str }),
	Figure({ alternative : Str, caption : Caption, drawing : Scene.Drawing }),
	InternalLink({ destination : Str, text : Str }),
	KeepTogether(List(DocumentBlock)),
	KeepWithNext({ contents : List(DocumentBlock), keep : Keep }),
	Link({ text : Str, uri : Str }),
	ListBlock({ items : List(DocumentListItem), marker : ListMarker }),
	PageArtifact({ kind : PageArtifactKind, text : Str }),
	PageBreak,
	Paragraph(Str),
	RichParagraph(List(DocumentInline)),
	Spacer(Layout.Unit),
	Title(Str),
	Unavailable({ feature : AuthoringFeature, summary : Str }),
].{}

## One authored list item: the blocks of its `LBody`, in logical order. Its
## `Lbl` is generated from the enclosing list's marker.
DocumentListItem :: [ListItem(List(DocumentBlock))].{}

## List label numbering styles (ISO 32000-2 Table 380 `ListNumbering`).
NumberStyle : [Decimal, LowerAlpha, LowerRoman, UpperAlpha, UpperRoman]

## A list's generated labels: a bullet (`ListNumbering /Disc`) or numbers
## counting from `start` in a style.
ListMarker : [Bullet, Numbered({ start : U64, style : NumberStyle })]

## The strength of an authored keep-with-next: `Required` is a mandatory
## layout constraint; `Preferred` is the ranked preference R2.
Keep : [Preferred, Required]

## Authored inline content of a rich paragraph. Every alternative carries the
## semantic role it becomes; presentation is Theme policy. Nesting is data,
## normalized with an explicit frame stack rather than recursion.
DocumentInline :: [
	Code(Str),
	Emphasis(List(DocumentInline)),
	Expansion({ expanded : Str, text : Str }),
	InLanguage({ contents : List(DocumentInline), tag : Str }),
	InternalLink({ contents : List(DocumentInline), destination : Str }),
	LineBreak,
	Link({ contents : List(DocumentInline), uri : Str }),
	Quote(List(DocumentInline)),
	Strong(List(DocumentInline)),
	Text(Str),
].{}

## A figure may have visible caption text independently of required alternative text.
Caption := [Caption(Str), NoCaption]

## The PDF 2.0 grouping element a container block becomes: `Part`, `Sect`,
## or `Div`. Grouping has no visual effect; children keep their own roles,
## so headings inside a section remain explicit `H1`..`H6`.
ContainerKind : [Division, Part, Section]

## Stable feature identities used by transactional preparation diagnostics.
AuthoringFeature := [
	AccessibleArchiveProfile,
	ArchiveProfile,
	ComplexTables,
	ContextualArtifacts,
	CustomLayout,
	Figures,
	Floats,
	Footnotes,
	GeneratedReferences,
	MultiColumnLayout,
	PageTemplates,
	SemanticTextProperties,
	SideContent,
	SimpleTables,
	VerticalWriting,
]

PageArtifactKind := [Background, Decoration, Footer, Header, PageNumber, Watermark]

## A semantic block placed into an explicit page frame.
FixedPlacement := { block : DocumentBlock, frame : Layout.Rect }

## A drawing whose non-content purpose and paint layer are explicit.
FixedArtifact := { drawing : Scene.Drawing, kind : PageArtifactKind }

## Immutable result of finishing a fixed-page builder.
FixedPage := {
	artifacts_after : List(FixedArtifact),
	artifacts_before : List(FixedArtifact),
	placements : List(FixedPlacement),
	size : Layout.Size,
}

## Content-first fixed-page authoring. Semantic blocks occupy explicit frames;
## drawings must be classified as before- or after-content artifacts.
FixedPageBuilder :: FixedPage.{
	start : Layout.Size -> FixedPageBuilder
	start = |size| FixedPageBuilder.{ artifacts_after: [], artifacts_before: [], placements: [], size }

	background : FixedPageBuilder, Scene.Drawing -> FixedPageBuilder
	background = |FixedPageBuilder.{ artifacts_after, artifacts_before, placements, size }, drawing| FixedPageBuilder.{ artifacts_after, artifacts_before: artifacts_before.append({ drawing, kind: Background }), placements, size }

	place : FixedPageBuilder, DocumentBlock, Layout.Rect -> FixedPageBuilder
	place = |FixedPageBuilder.{ artifacts_after, artifacts_before, placements, size }, block, frame| FixedPageBuilder.{ artifacts_after, artifacts_before, placements: placements.append({ block, frame }), size }

	overlay : FixedPageBuilder, PageArtifactKind, Scene.Drawing -> FixedPageBuilder
	overlay = |FixedPageBuilder.{ artifacts_after, artifacts_before, placements, size }, kind, drawing| FixedPageBuilder.{ artifacts_after: artifacts_after.append({ drawing, kind }), artifacts_before, placements, size }

	finish : FixedPageBuilder -> FixedPage
	finish = |FixedPageBuilder.{ artifacts_after, artifacts_before, placements, size }| { artifacts_after, artifacts_before, placements, size }
}

NormalizedBlockKind := [
	Bullet({ item : U64, list : U64 }),
	DestinationHeading({ level : U8, name : Str }),
	DestinationParagraph({ name : Str }),
	Figure(U64),
	Heading(U8),
	InternalLink({ destination : Str }),
	Link({ uri : Str }),
	PageArtifact(PageArtifactKind),
	Paragraph,
	RichParagraph(U64),
	Title,
]

## A rich paragraph's span of the dense inline arena: `inlines..inlines +
## length` in preorder, `children` direct children of the paragraph,
## `elements` inline elements, and `leaves` text leaves. `position` is the
## paragraph's index in its parent's authored contents, kept for diagnostics.
## Records live in `NormalizedAuthoring.rich_paragraphs`; a block names its
## record by index, so plain blocks keep their compact kind.
NormalizedRich : { children : U64, elements : U64, inlines : U64, leaves : U64, length : U64, position : U64 }

## An explicit line break inside rich paragraph `paragraph`: the paragraph
## text is split into segments at its line breaks, and every segment is its
## own interned source, so the break is a mandatory line boundary with no
## painted glyph, and paragraphs differing only in break positions never
## share a line-cache identity. `leaf` is the ordinal of the paragraph's
## first text leaf after the break and `text` the segment it begins.
## `parent` (`0` or `i + 1` for inline `i`) and `position` are the break's
## authored location. Breaks are stored in paragraph and authored order.
NormalizedLineBreak : { leaf : U64, paragraph : U64, parent : U64, position : U64, text : Str }

## An authored explicit page break before normalized leaf `block` (equal to
## the leaf count when no leaf follows); `parent` and `position` locate it.
NormalizedPageBreak : { block : U64, parent : U64, position : U64 }

## Authored vertical space between leaves `block - 1` and `block`. Layout
## adds it after leaf `block - 1`; space before the first leaf is at the top
## of a page and therefore suppressed. `parent` and `position` locate it.
NormalizedSpacer : { amount : Layout.Unit, block : U64, parent : U64, position : U64 }

## One authored list: its item count and label marker.
NormalizedList : { items : U64, marker : ListMarker }

## The role of one normalized group. Containers become `Part`, `Sect`, or
## `Div`; an item list becomes `L` (payload: its `lists` index) and each item
## `LI` with a generated `Lbl` and an `LBody` (payload: the item ordinal).
## Keep groups are layout-only and produce no structure element.
NormalizedGroupKind := [Container(ContainerKind), ItemList(U32), KeepTogether, KeepWithNext(Keep), ListItem(U32)]

## The semantic role of one normalized inline. Text leaves hold their exact
## authored string and its byte range in the paragraph's concatenated text.
NormalizedInlineKind := [
	Code,
	Emphasis,
	Expansion(Str),
	InLanguage(Str),
	InternalLink(Str),
	Link(Str),
	Quote,
	Strong,
	Text({ byte_length : U64, byte_start : U64, text : Str }),
]

## One inline in the dense preorder arena of `NormalizedAuthoring.inlines`.
## `parent` is `0` for a direct child of the paragraph and `i + 1` for the
## inline at arena index `i`; `position` is the index in the parent's
## authored list and `depth` is one for a direct child. For an element,
## `element` is its preorder ordinal among the paragraph's elements,
## `children` its direct child count, `spine` the offset of its children in
## the paragraph's content spine, and `first_leaf..leaf_end` the ordinals of
## the text leaves below it. A leaf's `first_leaf` is its own ordinal.
## `language` is `0` or `i + 1` for the nearest enclosing `InLanguage`.
NormalizedInline : { children : U64, depth : U64, element : U64, first_leaf : U64, kind : NormalizedInlineKind, language : U64, leaf_end : U64, parent : U64, position : U64, spine : U64 }

## One normalized leaf block. `parent` is `0` for a child of the Document
## root and `g + 1` for a child of normalized group `g`.
NormalizedBlock := { kind : NormalizedBlockKind, parent : U64, text : Str }

## One authored grouping block in a dense preorder arena. `parent` uses the
## same encoding as leaf blocks; `first_block..block_end` is the contiguous
## span of leaf blocks inside the group's subtree, and `index + 1..group_end`
## the contiguous span of its descendant groups. `position` is the group's
## index in its parent's authored contents (or items). `depth` is the
## container nesting depth for containers (one at the top level) and the
## list nesting level for lists and items; keep groups carry the depth of
## the containers around them. No recursive per-node value survives
## normalization.
NormalizedGroup : { block_end : U64, depth : U64, first_block : U64, group_end : U64, kind : NormalizedGroupKind, parent : U64, position : U64 }

## Dense normalized meaningful-image facts retained between semantic planning,
## layout, resource inspection, and scene lowering.
NormalizedFigure := { alternative : Str, caption : Caption, image : Image.Source, placement : Layout.Rect }

NormalizedAuthoring := {
	blocks : List(NormalizedBlock),
	figures : List(NormalizedFigure),
	groups : List(NormalizedGroup),
	inlines : List(NormalizedInline),
	language : Str,
	line_breaks : List(NormalizedLineBreak),
	lists : List(NormalizedList),
	metadata_title : Str,
	outline : List(OutlineEntry),
	page_breaks : List(NormalizedPageBreak),
	page_labels : List(PageLabelRange),
	rich_paragraphs : List(NormalizedRich),
	spacers : List(NormalizedSpacer),
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
	Fixed({ language : Str, metadata_title : Str, pages : List(FixedPage) }),
	Simple({ contents : List(DocumentBlock), language : Str, metadata_title : Str }),
]

Document :: { authoring : DocumentAuthoring, created : Metadata.TimestampInput, modified : Metadata.TimestampInput, outline : List(OutlineEntry), page_labels : List(PageLabelRange) }.{
	Block : DocumentBlock
	Builder : DocumentBuilder
	Caption : Caption
	ContainerKind : ContainerKind
	Feature : AuthoringFeature
	FixedArtifact : FixedArtifact
	FixedPage : FixedPage
	FixedPageBuilder : FixedPageBuilder
	FixedPlacement : FixedPlacement
	Inline : DocumentInline
	Keep : Keep
	ListItem : DocumentListItem
	ListMarker : ListMarker
	NavigationError : NavigationError
	NormalizedBlock : NormalizedBlock
	NormalizedBlockKind : NormalizedBlockKind
	NormalizedFigure : NormalizedFigure
	NormalizedGroup : NormalizedGroup
	NormalizedGroupKind : NormalizedGroupKind
	NormalizedInline : NormalizedInline
	NormalizedInlineKind : NormalizedInlineKind
	NormalizedLineBreak : NormalizedLineBreak
	NormalizedList : NormalizedList
	NormalizedPageBreak : NormalizedPageBreak
	NormalizedRich : NormalizedRich
	NormalizedSpacer : NormalizedSpacer
	NormalizedAuthoring : NormalizedAuthoring
	NumberStyle : NumberStyle
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

	## Construct an explicitly framed document. Preparation rejects it with the
	## `layout.custom` feature until fixed-layout lowering is executable.
	from_fixed_pages : { language : Str, pages : List(FixedPage), title : Str } -> Document
	from_fixed_pages = |{ language, pages, title: document_title }|
		Document.{
			authoring: Fixed({ language, metadata_title: document_title, pages }),
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

	## A `Part` grouping element around the given blocks, in logical order.
	part : List(DocumentBlock) -> DocumentBlock
	part = |contents| DocumentBlock.Container({ contents, kind: Part })

	## A `Sect` grouping element around the given blocks, in logical order.
	section : List(DocumentBlock) -> DocumentBlock
	section = |contents| DocumentBlock.Container({ contents, kind: Section })

	## A `Div` grouping element around the given blocks, in logical order.
	division : List(DocumentBlock) -> DocumentBlock
	division = |contents| DocumentBlock.Container({ contents, kind: Division })

	## A paragraph of inline content in authored order.
	rich_paragraph : List(DocumentInline) -> DocumentBlock
	rich_paragraph = |inlines| DocumentBlock.RichParagraph(inlines)

	## An unordered list; each item's label is a generated bullet.
	bullet_list : List(DocumentListItem) -> DocumentBlock
	bullet_list = |items| DocumentBlock.ListBlock({ items, marker: Bullet })

	## An ordered list whose generated labels count from `start` in `style`.
	numbered_list : { start : U64, style : NumberStyle }, List(DocumentListItem) -> DocumentBlock
	numbered_list = |numbering, items| DocumentBlock.ListBlock({ items, marker: Numbered(numbering) })

	## One list item holding its body blocks in logical order.
	list_item : List(DocumentBlock) -> DocumentListItem
	list_item = |contents| DocumentListItem.ListItem(contents)

	## A mandatory explicit page break between flow blocks.
	page_break : DocumentBlock
	page_break = DocumentBlock.PageBreak

	## A required keep-together group; it produces no structure element.
	keep_together : List(DocumentBlock) -> DocumentBlock
	keep_together = |contents| DocumentBlock.KeepTogether(contents)

	## Keep a block with the first placement unit of the block after it.
	keep_with_next : Keep, DocumentBlock -> DocumentBlock
	keep_with_next = |keep, block| DocumentBlock.KeepWithNext({ contents: [block], keep })

	## Layout-only vertical space; suppressed at the top of a page.
	spacer : Layout.Unit -> DocumentBlock
	spacer = |amount| DocumentBlock.Spacer(amount)

	## An explicit line break inside a rich paragraph.
	line_break : DocumentInline
	line_break = DocumentInline.LineBreak

	## Plain inline text.
	plain_text : Str -> DocumentInline
	plain_text = |value| DocumentInline.Text(value)

	## Stressed emphasis (`Em`).
	emphasis : List(DocumentInline) -> DocumentInline
	emphasis = |contents| DocumentInline.Emphasis(contents)

	## Strong importance (`Strong`).
	strong : List(DocumentInline) -> DocumentInline
	strong = |contents| DocumentInline.Strong(contents)

	## A fragment of computer code (`Code`).
	code : Str -> DocumentInline
	code = |value| DocumentInline.Code(value)

	## An inline quotation (`Quote`); quotation marks are authored text.
	quote : List(DocumentInline) -> DocumentInline
	quote = |contents| DocumentInline.Quote(contents)

	## A URI link around inline content (`Link`).
	inline_link : List(DocumentInline), Str -> DocumentInline
	inline_link = |contents, uri| DocumentInline.Link({ contents, uri })

	## An internal link around inline content to an authored destination name.
	inline_internal_link : List(DocumentInline), Str -> DocumentInline
	inline_internal_link = |contents, destination| DocumentInline.InternalLink({ contents, destination })

	## Inline content in another natural language (`Span` with `/Lang`).
	in_language : Str, List(DocumentInline) -> DocumentInline
	in_language = |tag, contents| DocumentInline.InLanguage({ contents, tag })

	## An abbreviation and its expansion (`Span` with `/E`).
	expansion : Str, Str -> DocumentInline
	expansion = |value, expanded| DocumentInline.Expansion({ expanded, text: value })

	## Attach meaningful drawing content with required alternative text.
	figure : Scene.Drawing, Str, Caption -> DocumentBlock
	figure = |drawing_value, alternative, caption_value| DocumentBlock.Figure({ alternative, caption: caption_value, drawing: drawing_value })

	## Construct an optional visible figure caption.
	caption : Str -> Caption
	caption = |text| Caption(text)

	## Retain future authoring intent for a feature-specific preparation error.
	unavailable : AuthoringFeature, Str -> DocumentBlock
	unavailable = |feature, summary| DocumentBlock.Unavailable({ feature, summary })

	## Start a content-first fixed page at an explicit size.
	fixed_page : Layout.Size -> FixedPageBuilder
	fixed_page = |size| FixedPageBuilder.start(size)

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
		Fixed(fixed) => fixed.metadata_title
		Simple(simple) => simple.metadata_title
	}

	language : Document -> Str
	language = |document| match document.authoring {
		Compact(compact) => compact.language
		Fixed(fixed) => fixed.language
		Simple(simple) => simple.language
	}

	block_count : Document -> U64
	block_count = |document| match document.authoring {
		Compact(compact) => compact.block_tags.len()
		Fixed(fixed) => fixed_block_count(fixed.pages)
		Simple(simple) => simple.contents.len()
	}

	## Return the first unsupported authored capability in deterministic order.
	first_unavailable : Document -> [Available, UnavailableFeature({ feature : AuthoringFeature, summary : Str })]
	first_unavailable = |document| match document.authoring {
		Fixed(_) => UnavailableFeature({ feature: CustomLayout, summary: "Fixed-page layout is represented by this API but is not executable in this release." })
		Compact(_) => Available
		Simple(simple) => first_unavailable_block(simple.contents)
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
	Fixed(fixed) => { blocks: [], figures: [], groups: [], inlines: [], language: fixed.language, line_breaks: [], lists: [], metadata_title: fixed.metadata_title, outline: [], page_breaks: [], page_labels: [], rich_paragraphs: [], spacers: [] }
	Simple(simple) => normalize_simple(simple)
}

first_unavailable_block : List(DocumentBlock) -> [Available, UnavailableFeature({ feature : AuthoringFeature, summary : Str })]
first_unavailable_block = |blocks| {
	var $index = 0
	while $index < blocks.len() {
		match list_at(blocks, $index) {
			Container({ contents, kind: _ }) => match first_unavailable_nested(contents) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			KeepTogether(contents) => match first_unavailable_nested(contents) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			KeepWithNext({ contents, keep: _ }) => match first_unavailable_nested(contents) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			ListBlock({ items, marker: _ }) => match first_unavailable_nested(item_blocks(items)) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			block => match unavailable_leaf(block) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
		}
		$index = $index + 1
	}
	Available
}

## Grouping blocks are walked with an explicit frame stack, allocated only
## when a document has them, so authored nesting depth never becomes Roc
## call depth. The depth bounds themselves are semantic-planning limits.
first_unavailable_nested : List(DocumentBlock) -> [Available, UnavailableFeature({ feature : AuthoringFeature, summary : Str })]
first_unavailable_nested = |contents| {
	var $frames = [{ blocks: contents, next: 0 }]
	while !$frames.is_empty() {
		top = list_at($frames, $frames.len() - 1)
		if top.next >= top.blocks.len() {
			$frames = $frames.drop_last(1)
		} else {
			$frames = list_set($frames, $frames.len() - 1, { ..top, next: top.next + 1 })
			match list_at(top.blocks, top.next) {
				Container({ contents: nested, kind: _ }) => {
					$frames = $frames.append({ blocks: nested, next: 0 })
				}
				KeepTogether(nested) => {
					$frames = $frames.append({ blocks: nested, next: 0 })
				}
				KeepWithNext({ contents: nested, keep: _ }) => {
					$frames = $frames.append({ blocks: nested, next: 0 })
				}
				ListBlock({ items, marker: _ }) => {
					$frames = $frames.append({ blocks: item_blocks(items), next: 0 })
				}
				block => match unavailable_leaf(block) {
					Available => {}
					UnavailableFeature(found) => return UnavailableFeature(found)
				}
			}
		}
	}
	Available
}

## The blocks of a list's items in authored order, for the availability
## walk only; normalization keeps the item structure.
item_blocks : List(DocumentListItem) -> List(DocumentBlock)
item_blocks = |items| {
	var $blocks = []
	for item in items {
		match item {
			ListItem(contents) => {
				$blocks = $blocks.concat(contents)
			}
		}
	}
	$blocks
}

unavailable_leaf : DocumentBlock -> [Available, UnavailableFeature({ feature : AuthoringFeature, summary : Str })]
unavailable_leaf = |block| match block {
	Figure({ alternative, caption: _, drawing }) => {
		commands = drawing.commands()
		if alternative.is_empty() or commands.len() != 1 {
			UnavailableFeature({ feature: Figures, summary: "The executable figure slice requires non-empty alternative text and exactly one image command." })
		} else {
			match list_at(commands, 0) {
				AuthorImage({ image: _, placement }) => if placement.size.width.raw() <= 0 or placement.size.height.raw() <= 0 {
					UnavailableFeature({ feature: Figures, summary: "Figure image placement must have positive width and height." })
				} else {
					Available
				}
				_ => UnavailableFeature({ feature: Figures, summary: "Vector and grouped drawings remain on the roadmap; the executable slice accepts one image command." })
			}
		}
	}
	Unavailable({ feature, summary }) => UnavailableFeature({ feature, summary })
	_ => Available
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
				$blocks = $blocks.append({ kind: Bullet({ item: $item, list: $list_index }), parent: 0, text: list_at(compact.text_sources, text_index) })
				$item = $item + 1
			}
			$list_index = $list_index + 1
		} else if tag == heading_tag {
			$blocks = $blocks.append({ kind: Heading(aux.to_u8_wrap()), parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == artifact_tag {
			$blocks = $blocks.append({ kind: PageArtifact(decode_artifact(aux)), parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == paragraph_tag {
			$blocks = $blocks.append({ kind: Paragraph, parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == title_tag {
			$blocks = $blocks.append({ kind: Title, parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == link_tag {
			$blocks = $blocks.append({ kind: Link({ uri: list_at(compact.text_sources, aux) }), parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == internal_link_tag {
			$blocks = $blocks.append({ kind: InternalLink({ destination: list_at(compact.text_sources, aux) }), parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == destination_heading_tag {
			$blocks = $blocks.append({ kind: DestinationHeading({ level: (aux % 8).to_u8_wrap(), name: list_at(compact.text_sources, aux // 8) }), parent: 0, text: list_at(compact.text_sources, text) })
		} else if tag == destination_paragraph_tag {
			$blocks = $blocks.append({ kind: DestinationParagraph({ name: list_at(compact.text_sources, aux) }), parent: 0, text: list_at(compact.text_sources, text) })
		} else {
			crash "compact authoring block tag escaped"
		}
		$block_index = $block_index + 1
	}
	{
		blocks: $blocks,
		figures: [],
		groups: [],
		inlines: [],
		language: compact.language,
		line_breaks: [],
		lists: [],
		metadata_title: compact.metadata_title,
		outline: [],
		page_breaks: [],
		page_labels: [],
		rich_paragraphs: [],
		spacers: [],
	}
}

SimpleState : {
	blocks : List(NormalizedBlock),
	figures : List(NormalizedFigure),
	groups : List(NormalizedGroup),
	inlines : List(NormalizedInline),
	line_breaks : List(NormalizedLineBreak),
	list_index : U64,
	lists : List(NormalizedList),
	page_breaks : List(NormalizedPageBreak),
	rich_paragraphs : List(NormalizedRich),
	spacers : List(NormalizedSpacer),
}

normalize_simple : { contents : List(DocumentBlock), language : Str, metadata_title : Str } -> NormalizedAuthoring
normalize_simple = |simple| {
	var $state = { blocks: [], figures: [], groups: [], inlines: [], line_breaks: [], list_index: 0, lists: [], page_breaks: [], rich_paragraphs: [], spacers: [] }
	var $block_index = 0
	while $block_index < simple.contents.len() {
		block = list_at(simple.contents, $block_index)
		$state = if is_grouping(block) append_group($state, block, $block_index) else append_leaf($state, block, 0, $block_index)
		$block_index = $block_index + 1
	}
	{
		blocks: $state.blocks,
		figures: $state.figures,
		groups: $state.groups,
		inlines: $state.inlines,
		language: simple.language,
		line_breaks: $state.line_breaks,
		lists: $state.lists,
		metadata_title: simple.metadata_title,
		outline: [],
		page_breaks: $state.page_breaks,
		page_labels: [],
		rich_paragraphs: $state.rich_paragraphs,
		spacers: $state.spacers,
	}
}

is_grouping : DocumentBlock -> Bool
is_grouping = |block| match block {
	Container(_) | KeepTogether(_) | KeepWithNext(_) | ListBlock(_) => True
	_ => False
}

## A frame of the group walk: the children of group `group` (encoded
## `g + 1`), either blocks or, when `listing`, a list's items. `depth` is the
## enclosing container depth and `list_depth` the list nesting level.
GroupFrame : { blocks : List(DocumentBlock), depth : U64, group : U64, items : List(DocumentListItem), list_depth : U64, listing : Bool, next : U64 }

## Lower one top-level grouping block and its descendants into the preorder
## arenas with an explicit frame stack: entering a group appends its record,
## leaving it closes the group's leaf and descendant spans. A list's frame
## walks its items, each of which opens an item group over its blocks.
append_group : SimpleState, DocumentBlock, U64 -> SimpleState
append_group = |state, block, position| {
	opened = open_block_group(state, block, 0, 0, 0, position)
	var $state = opened.state
	var $frames = [opened.frame]
	while !$frames.is_empty() {
		top = list_at($frames, $frames.len() - 1)
		limit = if top.listing top.items.len() else top.blocks.len()
		if top.next >= limit {
			$frames = $frames.drop_last(1)
			$state = close_group($state, top.group - 1)
		} else {
			$frames = list_set($frames, $frames.len() - 1, { ..top, next: top.next + 1 })
			if top.listing {
				contents = match list_at(top.items, top.next) {
					ListItem(blocks) => blocks
				}
				$state = open_group($state, ListItem(top.next.to_u32_wrap()), top.group, top.list_depth, top.next)
				$frames = $frames.append({ blocks: contents, depth: top.depth, group: $state.groups.len(), items: [], list_depth: top.list_depth, listing: False, next: 0 })
			} else {
				child = list_at(top.blocks, top.next)
				if is_grouping(child) {
					nested = open_block_group($state, child, top.group, top.depth, top.list_depth, top.next)
					$state = nested.state
					$frames = $frames.append(nested.frame)
				} else {
					$state = append_leaf($state, child, top.group, top.next)
				}
			}
		}
	}
	$state
}

open_block_group : SimpleState, DocumentBlock, U64, U64, U64, U64 -> { frame : GroupFrame, state : SimpleState }
open_block_group = |state, block, parent, depth, list_depth, position| match block {
	Container({ contents, kind }) => {
		opened = open_group(state, Container(kind), parent, depth + 1, position)
		{ frame: { blocks: contents, depth: depth + 1, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	KeepTogether(contents) => {
		opened = open_group(state, KeepTogether, parent, depth, position)
		{ frame: { blocks: contents, depth, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	KeepWithNext({ contents, keep }) => {
		opened = open_group(state, KeepWithNext(keep), parent, depth, position)
		{ frame: { blocks: contents, depth, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	ListBlock({ items, marker }) => {
		index = state.lists.len()
		listed = { ..state, lists: state.lists.append({ items: items.len(), marker }) }
		opened = open_group(listed, ItemList(index.to_u32_wrap()), parent, list_depth + 1, position)
		{ frame: { blocks: [], depth, group: opened.groups.len(), items, list_depth: list_depth + 1, listing: True, next: 0 }, state: opened }
	}
	_ => {
		crash "normalized leaf escaped the group walk"
	}
}

open_group : SimpleState, NormalizedGroupKind, U64, U64, U64 -> SimpleState
open_group = |state, kind, parent, depth, position| {
	..state,
	groups: state.groups.append({ block_end: state.blocks.len(), depth, first_block: state.blocks.len(), group_end: state.groups.len() + 1, kind, parent, position }),
}

close_group : SimpleState, U64 -> SimpleState
close_group = |state, group| {
	record = list_at(state.groups, group)
	{ ..state, groups: list_set(state.groups, group, { ..record, block_end: state.blocks.len(), group_end: state.groups.len() }) }
}

append_leaf : SimpleState, DocumentBlock, U64, U64 -> SimpleState
append_leaf = |state, block, parent, position| match block {
	Bullets(items) => {
		var $blocks = state.blocks
		var $item = 0
		while $item < items.len() {
			$blocks = $blocks.append({ kind: Bullet({ item: $item, list: state.list_index }), parent, text: list_at(items, $item) })
			$item = $item + 1
		}
		{ ..state, blocks: $blocks, list_index: state.list_index + 1 }
	}
	Container(_) | KeepTogether(_) | KeepWithNext(_) | ListBlock(_) => {
		crash "normalized group escaped the frame walk"
	}
	DestinationHeading({ level, name, text }) => { ..state, blocks: state.blocks.append({ kind: DestinationHeading({ level, name }), parent, text }) }
	DestinationParagraph({ name, text }) => { ..state, blocks: state.blocks.append({ kind: DestinationParagraph({ name: name }), parent, text }) }
	Heading({ level, text }) => { ..state, blocks: state.blocks.append({ kind: Heading(level), parent, text }) }
	Figure({ alternative, caption, drawing }) => match list_at(drawing.commands(), 0) {
		AuthorImage({ image, placement }) => {
			figure_index = state.figures.len()
			text = match caption {
				Caption(value) => value
				NoCaption => " "
			}
			{ ..state, blocks: state.blocks.append({ kind: Figure(figure_index), parent, text }), figures: state.figures.append({ alternative, caption, image, placement }) }
		}
		_ => crash "validated figure drawing escaped"
	}
	InternalLink({ destination, text }) => { ..state, blocks: state.blocks.append({ kind: InternalLink({ destination: destination }), parent, text }) }
	Link({ text, uri }) => { ..state, blocks: state.blocks.append({ kind: Link({ uri: uri }), parent, text }) }
	PageArtifact({ kind, text }) => { ..state, blocks: state.blocks.append({ kind: PageArtifact(kind), parent, text }) }
	PageBreak => { ..state, page_breaks: state.page_breaks.append({ block: state.blocks.len(), parent, position }) }
	Paragraph(text) => { ..state, blocks: state.blocks.append({ kind: Paragraph, parent, text }) }
	RichParagraph(contents) => append_rich(state, contents, parent, position)
	Spacer(amount) => { ..state, spacers: state.spacers.append({ amount, block: state.blocks.len(), parent, position }) }
	Title(text) => { ..state, blocks: state.blocks.append({ kind: Title, parent, text }) }

	## Preparation rejects this branch before normalization.
	Unavailable({ feature: _, summary: _ }) => { ..state, blocks: state.blocks.append({ kind: Paragraph, parent, text: "" }) }
}

InlineFrame : { breaks : U64, depth : U64, items : List(DocumentInline), language : U64, next : U64, owner : U64 }

## Lower one rich paragraph into the dense preorder inline arena with an
## explicit frame stack, so authored nesting never becomes Roc call depth.
## The paragraph's text is the concatenation of its leaves in logical order:
## one interned source, so line breaking sees the whole paragraph and every
## leaf owns an exact byte range of it. An explicit line break instead ends
## one segment and begins the next: the block text is the first segment,
## each break record carries the segment after it, and a leaf's byte range
## is relative to its own segment. A line break has no inline record and no
## content-spine slot, so each record's `position` is its slot among its
## siblings' records; the break keeps its authored position. Validation
## (emptiness, depth, links, languages, break placement) is a
## semantic-planning concern with stable diagnostics.
append_rich : SimpleState, List(DocumentInline), U64, U64 -> SimpleState
append_rich = |state, contents, parent, position| {
	paragraph = state.rich_paragraphs.len()
	base = state.inlines.len()
	first_break = state.line_breaks.len()
	var $inlines = state.inlines
	var $line_breaks = state.line_breaks
	var $elements = 0
	var $leaves = 0
	var $bytes = 0
	var $root_breaks = 0
	var $frames = [{ breaks: 0, depth: 1, items: contents, language: 0, next: 0, owner: 0 }]
	while !$frames.is_empty() {
		top = list_at($frames, $frames.len() - 1)
		if top.next >= top.items.len() {
			$frames = $frames.drop_last(1)
			if top.owner != 0 {
				record = list_at($inlines, top.owner - 1)
				$inlines = list_set($inlines, top.owner - 1, { ..record, children: record.children - top.breaks, leaf_end: $leaves })
			} else {
				$root_breaks = top.breaks
			}
		} else {
			$frames = list_set($frames, $frames.len() - 1, { ..top, next: top.next + 1 })
			index = $inlines.len()
			slot = top.next - top.breaks
			match list_at(top.items, top.next) {
				LineBreak => {
					$line_breaks = $line_breaks.append({ leaf: $leaves, paragraph, parent: top.owner, position: top.next, text: "" })
					$frames = list_set($frames, $frames.len() - 1, { ..top, breaks: top.breaks + 1, next: top.next + 1 })
					$bytes = 0
				}
				Text(value) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ children: 0, depth: top.depth, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: top.owner, position: slot, spine: 0 })
					$leaves = $leaves + 1
					$bytes = $bytes + length
				}
				Code(value) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ ..inline_element(top, slot, Code, 1, $elements, $leaves), leaf_end: $leaves + 1 })
					$inlines = $inlines.append({ children: 0, depth: top.depth + 1, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: index + 1, position: 0, spine: 0 })
					$elements = $elements + 1
					$leaves = $leaves + 1
					$bytes = $bytes + length
				}
				Expansion({ expanded, text: value }) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ ..inline_element(top, slot, Expansion(expanded), 1, $elements, $leaves), leaf_end: $leaves + 1 })
					$inlines = $inlines.append({ children: 0, depth: top.depth + 1, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: index + 1, position: 0, spine: 0 })
					$elements = $elements + 1
					$leaves = $leaves + 1
					$bytes = $bytes + length
				}
				Emphasis(nested) => {
					$inlines = $inlines.append(inline_element(top, slot, Emphasis, nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: top.language, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
				Strong(nested) => {
					$inlines = $inlines.append(inline_element(top, slot, Strong, nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: top.language, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
				Quote(nested) => {
					$inlines = $inlines.append(inline_element(top, slot, Quote, nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: top.language, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
				Link({ contents: nested, uri }) => {
					$inlines = $inlines.append(inline_element(top, slot, Link(uri), nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: top.language, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
				InternalLink({ contents: nested, destination }) => {
					$inlines = $inlines.append(inline_element(top, slot, InternalLink(destination), nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: top.language, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
				InLanguage({ contents: nested, tag }) => {
					$inlines = $inlines.append(inline_element(top, slot, InLanguage(tag), nested.len(), $elements, $leaves))
					$frames = $frames.append({ breaks: 0, depth: top.depth + 1, items: nested, language: index + 1, next: 0, owner: index + 1 })
					$elements = $elements + 1
				}
			}
		}
	}

	## Each element's children occupy one contiguous span of the content
	## spine after the paragraph's own children, in element preorder.
	children = contents.len() - $root_breaks
	var $spine = children
	var $index = base
	while $index < $inlines.len() {
		record = list_at($inlines, $index)
		match record.kind {
			Text(_) => {}
			_ => {
				$inlines = list_set($inlines, $index, { ..record, spine: $spine })
				$spine = $spine + record.children
			}
		}
		$index = $index + 1
	}
	rich = { children, elements: $elements, inlines: base, leaves: $leaves, length: $inlines.len() - base, position }
	if $line_breaks.len() == first_break {
		text = if $leaves == 1 single_leaf_text($inlines, base) else concatenated_text($inlines, base, $bytes)
		return { ..state, blocks: state.blocks.append({ kind: RichParagraph(paragraph), parent, text }), inlines: $inlines, line_breaks: $line_breaks, rich_paragraphs: state.rich_paragraphs.append(rich) }
	}
	segments = segment_texts($inlines, base, $line_breaks, first_break)
	var $index_break = first_break
	while $index_break < $line_breaks.len() {
		record = list_at($line_breaks, $index_break)
		$line_breaks = list_set($line_breaks, $index_break, { ..record, text: list_at(segments, $index_break - first_break + 1) })
		$index_break = $index_break + 1
	}
	{ ..state, blocks: state.blocks.append({ kind: RichParagraph(paragraph), parent, text: list_at(segments, 0) }), inlines: $inlines, line_breaks: $line_breaks, rich_paragraphs: state.rich_paragraphs.append(rich) }
}

inline_element : InlineFrame, U64, NormalizedInlineKind, U64, U64, U64 -> NormalizedInline
inline_element = |frame, slot, kind, children, element, leaves| { children, depth: frame.depth, element, first_leaf: leaves, kind, language: frame.language, leaf_end: leaves, parent: frame.owner, position: slot, spine: 0 }

single_leaf_text : List(NormalizedInline), U64 -> Str
single_leaf_text = |inlines, base| {
	var $index = base
	var $found = ""
	while $index < inlines.len() {
		match list_at(inlines, $index).kind {
			Text({ byte_length: _, byte_start: _, text }) => {
				$found = text
				$index = inlines.len()
			}
			_ => {
				$index = $index + 1
			}
		}
	}
	$found
}

concatenated_text : List(NormalizedInline), U64, U64 -> Str
concatenated_text = |inlines, base, bytes| {
	var $text = Str.with_capacity(bytes)
	var $index = base
	while $index < inlines.len() {
		match list_at(inlines, $index).kind {
			Text({ byte_length: _, byte_start: _, text }) => {
				$text = $text.concat(text)
			}
			_ => {}
		}
		$index = $index + 1
	}
	$text
}

## The segment texts of a paragraph with line breaks: segment `k` holds the
## leaves from break `k - 1` up to break `k`, in logical order. An empty
## segment (a break at either end, or two adjacent breaks) stays empty here
## and is rejected by semantic planning.
segment_texts : List(NormalizedInline), U64, List(NormalizedLineBreak), U64 -> List(Str)
segment_texts = |inlines, base, line_breaks, first_break| {
	var $segments = List.with_capacity(line_breaks.len() - first_break + 1)
	var $current = ""
	var $next_break = first_break
	var $leaf = 0
	var $index = base
	while $index < inlines.len() {
		match list_at(inlines, $index).kind {
			Text({ byte_length: _, byte_start: _, text }) => {
				while $next_break < line_breaks.len() and list_at(line_breaks, $next_break).leaf <= $leaf {
					$segments = $segments.append($current)
					$current = ""
					$next_break = $next_break + 1
				}
				$current = $current.concat(text)
				$leaf = $leaf + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	while $next_break < line_breaks.len() {
		$segments = $segments.append($current)
		$current = ""
		$next_break = $next_break + 1
	}
	$segments.append($current)
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
	Background => 0
	Decoration => 1
	Footer => 2
	Header => 3
	PageNumber => 4
	Watermark => 5
}

decode_artifact : U64 -> PageArtifactKind
decode_artifact = |value| match value {
	0 => Background
	1 => Decoration
	2 => Footer
	3 => Header
	4 => PageNumber
	5 => Watermark
	_ => {
		crash "compact page artifact kind escaped"
	}
}

fixed_block_count : List(FixedPage) -> U64
fixed_block_count = |pages| {
	var $count = 0
	var $index = 0
	while $index < pages.len() {
		$count = $count + list_at(pages, $index).placements.len()
		$index = $index + 1
	}
	$count
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

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "normalized authoring write escaped"
	}
	Ok(updated) => updated
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
