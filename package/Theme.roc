import Layout
import Scene

Theme :: {
	body : TextStyle,
	bullet_indent : Layout.Unit,
	code : TextStyle,
	heading : TextStyle,
	page_margin : PageMargin,
	paragraph_spacing : Layout.Unit,
	title : TextStyle,
}.{
	FontFaceId :: U64.{
		from_index : U64 -> FontFaceId
		from_index = |index| FontFaceId.(index)

		index : FontFaceId -> U64
		index = |FontFaceId.(index)| index
	}

	TextStyle : {
		color : Scene.Color,
		font : FontFaceId,
		leading : Layout.Unit,
		size : Layout.Unit,
	}

	PageMargin : {
		bottom : Layout.Unit,
		left : Layout.Unit,
		right : Layout.Unit,
		top : Layout.Unit,
	}

	## The built-in face ID is a versioned package resource identity. Gate 3
	## supplies and validates the corresponding font resource.
	default : Theme
	default = {
		black : Scene.Color
		black = Rgb({ blue: 0, green: 0, red: 0 })

		body = {
			color: black,
			font: FontFaceId.from_index(0),
			leading: Layout.Unit.from_raw(14000),
			size: Layout.Unit.from_raw(11000),
		}

		Theme.{
			body,
			bullet_indent: Layout.Unit.from_raw(18000),
			code: body,
			heading: {
				color: black,
				font: FontFaceId.from_index(0),
				leading: Layout.Unit.from_raw(18000),
				size: Layout.Unit.from_raw(15000),
			},
			page_margin: {
				bottom: Layout.Unit.from_raw(72000),
				left: Layout.Unit.from_raw(72000),
				right: Layout.Unit.from_raw(72000),
				top: Layout.Unit.from_raw(72000),
			},
			paragraph_spacing: Layout.Unit.from_raw(8000),
			title: {
				color: black,
				font: FontFaceId.from_index(0),
				leading: Layout.Unit.from_raw(28000),
				size: Layout.Unit.from_raw(24000),
			},
		}
	}
}

## Nested theme font references preserve their dense resource index.
expect Theme.FontFaceId.from_index(3).index() == 3

## The versioned default theme uses an exact 72-point left margin.
expect Layout.Unit.raw(Theme.default.page_margin.left) == 72000
