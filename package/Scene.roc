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

	## Gate 2 geometry uses PDF user space: a bottom-left origin, an upward Y
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
	PathStyle : {
		fill : [NoFill, SolidFill({ color : Color.Value, rule : FillRule })],
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
	Command : [
		Clip({ children : Semantics.Range, path : PathId }),
		DrawImage({ image : Image.Id, placement : Layout.Rect }),
		DrawPath({ path : PathId, style : PathStyle }),
		DrawText({ paint : TextPaint, run : Text.RunId }),
		Opacity({ children : Semantics.Range, opacity : U16 }),
		PlaceForm({ form : FormId, transform : Matrix }),
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

	## A Form XObject's content is a range into the flat form-command arena;
	## its `/Matrix` is the documented canonical identity because placement
	## transforms are entirely placement-side facts. Paths, dash values, and
	## text runs are shared with the page store; only the command arena is
	## separate so page and form content each keep dense once-each ownership.
	Form : {
		bbox : Layout.Rect,
		commands : Semantics.Range,
		id : FormId,
	}

	FormStore : {
		commands : List(Command),
		forms : List(Form),
	}

	no_forms : FormStore
	no_forms = { commands: [], forms: [] }
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
