import Color
import Font
import Layout

## The typed visual and layout policy of the convenience authoring path: a
## transparent record whose every field has a documented default. Write only
## the fields you change; the rest keep the versioned built-in values
## declared here, so `Theme.{}` (or `{}` where a `Theme` is expected) is
## the built-in theme:
##
## ```roc
## theme : Theme
## theme = {
##     face: faces.regular,
##     body: { color: charcoal, size: 11, leading: 16 },
##     headings: { all: { face: Face(faces.bold), size: 17, leading: 22 } },
##     inline: { code: { font: Face(faces.mono), scale: Percent(90) } },
##     page_margin: { top: 40, right: 54, bottom: 40, left: 54 },
## }
## ```
##
## A bare number where a `Layout.Unit` is expected is points. A nested
## record you write is completed from its own type's defaults, not from
## another theme's values: derive from an existing theme with
## `{ ..base, body: { ..base.body, leading: 16 } }`.
##
## A default is the value the theme holds when you leave a field out, never
## a fallback for an invalid value: preparation validates every field and
## rejects an invalid one with a located diagnostic (such as
## `text.inline_scale` at `theme.inline.code.scale`). Changing a default
## here is a reviewed package-version change, because it changes
## pagination and bytes. A theme holds no semantics: no roles, language,
## metadata, alternative text, or conformance choices.
Theme := {
	body : BodyStyle ?? {},
	bullet_indent : Layout.Unit ?? 18,
	face : Font.FaceId ?? Font.FaceId.from_index(0),
	font_selection : FontSelection ?? StyleFaces,
	headings : Headings ?? {},
	inline : InlineRoles ?? {},
	link : LinkStyle ?? {},
	page_margin : PageMargin ?? {},
	paragraph_spacing : Layout.Unit ?? 8,
	table : TableStyle ?? {},
	title : TitleStyle ?? {},
}.{

	## The built-in theme: every field at its default.
	default : Theme
	default = Theme.{}

	## The built-in text color.
	black : Color.SourceValue
	black = Srgb(Rgb({ blue: 0, green: 0, red: 0 }))

	## A text style's face: `ThemeFace` is the theme's `face`, `Face` any
	## face of the options' font registry, such as a bold face for
	## headings. It must cover the text it sets.
	FaceChoice : [Face(Font.FaceId), ThemeFace]

	## Body text: paragraphs, list items, table cells, and page furniture.
	BodyStyle := {
		# TODO(roc-lang/roc#11922): a default names a sibling by its
		# qualified name (`Theme.black`); a bare `black` is not in scope.
		color : Color.SourceValue ?? Theme.black,
		face : FaceChoice ?? ThemeFace,
		leading : Layout.Unit ?? 14,
		size : Layout.Unit ?? 11,
	}.{
		is_eq : _
	}

	## The document title (`Pdf.title`).
	TitleStyle := {
		# TODO(roc-lang/roc#11922): qualified sibling in a default.
		color : Color.SourceValue ?? Theme.black,
		face : FaceChoice ?? ThemeFace,
		leading : Layout.Unit ?? 28,
		size : Layout.Unit ?? 24,
	}.{
		is_eq : _
	}

	## One heading level's style.
	HeadingStyle := {
		# TODO(roc-lang/roc#11922): qualified sibling in a default.
		color : Color.SourceValue ?? Theme.black,
		face : FaceChoice ?? ThemeFace,
		leading : Layout.Unit ?? 18,
		size : Layout.Unit ?? 15,
	}.{
		is_eq : _
	}

	## The heading styles: `all` styles every level, and a level set to
	## `Own(style)` replaces it for that level alone, so `H1` and `H2` can
	## differ in face, size, leading, and color.
	Headings := {
		all : HeadingStyle ?? {},
		h1 : LevelStyle ?? SameAsAll,
		h2 : LevelStyle ?? SameAsAll,
		h3 : LevelStyle ?? SameAsAll,
		h4 : LevelStyle ?? SameAsAll,
		h5 : LevelStyle ?? SameAsAll,
		h6 : LevelStyle ?? SameAsAll,
	}.{
		is_eq : _
	}

	## One heading level: the `all` style, or its own.
	LevelStyle : [Own(HeadingStyle), SameAsAll]

	## A resolved text style, as preparation reads it: the style's face
	## choice is resolved against the theme's `face`.
	TextStyle : {
		color : Color.SourceValue,
		font : Font.FaceId,
		leading : Layout.Unit,
		size : Layout.Unit,
	}

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
	## and its size too unless the role has an `InlineScale`. The face must
	## be registered in the options' font registry; it applies under
	## `StyleFaces` selection, and a theme with an ordered font policy
	## rejects it (`text.inline_font_policy`) rather than ignoring it.
	InlineFont : [Face(Font.FaceId), Inherited]

	## The size of an inline role's text relative to its paragraph:
	## `Inherited` keeps the size of the text around it, and `Percent(p)`
	## paints it at `p` percent of the paragraph size (rounded down to a
	## thousandth of a point), from 50 to 100 (`text.inline_scale`
	## otherwise). The innermost role with a scale decides. A scaled run
	## sits on the paragraph's baseline and never changes its line's
	## leading, so a monospace `Code` face can match the body text's
	## apparent size.
	InlineScale : [Inherited, Percent(U64)]

	## The presentation of one inline role (`Pdf.code`, `Pdf.emphasis`,
	## `Pdf.quote`, `Pdf.strong`): its fill color, face, and size scale.
	InlineStyle := {
		color : InlineColor ?? Inherited,
		font : InlineFont ?? Inherited,
		scale : InlineScale ?? Inherited,
	}.{
		is_eq : _
	}

	## The presentation of each inline role.
	InlineRoles := {
		code : InlineStyle ?? {},
		emphasis : InlineStyle ?? {},
		quote : InlineStyle ?? {},
		strong : InlineStyle ?? {},
	}.{
		is_eq : _
	}

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
	## `footer_fill` the footer rows. The same fill in both is a solid
	## body, different fills are zebra stripes. A fill covers the row's box
	## across the table's width and half the row gap above and below it, so
	## filled neighbours meet; it is a layout decoration artifact painted
	## before the page's text, and never changes layout.
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
	## text, like the other rules, and never change layout
	## (`layout.table_rule` otherwise).
	TableStyle := {
		body_fills : BodyFills ?? {},
		body_rule : TableRule ?? NoRule,
		cell_padding : Layout.Unit ?? 4,
		column_rule : TableRule ?? NoRule,
		footer_fill : TableFill ?? NoFill,
		frame : TableRule ?? NoRule,
		header_color : InlineColor ?? Inherited,
		header_fill : TableFill ?? NoFill,
		row_gap : Layout.Unit ?? 4,
		row_header_color : InlineColor ?? Inherited,
		# TODO(roc-lang/roc#11922): qualified sibling in a default.
		rule : TableRule ?? Rule({ color: Theme.black, width: 0.5 }),
	}.{
		is_eq : _
	}

	## The fills of odd (first, third, ...) and even body rows.
	BodyFills := { even : TableFill ?? NoFill, odd : TableFill ?? NoFill }.{
		is_eq : _
	}

	TableRule : [NoRule, Rule({ color : Color.SourceValue, width : Layout.Unit })]

	## A row background: none, or a solid color.
	TableFill : [NoFill, Fill(Color.SourceValue)]

	## How link text is presented: its fill color (`Inherited` keeps the
	## surrounding text's color; an inner themed role such as `Strong`
	## still decides its own text) and an optional underline. An underline
	## is a decoration artifact painted in the link text's color below each
	## painted line run of the link: `offset` below the baseline to the top
	## of the line, `thickness` thick. The offset is at least zero and the
	## thickness positive, and together they fit below the body text
	## inside its leading (`text.link_underline` otherwise), so an
	## underline never reaches the next line. The link's text, semantics,
	## and annotation are unchanged.
	LinkStyle := { color : InlineColor ?? Inherited, underline : LinkUnderline ?? NoUnderline }.{
		is_eq : _
	}

	LinkUnderline : [NoUnderline, Underline({ offset : Layout.Unit, thickness : Layout.Unit })]

	## Inline colors that a scoped group of blocks (`Pdf.scoped`) paints in
	## place of the theme's: for example a warning callout's `Strong` label
	## in amber and a note callout's in teal
	## (`Pdf.scoped({ strong: Themed(amber) }, blocks)`). A role the scope
	## leaves `Inherited` keeps the color of the next enclosing scope, then
	## the theme's. `text` colors the scope's ordinary text: the text of its
	## paragraphs, headings, and list items and their generated labels,
	## beneath any inline role color, so light text can sit on a dark
	## custom-block panel. Table header colors still win inside a table.
	## Scopes change only fill colors, never faces, sizes, or semantics.
	Scope := {
		code : InlineColor ?? Inherited,
		emphasis : InlineColor ?? Inherited,
		link : InlineColor ?? Inherited,
		quote : InlineColor ?? Inherited,
		strong : InlineColor ?? Inherited,
		text : InlineColor ?? Inherited,
	}.{
		is_eq : _

		## The scope's color for one role.
		color : Scope, ScopeRole -> InlineColor
		color = |scope, role| match role {
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
	## from registry insertion order. Style faces remain recorded, but the
	## pipeline resolves fonts per grapheme cluster through the policy's
	## registry search space.
	FontSelection : [Policy(Font.PolicyId), StyleFaces]

	## The four page margins.
	PageMargin := {
		bottom : Layout.Unit ?? 72,
		left : Layout.Unit ?? 72,
		right : Layout.Unit ?? 72,
		top : Layout.Unit ?? 72,
	}.{
		is_eq : _
	}

	## The resolved body style.
	body_style : Theme -> TextStyle
	body_style = |theme| {
		style = theme.body
		{ color: style.color, font: resolve_face(theme, style.face), leading: style.leading, size: style.size }
	}

	## The resolved title style.
	title_style : Theme -> TextStyle
	title_style = |theme| {
		style = theme.title
		{ color: style.color, font: resolve_face(theme, style.face), leading: style.leading, size: style.size }
	}

	## The resolved style of one heading level.
	heading_level_style : Theme, HeadingLevel -> TextStyle
	heading_level_style = |theme, level| {
		headings = theme.headings
		own = match level {
			H1 => headings.h1
			H2 => headings.h2
			H3 => headings.h3
			H4 => headings.h4
			H5 => headings.h5
			H6 => headings.h6
		}
		style = match own {
			Own(value) => value
			SameAsAll => headings.all
		}
		{ color: style.color, font: resolve_face(theme, style.face), leading: style.leading, size: style.size }
	}

	## The body face.
	body_font : Theme -> Font.FaceId
	body_font = |theme| resolve_face(theme, theme.body.face)

	## The presentation of one inline role.
	inline_style : Theme, InlineRole -> InlineStyle
	inline_style = |theme, role| match role {
		Code => theme.inline.code
		Emphasis => theme.inline.emphasis
		Quote => theme.inline.quote
		Strong => theme.inline.strong
	}

	## The size scale of one inline role.
	inline_scale : Theme, InlineRole -> InlineScale
	inline_scale = |theme, role| inline_style(theme, role).scale

	## The face of one inline role; the innermost role with a face around a
	## text run decides its face.
	inline_font : Theme, InlineRole -> InlineFont
	inline_font = |theme, role| inline_style(theme, role).font

	## The color of one inline role; the innermost themed role around a
	## text run decides its color.
	inline_color : Theme, InlineRole -> InlineColor
	inline_color = |theme, role| inline_style(theme, role).color
}

resolve_face : Theme, Theme.FaceChoice -> Font.FaceId
resolve_face = |theme, choice| match choice {
	Face(face) => face
	ThemeFace => theme.face
}

# Every nested field default is its type's own defaults (`?? {}`), so a
# partial nested literal and an omitted field agree: the one exception
# would be a field default of `X.{ ... }` that differs from `X.{}`.
expect {
	theme = Theme.{}
	inline = theme.inline
	theme.body == Theme.BodyStyle.{} and theme.title == Theme.TitleStyle.{} and theme.headings == Theme.Headings.{} and theme.headings.all == Theme.HeadingStyle.{} and theme.inline == Theme.InlineRoles.{} and inline.code == Theme.InlineStyle.{} and inline.emphasis == Theme.InlineStyle.{} and inline.quote == Theme.InlineStyle.{} and inline.strong == Theme.InlineStyle.{} and theme.link == Theme.LinkStyle.{} and theme.table == Theme.TableStyle.{} and theme.table.body_fills == Theme.BodyFills.{} and theme.page_margin == Theme.PageMargin.{} and Theme.Scope.{} == { code: Inherited, emphasis: Inherited, link: Inherited, quote: Inherited, strong: Inherited, text: Inherited }
}

# The versioned built-in values: 11/14 pt body, 24/28 pt title, 15/18 pt
# headings in black in the packaged face, 72 pt margins, 8 pt paragraph
# spacing, 18 pt list indent, 4 pt cell padding and row gap, and a
# 0.5 pt black rule under table headers.
expect {
	theme = Theme.default
	black = Srgb(Rgb({ blue: 0, green: 0, red: 0 }))
	body = theme.body_style()
	title = theme.title_style()
	heading = theme.heading_level_style(H4)
	face = Font.FaceId.from_index(0)
	body == { color: black, font: face, leading: Layout.Unit.points(14), size: Layout.Unit.points(11) } and title == { color: black, font: face, leading: Layout.Unit.points(28), size: Layout.Unit.points(24) } and heading == { color: black, font: face, leading: Layout.Unit.points(18), size: Layout.Unit.points(15) } and theme.page_margin == { bottom: Layout.Unit.points(72), left: Layout.Unit.points(72), right: Layout.Unit.points(72), top: Layout.Unit.points(72) } and theme.paragraph_spacing == Layout.Unit.points(8) and theme.bullet_indent == Layout.Unit.points(18) and theme.table.cell_padding == Layout.Unit.points(4) and theme.table.row_gap == Layout.Unit.points(4) and theme.table.rule == Rule({ color: black, width: Layout.Unit.millipoints(500) }) and theme.font_selection == StyleFaces
}

# One heading level's own style replaces `all` for that level alone, and
# a style's `ThemeFace` resolves to the theme's face.
expect {
	theme : Theme
	theme = { face: Font.FaceId.from_index(2), headings: { all: { size: 16 }, h2: Own({ size: 20, face: Face(Font.FaceId.from_index(5)) }) } }
	h1 = theme.heading_level_style(H1)
	h2 = theme.heading_level_style(H2)
	h1.size == Layout.Unit.points(16) and h1.font == Font.FaceId.from_index(2) and h2.size == Layout.Unit.points(20) and h2.font == Font.FaceId.from_index(5) and h2.leading == Layout.Unit.points(18)
}

# A partial nested literal takes its own type's defaults, not a base
# theme's values; `{ ..base.body, ... }` keeps them.
expect {
	base : Theme
	base = { body: { size: 12, leading: 16 } }
	reset = { ..base, body: { leading: 20 } }
	kept = { ..base, body: { ..base.body, leading: 20 } }
	reset.body.size == Layout.Unit.points(11) and kept.body.size == Layout.Unit.points(12) and kept.body.leading == Layout.Unit.points(20)
}
