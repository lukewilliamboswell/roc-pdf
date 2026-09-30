app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "fonts/NotoSerif-Regular.ttf" as regular_bytes : List(U8)
import "fonts/NotoSerif-Bold.ttf" as bold_bytes : List(U8)
import "fonts/NotoSerif-Italic.ttf" as italic_bytes : List(U8)

## A members' quarterly report for a regional cooperative: a navy cover
## band in the first-page header, a navy "key figures" callout and a
## tinted diary callout authored through the custom-block seam and measured
## by the package, a striped KPI scorecard with shaded status cells and a
## segment table with a totals footer, two vector charts drawn from `Scene`
## groups (monthly revenue with a margin line and its data table, and
## progress against annual targets kept with its notes), and running
## headers inset above a ruled backdrop with `Page N of M` on every later
## page.
main! = |_args| {
	fonts = register_fonts({})?
	options = Pdf.Options.default.with_theme(with_faces(theme, fonts)).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-AU", title: "Northstar Cooperative quarterly report, Q2 FY2027" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2027-01-18T00:00:00Z")
		.with_modified("2027-01-18T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "quarterly-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote quarterly-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, italic : Font.FaceId, registry : Font.Registry }

## Noto Serif Regular, Bold, and Italic, each retained
## byte-for-byte from its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin = [Font.Script.from_iso15924("Latn")]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	italic = add(bold.registry, italic_bytes)?
	Ok({ regular: regular.face, bold: bold.face, italic: italic.face, registry: italic.registry })
}

## Regular for body text; Bold for the title, headings, and `Pdf.strong`;
## Italic for `Pdf.emphasis`. Level-2 headings are smaller and teal.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	title = Theme.title_style(base)
	heading = Theme.heading_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_level_style(H1, { ..heading, font: faces.bold })
		.with_heading_level_style(H2, { ..heading, font: faces.bold, color: teal, size: points(12), leading: points(17) })
		.with_inline_font(Strong, faces.bold)
		.with_inline_font(Emphasis, faces.italic)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

navy : Color.SourceValue
navy = Color.srgb8({ red: 18, green: 42, blue: 74 })

teal : Color.SourceValue
teal = Color.srgb8({ red: 0, green: 122, blue: 128 })

amber : Color.SourceValue
amber = Color.srgb8({ red: 214, green: 140, blue: 30 })

slate : Color.SourceValue
slate = Color.srgb8({ red: 150, green: 164, blue: 182 })

grid : Color.SourceValue
grid = Color.srgb8({ red: 218, green: 225, blue: 233 })

ink : Color.SourceValue
ink = Color.srgb8({ red: 34, green: 40, blue: 49 })

white : Color.SourceValue
white = Color.srgb8({ red: 255, green: 255, blue: 255 })

## A4 with 50 pt side margins: a 495 pt measure.
body_width : I64
body_width = 495

theme : Theme
theme = {
	base_title = Theme.title_style(Theme.default)
	base_heading = Theme.heading_style(Theme.default)
	base_body = Theme.body_style(Theme.default)
	Theme.default
		.with_page_margin({ top: points(40), right: points(50), bottom: points(40), left: points(50) })
		.with_title_style({ ..base_title, color: navy, size: points(30), leading: points(36) })
		.with_heading_style({ ..base_heading, color: navy, size: points(15), leading: points(20) })
		.with_body_style({ ..base_body, color: ink, size: points(10), leading: points(14) })
		.with_paragraph_spacing(points(7))
		.with_table_header_color(teal)
		.with_table_header_fill(Color.srgb8({ red: 232, green: 244, blue: 244 }))
		.with_table_body_fills({ odd: NoFill, even: Fill(Color.srgb8({ red: 246, green: 248, blue: 250 })) })
		.with_table_footer_fill(Color.srgb8({ red: 236, green: 241, blue: 247 }))
		.with_table_rule(Rule({ color: teal, width: points(1) }))
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(5))
		.with_link_color(teal)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1300), thickness: Layout.Unit.millipoints(500) }))
}

## ---------------------------------------------------------------------
## Page templates: a navy cover band on the first page, and a running
## header with a hairline on every later page. Both carry `Page N of M`.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(14),
	start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative Ltd · Members' quarterly report")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

## The cover band: a navy field over a teal keyline, with the cooperative's
## mark (three rising bars and a star-like diamond) at its end.
cover_band : Scene.Drawing
cover_band = {
	var $band = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 6, body_width, 50), navy)
	$band = Scene.rectangle($band, Layout.rect(0, 0, body_width, 4), teal)

	# Faint diagonal hatching across the band's start, for texture.
	var $x = 4
	while $x < 220 {
		$band = $band.path(Scene.path({}).move_to(Layout.point($x, 8)).line_to(Layout.point($x + 28, 54)).finish(), Scene.solid_stroke(Color.srgb8({ red: 34, green: 62, blue: 98 }), points(2)))
		$x = $x + 14
	}

	## The mark is its own drawing, grouped at the band's end.
	$band.group(Layout.point(body_width - 76, 17), coop_mark)
}

## The cooperative's mark: three rising bars and a diamond, from its own
## origin.
coop_mark : Scene.Drawing
coop_mark = {
	bar = |x, height| Scene.path({}).move_to(Layout.point(x, 0)).line_to(Layout.point(x + 8, 0)).line_to(Layout.point(x + 8, height)).line_to(Layout.point(x, height)).close().finish()
	Scene.drawing({})
		.path(bar(0, 12), Scene.solid_fill(slate))
		.path(bar(12, 20), Scene.solid_fill(teal))
		.path(bar(24, 28), Scene.solid_fill(white))
		.path(Scene.path({}).move_to(Layout.point(44, 20)).line_to(Layout.point(50, 28)).line_to(Layout.point(56, 20)).line_to(Layout.point(50, 12)).close().finish(), Scene.solid_fill(amber))
}

hairline : Scene.Drawing
hairline = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(600), width: points(body_width) } }, teal)

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.region({ height: points(56), start: [Pdf.furniture_image(cover_band)], center: [], end: [] }),
		lead: Pdf.no_lead,
		footer,
		gap: points(18),
	}),
	continuation: Pdf.page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(21),
					start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative · Q2 FY2027")])],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("Members' quarterly report")])],
				}),
				hairline,
			),
			points(3),
		),
		footer,
		gap: points(14),
	}),
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "glance", open: True, title: "At a glance" },
	{ depth: 0, destination: "scorecard", open: True, title: "1 Scorecard" },
	{ depth: 0, destination: "trading", open: True, title: "2 Trading performance" },
	{ depth: 1, destination: "segments", open: True, title: "2.1 Segment results" },
	{ depth: 0, destination: "targets", open: True, title: "3 Progress against targets" },
	{ depth: 0, destination: "priorities", open: True, title: "4 Priorities for Q3" },
	{ depth: 0, destination: "position", open: True, title: "5 Financial position" },
]

## ---------------------------------------------------------------------
## A key-figures callout, following `tests/custom_block/Callout.roc`: one
## paragraph per figure, measured by the package at the panel's content
## width, painted over a rounded panel with an accent bar at its start
## edge. `text` colours the callout's ordinary text, for a dark panel.

callout_inset : Layout.Unit
callout_inset = points(12)

## Each line is a label and its value; the callout scopes its `Strong`
## labels to its accent colour.
callout : Pdf.Options, { accent : Color.SourceValue, fill : Color.SourceValue, lines : List((Str, Str)), name : Str, text : Color.SourceValue } -> Try(Document.Block, Pdf.Error)
callout = |options, { accent, fill, lines, name, text }| {
	paragraphs = lines.map(|(label, value)| Pdf.rich_paragraph([Pdf.strong([Pdf.text(label)]), Pdf.text(" ${value}")]))
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-AU", width: points(body_width - 24) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(body_width) }
	block = Pdf.custom_block({
		contents: paragraphs,
		fragmentation: Unsplittable,
		inset: callout_inset,
		name,
		panel: callout_panel(size, fill, accent),
		size,
	})
	Ok(Pdf.scoped(Theme.Scope.empty.with_color(Strong, accent).with_color(Text, text), [block]))
}

callout_panel : Layout.Size, Color.SourceValue, Color.SourceValue -> Scene.Drawing
callout_panel = |size, fill, accent| {
	r = 5000
	k = r * 552 // 1000
	right = size.width.raw()
	top = size.height.raw()
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	outline_path = Scene.path({})
		.move_to(point(r, 0))
		.line_to(point(right - r, 0))
		.cubic_to({ control_1: point(right - r + k, 0), control_2: point(right, r - k), end: point(right, r) })
		.line_to(point(right, top - r))
		.cubic_to({ control_1: point(right, top - r + k), control_2: point(right - r + k, top), end: point(right - r, top) })
		.line_to(point(r, top))
		.cubic_to({ control_1: point(r - k, top), control_2: point(0, top - r + k), end: point(0, top - r) })
		.line_to(point(0, r))
		.cubic_to({ control_1: point(0, r - k), control_2: point(r - k, 0), end: point(r, 0) })
		.close()
		.finish()
	bar = Scene.path({}).rectangle({ origin: point(0, r), size: { height: Layout.Unit.from_raw(top - 2 * r), width: points(4) } }).finish()
	Scene.drawing({})
		.path(outline_path, Scene.solid_fill(fill))
		.path(bar, Scene.solid_fill(accent))
}

## ---------------------------------------------------------------------
## Figure 1: monthly revenue (AUD thousands) for July to December, Q1 in
## slate and Q2 in teal, with gross margin as an amber line on the same
## plot (a margin of m% is drawn at m × 50 on the revenue scale).

monthly : List({ margin : I64, name : Str, revenue : I64 })
monthly = [
	{ name: "Jul", revenue: 2410, margin: 31 },
	{ name: "Aug", revenue: 2530, margin: 32 },
	{ name: "Sep", revenue: 2480, margin: 31 },
	{ name: "Oct", revenue: 2690, margin: 33 },
	{ name: "Nov", revenue: 2870, margin: 34 },
	{ name: "Dec", revenue: 3140, margin: 36 },
]

revenue_height : I64 -> I64
revenue_height = |value| value * 128 // 4000

## A legend key: a small swatch drawing and its name.
key : Scene.Drawing, I64, I64, Scene.Drawing, Str -> Scene.Drawing
key = |drawing, x, y, swatch, name|
	drawing
		.group(Layout.point(x, y), swatch)
		.text({ align: Start, color: ink, origin: Layout.point(x + 14, y + 1), size: points(8), text: name })

revenue_chart : Scene.Drawing
revenue_chart = {
	left = 40
	base = 16
	width = body_width - left
	var $chart = Scene.drawing({})
	for step in [1, 2, 3, 4] {
		$chart = Scene.rectangle($chart, { origin: Layout.point(left, base + revenue_height(step * 1000)), size: { height: Layout.Unit.millipoints(500), width: points(width) } }, grid)
	}
	for step in [0, 1, 2, 3, 4] {
		$chart = $chart.text({ align: End, color: ink, origin: Layout.point(left - 6, base - 3 + revenue_height(step.to_i64_wrap() * 1000)), size: points(8), text: if step == 0 "0" else "${step.to_i64_wrap().to_str()},000" })
	}
	slot = width // 6
	var $index = 0
	var $line = Scene.path({})
	for month in monthly {
		x = left + $index * slot + slot // 2
		color = if $index < 3 slate else teal
		$chart = Scene.rectangle($chart, Layout.rect(x - 22, base, 44, revenue_height(month.revenue)), color)

		## The month under its bar and its revenue above it.
		$chart = $chart.text({ align: Center, color: ink, origin: Layout.point(x, 3), size: points(8), text: month.name })
		my = base + revenue_height(month.margin * 50 + 1000)
		$line = if $index == 0 $line.move_to(Layout.point(x, my)) else $line.line_to(Layout.point(x, my))
		$index = $index + 1
	}
	$chart = $chart
		.path($line.finish(), Scene.solid_stroke(amber, points(2)))
		.path(Scene.path({}).move_to(Layout.point(left, base)).line_to(Layout.point(body_width, base)).finish(), Scene.solid_stroke(ink, points(1)))
	var $i = 0
	for month in monthly {
		x = left + $i * slot + slot // 2
		my = base + revenue_height(month.margin * 50 + 1000)
		$chart = Scene.rectangle(Scene.rectangle($chart, Layout.rect(x - 4, my - 4, 8, 8), amber), Layout.rect(x - 2, my - 2, 4, 4), white)
		$i = $i + 1
	}

	## The legend, above the plot.
	legend_y = base + revenue_height(4000) + 14
	swatch = |color| Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 10, 8), color)
	margin_key = Scene.rectangle(Scene.drawing({}).path(Scene.path({}).move_to(Layout.point(0, 4)).line_to(Layout.point(10, 4)).finish(), Scene.solid_stroke(amber, points(2))), Layout.rect(3, 2, 4, 4), amber)
	$chart = key($chart, left, legend_y, swatch(slate), "Q1 revenue")
	$chart = key($chart, left + 90, legend_y, swatch(teal), "Q2 revenue")
	key($chart, left + 180, legend_y, margin_key, "Gross margin, 31% to 36%")
}

## ---------------------------------------------------------------------
## Figure 2: progress toward the four FY2027 targets as horizontal tracks,
## each named above its track, labelled with its percentage, and marked at
## the halfway point the calendar has reached.

progress : List((Str, U64))
progress = [("Revenue", 62), ("New members", 48), ("Advisory clients", 71), ("Emissions reduction", 39)]

progress_chart : Scene.Drawing
progress_chart = {
	## Names in a 104 pt column, tracks after it, percentages at the end.
	start = 112
	track = body_width - start - 46
	row_height = 23
	var $chart = Scene.drawing({})
	var $row = 0
	for (name, percent) in progress {
		y = 3 * row_height - $row * row_height + 6
		filled = track * percent.to_i64_wrap() // 100
		color = if percent >= 50 teal else amber
		$chart = Scene.rectangle(Scene.rectangle($chart, Layout.rect(start, y, track, 14), grid), Layout.rect(start, y, filled, 14), color)
		$chart = $chart
			.text({ align: End, color: ink, origin: Layout.point(start - 8, y + 3), size: points(9), text: name })
			.text_in(Strong, { align: End, color: ink, origin: Layout.point(body_width - 2, y + 3), size: points(10), text: "${percent.to_str()}%" })
		$row = $row + 1
	}

	## The calendar marker: half of the financial year has elapsed.
	half = start + track // 2
	top = 4 * row_height + 2
	$chart
		.path(Scene.path({}).move_to(Layout.point(half, 1)).line_to(Layout.point(half, top)).finish(), Scene.solid_stroke(navy, points(1)))
		.text_in(Strong, { align: Center, color: navy, origin: Layout.point(half, top + 4), size: points(8), text: "Half year" })
}

## ---------------------------------------------------------------------
## Tables.

## Figure 1's values as a table: one column per month, with the revenue
## in AUD thousands and the gross margin.
monthly_table : Document.Block
monthly_table = {
	var $columns = [{ width: Share(3), align: Start }]
	var $months = [Pdf.header_cell(Column, [Pdf.text("Month")])]
	var $revenue = [Pdf.header_cell(Row, [Pdf.text("Revenue")])]
	var $margin = [Pdf.header_cell(Row, [Pdf.text("Gross margin")])]
	for month in monthly {
		$columns = $columns.append({ width: Share(2), align: End })
		$months = $months.append(Pdf.header_cell(Column, [Pdf.text(month.name)]))

		## Every month's revenue is between 1,100 and 9,999 thousand.
		$revenue = $revenue.append(Pdf.cell([Pdf.text("${(month.revenue // 1000).to_str()},${(month.revenue % 1000).to_str()}")]))
		$margin = $margin.append(Pdf.cell([Pdf.text("${month.margin.to_str()}%")]))
	}
	Pdf.table({
		caption: Pdf.caption("Table 2. Monthly revenue in AUD thousands and gross margin, July to December 2026"),
		columns: $columns,
		header_rows: [Pdf.row($months)],
		body_rows: [Pdf.row($revenue), Pdf.row($margin)],
		footer_rows: [],
		row_split: KeepRows,
	})
}

kpi_row : Str, Str, Str, Str, Pdf.Cell -> Pdf.Row
kpi_row = |metric, q1, q2, target, status| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(metric)]),
	Pdf.cell([Pdf.text(q1)]),
	Pdf.cell([Pdf.text(q2)]),
	Pdf.cell([Pdf.text(target)]),
	status,
])

on_track : Pdf.Cell
on_track = Pdf.shaded(Color.srgb8({ red: 226, green: 243, blue: 234 }), Pdf.cell([Pdf.strong([Pdf.text("On track")])]))

watch : Pdf.Cell
watch = Pdf.shaded(Color.srgb8({ red: 252, green: 238, blue: 214 }), Pdf.cell([Pdf.emphasis([Pdf.text("Watch")])]))

scorecard : Document.Block
scorecard = Pdf.table({
	caption: Pdf.caption("Table 1. Quarterly scorecard"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Share(1), align: End },
		{ width: Share(1), align: End },
		{ width: Share(1), align: End },
		{ width: Fixed(points(72)), align: Start },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Measure")]),
			Pdf.header_cell(Column, [Pdf.text("Q1")]),
			Pdf.header_cell(Column, [Pdf.text("Q2")]),
			Pdf.header_cell(Column, [Pdf.text("Target")]),
			Pdf.header_cell(Column, [Pdf.text("Status")]),
		]),
	],
	body_rows: [
		kpi_row("Revenue (AUD m)", "7.42", "8.70", "8.40", on_track),
		kpi_row("Gross margin", "31.3%", "34.4%", "33.0%", on_track),
		kpi_row("Active members", "18,240", "19,105", "19,500", watch),
		kpi_row("Member retention (12 months)", "91.8%", "93.6%", "93.0%", on_track),
		kpi_row("Orders delivered on time", "95.1%", "96.9%", "96.0%", on_track),
		kpi_row("Net promoter score", "41", "44", "50", watch),
		kpi_row("Lost-time injuries", "2", "0", "0", on_track),
	],
	footer_rows: [],
	row_split: KeepRows,
})

segment_row : Str, Str, Str, Str, Str -> Pdf.Row
segment_row = |segment, revenue, share, growth, margin| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(segment)]),
	Pdf.cell([Pdf.text(revenue)]),
	Pdf.cell([Pdf.text(share)]),
	Pdf.cell([Pdf.text(growth)]),
	Pdf.cell([Pdf.text(margin)]),
])

segments : Document.Block
segments = Pdf.table({
	caption: Pdf.caption("Table 3. Results by segment, Q2 FY2027, revenue in AUD thousands"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Segment")]),
			Pdf.header_cell(Column, [Pdf.text("Revenue")]),
			Pdf.header_cell(Column, [Pdf.text("Share")]),
			Pdf.header_cell(Column, [Pdf.text("Growth")]),
			Pdf.header_cell(Column, [Pdf.text("Margin")]),
		]),
	],
	body_rows: [
		segment_row("Grain and fodder", "3,262", "37.5%", "+14.2%", "29.8%"),
		segment_row("Farm supplies", "2,436", "28.0%", "+9.6%", "36.1%"),
		segment_row("Fuel and lubricants", "1,705", "19.6%", "+4.1%", "22.4%"),
		segment_row("Advisory services", "853", "9.8%", "+31.5%", "58.0%"),
		segment_row("Online store", "444", "5.1%", "+62.0%", "41.7%"),
	],
	footer_rows: [
		Pdf.row([
			Pdf.header_cell(Row, [Pdf.text("Total")]),
			Pdf.cell([Pdf.strong([Pdf.text("8,700")])]),
			Pdf.cell([Pdf.text("100.0%")]),
			Pdf.cell([Pdf.strong([Pdf.text("+17.3%")])]),
			Pdf.cell([Pdf.text("34.4%")]),
		]),
	],
	row_split: KeepRows,
})

position_row : Str, Str, Str -> Pdf.Row
position_row = |item, june, december| Pdf.row([Pdf.header_cell(Row, [Pdf.text(item)]), Pdf.cell([Pdf.text(june)]), Pdf.cell([Pdf.text(december)])])

position_table : Document.Block
position_table = Pdf.table({
	caption: Pdf.caption("Table 4. Summary balance sheet, AUD thousands"),
	columns: [{ width: Share(3), align: Start }, { width: Share(1), align: End }, { width: Share(1), align: End }],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Item")]),
			Pdf.header_cell(Column, [Pdf.text("Jun 2026")]),
			Pdf.header_cell(Column, [Pdf.text("Dec 2026")]),
		]),
	],
	body_rows: [
		position_row("Cash and deposits", "4,180", "5,025"),
		position_row("Trade receivables", "3,960", "4,410"),
		position_row("Inventory", "6,720", "6,105"),
		position_row("Property, plant, and equipment", "12,340", "13,280"),
		position_row("Borrowings", "(3,500)", "(3,100)"),
		position_row("Other liabilities", "(5,870)", "(6,240)"),
	],
	footer_rows: [
		Pdf.row([
			Pdf.header_cell(Row, [Pdf.text("Members' equity")]),
			Pdf.cell([Pdf.text("17,830")]),
			Pdf.cell([Pdf.strong([Pdf.text("19,480")])]),
		]),
	],
	row_split: KeepRows,
})

## ---------------------------------------------------------------------

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| Ok([
	Pdf.title("Quarterly report"),
	Pdf.rich_paragraph([
		Pdf.strong([Pdf.text("Q2 FY2027")]),
		Pdf.text(" · October to December 2026 · Prepared for members by the Board and the Finance team"),
	]),
	Pdf.section([
		Pdf.destination_heading("glance", 1, "At a glance"),
		Pdf.rich_paragraph([
			Pdf.text("Northstar finished the half ahead of plan. Revenue rose "),
			Pdf.strong([Pdf.text("17.3%")]),
			Pdf.text(" on the same quarter last year, gross margin widened by three points, and the new "),
			Pdf.emphasis([Pdf.text("advisory")]),
			Pdf.text(" and "),
			Pdf.emphasis([Pdf.text("online")]),
			Pdf.text(" segments grew fastest. Membership growth and our net promoter score lag their targets; "),
			Pdf.inline_internal_link([Pdf.text("section 4")], "priorities"),
			Pdf.text(" sets out how we will close the gap."),
		]),
		callout(
			options,
			{
				accent: Color.srgb8({ red: 120, green: 210, blue: 214 }),
				fill: navy,
				lines: [
					("Revenue", "AUD 8.70 m, up 17.3% year on year"),
					("Gross margin", "34.4%, up 3.1 points on Q1"),
					("Member retention", "93.6%, the highest since 2019"),
					("Member rebate declared", "AUD 1.12 m, payable 28 February 2027"),
				],
				name: "Key figures",
				text: white,
			},
		)?,
	]),
	Pdf.section([
		Pdf.keep_with_next(Required, Pdf.destination_heading("scorecard", 1, "1 Scorecard")),
		Pdf.paragraph("Five of the seven board measures are on track. Status reads On track when the quarter met or beat its target, and Watch when it fell short."),
		scorecard,
		Pdf.rich_paragraph([
			Pdf.text("Both measures on Watch trail by small margins: active members are 395 short of the 19,500 target, and the net promoter score six points short of 50. "),
			Pdf.inline_internal_link([Pdf.text("Section 4")], "priorities"),
			Pdf.text(" sets out how the Board will close each gap before the next report."),
		]),
		callout(
			options,
			{
				accent: amber,
				fill: Color.srgb8({ red: 252, green: 244, blue: 230 }),
				lines: [
					("Members' meeting", "12 March 2027, 10 am, Dubbo Showground pavilion"),
					("Next report", "Q3 FY2027, published April 2027"),
				],
				name: "Diary dates",
				text: ink,
			},
		)?,
	]),
	Pdf.page_break,
	Pdf.section([
		Pdf.destination_heading("trading", 1, "2 Trading performance"),
		Pdf.rich_paragraph([
			Pdf.text("Revenue climbed in every month of the quarter, lifted by an early harvest and strong fodder demand after a dry spring. December was the strongest month on record at "),
			Pdf.strong([Pdf.text("AUD 3.14 m")]),
			Pdf.text(". Margin improved as we moved more volume through direct contracts and less through spot purchasing."),
		]),
		Pdf.figure_fit(
			Pdf.figure(
				revenue_chart,
				"Column chart of monthly revenue from July to December 2026, rising from AUD 2.41 million in July to AUD 3.14 million in December, with the second-quarter months highlighted. An overlaid line shows gross margin rising from 31% to 36%. Values are listed in Table 2.",
				Pdf.caption("Figure 1. Monthly revenue in AUD thousands, July to December 2026, with gross margin"),
			),
			ScaleToFit({ minimum_percent: 70 }),
		),
		monthly_table,
		Pdf.section([
			Pdf.destination_heading("segments", 2, "2.1 Segment results"),
			Pdf.paragraph("Grain and fodder remains our largest segment. Advisory services and the online store are still small, but together they contributed a fifth of the quarter's growth at well above the average margin."),
			segments,
		]),
	]),
	Pdf.section([
		Pdf.keep_together([
			Pdf.destination_heading("targets", 1, "3 Progress against targets"),
			Pdf.paragraph("Half of the financial year has elapsed, marked by the navy line. Teal tracks are at or ahead of that pace; amber tracks are behind it."),
			Pdf.figure(
				progress_chart,
				"Four progress bars against FY2027 targets: revenue 62%, new members 48%, advisory clients 71%, and emissions reduction 39%. A marker at 50% shows the elapsed half year.",
				Pdf.caption("Figure 2. Progress toward FY2027 targets"),
			),

			## The targets' notes stay with the figure they explain.
			Pdf.bullet_list([
				Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Revenue")]), Pdf.text(" is 62% of the annual target, twelve points ahead of pace.")])]),
				Pdf.list_item([Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("New members")]), Pdf.text(" are at 48%; winter field days usually add 300 more.")])]),
				Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Advisory clients")]), Pdf.text(" reached 71% after the agronomy team doubled.")])]),
				Pdf.list_item([Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("Emissions reduction")]), Pdf.text(" is at 39%; the solar array at the Dubbo depot is due in March.")])]),
			]),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("priorities", 1, "4 Priorities for Q3"),
		Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				Pdf.list_item([
					Pdf.paragraph("Lift membership through the autumn recruitment drive:"),
					Pdf.bullet_list([
						Pdf.list_item([Pdf.paragraph("waive the joining fee for growers under 35;")]),
						Pdf.list_item([Pdf.paragraph("run field days in Parkes, Forbes, and Cowra.")]),
					]),
				]),
				Pdf.list_item([Pdf.paragraph("Raise the net promoter score by resolving delivery queries within one business day.")]),
				Pdf.list_item([Pdf.paragraph("Commission the Dubbo solar array and report its first month of generation.")]),
			],
		),
		Pdf.rich_paragraph([
			Pdf.text("Members can read the full financial statements and the rebate schedule at "),
			Pdf.inline_link([Pdf.text("northstar.example/members/reports")], "https://northstar.example/members/reports"),
			Pdf.text(". Questions for the Board may be sent to the company secretary before the members' meeting on "),
			Pdf.strong([Pdf.text("12 March 2027")]),
			Pdf.text("."),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("position", 1, "5 Financial position"),
		Pdf.rich_paragraph([
			Pdf.text("The balance sheet strengthened over the half. Operating cash flow funded the Dubbo solar array without new borrowing, and the Board has reaffirmed the "),
			Pdf.strong([Pdf.text("AUD 1.12 m")]),
			Pdf.text(" member rebate. Figures are unaudited and reported excluding "),
			Pdf.expansion("GST", "Goods and Services Tax"),
			Pdf.text("."),
		]),
		position_table,
	]),
])
