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

	## A read-only view of replayable authoring data. Inspection shares source
	## byte lists and does not assign a PDF resource identity or validate them.
	SourceView : [
		JpegSrgbView({ bytes : List(U8), orientation : OrientationPolicy }),
		PackedGray8View({ alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 }),
		PackedRgb8View({ alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 }),
	]

	## An authoring image is replayable source data, not a caller-assigned PDF
	## resource identity. Preparation validates, normalizes, and deduplicates the
	## source before any page content is emitted.
	Source := [
		JpegSrgb({ bytes : List(U8), orientation : OrientationPolicy }),
		PackedGray8({ alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 }),
		PackedRgb8({ alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 }),
	].{

		## Retain encoded sRGB JPEG bytes with an explicit orientation policy.
		jpeg_srgb : List(U8), OrientationPolicy -> Source
		jpeg_srgb = |bytes, orientation| Source.JpegSrgb({ bytes, orientation })

		## Retain a packed 8-bit gray raster and optional packed alpha plane.
		gray8 : { alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 } -> Source
		gray8 = |source| Source.PackedGray8(source)

		## Retain a packed interleaved 8-bit sRGB raster and optional alpha plane.
		rgb8 : { alpha : AlphaPlane, dimensions : Dimensions, pixels : List(U8), row_stride : U64 } -> Source
		rgb8 = |source| Source.PackedRgb8(source)

		## Inspect the replayable authoring form without assigning a PDF resource
		## identity. Returned byte lists share the immutable source payload.
		inspect : Source -> SourceView
		inspect = |Source.(source)| match source {
			JpegSrgb(value) => JpegSrgbView(value)
			PackedGray8(value) => PackedGray8View(value)
			PackedRgb8(value) => PackedRgb8View(value)
		}
	}

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

	## Encoded JPEG source bytes cross a bounded inspection boundary before they
	## become a `ValidatedJpeg` or enter the normalized resource store.
	JpegSource : {
		bytes : List(U8),
		color_space : Color.SpaceId,
		orientation_policy : OrientationPolicy,
	}
	SourceResource : {
		id : Id,
		payload : [EncodedJpeg(JpegSource), PackedPixels(PackedRaster)],
	}
	SourceStore : { resources : List(SourceResource) }

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
