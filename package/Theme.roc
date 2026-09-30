import Color
import Font
import Layout

Theme :: {
	body : TextStyle,
	bullet_indent : Layout.Unit,
	code : InlineColor,
	emphasis : InlineColor,
	font_selection : FontSelection,
	headings : HeadingStyles,
	inline_fonts : InlineFonts,
	inline_scales : InlineScales,
	link : LinkStyle,
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

	## The text style of each heading level, `H1` to `H6`. Each level has
	## its own face, size, leading, and color; `with_heading_style` sets all
	## six and `with_heading_level_style` one.
	HeadingStyles : { h1 : TextStyle, h2 : TextStyle, h3 : TextStyle, h4 : TextStyle, h5 : TextStyle, h6 : TextStyle }

	## A heading level, as `Pdf.heading` numbers it: `H1` is level 1.
	HeadingLevel : [H1, H2, H3, H4, H5, H6]

	## The color of an inline semantic role inside rich text. An `Inherited`
	## role paints in the color of the text around it; a `Themed` role
	## changes the fill color. Inline roles never change the leading of
	## their line (`InlineScale` may only shrink their text), the package
	## produces no synthetic bold or oblique, and the semantic role never
	## depends on this presentation.
	InlineColor : [Inherited, Themed(Color.SourceValue)]

	## The face of an inline semantic role: `Inherited` paints in the face of
	## the text around it, and `Face` in a caller-registered face (for
	## example a monospace face for `Code`). The innermost role with a face
	## decides the face of a text run; its leading stays the paragraph's,
	## and its size too unless the role has an `InlineScale`.
	InlineFont : [Face(Font.FaceId), Inherited]

	InlineFonts : { code : InlineFont, emphasis : InlineFont, quote : InlineFont, strong : InlineFont }

	## The size of an inline role's text relative to its paragraph:
	## `Inherited` keeps the size of the text around it, and `Percent(p)`
	## paints it at `p` percent of the paragraph size (rounded down to a
	## thousandth of a point), from 50 to 100. The innermost role with a
	## scale decides. A scaled run sits on the paragraph's baseline and
	## never changes its line's leading, so a monospace `Code` face can
	## match the body text's apparent size.
	InlineScale : [Inherited, Percent(U64)]

	InlineScales : { code : InlineScale, emphasis : InlineScale, quote : InlineScale, strong : InlineScale }

	## Table presentation. Cells paint in the body style; `header_color`
	## changes only the fill color of column header cells (scope `Column` or
	## `Both`), and `row_header_color` that of row header cells (scope
	## `Row`), so a first column of row headers need not take the column
	## header color. `cell_padding` insets
	## cell text from each side of its column; `row_gap` separates
	## consecutive rows. `rule` is drawn centered in the row gap below the
	## header rows (and below every repeated header) and above the footer
	## rows, across the table's width, as a layout decoration artifact; it
	## must fit inside the row gap. `body_rule` is drawn the same way in the
	## gap above every body row except the first on its page, separating
	## consecutive body rows.
	##
	## Row fills shade whole rows behind their text: `header_fill` the
	## header rows (and every repeated header), `body_fills` the body rows,
	## alternating `odd` (the first body row) and `even` by the row's index
	## in the table body, so stripes stay stable across pages, and
	## `footer_fill` the footer rows. A fill covers the row's box across the
	## table's width and half the row gap above and below it, so filled
	## neighbours meet; it is a layout decoration artifact painted before
	## the page's text, and never changes layout.
	##
	## Columns have no gap of their own: adjacent cells' boxes abut, and the
	## space between two columns' text is the two cells' padding. A
	## `column_rule` is drawn centered on every boundary between adjacent
	## cells of a row (never through a spanning cell), from half the row
	## gap above the row to half the row gap below it, so the rules of
	## consecutive rows meet; it must fit in that padding (at most twice
	## `cell_padding`). A `frame` outlines each page's part of a table's rows
	## (repeated header rows included, the caption excluded) inside the
	## rows' outer boxes, so it must fit in the cell padding and in half
	## the row gap. Both are layout decoration artifacts painted after the
	## text, like the other rules, and never change layout.
	TableStyle : {
		body_fills : { even : TableFill, odd : TableFill },
		body_rule : TableRule,
		cell_padding : Layout.Unit,
		column_rule : TableRule,
		footer_fill : TableFill,
		frame : TableRule,
		header_color : InlineColor,
		header_fill : TableFill,
		row_gap : Layout.Unit,
		row_header_color : InlineColor,
		rule : TableRule,
	}

	TableRule : [NoRule, Rule({ color : Color.SourceValue, width : Layout.Unit })]

	## A row background: none, or a solid color.
	TableFill : [NoFill, Fill(Color.SourceValue)]

	## How link text is presented: its fill color (`Inherited` keeps the
	## surrounding text's color; an inner themed role such as `Strong`
	## still decides its own text) and an optional underline. An underline
	## is a decoration artifact painted in the link text's color below each
	## painted line run of the link: `offset` below the baseline to the top
	## of the line, `thickness` thick. The link's text, semantics, and
	## annotation are unchanged.
	LinkStyle : { color : InlineColor, underline : LinkUnderline }

	LinkUnderline : [NoUnderline, Underline({ offset : Layout.Unit, thickness : Layout.Unit })]

	## Inline colors that a scoped group of blocks (`Pdf.scoped`) paints in
	## place of the theme's: for example a warning callout's `Strong` label
	## in amber and a note callout's in teal. A role the scope leaves
	## `Inherited` keeps the color of the next enclosing scope, then the
	## theme's. `Text` colors the scope's ordinary text: the text of its
	## paragraphs, headings, and list items and their generated labels,
	## beneath any inline role color, so light text can sit on a dark
	## custom-block panel. Table header colors still win inside a table.
	## Scopes change only fill colors, never faces, sizes, or semantics.
	Scope :: { code : InlineColor, emphasis : InlineColor, link : InlineColor, quote : InlineColor, strong : InlineColor, text : InlineColor }.{

		## A scope that overrides nothing.
		empty : Scope
		empty = Scope.({ code: Inherited, emphasis: Inherited, link: Inherited, quote: Inherited, strong: Inherited, text: Inherited })

		## Paint one role's text, or link text, in `color` inside the scope.
		with_color : Scope, ScopeRole, Color.SourceValue -> Scope
		with_color = |Scope.(scope), role, color| Scope.(
			match role {
				Code => { ..scope, code: Themed(color) }
				Emphasis => { ..scope, emphasis: Themed(color) }
				Link => { ..scope, link: Themed(color) }
				Quote => { ..scope, quote: Themed(color) }
				Strong => { ..scope, strong: Themed(color) }
				Text => { ..scope, text: Themed(color) }
			},
		)

		## The scope's color for one role.
		color : Scope, ScopeRole -> InlineColor
		color = |Scope.(scope), role| match role {
			Code => scope.code
			Emphasis => scope.emphasis
			Link => scope.link
			Quote => scope.quote
			Strong => scope.strong
			Text => scope.text
		}
	}

	## The roles a scope can color: the inline roles, link text, and the
	## scope's ordinary text.
	ScopeRole : [Code, Emphasis, Link, Quote, Strong, Text]

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

		## Every heading level shares one style by default.
		heading = {
			color: black,
			font: Font.FaceId.from_index(0),
			leading: Layout.Unit.from_raw(18000),
			size: Layout.Unit.from_raw(15000),
		}

		Theme.{
			body,
			bullet_indent: Layout.Unit.from_raw(18000),
			code: Inherited,
			emphasis: Inherited,
			font_selection: StyleFaces,
			inline_fonts: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited },
			inline_scales: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited },
			link: { color: Inherited, underline: NoUnderline },
			headings: { h1: heading, h2: heading, h3: heading, h4: heading, h5: heading, h6: heading },
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
				body_fills: { even: NoFill, odd: NoFill },
				body_rule: NoRule,
				cell_padding: Layout.Unit.from_raw(4000),
				column_rule: NoRule,
				footer_fill: NoFill,
				frame: NoRule,
				header_color: Inherited,
				header_fill: NoFill,
				row_gap: Layout.Unit.from_raw(4000),
				row_header_color: Inherited,
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
		headings: map_headings(theme.headings, |style| { ..style, font }),
		inline_fonts: theme.inline_fonts,
		inline_scales: theme.inline_scales,
		link: theme.link,
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

	## Change every heading level's color while retaining its metrics and
	## selected face.
	with_heading_color : Theme, Color.SourceValue -> Theme
	with_heading_color = |theme, color| { ..theme, headings: map_headings(theme.headings, |style| { ..style, color }) }

	## Change title color while retaining its metrics and selected face.
	with_title_color : Theme, Color.SourceValue -> Theme
	with_title_color = |theme, color| { ..theme, title: { ..theme.title, color } }

	## Apply one color to every built-in text role. Inline roles and links
	## return to `Inherited`, so they paint in the same color as the text
	## around them.
	with_text_color : Theme, Color.SourceValue -> Theme
	with_text_color = |theme, color| {
		..theme,
		body: { ..theme.body, color },
		code: Inherited,
		emphasis: Inherited,
		headings: map_headings(theme.headings, |style| { ..style, color }),
		link: { ..theme.link, color: Inherited },
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

	## Paint `Pdf.code` text in its own color; `with_inline_font` selects a
	## face for it.
	with_code_color : Theme, Color.SourceValue -> Theme
	with_code_color = |theme, color| { ..theme, code: Themed(color) }

	## Paint `Pdf.quote` text in its own color. Quotation marks remain
	## authored text.
	with_quote_color : Theme, Color.SourceValue -> Theme
	with_quote_color = |theme, color| { ..theme, quote: Themed(color) }

	## Paint one inline role's text in a caller-registered face, such as a
	## monospace face for `Code`. The face must be registered in the
	## options' font registry; it applies under `StyleFaces` selection, and
	## a theme with an ordered font policy rejects it
	## (`text.inline_font_policy`) rather than ignoring it.
	with_inline_font : Theme, InlineRole, Font.FaceId -> Theme
	with_inline_font = |theme, role, face| {
		fonts = theme.inline_fonts
		updated = match role {
			Code => { ..fonts, code: Face(face) }
			Emphasis => { ..fonts, emphasis: Face(face) }
			Quote => { ..fonts, quote: Face(face) }
			Strong => { ..fonts, strong: Face(face) }
		}
		{ ..theme, inline_fonts: updated }
	}

	## Paint link text (inline links and link blocks) in its own color.
	with_link_color : Theme, Color.SourceValue -> Theme
	with_link_color = |theme, color| { ..theme, link: { ..theme.link, color: Themed(color) } }

	## Underline link text, or remove the underline with `NoUnderline`. The
	## offset is at least zero and the thickness positive, and together they
	## fit below the body text inside its leading (`text.link_underline`
	## otherwise, when the document is prepared), so an underline never
	## reaches the next line.
	with_link_underline : Theme, LinkUnderline -> Theme
	with_link_underline = |theme, underline| { ..theme, link: { ..theme.link, underline } }

	link_style : Theme -> LinkStyle
	link_style = |theme| theme.link

	## Paint one inline role's text at `percent` of its paragraph's size,
	## from 50 to 100 (`text.inline_scale` otherwise, when the document is
	## prepared). Use it to balance a caller face whose letters look larger
	## than the body face's at the same size.
	with_inline_scale : Theme, InlineRole, U64 -> Theme
	with_inline_scale = |theme, role, percent| {
		scales = theme.inline_scales
		scale = Percent(percent)
		updated = match role {
			Code => { ..scales, code: scale }
			Emphasis => { ..scales, emphasis: scale }
			Quote => { ..scales, quote: scale }
			Strong => { ..scales, strong: scale }
		}
		{ ..theme, inline_scales: updated }
	}

	## The size scale of one inline role.
	inline_scale : Theme, InlineRole -> InlineScale
	inline_scale = |theme, role| match role {
		Code => theme.inline_scales.code
		Emphasis => theme.inline_scales.emphasis
		Quote => theme.inline_scales.quote
		Strong => theme.inline_scales.strong
	}

	## The face of one inline role; the innermost role with a face around a
	## text run decides its face.
	inline_font : Theme, InlineRole -> InlineFont
	inline_font = |theme, role| match role {
		Code => theme.inline_fonts.code
		Emphasis => theme.inline_fonts.emphasis
		Quote => theme.inline_fonts.quote
		Strong => theme.inline_fonts.strong
	}

	## The presentation of one inline role; the innermost themed role around
	## a text run decides its color.
	inline_color : Theme, InlineRole -> InlineColor
	inline_color = |theme, role| match role {
		Code => theme.code
		Emphasis => theme.emphasis
		Quote => theme.quote
		Strong => theme.strong
	}

	## Paint column header-cell text (scope `Column` or `Both`) in its own
	## color.
	with_table_header_color : Theme, Color.SourceValue -> Theme
	with_table_header_color = |theme, color| { ..theme, table: { ..theme.table, header_color: Themed(color) } }

	## Paint row header-cell text (scope `Row`) in its own color, separately
	## from the column header color.
	with_table_row_header_color : Theme, Color.SourceValue -> Theme
	with_table_row_header_color = |theme, color| { ..theme, table: { ..theme.table, row_header_color: Themed(color) } }

	## Replace the horizontal inset of cell text on each side of its column.
	with_table_cell_padding : Theme, Layout.Unit -> Theme
	with_table_cell_padding = |theme, cell_padding| { ..theme, table: { ..theme.table, cell_padding } }

	## Replace the vertical space between consecutive table rows.
	with_table_row_gap : Theme, Layout.Unit -> Theme
	with_table_row_gap = |theme, row_gap| { ..theme, table: { ..theme.table, row_gap } }

	## Replace the header and footer rules of tables, or remove them.
	with_table_rule : Theme, TableRule -> Theme
	with_table_rule = |theme, rule| { ..theme, table: { ..theme.table, rule } }

	## Shade the header rows, including every repeated header.
	with_table_header_fill : Theme, Color.SourceValue -> Theme
	with_table_header_fill = |theme, color| { ..theme, table: { ..theme.table, header_fill: Fill(color) } }

	## Shade the body rows: `odd` for the first, third, ... body row and
	## `even` for the second, fourth, ...; the same fill in both is a solid
	## body, different fills are zebra stripes.
	with_table_body_fills : Theme, { even : TableFill, odd : TableFill } -> Theme
	with_table_body_fills = |theme, body_fills| { ..theme, table: { ..theme.table, body_fills } }

	## Shade the footer rows.
	with_table_footer_fill : Theme, Color.SourceValue -> Theme
	with_table_footer_fill = |theme, color| { ..theme, table: { ..theme.table, footer_fill: Fill(color) } }

	## Rule between consecutive body rows, or `NoRule` (the default).
	with_table_body_rule : Theme, TableRule -> Theme
	with_table_body_rule = |theme, body_rule| { ..theme, table: { ..theme.table, body_rule } }

	## Rule between adjacent cells of every row, or `NoRule` (the default).
	## It lies in the cells' padding, so it may be at most twice the cell
	## padding wide (`layout.table_rule`).
	with_table_column_rule : Theme, TableRule -> Theme
	with_table_column_rule = |theme, column_rule| { ..theme, table: { ..theme.table, column_rule } }

	## Outline each page's part of a table's rows, or `NoRule` (the
	## default). It lies inside the rows' outer boxes, so it may be at most
	## the cell padding and half the row gap wide (`layout.table_rule`).
	with_table_frame : Theme, TableRule -> Theme
	with_table_frame = |theme, frame| { ..theme, table: { ..theme.table, frame } }

	table_style : Theme -> TableStyle
	table_style = |theme| theme.table

	## Replace the complete body style while preserving every other theme role.
	with_body_style : Theme, TextStyle -> Theme
	with_body_style = |theme, style| { ..theme, body: style }

	## Replace the complete style of every heading level while preserving
	## every other theme role. The face may be any face of the options' font
	## registry, such as a bold face; it must cover the heading text.
	with_heading_style : Theme, TextStyle -> Theme
	with_heading_style = |theme, style| { ..theme, headings: { h1: style, h2: style, h3: style, h4: style, h5: style, h6: style } }

	## Replace the complete style of one heading level, so `H1` and `H2` can
	## differ in face, size, leading, and color.
	with_heading_level_style : Theme, HeadingLevel, TextStyle -> Theme
	with_heading_level_style = |theme, level, style| {
		headings = theme.headings
		updated = match level {
			H1 => { ..headings, h1: style }
			H2 => { ..headings, h2: style }
			H3 => { ..headings, h3: style }
			H4 => { ..headings, h4: style }
			H5 => { ..headings, h5: style }
			H6 => { ..headings, h6: style }
		}
		{ ..theme, headings: updated }
	}

	## Replace the complete title style while preserving every other theme
	## role. Like a heading style, its face may be any registered face.
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

	## The style of level-1 headings.
	heading_style : Theme -> TextStyle
	heading_style = |theme| theme.headings.h1

	## The style of one heading level.
	heading_level_style : Theme, HeadingLevel -> TextStyle
	heading_level_style = |theme, level| match level {
		H1 => theme.headings.h1
		H2 => theme.headings.h2
		H3 => theme.headings.h3
		H4 => theme.headings.h4
		H5 => theme.headings.h5
		H6 => theme.headings.h6
	}

	title_style : Theme -> TextStyle
	title_style = |theme| theme.title

	bullet_indent : Theme -> Layout.Unit
	bullet_indent = |theme| theme.bullet_indent

	page_margin : Theme -> PageMargin
	page_margin = |theme| theme.page_margin

	paragraph_spacing : Theme -> Layout.Unit
	paragraph_spacing = |theme| theme.paragraph_spacing
}

map_headings : Theme.HeadingStyles, (Theme.TextStyle -> Theme.TextStyle) -> Theme.HeadingStyles
map_headings = |headings, update| { h1: update(headings.h1), h2: update(headings.h2), h3: update(headings.h3), h4: update(headings.h4), h5: update(headings.h5), h6: update(headings.h6) }

# One heading level's style changes without touching the others.
expect {
	large = { ..Theme.default.heading_style(), size: Layout.Unit.from_raw(20000) }
	theme = Theme.default.with_heading_level_style(H2, large)
	Layout.Unit.raw(theme.heading_level_style(H2).size) == 20000 and Layout.Unit.raw(theme.heading_level_style(H1).size) == 15000 and Layout.Unit.raw(theme.heading_level_style(H3).size) == 15000
}

# Nested theme font references preserve their dense resource index.
expect Font.FaceId.from_index(3).index() == 3

# The versioned default theme uses an exact 72-point left margin.
expect Layout.Unit.raw(Theme.default.page_margin.left) == 72000
