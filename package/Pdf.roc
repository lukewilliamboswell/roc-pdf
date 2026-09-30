import Color
import Conformance
import Document
import Font
import Image
import KernelLex
import KernelEmit
import KernelBuiltInFont
import KernelFacadePipeline
import KernelFont
import KernelFontPlan
import KernelMetadata
import KernelNavigation
import KernelPdfA4
import KernelSrgbProfile
import KernelXmp
import Metadata
import Semantics
import KernelFacadeFragments
import KernelFacadeFurniture
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
import KernelFacadeReport
import KernelFacadeScenes
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelColor
import KernelContent
import KernelObjectPlan
import KernelTaggedTextStructure
import KernelImage
import KernelLineLayout
import KernelPageLayout
import KernelPdfFont
import KernelPdfText
import KernelScene
import KernelUnicode
import KernelObject
import KernelSeal
import KernelStructure
import KernelSemantics
import KernelShape
import KernelTextSemantics
import Layout
import Scene
import Theme

Pdf :: [].{
	Profile := [AccessibleArchive, Archive, Standard]

	## The facade records whether its selected theme face is the small packaged
	## face or one of the opaque faces retained by a caller font registry. Both
	## cases resolve to one validated inspection before the shared pipeline; no
	## later stage branches on font provenance.
	FontSource := [BuiltIn, Registered(Font.Registry)]

	PageSize := [A4, Letter]
	ChunkRetention := [OwnChunks, ShareUnchangedResources]

	## Stable roadmap feature identity carried by `FeatureUnavailable` diagnostics.
	Feature : Document.Feature

	## Opaque inline content of a rich paragraph. Each constructor below fixes
	## the semantic role its content becomes; `Theme` decides presentation.
	Inline : Document.Inline

	## One list item: its body blocks, with a generated label.
	ListItem : Document.ListItem

	## Generated number styles of a numbered list.
	NumberStyle : Document.NumberStyle

	## The strength of a keep-with-next: `Required` is a mandatory layout
	## constraint; `Preferred` is a ranked preference that may be relaxed.
	Keep : Document.Keep

	## One table column: how it is sized and how its cell text aligns.
	## `Fixed` is an exact width; `Share(n)` takes `n` shares of the width
	## left after fixed and content columns; `Content` takes its widest
	## content, reduced toward its widest unbreakable word only as needed.
	Column : Document.TableColumn

	## How content aligns inside its box: table cell text in its column, or
	## furniture content inside a reserved width.
	Align : Document.ColumnAlign

	## One table row of cells, from `row`.
	Row : Document.Row

	## One table cell, from `cell` or `header_cell`.
	Cell : Document.Cell

	## The cells a header cell heads: the data cells below it in its columns
	## (`Column`), the data cells of its row (`Row`), or both.
	Scope : Document.HeaderScope

	## Whether a body row may break across pages at a line boundary
	## (`SplitRows`) or always moves whole to the next page (`KeepRows`).
	RowSplit : Document.RowSplit

	## The first page's template: header, lead, and footer regions and the
	## gap between each present region and the body flow.
	FirstPageTemplate : Document.FirstPageTemplate

	## The template of every page after the first.
	PageTemplate : Document.PageTemplate

	## A header or footer region: a reserved height and three slots of
	## stacked furniture, or no region.
	Region : Document.Region

	## The first page's lead region of semantic blocks, or none.
	LeadRegion : Document.LeadRegion

	## One page furniture item: a line of furniture text or a decorative
	## drawing.
	Furniture : Document.Furniture

	## How a figure meets the flow region: `Exact` (the default) keeps its
	## authored size and rejects a figure that does not fit;
	## `ScaleToFit({ minimum_percent })` scales the drawing (never its
	## caption) uniformly by the largest factor at most one that fits.
	FigureFit : Document.FigureFit

	## A custom block from a separately authored extension (the custom-block
	## seam). The extension supplies ordinary blocks (paragraphs and rich
	## paragraphs), which keep their semantics inside a `Div`, and the
	## measurement it performed: the block's `size` in the flow and the
	## `inset` of its content on every side. The package lays the content
	## out at `size.width` less twice the inset and proves that it fits
	## `size.height` less twice the inset (`layout.custom_block_measure`
	## otherwise); the block then occupies exactly `size.height`. `panel` is
	## a decorative drawing of solid paths in box-local coordinates (origin
	## at the box's bottom-left corner, y upward), painted behind the
	## content as a `Decoration` artifact owned by the block.
	## `fragmentation` is `Unsplittable`, the only supported value: the
	## block moves whole to the next page, and one taller than a page flow
	## region is `layout.oversize_block`. No PDF operators, private stores,
	## or pagination callbacks are part of this contract.
	CustomBlock : { contents : List(Document.Block), fragmentation : [Unsplittable], inset : Layout.Unit, name : Str, panel : Scene.Drawing, size : Layout.Size }

	## The bounded, read-only preparation report returned beside a prepared
	## document by `prepare_with_report`. `facts` are mechanically proven
	## observations of the preparation; `obligations` are the human-review
	## obligations the document carries, which no preparation can discharge.
	## Every observation names the authored location it comes from as a
	## path such as `contents[2].contents[0]` or
	## `contents[3].inlines[1]`, the same paths diagnostics use. Pages are
	## numbered from 1. The report holds no PDF object identity, compiler
	## stage, or resource payload, and building it never changes the
	## prepared document's bytes.
	Report : { facts : ReportFacts, obligations : List(ReportObligation) }

	## - `title` and `language` are the authored metadata title and document
	##   language (author assertions).
	## - `pages` summarizes each final page: its number and fragment count.
	## - `blocks` lists every leaf block in logical reading order with its
	##   structure role and its final layout: first and last page and
	##   fragment count.
	## - `alternatives` lists authored alternatives and assertions: figure
	##   alternative text, abbreviation expansions, and nested languages.
	## - `outcomes` lists layout-policy outcomes.
	## - `coverage` lists, per leaf block, the text each output font and
	##   script covers (consecutive runs merged), in scalars.
	ReportFacts : {
		alternatives : List(ReportAlternative),
		blocks : List(ReportBlock),
		coverage : List(ReportCoverage),
		language : Str,
		outcomes : List(ReportOutcome),
		pages : List(ReportPage),
		title : Str,
	}
	ReportPage : { fragments : U64, page : U64 }
	ReportBlock : { first_page : U64, fragments : U64, last_page : U64, path : Str, role : Str }
	ReportAlternative : { kind : [Alternative, Expansion, Language], path : Str, text : Str }
	ReportCoverage : { font : U64, path : Str, scalars : U64, script : Str }

	## A layout-policy outcome: a ranked preference the accepted pagination
	## relaxed (at its declaring block), each figure's applied scale in
	## thousandths with its fit policy, each page on which a continued table
	## repaints its header rows, each page on which a split table row
	## continues, and the page and measured height of each custom block.
	ReportOutcome : [
		CustomBlockPlaced({ height : Layout.Unit, name : Str, page : U64, path : Str }),
		FigureScale({ fit : [Exact, ScaleToFit], path : Str, scale : U64 }),
		PreferenceRelaxed({ page : U64, path : Str, preference : [AuthorKeep, FooterCarry, HeadingKeep, Orphan, Widow] }),
		RepeatedHeader({ page : U64, path : Str, rows : U64 }),
		RowContinued({ page : U64, path : Str }),
	]

	## One human-review obligation at an authored location: whether a
	## figure's alternative text conveys what it communicates, whether the
	## reading order of the document (`document`) and of each custom block
	## is meaningful, whether a table's header cells head their data, whether
	## a link's text states its purpose, whether a declared language covers
	## exactly its text, and whether an expansion is accurate.
	ReportObligation : { obligation : [AlternativeTextMeaningful, ExpansionAccurate, LanguageAccurate, LinkPurposeMeaningful, ReadingOrderMeaningful, TableHeadersMeaningful], path : Str }

	## The report's explicit budget: its total entry count and the bytes of
	## its materialized paths and texts. A report that would exceed either
	## fails with `report.budget_exceeded` and no prepared document; no
	## entry or obligation is ever silently omitted.
	ReportBudget : { max_entries : U64, max_text_bytes : U64 }

	## Every facade failure is typed. `InvalidDocument` is a bounded diagnostic
	## batch and preparation emits no partial bytes on any error.
	Error := [
		InternalGenerationFailure,
		InvalidDocument(Conformance.DiagnosticBatch),
		InvalidFontResource(Font.ResourceError),
		InvalidFontSelection(List(Font.PlanError)),
		InvalidMetadata(Metadata.Error),
		InvalidNavigation(Document.NavigationError),
		UnsupportedAuthoringContent({ blocks : U64 }),
	]

	Options :: {
		chunk_retention : ChunkRetention,
		font_source : FontSource,
		page_size : PageSize,
		profile : Profile,
		theme : Theme,
	}.{

		## The production default selects the most complete public profile whose
		## claim set is implemented and validated: `Archive` (PDF 2.0 plus static
		## PDF/A-4). `AccessibleArchive` becomes the default only when its combined
		## claim closes; `Standard` is an explicit opt-out, never a fallback.
		default : Options
		default = Options.{
			chunk_retention: ShareUnchangedResources,
			font_source: BuiltIn,
			page_size: A4,
			profile: Archive,
			theme: Theme.default,
		}

		with_profile : Options, Profile -> Options
		with_profile = |options, profile| { ..options, profile }

		with_page_size : Options, PageSize -> Options
		with_page_size = |options, page_size| { ..options, page_size }

		with_theme : Options, Theme -> Options
		with_theme = |options, theme| { ..options, theme }

		## A registry is the complete public caller-resource boundary. It carries
		## the original immutable font bytes and the once-produced inspection
		## facts; callers still select only the returned opaque face through Theme.
		with_font_registry : Options, Font.Registry -> Options
		with_font_registry = |options, registry| { ..options, font_source: Registered(registry) }

		with_chunk_retention : Options, ChunkRetention -> Options
		with_chunk_retention = |options, chunk_retention| { ..options, chunk_retention }
	}

	## An opaque, fully validated document plan. Preparation performs all
	## authoring, layout, resource, navigation, conformance, and object-planning
	## work once; emission cannot reinterpret author intent or fail with a
	## document diagnostic after this boundary.
	Prepared :: KernelStructure.Plan.{}

	Encode :: KernelEmit.Encoder.{}
	ChunkStep : [Done, Emit(List(U8), Encode)]

	claims_for_profile : Profile -> Conformance.ClaimSet
	claims_for_profile = |profile| match profile {
		Standard => Conformance.claims_for_profile(Standard)
		Archive => Conformance.claims_for_profile(Archive)
		AccessibleArchive => Conformance.claims_for_profile(AccessibleArchive)
	}

	## Build an automatically paginated document from semantic blocks.
	document : { contents : List(Document.Block), language : Str, title : Str } -> Document
	document = |input| Document.from_blocks(input)

	## Build an explicitly framed document. The stable shape is available now;
	## preparation reports `layout.custom` until its lowering closes.
	fixed_document : { language : Str, pages : List(Document.FixedPage), title : Str } -> Document
	fixed_document = |input| Document.from_fixed_pages(input)

	## Add the document's visible title block.
	title : Str -> Document.Block
	title = |value| Document.title(value)

	## Add a semantic heading at the requested level.
	heading : U8, Str -> Document.Block
	heading = |level, value| Document.heading(level, value)

	## Add a plain paragraph.
	paragraph : Str -> Document.Block
	paragraph = |value| Document.paragraph(value)

	## Add an unordered list whose items are plain text.
	bullets : List(Str) -> Document.Block
	bullets = |items| Document.bullets(items)

	## An unordered list (`L` with `ListNumbering /Disc`). Each item is an
	## `LI` holding a generated bullet `Lbl` and an `LBody` of its blocks.
	## Items hold paragraphs, rich paragraphs, and nested lists, and begin
	## with a paragraph; lists nest at most four deep. Nested levels are
	## indented by `Theme.bullet_indent` each.
	bullet_list : List(ListItem) -> Document.Block
	bullet_list = |items| Document.bullet_list(items)

	## An ordered list whose generated labels count from `start` in `style`
	## (`Decimal`, `LowerAlpha`, `UpperAlpha`, `LowerRoman`, or
	## `UpperRoman`), each followed by a full stop: `1.`, `b.`, `iv.`. The
	## style becomes the list's `ListNumbering`. A label must fit the list
	## indent, letters and Roman numerals start at 1, and Roman numerals stop
	## at 3999.
	numbered_list : { start : U64, style : NumberStyle }, List(ListItem) -> Document.Block
	numbered_list = |numbering, items| Document.numbered_list(numbering, items)

	## One list item holding its body blocks in logical order.
	list_item : List(Document.Block) -> ListItem
	list_item = |contents| Document.list_item(contents)

	## A mandatory page break: the next block starts a new page. A break must
	## separate two flow blocks (never first, last, or doubled), and a break
	## inside a `keep_together` or after a required keep is a conflict.
	page_break : Document.Block
	page_break = Document.page_break

	## Keep blocks together on one page (a required constraint). The group
	## produces no structure element; a group taller than a page body is
	## `layout.keep_conflict`.
	keep_together : List(Document.Block) -> Document.Block
	keep_together = |contents| Document.keep_together(contents)

	## Keep a block with the first placement unit of the next block: its
	## first lines up to the orphan minimum, or all of it when unsplittable.
	## `Required` is mandatory; `Preferred` ranks after heading keeps and may
	## be relaxed.
	keep_with_next : Keep, Document.Block -> Document.Block
	keep_with_next = |keep, block| Document.keep_with_next(keep, block)

	## Layout-only vertical space after the previous block, suppressed at the
	## top of a page; it produces no structure.
	spacer : Layout.Unit -> Document.Block
	spacer = |amount| Document.spacer(amount)

	## Group blocks as a PDF 2.0 `Part`: a large division of the document,
	## such as a chapter group. Children keep their order and their own roles;
	## grouping changes no layout.
	part : List(Document.Block) -> Document.Block
	part = |contents| Document.part(contents)

	## Group blocks as a PDF 2.0 `Sect`, typically a heading and the content
	## it introduces. Headings inside keep their explicit `H1`..`H6` levels.
	section : List(Document.Block) -> Document.Block
	section = |contents| Document.section(contents)

	## Group blocks as a generic PDF 2.0 `Div` without a more specific
	## meaning, such as a letterhead or a callout.
	division : List(Document.Block) -> Document.Block
	division = |contents| Document.division(contents)

	## Own a drawing as meaningful figure content (`Figure`) with required,
	## non-empty alternative text (`/Alt`). The drawing may hold any number
	## of images and solid paths, grouped with `Scene.Drawing.group`, all at
	## or beyond its bottom-left origin; its extent is the union of its
	## commands. It is placed start-aligned in the flow at its authored size,
	## as one unsplittable unit together with its caption. A caption becomes
	## a visible `Caption` beside the `Figure` in a `Sect`, related to it by
	## `CaptionFor`, so assistive technology reads it independently of the
	## alternative text. A figure wider than the flow region, or taller with
	## its caption than a page's flow region, is `document.figure_oversize`
	## unless `figure_fit` selects `ScaleToFit`; nothing is clipped or
	## silently shrunk.
	figure : Scene.Drawing, Str, Document.Caption -> Document.Block
	figure = |drawing, alternative, caption_value| Document.figure(drawing, alternative, caption_value)

	## Select how a figure meets the flow region. `ScaleToFit({
	## minimum_percent })` scales the drawing uniformly by the largest
	## factor at most one (in thousandths) that fits the flow width and the
	## smallest page flow height together with its caption; a factor below
	## the floor is `document.figure_oversize`. Applied to any block other
	## than a figure, or with a floor above 100, it is rejected
	## (`document.figure_fit`).
	figure_fit : Document.Block, FigureFit -> Document.Block
	figure_fit = |block, fit| Document.figure_fit(block, fit)

	## An in-flow decorative drawing, such as a divider rule: a `Decoration`
	## page artifact outside the logical structure. It occupies its
	## drawing's height immediately above the next flow block and always
	## moves with that block's first line, so it is never clipped or split
	## from it. A decoration needs a following flow block, and may not
	## appear in a list item or a lead region.
	decoration : Scene.Drawing -> Document.Block
	decoration = |drawing| Document.decoration(drawing)

	## A custom block, as a separately authored extension measured it (see
	## `CustomBlock`).
	custom_block : CustomBlock -> Document.Block
	custom_block = |{ contents, fragmentation, inset, name, panel, size }| {
		match fragmentation {
			Unsplittable => {}
		}
		Document.custom_block({ contents, inset, name, panel, size })
	}

	## Add an optional visible caption to a figure.
	caption : Str -> Document.Caption
	caption = |value| Document.caption(value)

	## Explicitly omit a visible figure caption; alternative text is still required.
	no_caption : Document.Caption
	no_caption = NoCaption

	## Start a fixed page with explicit semantic frames and classified artifacts.
	fixed_page : Layout.Size -> Document.FixedPageBuilder
	fixed_page = |size| Document.fixed_page(size)

	## A paragraph (`P`) of inline content in logical order. Its text wraps as
	## one paragraph: lines break at Unicode line-break opportunities across
	## inline boundaries, and every inline keeps its own structure element.
	## A rich paragraph must contain text; empty inlines, links inside links,
	## inline nesting deeper than 8 elements, malformed language tags, and
	## malformed URIs reject with stable `semantics.*` codes and the inline's
	## path, such as `contents[2].inlines[1].inlines[0]`.
	rich_paragraph : List(Inline) -> Document.Block
	rich_paragraph = |inlines| Document.rich_paragraph(inlines)

	## Plain inline text in the surrounding language and role.
	text : Str -> Inline
	text = |value| Document.plain_text(value)

	## Stressed emphasis, an `Em` structure element.
	emphasis : List(Inline) -> Inline
	emphasis = |contents| Document.emphasis(contents)

	## Strong importance, a `Strong` structure element.
	strong : List(Inline) -> Inline
	strong = |contents| Document.strong(contents)

	## A fragment of computer code, a `Code` structure element.
	code : Str -> Inline
	code = |value| Document.code(value)

	## An inline quotation, a `Quote` structure element. Quotation marks are
	## authored text; none are generated.
	quote : List(Inline) -> Inline
	quote = |contents| Document.quote(contents)

	## A URI link around inline content: a `Link` element with one link
	## annotation per page whose quadrilaterals are its painted line boxes.
	inline_link : List(Inline), Str -> Inline
	inline_link = |contents, uri| Document.inline_link(contents, uri)

	## An internal link around inline content to an authored destination name.
	inline_internal_link : List(Inline), Str -> Inline
	inline_internal_link = |contents, destination| Document.inline_internal_link(contents, destination)

	## Inline content in another natural language: a `Span` with `/Lang`,
	## such as `Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")])`.
	in_language : Str, List(Inline) -> Inline
	in_language = |tag, contents| Document.in_language(tag, contents)

	## An abbreviation with its expansion: a `Span` whose `/E` is the
	## expansion, such as `Pdf.expansion("GST", "Goods and Services Tax")`.
	expansion : Str, Str -> Inline
	expansion = |value, expanded| Document.expansion(value, expanded)

	## A mandatory line break inside a rich paragraph. It paints nothing and
	## must separate text: a break at either end of the paragraph or directly
	## after another break is `semantics.line_break_position`.
	line_break : Inline
	line_break = Document.line_break

	## An ordinary table: a `Table` element with an optional `Caption`, one
	## `THead`, `TBody`, and `TFoot` for its header, body, and footer rows,
	## `TR` rows, and `TH`/`TD` cells. Every cell has a generated element
	## identifier; a header cell declares its `Scope`, and a data cell's
	## `Headers` name the column header cells above it in its columns and
	## the row header cells of its row, derived from the declared scopes.
	##
	## Column widths resolve once per table (fixed, then content, then
	## shares). Cells wrap within their columns; header rows repeat at the
	## top of every continuation page as a pagination artifact, never as new
	## rows; footer rows stay together after the last body row and prefer to
	## carry at least one body row. `KeepRows` moves a row that does not fit
	## to the next page and rejects a row taller than a page body as
	## `layout.oversize_row`; `SplitRows` breaks a row at a line boundary.
	## Each row's column spans must sum to the column count
	## (`table.grid_mismatch`), a table needs a header cell
	## (`table.header_missing`), and row spans are not yet supported
	## (`table.row_span`).
	table : { body_rows : List(Row), caption : Document.Caption, columns : List(Column), footer_rows : List(Row), header_rows : List(Row), row_split : RowSplit } -> Document.Block
	table = |spec| Document.table(spec)

	## One table row: its cells in logical order.
	row : List(Cell) -> Row
	row = |cells| Document.row(cells)

	## A data cell (`TD`) whose inline content forms one paragraph.
	cell : List(Inline) -> Cell
	cell = |contents| Document.cell(contents)

	## A header cell (`TH`) with its declared scope.
	header_cell : Scope, List(Inline) -> Cell
	header_cell = |scope, contents| Document.header_cell(scope, contents)

	## A cell spanning `count` columns (`ColSpan`).
	spanning : U16, Cell -> Cell
	spanning = |count, value| Document.spanning(count, value)

	## A cell whose lines align at `align` instead of in the alignment of
	## the first column it spans, such as an end-aligned label spanning a
	## table's start-aligned columns.
	aligned : Align, Cell -> Cell
	aligned = |align, value| Document.aligned(align, value)

	## A cell spanning `count` rows. Row spans are outside the supported
	## table subset: preparation reports `table.row_span` until Gate 8.
	row_spanning : U16, Cell -> Cell
	row_spanning = |count, value| Document.row_spanning(count, value)

	## Gate 6-8 authoring shapes are stable before their lowering is enabled.
	## These constructors retain the authored intent and reject transactionally
	## at preparation with a feature-specific explanation.

	## Reserve a spanning/header-associated table; currently reports `table.complex`.
	complex_table : Str -> Document.Block
	complex_table = |summary| Document.unavailable(ComplexTables, summary)

	## Reserve footnote content; currently reports `document.footnote`.
	footnote : Str -> Document.Block
	footnote = |value| Document.unavailable(Footnotes, value)

	## Reserve sidebar content; currently reports `document.side_content`.
	side_content : Str -> Document.Block
	side_content = |value| Document.unavailable(SideContent, value)

	## Reserve a generated cross-reference; currently reports `document.generated_reference`.
	generated_reference : Str -> Document.Block
	generated_reference = |name| Document.unavailable(GeneratedReferences, name)

	## Reserve a multi-column region; currently reports `layout.multi_column`.
	multi_column : Str -> Document.Block
	multi_column = |summary| Document.unavailable(MultiColumnLayout, summary)

	## Reserve custom layout intent; currently reports `layout.custom`.
	custom_layout : Str -> Document.Block
	custom_layout = |summary| Document.unavailable(CustomLayout, summary)

	## A URI link block; the whole text is the link.
	link : Str, Str -> Document.Block
	link = |value, uri| Document.link(value, uri)

	## An internal link block referencing an authored destination name.
	internal_link : Str, Str -> Document.Block
	internal_link = |value, destination| Document.internal_link(value, destination)

	## A heading that also declares a named destination.
	destination_heading : Str, U8, Str -> Document.Block
	destination_heading = |name, level, value| Document.destination_heading(name, level, value)

	destination_paragraph : Str, Str -> Document.Block
	destination_paragraph = |name, value| Document.destination_paragraph(name, value)

	## The authored document outline in dense preorder over authored
	## destination names.
	with_outline : Document, List(Document.OutlineEntry) -> Document
	with_outline = |doc, entries| Document.with_outline(doc, entries)

	## First-page and continuation-page templates. Each template reserves a
	## header and a footer region of fixed height inside the theme's body
	## frame, each separated from the body flow by the template's gap; the
	## first page may also reserve a lead region below its header. Body flow
	## is confined to what remains, so the first page and continuation pages
	## may hold different body heights. Region furniture paints on every
	## page of its template as a page artifact (`Header`, `Footer`, or
	## `PageNum` when a line holds a page field) and never joins the logical
	## structure; the lead region's blocks are semantic (a `Div`) and come
	## first in reading order.
	##
	## Page fields resolve after pagination by explicit reference states:
	## the first pass paginates the body, the second resolves every field
	## with the final page count and proves it fits. Regions have fixed
	## heights, so furniture never changes pagination and two passes always
	## suffice. Template regions that leave less than one body line are
	## `layout.template_body_space`; furniture or lead content that exceeds
	## its region, or slots that overlap, are
	## `layout.template_region_overflow`; a resolved field wider than its
	## reserved width is `layout.field_overflow`.
	with_page_templates : Document, { continuation : PageTemplate, first : FirstPageTemplate } -> Document
	with_page_templates = |doc, templates| Document.with_page_templates(doc, templates)

	## The first page's template. `lead` is a lead region of semantic blocks
	## (such as a letterhead) or `no_lead`.
	first_page_template : { footer : Region, gap : Layout.Unit, header : Region, lead : LeadRegion } -> FirstPageTemplate
	first_page_template = |record| Document.first_page_template(record)

	## The template of every page after the first.
	page_template : { footer : Region, gap : Layout.Unit, header : Region } -> PageTemplate
	page_template = |record| Document.page_template(record)

	## A header or footer region of positive `height`. Its `start`, `center`,
	## and `end` slots each hold a vertical stack of furniture: a header's
	## stacks sit on its bottom edge and a footer's hang from its top edge,
	## beside the body flow. Start items align to the frame's start edge,
	## end items to its end edge, and center items are centered.
	region : { center : List(Furniture), end : List(Furniture), height : Layout.Unit, start : List(Furniture) } -> Region
	region = |record| Document.region(record)

	## A template without this region; it reserves no height and no gap.
	no_region : Region
	no_region = Document.no_region

	## A lead region of `height` holding semantic blocks laid out once, as
	## one unsplittable unit, below the first page's header. Its content
	## becomes a `Div` before the body in reading order.
	lead_region : Layout.Unit, List(Document.Block) -> LeadRegion
	lead_region = |height, contents| Document.lead_region(height, contents)

	## A first page without a lead region.
	no_lead : LeadRegion
	no_lead = Document.no_lead

	## One line of furniture text: plain text, page fields, and reserved
	## widths, in the theme's body style. It is never wrapped, clipped, or
	## shrunk.
	furniture_text : List(Inline) -> Furniture
	furniture_text = |contents| Document.furniture_text(contents)

	## A decorative drawing painted as page furniture: image commands and
	## solid paths in drawing-local coordinates (origin at the item's
	## bottom-left, y upward), whose extent is the item's size.
	furniture_image : Scene.Drawing -> Furniture
	furniture_image = |drawing| Document.furniture_image(drawing)

	## The physical page number (1-based) in a number style. Page fields are
	## page furniture only; in body content they report
	## `document.generated_reference`.
	page_number : NumberStyle -> Inline
	page_number = |style| Document.page_number(style)

	## The physical page count in a number style (furniture only).
	total_pages : NumberStyle -> Inline
	total_pages = |style| Document.total_pages(style)

	## Furniture content laid out in an exact width and aligned inside it,
	## such as `Page N of M` in 64 pt. Each page's resolved content must fit
	## the width, or preparation reports `layout.field_overflow`.
	reserved_width : Layout.Unit, Align, List(Inline) -> Inline
	reserved_width = |width, align, contents| Document.reserved_width(width, align, contents)

	## Authored page-label ranges keyed by physical page index.
	with_page_labels : Document, List(Document.PageLabelRange) -> Document
	with_page_labels = |doc, ranges| Document.with_page_labels(doc, ranges)

	## Optional explicit metadata timestamps in the canonical UTC form
	## `YYYY-MM-DDThh:mm:ssZ`. The package never invents a timestamp: omitted
	## values deterministically omit their XMP properties.
	with_created : Document, Str -> Document
	with_created = |doc, timestamp| Document.with_created(doc, timestamp)

	with_modified : Document, Str -> Document
	with_modified = |doc, timestamp| Document.with_modified(doc, timestamp)

	## The default profile is `Archive`: content follows the completed typed
	## facade pipeline and passes static PDF/A-4 profile and lowered-plan
	## validation before any byte exists. `Standard` is an explicit opt-out.
	## AccessibleArchive remains unavailable until its combined capability
	## closes; a document that cannot meet the requested claim is an error.
	to_bytes : Document -> Try(List(U8), Error)
	to_bytes = |doc| to_bytes_with(doc, Options.default)

	to_bytes_with : Document, Options -> Try(List(U8), Error)
	to_bytes_with = |doc, options| {
		prepared = prepare(doc, options)?
		to_bytes_prepared(prepared)
	}

	## Validate and lower an authored document once for repeated or deferred
	## emission. The returned value contains no authoring callbacks or mutable
	## caches and exposes no PDF object internals.
	prepare : Document, Options -> Try(Prepared, Error)
	prepare = |doc, options| {
		match Document.first_unavailable(doc) {
			Available => {}
			UnavailableFeature({ feature, summary }) => return Err(InvalidDocument(unavailable_batch(feature, summary)))
		}
		plan = build_plan(doc, options)?
		Ok(Prepared.(plan))
	}

	## Prepare a document exactly as `prepare` does and return the bounded
	## read-only preparation report beside it (see `Report`), under the
	## default report budget of 65,536 entries and 4 MiB of text. The
	## prepared document, and so its bytes, is identical to `prepare`'s.
	prepare_with_report : Document, Options -> Try({ prepared : Prepared, report : Report }, Error)
	prepare_with_report = |doc, options| prepare_with_report_budget(doc, options, default_report_budget)

	## `prepare_with_report` under an explicit report budget.
	prepare_with_report_budget : Document, Options, ReportBudget -> Try({ prepared : Prepared, report : Report }, Error)
	prepare_with_report_budget = |doc, options, budget| {
		match Document.first_unavailable(doc) {
			Available => {}
			UnavailableFeature({ feature, summary }) => return Err(InvalidDocument(unavailable_batch(feature, summary)))
		}
		{ facts, normalized, plan } = build_reporting_plan(doc, options)?
		report = build_report(normalized, facts, budget)?
		Ok({ prepared: Prepared.(plan), report })
	}

	to_bytes_prepared : Prepared -> Try(List(U8), Error)
	to_bytes_prepared = |Prepared.(plan)| {
		bytes = KernelEmit.to_bytes(plan) ? |_| InternalGenerationFailure
		Ok(bytes)
	}

	to_chunks : Document -> Try(Encode, Error)
	to_chunks = |doc| to_chunks_with(doc, Options.default)

	## Chunked delivery drives the same emission transition as `to_bytes_with`
	## over the same sealed plan, so the concatenated chunks are byte-identical
	## to the buffered output by construction. Every document error occurs
	## while building that plan, before sealing: a rejected document yields a
	## typed error and no partial chunk sequence.
	to_chunks_with : Document, Options -> Try(Encode, Error)
	to_chunks_with = |doc, options| {
		prepared = prepare(doc, options)?
		to_chunks_prepared(prepared, options.chunk_retention)
	}

	## Start chunked emission from an already prepared document. Retention is
	## selected at emission time and cannot alter the sealed document bytes.
	to_chunks_prepared : Prepared, ChunkRetention -> Try(Encode, Error)
	to_chunks_prepared = |Prepared.(plan), chunk_retention| {
		retention = match chunk_retention {
			OwnChunks => OwnResourceChunks
			ShareUnchangedResources => ShareResourceChunks
		}
		encoder = KernelEmit.start(plan, retention) ? |_| InternalGenerationFailure
		Ok(Encode.(encoder))
	}

	next_chunk : Encode -> ChunkStep
	next_chunk = |Encode.(encoder)| match KernelEmit.Encoder.next_infallible(encoder) {
		Done => Done
		Emit(segment, next) => Emit(segment.bytes, Encode.(next))
	}
}

build_plan : Document, Pdf.Options -> Try(KernelStructure.Plan, Pdf.Error)
build_plan = |doc, options| {
	claim = validate_profile_request(options)?

	## The authored metadata facts validate once and the canonical XMP packet
	## serializes once, identified exactly when the requested profile claims
	## static PDF/A-4; every later stage consumes the same validated values.
	validated = KernelMetadata.validate(
		{
			created: Document.created(doc),
			language: Document.language(doc),
			modified: Document.modified(doc),
			title: Document.metadata_title(doc),
		},
		standard_metadata_limits,
	) ? InvalidMetadata
	xmp = KernelXmp.Packet.build_identified(validated.facts, KernelPdfA4.identification(claim), standard_xmp_bytes) ? |_| InternalGenerationFailure
	if Document.block_count(doc) == 0 and Document.has_templates(doc) {
		return Err(furniture_error(BodyEmpty))
	}
	if Document.block_count(doc) == 0 {
		plan = KernelStructure.build_blank_with_facts(
			1,
			structure_page_size(options.page_size),
			{
				condition_identifier: KernelMetadata.srgb_condition_identifier,
				language: validated.facts.language,
				profile_bytes: KernelSrgbProfile.bytes,
				profile_components: 3,
				registry_name: KernelMetadata.icc_registry_name,
				xmp: KernelXmp.Packet.bytes(xmp),
			},
		) ? |_| InternalGenerationFailure
		validate_lowered_plan(claim, xmp, plan)?
		return Ok(plan)
	}
	facts = WithDocumentFacts({
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		profile: Color.ProfileId.from_index(0),
		registry_name: KernelMetadata.icc_registry_name,
		language: validated.facts.language,
		xmp: KernelXmp.Packet.bytes(xmp),
	})
	pipeline = match selected_fonts(options)? {
		Single(font) => KernelFacadePipeline.Plan.build_with_facts(
			Document.normalize(doc),
			font,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| pipeline_error(error, doc)
		Styled(styled) => KernelFacadePipeline.Plan.build_styled_with_facts(
			Document.normalize(doc),
			styled,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| pipeline_error(error, doc)
		Ordered(ordered) => KernelFacadePipeline.Plan.build_ordered_with_facts(
			Document.normalize(doc),
			ordered,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| ordered_pipeline_error(error, ordered.policy, doc)
	}
	output = KernelFacadePipeline.Plan.output(pipeline)
	_text_work = KernelPdfA4.validate_text(claim, KernelFacadeOutput.Plan.text_facts(output)) ? |violation| InvalidDocument(profile_batch(violation, ProfileValidation))
	plan = KernelFacadeOutput.Plan.structure(output)
	validate_lowered_plan(claim, xmp, plan)?
	Ok(plan)
}

## `build_plan` with the preparation report's facts collected by the
## `*_reporting` pipeline builders, which produce the identical prepared
## plan. The document is normalized once and the normalized authoring is
## returned for the report's path materialization.
build_reporting_plan : Document, Pdf.Options -> Try({ facts : [Facts(KernelFacadeReport.Facts), NoFacts], normalized : Document.NormalizedAuthoring, plan : KernelStructure.Plan }, Pdf.Error)
build_reporting_plan = |doc, options| {
	normalized = Document.normalize(doc)
	claim = validate_profile_request(options)?

	## The authored metadata facts validate once and the canonical XMP packet
	## serializes once, identified exactly when the requested profile claims
	## static PDF/A-4; every later stage consumes the same validated values.
	validated = KernelMetadata.validate(
		{
			created: Document.created(doc),
			language: Document.language(doc),
			modified: Document.modified(doc),
			title: Document.metadata_title(doc),
		},
		standard_metadata_limits,
	) ? InvalidMetadata
	xmp = KernelXmp.Packet.build_identified(validated.facts, KernelPdfA4.identification(claim), standard_xmp_bytes) ? |_| InternalGenerationFailure
	if Document.block_count(doc) == 0 and Document.has_templates(doc) {
		return Err(furniture_error(BodyEmpty))
	}
	if Document.block_count(doc) == 0 {
		plan = KernelStructure.build_blank_with_facts(
			1,
			structure_page_size(options.page_size),
			{
				condition_identifier: KernelMetadata.srgb_condition_identifier,
				language: validated.facts.language,
				profile_bytes: KernelSrgbProfile.bytes,
				profile_components: 3,
				registry_name: KernelMetadata.icc_registry_name,
				xmp: KernelXmp.Packet.bytes(xmp),
			},
		) ? |_| InternalGenerationFailure
		validate_lowered_plan(claim, xmp, plan)?
		return Ok({ facts: NoFacts, normalized, plan })
	}
	facts = WithDocumentFacts({
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		profile: Color.ProfileId.from_index(0),
		registry_name: KernelMetadata.icc_registry_name,
		language: validated.facts.language,
		xmp: KernelXmp.Packet.bytes(xmp),
	})
	pipeline = match selected_fonts(options)? {
		Single(font) => KernelFacadePipeline.Plan.build_reporting(
			normalized,
			font,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| pipeline_error(error, doc)
		Styled(styled) => KernelFacadePipeline.Plan.build_styled_reporting(
			normalized,
			styled,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| pipeline_error(error, doc)
		Ordered(ordered) => KernelFacadePipeline.Plan.build_ordered_reporting(
			normalized,
			ordered,
			options.theme,
			layout_page_size(options.page_size),
			standard_font_descriptor,
			facts,
			standard_pipeline_limits,
		) ? |error| ordered_pipeline_error(error, ordered.policy, doc)
	}
	output = KernelFacadePipeline.Plan.output(pipeline)
	_text_work = KernelPdfA4.validate_text(claim, KernelFacadeOutput.Plan.text_facts(output)) ? |violation| InvalidDocument(profile_batch(violation, ProfileValidation))
	plan = KernelFacadeOutput.Plan.structure(output)
	validate_lowered_plan(claim, xmp, plan)?
	Ok({ facts: KernelFacadePipeline.Plan.facts(pipeline), normalized, plan })
}

## Lowered-plan validation runs on every prepared plan before it is wrapped:
## an unclaimed plan checks only that its packet declares no identification,
## and a claimed plan is checked against the full static whitelist.
validate_lowered_plan : KernelPdfA4.Claim, KernelXmp.Packet, KernelStructure.Plan -> Try({}, Pdf.Error)
validate_lowered_plan = |claim, packet, plan| {
	_work = KernelPdfA4.validate_lowered(
		claim,
		{ packet, root: KernelStructure.Plan.root(plan), sealed: KernelStructure.Plan.sealed(plan) },
	) ? |violation| InvalidDocument(profile_batch(violation, LoweredPlanValidation))
	Ok({})
}

profile_batch : KernelPdfA4.Violation, Conformance.ValidationStage -> Conformance.DiagnosticBatch
profile_batch = |violation, stage| {
	requirement = violation.requirement
	message = "The Archive profile requires that ${KernelPdfA4.summary(requirement)} (${KernelPdfA4.clause(requirement)}). No PDF bytes were emitted; this is not a downgrade to Standard."
	{
		detail_bytes: Str.to_utf8(message).len(),
		diagnostics: [
			{
				clause_references: [KernelPdfA4.clause(requirement)],
				code: ProfileRequirementViolated,
				details: [],
				feature: Feature(feature_code(ArchiveProfile)),
				location: Document,
				message,
				requirement_ids: [KernelPdfA4.requirement_code(requirement)],
				stage,
			},
		],
		truncation: Complete,
	}
}

## The Theme decides between exact style faces and an ordered policy. Policy
## selection requires the caller registry that constructed the policy; the
## packaged built-in face defines no policies, so that combination is a
## stable typed error rather than an implicit single-face fallback.
selected_fonts : Pdf.Options -> Try(KernelFacadeShape.FontSelection, Pdf.Error)
selected_fonts = |options| match Theme.font_selection(options.theme) {
	StyleFaces => if !has_role_face(options.theme) Ok(Single(selected_font(options)?)) else selected_styled_fonts(options)
	Policy(policy) => if has_role_face(options.theme) Err(InvalidDocument(located_batch(FeatureUnavailable, "text.inline_font_policy", "An inline role face applies to style faces only; under an ordered font policy every cluster takes the first policy face that covers it. Remove Theme.with_inline_font or use style faces.", []))) else match options.font_source {
		BuiltIn => Err(InvalidFontSelection([InvalidPolicy(policy)]))
		Registered(registry) => {
			_faces = registry.policy_faces(policy) ? |_| InvalidFontSelection([InvalidPolicy(policy)])
			Ok(Ordered({ policy, registry }))
		}
	}
}

## Ordered-selection failures surface the exact planner rejections; script
## boundaries of the convenience path map to the planner's typed
## unsupported-shaping fact. Everything else keeps the authored-content error.
ordered_pipeline_error : KernelFacadePipeline.Error, Font.PolicyId, Document -> Pdf.Error
ordered_pipeline_error = |error, policy, doc| match error {
	Shape(FontSelectionRejected(errors)) => InvalidFontSelection(errors)
	Shape(PolicyInvalid(_)) => InvalidFontSelection([InvalidPolicy(policy)])
	Shape(UndeclaredScript({ script, source })) => InvalidFontSelection([UnsupportedBuiltInShaping({ cluster: source, script: Font.Script.from_iso15924(script) })])
	_ => pipeline_error(error, doc)
}

## Author-facing navigation rejections surface with their exact typed cause;
## every other pipeline failure keeps the authored-content error.
## Container rejections name the container's authored block path. The
## normalized arena is rebuilt only on that rejection path, so the success
## path still hands its single normalized value to the pipeline uniquely.
pipeline_error : KernelFacadePipeline.Error, Document -> Pdf.Error
pipeline_error = |error, doc| match error {
	Fragments(Navigation(navigation)) => InvalidNavigation(navigation)
	Output(Structure(Navigation(navigation))) => InvalidNavigation(navigation)
	Semantics(ContainerDepthExceeded({ attempted, group, limit })) => InvalidDocument(
		container_batch(
			BudgetExceeded,
			"semantics.container_depth",
			"A container is nested ${attempted.to_str()} levels deep; the facade accepts at most ${limit.to_str()} nested part, section, and division levels.",
			group_path(Document.normalize(doc).groups, group),
		),
	)
	Semantics(EmptyContainer({ group })) => InvalidDocument(
		container_batch(
			InvalidRelationship,
			"semantics.empty_container",
			"A part, section, or division contains no semantic block; it would become an empty grouping element.",
			group_path(Document.normalize(doc).groups, group),
		),
	)
	Semantics(HeadingSkip({ block, previous })) => located_error(doc, InvalidRelationship, "semantics.heading_skip", "A heading is more than one level deeper than the heading before it; heading levels must not skip a level.", [leaf_path(doc, previous), leaf_path(doc, block)])
	Semantics(FigureAlternativeEmpty({ block })) => located_error(doc, InvalidRelationship, "document.figure_alternative_empty", "A figure's alternative text is empty; every figure needs alternative text that conveys what it communicates.", [leaf_path(doc, block)])
	Semantics(FigureCaptionEmpty({ block })) => located_error(doc, InvalidRelationship, "document.figure_caption_empty", "A figure caption is empty; use no_caption for a figure without a visible caption.", [leaf_path(doc, block)])
	Semantics(FigureDrawing({ block, reason })) => located_error(doc, InvalidRelationship, "document.figure_drawing", "A figure's drawing is not a supported flow drawing: ${reason}.", [leaf_path(doc, block)])
	Semantics(FigureFitInvalid({ block })) => located_error(doc, InvalidRelationship, "document.figure_fit", "A ScaleToFit floor is above 100 percent; a figure is never enlarged.", [leaf_path(doc, block)])
	Semantics(DecorationDrawing({ decoration, reason })) => flow_item_error(doc, DecorationItem(decoration), InvalidRelationship, "layout.decoration_drawing", "A decoration's drawing is not a supported flow drawing: ${reason}.")
	Semantics(DecorationPosition({ decoration })) => flow_item_error(doc, DecorationItem(decoration), LayoutConstraintViolated, "layout.decoration_position", "A decoration is placed above the next flow block and moves with it, so it needs a following flow block and cannot appear in a lead region.")
	Semantics(ListItemDecoration({ decoration })) => flow_item_error(doc, DecorationItem(decoration), InvalidRelationship, "semantics.list_item_content", "A decoration cannot appear inside a list item.")
	Pages(FigureOversize({ block, frame_height, frame_width, height, width })) => located_error(doc, LayoutConstraintViolated, "document.figure_oversize", "A figure's drawing is ${points_text(width)} wide and ${points_text(height)} tall, but the flow region is ${points_text(frame_width)} wide and ${points_text(frame_height)} tall for the figure with its caption and any decoration above it; a figure is never clipped or shrunk unless figure_fit selects ScaleToFit.", [leaf_path(doc, block)])
	Pages(FigureScaleFloor({ block, floor, scale })) => located_error(doc, LayoutConstraintViolated, "document.figure_oversize", "A figure fits the flow region only at ${percent_text(scale)} of its size, below its ScaleToFit floor of ${floor.to_str()}%.", [leaf_path(doc, block)])
	Semantics(CustomContent({ child, custom })) => custom_content_error(doc, custom, child)
	Semantics(CustomDrawing({ custom, reason })) => custom_error(doc, custom, InvalidRelationship, "layout.custom_block_drawing", "A custom block's panel is not a supported panel drawing: ${reason}.")
	Semantics(CustomName({ custom })) => custom_error(doc, custom, InvalidRelationship, "semantics.custom_block_name", "A custom block's name is empty; the name identifies the block in diagnostics and the preparation report.")
	Semantics(CustomMeasure({ custom })) => custom_error(doc, custom, LayoutConstraintViolated, "layout.custom_block_measure", "A custom block's measured width and height must be positive and its inset positive and less than half of each, so its content has a box to fill.")
	Lines(CustomWidth({ available, custom, width })) => custom_error(doc, custom, LayoutConstraintViolated, "layout.oversize_block", "A custom block is measured ${points_text(width)} wide, but the flow region gives it ${points_text(available)}; a custom block is never clipped or shrunk.")
	Pages(CustomOversize({ custom, frame_height, height })) => custom_error(doc, custom, LayoutConstraintViolated, "layout.oversize_block", "A custom block is unsplittable and needs ${points_text(height)}, but a page flow region holds at most ${points_text(frame_height)}; it is never split, clipped, or shrunk.")
	Pages(CustomMeasureShort({ available, content, custom })) => custom_error(doc, custom, LayoutConstraintViolated, "layout.custom_block_measure", "A custom block's content needs ${points_text(content)}, but its measured height less twice its inset leaves ${points_text(available)}; the extension must measure the block at least that tall.")
	Pages(DecorationOversize({ decoration, frame_height, frame_width, height, width })) => flow_item_error(doc, DecorationItem(decoration), LayoutConstraintViolated, "layout.oversize_block", "A decoration is ${points_text(width)} wide and ${points_text(height)} tall, but the flow region is ${points_text(frame_width)} wide and at most ${points_text(frame_height)} tall; a decoration is never clipped or shrunk.")
	Semantics(EmptyRichParagraph({ block })) => inline_error(doc, block, NoInline, InvalidRelationship, "semantics.inline_empty", "A rich paragraph contains no text.")
	Semantics(TableCellEmpty({ block })) => located_error(doc, InvalidRelationship, "table.cell_empty", "A table cell contains no text.", [leaf_path(doc, block)])
	Semantics(TableEmpty({ group })) => group_error(doc, group, InvalidRelationship, "table.empty", "A table needs at least one column and one body row.")
	Semantics(TableGridMismatch({ columns, group, spanned })) => group_error(doc, group, InvalidRelationship, "table.grid_mismatch", "A table row spans ${spanned.to_str()} columns but the table declares ${columns.to_str()}; every row's column spans must sum to the column count and each span must be at least one.")
	Semantics(TableHeaderMissing({ group })) => group_error(doc, group, InvalidRelationship, "table.header_missing", "A table declares no header cell; at least one cell must be a header_cell with a declared scope.")
	Semantics(TableRowSpan({ block })) => located_error(doc, FeatureUnavailable, "table.row_span", "A table cell spans rows; row spans are scheduled for Gate 8 and only column spans are supported.", [leaf_path(doc, block)])
	Semantics(BlockLimitExceeded({ attempted, block, dimension, limit })) => located_error(doc, BudgetExceeded, "document.content_limit", "The document needs ${attempted.to_str()} ${dimension_name(dimension)} but the facade accepts at most ${limit.to_str()}.", if block < Document.normalize(doc).blocks.len() [member_path(doc, Document.normalize(doc), block)] else [])
	Lines(Tables(TableWidth({ available, group, required }))) => group_error(doc, group, LayoutConstraintViolated, "layout.table_width", "A table's fixed column widths and column minimums need ${points_text(required)} but the table has ${points_text(available)}; content is never shrunk or clipped.")
	Lines(Tables(UnbreakableToken({ available, block, token, width }))) => located_error(doc, LayoutConstraintViolated, "layout.unbreakable_token", "A table cell holds text with no break opportunity (scalars ${token.start().to_str()} to ${(token.start() + token.length()).to_str()}) that is ${points_text(width)} wide, but its column gives it at most ${points_text(available)}; there is no emergency breaking.", [leaf_path(doc, block)])
	Pages(TableLayout({ error: LeadOverflow({ available, required }), groups: _, units: _ })) => lead_overflow_error(available, required)
	Pages(TableLayout({ error: layout_error, groups: sources, units })) => table_layout_error(doc, layout_error, sources, units)
	Pages(TableRuleWidth({ gap, width })) => located_error(doc, LayoutConstraintViolated, "layout.table_rule", "The theme's table rule is ${points_text(width)} wide but the row gap it is drawn in is ${points_text(gap)}.", [])
	Semantics(EmptyInline({ block, inline })) => inline_error(doc, block, AtInline(inline), InvalidRelationship, "semantics.inline_empty", "An inline is empty: inline text, code, and expansions need text, and every inline element must contain text.")
	Semantics(EmptyLinkText({ block, inline })) => inline_error(doc, block, AtInline(inline), InvalidRelationship, "semantics.link_text_empty", "A link has no text content to announce as its purpose.")
	Semantics(NestedLink({ block, inline })) => inline_error(doc, block, AtInline(inline), InvalidRelationship, "semantics.nested_link", "A link contains another link.")
	Semantics(InlineDepthExceeded({ attempted, block, inline, limit })) => inline_error(doc, block, AtInline(inline), BudgetExceeded, "semantics.inline_depth", "An inline element is nested ${attempted.to_str()} levels deep; rich paragraphs accept at most ${limit.to_str()} nested inline elements.")
	Semantics(InvalidInlineLanguage({ block, inline })) => inline_error(doc, block, AtInline(inline), InvalidLanguage, "semantics.language_tag", "An in_language tag is not a well-formed BCP 47 language tag.")
	Semantics(InvalidInlineUri({ block, error: uri_error, inline })) => inline_error(doc, block, AtInline(inline), InvalidRelationship, "semantics.link_uri", "An inline link URI is not a valid absolute URI (${uri_problem(uri_error)}).")
	Shape(UnsupportedInlineScript({ block, inline, script })) => inline_error(doc, block, AtInline(inline), FontCoverageMissing, "text.unsupported_script", "Inline text uses the script ${script}, which the convenience text path does not shape.")
	Shape(InlineClusterBoundary({ block, inline })) => inline_error(doc, block, AtInline(inline), FontCoverageMissing, "text.unsupported_cluster", "An inline boundary falls inside a multi-scalar grapheme cluster, which the convenience shaper does not support.")
	Semantics(LineBreakPosition({ block, line_break })) => line_break_error(doc, block, line_break)
	Semantics(EmptyKeep({ group })) => group_error(doc, group, LayoutConstraintViolated, "layout.keep_empty", "A keep contains no laid-out block.")
	Semantics(EmptyList({ group })) => group_error(doc, group, InvalidRelationship, "semantics.list_empty", "A list has no items.")
	Semantics(EmptyListItem({ group })) => group_error(doc, group, InvalidRelationship, "semantics.list_item_empty", "A list item has no blocks.")
	Semantics(ListDepthExceeded({ attempted, group, limit })) => group_error(doc, group, BudgetExceeded, "semantics.list_depth", "A list is nested ${attempted.to_str()} levels deep; the facade accepts at most ${limit.to_str()} nested lists.")
	Semantics(ListItemStart({ group })) => group_error(doc, group, InvalidRelationship, "semantics.list_item_content", "A list item must begin with a paragraph or rich paragraph, which its label paints beside.")
	Semantics(ListItemGroup({ group })) => group_error(doc, group, InvalidRelationship, "semantics.list_item_content", "A list item holds only paragraphs, rich paragraphs, and nested lists.")
	Semantics(ListItemBlock({ block })) => located_error(doc, InvalidRelationship, "semantics.list_item_content", "A list item holds only paragraphs, rich paragraphs, and nested lists.", [leaf_path(doc, block)])
	Semantics(ListItemBreak({ page_break })) => flow_item_error(doc, PageBreakItem(page_break), InvalidRelationship, "semantics.list_item_content", "A page break cannot appear inside a list item.")
	Semantics(ListItemSpacer({ spacer })) => flow_item_error(doc, SpacerItem(spacer), InvalidRelationship, "semantics.list_item_content", "A spacer cannot appear inside a list item.")
	Semantics(NegativeSpacer({ spacer })) => flow_item_error(doc, SpacerItem(spacer), LayoutConstraintViolated, "layout.spacer_negative", "A spacer has a negative height; spacing never overlaps content.")
	Semantics(ListNumbering({ group })) => group_error(doc, group, InvalidRelationship, "semantics.list_numbering", "A generated list number cannot be written in its style: letters and Roman numerals start at 1, and Roman numerals stop at 3999.")
	Shape(UnsupportedText({ block, inline, reason, scalars })) => unsupported_text_error(doc, block, inline, reason, scalars)
	Lines(LabelTooWide({ available, block, width })) => label_width_error(doc, block, width, available)
	Pages(PageBreakPosition({ page_break })) => flow_item_error(doc, PageBreakItem(page_break), LayoutConstraintViolated, "layout.page_break_position", "A page break must separate two flow blocks; a break first, last, or directly after another would produce an empty page.")
	Pages(PageLayout(KeepConflict(conflict))) => keep_conflict_error(doc, conflict)
	Pages(PageLayout(Oversize({ available, block, required }))) => oversize_error(doc, block, required, available)
	Pages(PageLayout(LimitExceeded({ attempted, dimension: Pages, limit }))) => located_error(doc, BudgetExceeded, "document.content_limit", "The document needs ${attempted.to_str()} pages but the facade accepts at most ${limit.to_str()}.", [])
	Pages(PageLayout(LeadOverflow({ available, required }))) => lead_overflow_error(available, required)
	Semantics(FurnitureInline({ block, inline })) => inline_error(doc, block, AtInline(inline), FeatureUnavailable, "document.generated_reference", "Page fields and reserved widths are page furniture only: they may appear in a template region's furniture text, never in body content. Generated references in the body are scheduled for Gate 8.")
	Furniture(furniture) => furniture_error(furniture)
	ReferenceCycle({ first_seen_pass, repeated_at_pass }) => located_error(doc, LayoutCycle, "layout.reference_cycle", "Reference stabilization repeated the state of pass ${first_seen_pass.to_str()} at pass ${repeated_at_pass.to_str()}; no attempted state is accepted.", [])
	ReferenceBudget({ passes }) => located_error(doc, BudgetExceeded, "layout.budget_exhausted", "Reference stabilization did not repeat a state within its budget of ${passes.to_str()} passes; no attempted state is accepted.", [])
	_ => UnsupportedAuthoringContent({ blocks: Document.block_count(doc) })
}

## Text a shaping path cannot shape, located at its paragraph or rich
## inline with the failing cluster's scalars. A script outside the path's
## set is reported before a multi-scalar cluster, and both before coverage,
## so the author sees the fundamental cause; no face is substituted.
unsupported_text_error : Document, U64, [AtInline(U64), NoInline], [Cluster, Coverage(U32), Script(Str)], Semantics.Range -> Pdf.Error
unsupported_text_error = |doc, block, inline, reason, scalars| {
	at = "scalars ${scalars.start().to_str()} to ${(scalars.start() + scalars.length()).to_str()}"
	(feature, message) = match reason {
		Script(script) => ("text.unsupported_script", "Text at ${at} uses the script ${if script.is_empty() "Unknown" else script}, which the selected text path does not shape.")
		Cluster => ("text.unsupported_cluster", "Text at ${at} is a multi-scalar grapheme cluster, which the convenience shaper does not support.")
		Coverage(scalar) => ("text.coverage_missing", "No selected face covers U+${scalar_hex(scalar)} at ${at}; no face is substituted.")
	}
	normalized = Document.normalize(doc)
	rich = match normalized.blocks.get(block) {
		Ok({ kind: RichParagraph(_), .. }) => True
		_ => False
	}
	if rich {
		inline_error(doc, block, inline, FontCoverageMissing, feature, message)
	} else {
		located_error(doc, FontCoverageMissing, feature, message, [leaf_path(doc, block)])
	}
}

## A scalar in at least four upper-case hexadecimal digits.
scalar_hex : U32 -> Str
scalar_hex = |scalar| {
	digits = "0123456789ABCDEF".to_utf8()
	value = scalar.to_u64()
	var $bytes = []
	var $place = 1048576
	while $place > 0 {
		digit = (value // $place) % 16
		if digit != 0 or !$bytes.is_empty() or $place <= 4096 {
			$bytes = $bytes.append(digits.get(digit) ?? '0')
		}
		$place = $place // 16
	}
	Str.from_utf8($bytes) ?? ""
}

lead_overflow_error : U64, U64 -> Pdf.Error
lead_overflow_error = |available, required| InvalidDocument(located_batch(LayoutConstraintViolated, "layout.template_region_overflow", "The first page's lead region holds content ${points_text(required)} tall but reserves ${points_text(available)}; its blocks are laid out once, as one unit, and never split, shrunk, or clipped.", ["templates.first.lead"]))

## Page-template and furniture rejections name their authored template
## path, such as `templates.continuation.footer.end[0].inlines[0]`.
furniture_error : KernelFacadeFurniture.Error -> Pdf.Error
furniture_error = |error| {
	located = |diagnostic, feature, message, paths| InvalidDocument(located_batch(diagnostic, feature, message, paths))
	match error {
		BodySpace({ footer, gap, header, lead, line, remaining, template }) => {
			zero : I64
			zero = 0
			remaining_text = if remaining < zero "-${points_text((zero - remaining).to_u64_wrap())}" else points_text(remaining.to_u64_wrap())
			lead_text = if lead == 0 "" else ", lead region ${points_text(lead)}"
			located(LayoutConstraintViolated, "layout.template_body_space", "The template's regions (header ${points_text(header)}${lead_text}, footer ${points_text(footer)}, gap ${points_text(gap)}) leave ${remaining_text} of body flow, less than one body line of ${points_text(line)}.", [template])
		}
		BodyEmpty => located(LayoutConstraintViolated, "layout.template_body_empty", "A document with page templates needs at least one body block; a lead region alone does not start the body.", [])
		RegionEmpty({ path }) => located(LayoutConstraintViolated, "layout.template_region_empty", "A template region must reserve a positive height and hold at least one furniture item; use no_region (or no_lead) for a page without that region.", [path])
		RegionOverflow({ available, path, required }) => located(LayoutConstraintViolated, "layout.template_region_overflow", "Furniture needs ${points_text(required)} but its region or reserved width holds ${points_text(available)}; furniture is never wrapped, shrunk, or clipped.", [path])
		SlotOverlap({ page, path, slots }) => located(LayoutConstraintViolated, "layout.template_region_overflow", "The ${slots} slots of a template region overlap on page ${page.to_str()}.", [path])
		FieldOverflow({ page, path, reserved, value, width }) => located(LayoutConstraintViolated, "layout.field_overflow", "A page field first fails to fit on page ${page.to_str()}: its resolved value ${value} makes its content ${points_text(width)} wide but it has ${points_text(reserved)}. Field values are never approximated, abbreviated, or shrunk.", [path])
		FurnitureInline({ path }) => located(LayoutConstraintViolated, "layout.furniture_inline", "Furniture text holds only text, page fields, and reserved widths of text and page fields.", [path])
		InlineEmpty({ path }) => located(InvalidRelationship, "semantics.inline_empty", "Furniture text and every reserved width in it must contain text or a page field, and no text inline may be empty.", [path])
		DrawingInvalid({ path, reason }) => located(InvalidRelationship, "layout.furniture_drawing", "A furniture drawing is not a supported decorative drawing: ${reason}.", [path])
		GapNegative({ path }) => located(LayoutConstraintViolated, "layout.spacer_negative", "A template gap is negative; spacing never overlaps content.", [path])
		FurnitureText({ path, reason: Coverage }) => located(FontCoverageMissing, "text.coverage_missing", "No face of the ordered font policy covers every cluster of this furniture text; no face is substituted.", [path])
		FurnitureText({ path, reason: Script(script) }) => located(FontCoverageMissing, "text.unsupported_script", "Furniture text uses the script ${if script.is_empty() "Unknown" else script}, which the convenience text path does not shape.", [path])
		_ => InternalGenerationFailure
	}
}

dimension_name : KernelFacadeSemantics.Dimension -> Str
dimension_name = |dimension| match dimension {
	ContentSpine => "content-spine items"
	Nodes => "structure elements"
	Occurrences => "content occurrences"
	Properties => "text properties"
	SourceInputs => "text sources"
}

## The authored member a leaf stands for: the table around a caption or a
## cell, else the leaf itself.
member_path : Document, Document.NormalizedAuthoring, U64 -> Str
member_path = |doc, normalized, block| {
	var $code = match normalized.blocks.get(block) {
		Ok(record) => record.parent
		Err(OutOfBounds) => 0
	}
	var $table = 0
	while $code != 0 {
		record = group_record(normalized.groups, $code)
		match record.kind {
			Table(_) => {
				$table = $code
			}
			_ => {}
		}
		$code = record.parent
	}
	if $table == 0 leaf_path(doc, block) else group_path(normalized.groups, $table - 1)
}

## A page-layout rejection of a document with tables, whose block indexes
## name page-layout units: a leaf block's path, or a table row's
## `contents[k].table.body_rows[r]`.
table_layout_error : Document, KernelPageLayout.Error, List(KernelFacadePages.KeepSource), List(KernelFacadePages.Unit) -> Pdf.Error
table_layout_error = |doc, error, sources, units| {
	normalized = Document.normalize(doc)
	unit_at = |index| match units.get(index) {
		Ok(value) => value
		Err(OutOfBounds) => crash "page-layout unit escaped"
	}
	unit_path = |index| match unit_at(index) {
		LeafUnit(block) => leaf_path(doc, block)
		RowUnit(group) => group_path(normalized.groups, group)
	}
	leaf_of = |index| match unit_at(index) {
		LeafUnit(block) => block
		RowUnit(group) => group_record(normalized.groups, group + 1).block_end - 1
	}
	feature = "layout.keep_conflict"
	match error {
		Oversize({ available, block, required }) => match unit_at(block) {
			LeafUnit(leaf) => oversize_error(doc, leaf, required, available)
			RowUnit(group) => located_error(doc, LayoutConstraintViolated, "layout.oversize_row", "A table row needs ${points_text(required)}, with the repeated header rows, but a page body holds ${points_text(available)}; under KeepRows a row is never split, shrunk, or clipped. Select SplitRows to let rows break at line boundaries.", [group_path(normalized.groups, group)])
		}
		KeepConflict(conflict) => match conflict {
			GroupTooTall({ available, group, required }) => match sources.get(group) {
				Ok(FooterRows({ first, last })) => located_error(doc, LayoutConstraintViolated, feature, "A table's footer rows stay together and need ${points_text(required)}, with the repeated header rows, but a page body holds ${points_text(available)}.", [group_path(normalized.groups, first), group_path(normalized.groups, last)])
				Ok(AuthoredKeep(k)) => {
					index = together_group(normalized.groups, k)
					record = group_record(normalized.groups, index + 1)
					located_error(doc, LayoutConstraintViolated, feature, "A keep-together group needs ${points_text(required)} but a page body holds ${points_text(available)}.", [group_path(normalized.groups, index), member_path(doc, normalized, record.first_block), member_path(doc, normalized, record.block_end - 1)])
				}
				Err(OutOfBounds) => crash "page-layout group escaped"
			}
			BreakInsideGroup({ block, group }) => {
				group_paths = match sources.get(group) {
					Ok(AuthoredKeep(k)) => [group_path(normalized.groups, together_group(normalized.groups, k))]
					Ok(FooterRows({ first, last: _ })) => [group_path(normalized.groups, first)]
					Err(OutOfBounds) => []
				}
				located_error(doc, LayoutConstraintViolated, feature, "A page break falls inside a keep-together group.", [break_path(normalized, leaf_of(block))].concat(group_paths))
			}
			BreakAfterRequiredKeep({ block, next }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next is followed by a page break.", [required_keep_path(doc, normalized, leaf_of(block)), break_path(normalized, leaf_of(next))])
			ChainTooTall({ available, block, next, required }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next chain (such as a table's caption, header rows, and first body row) needs ${points_text(required)} but a page body holds ${points_text(available)}.", [unit_path(block), unit_path(next)])
			RequiredKeepAtEnd({ block }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next has no following block.", [required_keep_path(doc, normalized, leaf_of(block))])
		}
		LimitExceeded({ attempted, dimension: Pages, limit }) => located_error(doc, BudgetExceeded, "document.content_limit", "The document needs ${attempted.to_str()} pages but the facade accepts at most ${limit.to_str()}.", [])
		_ => UnsupportedAuthoringContent({ blocks: Document.block_count(doc) })
	}
}

## A custom-block rejection located at the block's authored path.
custom_error : Document, U64, Conformance.DiagnosticCode, Str, Str -> Pdf.Error
custom_error = |doc, custom, diagnostic, feature, message| {
	normalized = Document.normalize(doc)
	group = match normalized.customs.get(custom) {
		Ok(record) => record.group
		Err(OutOfBounds) => crash "normalized custom block path escaped"
	}
	located_error(doc, diagnostic, feature, message, [group_path(normalized.groups, group)])
}

## Content a custom block cannot hold, located at the block and at the
## offending child; a custom block in the lead region names the block.
custom_content_error : Document, U64, [Child(U64), NoChild] -> Pdf.Error
custom_content_error = |doc, custom, child| {
	normalized = Document.normalize(doc)
	group = match normalized.customs.get(custom) {
		Ok(record) => record.group
		Err(OutOfBounds) => crash "normalized custom block path escaped"
	}
	path = group_path(normalized.groups, group)
	feature = "semantics.custom_block_content"
	match child {
		Child(position) => located_error(doc, InvalidRelationship, feature, "A custom block holds only paragraphs and rich paragraphs, laid out inside its measured box.", [path, child_path(normalized.groups, group + 1, position)])
		NoChild => located_error(doc, InvalidRelationship, feature, "A custom block is body flow; it cannot appear in the first page's lead region.", [path])
	}
}

## A layout-policy or list rejection located at authored group `group`.
group_error : Document, U64, Conformance.DiagnosticCode, Str, Str -> Pdf.Error
group_error = |doc, group, diagnostic, feature, message| {
	normalized = Document.normalize(doc)
	located_error(doc, diagnostic, feature, message, [group_path(normalized.groups, group)])
}

located_error : Document, Conformance.DiagnosticCode, Str, Str, List(Str) -> Pdf.Error
located_error = |_doc, diagnostic, feature, message, paths| InvalidDocument(located_batch(diagnostic, feature, message, paths))

## A scale in thousandths as a percentage, such as `80.5%`.
percent_text : U64 -> Str
percent_text = |scale| if scale % 10 == 0 "${(scale // 10).to_str()}%" else "${(scale // 10).to_str()}.${(scale % 10).to_str()}%"

## A page break, spacer, or decoration located by its authored parent and
## position.
flow_item_error : Document, [DecorationItem(U64), PageBreakItem(U64), SpacerItem(U64)], Conformance.DiagnosticCode, Str, Str -> Pdf.Error
flow_item_error = |doc, item, diagnostic, feature, message| {
	normalized = Document.normalize(doc)
	path = match item {
		PageBreakItem(index) => match normalized.page_breaks.get(index) {
			Ok(record) => child_path(normalized.groups, record.parent, record.position)
			Err(OutOfBounds) => crash "normalized page break path escaped"
		}
		SpacerItem(index) => match normalized.spacers.get(index) {
			Ok(record) => child_path(normalized.groups, record.parent, record.position)
			Err(OutOfBounds) => crash "normalized spacer path escaped"
		}
		DecorationItem(index) => match normalized.decorations.get(index) {
			Ok(record) => child_path(normalized.groups, record.parent, record.position)
			Err(OutOfBounds) => crash "normalized decoration path escaped"
		}
	}
	located_error(doc, diagnostic, feature, message, [path])
}

## A line break with no text on one side, located by its paragraph path and
## its authored inline position.
line_break_error : Document, U64, U64 -> Pdf.Error
line_break_error = |doc, block, line_break| {
	normalized = Document.normalize(doc)
	record = match normalized.line_breaks.get(line_break) {
		Ok(value) => value
		Err(OutOfBounds) => crash "normalized line break path escaped"
	}
	owner = if record.parent == 0 NoInline else AtInline(record.parent - 1)
	path = "${inline_path(normalized, block, owner)}.inlines[${record.position.to_str()}]"
	located_error(doc, InvalidRelationship, "semantics.line_break_position", "A line break must separate text inside its paragraph; it cannot begin or end the paragraph or follow another line break.", [path])
}

## A generated list label wider than the list indent, located at its item.
label_width_error : Document, U64, U64, U64 -> Pdf.Error
label_width_error = |doc, block, width, available| {
	normalized = Document.normalize(doc)
	var $item = normalized.groups.len()
	var $index = 0
	for group in normalized.groups {
		match group.kind {
			ListItem(_) => if group.first_block == block {
				$item = $index
			}
			_ => {}
		}
		$index = $index + 1
	}
	path = if $item < normalized.groups.len() group_path(normalized.groups, $item) else leaf_path(doc, block)
	located_error(doc, LayoutConstraintViolated, "layout.list_label_width", "A list's label column, widened to ${points_text(width)} for its widest generated label, leaves its body no width: the column may use at most ${points_text(available)}. Labels are never shrunk or allowed to overlap their body.", [path])
}

## A mandatory keep conflict naming every participating source.
keep_conflict_error : Document, KernelPageLayout.Conflict -> Pdf.Error
keep_conflict_error = |doc, conflict| {
	normalized = Document.normalize(doc)
	feature = "layout.keep_conflict"
	match conflict {
		GroupTooTall({ available, group, required }) => {
			index = together_group(normalized.groups, group)
			record = match normalized.groups.get(index) {
				Ok(value) => value
				Err(OutOfBounds) => crash "normalized keep path escaped"
			}
			located_error(doc, LayoutConstraintViolated, feature, "A keep-together group needs ${points_text(required)} but a page body holds ${points_text(available)}.", [group_path(normalized.groups, index), leaf_path(doc, record.first_block), leaf_path(doc, record.block_end - 1)])
		}
		BreakInsideGroup({ block, group }) => located_error(doc, LayoutConstraintViolated, feature, "A page break falls inside a keep-together group.", [break_path(normalized, block), group_path(normalized.groups, together_group(normalized.groups, group))])
		BreakAfterRequiredKeep({ block, next }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next is followed by a page break.", [required_keep_path(doc, normalized, block), break_path(normalized, next)])
		ChainTooTall({ available, block, next, required }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next and the block it keeps with need ${points_text(required)} but a page body holds ${points_text(available)}.", [required_keep_path(doc, normalized, block), leaf_path(doc, next)])
		RequiredKeepAtEnd({ block }) => located_error(doc, LayoutConstraintViolated, feature, "A required keep-with-next has no following block.", [required_keep_path(doc, normalized, block)])
	}
}

## An unsplittable block taller than a page body: a figure is
## `document.figure_oversize`, any other block `layout.oversize_block`.
oversize_error : Document, U64, U64, U64 -> Pdf.Error
oversize_error = |doc, block, required, available| {
	normalized = Document.normalize(doc)
	figure = match normalized.blocks.get(block) {
		Ok(record) => match record.kind {
			Figure(_) => True
			_ => False
		}
		Err(OutOfBounds) => False
	}
	feature = if figure "document.figure_oversize" else "layout.oversize_block"
	located_error(doc, LayoutConstraintViolated, feature, "An unsplittable block needs ${points_text(required)} but a page body holds ${points_text(available)}; content is never shrunk, clipped, or split to fit.", [leaf_path(doc, block)])
}

## The `k`-th keep-together group in preorder, as a normalized group index.
together_group : List(Document.NormalizedGroup), U64 -> U64
together_group = |groups, k| {
	var $seen = 0
	var $found = groups.len()
	var $index = 0
	for group in groups {
		match group.kind {
			KeepTogether | Custom(_) => {
				if $seen == k and $found == groups.len() {
					$found = $index
				}
				$seen = $seen + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	$found
}

## The authored page break before leaf `block`.
break_path : Document.NormalizedAuthoring, U64 -> Str
break_path = |normalized, block| {
	var $path = ""
	for record in normalized.page_breaks {
		if record.block == block and $path.is_empty() {
			$path = child_path(normalized.groups, record.parent, record.position)
		}
	}
	$path
}

## The innermost required `keep_with_next` whose last leaf is `block`.
required_keep_path : Document, Document.NormalizedAuthoring, U64 -> Str
required_keep_path = |doc, normalized, block| {
	var $found = normalized.groups.len()
	var $index = 0
	for group in normalized.groups {
		match group.kind {
			KeepWithNext(Required) => if group.block_end == block + 1 {
				$found = $index
			}
			_ => {}
		}
		$index = $index + 1
	}
	if $found < normalized.groups.len() group_path(normalized.groups, $found) else leaf_path(doc, block)
}

## A fixed-point length as points, such as `746 pt` or `12.5 pt`.
points_text : U64 -> Str
points_text = |raw| {
	whole = raw // 1000
	fraction = raw % 1000
	if fraction == 0 {
		"${whole.to_str()} pt"
	} else {
		digits = (1000 + fraction).to_str()
		trimmed = trim_zeros(Str.to_utf8(digits).drop_first(1))
		text = match Str.from_utf8(trimmed) {
			Ok(value) => value
			Err(_) => "0"
		}
		"${whole.to_str()}.${text} pt"
	}
}

trim_zeros : List(U8) -> List(U8)
trim_zeros = |bytes| {
	var $bytes = bytes
	while !$bytes.is_empty() and (match $bytes.get($bytes.len() - 1) {
		Ok(last) => last == 48
		Err(OutOfBounds) => False
	}) {
		$bytes = $bytes.drop_last(1)
	}
	$bytes
}

located_batch : Conformance.DiagnosticCode, Str, Str, List(Str) -> Conformance.DiagnosticBatch
located_batch = |diagnostic, feature, message, paths| {
	full = "${message} No PDF bytes were emitted."
	var $bytes = full.count_utf8_bytes()
	for path in paths {
		$bytes = $bytes + path.count_utf8_bytes()
	}
	{
		detail_bytes: $bytes,
		diagnostics: [
			{
				clause_references: [],
				code: diagnostic,
				details: paths,
				feature: Feature(feature),
				location: Document,
				message: full,
				requirement_ids: [],
				stage: AuthoringValidation,
			},
		],
		truncation: Complete,
	}
}

## The authored path of normalized leaf `block`, recovered by walking the
## authored tree in normalization order on the rejection path only. Groups
## name their children `contents[k]`, a list its `items[k]`, and a keep
## with next its single `block`.
leaf_path : Document, U64 -> Str
leaf_path = |doc, block| {
	normalized = Document.normalize(doc)
	record = match normalized.blocks.get(block) {
		Ok(value) => value
		Err(OutOfBounds) => crash "normalized leaf path escaped"
	}

	## A figure's leaves are named by the figure's own path, its caption
	## as `.caption`.
	figure_leaf = if record.parent == 0 {
		NotFigure
	} else {
		match group_record(normalized.groups, record.parent).kind {
			FigureGroup(_) => match record.kind {
				FigureCaption(_) => CaptionLeaf
				_ => FigureLeaf
			}
			_ => NotFigure
		}
	}
	match figure_leaf {
		NotFigure => {
			position = leaf_position(normalized, block, record.parent)
			child_path(normalized.groups, record.parent, position)
		}
		FigureLeaf => chain_path(normalized.groups, record.parent)
		CaptionLeaf => "${chain_path(normalized.groups, record.parent)}.caption"
	}
}

## A leaf's authored index in its parent: the next leaves, groups, page
## breaks, and spacers of the parent occupy the positions around it, so the
## leaf's position is found by counting those siblings that precede it.
leaf_position : Document.NormalizedAuthoring, U64, U64 -> U64
leaf_position = |normalized, block, parent| {
	match normalized.blocks.get(block) {
		Ok(record) => match record.kind {
			RichParagraph(paragraph) => match normalized.rich_paragraphs.get(paragraph) {
				Ok(rich) => return rich.position
				Err(OutOfBounds) => crash "normalized rich block path escaped"
			}
			_ => {}
		}
		Err(OutOfBounds) => crash "normalized leaf path escaped"
	}

	## Siblings in the same parent before this leaf: earlier leaves (a legacy
	## bullet list counts once), child groups, page breaks, and spacers.
	var $position = 0
	var $index = 0
	var $previous_list = U64.highest
	while $index < block {
		match normalized.blocks.get($index) {
			Ok(sibling) => if sibling.parent == parent {
				match sibling.kind {
					Bullet({ item: _, list }) => if list != $previous_list {
						$position = $position + 1
						$previous_list = list
					}
					_ => {
						$position = $position + 1
					}
				}
			}
			Err(OutOfBounds) => {}
		}
		$index = $index + 1
	}
	for group in normalized.groups {
		## The lead region is a template region, not an authored sibling.
		lead = match group.kind {
			LeadRegion => True
			_ => False
		}
		if group.parent == parent and group.block_end <= block and !lead {
			$position = $position + 1
		}
	}
	for record in normalized.page_breaks {
		if record.parent == parent and record.block <= block {
			$position = $position + 1
		}
	}
	for record in normalized.spacers {
		if record.parent == parent and record.block <= block {
			$position = $position + 1
		}
	}
	for record in normalized.decorations {
		if record.parent == parent and record.block <= block {
			$position = $position + 1
		}
	}
	match normalized.blocks.get(block) {
		Ok(record) => match record.kind {
			Bullet({ item, list: _ }) => if item > 0 $position - 1 else $position
			_ => $position
		}
		Err(OutOfBounds) => $position
	}
}

uri_problem : Document.NavigationError -> Str
uri_problem = |error| match error {
	UriEmpty(_) => "it is empty"
	UriTooLong(_) => "it is too long"
	UriMissingScheme(_) => "it has no scheme"
	UriInvalidPercentEncoding(_) => "it has an invalid percent-encoding"
	UriInvalidByte(_) => "it contains a byte outside the URI grammar"
	_ => "it is malformed"
}

## A rich-inline rejection located by the authored block path of its
## paragraph and, below it, the authored inline positions, such as
## `contents[2].inlines[1].inlines[0]`. Like the container paths, the
## normalized arenas are rebuilt only on this rejection path.
inline_error : Document, U64, [AtInline(U64), NoInline], Conformance.DiagnosticCode, Str, Str -> Pdf.Error
inline_error = |doc, block, inline, diagnostic, feature, message| {
	normalized = Document.normalize(doc)
	InvalidDocument(container_batch(diagnostic, feature, message, inline_path(normalized, block, inline)))
}

inline_path : Document.NormalizedAuthoring, U64, [AtInline(U64), NoInline] -> Str
inline_path = |normalized, block_index, inline| {
	block = match normalized.blocks.get(block_index) {
		Ok(value) => value
		Err(OutOfBounds) => crash "normalized rich block path escaped"
	}
	(paragraph, position) = match block.kind {
		RichParagraph(index) => match normalized.rich_paragraphs.get(index) {
			Ok(rich) => (index, rich.position)
			Err(OutOfBounds) => crash "normalized rich block path escaped"
		}
		_ => crash "normalized rich block path named a non-rich block"
	}
	var $positions = []
	var $cursor = match inline {
		AtInline(index) => index + 1
		NoInline => 0
	}
	while $cursor != 0 {
		record = match normalized.inlines.get($cursor - 1) {
			Ok(value) => value
			Err(OutOfBounds) => crash "normalized inline path escaped"
		}
		$positions = $positions.append(authored_inline_position(normalized.line_breaks, paragraph, record.parent, record.position))
		$cursor = record.parent
	}
	var $path = child_path(normalized.groups, block.parent, position)
	var $index = $positions.len()
	while $index > 0 {
		segment = match $positions.get($index - 1) {
			Ok(value) => value
			Err(OutOfBounds) => crash "normalized inline path escaped"
		}
		$path = "${$path}.inlines[${segment.to_str()}]"
		$index = $index - 1
	}
	$path
}

## An inline record's `position` is its content-spine slot among its
## siblings; line breaks hold no slot, so the authored index adds back each
## sibling line break (in authored order) at or before it.
authored_inline_position : List(Document.NormalizedLineBreak), U64, U64, U64 -> U64
authored_inline_position = |line_breaks, paragraph, parent, slot| {
	var $position = slot
	for record in line_breaks {
		if record.paragraph == paragraph and record.parent == parent and record.position <= $position {
			$position = $position + 1
		}
	}
	$position
}

## The compact authored location of group `group`, such as
## `contents[3].contents[0]` or `contents[2].items[1].contents[0]`: each
## segment is the group's index in its parent's authored contents, named
## `items[k]` inside a list and `block` inside a keep-with-next.
group_path : List(Document.NormalizedGroup), U64 -> Str
group_path = |groups, group| chain_path(groups, group + 1)

## The path of the child at authored `position` of group code `parent`.
child_path : List(Document.NormalizedGroup), U64, U64 -> Str
child_path = |groups, parent, position| if parent == 0 {
	"contents[${position.to_str()}]"
} else {
	"${chain_path(groups, parent)}.${child_segment(groups, parent, position)}"
}

## The path of group code `code`, from the outermost group inwards.
chain_path : List(Document.NormalizedGroup), U64 -> Str
chain_path = |groups, code| {
	var $codes = []
	var $cursor = code
	while $cursor != 0 {
		$codes = $codes.append($cursor)
		$cursor = group_record(groups, $cursor).parent
	}
	var $path = ""
	var $index = $codes.len()
	while $index > 0 {
		record = match $codes.get($index - 1) {
			Ok(value) => group_record(groups, value)
			Err(OutOfBounds) => crash "normalized group path escaped"
		}
		segment = match record.kind {
			LeadRegion => "templates.first.lead"
			TableRow(Header) => "table.header_rows[${record.position.to_str()}]"
			TableRow(Body) => "table.body_rows[${record.position.to_str()}]"
			TableRow(Footer) => "table.footer_rows[${record.position.to_str()}]"
			_ => child_segment(groups, record.parent, record.position)
		}
		$path = if $path.is_empty() segment else "${$path}.${segment}"
		$index = $index - 1
	}
	$path
}

## One path segment: a list names its children `items[k]`, a keep with
## next its single `block`, and every other parent `contents[k]`.
child_segment : List(Document.NormalizedGroup), U64, U64 -> Str
child_segment = |groups, parent, position| if parent == 0 {
	"contents[${position.to_str()}]"
} else {
	match group_record(groups, parent).kind {
		ItemList(_) => "items[${position.to_str()}]"
		KeepWithNext(_) => "block"
		Table(_) => "caption"
		TableRow(_) => "cells[${position.to_str()}]"
		_ => "contents[${position.to_str()}]"
	}
}

group_record : List(Document.NormalizedGroup), U64 -> Document.NormalizedGroup
group_record = |groups, code| match groups.get(code - 1) {
	Ok(value) => value
	Err(OutOfBounds) => crash "normalized group path escaped"
}

container_batch : Conformance.DiagnosticCode, Str, Str, Str -> Conformance.DiagnosticBatch
container_batch = |diagnostic, feature, message, path| {
	full = "${message} No PDF bytes were emitted."
	{
		detail_bytes: full.count_utf8_bytes() + path.count_utf8_bytes(),
		diagnostics: [
			{
				clause_references: [],
				code: diagnostic,
				details: [path],
				feature: Feature(feature),
				location: Document,
				message: full,
				requirement_ids: [],
				stage: AuthoringValidation,
			},
		],
		truncation: Complete,
	}
}

## Whether a theme selects an inline role face other than its body face,
## without building a list on the common path.
has_role_face : Theme -> Bool
has_role_face = |theme| {
	body = Theme.body_font(theme).index()
	differs = |font| match font {
		Face(face) => face.index() != body
		Inherited => Bool.False
	}
	differs(Theme.inline_font(theme, Code)) or differs(Theme.inline_font(theme, Emphasis)) or differs(Theme.inline_font(theme, Quote)) or differs(Theme.inline_font(theme, Strong))
}

## The inline role faces a theme selects that differ from its body face.
role_faces : Theme -> List(Font.FaceId)
role_faces = |theme| {
	body = Theme.body_font(theme)
	[Theme.inline_font(theme, Code), Theme.inline_font(theme, Emphasis), Theme.inline_font(theme, Quote), Theme.inline_font(theme, Strong)]
		.keep_if(
			|font| match font {
				Face(face) => face.index() != body.index()
				Inherited => Bool.False
			},
		)
		.map(
			|font| match font {
				Face(face) => face
				Inherited => body
			},
		)
}

## The style-face candidates with inline role faces: the body face first,
## then each distinct role face, all prepared from the caller registry. The
## packaged face alone has no second face, so a role face there is an
## unknown face.
selected_styled_fonts : Pdf.Options -> Try(KernelFacadeShape.FontSelection, Pdf.Error)
selected_styled_fonts = |options| {
	body_face = Theme.body_font(options.theme)
	body = selected_font(options)?
	registry = match options.font_source {
		Registered(value) => value
		BuiltIn => return Err(InvalidFontResource(UnknownFace(list_first_or(role_faces(options.theme), body_face))))
	}
	var $faces = [body_face]
	var $fonts = [body]
	for face in role_faces(options.theme) {
		if !$faces.any(|known| known.index() == face.index()) {
			font = registry.prepared_face(face) ? InvalidFontResource
			$faces = $faces.append(face)
			$fonts = $fonts.append(font)
		}
	}
	candidate = |role| match Theme.inline_font(options.theme, role) {
		Face(face) => if face.index() == body_face.index() Inherited else Candidate(index_of($faces, face))
		Inherited => Inherited
	}
	Ok(Styled({ faces: $faces, fonts: $fonts, roles: { code: candidate(Code), emphasis: candidate(Emphasis), quote: candidate(Quote), strong: candidate(Strong) } }))
}

list_first_or : List(a), a -> a
list_first_or = |items, fallback| match items.first() {
	Ok(value) => value
	Err(_) => fallback
}

index_of : List(Font.FaceId), Font.FaceId -> U64
index_of = |faces, face| {
	var $index = 0
	while $index < faces.len() {
		if list_at_face(faces, $index).index() == face.index() {
			return $index
		}
		$index = $index + 1
	}
	0
}

list_at_face : List(Font.FaceId), U64 -> Font.FaceId
list_at_face = |faces, index| match faces.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "styled face index escaped"
	}
}

selected_font : Pdf.Options -> Try(KernelFont.Inspection, Pdf.Error)
selected_font = |options| match options.font_source {
	BuiltIn => {
		## The packaged face has the same dense facade identity as the initial
		## caller registry face. The shaping stage consumes only the validated
		## inspection and typed Theme face, never a provenance flag.
		if Theme.body_font(options.theme).index() != 0 {
			Err(InvalidFontResource(UnknownFace(Theme.body_font(options.theme))))
		} else {
			selected_built_in_font({})
		}
	}
	Registered(registry) => selected_registered_font(registry, Theme.body_font(options.theme))
}

selected_built_in_font : {} -> Try(KernelFont.Inspection, Pdf.Error)
selected_built_in_font = |_| {
	font = KernelFont.inspect(KernelBuiltInFont.bytes, standard_font_limits) ? |_| InternalGenerationFailure
	Ok(font)
}

selected_registered_font : Font.Registry, Font.FaceId -> Try(KernelFont.Inspection, Pdf.Error)
selected_registered_font = |registry, face| {
	font = registry.prepared_face(face) ? InvalidFontResource
	Ok(font)
}

## The requested claim is derived from the public profile's exact claim set.
## A profile whose claim set includes an unfinished capability is rejected
## before any work; it never falls back to a narrower claim set.
validate_profile_request : Pdf.Options -> Try(KernelPdfA4.Claim, Pdf.Error)
validate_profile_request = |options| {
	match options.profile {
		AccessibleArchive => Err(Pdf.Error.InvalidDocument(unavailable_batch(AccessibleArchiveProfile, "The AccessibleArchive profile requires the unfinished combined PDF/A-4 and PDF/UA-2 capability.")))
		Archive | Standard => Ok(if Pdf.claims_for_profile(options.profile).static_pdf_a4 StaticPdfA4Claim else NoArchiveClaim)
	}
}

unavailable_message : Document.Feature, Str -> Str
unavailable_message = |feature, summary| {
	misuse = match feature {
		FigureFit => True
		_ => False
	}
	if misuse {
		return "${summary} No PDF bytes were emitted."
	}
	roadmap = match feature {
		ArchiveProfile => "Gate 5"
		AccessibleArchiveProfile => "Gate 7"
		Figures | FigureFit => "Gate 6"
		ContextualArtifacts | PageTemplates | SemanticTextProperties => "Gate 6"
		ComplexTables | CustomLayout | Floats | Footnotes | GeneratedReferences | MultiColumnLayout | SideContent | VerticalWriting => "Gate 8"
	}
	"${summary} No PDF bytes were emitted. This capability remains scheduled for ${roadmap}."
}

feature_code : Document.Feature -> Str
feature_code = |feature| match feature {
	ArchiveProfile => "profile.archive"
	AccessibleArchiveProfile => "profile.accessible_archive"
	Figures => "document.figure"
	FigureFit => "document.figure_fit"
	ContextualArtifacts => "semantics.contextual_artifact"
	SemanticTextProperties => "semantics.text_properties"
	ComplexTables => "table.complex"
	CustomLayout => "layout.custom"
	Floats => "layout.float"
	Footnotes => "document.footnote"
	GeneratedReferences => "document.generated_reference"
	MultiColumnLayout => "layout.multi_column"
	PageTemplates => "layout.page_template"
	SideContent => "document.side_content"
	VerticalWriting => "text.vertical_writing"
}

unavailable_batch : Document.Feature, Str -> Conformance.DiagnosticBatch
unavailable_batch = |feature, summary| {
	message = unavailable_message(feature, summary)
	{
		detail_bytes: Str.to_utf8(message).len(),
		diagnostics: [
			{
				clause_references: [],
				code: match feature {
					FigureFit => InvalidRelationship
					_ => FeatureUnavailable
				},
				details: [],
				feature: Feature(feature_code(feature)),
				location: Document,
				message,
				requirement_ids: [],
				stage: AuthoringValidation,
			},
		],
		truncation: Complete,
	}
}

structure_page_size : Pdf.PageSize -> KernelStructure.PageSize
structure_page_size = |page_size| match page_size {
	A4 => KernelStructure.PageSize.A4
	Letter => KernelStructure.PageSize.Letter
}

layout_page_size : Pdf.PageSize -> Layout.Size
layout_page_size = |page_size| match page_size {
	A4 => { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }
	Letter => { height: Layout.Unit.from_raw(792000), width: Layout.Unit.from_raw(612000) }
}

standard_metadata_limits : KernelMetadata.Limits
standard_metadata_limits = KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })

## The canonical packet for a maximal facade title (2048 bytes escaped up to
## five-fold), language, and both timestamps stays far below this budget, so
## the facade cannot reach the kernel packet bound.
standard_xmp_bytes : U64
standard_xmp_bytes = 16384

standard_font_limits : KernelFont.Limits
standard_font_limits = KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })

standard_font_descriptor : KernelPdfFont.Descriptor
standard_font_descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

## The facade's documented content bounds. A document may hold up to
## 16,384 content occurrences (text leaves, cells, and generated labels),
## 16,384 structure elements and interned text sources, 65,536 content-spine
## items, 65,536 typed attributes and relationships, 16,384 leaf blocks,
## 65,536 shaped physical runs, and 1,024 pages. The semantic bounds are
## checked first, while planning each authored block, and exceeding one is
## the located `document.content_limit` diagnostic; every later stage's
## bound is at least as large, so it cannot be reached first by content the
## semantic bounds admit (a 500-row invoice table is far inside them).
facade_occurrences : U64
facade_occurrences = 16384

facade_nodes : U64
facade_nodes = 16384

facade_spine : U64
facade_spine = 65536

facade_attributes : U64
facade_attributes = 65536

facade_blocks : U64
facade_blocks = 16384

facade_runs : U64
facade_runs = 65536

standard_pipeline_limits : KernelFacadePipeline.Limits
standard_pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: facade_attributes, max_content_spine: facade_spine + facade_runs, max_fragments: 1000000, max_namespaces: 2, max_nodes: facade_nodes, max_occurrences: facade_occurrences, max_semantic_depth: 48 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 1000000, max_occurrences: facade_occurrences, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 4000000,
			max_lines: 1000000,
			max_runs: facade_runs,
			max_table_slots: 262144,
			max_templates: facade_runs,
		}),
		max_blocks: facade_blocks,
		max_runs: facade_runs,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: standard_object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 1000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: facade_blocks,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: facade_blocks, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 1000000, max_paths: 1000000 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: facade_spine,
		max_inline_depth: 8,
		max_nodes: facade_nodes,
		max_occurrences: facade_occurrences,
		max_properties: facade_occurrences,
		max_source_inputs: facade_occurrences,
		semantics: KernelSemantics.Limits.make({ max_attributes: facade_attributes, max_content_spine: facade_spine, max_fragments: 0, max_namespaces: 2, max_nodes: facade_nodes, max_occurrences: facade_occurrences, max_semantic_depth: 48 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 4000000,
			max_inputs: facade_occurrences,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 65536,
			max_unique_sources: facade_occurrences,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: facade_occurrences, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: facade_occurrences }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: facade_runs, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

standard_object_limits : KernelObject.Limits
standard_object_limits = {
	max_array_items: 4000000,
	max_byte_string_bytes: 8388608,
	max_byte_strings: 1000000,
	max_dictionary_entries: 4000000,
	max_direct_depth: 8,

	## Every structure element interns its role name and every attribute
	## dictionary its keys, so names grow with structure: the facade's
	## 16,384 nodes with the longest roles and their `/A` entries, and a
	## table cell's element identifier and `/Headers` byte strings, stay
	## well inside these bounds.
	max_name_bytes: 8388608,
	max_names: 1000000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 4000000,
}

## Public profiles map to exact claim sets without enabling orthogonal WTPDF claims.
expect {
	claims = Pdf.claims_for_profile(Pdf.Profile.AccessibleArchive)

	claims.pdf20 and claims.static_pdf_a4 and claims.pdf_ua2 and !claims.wtpdf_accessibility
}

## The lexical implementation remains a private package module.
expect KernelLex.boolean(True) == Str.to_utf8("true")

## text-layout Unicode analysis is pinned to the reviewed Unicode 17 package release.
expect KernelUnicode.version == "17.0.0"

## Object/value/edge storage is likewise package-private.
expect KernelObject.counts(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
).objects == 0

## Sealing remains private and accepts the empty construction store.
expect match KernelSeal.seal(
	KernelObject.init({
		max_array_items: 0,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: 0,
		max_direct_depth: 0,
		max_name_bytes: 0,
		max_names: 0,
		max_objects: 0,
		max_payload_bytes: 0,
		max_payloads: 0,
		max_streams: 0,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: 0,
	}),
) {
	Ok(_) => True
	Err(_) => False
}

## The blank-page structural lowerer is private to the package.
expect match KernelStructure.build_blank(1, KernelStructure.PageSize.A4) {
	Ok(plan) => KernelStructure.Plan.object_count(plan) == 5
	Err(_) => False
}

## The private buffered and chunk transitions share one emitter.
expect {
	plan = KernelStructure.build_blank(1, KernelStructure.PageSize.A4)?
	bytes = KernelEmit.to_bytes(plan)?

	bytes.len() > 0
}

## Default authored content crosses the public facade without exposing PDF internals.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})

	bytes = Pdf.to_bytes(document)?
	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## Preparation is a one-way public boundary and both emission paths consume
## the same sealed plan.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Prepared once")], language: "en-AU", title: "Prepared" })
	prepared = Pdf.prepare(document, Pdf.Options.default)?
	buffered = Pdf.to_bytes_prepared(prepared)?
	chunked = collect_chunks(Pdf.to_chunks_prepared(prepared, ShareUnchangedResources)?)

	buffered == chunked.bytes
}

## Every sRGB theme color is resolved through the packaged profile rather
## than being silently reduced to black.
expect {
	blue : Color.SourceValue
	blue = Srgb(Rgb({ blue: 65535, green: 16000, red: 4000 }))
	theme = Theme.with_body_color(Theme.default, blue)
	options = Pdf.Options.with_theme(Pdf.Options.default, theme)
	document = Pdf.document({ contents: [Pdf.paragraph("Blue body text")], language: "en-AU", title: "Color" })
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.len() > 667
}

## Unavailable authored content rejects atomically through the facade; no
## blank document or partial bytes can escape a Try error.
expect {
	document = Pdf.document({
		contents: [Pdf.footnote("Not implemented")],
		language: "en-AU",
		title: "Unavailable rejection",
	})

	match Pdf.to_bytes(document) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(feature), .. }], .. })) => feature == "document.footnote"
		_ => False
	}
}

## Page templates: furniture, a lead region, and page fields prepare
## through the public facade; a template that leaves no body line and a page
## field in body text reject with their stable codes and paths.
expect {
	page_of = Pdf.reserved_width(Layout.Unit.points(72), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])
	header = Pdf.region({ center: [], end: [Pdf.furniture_text([page_of])], height: Layout.Unit.points(16), start: [Pdf.furniture_text([Pdf.text("Running head")])] })
	templates = |lead_height| {
		continuation: Pdf.page_template({ footer: Pdf.no_region, gap: Layout.Unit.points(12), header }),
		first: Pdf.first_page_template({ footer: Pdf.no_region, gap: Layout.Unit.points(12), header, lead: Pdf.lead_region(Layout.Unit.points(lead_height), [Pdf.paragraph("Letterhead")]) }),
	}
	document = |contents, lead_height| Pdf.with_page_templates(Pdf.document({ contents, language: "en-AU", title: "Templates" }), templates(lead_height))
	accepted = match Pdf.to_bytes(document([Pdf.paragraph("First"), Pdf.page_break, Pdf.paragraph("Second")], 40)) {
		Ok(bytes) => bytes.len() > 1000
		Err(_) => False
	}
	body_space = match Pdf.to_bytes(document([Pdf.paragraph("Body")], 690)) {
		Err(InvalidDocument({ diagnostics: [{ code: LayoutConstraintViolated, details: ["templates.first"], feature: Feature(feature), .. }], .. })) => feature == "layout.template_body_space"
		_ => False
	}
	body_field = match Pdf.to_bytes(Pdf.document({ contents: [Pdf.paragraph("Lead"), Pdf.rich_paragraph([Pdf.text("Page "), Pdf.page_number(Decimal)])], language: "en-AU", title: "Field" })) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, details: ["contents[1].inlines[1]"], feature: Feature(feature), .. }], .. })) => feature == "document.generated_reference"
		_ => False
	}
	accepted and body_space and body_field
}

## Empty default documents emit one structural PDF 2.0 page.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	bytes = Pdf.to_bytes(document)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n")
}

## The explicit Standard option takes the same authored-content path.
expect {
	document = Pdf.document({
		contents: [Pdf.paragraph("Explicit Standard")],
		language: "en-AU",
		title: "Explicit Standard",
	})
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Standard)
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## The default is exactly `to_bytes_with(document, Options.default)`, and
## that default claims static PDF/A-4.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Default")], language: "en-AU", title: "Default" })
	implicit = Pdf.to_bytes(document)?
	explicit = Pdf.to_bytes_with(document, Pdf.Options.default)?
	archive = Pdf.to_bytes_with(document, Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive))?

	implicit == explicit and implicit == archive and contains_bytes(implicit, Str.to_utf8("<pdfaid:part>4</pdfaid:part>"))
}

## Archive emits the same document with exactly the PDF/A identification
## added to its canonical metadata; Standard never declares it.
expect {
	document = Pdf.document({ contents: [Pdf.paragraph("Archive")], language: "en-AU", title: "Archive" })
	archive = Pdf.to_bytes_with(document, Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive))?
	standard = Pdf.to_bytes_with(document, Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Standard))?
	marker = Str.to_utf8("<pdfaid:part>4</pdfaid:part>")

	archive.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and contains_bytes(archive, marker) and !contains_bytes(standard, marker)
}

## A blank Archive document is validated on the same lowered-plan path.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Archive" })
	bytes = Pdf.to_bytes_with(document, Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive))?

	contains_bytes(bytes, Str.to_utf8("<pdfaid:rev>2020</pdfaid:rev>"))
}

## AccessibleArchive remains unavailable rather than dropping its UA claim.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Accessible" })
	options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.AccessibleArchive)

	match Pdf.to_bytes_with(document, options) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, feature: Feature(code), message, .. }], .. })) => code == "profile.accessible_archive" and message.contains("Gate 7")
		_ => False
	}
}

## Chunked facade output is byte-identical with buffered output.
expect {
	document = Pdf.document({ contents: [], language: "en-AU", title: "Blank" })
	expected = Pdf.to_bytes(document)?
	var $encoder = Pdf.to_chunks(document)?
	var $actual = []
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(bytes, next) => {
				$actual = append_pdf_bytes($actual, bytes)
				$encoder = next
			}
		}
	}

	$actual == expected
}

## Authored chunked output is byte-identical to buffered output and arrives
## in more than one plan-derived chunk.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})
	expected = Pdf.to_bytes(document)?
	collected = collect_chunks(Pdf.to_chunks(document)?)

	collected.chunks >= 2 and collected.bytes == expected
}

## Unavailable authored content rejects atomically before any chunk exists.
expect {
	document = Pdf.document({
		contents: [Pdf.footnote("Not implemented")],
		language: "en-AU",
		title: "Chunk rejection",
	})

	match Pdf.to_chunks(document) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, .. }], .. })) => True
		_ => False
	}
}

## The owned-chunk retention mode concatenates to the identical authored bytes.
expect {
	document = Pdf.document({
		contents: [Pdf.title("Report"), Pdf.paragraph("Body")],
		language: "en-AU",
		title: "Report",
	})
	expected = Pdf.to_bytes(document)?
	options = Pdf.Options.with_chunk_retention(Pdf.Options.default, Pdf.ChunkRetention.OwnChunks)
	collected = collect_chunks(Pdf.to_chunks_with(document, options)?)

	collected.bytes == expected
}

collect_chunks : Pdf.Encode -> { bytes : List(U8), chunks : U64 }
collect_chunks = |encoder| {
	var $encoder = encoder
	var $bytes = []
	var $chunks = 0
	var $done = False
	while $done == False {
		match Pdf.next_chunk($encoder) {
			Done => {
				$done = True
			}
			Emit(chunk, next) => {
				$bytes = append_pdf_bytes($bytes, chunk)
				$chunks = $chunks + 1
				$encoder = next
			}
		}
	}
	{ bytes: $bytes, chunks: $chunks }
}

contains_bytes : List(U8), List(U8) -> Bool
contains_bytes = |haystack, needle| {
	var $start = 0
	var $found = False
	while !$found and $start + needle.len() <= haystack.len() {
		$found = haystack.sublist({ start: $start, len: needle.len() }) == needle
		$start = $start + 1
	}
	$found
}

## Appends every element of `source`. It deliberately does not
## `List.reserve` first: an explicit reserve sizes the allocation exactly, so
## a target that keeps growing was reallocated on every call, while `append`
## grows geometrically and keeps accumulation amortized linear.
append_pdf_bytes : List(U8), List(U8) -> List(U8)
append_pdf_bytes = |target, source| {
	length = source.len()
	var $out = target
	var $index = 0
	while $index < length {
		match source.get($index) {
			Ok(byte) => {
				$out = $out.append(byte)
			}
			Err(OutOfBounds) => {
				crash "PDF chunk test index invariant failed"
			}
		}
		$index = $index + 1
	}
	$out
}

## Facade navigation: URI and internal links, an authored named destination,
## an outline, and page labels lower end to end through the standard
## pipeline, and the navigation rejections surface as typed errors.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Navigation"),
			Pdf.destination_heading("intro", 1, "Introduction"),
			Pdf.paragraph("Opening body text."),
			Pdf.link("Visit the project site", "https://example.org/project"),
			Pdf.internal_link("Back to the introduction", "intro"),
		],
		language: "en-AU",
		title: "Navigation",
	})
	navigated = document
		.with_outline([{ depth: 0, destination: "intro", open: True, title: "Introduction" }])
		.with_page_labels([{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }])
	bytes = Pdf.to_bytes(navigated)?

	bytes.len() > 4717
}

## A navigation document's chunked output is byte-identical to its buffered
## output under both retention policies.
expect {
	document = Pdf.document({
		contents: [
			Pdf.destination_heading("start", 1, "Start"),
			Pdf.internal_link("Back to the start", "start"),
			Pdf.link("Reference", "https://example.org/ref"),
		],
		language: "en-AU",
		title: "Chunked navigation",
	}).with_outline([{ depth: 0, destination: "start", open: True, title: "Start" }])
	expected = Pdf.to_bytes(document)?
	shared = collect_chunks(Pdf.to_chunks(document)?)
	owned_options = Pdf.Options.with_chunk_retention(Pdf.Options.default, OwnChunks)
	owned = collect_chunks(Pdf.to_chunks_with(document, owned_options)?)

	shared.bytes == expected and owned.bytes == expected
}

## An unknown destination name on an internal link is a typed navigation
## rejection through the facade, and no bytes escape.
expect {
	document = Pdf.document({
		contents: [Pdf.internal_link("Broken", "missing")],
		language: "en-AU",
		title: "Broken",
	})

	match Pdf.to_bytes(document) {
		Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 }))) => True
		_ => False
	}
}

## White-box twins over a realistic claimed plan: text, an alpha raster
## figure, URI and internal links, an outline, and page labels. Each twin
## differs from the prepared plan in exactly one lowered fact or one prepared
## text fact and must be rejected with its own ledger requirement.
archive_twin_document : Document
archive_twin_document = {
	image = Image.Source.rgb8({
		alpha: PackedAlpha({ bytes: [0, 64, 128, 255], row_stride: 2 }),
		dimensions: { height: 2, width: 2 },
		pixels: [20, 90, 140, 240, 180, 40, 40, 160, 90, 245, 245, 240],
		row_stride: 6,
	})
	Pdf.document({
		contents: [
			Pdf.destination_heading("start", 1, "Archive twins"),
			Pdf.figure(Scene.drawing({}).image(image, Layout.rect(0, 0, 120, 120)), "A two by two translucent raster", Pdf.no_caption),
			Pdf.link("Specification", "https://example.com/pdfa"),
			Pdf.internal_link("Back to start", "start"),
		],
		language: "en-AU",
		title: "Archive twins",
	})
		.with_outline([{ depth: 0, destination: "start", open: True, title: "Start" }])
		.with_page_labels([{ prefix: "T-", start_number: 1, start_page: 0, style: DecimalArabic }])
}

archive_twin_options : Pdf.Options
archive_twin_options = Pdf.Options.with_profile(Pdf.Options.default, Pdf.Profile.Archive)

archive_twin_packet : Str -> KernelXmp.Packet
archive_twin_packet = |title| match KernelMetadata.validate({ created: Omitted, language: "en-AU", modified: Omitted, title }, standard_metadata_limits) {
	Ok(validated) => match KernelXmp.Packet.build_identified(validated.facts, PdfA4Identification, standard_xmp_bytes) {
		Ok(packet) => packet
		Err(_) => {
			crash "archive twin packet failed"
		}
	}
	Err(_) => {
		crash "archive twin metadata failed"
	}
}

archive_twin_pipeline : Pdf.Options -> KernelFacadeOutput.Plan
archive_twin_pipeline = |options| {
	font = match selected_font(options) {
		Ok(value) => value
		Err(_) => {
			crash "archive twin font failed"
		}
	}
	facts = WithDocumentFacts({
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		profile: Color.ProfileId.from_index(0),
		registry_name: KernelMetadata.icc_registry_name,
		language: "en-AU",
		xmp: KernelXmp.Packet.bytes(archive_twin_packet("Archive twins")),
	})
	match KernelFacadePipeline.Plan.build_with_facts(Document.normalize(archive_twin_document), font, options.theme, layout_page_size(A4), standard_font_descriptor, facts, standard_pipeline_limits) {
		Ok(pipeline) => KernelFacadePipeline.Plan.output(pipeline)
		Err(_) => {
			crash "archive twin pipeline failed"
		}
	}
}

ArchiveTwinOutcome : [Accepted, Rejected(KernelPdfA4.Requirement)]

## Validate one white-box store mutation of the claimed twin plan.
archive_twin_lowered : (KernelObject.Store -> KernelObject.Store) -> ArchiveTwinOutcome
archive_twin_lowered = |mutate| {
	plan = KernelFacadeOutput.Plan.structure(archive_twin_pipeline(archive_twin_options))
	store = mutate(KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan)))
	builder = KernelObject.init(archive_twin_store_limits)
	sealed = match KernelSeal.seal({ ..builder, store }) {
		Ok(value) => value
		Err(_) => {
			crash "archive twin mutation broke the sealed store shape"
		}
	}
	match KernelPdfA4.validate_lowered(StaticPdfA4Claim, { packet: archive_twin_packet("Archive twins"), root: KernelStructure.Plan.root(plan), sealed }) {
		Ok(_) => Accepted
		Err(found) => Rejected(found.requirement)
	}
}

archive_twin_store_limits : KernelObject.Limits
archive_twin_store_limits = {
	max_array_items: 10000000,
	max_byte_string_bytes: 100000000,
	max_byte_strings: 10000000,
	max_dictionary_entries: 10000000,
	max_direct_depth: 64,
	max_name_bytes: 10000000,
	max_names: 10000000,
	max_objects: 10000000,
	max_payload_bytes: 1000000000,
	max_payloads: 10000000,
	max_streams: 10000000,
	max_text_string_bytes: 100000000,
	max_text_strings: 10000000,
	max_values: 10000000,
}

## Replace the spelling of the first interned name equal to `from`.
archive_twin_rename : Str, Str -> (KernelObject.Store -> KernelObject.Store)
archive_twin_rename = |from, to| |store| {
	var $names = store.names
	var $index = 0
	var $done = False
	while !$done and $index < $names.len() {
		if KernelLex.Name.bytes(twin_at($names, $index)) == Str.to_utf8(from) {
			replacement = match KernelLex.Name.from_bytes(Str.to_utf8(to)) {
				Ok(name) => name
				Err(_) => {
					crash "archive twin replacement name is invalid"
				}
			}
			$names = match $names.set($index, replacement) {
				Ok(updated) => updated
				Err(_) => $names
			}
			$done = True
		}
		$index = $index + 1
	}
	{ ..store, names: $names }
}

## Rewrite the value of every dictionary entry keyed `key`.
archive_twin_rewrite : Str, KernelObject.Value -> (KernelObject.Store -> KernelObject.Store)
archive_twin_rewrite = |key, value| |store| {
	var $values = store.values
	var $entry = 0
	while $entry < store.dictionary_entries.len() {
		entry = twin_at(store.dictionary_entries, $entry)
		if KernelLex.Name.bytes(twin_at(store.names, KernelObject.NameId.index(entry.key))) == Str.to_utf8(key) {
			$values = match $values.set(KernelObject.ValueId.index(entry.value), value) {
				Ok(updated) => updated
				Err(_) => $values
			}
		}
		$entry = $entry + 1
	}
	{ ..store, values: $values }
}

## The unmutated claimed plan is eligible.
expect archive_twin_lowered(|store| store) == Accepted

## Annotation flags: a hidden or unprintable link is rejected.
expect archive_twin_lowered(archive_twin_rewrite("F", Integer(0))) == Rejected(AnnotationFlags)
	and archive_twin_lowered(archive_twin_rewrite("F", Integer(6))) == Rejected(AnnotationFlags)
		and archive_twin_lowered(archive_twin_rewrite("F", Integer(4 + 32))) == Rejected(AnnotationFlags)

## Actions: a non-whitelisted action type, and a URI action retyped as a
## non-link annotation.
expect archive_twin_lowered(archive_twin_rename("URI", "Launch")) == Rejected(Actions)
	and archive_twin_lowered(archive_twin_rename("Link", "Widget")) == Rejected(AnnotationTypes)

## Images: interpolation, an unsupported bit depth, and OPI data.
expect archive_twin_lowered(archive_twin_rewrite("BitsPerComponent", Integer(3))) == Rejected(ImageDictionary)
	and archive_twin_lowered(archive_twin_rename("BitsPerComponent", "Interpolate")) == Rejected(ImageDictionary)
		and archive_twin_lowered(archive_twin_rename("Width", "OPI")) == Rejected(ImageDictionary)

## Fonts: a simple font subtype, a non-FontFile2 program, and a CIDFont
## without CIDToGIDMap.
expect archive_twin_lowered(archive_twin_rename("Type0", "TrueType")) == Rejected(FontDictionary)
	and archive_twin_lowered(archive_twin_rename("FontFile2", "FontFile3")) == Rejected(FontEmbedding)
		and archive_twin_lowered(archive_twin_rename("CIDToGIDMap", "CIDToGIDMapz")) == Rejected(CompositeFont)

## Package exclusions reachable as keys anywhere in the plan.
expect archive_twin_lowered(archive_twin_rename("Lang", "JS")) == Rejected(Actions)
	and archive_twin_lowered(archive_twin_rename("Lang", "OC")) == Rejected(OptionalContent)
		and archive_twin_lowered(archive_twin_rename("Lang", "AF")) == Rejected(EmbeddedFiles)
			and archive_twin_lowered(archive_twin_rename("Lang", "PresSteps")) == Rejected(Presentations)
				and archive_twin_lowered(archive_twin_rename("Lang", "Ref")) == Rejected(ReferenceXObject)
					and archive_twin_lowered(archive_twin_rename("Lang", "TR")) == Rejected(GraphicsState)
						and archive_twin_lowered(archive_twin_rename("Lang", "NeedsRendering")) == Rejected(InteractiveForms)

## Stream dictionaries must not reference external file data.
expect archive_twin_lowered(archive_twin_rename("Length1", "FFilter")) == Rejected(StreamExternal)

## Profile-stage twins over the prepared text facts of the same plan.
expect {
	facts = KernelFacadeOutput.Plan.text_facts(archive_twin_pipeline(archive_twin_options))
	clean = KernelPdfA4.validate_text(StaticPdfA4Claim, facts)
	bom = KernelPdfA4.validate_text(StaticPdfA4Claim, { ..facts, mappings: facts.mappings.append([{ cid: 1, scalars: [0xFEFF] }]) })
	private = KernelPdfA4.validate_text(StaticPdfA4Claim, { ..facts, actual_text: PrivateUseInRun(0) })
	clean.is_ok()
		and bom == Err({ position: facts.mappings.map(|font| font.len()).sum(), requirement: ToUnicodeValues })
			and private == Err({ position: 0, requirement: ActualTextPrivateUse })
}

twin_at : List(a), U64 -> a
twin_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "archive twin index escaped"
	}
}

## Public containers lower to nested PDF 2.0 grouping elements in authored
## order, and every tagged facade document asks readers to display its
## metadata title.
expect {
	document = Pdf.document({
		contents: [
			Pdf.title("Grouped"),
			Pdf.part([Pdf.section([Pdf.heading(1, "One"), Pdf.division([Pdf.paragraph("Inside")])])]),
		],
		language: "en-AU",
		title: "Grouped",
	})
	bytes = Pdf.to_bytes(document)?
	text = Str.from_utf8_lossy(bytes)

	text.contains("/S /Part ") and text.contains("/S /Sect ") and text.contains("/S /Div ") and text.contains("/S /H1 ") and text.contains("/ViewerPreferences << /DisplayDocTitle true >>")
}

## Container depth and emptiness reject with stable feature codes and the
## compact authored path of the offending container; no bytes are emitted.
expect {
	var $block = Pdf.paragraph("Leaf")
	var $depth = 0
	while $depth < 17 {
		$block = Pdf.section([$block])
		$depth = $depth + 1
	}
	deep = Pdf.document({ contents: [Pdf.title("Deep"), $block], language: "en-AU", title: "Deep" })
	empty = Pdf.document({ contents: [Pdf.paragraph("Lead"), Pdf.section([Pdf.paragraph("Kept"), Pdf.division([])])], language: "en-AU", title: "Empty" })
	deep_rejected = match Pdf.to_bytes(deep) {
		Err(InvalidDocument({ diagnostics: [{ code: BudgetExceeded, details: [path], feature: Feature(code), stage: AuthoringValidation, .. }], .. })) => code == "semantics.container_depth" and path == "contents[1]${Str.repeat(".contents[0]", 16)}"
		_ => False
	}
	empty_rejected = match Pdf.to_bytes(empty) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: [path], feature: Feature(code), .. }], .. })) => code == "semantics.empty_container" and path == "contents[1].contents[1]"
		_ => False
	}
	deep_rejected and empty_rejected
}

## Rich paragraphs lower each inline to its PDF 2.0 role inside one `P`,
## with `/Lang` on language spans and `/E` on expansions, and an inline link
## gains a link annotation owned by its `Link` element.
expect {
	document = Pdf.document({
		contents: [
			Pdf.section([
				Pdf.rich_paragraph([
					Pdf.text("Revenue rose "),
					Pdf.strong([Pdf.text("5.0%")]),
					Pdf.text(" under "),
					Pdf.expansion("GST", "Goods and Services Tax"),
					Pdf.text(" at "),
					Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
					Pdf.text("; see "),
					Pdf.inline_link([Pdf.emphasis([Pdf.text("the report")])], "https://example.org/report"),
					Pdf.text(" and "),
					Pdf.code("WMS-7"),
					Pdf.text(" in "),
					Pdf.quote([Pdf.text("“quotes”")]),
					Pdf.text("."),
				]),
			]),
		],
		language: "en-AU",
		title: "Rich",
	})
	bytes = Pdf.to_bytes(document)?
	text = Str.from_utf8_lossy(bytes)

	text.contains("/S /Sect ") and text.contains("/S /Strong ") and text.contains("/S /Em ") and text.contains("/S /Code ") and text.contains("/S /Quote ") and text.contains("/S /Link ") and text.contains("/Lang <FEFF00660072>") and text.contains("/E <FEFF") and text.contains("/Subtype /Link")
}

## Inline rejections carry a stable dotted code and the inline's authored
## path below its paragraph; no bytes are emitted.
expect {
	nested = Pdf.document({
		contents: [Pdf.paragraph("Lead"), Pdf.section([Pdf.rich_paragraph([Pdf.inline_link([Pdf.text("a "), Pdf.inline_link([Pdf.text("b")], "https://example.org")], "https://example.org")])])],
		language: "en-AU",
		title: "Nested link",
	})
	empty = Pdf.document({ contents: [Pdf.rich_paragraph([Pdf.text("Lead "), Pdf.strong([])])], language: "en-AU", title: "Empty inline" })
	nested_rejected = match Pdf.to_bytes(nested) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: [path], feature: Feature(feature), .. }], .. })) => feature == "semantics.nested_link" and path == "contents[1].contents[0].inlines[0].inlines[1]"
		_ => False
	}
	empty_rejected = match Pdf.to_bytes(empty) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: [path], feature: Feature(feature), .. }], .. })) => feature == "semantics.inline_empty" and path == "contents[0].inlines[1]"
		_ => False
	}
	nested_rejected and empty_rejected
}

## Lists lower to `L > LI > (Lbl, LBody)` with a typed `ListNumbering` on
## every `L`, including the legacy plain-text bullets; items hold paragraphs,
## rich paragraphs, and nested lists; an explicit line break splits a rich
## paragraph's lines without a painted glyph.
expect {
	item = |text| Pdf.list_item([Pdf.paragraph(text)])
	document = Pdf.document({
		contents: [
			Pdf.bullets(["Legacy"]),
			Pdf.numbered_list(
				{ start: 1, style: LowerRoman },
				[
					Pdf.list_item([Pdf.rich_paragraph([Pdf.text("First"), Pdf.line_break, Pdf.strong([Pdf.text("second line")])]), Pdf.bullet_list([item("Nested")])]),
					item("Two"),
				],
			),
			Pdf.keep_with_next(Required, Pdf.paragraph("Kept")),
			Pdf.keep_together([Pdf.paragraph("A"), Pdf.spacer(Layout.Unit.points(12)), Pdf.paragraph("B")]),
			Pdf.page_break,
			Pdf.paragraph("Next page"),
		],
		language: "en-AU",
		title: "Lists",
	})
	bytes = Pdf.to_bytes(document)?
	text = Str.from_utf8_lossy(bytes)

	text.contains("/A << /ListNumbering /Disc /O /List >>") and text.contains("/A << /ListNumbering /LowerRoman /O /List >>") and text.contains("/S /LBody ") and text.contains("/Count 2")
}

## List, break, and keep rejections carry stable codes and authored paths.
expect {
	check = |contents, expected_feature, expected_path| match Pdf.to_bytes(Pdf.document({ contents, language: "en-AU", title: "Rejected" })) {
		Err(InvalidDocument({ diagnostics: [{ details: [path, ..], feature: Feature(feature), .. }], .. })) => feature == expected_feature and path == expected_path
		_ => False
	}
	check([Pdf.paragraph("Lead"), Pdf.bullet_list([Pdf.list_item([])])], "semantics.list_item_empty", "contents[1].items[0]")
		and check([Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("One"), Pdf.heading(2, "Nope")])])], "semantics.list_item_content", "contents[0].items[0].contents[1]")
			and check([Pdf.paragraph("A"), Pdf.page_break, Pdf.page_break, Pdf.paragraph("B")], "layout.page_break_position", "contents[2]")
				and check([Pdf.paragraph("A"), Pdf.keep_together([Pdf.paragraph("B"), Pdf.page_break, Pdf.paragraph("C")])], "layout.keep_conflict", "contents[1].contents[1]")
					and check([Pdf.rich_paragraph([Pdf.text("A"), Pdf.line_break])], "semantics.line_break_position", "contents[0].inlines[1]")
						and check([Pdf.keep_with_next(Required, Pdf.paragraph("A")), Pdf.page_break, Pdf.paragraph("B")], "layout.keep_conflict", "contents[0]")
							and check([Pdf.numbered_list({ start: 0, style: UpperAlpha }, [Pdf.list_item([Pdf.paragraph("A")])])], "semantics.list_numbering", "contents[0]")
}

## A public table lowers `Table > THead/TBody > TR > TH/TD` with typed
## `Scope`, `ColSpan`, identifiers, and `Headers`, and a table continued on
## a second page repaints its header row as a pagination artifact.
expect {
	row = |code| Pdf.row([Pdf.header_cell(Row, [Pdf.text(code)]), Pdf.cell([Pdf.text("Standing desk frame, twin motor")]), Pdf.cell([Pdf.text("2,756.00")])])
	document = Pdf.document({
		contents: [
			Pdf.table({
				body_rows: List.repeat(row("HF-DSK-140"), 60),
				caption: Pdf.caption("Items"),
				columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }, { align: End, width: Fixed(Layout.Unit.points(80)) }],
				footer_rows: [Pdf.row([Pdf.spanning(2, Pdf.header_cell(Row, [Pdf.text("Total")])), Pdf.cell([Pdf.text("165,360.00")])])],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Code")]), Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Amount")])])],
				row_split: KeepRows,
			}),
		],
		language: "en-AU",
		title: "Table",
	})
	bytes = Pdf.to_bytes(document)?
	contains = |needle| {
		pattern = Str.to_utf8(needle)
		var $index = 0
		var $found = False
		while !$found and $index + pattern.len() <= bytes.len() {
			$found = bytes.sublist({ start: $index, len: pattern.len() }) == pattern
			$index = $index + 1
		}
		$found
	}

	contains("/S /THead") and contains("/S /TFoot") and contains("/ColSpan 2") and contains("/Scope /Column") and contains("/Headers [<63303030303032> <63303030303034>]") and contains("/IDTree")
}

## Table rejections are located: the row whose spans do not sum to the
## column count, and a cell that spans rows.
expect {
	columns = [{ align: Start, width: Content }, { align: Start, width: Share(1) }]
	header = Pdf.row([Pdf.header_cell(Column, [Pdf.text("A")]), Pdf.header_cell(Column, [Pdf.text("B")])])
	table = |rows| Pdf.document({ contents: [Pdf.table({ body_rows: rows, caption: Pdf.no_caption, columns, footer_rows: [], header_rows: [header], row_split: KeepRows })], language: "en-AU", title: "Table" })
	grid = match Pdf.to_bytes(table([Pdf.row([Pdf.cell([Pdf.text("x")])])])) {
		Err(InvalidDocument({ diagnostics: [{ code: InvalidRelationship, details: ["contents[0].table.body_rows[0]"], feature: Feature("table.grid_mismatch"), .. }], .. })) => True
		_ => False
	}
	spanned = match Pdf.to_bytes(table([Pdf.row([Pdf.row_spanning(2, Pdf.cell([Pdf.text("x")])), Pdf.cell([Pdf.text("y")])])])) {
		Err(InvalidDocument({ diagnostics: [{ code: FeatureUnavailable, details: ["contents[0].table.body_rows[0].cells[0]"], feature: Feature("table.row_span"), .. }], .. })) => True
		_ => False
	}
	grid and spanned
}

## The default preparation-report budget: 65,536 entries and 4 MiB of
## materialized paths and texts.
default_report_budget : Pdf.ReportBudget
default_report_budget = { max_entries: 65536, max_text_bytes: 4194304 }

## Materialize the preparation report from its compact facts. The entry
## count is computed from scalar facts and checked against the budget
## before any path or text is materialized, so materialization work is
## bounded by the budget; the text bytes are checked once materialized.
## Exceeding either is `report.budget_exceeded`: an explicit error, never
## a report with fewer entries or obligations. Leaf paths are computed in
## one linear pass; each is shared by that leaf's entries.
build_report : Document.NormalizedAuthoring, [Facts(KernelFacadeReport.Facts), NoFacts], Pdf.ReportBudget -> Try(Pdf.Report, Pdf.Error)
build_report = |normalized, collected, budget| {
	facts = match collected {
		Facts(value) => value
		NoFacts => { blocks: [], coverage: [], layout: { panels: [], relaxations: [], repeats: [], scales: [], splits: [] }, pages: [1] }
	}
	inline_counts = count_inline_entries(normalized)
	link_blocks = count_link_blocks(normalized)
	obligation_count = 2 + normalized.figures.len() + normalized.tables.len() + normalized.customs.len() + link_blocks + inline_counts.links + inline_counts.languages + inline_counts.expansions
	alternative_count = normalized.figures.len() + inline_counts.languages + inline_counts.expansions
	outcome_count = facts.layout.relaxations.len() + normalized.figures.len() + facts.layout.repeats.len() + facts.layout.splits.len() + facts.layout.panels.len()
	entries = facts.pages.len() + normalized.blocks.len() + alternative_count + outcome_count + facts.coverage.len() + obligation_count
	if entries > budget.max_entries {
		return Err(report_budget_error("entries", entries, budget.max_entries))
	}
	paths = leaf_paths(normalized)
	path_at = |block| match paths.get(block) {
		Ok(value) => value
		Err(OutOfBounds) => crash "report leaf path escaped"
	}
	var $pages = List.with_capacity(facts.pages.len())
	var $page = 0
	for fragments in facts.pages {
		$pages = $pages.append({ fragments, page: $page + 1 })
		$page = $page + 1
	}
	var $blocks = List.with_capacity(normalized.blocks.len())
	var $cell = 0
	var $index = 0
	for record in normalized.blocks {
		span = match facts.blocks.get($index) {
			Ok(value) => value
			Err(OutOfBounds) => { first_page: U64.highest, fragments: 0, last_page: 0 }
		}
		is_cell = $cell < normalized.cells.len() and (match normalized.cells.get($cell) {
			Ok(cell) => cell.block == $index
			Err(OutOfBounds) => False
		})
		role = if is_cell {
			kind = match normalized.cells.get($cell) {
				Ok(cell) => cell.kind
				Err(OutOfBounds) => DataCell
			}
			$cell = $cell + 1
			match kind {
				DataCell => "TD"
				HeaderCell(_) => "TH"
			}
		} else {
			leaf_role(normalized, record)
		}
		first = if span.fragments == 0 0 else span.first_page + 1
		last = if span.fragments == 0 0 else span.last_page + 1
		$blocks = $blocks.append({ first_page: first, fragments: span.fragments, last_page: last, path: path_at($index), role })
		$index = $index + 1
	}
	var $alternatives = List.with_capacity(alternative_count)
	var $outcomes = List.with_capacity(outcome_count)
	var $obligations = List.with_capacity(obligation_count)
	$obligations = $obligations.append({ obligation: ReadingOrderMeaningful, path: "document" })
	$obligations = $obligations.append({ obligation: LanguageAccurate, path: "document" })

	## Figures, in figure order, with their alternative text, their fit
	## outcome, and their alternative-text obligation.
	$index = 0
	for record in normalized.blocks {
		match record.kind {
			Figure(figure_index) => match normalized.figures.get(figure_index) {
				Ok(figure) => {
					path = path_at($index)
					scale = facts.layout.scales.get(figure_index) ?? 1000
					fit = match figure.fit {
						ExactFit => Exact
						ScaleFit(_) => ScaleToFit
					}
					$alternatives = $alternatives.append({ kind: Alternative, path, text: figure.alternative })
					$outcomes = $outcomes.append(FigureScale({ fit, path, scale }))
					$obligations = $obligations.append({ obligation: AlternativeTextMeaningful, path })
				}
				Err(OutOfBounds) => {}
			}
			Link(_) | InternalLink(_) => {
				$obligations = $obligations.append({ obligation: LinkPurposeMeaningful, path: path_at($index) })
			}
			RichParagraph(paragraph) => match normalized.rich_paragraphs.get(paragraph) {
				Ok(rich) => {
					var $inline = rich.inlines
					while $inline < rich.inlines + rich.length {
						match normalized.inlines.get($inline) {
							Ok(inline) => match inline.kind {
								Link(_) | InternalLink(_) => {
									$obligations = $obligations.append({ obligation: LinkPurposeMeaningful, path: inline_path(normalized, $index, AtInline($inline)) })
								}
								InLanguage(tag) => {
									path = inline_path(normalized, $index, AtInline($inline))
									$alternatives = $alternatives.append({ kind: Language, path, text: tag })
									$obligations = $obligations.append({ obligation: LanguageAccurate, path })
								}
								Expansion(expanded) => {
									path = inline_path(normalized, $index, AtInline($inline))
									$alternatives = $alternatives.append({ kind: Expansion, path, text: expanded })
									$obligations = $obligations.append({ obligation: ExpansionAccurate, path })
								}
								_ => {}
							}
							Err(OutOfBounds) => {}
						}
						$inline = $inline + 1
					}
				}
				Err(OutOfBounds) => {}
			}
			_ => {}
		}
		$index = $index + 1
	}

	## Tables and custom blocks, by their group paths.
	var $group = 0
	for group in normalized.groups {
		match group.kind {
			Table(_) => {
				$obligations = $obligations.append({ obligation: TableHeadersMeaningful, path: group_path(normalized.groups, $group) })
			}
			Custom(_) => {
				$obligations = $obligations.append({ obligation: ReadingOrderMeaningful, path: group_path(normalized.groups, $group) })
			}
			_ => {}
		}
		$group = $group + 1
	}
	for relaxation in facts.layout.relaxations {
		path = match relaxation.unit {
			LeafUnit(block) => path_at(block)
			RowUnit(group) => group_path(normalized.groups, group)
		}
		$outcomes = $outcomes.append(PreferenceRelaxed({ page: relaxation.page + 1, path, preference: relaxation.rank }))
	}
	for repeat in facts.layout.repeats {
		$outcomes = $outcomes.append(RepeatedHeader({ page: repeat.page + 1, path: group_path(normalized.groups, repeat.group), rows: repeat.rows }))
	}
	for split in facts.layout.splits {
		$outcomes = $outcomes.append(RowContinued({ page: split.page + 1, path: group_path(normalized.groups, split.group) }))
	}
	for panel in facts.layout.panels {
		match normalized.customs.get(panel.custom) {
			Ok(custom) => {
				$outcomes = $outcomes.append(CustomBlockPlaced({ height: custom.height, name: custom.name, page: panel.page + 1, path: group_path(normalized.groups, custom.group) }))
			}
			Err(OutOfBounds) => {}
		}
	}
	var $coverage = List.with_capacity(facts.coverage.len())
	for covered in facts.coverage {
		$coverage = $coverage.append({ font: covered.font, path: path_at(covered.block), scalars: covered.scalars, script: covered.script })
	}
	report = {
		facts: {
			alternatives: $alternatives,
			blocks: $blocks,
			coverage: $coverage,
			language: normalized.language,
			outcomes: $outcomes,
			pages: $pages,
			title: normalized.metadata_title,
		},
		obligations: $obligations,
	}
	text_bytes = report_text_bytes(report)
	if text_bytes > budget.max_text_bytes {
		return Err(report_budget_error("text bytes", text_bytes, budget.max_text_bytes))
	}
	Ok(report)
}

report_budget_error : Str, U64, U64 -> Pdf.Error
report_budget_error = |dimension, required, limit| InvalidDocument(located_batch(BudgetExceeded, "report.budget_exceeded", "The preparation report needs ${required.to_str()} ${dimension} but its budget allows ${limit.to_str()}; no report entry or obligation is omitted to fit, so no report and no prepared document are returned.", []))

## The bytes of every materialized path and text in a report.
report_text_bytes : Pdf.Report -> U64
report_text_bytes = |report| {
	facts = report.facts
	var $bytes = facts.title.count_utf8_bytes() + facts.language.count_utf8_bytes()
	for block in facts.blocks {
		$bytes = $bytes + block.path.count_utf8_bytes() + block.role.count_utf8_bytes()
	}
	for alternative in facts.alternatives {
		$bytes = $bytes + alternative.path.count_utf8_bytes() + alternative.text.count_utf8_bytes()
	}
	for outcome in facts.outcomes {
		$bytes = $bytes + match outcome {
			CustomBlockPlaced({ height: _, name, page: _, path }) => path.count_utf8_bytes() + name.count_utf8_bytes()
			FigureScale({ fit: _, path, scale: _ }) => path.count_utf8_bytes()
			PreferenceRelaxed({ page: _, path, preference: _ }) => path.count_utf8_bytes()
			RepeatedHeader({ page: _, path, rows: _ }) => path.count_utf8_bytes()
			RowContinued({ page: _, path }) => path.count_utf8_bytes()
		}
	}
	for covered in facts.coverage {
		$bytes = $bytes + covered.path.count_utf8_bytes() + covered.script.count_utf8_bytes()
	}
	for obligation in report.obligations {
		$bytes = $bytes + obligation.path.count_utf8_bytes()
	}
	$bytes
}

## Inline links, nested languages, and expansions across rich paragraphs.
count_inline_entries : Document.NormalizedAuthoring -> { expansions : U64, languages : U64, links : U64 }
count_inline_entries = |normalized| {
	var $links = 0
	var $languages = 0
	var $expansions = 0
	for inline in normalized.inlines {
		match inline.kind {
			Link(_) | InternalLink(_) => {
				$links = $links + 1
			}
			InLanguage(_) => {
				$languages = $languages + 1
			}
			Expansion(_) => {
				$expansions = $expansions + 1
			}
			_ => {}
		}
	}
	{ expansions: $expansions, languages: $languages, links: $links }
}

count_link_blocks : Document.NormalizedAuthoring -> U64
count_link_blocks = |normalized| {
	var $count = 0
	for record in normalized.blocks {
		match record.kind {
			Link(_) | InternalLink(_) => {
				$count = $count + 1
			}
			_ => {}
		}
	}
	$count
}

## The structure role of a leaf's own element (table cells are resolved
## from the cell arena by the caller).
leaf_role : Document.NormalizedAuthoring, Document.NormalizedBlock -> Str
leaf_role = |normalized, record| {
	in_table = record.parent != 0 and (match normalized.groups.get(record.parent - 1) {
		Ok(group) => match group.kind {
			Table(_) => True
			_ => False
		}
		Err(OutOfBounds) => False
	})
	match record.kind {
		Bullet(_) => "LI"
		DestinationHeading({ level, name: _ }) => "H${level.to_str()}"
		DestinationParagraph(_) => "P"
		Figure(_) => "Figure"
		FigureCaption(_) => "Caption"
		Heading(level) => "H${level.to_str()}"
		InternalLink(_) | Link(_) => "Link"
		Paragraph => if in_table "Caption" else "P"
		RichParagraph(_) => "P"
		Title => "Title"
	}
}

## Every leaf's authored path in one pass, O(blocks + groups log groups +
## flow items + path lengths): the linear form of `leaf_path`. A plain
## leaf's position counts the earlier leaves (a legacy bullet list once)
## and the earlier sibling groups, page breaks, spacers, and decorations of
## its parent, taken from forward cursors over those items in block order.
leaf_paths : Document.NormalizedAuthoring -> List(Str)
leaf_paths = |normalized| {
	groups = normalized.groups
	slots = groups.len() + 1
	var $closed = []
	var $group_index = 0
	for group in groups {
		lead = match group.kind {
			LeadRegion => True
			_ => False
		}
		if !lead {
			$closed = $closed.append({ end: group.block_end, parent: group.parent })
		}
		$group_index = $group_index + 1
	}
	ends = $closed.sort_with(|left, right| if left.end < right.end Before else if left.end > right.end After else Same)
	var $siblings = List.repeat(0, slots)
	var $leaves = List.repeat(0, slots)
	var $lists = List.repeat(U64.highest, slots)
	var $group_cursor = 0
	var $break_cursor = 0
	var $spacer_cursor = 0
	var $decoration_cursor = 0
	var $paths = List.with_capacity(normalized.blocks.len())
	var $block = 0
	for record in normalized.blocks {
		while $group_cursor < ends.len() and at(ends, $group_cursor).end <= $block {
			parent = at(ends, $group_cursor).parent
			$siblings = set_at($siblings, parent, at($siblings, parent) + 1)
			$group_cursor = $group_cursor + 1
		}
		while $break_cursor < normalized.page_breaks.len() and at(normalized.page_breaks, $break_cursor).block <= $block {
			parent = at(normalized.page_breaks, $break_cursor).parent
			$siblings = set_at($siblings, parent, at($siblings, parent) + 1)
			$break_cursor = $break_cursor + 1
		}
		while $spacer_cursor < normalized.spacers.len() and at(normalized.spacers, $spacer_cursor).block <= $block {
			parent = at(normalized.spacers, $spacer_cursor).parent
			$siblings = set_at($siblings, parent, at($siblings, parent) + 1)
			$spacer_cursor = $spacer_cursor + 1
		}
		while $decoration_cursor < normalized.decorations.len() and at(normalized.decorations, $decoration_cursor).block <= $block {
			parent = at(normalized.decorations, $decoration_cursor).parent
			$siblings = set_at($siblings, parent, at($siblings, parent) + 1)
			$decoration_cursor = $decoration_cursor + 1
		}
		parent = record.parent
		figure_leaf = if parent == 0 {
			NotFigure
		} else {
			match group_record(groups, parent).kind {
				FigureGroup(_) => match record.kind {
					FigureCaption(_) => CaptionLeaf
					_ => FigureLeaf
				}
				_ => NotFigure
			}
		}

		## Plain leaves count toward their parent's authored positions; a
		## legacy bullet list counts once.
		counted = match record.kind {
			Bullet({ item: _, list }) => if at($lists, parent) == list {
				False
			} else {
				$lists = set_at($lists, parent, list)
				True
			}
			_ => True
		}
		own = at($leaves, parent) + at($siblings, parent)
		position = match record.kind {
			RichParagraph(paragraph) => match normalized.rich_paragraphs.get(paragraph) {
				Ok(rich) => rich.position
				Err(OutOfBounds) => own
			}
			Bullet(_) => if counted own else own - 1
			_ => own
		}
		if counted {
			$leaves = set_at($leaves, parent, at($leaves, parent) + 1)
		}
		path = match figure_leaf {
			NotFigure => child_path(groups, parent, position)
			FigureLeaf => chain_path(groups, parent)
			CaptionLeaf => "${chain_path(groups, parent)}.caption"
		}
		$paths = $paths.append(path)
		$block = $block + 1
	}
	$paths
}

at : List(a), U64 -> a
at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "report index escaped"
}

set_at : List(a), U64, a -> List(a)
set_at = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "report index escaped"
}

## The report's linear leaf paths equal the diagnostic `leaf_path` of every
## leaf across groups, lists, a legacy bullet list, a table, a captioned
## figure, flow items, and a custom block.
expect {
	mark = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 20, 20), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	panel = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 200, 60), Color.srgb8({ blue: 0, green: 0, red: 0 }))
	doc = Pdf.document({
		contents: [
			Pdf.title("Paths"),
			Pdf.bullets(["One", "Two"]),
			Pdf.spacer(Layout.Unit.points(4)),
			Pdf.section([
				Pdf.paragraph("Lead"),
				Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item"), Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Nested")])])])]),
				Pdf.decoration(mark),
				Pdf.figure(mark, "A mark", Pdf.caption("Figure 1.")),
				Pdf.page_break,
				Pdf.rich_paragraph([Pdf.text("Rich")]),
				Pdf.custom_block({ contents: [Pdf.paragraph("Inside"), Pdf.paragraph("Also")], fragmentation: Unsplittable, inset: Layout.Unit.points(4), name: "Box", panel, size: { height: Layout.Unit.points(60), width: Layout.Unit.points(200) } }),
			]),
			Pdf.table({ body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.text("A")]), Pdf.cell([Pdf.text("B")])])], caption: Pdf.caption("Table 1."), columns: [{ align: Start, width: Share(1) }, { align: Start, width: Share(1) }], footer_rows: [], header_rows: [], row_split: KeepRows }),
			Pdf.paragraph("Tail"),
		],
		language: "en-AU",
		title: "Paths",
	})
	normalized = Document.normalize(doc)
	var $index = 0
	var $expected = []
	while $index < normalized.blocks.len() {
		$expected = $expected.append(leaf_path(doc, $index))
		$index = $index + 1
	}
	leaf_paths(normalized) == $expected
}
