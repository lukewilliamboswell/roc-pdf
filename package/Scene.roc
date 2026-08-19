import Color
import Image
import Layout
import Semantics
import Text

Scene :: [].{
	GroupId :: U64.{
		from_index : U64 -> GroupId
		from_index = |index| GroupId.(index)

		index : GroupId -> U64
		index = |GroupId.(index)| index
	}

	PathId :: U64.{
		from_index : U64 -> PathId
		from_index = |index| PathId.(index)

		index : PathId -> U64
		index = |PathId.(index)| index
	}

	FormId :: U64.{
		from_index : U64 -> FormId
		from_index = |index| FormId.(index)

		index : FormId -> U64
		index = |FormId.(index)| index
	}

	ShadingId :: U64.{
		from_index : U64 -> ShadingId
		from_index = |index| ShadingId.(index)

		index : ShadingId -> U64
		index = |ShadingId.(index)| index
	}

	PatternId :: U64.{
		from_index : U64 -> PatternId
		from_index = |index| PatternId.(index)

		index : PatternId -> U64
		index = |PatternId.(index)| index
	}

	Matrix : {
		a : Layout.Unit,
		b : Layout.Unit,
		c : Layout.Unit,
		d : Layout.Unit,
		e : Layout.Unit,
		f : Layout.Unit,
	}

	CoordinateOrigin : [BottomLeft]
	CoordinateDirection : [Upward]
	CoordinateModel : {
		origin : CoordinateOrigin,
		transform_coefficient_scale : U64,
		units_per_point : U64,
		y_direction : CoordinateDirection,
	}

	## tagged-visual geometry uses PDF user space: a bottom-left origin, an upward Y
	## axis, 1,000 layout units per point, and matrix coefficients scaled by
	## 1,000. Translation entries use ordinary layout units.
	coordinate_model : CoordinateModel
	coordinate_model = {
		origin: BottomLeft,
		transform_coefficient_scale: 1000,
		units_per_point: Layout.Unit.units_per_point,
		y_direction: Upward,
	}

	Rotation : [Rotate0, Rotate90, Rotate180, Rotate270]
	PageBoxes : {
		art : Layout.Rect,
		bleed : Layout.Rect,
		crop : Layout.Rect,
		media : Layout.Rect,
		trim : Layout.Rect,
	}

	PageArtifactKind : [
		Background,
		Decoration,
		Footer,
		Header,
		PageNumber,
		Watermark,
	]

	## Contextual Artifact elements are intentionally absent from this union;
	## they live in the semantic content spine, not page-artifact ownership.
	GroupOwner : [
		Fragment(Semantics.FragmentId),
		PageArtifact(PageArtifactKind),
	]

	FillRule : [EvenOdd, Nonzero]
	LineCap : [ButtCap, ProjectingSquareCap, RoundCap]
	LineJoin : [BevelJoin, MiterJoin, RoundJoin]
	DashPattern : [
		Dashed({ lengths : Semantics.Range, phase : Layout.Unit }),
		SolidLine,
	]
	StrokeStyle : {
		cap : LineCap,
		color : Color.Value,
		dash : DashPattern,
		join : LineJoin,
		miter_limit : Layout.Unit,
		width : Layout.Unit,
	}

	## `PatternFill` fills the path with a colored tiling pattern selected as
	## the nonstroking paint. Stroke patterns are not representable: a stroke
	## keeps its solid typed color, so a patterned outline is outside the
	## supported subset by construction.
	PathStyle : {
		fill : [
			NoFill,
			PatternFill({ pattern : PatternId, rule : FillRule }),
			SolidFill({ color : Color.Value, rule : FillRule }),
		],
		stroke : [NoStroke, SolidStroke(StrokeStyle)],
	}

	PathSegment : [
		Close,
		CubicTo({ control_1 : Layout.Point, control_2 : Layout.Point, end : Layout.Point }),
		LineTo(Layout.Point),
		MoveTo(Layout.Point),
		Rectangle(Layout.Rect),
	]
	Path : { id : PathId, segments : Semantics.Range }

	TextRenderingMode : [Fill, FillAndStroke]
	TextPaint : {
		fill : Color.Value,
		mode : TextRenderingMode,
		opacity : U16,
		stroke : [NoStroke, Stroke({ color : Color.Value, width : Layout.Unit })],
	}

	## Child ranges point into the same command arena, preserving balanced
	## graphics-state nesting without allocating recursive command values.
	## `PlaceForm` invokes a Form XObject at an explicit placement transform;
	## its ownership is inherited from the containing owned scene group, and a
	## placement inside form content inherits transitively through the
	## outermost page-level placement.
	## `Opacity` applies a constant fill-and-stroke alpha to its children with
	## Normal blending. The effective alpha of a painted element is the product
	## of every enclosing opacity group within its content stream, computed in
	## exact `U16` fixed point (65535 is fully opaque and an exact identity;
	## the identity value normalizes away entirely). An isolated-group form
	## resets that ambient product at its boundary; see `Form`.
	## `SoftMask` applies a per-sample alpha soft mask to its children's
	## painting operations. The mask is the alpha channel of the referenced
	## mask form, which must be an `IsolatedGroup` form rendered against a
	## fully transparent backdrop. Constant alpha and the mask multiply
	## natively (they are independent graphics-state parameters). One stream
	## context supports at most one active mask: nesting a `SoftMask` under
	## another within a stream is rejected, and mask composition is expressed
	## explicitly by masking an isolated-group form whose content applies the
	## inner mask (the group boundary resets the ambient mask; see `Form`).
	## `PaintShading` paints the referenced shading across the current clip
	## region with the `sh` operator. The shading's geometry is expressed in
	## the user space active at the paint site, so authors bound the painted
	## area with an enclosing `Clip` and position it with `Transform`.
	Command : [
		Clip({ children : Semantics.Range, path : PathId }),
		DrawImage({ image : Image.Id, placement : Layout.Rect }),
		DrawPath({ path : PathId, style : PathStyle }),
		DrawText({ paint : TextPaint, run : Text.RunId }),
		Opacity({ children : Semantics.Range, opacity : U16 }),
		PaintShading({ shading : ShadingId }),
		PlaceForm({ form : FormId, transform : Matrix }),
		SoftMask({ children : Semantics.Range, mask : FormId }),
		Transform({ children : Semantics.Range, matrix : Matrix }),
	]

	OwnedGroup : {
		commands : Semantics.Range,
		id : GroupId,
		owner : GroupOwner,
	}

	Page : {
		boxes : PageBoxes,
		id : Semantics.PageId,
		paint_order : Semantics.Range,
		rotation : Rotation,
	}

	## Pages index `page_groups`; groups index roots in `commands`; nested
	## commands index further ranges. Payload resources remain in their own
	## stores and repeated placements carry only scalar IDs.
	Store : {
		commands : List(Command),
		dash_lengths : List(Layout.Unit),
		groups : List(OwnedGroup),
		page_groups : List(GroupId),
		pages : List(Page),
		path_segments : List(PathSegment),
		paths : List(Path),
	}

	## Whether a form is an isolated PDF 2.0 transparency group. An isolated
	## group composites as a unit: constant alpha applied at a placement site
	## multiplies the group's rendered result exactly once, and the ambient
	## constant alpha and soft mask inside the group reset to their identity
	## values (ISO 32000-2, 11.6.6). `NoGroup` forms stay transparent to the
	## graphics state, so their painted elements each compose with the ambient
	## alpha and mask individually. A form referenced as a soft mask must be
	## an isolated group. Knockout groups are not representable.
	FormGroup : [IsolatedGroup, NoGroup]

	## A Form XObject's content is a range into the flat form-command arena;
	## its `/Matrix` is the documented canonical identity because placement
	## transforms are entirely placement-side facts. Paths, dash values, and
	## text runs are shared with the page store; only the command arena is
	## separate so page and form content each keep dense once-each ownership.
	Form : {
		bbox : Layout.Rect,
		commands : Semantics.Range,
		group : FormGroup,
		id : FormId,
	}

	FormStore : {
		commands : List(Command),
		forms : List(Form),
	}

	no_forms : FormStore
	no_forms = { commands: [], forms: [] }

	## One ordered gradient color stop. `offset` is an exact `U16` domain
	## position: 0 is domain 0.0 and 65535 is domain 1.0, with the canonical
	## PDF number derived by the identical fixed-width mapping color channels
	## use. Channel arity must match the owning shading's color space.
	GradientStop : { channels : Color.Channels, offset : U16 }

	## Explicit shading geometry in the user space of the paint site. An
	## axial shading interpolates along the start-to-end axis; a radial
	## shading interpolates between the two circles. Radii must be
	## non-negative; a single zero radius is a supported cone endpoint.
	ShadingGeometry : [
		Axial({ end : Layout.Point, start : Layout.Point }),
		Radial({ end_center : Layout.Point, end_radius : Layout.Unit, start_center : Layout.Point, start_radius : Layout.Unit }),
	]

	## A typed linear or radial gradient. Stops are an exact range into the
	## flat stop list: at least two, strictly increasing offsets, first
	## exactly 0 and last exactly 65535. All stops share the declared color
	## space. `extend_start`/`extend_end` extend the boundary colors beyond
	## the geometry exactly as PDF `/Extend` does. Adjacent equal colors are
	## retained as authored; they are a visually meaningful flat band.
	Shading : {
		extend_end : Bool,
		extend_start : Bool,
		geometry : ShadingGeometry,
		id : ShadingId,
		space : Color.SpaceId,
		stops : Semantics.Range,
	}

	ShadingStore : { shadings : List(Shading), stops : List(GradientStop) }

	no_shadings : ShadingStore
	no_shadings = { shadings: [], stops: [] }

	## A colored tiling pattern cell: an ownership-neutral reusable visual
	## resource. The cell's content is a range into the flat pattern-command
	## arena and may clip, transform, draw solid paths, place alpha-free
	## images, paint shadings, and place text-free, transparency-free forms.
	## Text, transparency, soft masks, and nested pattern invocation are
	## rejected. `matrix` maps pattern space to the default space of the
	## stream that uses the pattern (a placement transform of a consuming
	## form composes on top); the identity matrix is retained and emitted
	## explicitly. `x_step`/`y_step` are the positive tile advances.
	PatternCell : {
		bbox : Layout.Rect,
		commands : Semantics.Range,
		id : PatternId,
		matrix : Matrix,
		x_step : Layout.Unit,
		y_step : Layout.Unit,
	}

	PatternStore : { cells : List(PatternCell), commands : List(Command) }

	no_patterns : PatternStore
	no_patterns = { cells: [], commands: [] }
}

## Scene group IDs preserve their dense index.
expect Scene.GroupId.from_index(2).index() == 2

## Path IDs preserve their dense index.
expect Scene.PathId.from_index(4).index() == 4

## The public coordinate model matches the fixed-point layout scale.
expect Scene.coordinate_model.units_per_point == 1000

## Nested public type modules construct opaque scene group IDs directly.
expect Scene.GroupId.from_index(10).index() == 10

## Form IDs preserve their dense index and the empty store carries no forms.
expect Scene.FormId.from_index(3).index() == 3 and Scene.no_forms.forms.len() == 0

## Shading and pattern IDs preserve their dense indices, and the empty paint
## stores carry no resources.
expect Scene.ShadingId.from_index(5).index() == 5 and Scene.PatternId.from_index(7).index() == 7 and Scene.no_shadings.shadings.len() == 0 and Scene.no_patterns.cells.len() == 0
