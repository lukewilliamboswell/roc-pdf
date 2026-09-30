import Color
import Document
import Font
import Image
import KernelFacadePages
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFont
import KernelPageLayout
import KernelShape
import Layout
import Scene
import Semantics
import Text
import Theme

## Page templates and their furniture (`reference-documents-v6`).
##
## `Static.build` runs before flow: it derives every page kind's flow frame
## and lead region from the templates' fixed region heights, validates each
## region, slot stack, furniture item, and inline, and computes each item's
## vertical position. Nothing it produces depends on a page field's value.
##
## `Plan.resolve` is the second stabilization pass: with the final page
## count it resolves every page field, shapes each distinct furniture line
## once, proves that every reserved width and slot fits, and places each
## text piece and drawing on its page. Furniture text belongs to no
## structure element: its runs carry artifact Unicode sources, appended to
## the document's text sources after the semantic sources.
KernelFacadeFurniture :: [].{
	Dimension : [Inputs, Items, Pieces]

	## `path` values are compact authored template paths, such as
	## `templates.continuation.footer.end[0].inlines[0]`.
	Error : [
		ArithmeticOverflow,

		## A document with page templates has no body block.
		BodyEmpty,

		## A template's regions leave less than one body line of flow.
		BodySpace({ footer : U64, gap : U64, header : U64, lead : U64, line : U64, remaining : I64, template : Str }),

		## A furniture drawing that is not a validated decorative drawing.
		DrawingInvalid({ path : Str, reason : Str }),

		## A resolved page field does not fit its reserved width or slot on
		## `page` (one-based).
		FieldOverflow({ page : U64, path : Str, reserved : U64, value : Str, width : U64 }),

		## An inline other than text, a page field, or a reserved width.
		FurnitureInline({ path : Str }),
		GapNegative({ path : Str }),
		InlineEmpty({ path : Str }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),

		## Furniture text that its selection cannot shape: a script
		## outside the declared set, or a cluster no policy face covers.
		## `path` names the furniture item.
		FurnitureText({ path : Str, reason : [Coverage, Script(Str)] }),

		## A region that reserves no height or holds no furniture.
		RegionEmpty({ path : Str }),

		## Furniture wider or taller than its region or reserved box.
		RegionOverflow({ available : U64, path : Str, required : U64 }),
		Selection(KernelFacadeShape.Error),
		Shape(KernelShape.Error),

		## Slots of one region overlap on `page` (one-based).
		SlotOverlap({ page : U64, path : Str, slots : Str }),
		Sources(KernelFacadeSources.Error),
		UnsupportedThemeFace({ face : U64 }),
	]

	Limits :: { max_inputs : U64, max_items : U64, max_pieces : U64, shape : KernelShape.Limits, sources : KernelFacadeSources.Limits }.{
		make : { max_inputs : U64, max_items : U64, max_pieces : U64, shape : KernelShape.Limits, sources : KernelFacadeSources.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## Which page band a painted piece belongs to: header furniture paints
	## before the page's body text and footer furniture after it.
	Band : [Above, Below]

	## One validated decorative drawing command in drawing-local geometry
	## (origin at the item's bottom-left, y upward). `image` indexes
	## `Plan.images`.
	DrawingCommand : [
		DrawingImage({ image : U64, placement : Layout.Rect }),
		DrawingPath({ fill : [Fill(Color.SourceValue), NoFill], segments : List(Scene.PathSegment), stroke : [NoStroke, Stroke({ color : Color.SourceValue, width : Layout.Unit })] }),
	]

	## One furniture drawing and its extent.
	Drawing : { commands : List(DrawingCommand), height : U64, width : U64 }

	## One painted drawing: its drawing, artifact kind, page, and the
	## absolute position of its bottom-left corner.
	DrawingPaint : { drawing : U64, kind : Scene.PageArtifactKind, origin : Layout.Point, page : U64 }

	## One painted text piece: a contiguous cluster range of shaped furniture
	## run `run`, its source range within that run's source, and its
	## baseline origin. Through the single face a source is one run; under
	## an ordered policy a source is one run per selected face and script
	## segment, and a piece never crosses a run.
	Piece : { band : Band, clusters : Semantics.Range, kind : Scene.PageArtifactKind, origin : Layout.Point, page : U64, run : U64, source : Semantics.TextRange }

	Work : {
		drawing_paints : U64,
		field_resolutions : U64,
		items_shaped : U64,
		sources : U64,
	}

	## The pre-flow template facts. `flow` is the page-layout geometry;
	## nothing else here may influence pagination.
	Static :: { drawings : List(Drawing), flow : KernelFacadePages.FlowTemplate, frame : FrameFacts, images : List(Image.Source), items : List(Item), regions : List(Region), style : Theme.TextStyle, texts : List(TextTemplate) }.{
		build : Document.NormalizedAuthoring, Theme, Layout.Size -> Try(Static, Error)
		build = |authoring, theme, page_size| build_static(authoring, theme, page_size)

		flow : Static -> KernelFacadePages.FlowTemplate
		flow = |plan| plan.flow

		## Every furniture image source, in drawing order.
		images : Static -> List(Image.Source)
		images = |plan| plan.images
	}

	## The ordered policy's selection context for furniture: the body's
	## dense output faces and fonts, which furniture runs reuse, and the
	## registry and policy that select every furniture cluster.
	PolicyFonts : { faces : List(Font.FaceId), fonts : List(KernelFont.Inspection), policy : Font.PolicyId, registry : Font.Registry }

	Plan :: { drawing_paints : List(DrawingPaint), drawings : List(Drawing), extra_fonts : List(KernelFont.Inspection), images : List(Image.Source), pieces : List(Piece), source_base : U64, sources : List(Str), store : Text.Store, style : Theme.TextStyle, work : Work }.{

		## Resolve every page field with the final page count, shape each
		## distinct furniture line, prove every fit, and place all furniture.
		## `source_base` is the number of semantic text sources: furniture
		## source `k` becomes text source `source_base + k`.
		##
		## Furniture text shapes through the single resolved face, or, under
		## an ordered font policy (`PolicyFaces`), selects each cluster's
		## face exactly as body text does. A selected face the body did not
		## use becomes an extra output font after the body's fonts.
		resolve : Static, U64, [PolicyFaces(PolicyFonts), SingleFace(KernelFont.Inspection)], Semantics.Language, U64, Limits -> Try(Plan, Error)
		resolve = |static, pages, font, language, source_base, limits| resolve_plan(static, pages, font, language, source_base, limits)

		drawing_paints : Plan -> List(DrawingPaint)
		drawing_paints = |plan| plan.drawing_paints

		drawings : Plan -> List(Drawing)
		drawings = |plan| plan.drawings

		## Furniture image sources; drawing commands index this list.
		images : Plan -> List(Image.Source)
		images = |plan| plan.images

		pieces : Plan -> List(Piece)
		pieces = |plan| plan.pieces

		source_base : Plan -> U64
		source_base = |plan| plan.source_base

		## The distinct furniture Unicode sources in text-source order.
		sources : Plan -> List(Str)
		sources = |plan| plan.sources

		## Output fonts after the body's under an ordered policy, in first
		## use order; the dense run instance of extra font `k` is the body
		## font count plus `k`. Empty through the single face.
		extra_fonts : Plan -> List(KernelFont.Inspection)
		extra_fonts = |plan| plan.extra_fonts

		## The shaped furniture runs.
		store : Plan -> Text.Store
		store = |plan| plan.store

		style : Plan -> Theme.TextStyle
		style = |plan| plan.style

		work : Plan -> Work
		work = |plan| plan.work
	}
}

## The body frame: its left edge and top edge in page space, and its width.
FrameFacts : { left : U64, top : U64, width : U64 }

TemplateKind : [ContinuationTemplate, FirstTemplate]

Slot : [CenterSlot, EndSlot, StartSlot]

## One present header or footer region: its items (in slot order, each
## stack top to bottom), its offset below the body frame top, and height.
Region : { band : KernelFacadeFurniture.Band, height : U64, items : Semantics.Range, kind : Scene.PageArtifactKind, path : Str, template : TemplateKind, top : U64 }

## One furniture item: its content, height, path, slot, and the offset of
## its top edge below the body frame top.
Item : { content : [DrawingContent(U64), TextContent(U64)], height : U64, path : Str, slot : Slot, top : U64 }

Field : [PageField, TotalField]

## One validated furniture line as parts. Literal scalar counts are counted
## once here.
Part : [
	BoxClose,
	BoxOpen({ align : Document.ReservedAlign, path : Str, width : U64 }),
	FieldPart({ field : Field, path : Str, style : Document.PageFieldStyle }),
	Literal({ scalars : U64, text : Str }),
]

TextTemplate : { fields : Bool, parts : List(Part) }

## One segment of a resolved furniture line: the text outside reserved
## widths, or one reserved width's content, with its first field.
Segment : { box : [Box({ align : Document.ReservedAlign, path : Str, width : U64 }), Free], bytes : Semantics.Range, field : [Field({ path : Str, value : Str }), NoField], scalars : Semantics.Range }

## One resolved text item on one page, before shaping.
Pending : { input : U64, item : U64, page : U64, region : U64, segments : List(Segment) }

build_static : Document.NormalizedAuthoring, Theme, Layout.Size -> Try(KernelFacadeFurniture.Static, KernelFacadeFurniture.Error)
build_static = |authoring, theme, page_size| {
	templates = match authoring.templates {
		NoTemplates => return Err(BodyEmpty)
		Templates(value) => value
	}
	margins = Theme.page_margin(theme)
	page_height = nonnegative(page_size.height)?
	page_width = nonnegative(page_size.width)?
	top_margin = nonnegative(margins.top)?
	bottom_margin = nonnegative(margins.bottom)?
	left_margin = nonnegative(margins.left)?
	right_margin = nonnegative(margins.right)?
	frame_height = checked_sub(page_height, checked_add(top_margin, bottom_margin)?)?
	frame_width = checked_sub(page_width, checked_add(left_margin, right_margin)?)?
	style = Theme.body_style(theme)
	line = nonnegative(style.leading)?
	lead_leaves = match templates.lead {
		NoLead => 0
		Lead(_) => lead_block_end(authoring)
	}
	if lead_leaves >= authoring.blocks.len() {
		return Err(BodyEmpty)
	}
	var $state = { drawings: [], images: [], items: [], regions: [], texts: [] }

	## The first page: header, then the lead region, then the footer.
	first_path = "templates.first"
	first_gap = gap_of(templates.first.gap, first_path)?
	first_header = region_height(templates.first.header, "${first_path}.header")?
	lead_height = match templates.lead {
		NoLead => 0
		Lead(height) => {
			value = if height.raw() <= 0 0 else height.raw().to_u64_wrap()
			if value == 0 {
				return Err(RegionEmpty({ path: "${first_path}.lead" }))
			}
			value
		}
	}
	first_footer = region_height(templates.first.footer, "${first_path}.footer")?
	lead_top = if first_header == 0 0 else checked_add(first_header, first_gap)?
	first_top = if lead_height == 0 lead_top else checked_add(lead_top, checked_add(lead_height, first_gap)?)?
	first_bottom = if first_footer == 0 0 else checked_add(first_footer, first_gap)?
	first_remaining = frame_height.to_i64_wrap() - first_top.to_i64_wrap() - first_bottom.to_i64_wrap()
	if first_remaining < line.to_i64_wrap() {
		return Err(BodySpace({ footer: first_footer, gap: first_gap, header: first_header, lead: lead_height, line, remaining: first_remaining, template: first_path }))
	}

	## Continuation pages: header and footer.
	next_path = "templates.continuation"
	next_gap = gap_of(templates.continuation.gap, next_path)?
	next_header = region_height(templates.continuation.header, "${next_path}.header")?
	next_footer = region_height(templates.continuation.footer, "${next_path}.footer")?
	next_top = if next_header == 0 0 else checked_add(next_header, next_gap)?
	next_bottom = if next_footer == 0 0 else checked_add(next_footer, next_gap)?
	next_remaining = frame_height.to_i64_wrap() - next_top.to_i64_wrap() - next_bottom.to_i64_wrap()
	if next_remaining < line.to_i64_wrap() {
		return Err(BodySpace({ footer: next_footer, gap: next_gap, header: next_header, lead: 0, line, remaining: next_remaining, template: next_path }))
	}

	## Regions in template order; each validates its slots and items.
	$state = add_region($state, templates.first.header, { band: Above, kind: Header, path: "${first_path}.header", template: FirstTemplate, top: 0 }, style)?
	$state = add_region($state, templates.first.footer, { band: Below, kind: Footer, path: "${first_path}.footer", template: FirstTemplate, top: frame_height - first_footer }, style)?
	$state = add_region($state, templates.continuation.header, { band: Above, kind: Header, path: "${next_path}.header", template: ContinuationTemplate, top: 0 }, style)?
	$state = add_region($state, templates.continuation.footer, { band: Below, kind: Footer, path: "${next_path}.footer", template: ContinuationTemplate, top: frame_height - next_footer }, style)?
	first_frame = { height: unit(first_remaining.to_u64_wrap()), top: unit(first_top) }
	next_frame = { height: unit(next_remaining.to_u64_wrap()), top: unit(next_top) }
	lead = if lead_height == 0 NoLead else Lead({ frame: { height: unit(lead_height), top: unit(lead_top) }, leaves: lead_leaves })
	Ok(
		KernelFacadeFurniture.Static.{
			drawings: $state.drawings,
			flow: { continuation: next_frame, first: first_frame, lead },
			frame: { left: left_margin, top: checked_sub(page_height, top_margin)?, width: frame_width },
			images: $state.images,
			items: $state.items,
			regions: $state.regions,
			style,
			texts: $state.texts,
		},
	)
}

StaticState : { drawings : List(KernelFacadeFurniture.Drawing), images : List(Image.Source), items : List(Item), regions : List(Region), texts : List(TextTemplate) }

## The number of leaves in the lead region (group 0).
lead_block_end : Document.NormalizedAuthoring -> U64
lead_block_end = |authoring| match authoring.groups.first() {
	Ok(group) => match group.kind {
		LeadRegion => group.block_end
		_ => 0
	}
	Err(_) => 0
}

gap_of : Layout.Unit, Str -> Try(U64, KernelFacadeFurniture.Error)
gap_of = |gap, path| if gap.raw() < 0 Err(GapNegative({ path: "${path}.gap" })) else Ok(gap.raw().to_u64_wrap())

## A present region reserves positive height and holds at least one item;
## `no_region` reserves nothing.
region_height : Document.NormalizedRegion, Str -> Try(U64, KernelFacadeFurniture.Error)
region_height = |region, path| match region {
	NoRegion => Ok(0)
	Region({ center, end, height, start }) => if height.raw() <= 0 or (center.is_empty() and end.is_empty() and start.is_empty()) Err(RegionEmpty({ path: path })) else Ok(height.raw().to_u64_wrap())
}

add_region : StaticState, Document.NormalizedRegion, { band : KernelFacadeFurniture.Band, kind : Scene.PageArtifactKind, path : Str, template : TemplateKind, top : U64 }, Theme.TextStyle -> Try(StaticState, KernelFacadeFurniture.Error)
add_region = |state, region, at, style| match region {
	NoRegion => Ok(state)
	Region({ center, end, height, start }) => {
		region_height_value = height.raw().to_u64_wrap()
		first_item = state.items.len()
		var $state = state
		$state = add_slot($state, start, StartSlot, "${at.path}.start", { band: at.band, height: region_height_value, top: at.top }, style)?
		$state = add_slot($state, center, CenterSlot, "${at.path}.center", { band: at.band, height: region_height_value, top: at.top }, style)?
		$state = add_slot($state, end, EndSlot, "${at.path}.end", { band: at.band, height: region_height_value, top: at.top }, style)?
		region_record = { band: at.band, height: region_height_value, items: Semantics.Range.from_start_and_length(first_item, $state.items.len() - first_item), kind: at.kind, path: at.path, template: at.template, top: at.top }
		Ok({ ..$state, regions: $state.regions.append(region_record) })
	}
}

## One slot's stack: its items' heights must fit the region; a header's
## stack sits on the region's bottom edge and a footer's hangs from its top
## edge, next to the body flow.
add_slot : StaticState, List(Document.NormalizedFurniture), Slot, Str, { band : KernelFacadeFurniture.Band, height : U64, top : U64 }, Theme.TextStyle -> Try(StaticState, KernelFacadeFurniture.Error)
add_slot = |state, furniture, slot, path, region, style| {
	if furniture.is_empty() {
		return Ok(state)
	}
	var $drawings = state.drawings
	var $images = state.images
	var $texts = state.texts
	var $contents = List.with_capacity(furniture.len())
	var $stack = 0
	var $index = 0
	while $index < furniture.len() {
		item_path = "${path}[${$index.to_str()}]"
		match list_at(furniture, $index) {
			FurnitureText(inlines) => {
				text = text_template(inlines, item_path)?
				height = nonnegative(style.leading)?
				$contents = $contents.append({ content: TextContent($texts.len()), height, path: item_path })
				$texts = $texts.append(text)
				$stack = checked_add($stack, height)?
			}
			FurnitureDrawing(drawing) => {
				validated = validate_drawing(drawing, item_path, $images.len())?
				$contents = $contents.append({ content: DrawingContent($drawings.len()), height: validated.drawing.height, path: item_path })
				$drawings = $drawings.append(validated.drawing)
				$images = List.concat($images, validated.images)
				$stack = checked_add($stack, validated.drawing.height)?
			}
		}
		$index = $index + 1
	}
	if $stack > region.height {
		return Err(RegionOverflow({ available: region.height, path, required: $stack }))
	}
	var $top = match region.band {
		Above => checked_add(region.top, region.height - $stack)?
		Below => region.top
	}
	var $items = state.items
	for content in $contents {
		$items = $items.append({ content: content.content, height: content.height, path: content.path, slot, top: $top })
		$top = checked_add($top, content.height)?
	}
	Ok({ drawings: $drawings, images: $images, items: $items, regions: state.regions, texts: $texts })
}

## A furniture line's inlines: text, page fields, and reserved widths whose
## content is text and page fields. Every text and reserved width is
## non-empty.
text_template : List(Document.NormalizedFurnitureInline), Str -> Try(TextTemplate, KernelFacadeFurniture.Error)
text_template = |inlines, path| {
	if inlines.is_empty() {
		return Err(InlineEmpty({ path: path }))
	}
	var $parts = List.with_capacity(inlines.len())
	var $fields = False
	var $open = NoBox
	for inline in inlines {
		match inline {
			BoxStart({ align, position, width }) => {
				box_path = "${path}.inlines[${position.to_str()}]"
				$open = OpenBox({ path: box_path, used: False })
				$parts = $parts.append(BoxOpen({ align, path: box_path, width: if width.raw() <= 0 0 else width.raw().to_u64_wrap() }))
			}
			BoxEnd => {
				match $open {
					OpenBox({ path: box_path, used: False }) => return Err(InlineEmpty({ path: box_path }))
					_ => {}
				}
				$open = NoBox
				$parts = $parts.append(BoxClose)
			}
			Text({ inner, position, text }) => {
				leaf_path = furniture_path(path, position, inner)
				if text.is_empty() {
					return Err(InlineEmpty({ path: leaf_path }))
				}
				$open = used_box($open)
				$parts = $parts.append(Literal({ scalars: scalar_count(text), text }))
			}
			Field({ field, inner, position, style }) => {
				$open = used_box($open)
				$fields = True
				kind = match field {
					PageNumberField => PageField
					TotalPagesField => TotalField
				}
				$parts = $parts.append(FieldPart({ field: kind, path: furniture_path(path, position, inner), style }))
			}
			Unsupported({ inner, position }) => return Err(FurnitureInline({ path: furniture_path(path, position, inner) }))
		}
	}
	Ok({ fields: $fields, parts: $parts })
}

used_box : [NoBox, OpenBox({ path : Str, used : Bool })] -> [NoBox, OpenBox({ path : Str, used : Bool })]
used_box = |open| match open {
	NoBox => NoBox
	OpenBox({ path, used: _ }) => OpenBox({ path, used: True })
}

furniture_path : Str, U64, [Inner(U64), Outer] -> Str
furniture_path = |path, position, inner| match inner {
	Outer => "${path}.inlines[${position.to_str()}]"
	Inner(index) => "${path}.inlines[${position.to_str()}].inlines[${index.to_str()}]"
}

## A decorative drawing: at least one command; images with positive size
## and paths with a solid fill, a solid stroke of positive width, or both,
## all at or beyond the drawing origin. Groups are not supported in
## furniture. The drawing's extent is its commands' union from the origin.
validate_drawing : Scene.Drawing, Str, U64 -> Try({ drawing : KernelFacadeFurniture.Drawing, images : List(Image.Source) }, KernelFacadeFurniture.Error)
validate_drawing = |drawing, path, image_base| {
	commands = drawing.commands()
	if commands.is_empty() {
		return Err(DrawingInvalid({ path, reason: "it has no commands" }))
	}
	var $converted = List.with_capacity(commands.len())
	var $images = []
	var $width = 0
	var $height = 0
	var $index = 0
	while $index < commands.len() {
		match list_at(commands, $index) {
			AuthorImage({ image, placement }) => {
				if placement.size.width.raw() <= 0 or placement.size.height.raw() <= 0 or placement.origin.x.raw() < 0 or placement.origin.y.raw() < 0 {
					return Err(DrawingInvalid({ path, reason: "an image placement needs a positive size at or beyond the drawing origin" }))
				}
				$width = U64.max($width, (placement.origin.x.raw() + placement.size.width.raw()).to_u64_wrap())
				$height = U64.max($height, (placement.origin.y.raw() + placement.size.height.raw()).to_u64_wrap())
				$converted = $converted.append(DrawingImage({ image: image_base + $images.len(), placement }))
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
						if width.raw() <= 0 {
							return Err(DrawingInvalid({ path, reason: "a stroke needs a positive width" }))
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
					return Err(DrawingInvalid({ path, reason: "a path paints nothing without a fill or a stroke" }))
				}
				bounds = path_bounds(segments)
				match bounds {
					NoPoints => return Err(DrawingInvalid({ path, reason: "a path needs at least one segment beginning with a move or a rectangle" }))
					Bounds({ max_x, max_y, min_x, min_y }) => {
						if min_x - half < 0 or min_y - half < 0 {
							return Err(DrawingInvalid({ path, reason: "a path extends below or left of the drawing origin" }))
						}
						$width = U64.max($width, (max_x + half).to_u64_wrap())
						$height = U64.max($height, (max_y + half).to_u64_wrap())
					}
				}
				$converted = $converted.append(DrawingPath({ fill, segments, stroke }))
			}
			AuthorGroup(_) | AuthorTranslate(_) => return Err(DrawingInvalid({ path, reason: "grouped drawing commands are not supported in furniture" }))
			AuthorText(_) => return Err(DrawingInvalid({ path, reason: "text labels are not supported in furniture drawings; use furniture text" }))
		}
		$index = $index + 1
	}
	if $width == 0 or $height == 0 {
		return Err(DrawingInvalid({ path, reason: "it has no positive extent" }))
	}
	Ok({ drawing: { commands: $converted, height: $height, width: $width }, images: $images })
}

## The bounds of a path's points: control points included, so the extent
## is conservative for curves. A path must begin with a move or rectangle.
path_bounds : List(Scene.PathSegment) -> [Bounds({ max_x : I64, max_y : I64, min_x : I64, min_y : I64 }), NoPoints]
path_bounds = |segments| {
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

## Pass 2: resolve, shape, prove, and place.
resolve_plan : KernelFacadeFurniture.Static, U64, [PolicyFaces(KernelFacadeFurniture.PolicyFonts), SingleFace(KernelFont.Inspection)], Semantics.Language, U64, KernelFacadeFurniture.Limits -> Try(KernelFacadeFurniture.Plan, KernelFacadeFurniture.Error)
resolve_plan = |static, page_count, selection, language, source_base, limits| {
	## The single face is the theme's body face, which is the furniture
	## style's face whatever its registry index.
	check_limit(static.items.len(), limits.max_items, Items)?

	## Resolve every text item on every page into its line string and
	## segments. Static items resolve to the same string on every page and
	## intern to one source.
	var $inputs = []
	var $pending = []
	var $field_resolutions = 0
	var $page = 0
	while $page < page_count {
		template = if $page == 0 FirstTemplate else ContinuationTemplate
		var $region = 0
		while $region < static.regions.len() {
			region = list_at(static.regions, $region)
			if region.template == template {
				var $item = region.items.start()
				while $item < region.items.start() + region.items.length() {
					match list_at(static.items, $item).content {
						DrawingContent(_) => {}
						TextContent(text_index) => {
							text = list_at(static.texts, text_index)
							resolved = resolve_line(text.parts, $page + 1, page_count)
							$field_resolutions = checked_add($field_resolutions, resolved.fields)?
							check_limit(checked_add($inputs.len(), 1)?, limits.max_inputs, Inputs)?
							$pending = $pending.append({ input: $inputs.len(), item: $item, page: $page, region: $region, segments: resolved.segments })
							$inputs = $inputs.append(resolved.text)
						}
					}
					$item = $item + 1
				}
			}
			$region = $region + 1
		}
		$page = $page + 1
	}

	## Every distinct line is analyzed and shaped once, whole: through the
	## single face as one run, or under an ordered policy as one run per
	## selected face and script segment.
	interned = KernelFacadeSources.Plan.build($inputs, limits.sources) ? Sources
	unique = KernelFacadeSources.Plan.sources(interned)
	input_sources = KernelFacadeSources.Plan.input_sources(interned)
	shaped = match selection {
		SingleFace(font) => {
			var $requests = List.with_capacity(unique.len())
			while $requests.len() < unique.len() {
				index = $requests.len()
				$requests = $requests.append({ occurrence: Semantics.OccurrenceId.from_index(index), size: static.style.size, source: Semantics.TextSourceId.from_index(index) })
			}
			options = { direction: LeftToRight, instance: Font.InstanceId.from_index(0), language, script: Font.Script.from_iso15924("Latn"), writing_mode: Horizontal }
			batch = if unique.is_empty() { advances: [], store: empty_store, work: empty_shape_work } else KernelShape.shape_simple_batch(font, unique, options, $requests, limits.shape) ? Shape
			{ batch, extra_fonts: [], run_sources: [], source_runs: [] }
		}
		PolicyFaces(policy) => shape_under_policy(policy, unique, static, input_sources, $pending, language, limits)?
	}
	source_runs = shaped.source_runs

	## The batch identifies a request by an occurrence ordinal; a furniture
	## run's Unicode is its artifact source.
	run_sources = shaped.run_sources
	store = { ..shaped.batch.store, runs: shaped.batch.store.runs.map(|run| { ..run, unicode: ArtifactText(Semantics.TextSourceId.from_index(source_base + (if run_sources.is_empty() run.id.index() else list_at(run_sources, run.id.index())))) }) }

	## Prove fits and place every piece and drawing, page by page.
	var $pieces = []
	var $drawing_paints = []
	var $cursor = 0
	$page = 0
	while $page < page_count {
		template = if $page == 0 FirstTemplate else ContinuationTemplate
		var $region = 0
		while $region < static.regions.len() {
			region = list_at(static.regions, $region)
			if region.template == template {
				measured = measure_region(static, store, source_runs, input_sources, $pending, $cursor, region, $region, $page)?
				placed = place_region(static, store, source_runs, input_sources, $pending, $cursor, region, measured, $page, $pieces, $drawing_paints)?
				$pieces = placed.pieces
				$drawing_paints = placed.drawing_paints
				$cursor = placed.cursor
			}
			$region = $region + 1
		}
		$page = $page + 1
	}
	check_limit($pieces.len(), limits.max_pieces, Pieces)?
	Ok(
		KernelFacadeFurniture.Plan.{
			drawing_paints: $drawing_paints,
			drawings: static.drawings,
			extra_fonts: shaped.extra_fonts,
			images: static.images,
			pieces: $pieces,
			source_base,
			sources: unique.map(|source| source.unicode),
			store,
			style: static.style,
			work: {
				drawing_paints: $drawing_paints.len(),
				field_resolutions: $field_resolutions,
				items_shaped: $pending.len(),
				sources: unique.len(),
			},
		},
	)
}

empty_store : Text.Store
empty_store = { clusters: [], glyph_indices: [], glyphs: [], runs: [], substitutions: [], transformations: [] }

empty_shape_work : KernelShape.Work
empty_shape_work = { cluster_visits: 0, glyph_visits: 0, metric_reads: 0, scalar_visits: 0, script_run_visits: 0, utf8_bytes: 0 }

## One resolved line: its text, its segments, and how many fields resolved.
resolve_line : List(Part), U64, U64 -> { fields : U64, segments : List(Segment), text : Str }
resolve_line = |parts, page, pages| {
	var $pieces = List.with_capacity(parts.len())
	var $segments = []
	var $bytes = 0
	var $scalars = 0
	var $segment_bytes = 0
	var $segment_scalars = 0
	var $box = Free
	var $field = NoField
	var $fields = 0
	for part in parts {
		match part {
			Literal({ scalars, text }) => {
				$pieces = $pieces.append(text)
				$bytes = $bytes + text.count_utf8_bytes()
				$scalars = $scalars + scalars
			}
			FieldPart({ field, path, style }) => {
				value = KernelFacadeSemantics.number_text(Document.page_field_number_style(style), if field == PageField page else pages)
				$pieces = $pieces.append(value)
				length = value.count_utf8_bytes()
				$bytes = $bytes + length
				$scalars = $scalars + length
				$fields = $fields + 1
				$field = match $field {
					NoField => Field({ path, value })
					found => found
				}
			}
			BoxOpen({ align, path, width }) => {
				if $bytes > $segment_bytes {
					$segments = $segments.append({ box: $box, bytes: span($segment_bytes, $bytes), field: $field, scalars: span($segment_scalars, $scalars) })
				}
				$segment_bytes = $bytes
				$segment_scalars = $scalars
				$box = Box({ align, path, width })
				$field = NoField
			}
			BoxClose => {
				$segments = $segments.append({ box: $box, bytes: span($segment_bytes, $bytes), field: $field, scalars: span($segment_scalars, $scalars) })
				$segment_bytes = $bytes
				$segment_scalars = $scalars
				$box = Free
				$field = NoField
			}
		}
	}
	if $bytes > $segment_bytes {
		$segments = $segments.append({ box: $box, bytes: span($segment_bytes, $bytes), field: $field, scalars: span($segment_scalars, $scalars) })
	}
	var $text = Str.with_capacity($bytes)
	for piece in $pieces {
		$text = $text.concat(piece)
	}
	{ fields: $fields, segments: $segments, text: $text }
}

## The measured width of every item of one region on one page, and its
## slots' widths; every reserved width and the region width are proven.
measure_region : KernelFacadeFurniture.Static, Text.Store, List(Semantics.Range), List(Semantics.TextSourceId), List(Pending), U64, Region, U64, U64 -> Try(List(U64), KernelFacadeFurniture.Error)
measure_region = |static, store, source_runs, input_sources, pending, cursor, region, region_index, page| {
	width = static.frame.width
	var $widths = List.with_capacity(region.items.length())
	var $cursor = cursor
	var $item = region.items.start()
	while $item < region.items.start() + region.items.length() {
		record = list_at(static.items, $item)
		item_width = match record.content {
			DrawingContent(drawing) => {
				value = list_at(static.drawings, drawing).width
				if value > width {
					return Err(RegionOverflow({ available: width, path: record.path, required: value }))
				}
				value
			}
			TextContent(_) => {
				entry = list_at(pending, $cursor)
				if entry.item != $item or entry.page != page or entry.region != region_index {
					crash "furniture pending order escaped"
				}
				$cursor = $cursor + 1
				runs = runs_of(source_runs, list_at(input_sources, entry.input).index())
				var $total = 0
				var $free_field = NoField
				for segment in entry.segments {
					segment_width = runs_width(store, runs, segment.scalars)
					match segment.box {
						Free => {
							$total = checked_add($total, segment_width)?
							$free_field = match $free_field {
								NoField => segment.field
								found => found
							}
						}
						Box({ align: _, path: box_path, width: reserved }) => {
							if segment_width > reserved {
								return match segment.field {
									Field({ path: field_path, value }) => Err(FieldOverflow({ page: page + 1, path: field_path, reserved, value, width: segment_width }))
									NoField => Err(RegionOverflow({ available: reserved, path: box_path, required: segment_width }))
								}
							}
							$total = checked_add($total, reserved)?
						}
					}
				}
				if $total > width {
					return match $free_field {
						Field({ path: field_path, value }) => Err(FieldOverflow({ page: page + 1, path: field_path, reserved: width, value, width: $total }))
						NoField => Err(RegionOverflow({ available: width, path: record.path, required: $total }))
					}
				}
				$total
			}
		}
		$widths = $widths.append(item_width)
		$item = $item + 1
	}

	## Slot extents from the frame's start edge; slots may touch but never
	## overlap.
	var $start = 0
	var $center = 0
	var $end = 0
	var $offset = 0
	while $offset < $widths.len() {
		item_width = list_at($widths, $offset)
		match list_at(static.items, region.items.start() + $offset).slot {
			StartSlot => {
				$start = U64.max($start, item_width)
			}
			CenterSlot => {
				$center = U64.max($center, item_width)
			}
			EndSlot => {
				$end = U64.max($end, item_width)
			}
		}
		$offset = $offset + 1
	}
	center_left = (width - $center) // 2
	center_right = center_left + $center
	end_left = width - $end

	## `required` is the region width the two overlapping slots need: a
	## centered slot needs its width plus twice the wider side slot.
	overlaps = if $center > 0 and $start > center_left {
		Overlap({ required: checked_add(checked_add($start, $start)?, $center)?, slots: "start and center" })
	} else if $center > 0 and center_right > end_left and $end > 0 {
		Overlap({ required: checked_add(checked_add($end, $end)?, $center)?, slots: "center and end" })
	} else if $start > 0 and $end > 0 and $start > end_left {
		Overlap({ required: checked_add($start, $end)?, slots: "start and end" })
	} else {
		NoOverlap
	}
	match overlaps {
		NoOverlap => Ok($widths)
		Overlap({ required, slots }) => {
			## A slot holding a page field whose resolved value causes the
			## overlap is a field overflow; otherwise the static slots
			## overlap.
			match first_field(static, pending, cursor, region, page) {
				NoField => Err(SlotOverlap({ page: page + 1, path: region.path, slots }))
				Field({ path, value }) => Err(FieldOverflow({ page: page + 1, path, reserved: width, value, width: required }))
			}
		}
	}
}

## The first page field outside a reserved width among a region's items on
## one page, in item order.
first_field : KernelFacadeFurniture.Static, List(Pending), U64, Region, U64 -> [Field({ path : Str, value : Str }), NoField]
first_field = |static, pending, cursor, region, page| {
	var $cursor = cursor
	var $item = region.items.start()
	while $item < region.items.start() + region.items.length() {
		match list_at(static.items, $item).content {
			DrawingContent(_) => {}
			TextContent(_) => {
				entry = list_at(pending, $cursor)
				$cursor = $cursor + 1
				if entry.page == page {
					for segment in entry.segments {
						match (segment.box, segment.field) {
							(Free, Field(found)) => return Field(found)
							_ => {}
						}
					}
				}
			}
		}
		$item = $item + 1
	}
	NoField
}

## Place one region's measured items on one page: drawings by their
## bottom-left corners, text pieces by their baselines. A reserved width's
## content aligns inside it.
place_region : KernelFacadeFurniture.Static, Text.Store, List(Semantics.Range), List(Semantics.TextSourceId), List(Pending), U64, Region, List(U64), U64, List(KernelFacadeFurniture.Piece), List(KernelFacadeFurniture.DrawingPaint) -> Try({ cursor : U64, drawing_paints : List(KernelFacadeFurniture.DrawingPaint), pieces : List(KernelFacadeFurniture.Piece) }, KernelFacadeFurniture.Error)
place_region = |static, store, source_runs, input_sources, pending, cursor, region, widths, page, pieces, drawing_paints| {
	var $pieces = pieces
	var $drawing_paints = drawing_paints
	var $cursor = cursor
	frame = static.frame
	size = nonnegative(static.style.size)?
	var $offset = 0
	while $offset < widths.len() {
		item_index = region.items.start() + $offset
		record = list_at(static.items, item_index)
		item_width = list_at(widths, $offset)
		x = checked_add(
			frame.left,
			match record.slot {
				StartSlot => 0
				CenterSlot => (frame.width - item_width) // 2
				EndSlot => frame.width - item_width
			},
		)?
		top_y = checked_sub(frame.top, record.top)?
		match record.content {
			DrawingContent(drawing) => {
				bottom = checked_sub(top_y, record.height)?
				$drawing_paints = $drawing_paints.append({ drawing, kind: region.kind, origin: point(x, bottom), page })
			}
			TextContent(text_index) => {
				entry = list_at(pending, $cursor)
				$cursor = $cursor + 1
				kind = if list_at(static.texts, text_index).fields PageNumber else region.kind
				runs = runs_of(source_runs, list_at(input_sources, entry.input).index())
				baseline = checked_sub(top_y, size)?
				var $pen = x
				for segment in entry.segments {
					segment_width = runs_width(store, runs, segment.scalars)
					origin_x = match segment.box {
						Free => $pen
						Box({ align, path: _, width: reserved }) => checked_add(
							$pen,
							match align {
								StartReserved => 0
								EndReserved => reserved - segment_width
								CenterReserved => (reserved - segment_width) // 2
							},
						)?
					}

					## One piece per run the segment covers, in order, each at
					## the advance of the pieces before it.
					var $piece_x = origin_x
					var $run_index = runs.start()
					while $run_index < runs.start() + runs.length() {
						run = list_at(store.runs, $run_index)
						match run_clusters(store, run, segment.scalars) {
							Covered({ clusters, source }) => {
								$pieces = $pieces.append({ band: region.band, clusters, kind, origin: point($piece_x, baseline), page, run: $run_index, source })
								$piece_x = checked_add($piece_x, scalar_width(store, run, segment.scalars))?
							}
							Uncovered => {}
						}
						$run_index = $run_index + 1
					}
					if $piece_x != origin_x + segment_width {
						return Err(ArithmeticOverflow)
					}
					advance = match segment.box {
						Free => segment_width
						Box({ align: _, path: _, width: reserved }) => reserved
					}
					$pen = checked_add($pen, advance)?
				}
			}
		}
		$offset = $offset + 1
	}
	Ok({ cursor: $cursor, drawing_paints: $drawing_paints, pieces: $pieces })
}

## The runs shaping one furniture source: `source_runs` is empty through
## the single face, where source `k` is run `k`.
runs_of : List(Semantics.Range), U64 -> Semantics.Range
runs_of = |source_runs, source| if source_runs.is_empty() Semantics.Range.from_start_and_length(source, 1) else list_at(source_runs, source)

## The advance width of a scalar range across the runs of one source.
runs_width : Text.Store, Semantics.Range, Semantics.Range -> U64
runs_width = |store, runs, scalars| {
	var $total = 0
	var $run = runs.start()
	while $run < runs.start() + runs.length() {
		$total = $total + scalar_width(store, list_at(store.runs, $run), scalars)
		$run = $run + 1
	}
	$total
}

## The clusters of one run inside a scalar range and the source range they
## cover, or `Uncovered` when the run holds none of it. A range boundary
## inside a cluster is invalid.
run_clusters : Text.Store, Text.Run, Semantics.Range -> [Covered({ clusters : Semantics.Range, source : Semantics.TextRange }), Uncovered]
run_clusters = |store, run, scalars| {
	var $first = 0
	var $count = 0
	var $scalar_start = 0
	var $scalar_end = 0
	var $byte_start = 0
	var $byte_end = 0
	var $cluster = run.clusters.start()
	while $cluster < run.clusters.start() + run.clusters.length() {
		record = list_at(store.clusters, $cluster)
		start = record.source.scalars.start()
		if start >= scalars.start() and start < scalars.start() + scalars.length() {
			if $count == 0 {
				$first = $cluster
				$scalar_start = start
				$byte_start = record.source.utf8_bytes.start()
			}
			$count = $count + 1
			$scalar_end = start + record.source.scalars.length()
			$byte_end = record.source.utf8_bytes.start() + record.source.utf8_bytes.length()
		}
		$cluster = $cluster + 1
	}
	if $count == 0 {
		Uncovered
	} else {
		Covered({ clusters: Semantics.Range.from_start_and_length($first, $count), source: { scalars: span($scalar_start, $scalar_end), utf8_bytes: span($byte_start, $byte_end) } })
	}
}

## Shape every distinct furniture line under an ordered policy: each source
## is selected exactly as body text is, its segments become runs in order,
## and a face the body did not use becomes an extra output font.
shape_under_policy : KernelFacadeFurniture.PolicyFonts, List(KernelFacadeSources.Source), KernelFacadeFurniture.Static, List(Semantics.TextSourceId), List(Pending), Semantics.Language, KernelFacadeFurniture.Limits -> Try({ batch : KernelShape.Batch, extra_fonts : List(KernelFont.Inspection), run_sources : List(U64), source_runs : List(Semantics.Range) }, KernelFacadeFurniture.Error)
shape_under_policy = |policy, unique, static, input_sources, pending, language, limits| {
	var $faces = policy.faces
	var $fonts = policy.fonts
	var $selected = []
	var $run_sources = []
	var $source_runs = List.with_capacity(unique.len())
	var $index = 0
	while $index < unique.len() {
		segments = match KernelFacadeShape.select_source(policy.registry, policy.policy, list_at(unique, $index), $index, language) {
			Ok(value) => value
			Err(error) => return Err(furniture_text_error(error, source_path(static, input_sources, pending, $index)))
		}
		start = $selected.len()
		for segment in segments {
			known = face_position($faces, segment.face)
			if known == $faces.len() {
				font = policy.registry.prepared_face(segment.face) ? |_| Selection(PolicyInvalid(UnknownPolicyFace(segment.face)))
				$fonts = $fonts.append(font)
				$faces = $faces.append(segment.face)
			}
			$selected = $selected.append({ clusters: segment.clusters, instance: Font.InstanceId.from_index(known), language, occurrence: Semantics.OccurrenceId.from_index($index), script: segment.script, size: static.style.size, source: Semantics.TextSourceId.from_index($index) })
			$run_sources = $run_sources.append($index)
		}
		$source_runs = $source_runs.append(span(start, $selected.len()))
		$index = $index + 1
	}
	batch = if unique.is_empty() { advances: [], store: empty_store, work: empty_shape_work } else KernelShape.shape_selected_batch($fonts, unique, { direction: LeftToRight, language, writing_mode: Horizontal }, $selected, limits.shape) ? Shape
	Ok({ batch, extra_fonts: $fonts.drop_first(policy.fonts.len()), run_sources: $run_sources, source_runs: $source_runs })
}

## The dense position of a face, or the list length when it is new.
face_position : List(Font.FaceId), Font.FaceId -> U64
face_position = |faces, face| {
	var $index = 0
	while $index < faces.len() {
		if list_at(faces, $index).index() == face.index() {
			return $index
		}
		$index = $index + 1
	}
	faces.len()
}

## The furniture item path of the first line that interns to `source`.
source_path : KernelFacadeFurniture.Static, List(Semantics.TextSourceId), List(Pending), U64 -> Str
source_path = |static, input_sources, pending, source| {
	for entry in pending {
		if list_at(input_sources, entry.input).index() == source {
			return list_at(static.items, entry.item).path
		}
	}
	"templates"
}

## A selection rejection of a furniture line, located at its item: an
## undeclared script, or a cluster no policy face covers (the script check
## runs first, as for body text).
furniture_text_error : KernelFacadeShape.Error, Str -> KernelFacadeFurniture.Error
furniture_text_error = |error, path| match error {
	UndeclaredScript({ script, source: _ }) => FurnitureText({ path, reason: Script(script) })
	FontSelectionRejected(errors) => match errors.first() {
		Ok(MissingCoverage(_)) => FurnitureText({ path, reason: Coverage })
		Ok(UnsupportedBuiltInShaping({ cluster: _, script })) => FurnitureText({ path, reason: Script(script.as_str()) })
		_ => Selection(error)
	}
	_ => Selection(error)
}

## The advance width of a scalar range of one furniture run.
## The convenience shaper forms one cluster of one glyph per scalar.
scalar_width : Text.Store, Text.Run, Semantics.Range -> U64
scalar_width = |store, run, scalars| {
	var $total = 0
	var $cluster = run.clusters.start()
	while $cluster < run.clusters.start() + run.clusters.length() {
		record = list_at(store.clusters, $cluster)
		start = record.source.scalars.start()
		if start >= scalars.start() and start < scalars.start() + scalars.length() {
			var $reference = record.glyphs.start()
			while $reference < record.glyphs.start() + record.glyphs.length() {
				glyph = list_at(store.glyphs, list_at(store.glyph_indices, $reference))
				$total = $total + glyph.advance_x.raw().to_u64_wrap()
				$reference = $reference + 1
			}
		}
		$cluster = $cluster + 1
	}
	$total
}

## The absolute cluster range of a run covering exactly a scalar range; a
## segment boundary inside a cluster is invalid.
cluster_range : Text.Store, Text.Run, Semantics.Range -> Try(Semantics.Range, KernelFacadeFurniture.Error)
cluster_range = |store, run, scalars| {
	var $first = run.clusters.start() + run.clusters.length()
	var $count = 0
	var $covered = 0
	var $cluster = run.clusters.start()
	while $cluster < run.clusters.start() + run.clusters.length() {
		record = list_at(store.clusters, $cluster)
		start = record.source.scalars.start()
		if start >= scalars.start() and start < scalars.start() + scalars.length() {
			if $count == 0 {
				$first = $cluster
			}
			$count = $count + 1
			$covered = $covered + record.source.scalars.length()
		}
		$cluster = $cluster + 1
	}
	if $count == 0 or $covered != scalars.length() {
		Err(ArithmeticOverflow)
	} else {
		Ok(Semantics.Range.from_start_and_length($first, $count))
	}
}

scalar_count : Str -> U64
scalar_count = |text| {
	var $count = 0
	for byte in Str.to_utf8(text) {
		if byte.bitwise_and(0xC0) != 0x80 {
			$count = $count + 1
		}
	}
	$count
}

span : U64, U64 -> Semantics.Range
span = |start, end| Semantics.Range.from_start_and_length(start, end - start)

point : U64, U64 -> Layout.Point
point = |x, y| { x: Layout.Unit.from_raw(x.to_i64_wrap()), y: Layout.Unit.from_raw(y.to_i64_wrap()) }

unit : U64 -> Layout.Unit
unit = |value| Layout.Unit.from_raw(value.to_i64_wrap())

nonnegative : Layout.Unit -> Try(U64, KernelFacadeFurniture.Error)
nonnegative = |value| if value.raw() < 0 Err(ArithmeticOverflow) else Ok(value.raw().to_u64_wrap())

check_limit : U64, U64, KernelFacadeFurniture.Dimension -> Try({}, KernelFacadeFurniture.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeFurniture.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

checked_sub : U64, U64 -> Try(U64, KernelFacadeFurniture.Error)
checked_sub = |left, right| if right > left Err(ArithmeticOverflow) else Ok(left - right)

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated furniture index escaped"
}
