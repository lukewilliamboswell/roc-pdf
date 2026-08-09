app [main!] {
	pf: platform "../tests/platform/main.roc",
	pdf: "../package/main.roc",
}

import pdf.Color
import pdf.Font
import pdf.Image
import pdf.Pdf
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

## A registered caller face is selected by Theme and reaches the one-import
## facade without exposing a resource ID or any PDF object detail.
expect {
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	)?
	theme = Theme.with_font(Theme.default, registered.face)
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), registered.registry)
	document = Pdf.document({
		contents: [Pdf.paragraph("Café PDF")],
		language: "en-AU",
		title: "Caller font facade",
	})
	bytes = Pdf.to_bytes_with(document, options)?

	bytes.sublist({ start: 0, len: 9 }) == Str.to_utf8("%PDF-2.0\n") and bytes.len() > 667
}

## The facade does not substitute the packaged font if a selected caller face
## is absent from the supplied registry. The failed Try has no PDF byte value.
expect {
	theme = Theme.with_font(Theme.default, Font.FaceId.from_index(1))
	options = Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), Font.Registry.empty)
	document = Pdf.document({
		contents: [Pdf.paragraph("No fallback")],
		language: "en-AU",
		title: "Unknown caller face",
	})

	match Pdf.to_bytes_with(document, options) {
		Err(InvalidFontResource(UnknownFace(face))) => face.index() == 1
		_ => False
	}
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
								list_at(store.faces, 0).postscript_name == Str.to_utf8("CallerFixtureSans-Regular") and
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
