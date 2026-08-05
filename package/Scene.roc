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

	Matrix : {
		a : Layout.Unit,
		b : Layout.Unit,
		c : Layout.Unit,
		d : Layout.Unit,
		e : Layout.Unit,
		f : Layout.Unit,
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

	PathStyle : {
		fill : [NoFill, SolidFill(Color.Value)],
		stroke : [NoStroke, SolidStroke({ color : Color.Value, width : Layout.Unit })],
	}

	TextRenderingMode : [Fill, FillAndStroke]
	TextPaint : {
		fill : Color.Value,
		mode : TextRenderingMode,
		opacity : U16,
		stroke : [NoStroke, Stroke({ color : Color.Value, width : Layout.Unit })],
	}

	## Child ranges point into the same command arena, preserving balanced
	## graphics-state nesting without allocating recursive command values.
	Command : [
		Clip({ children : Semantics.Range, path : PathId }),
		DrawImage(Image.Id),
		DrawPath({ path : PathId, style : PathStyle }),
		DrawText({ paint : TextPaint, run : Text.RunId }),
		Opacity({ children : Semantics.Range, opacity : U16 }),
		Transform({ children : Semantics.Range, matrix : Matrix }),
	]

	OwnedGroup : {
		commands : Semantics.Range,
		id : GroupId,
		owner : GroupOwner,
	}

	Page : {
		id : Semantics.PageId,
		paint_order : Semantics.Range,
	}

	## Pages index `page_groups`; groups index roots in `commands`; nested
	## commands index further ranges. Payload resources remain in their own
	## stores and repeated placements carry only scalar IDs.
	Store : {
		commands : List(Command),
		groups : List(OwnedGroup),
		page_groups : List(GroupId),
		pages : List(Page),
	}
}

## Scene group IDs preserve their dense index.
expect Scene.GroupId.from_index(2).index() == 2

## Path IDs preserve their dense index.
expect Scene.PathId.from_index(4).index() == 4

## Nested public type modules construct opaque scene group IDs directly.
expect Scene.GroupId.from_index(10).index() == 10
