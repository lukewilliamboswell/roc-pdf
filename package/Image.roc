import Color

Image :: [].{
	Id :: U64.{
		from_index : U64 -> Id
		from_index = |index| Id.(index)

		index : Id -> U64
		index = |Id.(index)| index
	}

	Dimensions : { height : U32, width : U32 }
	PixelFormat : [Gray8, Rgb8]

	AlphaPlane : [
		NoAlpha,
		PackedAlpha({ bytes : List(U8), row_stride : U64 }),
	]

	## Raster pixels are one packed byte plane, never a list of pixel records.
	PackedRaster : {
		alpha : AlphaPlane,
		color_space : Color.SpaceId,
		dimensions : Dimensions,
		format : PixelFormat,
		pixels : List(U8),
		row_stride : U64,
	}

	ExifOrientation : [
		BottomLeft,
		BottomRight,
		LeftBottom,
		LeftTop,
		RightBottom,
		RightTop,
		TopLeft,
		TopRight,
	]
	OrientationPolicy : [ApplyBeforePlacement, RequireDisplayReady]
	OrientationEvidence : [
		Applied(ExifOrientation),
		ConfirmedDisplayReady,
		NoExifOrientation,
	]

	## Encoded JPEG bytes have already passed bounded marker, dimension, color,
	## and orientation inspection. Irrelevant metadata is not copied onward.
	ValidatedJpeg : {
		bytes : List(U8),
		color_space : Color.SpaceId,
		components : Color.ComponentCount,
		dimensions : Dimensions,
		orientation : OrientationEvidence,
	}

	Resource : {
		id : Id,
		payload : [Jpeg(ValidatedJpeg), Raster(PackedRaster)],
	}

	InspectionWork : {
		bytes_checked : U64,
		markers_checked : U64,
		rows_checked : U64,
	}

	Store : {
		resources : List(Resource),
	}
}

## Image resource IDs preserve their dense index.
expect Image.Id.from_index(7).index() == 7
