import Color
import Conformance
import Font
import Image
import Layout
import Metadata
import Scene
import Semantics
import Text
import Theme

DocumentBlock :: [
	Bullets(List(Str)),
	Container({ contents : List(DocumentBlock), kind : ContainerKind }),

	## A separately authored extension block (the custom-block seam),
	## boxed so the block union keeps the size of its other alternatives.
	Custom(Box(CustomSpec)),
	DestinationHeading({ level : U8, name : Str, text : Str }),
	DestinationParagraph({ name : Str, text : Str }),
	Heading({ level : U8, text : Str }),

	## An in-flow decoration (smaller than a figure, so unboxed).
	Decoration(DecorationSpec),
	Figure({ alternative : Str, caption : Caption, drawing : Scene.Drawing, fit : FigurePolicy }),
	InternalLink({ destination : Str, text : Str }),
	KeepTogether(List(DocumentBlock)),
	KeepWithNext({ contents : List(DocumentBlock), keep : Keep }),
	Link({ text : Str, uri : Str }),
	ListBlock({ items : List(DocumentListItem), marker : ListMarker }),
	PageBreak,
	Paragraph(Str),
	RichParagraph(List(DocumentInline)),

	## Blocks whose inline colors a `Theme.Scope` overrides, boxed so the
	## block union keeps the size of its other alternatives.
	Scoped(Box({ contents : List(DocumentBlock), scope : Theme.Scope })),
	Spacer(Layout.Unit),
	Table(Box(TableSpec)),
	Title(Str),
	Unavailable({ feature : AuthoringFeature, summary : Str }),
].{}

## An in-flow decoration: its drawing, the space it keeps above the
## drawing and between the drawing and the next block (`below`, negative
## to overlap that block's first lines by at most the drawing's height),
## and whether it paints behind the page's text or over it.
DecorationSpec : { above : Layout.Unit, behind : Bool, below : Layout.Unit, drawing : Scene.Drawing }

## A custom block as the extension authored it: its semantic content
## (ordinary paragraphs and rich paragraphs, which become a `Div`), its
## measured box (`size`), the inset of the content inside that box on every
## side, a label naming it in diagnostics and the preparation report, and a
## decorative panel drawn in box-local coordinates (origin at the box's
## bottom-left corner, y upward) behind the content. The block is
## unsplittable: it moves whole to the next page. No PDF operators, stores,
## or pagination callbacks cross this boundary.
CustomSpec : { contents : List(DocumentBlock), inset : Layout.Unit, name : Str, panel : Scene.Drawing, size : Layout.Size }

## An ordinary table: boxed, so the authored block union keeps the size of
## its other alternatives. An optional caption, the column declarations, and its
## header, body, and footer rows in logical order. Header rows are declared
## once; the rows of every section become `TR` elements of `THead`, `TBody`,
## and `TFoot`.
TableSpec : { body_rows : List(DocumentRow), caption : Caption, columns : List(TableColumn), footer_rows : List(DocumentRow), header_rows : List(DocumentRow), row_split : RowSplit }

## How a table column is sized: an exact width, a proportional share of the
## width that remains, or its content's width.
ColumnWidth : [Content, Fixed(Layout.Unit), Share(U16)]

## How cell text aligns inside its column: at the start edge, at the end
## edge (numeric amounts), or centered.
ColumnAlign : [Center, End, Start]

TableColumn : { align : ColumnAlign, width : ColumnWidth }

## The cells a header cell heads: those below it in its columns, those in
## its row, or both.
HeaderScope : [Both, Column, Row]

## Whether a body row may break across pages at a line boundary.
RowSplit : [KeepRows, SplitRows]

## How one cell's lines align: in the alignment of the first column it
## spans, or in an explicit alignment of its own.
CellAlign : [Aligned(ColumnAlign), FirstColumn]

## A cell's own background: none, or a solid color painted over its row's
## fill as a layout decoration artifact.
CellFill := [NoCellFill, CellFill(Color.SourceValue)]

## A data cell (`TD`) or a header cell (`TH`) with its declared scope.
CellKind : [DataCell, HeaderCell(HeaderScope)]

## One authored table row: its cells in logical order.
DocumentRow :: [Row(List(DocumentCell))].{}

## One authored table cell: inline content forming one paragraph, its kind,
## and the columns and rows it spans. Row spans are represented so they can
## be rejected with a located diagnostic.
DocumentCell :: [Cell({ align : CellAlign, column_span : U16, contents : List(DocumentInline), fill : CellFill, kind : CellKind, row_span : U16 })].{}

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

	## The physical page number of the page a furniture line is painted on,
	## in a number style. Page fields are resolved after pagination and are
	## page furniture only.
	PageNumber(PageFieldStyle),
	Quote(List(DocumentInline)),

	## Furniture inline content laid out in an exact reserved width, aligned
	## inside it, so a page field's resolved value is proven to fit.
	ReservedWidth({ align : ReservedAlign, contents : List(DocumentInline), width : Layout.Unit }),
	Strong(List(DocumentInline)),
	Text(Str),

	## The document's physical page count, in a number style (furniture only).
	TotalPages(PageFieldStyle),
].{}

## A page field's number style and a reserved width's alignment, held in
## their own nominal types rather than as `NumberStyle` and `ColumnAlign`:
## with a structural enumeration shared by an inline alternative, the pinned
## compiler's code for unrelated rich paragraphs allocates once more
## (docs/performance/page-templates.md). The constructors convert.
PageFieldStyle := [DecimalField, LowerAlphaField, LowerRomanField, UpperAlphaField, UpperRomanField]

ReservedAlign := [CenterReserved, EndReserved, StartReserved]

reserved_align : ColumnAlign -> ReservedAlign
reserved_align = |align| match align {
	Center => CenterReserved
	End => EndReserved
	Start => StartReserved
}

page_field_style : NumberStyle -> PageFieldStyle
page_field_style = |style| match style {
	Decimal => DecimalField
	LowerAlpha => LowerAlphaField
	LowerRoman => LowerRomanField
	UpperAlpha => UpperAlphaField
	UpperRoman => UpperRomanField
}

field_number_style : PageFieldStyle -> NumberStyle
field_number_style = |style| match style {
	DecimalField => Decimal
	LowerAlphaField => LowerAlpha
	LowerRomanField => LowerRoman
	UpperAlphaField => UpperAlpha
	UpperRomanField => UpperRoman
}

## One page furniture item of a template region slot: one line of
## furniture text (text, page fields, and reserved widths), or a decorative
## drawing. Furniture is a page-content artifact: it paints on every page of
## its template and never joins the logical structure.
DocumentFurniture :: [FurnitureDrawing(Scene.Drawing), FurnitureText(List(DocumentInline))].{}

## A header or footer region of a page template: a fixed authored height
## reserved inside the body frame and three slots whose furniture items
## stack vertically, over an optional full-width backdrop drawing.
## `NoRegion` reserves nothing.
DocumentRegion :: [NoRegion, Region({ backdrop : Backdrop, center : List(DocumentFurniture), end : List(DocumentFurniture), height : Layout.Unit, start : List(DocumentFurniture) })].{}

## A region's backdrop: a decorative drawing painted behind its slots, or
## none.
Backdrop : [Backdrop(Scene.Drawing), NoBackdrop]

## The first page's lead region: semantic blocks (such as a letterhead) laid
## out once, below the first page's header, in a reserved height. They keep
## semantic ownership as a `Div` that precedes the body in reading order.
DocumentLeadRegion :: [Lead({ contents : List(DocumentBlock), height : Layout.Unit }), NoLead].{}

## The first page's template.
DocumentFirstPageTemplate :: { footer : DocumentRegion, gap : Layout.Unit, header : DocumentRegion, lead : DocumentLeadRegion }.{}

## The template of every page after the first.
DocumentPageTemplate :: { footer : DocumentRegion, gap : Layout.Unit, header : DocumentRegion }.{}

## A document's page templates, or none (template-free pagination).
DocumentTemplates : [NoTemplates, Templates({ continuation : DocumentPageTemplate, first : DocumentFirstPageTemplate })]

## One inline of a normalized furniture line, flattened: a reserved width
## becomes `BoxStart`, its content, and `BoxEnd`. `position` is the
## inline's index in its authored list and `inner` its index inside a
## reserved width, so diagnostics name `inlines[k]` or
## `inlines[k].inlines[j]`. `Unsupported` is any other inline (including a
## reserved width inside a reserved width), rejected by the template stage.
NormalizedFurnitureInline : [
	BoxEnd,
	BoxStart({ align : ReservedAlign, position : U64, width : Layout.Unit }),
	Field({ field : [PageNumberField, TotalPagesField], inner : [Inner(U64), Outer], position : U64, style : PageFieldStyle }),
	Text({ inner : [Inner(U64), Outer], position : U64, text : Str }),
	Unsupported({ inner : [Inner(U64), Outer], position : U64 }),
]

NormalizedFurniture : [FurnitureDrawing(Scene.Drawing), FurnitureText(List(NormalizedFurnitureInline))]

NormalizedRegion : [NoRegion, Region({ backdrop : Backdrop, center : List(NormalizedFurniture), end : List(NormalizedFurniture), height : Layout.Unit, start : List(NormalizedFurniture) })]

## One normalized page template: its regions and the gap between each
## present region and the flow region.
NormalizedPageTemplate : { footer : NormalizedRegion, gap : Layout.Unit, header : NormalizedRegion }

## The normalized templates. A lead region's blocks are normalized into the
## block and group arenas as their first `LeadRegion` group (group 0), so
## only its reserved height is kept here.
NormalizedTemplates : [NoTemplates, Templates({ continuation : NormalizedPageTemplate, first : NormalizedPageTemplate, lead : [Lead(Layout.Unit), NoLead] })]

## A figure may have visible caption text independently of required alternative text.
Caption := [Caption(Str), NoCaption]

## How a flow figure meets the flow region: at its authored size, or scaled
## uniformly by the largest factor at most one that fits the flow width and
## the smallest page frame together with its caption, never below
## `minimum_percent`.
FigureFit : [Exact, ScaleToFit({ minimum_percent : U8 })]

## A figure's fit policy, held nominally and converted by the constructors
## (a structural enumeration inside the block union costs the pinned
## compiler extra allocations; docs/performance/page-templates.md).
FigurePolicy := [ExactFit, ScaleFit(U64)]

## One validated flow drawing command in drawing-local geometry (origin at
## the drawing's bottom-left, y upward). Groups are flattened: their
## translations are applied to every point. `image` indexes the drawing's
## own `images`.
FlowCommand : [
	FlowImage({ image : U64, placement : Layout.Rect }),
	FlowPath({ fill : [Fill(Color.SourceValue), NoFill], segments : List(Scene.PathSegment), stroke : [NoStroke, Stroke({ color : Color.SourceValue, width : Layout.Unit })] }),

	## A text label, its origin translated into drawing coordinates; boxed
	## so the command union keeps its size.
	FlowText(Box(Scene.Label)),
]

## A validated flow drawing: its flattened commands, the image sources
## they place in command order, and its extent from the origin.
FlowDrawing : { commands : List(FlowCommand), height : U64, images : List(Image.Source), width : U64 }

## A figure or decoration drawing after validation at normalization. An
## invalid drawing keeps its reason so semantic planning can reject it at
## its authored location.
ValidatedDrawing : [InvalidDrawing(Str), ValidDrawing(FlowDrawing)]

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
	FigureFit,
	Figures,
	Floats,
	Footnotes,
	GeneratedReferences,
	MultiColumnLayout,
	PageTemplates,
	SemanticTextProperties,
	SideContent,
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

	## A table cell authored with no inline content (`Pdf.cell([])`): a
	## `TD` or `TH` with no text. It has no source, no shaped run, and no
	## line; its row keeps its grid position, and structure gives it an
	## element with no marked content. Every stage after normalization
	## handles it explicitly instead of inferring it from empty text.
	EmptyCell,
	Figure(U64),

	## The visible caption of figure `k`: a `Caption` sibling of the
	## `Figure` inside the figure's `Sect`, related by `CaptionFor`.
	FigureCaption(U64),
	Heading(U8),
	InternalLink({ destination : Str }),
	Link({ uri : Str }),
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

## An authored in-flow decoration before leaf `block` (equal to the leaf
## count when no leaf follows): a `Decoration` page artifact that occupies
## its drawing's height immediately above that leaf's first line, on the
## same page. `parent` and `position` locate it.
## `behind` paints the decoration before its page's text. Its drawing
## already includes its authored spacing (`space_decoration`).
NormalizedDecoration : { behind : Bool, block : U64, drawing : ValidatedDrawing, parent : U64, position : U64 }

## One custom block: its `Custom` group, the name the extension gave it,
## its measured box, the content inset, and its validated panel drawing.
NormalizedCustom : { group : U64, height : Layout.Unit, inset : Layout.Unit, name : Str, panel : ValidatedDrawing, width : Layout.Unit }

## One authored list: its item count and label marker.
NormalizedList : { items : U64, marker : ListMarker }

## One authored table: its columns, row split policy, whether a caption
## leaf precedes its rows, and its row counts per section.
NormalizedTable : { body_rows : U64, caption : Bool, columns : List(TableColumn), footer_rows : U64, header_rows : U64, row_split : RowSplit }

## One table cell, in leaf-block order: its rich-paragraph leaf `block`, its
## kind, its authored column and row spans, and its line alignment.
##
## `fill` is zero, or the cell's own background packed by `pack_color`.
## Spans keep their authored `U16` so the record stays 24 bytes: a wider
## cell record made every document allocate more under the pinned
## compiler (docs/performance/tables.md).
NormalizedCell : { align : CellAlign, block : U64, column_span : U16, fill : U64, kind : CellKind, row_span : U16 }

## The section a normalized table row belongs to.
TableSection : [Body, Footer, Header]

## The role of one normalized group. Containers become `Part`, `Sect`, or
## `Div`; an item list becomes `L` (payload: its `lists` index) and each item
## `LI` with a generated `Lbl` and an `LBody` (payload: the item ordinal).
## Keep groups are layout-only and produce no structure element.
##
## A table becomes `Table` (payload: its `tables` index) holding its caption
## leaf and one `TableRow` group per row, whose payload names its section and
## whose `position` is the row's index in that section. Each cell is a rich
## paragraph leaf of its row group, described in `cells`.
##
## `LeadRegion` is the first page template's lead region: a `Div` of
## semantic blocks laid out in its reserved region, first in reading order.
##
## `FigureGroup` is a captioned figure: a `Sect` holding its `Figure` leaf and
## its `FigureCaption` leaf (payload: the figure's `figures` index).
##
## `Custom` is a custom block (payload: its `customs` index): a `Div` of its
## paragraphs for semantics and one unsplittable unit for layout.
NormalizedGroupKind := [Container(ContainerKind), Custom(U32), FigureGroup(U32), ItemList(U32), KeepTogether, KeepWithNext(Keep), LeadRegion, ListItem(U32), Scope(U32), Table(U32), TableRow(TableSection)]

## The semantic role of one normalized inline. Text leaves hold their exact
## authored string and its byte range in the paragraph's concatenated text.
##
## `FurnitureOnly` is a page field or reserved width authored in body
## content. It holds no text and no children; semantic planning rejects it,
## because page fields are page furniture only.
NormalizedInlineKind := [
	Code,
	Emphasis,
	Expansion(Str),
	FurnitureOnly,
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

## Dense normalized figure facts retained between semantic planning,
## layout, resource inspection, and scene lowering: the alternative text,
## whether a caption leaf follows the figure leaf, the validated drawing,
## and the fit policy.
NormalizedFigure := { alternative : Str, captioned : Bool, drawing : ValidatedDrawing, fit : FigurePolicy }

NormalizedAuthoring := {
	blocks : List(NormalizedBlock),
	cells : List(NormalizedCell),
	customs : List(NormalizedCustom),
	decorations : List(NormalizedDecoration),
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
	scopes : List(Theme.Scope),
	spacers : List(NormalizedSpacer),
	tables : List(NormalizedTable),
	templates : NormalizedTemplates,
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
	finish = |state| Document.{ authoring: Compact(state), created: Omitted, modified: Omitted, outline: [], page_labels: [], templates: NoTemplates }
}

DocumentAuthoring := [
	Compact(DocumentBuilder),
	Fixed({ language : Str, metadata_title : Str, pages : List(FixedPage) }),
	Simple({ contents : List(DocumentBlock), language : Str, metadata_title : Str }),
]

Document :: { authoring : DocumentAuthoring, created : Metadata.TimestampInput, modified : Metadata.TimestampInput, outline : List(OutlineEntry), page_labels : List(PageLabelRange), templates : DocumentTemplates }.{
	Block : DocumentBlock
	Builder : DocumentBuilder
	Caption : Caption
	Cell : DocumentCell
	CellAlign : CellAlign
	CellFill : CellFill

	## A normalized cell's own fill color.
	cell_fill : NormalizedCell -> CellFill
	cell_fill = |cell| if cell.fill == 0 NoCellFill else CellFill(unpack_color(cell.fill))

	CellKind : CellKind
	ColumnAlign : ColumnAlign
	ColumnWidth : ColumnWidth
	ContainerKind : ContainerKind
	Feature : AuthoringFeature
	FixedArtifact : FixedArtifact
	FixedPage : FixedPage
	FixedPageBuilder : FixedPageBuilder
	FixedPlacement : FixedPlacement
	FirstPageTemplate : DocumentFirstPageTemplate
	Furniture : DocumentFurniture
	HeaderScope : HeaderScope
	Inline : DocumentInline
	Keep : Keep
	LeadRegion : DocumentLeadRegion
	ListItem : DocumentListItem
	ListMarker : ListMarker
	NavigationError : NavigationError
	NormalizedBlock : NormalizedBlock
	NormalizedBlockKind : NormalizedBlockKind
	NormalizedCell : NormalizedCell
	NormalizedDecoration : NormalizedDecoration
	NormalizedCustom : NormalizedCustom
	CustomSpec : CustomSpec
	NormalizedFigure : NormalizedFigure
	FigureFit : FigureFit
	FigurePolicy : FigurePolicy
	FlowCommand : FlowCommand
	FlowDrawing : FlowDrawing
	ValidatedDrawing : ValidatedDrawing
	NormalizedGroup : NormalizedGroup
	NormalizedGroupKind : NormalizedGroupKind
	NormalizedInline : NormalizedInline
	NormalizedInlineKind : NormalizedInlineKind
	NormalizedLineBreak : NormalizedLineBreak
	NormalizedList : NormalizedList
	NormalizedPageBreak : NormalizedPageBreak
	NormalizedPageTemplate : NormalizedPageTemplate
	NormalizedFurniture : NormalizedFurniture
	NormalizedFurnitureInline : NormalizedFurnitureInline
	NormalizedRegion : NormalizedRegion
	PageFieldStyle : PageFieldStyle
	ReservedAlign : ReservedAlign

	## The number style a page field is written in.
	page_field_number_style : PageFieldStyle -> NumberStyle
	page_field_number_style = |style| field_number_style(style)
	NormalizedRich : NormalizedRich
	NormalizedSpacer : NormalizedSpacer
	NormalizedTable : NormalizedTable
	NormalizedTemplates : NormalizedTemplates
	NormalizedAuthoring : NormalizedAuthoring
	NumberStyle : NumberStyle
	OutlineEntry : OutlineEntry
	PageArtifactKind : PageArtifactKind
	PageLabelRange : PageLabelRange
	PageLabelStyle : PageLabelStyle
	PageTemplate : DocumentPageTemplate
	Region : DocumentRegion
	Backdrop : Backdrop
	Row : DocumentRow
	RowSplit : RowSplit
	TableColumn : TableColumn
	TableSection : TableSection
	TableSpec : TableSpec
	Templates : DocumentTemplates

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
			templates: NoTemplates,
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
			templates: NoTemplates,
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
		templates: document.templates,
	}

	with_modified : Document, Str -> Document
	with_modified = |document, timestamp| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: Explicit(timestamp),
		outline: document.outline,
		page_labels: document.page_labels,
		templates: document.templates,
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
		templates: document.templates,
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
		templates: document.templates,
	}

	created : Document -> Metadata.TimestampInput
	created = |document| document.created

	modified : Document -> Metadata.TimestampInput
	modified = |document| document.modified

	outline : Document -> List(OutlineEntry)
	outline = |document| document.outline

	page_labels : Document -> List(PageLabelRange)
	page_labels = |document| document.page_labels

	## First-page and continuation-page templates: reserved header, footer,
	## and first-page lead regions, and the furniture they paint. Without
	## templates, pagination uses the theme's body frame on every page.
	with_page_templates : Document, { continuation : DocumentPageTemplate, first : DocumentFirstPageTemplate } -> Document
	with_page_templates = |document, { continuation, first }| Document.{
		authoring: document.authoring,
		created: document.created,
		modified: document.modified,
		outline: document.outline,
		page_labels: document.page_labels,
		templates: Templates({ continuation, first }),
	}

	## Whether the document declares page templates.
	has_templates : Document -> Bool
	has_templates = |document| match document.templates {
		NoTemplates => False
		Templates(_) => True
	}

	first_page_template : { footer : DocumentRegion, gap : Layout.Unit, header : DocumentRegion, lead : DocumentLeadRegion } -> DocumentFirstPageTemplate
	first_page_template = |{ footer, gap, header, lead }| DocumentFirstPageTemplate.{ footer, gap, header, lead }

	page_template : { footer : DocumentRegion, gap : Layout.Unit, header : DocumentRegion } -> DocumentPageTemplate
	page_template = |{ footer, gap, header }| DocumentPageTemplate.{ footer, gap, header }

	region : { center : List(DocumentFurniture), end : List(DocumentFurniture), height : Layout.Unit, start : List(DocumentFurniture) } -> DocumentRegion
	region = |{ center, end, height, start }| DocumentRegion.Region({ backdrop: NoBackdrop, center, end, height, start })

	## A region with a backdrop drawing behind its slots.
	with_backdrop : DocumentRegion, Scene.Drawing -> DocumentRegion
	with_backdrop = |value, drawing| match value {
		NoRegion => DocumentRegion.Region({ backdrop: Backdrop(drawing), center: [], end: [], height: Layout.Unit.from_raw(0), start: [] })
		Region(record) => DocumentRegion.Region({ ..record, backdrop: Backdrop(drawing) })
	}

	no_region : DocumentRegion
	no_region = DocumentRegion.NoRegion

	lead_region : Layout.Unit, List(DocumentBlock) -> DocumentLeadRegion
	lead_region = |height, contents| DocumentLeadRegion.Lead({ contents, height })

	no_lead : DocumentLeadRegion
	no_lead = DocumentLeadRegion.NoLead

	furniture_text : List(DocumentInline) -> DocumentFurniture
	furniture_text = |contents| DocumentFurniture.FurnitureText(contents)

	furniture_image : Scene.Drawing -> DocumentFurniture
	furniture_image = |drawing_value| DocumentFurniture.FurnitureDrawing(drawing_value)

	page_number : NumberStyle -> DocumentInline
	page_number = |style| DocumentInline.PageNumber(page_field_style(style))

	total_pages : NumberStyle -> DocumentInline
	total_pages = |style| DocumentInline.TotalPages(page_field_style(style))

	reserved_width : Layout.Unit, ColumnAlign, List(DocumentInline) -> DocumentInline
	reserved_width = |width, align, contents| DocumentInline.ReservedWidth({ align: reserved_align(align), contents, width })

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

	scoped : Theme.Scope, List(DocumentBlock) -> DocumentBlock
	scoped = |scope, contents| DocumentBlock.Scoped(Box.box({ contents, scope }))

	## Keep a block with the first placement unit of the block after it.
	keep_with_next : Keep, DocumentBlock -> DocumentBlock
	keep_with_next = |keep, block| DocumentBlock.KeepWithNext({ contents: [block], keep })

	## Layout-only vertical space; suppressed at the top of a page.
	spacer : Layout.Unit -> DocumentBlock
	spacer = |amount| DocumentBlock.Spacer(amount)

	## An ordinary table of rows and cells.
	table : TableSpec -> DocumentBlock
	table = |spec| DocumentBlock.Table(Box.box(spec))

	## One table row of cells in logical order.
	row : List(DocumentCell) -> DocumentRow
	row = |cells| DocumentRow.Row(cells)

	## A data cell (`TD`) of inline content.
	cell : List(DocumentInline) -> DocumentCell
	cell = |contents| DocumentCell.Cell({ align: FirstColumn, column_span: 1, contents, fill: NoCellFill, kind: DataCell, row_span: 1 })

	## A header cell (`TH`) with its declared scope.
	header_cell : HeaderScope, List(DocumentInline) -> DocumentCell
	header_cell = |scope, contents| DocumentCell.Cell({ align: FirstColumn, column_span: 1, contents, fill: NoCellFill, kind: HeaderCell(scope), row_span: 1 })

	## A cell spanning `count` columns.
	spanning : U16, DocumentCell -> DocumentCell
	spanning = |count, value| match value {
		Cell(record) => DocumentCell.Cell({ ..record, column_span: count })
	}

	## A cell whose lines align at `align` instead of in the alignment of
	## the first column it spans.
	aligned : ColumnAlign, DocumentCell -> DocumentCell
	aligned = |align, value| match value {
		Cell(record) => DocumentCell.Cell({ ..record, align: Aligned(align) })
	}

	## A cell with its own background color.
	shaded : Color.SourceValue, DocumentCell -> DocumentCell
	shaded = |color, value| match value {
		Cell(record) => DocumentCell.Cell({ ..record, fill: CellFill(color) })
	}

	## A cell spanning `count` rows; row spans are outside the supported
	## subset and reject at preparation.
	row_spanning : U16, DocumentCell -> DocumentCell
	row_spanning = |count, value| match value {
		Cell(record) => DocumentCell.Cell({ ..record, row_span: count })
	}

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
	figure = |drawing_value, alternative, caption_value| DocumentBlock.Figure({ alternative, caption: caption_value, drawing: drawing_value, fit: ExactFit })

	## Select how a figure meets the flow region. On any block other than a
	## figure this is rejected (`document.figure_fit`).
	figure_fit : DocumentBlock, FigureFit -> DocumentBlock
	figure_fit = |block, fit| match block {
		Figure({ alternative, caption: caption_value, drawing, fit: _ }) => DocumentBlock.Figure({ alternative, caption: caption_value, drawing, fit: figure_policy(fit) })
		_ => DocumentBlock.Unavailable({ feature: FigureFit, summary: "figure_fit applies only to a figure block." })
	}

	## An in-flow decorative drawing: a `Decoration` page artifact that
	## occupies its drawing's height immediately above the next flow block.
	decoration : Scene.Drawing -> DocumentBlock
	decoration = |drawing_value| DocumentBlock.Decoration({ above: Layout.Unit.from_raw(0), behind: Bool.False, below: Layout.Unit.from_raw(0), drawing: drawing_value })

	## An in-flow decoration with its own spacing and paint layer.
	spaced_decoration : Scene.Drawing, { above : Layout.Unit, behind : Bool, below : Layout.Unit } -> DocumentBlock
	spaced_decoration = |drawing_value, { above, behind, below }| DocumentBlock.Decoration({ above, behind, below, drawing: drawing_value })

	## A custom block from a separately authored extension: its paragraphs
	## become a `Div`, laid out inside its measured box, with its panel
	## painted behind them as a `Decoration` artifact. It is unsplittable.
	custom_block : CustomSpec -> DocumentBlock
	custom_block = |spec| DocumentBlock.Custom(Box.box(spec))

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
	first_unavailable = |document| {
		match document.templates {
			NoTemplates => {}
			Templates({ continuation: _, first }) => match first.lead {
				NoLead => {}
				Lead({ contents, height: _ }) => match first_unavailable_block(contents) {
					Available => {}
					UnavailableFeature(found) => return UnavailableFeature(found)
				}
			}
		}
		match document.authoring {
			Fixed(_) => UnavailableFeature({ feature: CustomLayout, summary: "Fixed-page layout is represented by this API but is not executable in this release." })
			Compact(_) => Available
			Simple(simple) => first_unavailable_block(simple.contents)
		}
	}

	## Both authoring front ends lower once to the same flat text/block store.
	## String payloads remain shared values; block and list identity are scalar facts.
	normalize : Document -> NormalizedAuthoring

	##
	## Page templates normalize their regions as authored values and their
	## lead region's blocks first, as group 0 (`LeadRegion`), so the lead
	## precedes the body in every arena and in reading order.
	normalize = |document| match document.templates {
		NoTemplates => {
			normalized = normalize_authoring(document.authoring, empty_state)
			{ ..normalized, outline: document.outline, page_labels: document.page_labels }
		}
		Templates({ continuation, first }) => {
			lead = match first.lead {
				NoLead => { height: NoLead, state: empty_state }
				Lead({ contents, height }) => { height: Lead(height), state: append_lead(empty_state, contents) }
			}
			normalized = normalize_authoring(document.authoring, lead.state)
			templates = Templates({
				continuation: { footer: normalize_region(continuation.footer), gap: continuation.gap, header: normalize_region(continuation.header) },
				first: { footer: normalize_region(first.footer), gap: first.gap, header: normalize_region(first.header) },
				lead: lead.height,
			})
			{ ..normalized, outline: document.outline, page_labels: document.page_labels, templates }
		}
	}
}

normalize_region : DocumentRegion -> NormalizedRegion
normalize_region = |region| match region {
	NoRegion => NoRegion
	Region({ backdrop, center, end, height, start }) => Region({ backdrop, center: center.map(normalize_furniture), end: end.map(normalize_furniture), height, start: start.map(normalize_furniture) })
}

normalize_furniture : DocumentFurniture -> NormalizedFurniture
normalize_furniture = |furniture| match furniture {
	FurnitureDrawing(drawing) => FurnitureDrawing(drawing)
	FurnitureText(inlines) => FurnitureText(flatten_furniture(inlines))
}

## Flatten one furniture line. A reserved width's content is walked one
## level deep; anything deeper is `Unsupported`, so no recursion follows
## authored nesting.
flatten_furniture : List(DocumentInline) -> List(NormalizedFurnitureInline)
flatten_furniture = |inlines| {
	var $flat = List.with_capacity(inlines.len())
	var $position = 0
	while $position < inlines.len() {
		match list_at(inlines, $position) {
			ReservedWidth({ align, contents, width }) => {
				$flat = $flat.append(BoxStart({ align, position: $position, width }))
				var $inner = 0
				while $inner < contents.len() {
					$flat = $flat.append(furniture_leaf(list_at(contents, $inner), $position, Inner($inner)))
					$inner = $inner + 1
				}
				$flat = $flat.append(BoxEnd)
			}
			other => {
				$flat = $flat.append(furniture_leaf(other, $position, Outer))
			}
		}
		$position = $position + 1
	}
	$flat
}

furniture_leaf : DocumentInline, U64, [Inner(U64), Outer] -> NormalizedFurnitureInline
furniture_leaf = |inline, position, inner| match inline {
	Text(text) => Text({ inner, position, text })
	PageNumber(style) => Field({ field: PageNumberField, inner, position, style })
	TotalPages(style) => Field({ field: TotalPagesField, inner, position, style })
	_ => Unsupported({ inner, position })
}

empty_state : SimpleState
empty_state = { blocks: [], cells: [], customs: [], decorations: [], figures: [], groups: [], inlines: [], line_breaks: [], list_index: 0, lists: [], page_breaks: [], rich_paragraphs: [], scopes: [], spacers: [], tables: [] }

normalize_authoring : DocumentAuthoring, SimpleState -> NormalizedAuthoring
normalize_authoring = |authoring, initial| match authoring {
	Compact(compact) => normalize_compact(compact, initial)
	Fixed(fixed) => { blocks: [], cells: [], customs: [], decorations: [], figures: [], groups: [], inlines: [], language: fixed.language, line_breaks: [], lists: [], metadata_title: fixed.metadata_title, outline: [], page_breaks: [], page_labels: [], rich_paragraphs: [], scopes: [], spacers: [], tables: [], templates: NoTemplates }
	Simple(simple) => normalize_simple(simple, initial)
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
			Custom(spec) => match first_unavailable_nested(Box.unbox(spec).contents) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			KeepTogether(contents) => match first_unavailable_nested(contents) {
				Available => {}
				UnavailableFeature(found) => return UnavailableFeature(found)
			}
			Scoped(scoped) => match first_unavailable_nested(Box.unbox(scoped).contents) {
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
				Custom(spec) => {
					$frames = $frames.append({ blocks: Box.unbox(spec).contents, next: 0 })
				}
				KeepTogether(nested) => {
					$frames = $frames.append({ blocks: nested, next: 0 })
				}
				Scoped(scoped) => {
					$frames = $frames.append({ blocks: Box.unbox(scoped).contents, next: 0 })
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
				$blocks = append_all($blocks, contents)
			}
		}
	}
	$blocks
}

unavailable_leaf : DocumentBlock -> [Available, UnavailableFeature({ feature : AuthoringFeature, summary : Str })]
unavailable_leaf = |block| match block {
	Unavailable({ feature, summary }) => UnavailableFeature({ feature, summary })
	_ => Available
}

## `initial` holds a lead region's normalized blocks (or nothing); compact
## blocks follow them at the top level.
normalize_compact : DocumentBuilder, SimpleState -> NormalizedAuthoring
normalize_compact = |compact, initial| {
	var $blocks = initial.blocks
	var $block_index = 0
	var $list_index = initial.list_index
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
		cells: initial.cells,
		customs: initial.customs,
		decorations: initial.decorations,
		figures: initial.figures,
		groups: initial.groups,
		inlines: initial.inlines,
		language: compact.language,
		line_breaks: initial.line_breaks,
		lists: initial.lists,
		metadata_title: compact.metadata_title,
		outline: [],
		page_breaks: initial.page_breaks,
		page_labels: [],
		rich_paragraphs: initial.rich_paragraphs,
		scopes: initial.scopes,
		spacers: initial.spacers,
		tables: initial.tables,
		templates: NoTemplates,
	}
}

SimpleState : {
	blocks : List(NormalizedBlock),
	cells : List(NormalizedCell),
	customs : List(NormalizedCustom),
	decorations : List(NormalizedDecoration),
	figures : List(NormalizedFigure),
	groups : List(NormalizedGroup),
	inlines : List(NormalizedInline),
	line_breaks : List(NormalizedLineBreak),
	list_index : U64,
	lists : List(NormalizedList),
	page_breaks : List(NormalizedPageBreak),
	rich_paragraphs : List(NormalizedRich),
	scopes : List(Theme.Scope),
	spacers : List(NormalizedSpacer),
	tables : List(NormalizedTable),
}

normalize_simple : { contents : List(DocumentBlock), language : Str, metadata_title : Str }, SimpleState -> NormalizedAuthoring
normalize_simple = |simple, initial| {
	var $state = initial
	var $block_index = 0
	while $block_index < simple.contents.len() {
		block = list_at(simple.contents, $block_index)
		$state = if is_grouping(block) append_group($state, block, $block_index) else append_leaf($state, block, 0, $block_index)
		$block_index = $block_index + 1
	}
	{
		blocks: $state.blocks,
		cells: $state.cells,
		customs: $state.customs,
		decorations: $state.decorations,
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
		scopes: $state.scopes,
		spacers: $state.spacers,
		tables: $state.tables,
		templates: NoTemplates,
	}
}

is_grouping : DocumentBlock -> Bool
is_grouping = |block| match block {
	Container(_) | Custom(_) | KeepTogether(_) | KeepWithNext(_) | ListBlock(_) | Scoped(_) => True
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
	walk_group(opened.state, opened.frame)
}

## The first page's lead region: a top-level `LeadRegion` group (a `Div`)
## at container depth one, whose blocks normalize exactly as a division's.
append_lead : SimpleState, List(DocumentBlock) -> SimpleState
append_lead = |state, contents| {
	opened = open_group(state, LeadRegion, 0, 1, 0)
	walk_group(opened, { blocks: contents, depth: 1, group: opened.groups.len(), items: [], list_depth: 0, listing: False, next: 0 })
}

## Walk an opened group's frame and its descendants to completion.
walk_group : SimpleState, GroupFrame -> SimpleState
walk_group = |opened_state, opened_frame| {
	var $state = opened_state
	var $frames = [opened_frame]
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
	Custom(boxed) => {
		spec = Box.unbox(boxed)
		index = state.customs.len()
		custom = { group: state.groups.len(), height: spec.size.height, inset: spec.inset, name: spec.name, panel: validate_flow_drawing(spec.panel), width: spec.size.width }
		opened = open_group({ ..state, customs: state.customs.append(custom) }, Custom(index.to_u32_wrap()), parent, depth + 1, position)
		{ frame: { blocks: spec.contents, depth: depth + 1, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	KeepTogether(contents) => {
		opened = open_group(state, KeepTogether, parent, depth, position)
		{ frame: { blocks: contents, depth, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	KeepWithNext({ contents, keep }) => {
		opened = open_group(state, KeepWithNext(keep), parent, depth, position)
		{ frame: { blocks: contents, depth, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
	}
	Scoped(boxed) => {
		scoped = Box.unbox(boxed)
		index = state.scopes.len()
		opened = open_group({ ..state, scopes: state.scopes.append(scoped.scope) }, Scope(index.to_u32_wrap()), parent, depth, position)
		{ frame: { blocks: scoped.contents, depth, group: opened.groups.len(), items: [], list_depth, listing: False, next: 0 }, state: opened }
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
	Container(_) | Custom(_) | KeepTogether(_) | KeepWithNext(_) | ListBlock(_) | Scoped(_) => {
		crash "normalized group escaped the frame walk"
	}
	DestinationHeading({ level, name, text }) => { ..state, blocks: state.blocks.append({ kind: DestinationHeading({ level, name }), parent, text }) }
	DestinationParagraph({ name, text }) => { ..state, blocks: state.blocks.append({ kind: DestinationParagraph({ name: name }), parent, text }) }
	Heading({ level, text }) => { ..state, blocks: state.blocks.append({ kind: Heading(level), parent, text }) }
	Decoration(spec) => {
		{ ..state, decorations: state.decorations.append({ behind: spec.behind, block: state.blocks.len(), drawing: space_decoration(without_decoration_labels(validate_flow_drawing(spec.drawing)), spec.above, spec.below), parent, position }) }
	}
	Figure({ alternative, caption, drawing, fit }) => append_figure(state, { alternative, caption, drawing, fit }, parent, position)
	InternalLink({ destination, text }) => { ..state, blocks: state.blocks.append({ kind: InternalLink({ destination: destination }), parent, text }) }
	Link({ text, uri }) => { ..state, blocks: state.blocks.append({ kind: Link({ uri: uri }), parent, text }) }
	PageBreak => { ..state, page_breaks: state.page_breaks.append({ block: state.blocks.len(), parent, position }) }
	Paragraph(text) => { ..state, blocks: state.blocks.append({ kind: Paragraph, parent, text }) }
	RichParagraph(contents) => append_rich(state, contents, parent, position)
	Spacer(amount) => { ..state, spacers: state.spacers.append({ amount, block: state.blocks.len(), parent, position }) }
	Table(spec) => append_table(state, Box.unbox(spec), parent, position)
	Title(text) => { ..state, blocks: state.blocks.append({ kind: Title, parent, text }) }

	## Preparation rejects this branch before normalization.
	Unavailable({ feature: _, summary: _ }) => { ..state, blocks: state.blocks.append({ kind: Paragraph, parent, text: "" }) }
}

## Lower one table: its `Table` group, an optional caption paragraph leaf,
## and one `TableRow` group per row (header, body, then footer rows) whose
## cells are rich paragraph leaves described in the `cells` arena. A table
## has fixed depth, so no frame stack is needed.
append_table : SimpleState, TableSpec, U64, U64 -> SimpleState
append_table = |state, spec, parent, position| {
	table_group = state.groups.len()
	table_code = table_group + 1
	var $state = open_group({ ..state, tables: state.tables.append({ body_rows: spec.body_rows.len(), caption: has_caption(spec.caption), columns: spec.columns, footer_rows: spec.footer_rows.len(), header_rows: spec.header_rows.len(), row_split: spec.row_split }) }, Table(state.tables.len().to_u32_wrap()), parent, 0, position)
	match spec.caption {
		Caption(text) => {
			$state = { ..$state, blocks: $state.blocks.append({ kind: Paragraph, parent: table_code, text }) }
		}
		NoCaption => {}
	}
	$state = append_table_rows($state, spec.header_rows, Header, table_code)
	$state = append_table_rows($state, spec.body_rows, Body, table_code)
	$state = append_table_rows($state, spec.footer_rows, Footer, table_code)
	close_group($state, table_group)
}

## Lower one figure. An uncaptioned figure is one `Figure` leaf. A
## captioned figure is a `FigureGroup` (a `Sect`) holding the `Figure` leaf
## and a `FigureCaption` leaf, so the caption stays a visible `Caption`
## beside the figure rather than hidden under the figure's `/Alt`. The
## figure leaf's text is one space: the anchor line its drawing occupies.
append_figure : SimpleState, { alternative : Str, caption : Caption, drawing : Scene.Drawing, fit : FigurePolicy }, U64, U64 -> SimpleState
append_figure = |state, authored, parent, position| {
	index = state.figures.len()
	figure = { alternative: authored.alternative, captioned: has_caption(authored.caption), drawing: validate_flow_drawing(authored.drawing), fit: authored.fit }
	figured = { ..state, figures: state.figures.append(figure) }
	match authored.caption {
		NoCaption => { ..figured, blocks: figured.blocks.append({ kind: Figure(index), parent, text: " " }) }
		Caption(text) => {
			group = figured.groups.len()
			opened = open_group(figured, FigureGroup(index.to_u32_wrap()), parent, 0, position)
			placed = { ..opened, blocks: opened.blocks.append({ kind: Figure(index), parent: group + 1, text: " " }).append({ kind: FigureCaption(index), parent: group + 1, text }) }
			close_group(placed, group)
		}
	}
}

## Figure and decoration drawings nest at most this many groups deep.
flow_group_depth : U64
flow_group_depth = 8

## Validate one figure or decoration drawing: at least one command; images
## with a positive size and paths with a solid fill, a solid stroke of
## positive width, or both, each beginning with a move or a rectangle; and
## groups nested at most `flow_group_depth` deep. Each group's translation
## is applied to the points and placements it contains, so the result is
## flat. Every command lies at or beyond the origin; the extent is the
## union of the commands from the origin, a stroke extending its path by
## half its width on every side. Opacity, clip, and soft-mask groups are
## not supported.
## A decoration paints after the page's text, so a label in it would sit
## under the decoration's own paths; decorations take no text labels.
without_decoration_labels : ValidatedDrawing -> ValidatedDrawing
without_decoration_labels = |validated| match validated {
	ValidDrawing(drawing) => if drawing.commands.any(
		|command| match command {
			FlowText(_) => Bool.True
			_ => Bool.False
		},
	) {
		InvalidDrawing("a decoration takes no text labels; put labels in a figure's drawing or a custom block's panel")
	} else {
		validated
	}
	InvalidDrawing(_) => validated
}

## A decoration's drawing with its spacing applied: the space above adds to
## its height, and the space below lifts every command by that amount and
## adds to its height too (a negative amount lowers the commands into the
## next block instead). The decoration then occupies `above + height +
## below`, exactly as an unspaced drawing occupies its height. Negative
## space above, or an overlap deeper than the drawing, is invalid.
space_decoration : ValidatedDrawing, Layout.Unit, Layout.Unit -> ValidatedDrawing
space_decoration = |validated, above, below| match validated {
	InvalidDrawing(_) => validated
	ValidDrawing(drawing) => {
		up = above.raw()
		down = below.raw()
		if up == 0 and down == 0 {
			return validated
		}
		if up < 0 {
			return InvalidDrawing("the space above a decoration is negative")
		}
		if !within_bound(up) or !within_bound(down) or down + drawing.height.to_i64_wrap() < 0 {
			return InvalidDrawing("a decoration overlaps the next block by more than its own height")
		}
		var $moved = List.with_capacity(drawing.commands.len())
		for command in drawing.commands {
			$moved = $moved.append(
				match command {
					FlowImage({ image, placement }) => FlowImage({ image, placement: { origin: { x: placement.origin.x, y: Layout.Unit.from_raw(placement.origin.y.raw() + down) }, size: placement.size } })
					FlowPath({ fill, segments, stroke }) => FlowPath({ fill, segments: lift_segments(segments, down), stroke })
					FlowText(boxed) => FlowText(boxed)
				},
			)
		}
		ValidDrawing({ ..drawing, commands: $moved, height: (drawing.height.to_i64_wrap() + up + down).to_u64_wrap() })
	}
}

lift_segments : List(Scene.PathSegment), I64 -> List(Scene.PathSegment)
lift_segments = |segments, dy| {
	lift = |point| { x: point.x, y: Layout.Unit.from_raw(point.y.raw() + dy) }
	segments.map(
		|segment| match segment {
			Close => Close
			CubicTo({ control_1, control_2, end }) => CubicTo({ control_1: lift(control_1), control_2: lift(control_2), end: lift(end) })
			LineTo(point) => LineTo(lift(point))
			MoveTo(point) => MoveTo(lift(point))
			Rectangle(rect) => Rectangle({ origin: lift(rect.origin), size: rect.size })
		},
	)
}

validate_flow_drawing : Scene.Drawing -> ValidatedDrawing
validate_flow_drawing = |drawing| {
	commands = drawing.commands()
	if commands.is_empty() {
		return InvalidDrawing("it has no commands")
	}
	var $converted = List.with_capacity(commands.len())
	var $images = []
	var $groups = []
	var $labels = 0
	var $dx = 0
	var $dy = 0
	var $width = 0
	var $height = 0
	var $index = 0
	while $index < commands.len() {
		## Close every group that ends before this command.
		while !$groups.is_empty() and list_at($groups, $groups.len() - 1).end <= $index {
			closed = list_at($groups, $groups.len() - 1)
			$dx = $dx - closed.x
			$dy = $dy - closed.y
			$groups = $groups.drop_last(1)
		}
		match list_at(commands, $index) {
			AuthorImage({ image, placement }) => {
				if !within_bound(placement.origin.x.raw()) or !within_bound(placement.origin.y.raw()) or !within_bound(placement.size.width.raw()) or !within_bound(placement.size.height.raw()) {
					return InvalidDrawing("a coordinate lies more than 10^9 pt from the drawing origin")
				}
				x = placement.origin.x.raw() + $dx
				y = placement.origin.y.raw() + $dy
				if placement.size.width.raw() <= 0 or placement.size.height.raw() <= 0 or x < 0 or y < 0 {
					return InvalidDrawing("an image placement needs a positive size at or beyond the drawing origin")
				}
				$width = U64.max($width, (x + placement.size.width.raw()).to_u64_wrap())
				$height = U64.max($height, (y + placement.size.height.raw()).to_u64_wrap())
				$converted = $converted.append(FlowImage({ image: $images.len(), placement: { origin: { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }, size: placement.size } }))
				$images = $images.append(image)
			}
			AuthorPath({ path: segments, style }) => {
				fill = match style.fill {
					AuthorNoFill => NoFill
					AuthorSolidFill(color) => Fill(color)
				}
				stroke = match style.stroke {
					AuthorNoStroke => NoStroke
					AuthorSolidStroke({ color, width }) => {
						if width.raw() <= 0 or !within_bound(width.raw()) {
							return InvalidDrawing("a stroke needs a positive width")
						}
						Stroke({ color, width })
					}
				}
				half = match stroke {
					NoStroke => 0
					Stroke({ color: _, width }) => (width.raw() + 1) // 2
				}
				paints = match (fill, stroke) {
					(NoFill, NoStroke) => False
					_ => True
				}
				if !paints {
					return InvalidDrawing("a path paints nothing without a fill or a stroke")
				}
				moved = match translate_segments(segments, $dx, $dy) {
					Moved(value) => value
					OutOfRange => return InvalidDrawing("a coordinate lies more than 10^9 pt from the drawing origin")
				}
				match flow_path_bounds(moved) {
					NoPoints => return InvalidDrawing("a path needs at least one segment beginning with a move or a rectangle")
					Bounds({ max_x, max_y, min_x, min_y }) => {
						if min_x - half < 0 or min_y - half < 0 {
							return InvalidDrawing(origin_violation(moved, half, $index))
						}
						$width = U64.max($width, (max_x + half).to_u64_wrap())
						$height = U64.max($height, (max_y + half).to_u64_wrap())
					}
				}
				$converted = $converted.append(FlowPath({ fill, segments: moved, stroke }))
			}
			AuthorTranslate({ commands: count, offset }) => {
				if $groups.len() >= flow_group_depth {
					return InvalidDrawing("groups nest more than ${flow_group_depth.to_str()} deep")
				}
				if count > commands.len() - $index - 1 {
					return InvalidDrawing("a group extends past the drawing's last command")
				}
				if !within_bound(offset.x.raw()) or !within_bound(offset.y.raw()) {
					return InvalidDrawing("a coordinate lies more than 10^9 pt from the drawing origin")
				}
				end = $index + 1 + count
				$groups = $groups.append({ end, x: offset.x.raw(), y: offset.y.raw() })
				$dx = $dx + offset.x.raw()
				$dy = $dy + offset.y.raw()
			}
			AuthorGroup(_) => return InvalidDrawing("opacity, clip, soft-mask, and transform groups are not supported; group drawings with Scene.Drawing.group")
			AuthorText(boxed) => {
				label = Box.unbox(boxed)
				if !within_bound(label.origin.x.raw()) or !within_bound(label.origin.y.raw()) or !within_bound(label.size.raw()) {
					return InvalidDrawing("a coordinate lies more than 10^9 pt from the drawing origin")
				}
				x = label.origin.x.raw() + $dx
				y = label.origin.y.raw() + $dy
				if label.text.is_empty() {
					return InvalidDrawing("a text label is empty")
				}
				if label.size.raw() <= 0 {
					return InvalidDrawing("a text label needs a positive size")
				}
				if x < 0 or y < 0 {
					return InvalidDrawing("a text label's origin lies below or left of the drawing origin")
				}

				## A label's baseline plus its size is known before shaping and
				## joins the drawing's height; its width is proved after
				## shaping, against the width the paths and images give.
				$height = U64.max($height, (y + label.size.raw()).to_u64_wrap())
				$width = U64.max($width, x.to_u64_wrap())
				$labels = $labels + 1
				$converted = $converted.append(FlowText(Box.box({ ..label, origin: { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) } })))
			}
		}
		$index = $index + 1
	}
	if $converted.len() == $labels {
		return InvalidDrawing("it has no painting command")
	}
	if $width == 0 or $height == 0 {
		return InvalidDrawing("it has no positive extent")
	}
	ValidDrawing({ commands: $converted, height: $height, images: $images, width: $width })
}

## Why a path's extent reaches below or left of the drawing origin, and
## where, for its diagnostic: its own geometry (a move, line, curve end,
## or rectangle corner), a Bézier control point (the extent is the
## control-point hull, which contains the curve), or, when every point is
## inside, its stroke's half-width. Coordinates are drawing-local, after
## any group offsets. Only a rejected path reaches this.
origin_violation : List(Scene.PathSegment), I64, U64 -> Str
origin_violation = |segments, half, command| {
	var $geometry = NoPoint
	var $control = NoPoint
	var $low_x = I64.highest
	var $low_y = I64.highest
	for segment in segments {
		anchors = match segment {
			Close => []
			CubicTo({ end, .. }) => [end]
			LineTo(point) | MoveTo(point) => [point]
			Rectangle(rect) => [rect.origin, { x: Layout.Unit.from_raw(rect.origin.x.raw() + rect.size.width.raw()), y: Layout.Unit.from_raw(rect.origin.y.raw() + rect.size.height.raw()) }]
		}
		controls = match segment {
			CubicTo({ control_1, control_2, .. }) => [control_1, control_2]
			_ => []
		}
		for point in anchors {
			$low_x = I64.min($low_x, point.x.raw())
			$low_y = I64.min($low_y, point.y.raw())
			if $geometry == NoPoint and (point.x.raw() < 0 or point.y.raw() < 0) {
				$geometry = At(point.x.raw(), point.y.raw())
			}
		}
		for point in controls {
			if $control == NoPoint and (point.x.raw() < 0 or point.y.raw() < 0) {
				$control = At(point.x.raw(), point.y.raw())
			}
		}
	}
	prefix = "command ${command.to_str()} (a path)"
	match ($geometry, $control) {
		(At(x, y), _) => "${prefix} has a point at (${signed_points(x)}, ${signed_points(y)}), below or left of the drawing origin"
		(NoPoint, At(x, y)) => "${prefix} has a Bézier control point at (${signed_points(x)}, ${signed_points(y)}), below or left of the drawing origin; a path's extent includes its control points, so move the control point or the whole path"
		(NoPoint, NoPoint) => "${prefix} lies inside the drawing, but its stroke's half-width of ${signed_points(half)} reaches (${signed_points($low_x - half)}, ${signed_points($low_y - half)}), below or left of the drawing origin; move the path in by at least half the stroke width"
	}
}

## A signed millipoint length as points, such as `-3 pt` or `0.375 pt`.
signed_points : I64 -> Str
signed_points = |raw| {
	magnitude = if raw < 0 (0 - raw).to_u64_wrap() else raw.to_u64_wrap()
	sign = if raw < 0 "-" else ""
	fraction = magnitude % 1000
	if fraction == 0 {
		"${sign}${(magnitude // 1000).to_str()} pt"
	} else {
		digits = (1000 + fraction).to_str()
		var $trimmed = Str.to_utf8(digits).drop_first(1)
		while $trimmed.last() == Ok('0') {
			$trimmed = $trimmed.drop_last(1)
		}
		text = match Str.from_utf8($trimmed) {
			Ok(value) => value
			Err(_) => "0"
		}
		"${sign}${(magnitude // 1000).to_str()}.${text} pt"
	}
}

## A path translated by a group offset. Every coordinate must lie within
## `flow_coordinate_bound` of the origin before and after translation, so
## no later arithmetic can overflow.
translate_segments : List(Scene.PathSegment), I64, I64 -> [Moved(List(Scene.PathSegment)), OutOfRange]
translate_segments = |segments, dx, dy| {
	var $moved = List.with_capacity(segments.len())
	for segment in segments {
		points = match segment {
			Close => []
			CubicTo({ control_1, control_2, end }) => [control_1, control_2, end]
			LineTo(point) => [point]
			MoveTo(point) => [point]
			Rectangle(rect) => [rect.origin, { x: rect.size.width, y: rect.size.height }]
		}
		for point in points {
			if !within_bound(point.x.raw()) or !within_bound(point.y.raw()) {
				return OutOfRange
			}
		}
		move = |point| { x: Layout.Unit.from_raw(point.x.raw() + dx), y: Layout.Unit.from_raw(point.y.raw() + dy) }
		$moved = $moved.append(
			match segment {
				Close => Close
				CubicTo({ control_1, control_2, end }) => CubicTo({ control_1: move(control_1), control_2: move(control_2), end: move(end) })
				LineTo(point) => LineTo(move(point))
				MoveTo(point) => MoveTo(move(point))
				Rectangle(rect) => Rectangle({ origin: move(rect.origin), size: rect.size })
			},
		)
	}
	Moved($moved)
}

## Authored drawing coordinates, sizes, and accumulated group offsets stay
## within 10^9 pt of the origin.
flow_coordinate_bound : I64
flow_coordinate_bound = 1000000000000

within_bound : I64 -> Bool
within_bound = |value| value <= flow_coordinate_bound and value >= 0 - flow_coordinate_bound

## The bounds of a path's points: control points included, so the extent
## is conservative for curves. A path must begin with a move or rectangle.
flow_path_bounds : List(Scene.PathSegment) -> [Bounds({ max_x : I64, max_y : I64, min_x : I64, min_y : I64 }), NoPoints]
flow_path_bounds = |segments| {
	valid_start = match segments.first() {
		Ok(MoveTo(_)) | Ok(Rectangle(_)) => True
		_ => False
	}
	if !valid_start {
		return NoPoints
	}
	var $min_x = I64.highest
	var $min_y = I64.highest
	var $max_x = I64.lowest
	var $max_y = I64.lowest
	for segment in segments {
		points = match segment {
			Close => []
			CubicTo({ control_1, control_2, end }) => [control_1, control_2, end]
			LineTo(point) => [point]
			MoveTo(point) => [point]
			Rectangle(rect) => [rect.origin, { x: Layout.Unit.from_raw(rect.origin.x.raw() + rect.size.width.raw()), y: Layout.Unit.from_raw(rect.origin.y.raw() + rect.size.height.raw()) }]
		}
		for point in points {
			$min_x = I64.min($min_x, point.x.raw())
			$min_y = I64.min($min_y, point.y.raw())
			$max_x = I64.max($max_x, point.x.raw())
			$max_y = I64.max($max_y, point.y.raw())
		}
	}
	Bounds({ max_x: $max_x, max_y: $max_y, min_x: $min_x, min_y: $min_y })
}

figure_policy : FigureFit -> FigurePolicy
figure_policy = |fit| match fit {
	Exact => ExactFit
	ScaleToFit({ minimum_percent }) => ScaleFit(minimum_percent.to_u64())
}

has_caption : Caption -> Bool
has_caption = |caption| match caption {
	Caption(_) => True
	NoCaption => False
}

## An exact color as one integer: `1 << 48` plus the red, green, and blue
## channels for an sRGB color, `2 << 48` plus the channel for a gray one.
pack_color : Color.SourceValue -> U64
pack_color = |color| match color {
	Srgb(Rgb({ blue, green, red })) => rgb_color_kind + red.to_u64().shl_wrap(32) + green.to_u64().shl_wrap(16) + blue.to_u64()
	Srgb(Gray(level)) => gray_color_kind + level.to_u64()
}

unpack_color : U64 -> Color.SourceValue
unpack_color = |packed| {
	channel = |shift| packed.shr_wrap(shift).bitwise_and(0xFFFF).to_u16_wrap()
	if packed >= gray_color_kind Srgb(Gray(channel(0))) else Srgb(Rgb({ blue: channel(0), green: channel(16), red: channel(32) }))
}

rgb_color_kind : U64
rgb_color_kind = 0x1_0000_0000_0000

gray_color_kind : U64
gray_color_kind = 0x2_0000_0000_0000

append_table_rows : SimpleState, List(DocumentRow), TableSection, U64 -> SimpleState
append_table_rows = |state, rows, section, table_code| {
	var $state = state
	var $ordinal = 0
	while $ordinal < rows.len() {
		cells = match list_at(rows, $ordinal) {
			Row(value) => value
		}
		row_group = $state.groups.len()
		$state = open_group($state, TableRow(section), table_code, 0, $ordinal)
		var $index = 0
		while $index < cells.len() {
			record = match list_at(cells, $index) {
				Cell(value) => value
			}
			fill = match record.fill {
				NoCellFill => 0
				CellFill(color) => pack_color(color)
			}
			$state = { ..$state, cells: $state.cells.append({ align: record.align, block: $state.blocks.len(), column_span: record.column_span, fill, kind: record.kind, row_span: record.row_span }) }
			$state = if record.contents.is_empty() {
				{ ..$state, blocks: $state.blocks.append({ kind: EmptyCell, parent: row_group + 1, text: "" }) }
			} else {
				append_rich($state, record.contents, row_group + 1, $index)
			}
			$index = $index + 1
		}
		$state = close_group($state, row_group)
		$ordinal = $ordinal + 1
	}
	$state
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
	var $last_text = 0
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
					## The break's separator: the text before it gains a
					## trailing U+0020, painted at the end of its line, so
					## logical text keeps a word boundary at the break. The
					## segment's byte cursor restarts below, so no offset
					## moves.
					$inlines = separate_leaf($inlines, $last_text, base)
					$line_breaks = $line_breaks.append({ leaf: $leaves, paragraph, parent: top.owner, position: top.next, text: "" })
					$frames = list_set($frames, $frames.len() - 1, { ..top, breaks: top.breaks + 1, next: top.next + 1 })
					$bytes = 0
				}
				Text(value) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ children: 0, depth: top.depth, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: top.owner, position: slot, spine: 0 })
					$last_text = $inlines.len()
					$leaves = $leaves + 1
					$bytes = $bytes + length
				}
				Code(value) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ ..inline_element(top, slot, Code, 1, $elements, $leaves), leaf_end: $leaves + 1 })
					$inlines = $inlines.append({ children: 0, depth: top.depth + 1, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: index + 1, position: 0, spine: 0 })
					$last_text = $inlines.len()
					$elements = $elements + 1
					$leaves = $leaves + 1
					$bytes = $bytes + length
				}
				Expansion({ expanded, text: value }) => {
					length = value.count_utf8_bytes()
					$inlines = $inlines.append({ ..inline_element(top, slot, Expansion(expanded), 1, $elements, $leaves), leaf_end: $leaves + 1 })
					$inlines = $inlines.append({ children: 0, depth: top.depth + 1, element: 0, first_leaf: $leaves, kind: Text({ byte_length: length, byte_start: $bytes, text: value }), language: top.language, leaf_end: $leaves + 1, parent: index + 1, position: 0, spine: 0 })
					$last_text = $inlines.len()
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

				## Furniture-only inlines hold no text here; semantic
				## planning rejects them with their inline path.
				PageNumber(_) | ReservedWidth(_) | TotalPages(_) => {
					$inlines = $inlines.append(inline_element(top, slot, FurnitureOnly, 0, $elements, $leaves))
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

## The text leaf `last_text - 1` before a line break, ending in U+0020: the
## break's separator. A leaf already ending in a space keeps its text; a
## break before the paragraph's first leaf (rejected later) changes nothing.
separate_leaf : List(NormalizedInline), U64, U64 -> List(NormalizedInline)
separate_leaf = |inlines, last_text, base| {
	if last_text <= base {
		return inlines
	}
	index = last_text - 1
	record = list_at(inlines, index)
	match record.kind {
		Text({ byte_length, byte_start, text }) => if text.ends_with(" ") inlines else list_set(inlines, index, { ..record, kind: Text({ byte_length: byte_length + 1, byte_start, text: text.concat(" ") }) })
		_ => inlines
	}
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

	## A segment's leaf texts are joined once when the segment ends. Growing
	## the segment with `Str.concat` sized it exactly on every leaf, which
	## copied the segment once per leaf.
	var $current = []
	var $next_break = first_break
	var $leaf = 0
	var $index = base
	while $index < inlines.len() {
		match list_at(inlines, $index).kind {
			Text({ byte_length: _, byte_start: _, text }) => {
				while $next_break < line_breaks.len() and list_at(line_breaks, $next_break).leaf <= $leaf {
					$segments = $segments.append(Str.join_with($current, ""))
					$current = []
					$next_break = $next_break + 1
				}
				$current = $current.append(text)
				$leaf = $leaf + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	while $next_break < line_breaks.len() {
		$segments = $segments.append(Str.join_with($current, ""))
		$current = []
		$next_break = $next_break + 1
	}
	$segments.append(Str.join_with($current, ""))
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

## Appends every element of `source`. `List.concat` sizes its result
## exactly, so an accumulator grown by `concat` in a loop was reallocated,
## and copied, on every call; `append` grows geometrically
## (docs/performance/emission-linearity.md).
append_all : List(a), List(a) -> List(a)
append_all = |target, source| {
	var $out = target
	var $index = 0
	while $index < source.len() {
		$out = $out.append(list_at(source, $index))
		$index = $index + 1
	}
	$out
}

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
		.add_paragraph("Closing")

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

## Nested translated groups flatten: every point moves by the accumulated
## offsets of its groups, and the extent covers the moved commands.
expect {
	black = Color.srgb8({ blue: 0, green: 0, red: 0 })
	inner = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 10, 5), black)
	drawing = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 1, 1), black).group(Layout.point(20, 10), Scene.drawing({}).group(Layout.point(5, 5), inner))
	match validate_flow_drawing(drawing) {
		ValidDrawing({ commands: [_, FlowPath({ fill: Fill(_), segments: [Rectangle(rect)], stroke: NoStroke })], height, images: [], width }) => rect.origin.x.raw() == 25000 and rect.origin.y.raw() == 15000 and width == 35000 and height == 20000
		_ => False
	}
}

## Nine nested groups, a path moved left of the origin, a drawing without
## a painting command, and an empty drawing are rejected with a reason.
expect {
	black = Color.srgb8({ blue: 0, green: 0, red: 0 })
	mark = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 4, 4), black)
	var $deep = mark
	var $level = 0
	while $level < 9 {
		$deep = Scene.drawing({}).group(Layout.point(1, 1), $deep)
		$level = $level + 1
	}
	rejected = |drawing| match validate_flow_drawing(drawing) {
		InvalidDrawing(_) => True
		ValidDrawing(_) => False
	}
	rejected($deep) and rejected(Scene.drawing({}).group(Layout.point(-5, 0), mark)) and rejected(Scene.drawing({}).group(Layout.point(1, 1), Scene.drawing({}))) and rejected(Scene.drawing({}))
}
