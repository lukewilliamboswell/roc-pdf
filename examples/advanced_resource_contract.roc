app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Color
import pdf.Font
import pdf.Image
import pdf.Semantics
import pdf.Theme
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)

## Prepared color values identify the exact validated color-space resource.
expect {
	color : Color.Value
	color = {
		channels: Rgb({ blue: 300, green: 200, red: 100 }),
		space: Color.SpaceId.from_index(1),
	}

	color.space.index() == 1
}

## Complete caller-owned bytes are validated once, assigned opaque dense
## handles, attached to options, and selected through Theme without a font name
## or caller-assigned resource ID.
expect {
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	)?
	store = registered.registry.store()
	theme = Theme.with_font(Theme.default, registered.face)
	registered.face.index() == 0 and
		registered.instance.index() == 0 and
			registered.policy.index() == 0 and
				registered.work.input_bytes == caller_font_bytes.len() and
					registered.work.retained_input_bytes == caller_font_bytes.len() and
						registered.work.copied_input_bytes == 0 and
							list_at(store.resources, 0).bytes.len() == caller_font_bytes.len() and
								theme.body_font().index() == registered.face.index()
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "caller resource contract index escaped"
	}
	Ok(value) => value
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
