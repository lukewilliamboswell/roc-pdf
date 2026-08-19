import Color
import Font
import Layout

Theme :: {
	body : TextStyle,
	bullet_indent : Layout.Unit,
	code : TextStyle,
	font_selection : FontSelection,
	heading : TextStyle,
	page_margin : PageMargin,
	paragraph_spacing : Layout.Unit,
	title : TextStyle,
}.{
	TextStyle : {
		color : Color.SourceValue,
		font : Font.FaceId,
		leading : Layout.Unit,
		size : Layout.Unit,
	}

	## `StyleFaces` selects each style's exact single face. `Policy` selects a
	## registry-constructed finite ordered policy for per-cluster coverage
	## selection; the policy identity is Theme-selectable state, never inferred
	## from registry insertion order.
	FontSelection : [Policy(Font.PolicyId), StyleFaces]

	PageMargin : {
		bottom : Layout.Unit,
		left : Layout.Unit,
		right : Layout.Unit,
		top : Layout.Unit,
	}

	## The built-in face ID is a versioned package resource identity. text-layout
	## supplies and validates the corresponding font resource.
	default : Theme
	default = {
		black : Color.SourceValue
		black = Srgb(Rgb({ blue: 0, green: 0, red: 0 }))

		body = {
			color: black,
			font: Font.FaceId.from_index(0),
			leading: Layout.Unit.from_raw(14000),
			size: Layout.Unit.from_raw(11000),
		}

		Theme.{
			body,
			bullet_indent: Layout.Unit.from_raw(18000),
			code: body,
			font_selection: StyleFaces,
			heading: {
				color: black,
				font: Font.FaceId.from_index(0),
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
				font: Font.FaceId.from_index(0),
				leading: Layout.Unit.from_raw(28000),
				size: Layout.Unit.from_raw(24000),
			},
		}
	}

	with_font : Theme, Font.FaceId -> Theme
	with_font = |theme, font| Theme.{
		body: { ..theme.body, font },
		bullet_indent: theme.bullet_indent,
		code: { ..theme.code, font },
		font_selection: StyleFaces,
		heading: { ..theme.heading, font },
		page_margin: theme.page_margin,
		paragraph_spacing: theme.paragraph_spacing,
		title: { ..theme.title, font },
	}

	## Select an ordered multi-face policy for the whole document body. Style
	## faces remain recorded but the pipeline resolves fonts per grapheme
	## cluster through the policy's registry search space.
	with_font_policy : Theme, Font.PolicyId -> Theme
	with_font_policy = |theme, policy| { ..theme, font_selection: Policy(policy) }

	## Change the body color without exposing the theme representation.
	with_body_color : Theme, Color.SourceValue -> Theme
	with_body_color = |theme, color| { ..theme, body: { ..theme.body, color } }

	## Change heading color while retaining its metrics and selected face.
	with_heading_color : Theme, Color.SourceValue -> Theme
	with_heading_color = |theme, color| { ..theme, heading: { ..theme.heading, color } }

	## Change title color while retaining its metrics and selected face.
	with_title_color : Theme, Color.SourceValue -> Theme
	with_title_color = |theme, color| { ..theme, title: { ..theme.title, color } }

	## Apply one color to every built-in text role.
	with_text_color : Theme, Color.SourceValue -> Theme
	with_text_color = |theme, color| {
		..theme,
		body: { ..theme.body, color },
		code: { ..theme.code, color },
		heading: { ..theme.heading, color },
		title: { ..theme.title, color },
	}

	## Replace the complete body style while preserving every other theme role.
	with_body_style : Theme, TextStyle -> Theme
	with_body_style = |theme, style| { ..theme, body: style }

	## Replace the complete heading style while preserving every other theme role.
	with_heading_style : Theme, TextStyle -> Theme
	with_heading_style = |theme, style| { ..theme, heading: style }

	## Replace the complete title style while preserving every other theme role.
	with_title_style : Theme, TextStyle -> Theme
	with_title_style = |theme, style| { ..theme, title: style }

	## Replace all four page margins using exact layout units.
	with_page_margin : Theme, PageMargin -> Theme
	with_page_margin = |theme, page_margin| { ..theme, page_margin }

	## Replace the vertical spacing following each paragraph-like block.
	with_paragraph_spacing : Theme, Layout.Unit -> Theme
	with_paragraph_spacing = |theme, paragraph_spacing| { ..theme, paragraph_spacing }

	## Replace the list-body indentation from the containing text edge.
	with_bullet_indent : Theme, Layout.Unit -> Theme
	with_bullet_indent = |theme, bullet_indent| { ..theme, bullet_indent }

	font_selection : Theme -> FontSelection
	font_selection = |theme| theme.font_selection

	body_font : Theme -> Font.FaceId
	body_font = |theme| theme.body.font

	body_style : Theme -> TextStyle
	body_style = |theme| theme.body

	heading_style : Theme -> TextStyle
	heading_style = |theme| theme.heading

	title_style : Theme -> TextStyle
	title_style = |theme| theme.title

	bullet_indent : Theme -> Layout.Unit
	bullet_indent = |theme| theme.bullet_indent

	page_margin : Theme -> PageMargin
	page_margin = |theme| theme.page_margin

	paragraph_spacing : Theme -> Layout.Unit
	paragraph_spacing = |theme| theme.paragraph_spacing
}

## Nested theme font references preserve their dense resource index.
expect Font.FaceId.from_index(3).index() == 3

## The versioned default theme uses an exact 72-point left margin.
expect Layout.Unit.raw(Theme.default.page_margin.left) == 72000
