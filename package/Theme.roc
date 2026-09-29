import Color
import Font
import Layout

Theme :: {
	body : TextStyle,
	bullet_indent : Layout.Unit,
	code : InlineColor,
	emphasis : InlineColor,
	font_selection : FontSelection,
	heading : TextStyle,
	page_margin : PageMargin,
	paragraph_spacing : Layout.Unit,
	quote : InlineColor,
	strong : InlineColor,
	table : TableStyle,
	title : TextStyle,
}.{
	TextStyle : {
		color : Color.SourceValue,
		font : Font.FaceId,
		leading : Layout.Unit,
		size : Layout.Unit,
	}

	## The presentation of an inline semantic role inside rich text. An
	## `Inherited` role paints exactly like the text around it; a `Themed`
	## role changes only the fill color. Inline roles never change the face,
	## size, or leading of their line: the package ships one regular face and
	## produces no synthetic bold or oblique, and the semantic role never
	## depends on this presentation.
	InlineColor : [Inherited, Themed(Color.SourceValue)]

	## Table presentation. Cells paint in the body style; `header_color`
	## changes only the fill color of header-cell text. `cell_padding` insets
	## cell text from each side of its column; `row_gap` separates
	## consecutive rows. `rule` is drawn centered in the row gap below the
	## header rows (and below every repeated header) and above the footer
	## rows, across the table's width, as a layout decoration artifact; it
	## must fit inside the row gap.
	TableStyle : {
		cell_padding : Layout.Unit,
		header_color : InlineColor,
		row_gap : Layout.Unit,
		rule : TableRule,
	}

	TableRule : [NoRule, Rule({ color : Color.SourceValue, width : Layout.Unit })]

	## The inline semantic roles whose presentation a theme can distinguish.
	InlineRole : [Code, Emphasis, Quote, Strong]

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
			code: Inherited,
			emphasis: Inherited,
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
			quote: Inherited,
			strong: Inherited,
			table: {
				cell_padding: Layout.Unit.from_raw(4000),
				header_color: Inherited,
				row_gap: Layout.Unit.from_raw(4000),
				rule: Rule({ color: black, width: Layout.Unit.from_raw(500) }),
			},
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
		code: theme.code,
		emphasis: theme.emphasis,
		font_selection: StyleFaces,
		heading: { ..theme.heading, font },
		page_margin: theme.page_margin,
		paragraph_spacing: theme.paragraph_spacing,
		quote: theme.quote,
		strong: theme.strong,
		table: theme.table,
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

	## Apply one color to every built-in text role. Inline roles return to
	## `Inherited`, so they paint in the same color as the text around them.
	with_text_color : Theme, Color.SourceValue -> Theme
	with_text_color = |theme, color| {
		..theme,
		body: { ..theme.body, color },
		code: Inherited,
		emphasis: Inherited,
		heading: { ..theme.heading, color },
		quote: Inherited,
		strong: Inherited,
		title: { ..theme.title, color },
	}

	## Paint `Pdf.emphasis` text in its own color. The face, size, and
	## leading stay those of the surrounding text.
	with_emphasis_color : Theme, Color.SourceValue -> Theme
	with_emphasis_color = |theme, color| { ..theme, emphasis: Themed(color) }

	## Paint `Pdf.strong` text in its own color.
	with_strong_color : Theme, Color.SourceValue -> Theme
	with_strong_color = |theme, color| { ..theme, strong: Themed(color) }

	## Paint `Pdf.code` text in its own color. A distinct monospace face for
	## inline code is not selectable yet; code uses the surrounding face.
	with_code_color : Theme, Color.SourceValue -> Theme
	with_code_color = |theme, color| { ..theme, code: Themed(color) }

	## Paint `Pdf.quote` text in its own color. Quotation marks remain
	## authored text.
	with_quote_color : Theme, Color.SourceValue -> Theme
	with_quote_color = |theme, color| { ..theme, quote: Themed(color) }

	## The presentation of one inline role; the innermost themed role around
	## a text run decides its color.
	inline_color : Theme, InlineRole -> InlineColor
	inline_color = |theme, role| match role {
		Code => theme.code
		Emphasis => theme.emphasis
		Quote => theme.quote
		Strong => theme.strong
	}

	## Paint table header-cell text in its own color.
	with_table_header_color : Theme, Color.SourceValue -> Theme
	with_table_header_color = |theme, color| { ..theme, table: { ..theme.table, header_color: Themed(color) } }

	## Replace the horizontal inset of cell text on each side of its column.
	with_table_cell_padding : Theme, Layout.Unit -> Theme
	with_table_cell_padding = |theme, cell_padding| { ..theme, table: { ..theme.table, cell_padding } }

	## Replace the vertical space between consecutive table rows.
	with_table_row_gap : Theme, Layout.Unit -> Theme
	with_table_row_gap = |theme, row_gap| { ..theme, table: { ..theme.table, row_gap } }

	## Replace the header and footer rules of tables, or remove them.
	with_table_rule : Theme, TableRule -> Theme
	with_table_rule = |theme, rule| { ..theme, table: { ..theme.table, rule } }

	table_style : Theme -> TableStyle
	table_style = |theme| theme.table

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
