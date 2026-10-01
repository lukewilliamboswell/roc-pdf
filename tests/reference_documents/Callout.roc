import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## A "key figures" callout: a separately authored extension of the
## custom-block seam. It uses only the public `Pdf`, `Scene`, `Layout`,
## `Color`, and `Theme` surface: no private store, no PDF object, and no
## content-stream operator crosses into it.
##
## Its measurement contract: every line of the callout is one short
## paragraph that the extension expects to fit on one line of the theme's
## body style inside the panel. It measures its height from the theme's
## public metrics (body leading and paragraph spacing) as twice the inset
## plus one leading per line plus the spacing between lines. The package
## lays the paragraphs out and proves they fit that height; a line that
## wraps makes the callout under-measured, which preparation rejects as
## `layout.custom_block_measure` rather than clipping it. The callout is
## `Unsplittable`: it moves whole to the next page.
##
## Its semantic ownership: each figure stays an ordinary paragraph, its
## label in `Strong` and its value in plain text, which the package groups
## in a `Div`; the tinted rounded panel and its accent bar are decoration
## owned by the block and painted behind them.
Callout :: [].{

	## The callout's panel tint, outline, and start-edge accent bar.
	Style : { accent : Color.SourceValue, fill : Color.SourceValue, radius : Layout.Unit, stroke : Color.SourceValue }

	default_style : Style
	default_style = {
		accent: "#183454",
		fill: "#F7F1E6",
		radius: 6,
		stroke: "#DCC69A",
	}

	## A callout `width` wide holding one paragraph per figure: its label
	## (with a colon) in `Strong`, then its value.
	key_figures : Theme, { figures : List((Str, Str)), name : Str, width : Layout.Unit } -> Document.Block
	key_figures = |theme, { figures, name, width }| with_style(theme, default_style, { figures, name, width })

	with_style : Theme, Style, { figures : List((Str, Str)), name : Str, width : Layout.Unit } -> Document.Block
	with_style = |theme, style, { figures, name, width }| {
		size = measure(theme, figures.len(), width)
		Pdf.custom_block({
			contents: figures.map(|(label, value)| Pdf.rich_paragraph([Pdf.strong([Pdf.text("${label}:")]), Pdf.text(" ${value}")])),
			inset: inset,
			name,
			panel: panel(style, size),
			size,
		})
	}

	## The measured box: the extension's own arithmetic over public theme
	## metrics.
	measure : Theme, U64, Layout.Unit -> Layout.Size
	measure = |theme, count, width| {
		leading = Theme.body_style(theme).leading.raw()
		spacing = theme.paragraph_spacing.raw()
		lines = count.to_i64_wrap()
		gaps = if lines == 0 0 else lines - 1
		{ height: Layout.Unit.from_raw(inset.raw() * 2 + leading * lines + spacing * gaps), width }
	}

	## A measured box with an explicit height, for callers that measured
	## differently (and for the adverse variants).
	with_height : Theme, { height : Layout.Unit, lines : List(Str), name : Str, width : Layout.Unit } -> Document.Block
	with_height = |_theme, { height, lines, name, width }| {
		size = { height, width }
		Pdf.custom_block({
			contents: lines.map(|line| Pdf.paragraph(line)),
			inset: inset,
			name,
			panel: panel(default_style, size),
			size,
		})
	}
}

## Content sits 10 pt inside the panel on every side.
inset : Layout.Unit
inset = 10

## A rounded rectangle filling the measured box, with a 1 pt outline kept
## inside it (the stroke's half width is the path's margin), and a 4 pt
## accent bar along its start edge between the corners.
panel : Callout.Style, Layout.Size -> Scene.Drawing
panel = |style, size| {
	half = 500
	r = style.radius.raw()
	k = r * 552 // 1000
	left = half
	bottom = half
	right = size.width.raw() - half
	top = size.height.raw() - half
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	outline = Scene.PathBuilder.start
		.move_to(point(left + r, bottom))
		.line_to(point(right - r, bottom))
		.cubic_to({ control_1: point(right - r + k, bottom), control_2: point(right, bottom + r - k), end: point(right, bottom + r) })
		.line_to(point(right, top - r))
		.cubic_to({ control_1: point(right, top - r + k), control_2: point(right - r + k, top), end: point(right - r, top) })
		.line_to(point(left + r, top))
		.cubic_to({ control_1: point(left + r - k, top), control_2: point(left, top - r + k), end: point(left, top - r) })
		.line_to(point(left, bottom + r))
		.cubic_to({ control_1: point(left, bottom + r - k), control_2: point(left + r - k, bottom), end: point(left + r, bottom) })
		.close()
		.finish()
	bar = Scene.PathBuilder.start.rectangle({ origin: point(left, bottom + r), size: { height: Layout.Unit.from_raw(top - bottom - 2 * r), width: 4 } }).finish()
	Scene.Drawing.empty
		.path(outline, { fill: AuthorSolidFill(style.fill), stroke: AuthorSolidStroke({ color: style.stroke, width: 1 }) })
		.path(bar, Scene.solid_fill(style.accent))
}
