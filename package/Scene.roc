import Layout
import Semantics

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

	GlyphRunId :: U64.{
		from_index : U64 -> GlyphRunId
		from_index = |index| GlyphRunId.(index)

		index : GlyphRunId -> U64
		index = |GlyphRunId.(index)| index
	}

	ImageId :: U64.{
		from_index : U64 -> ImageId
		from_index = |index| ImageId.(index)

		index : ImageId -> U64
		index = |ImageId.(index)| index
	}

	Matrix : {
		a : Layout.Unit,
		b : Layout.Unit,
		c : Layout.Unit,
		d : Layout.Unit,
		e : Layout.Unit,
		f : Layout.Unit,
	}

	Color : [Gray(U16), Rgb({ blue : U16, green : U16, red : U16 })]

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
		fill : [NoFill, SolidFill(Color)],
		stroke : [NoStroke, SolidStroke({ color : Color, width : Layout.Unit })],
	}

	## Child ranges point into the same command arena, preserving balanced
	## graphics-state nesting without allocating recursive command values.
	Command : [
		Clip({ children : Semantics.Range, path : PathId }),
		DrawImage(ImageId),
		DrawPath({ path : PathId, style : PathStyle }),
		DrawText(GlyphRunId),
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

## Glyph-run IDs preserve their dense index.
expect Scene.GlyphRunId.from_index(6).index() == 6

## Image IDs preserve their dense index.
expect Scene.ImageId.from_index(8).index() == 8

## Nested public type modules construct opaque scene group IDs directly.
expect Scene.GroupId.from_index(10).index() == 10
