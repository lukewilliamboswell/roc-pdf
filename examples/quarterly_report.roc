app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## A members' quarterly report for a regional cooperative: a navy cover
## band in the first-page header, a tinted "at a glance" callout authored
## through the custom-block seam, a KPI scorecard and a segment table with
## a totals footer, two vector charts drawn from `Scene` groups (monthly
## revenue with a margin line, and progress against annual targets), and
## running headers with `Page N of M` on every later page.
main! = |_args| {
	document = Pdf.document({ contents, language: "en-AU", title: "Northstar Cooperative quarterly report, Q2 FY2027" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2027-01-18T00:00:00Z")
		.with_modified("2027-01-18T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "quarterly-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote quarterly-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
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
		.with_strong_color(teal)
		.with_emphasis_color(Color.srgb8({ red: 160, green: 94, blue: 0 }))
		.with_table_header_color(teal)
		.with_table_rule(Rule({ color: teal, width: points(1) }))
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(5))
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
	## Faint diagonal hatching across the band's start, for texture.
	var $x = 4
	while $x < 220 {
		$band = $band.path(Scene.path({}).move_to(Layout.point($x, 8)).line_to(Layout.point($x + 28, 54)).finish(), Scene.solid_stroke(Color.srgb8({ red: 34, green: 62, blue: 98 }), points(2)))
		$x = $x + 14
	}
	## Furniture drawings hold no groups, so the mark is placed directly.
	m = body_width - 76
	bar = |x, height| Scene.path({}).move_to(Layout.point(m + x, 17)).line_to(Layout.point(m + x + 8, 17)).line_to(Layout.point(m + x + 8, 17 + height)).line_to(Layout.point(m + x, 17 + height)).close().finish()
	$band
		.path(bar(0, 12), Scene.solid_fill(slate))
		.path(bar(12, 20), Scene.solid_fill(teal))
		.path(bar(24, 28), Scene.solid_fill(white))
		.path(Scene.path({}).move_to(Layout.point(m + 44, 37)).line_to(Layout.point(m + 50, 45)).line_to(Layout.point(m + 56, 37)).line_to(Layout.point(m + 50, 29)).close().finish(), Scene.solid_fill(amber))
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
		header: Pdf.region({
			height: points(22),
			start: [Pdf.furniture_text([Pdf.text("Northstar Cooperative · Q2 FY2027")]), Pdf.furniture_image(hairline)],
			center: [],
			end: [],
		}),
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
## single-line paragraph per figure, measured from the theme's public body
## leading and paragraph spacing, painted over a tinted rounded panel with
## an accent bar at its start edge.

callout_inset : Layout.Unit
callout_inset = points(12)

callout : { accent : Color.SourceValue, fill : Color.SourceValue, lines : List(Str), name : Str } -> Document.Block
callout = |{ accent, fill, lines, name }| {
	leading = Theme.body_style(theme).leading.raw()
	spacing = Theme.paragraph_spacing(theme).raw()
	count = lines.len().to_i64_wrap()
	size = { height: Layout.Unit.from_raw(callout_inset.raw() * 2 + leading * count + spacing * (count - 1)), width: points(body_width) }
	Pdf.custom_block({
		contents: lines.map(|line| Pdf.paragraph(line)),
		fragmentation: Unsplittable,
		inset: callout_inset,
		name,
		panel: callout_panel(size, fill, accent),
		size,
	})
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
## Chart lettering: seven-segment digits drawn as rectangles, 5 × 9 pt.

digit : U64 -> Scene.Drawing
digit = |value| {
	a = (0, 8, 5, 1)
	b = (4, 4, 1, 5)
	c = (4, 0, 1, 5)
	d = (0, 0, 5, 1)
	e = (0, 0, 1, 5)
	f = (0, 4, 1, 5)
	g = (0, 4, 5, 1)
	segments = if value == 0 {
		[a, b, c, d, e, f]
	} else if value == 1 {
		[b, c]
	} else if value == 2 {
		[a, b, g, e, d]
	} else if value == 3 {
		[a, b, g, c, d]
	} else if value == 4 {
		[f, g, b, c]
	} else if value == 5 {
		[a, f, g, c, d]
	} else if value == 6 {
		[a, f, g, e, c, d]
	} else if value == 7 {
		[a, b, c]
	} else if value == 8 {
		[a, b, c, d, e, f, g]
	} else {
		[a, b, c, d, f, g]
	}
	var $drawing = Scene.drawing({})
	for (x, y, w, h) in segments {
		$drawing = Scene.rectangle($drawing, Layout.rect(x, y, w, h), ink)
	}
	$drawing
}

## The decimal digits of `value`, most significant first.
digits_of : U64 -> List(U64)
digits_of = |value| {
	var $power = 1
	while $power * 10 <= value {
		$power = $power * 10
	}
	var $digits = List.with_capacity(6)
	while $power > 0 {
		$digits = $digits.append((value // $power) % 10)
		$power = $power // 10
	}
	$digits
}

## Draws `value` with its last digit ending at `x` and its baseline at `y`.
number_end : Scene.Drawing, U64, I64, I64 -> Scene.Drawing
number_end = |drawing, value, x, y| {
	digits = digits_of(value)
	var $drawing = drawing
	var $at = x - 7 * digits.len().to_i64_wrap() + 2
	for d in digits {
		$drawing = $drawing.group(Layout.point($at, y), digit(d))
		$at = $at + 7
	}
	$drawing
}

## ---------------------------------------------------------------------
## Figure 1: monthly revenue (AUD thousands) for July to December, Q1 in
## slate and Q2 in teal, with gross margin as an amber line on the same
## plot (a margin of m% is drawn at m × 50 on the revenue scale).

monthly : List({ margin : I64, revenue : I64 })
monthly = [
	{ revenue: 2410, margin: 31 },
	{ revenue: 2530, margin: 32 },
	{ revenue: 2480, margin: 31 },
	{ revenue: 2690, margin: 33 },
	{ revenue: 2870, margin: 34 },
	{ revenue: 3140, margin: 36 },
]

revenue_height : I64 -> I64
revenue_height = |value| value * 170 // 4000

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
		$chart = number_end($chart, step * 1000, left - 6, base - 4 + revenue_height(step.to_i64_wrap() * 1000))
	}
	slot = width // 6
	var $index = 0
	var $line = Scene.path({})
	for month in monthly {
		x = left + $index * slot + slot // 2
		color = if $index < 3 slate else teal
		$chart = Scene.rectangle($chart, Layout.rect(x - 22, base, 44, revenue_height(month.revenue)), color)
		## The month number (7 to 12) under its bar.
		$chart = number_end($chart, ($index + 7).to_u64_wrap(), x + 5, 2)
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
	$chart
}

## ---------------------------------------------------------------------
## Figure 2: progress toward the four FY2027 targets as horizontal tracks,
## each labelled with its percentage and marked at the halfway point the
## calendar has reached.

progress : List(U64)
progress = [62, 48, 71, 39]

progress_chart : Scene.Drawing
progress_chart = {
	track = body_width - 60
	var $chart = Scene.drawing({})
	var $row = 0
	for percent in progress {
		y = 3 * 30 - $row * 30 + 6
		filled = track * percent.to_i64_wrap() // 100
		color = if percent >= 50 teal else amber
		$chart = Scene.rectangle(Scene.rectangle($chart, Layout.rect(0, y, track, 14), grid), Layout.rect(0, y, filled, 14), color)
		$chart = number_end($chart, percent, track + 26, y + 3)
		## A percent sign: two dots and a slash.
		$chart = Scene.rectangle(Scene.rectangle($chart, Layout.rect(track + 30, y + 9, 2, 2), ink), Layout.rect(track + 36, y + 3, 2, 2), ink)
			.path(Scene.path({}).move_to(Layout.point(track + 30, y + 3)).line_to(Layout.point(track + 38, y + 11)).finish(), Scene.solid_stroke(ink, Layout.Unit.millipoints(900)))
		$row = $row + 1
	}
	## The calendar marker: half of the financial year has elapsed.
	half = track // 2
	$chart.path(Scene.path({}).move_to(Layout.point(half, 1)).line_to(Layout.point(half, 124)).finish(), Scene.solid_stroke(navy, points(1)))
}

## ---------------------------------------------------------------------
## Tables.

kpi_row : Str, Str, Str, Str, Pdf.Inline -> Pdf.Row
kpi_row = |metric, q1, q2, target, status| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(metric)]),
	Pdf.cell([Pdf.text(q1)]),
	Pdf.cell([Pdf.text(q2)]),
	Pdf.cell([Pdf.text(target)]),
	Pdf.cell([status]),
])

on_track : Pdf.Inline
on_track = Pdf.strong([Pdf.text("On track")])

watch : Pdf.Inline
watch = Pdf.emphasis([Pdf.text("Watch")])

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
	header_rows: [Pdf.row([
		Pdf.header_cell(Column, [Pdf.text("Measure")]),
		Pdf.header_cell(Column, [Pdf.text("Q1")]),
		Pdf.header_cell(Column, [Pdf.text("Q2")]),
		Pdf.header_cell(Column, [Pdf.text("Target")]),
		Pdf.header_cell(Column, [Pdf.text("Status")]),
	])],
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
	caption: Pdf.caption("Table 2. Results by segment, Q2 FY2027, revenue in AUD thousands"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
		{ width: Share(2), align: End },
	],
	header_rows: [Pdf.row([
		Pdf.header_cell(Column, [Pdf.text("Segment")]),
		Pdf.header_cell(Column, [Pdf.text("Revenue")]),
		Pdf.header_cell(Column, [Pdf.text("Share")]),
		Pdf.header_cell(Column, [Pdf.text("Growth")]),
		Pdf.header_cell(Column, [Pdf.text("Margin")]),
	])],
	body_rows: [
		segment_row("Grain and fodder", "3,262", "37.5%", "+14.2%", "29.8%"),
		segment_row("Farm supplies", "2,436", "28.0%", "+9.6%", "36.1%"),
		segment_row("Fuel and lubricants", "1,705", "19.6%", "+4.1%", "22.4%"),
		segment_row("Advisory services", "853", "9.8%", "+31.5%", "58.0%"),
		segment_row("Online store", "444", "5.1%", "+62.0%", "41.7%"),
	],
	footer_rows: [Pdf.row([
		Pdf.header_cell(Row, [Pdf.text("Total")]),
		Pdf.cell([Pdf.strong([Pdf.text("8,700")])]),
		Pdf.cell([Pdf.text("100.0%")]),
		Pdf.cell([Pdf.strong([Pdf.text("+17.3%")])]),
		Pdf.cell([Pdf.text("34.4%")]),
	])],
	row_split: KeepRows,
})

position_row : Str, Str, Str -> Pdf.Row
position_row = |item, june, december| Pdf.row([Pdf.header_cell(Row, [Pdf.text(item)]), Pdf.cell([Pdf.text(june)]), Pdf.cell([Pdf.text(december)])])

position_table : Document.Block
position_table = Pdf.table({
	caption: Pdf.caption("Table 3. Summary balance sheet, AUD thousands"),
	columns: [{ width: Share(3), align: Start }, { width: Share(1), align: End }, { width: Share(1), align: End }],
	header_rows: [Pdf.row([
		Pdf.header_cell(Column, [Pdf.text("Item")]),
		Pdf.header_cell(Column, [Pdf.text("Jun 2026")]),
		Pdf.header_cell(Column, [Pdf.text("Dec 2026")]),
	])],
	body_rows: [
		position_row("Cash and deposits", "4,180", "5,025"),
		position_row("Trade receivables", "3,960", "4,410"),
		position_row("Inventory", "6,720", "6,105"),
		position_row("Property, plant, and equipment", "12,340", "13,280"),
		position_row("Borrowings", "(3,500)", "(3,100)"),
		position_row("Other liabilities", "(5,870)", "(6,240)"),
	],
	footer_rows: [Pdf.row([
		Pdf.header_cell(Row, [Pdf.text("Members' equity")]),
		Pdf.cell([Pdf.text("17,830")]),
		Pdf.cell([Pdf.strong([Pdf.text("19,480")])]),
	])],
	row_split: KeepRows,
})

## ---------------------------------------------------------------------

contents : List(Document.Block)
contents = [
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
		callout({
			accent: teal,
			fill: Color.srgb8({ red: 232, green: 244, blue: 244 }),
			lines: [
				"Revenue: AUD 8.70 m, up 17.3% year on year",
				"Gross margin: 34.4%, up 3.1 points on Q1",
				"Member retention: 93.6%, the highest since 2019",
				"Member rebate declared: AUD 1.12 m, payable 28 February 2027",
			],
			name: "Key figures",
		}),
	]),
	Pdf.section([
		Pdf.keep_with_next(Required, Pdf.destination_heading("scorecard", 1, "1 Scorecard")),
		Pdf.paragraph("Five of the seven board measures are on track. Status reads On track when the quarter met or beat its target, and Watch when it fell short."),
		scorecard,
		callout({
			accent: amber,
			fill: Color.srgb8({ red: 252, green: 244, blue: 230 }),
			lines: [
				"Members' meeting: 12 March 2027, 10 am, Dubbo Showground pavilion",
				"Next report: Q3 FY2027, published April 2027",
			],
			name: "Diary dates",
		}),
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
				"Column chart of monthly revenue from July to December 2026, rising from AUD 2.41 million in July to AUD 3.14 million in December, with the second-quarter months highlighted. An overlaid line shows gross margin rising from 31% to 36%.",
				Pdf.caption("Figure 1. Monthly revenue in AUD thousands for months 7 to 12 (Q1 slate, Q2 teal), with gross margin as the amber line"),
			),
			ScaleToFit({ minimum_percent: 70 }),
		),
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
			Pdf.caption("Figure 2. Progress toward FY2027 targets, from top: revenue, new members, advisory clients, emissions reduction"),
		),
		]),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Revenue")]), Pdf.text(" is 62% of the annual target, twelve points ahead of pace.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("New members")]), Pdf.text(" are at 48%; winter field days usually add 300 more.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Advisory clients")]), Pdf.text(" reached 71% after the agronomy team doubled.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.emphasis([Pdf.text("Emissions reduction")]), Pdf.text(" is at 39%; the solar array at the Dubbo depot is due in March.")])]),
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
]
