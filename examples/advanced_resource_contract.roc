app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Color
import pdf.Image
import pdf.Semantics

## Prepared color values identify the exact validated color-space resource.
expect {
	color : Color.Value
	color = {
		channels: Rgb({ blue: 300, green: 200, red: 100 }),
		space: Color.SpaceId.from_index(1),
	}

	color.space.index() == 1
}

## ICC profile bytes are retained once and tags remain validated source ranges.
expect {
	profile : Color.IccProfile
	profile = {
		bytes: [0, 0, 0, 12],
		components: Three,
		id: Color.ProfileId.from_index(0),
		tags: Semantics.Range.from_start_and_length(0, 1),
		version: IccV4,
	}

	profile.id.index() == 0 and profile.tags.length() == 1
}

## Raster resources use packed planes and an explicit typed color space.
expect {
	resource : Image.Resource
	resource = {
		id: Image.Id.from_index(2),
		payload: Raster({
			alpha: NoAlpha,
			color_space: Color.SpaceId.from_index(1),
			dimensions: { height: 1, width: 2 },
			format: Rgb8,
			pixels: [255, 0, 0, 0, 0, 255],
			row_stride: 6,
		}),
	}

	match resource.payload {
		Raster(raster) => raster.pixels.len() == 6 and raster.color_space.index() == 1
		_ => False
	}
}

## JPEG orientation evidence is explicit before placement.
expect {
	jpeg : Image.ValidatedJpeg
	jpeg = {
		bytes: [255, 216, 255, 217],
		color_space: Color.SpaceId.from_index(1),
		components: Three,
		dimensions: { height: 1, width: 1 },
		orientation: ConfirmedDisplayReady,
	}

	jpeg.orientation == ConfirmedDisplayReady
}

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |_| { bytes: [], work: [] }
