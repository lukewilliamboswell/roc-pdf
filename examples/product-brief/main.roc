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
import "fonts/Inter-Regular.ttf" as regular_bytes : List(U8)
import "fonts/Inter-Bold.ttf" as bold_bytes : List(U8)
import "fonts/Inter-Italic.ttf" as italic_bytes : List(U8)
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## Sprout 2.4 product brief: a US Letter launch brief with a vector hero
## illustration of the planning board, a "Pilot results" key-figures
## callout and a customer quote on a forest panel, both measured by the
## package, a line chart of decision time with its data table, a plan
## comparison table kept whole on one page with shaded group rows, empty
## cells where a plan lacks a capability, and a price footer, a support
## table, rich inline content with monospace code, lists, links, running
## furniture with its header text inset above ruled backdrops and
## `Page N of M`, and an outline.
main! = |_args| {
	fonts = register_fonts({})?
	theme = with_faces(base_theme, fonts)
	options = Pdf.Options.default.with_theme(theme).with_page_size(Letter).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-US", title: "Sprout 2.4 product brief" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "product-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote product-brief.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, italic : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }

## Inter Regular, Bold, and Italic, and Source Code Pro Regular, each retained
## byte-for-byte from its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin : List(Font.Script)
	latin = ["Latn"]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	italic = add(bold.registry, italic_bytes)?
	mono = add(italic.registry, mono_bytes)?
	Ok({ regular: regular.face, bold: bold.face, italic: italic.face, mono: mono.face, registry: mono.registry })
}

## Regular for body text; Bold for the title, headings, and `Pdf.strong`;
## Italic for `Pdf.emphasis`; the monospace face for `Pdf.code`, at 90%
## of the text around it.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	title = Theme.title_style(base)
	heading = Theme.heading_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_style({ ..heading, font: faces.bold })
		.with_inline_font(Strong, faces.bold)
		.with_inline_font(Emphasis, faces.italic)
		.with_inline_font(Code, faces.mono)
		.with_inline_scale(Code, 90)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

forest : Color.SourceValue
forest = Color.srgb8({ red: 14, green: 92, blue: 60 })

leaf : Color.SourceValue
leaf = Color.srgb8({ red: 46, green: 158, blue: 98 })

sage : Color.SourceValue
sage = Color.srgb8({ red: 214, green: 236, blue: 222 })

meadow : Color.SourceValue
meadow = Color.srgb8({ red: 240, green: 247, blue: 242 })

sun : Color.SourceValue
sun = Color.srgb8({ red: 247, green: 190, blue: 72 })

clay : Color.SourceValue
clay = Color.srgb8({ red: 226, green: 120, blue: 84 })

stone : Color.SourceValue
stone = Color.srgb8({ red: 196, green: 204, blue: 200 })

charcoal : Color.SourceValue
charcoal = Color.srgb8({ red: 33, green: 41, blue: 37 })

white : Color.SourceValue
white = Color.srgb8({ red: 255, green: 255, blue: 255 })

## US Letter with 54 pt margins: a 504 pt measure.
base_theme : Theme
base_theme = {
	body = Theme.body_style(Theme.default)
	heading = Theme.heading_style(Theme.default)
	title = Theme.title_style(Theme.default)
	Theme.default
		.with_body_style({ ..body, color: charcoal, size: points(11), leading: points(16) })
		.with_heading_style({ ..heading, color: forest, size: points(17), leading: points(22) })
		.with_title_style({ ..title, color: forest, size: points(40), leading: points(46) })
		.with_page_margin({ top: points(40), right: points(54), bottom: points(40), left: points(54) })
		.with_paragraph_spacing(points(9))
		.with_code_color(Color.srgb8({ red: 120, green: 64, blue: 18 }))
		.with_table_header_color(forest)
		.with_table_header_fill(meadow)
		.with_table_footer_fill(meadow)
		.with_table_body_rule(Rule({ color: Color.srgb8({ red: 214, green: 230, blue: 214 }), width: Layout.Unit.millipoints(500) }))
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(4))
		.with_table_rule(Rule({ color: leaf, width: points(1) }))
		.with_link_color(forest)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1600), thickness: Layout.Unit.millipoints(700) }))
}

## ---------------------------------------------------------------------
## Drawings.

## A closed circle of radius `r` centred at (`cx`, `cy`).
circle : I64, I64, I64 -> Scene.AuthorPath
circle = |cx, cy, r| {
	k = r * 552 // 1000
	Scene.path({})
		.move_to(Layout.point(cx + r, cy))
		.cubic_to({ control_1: Layout.point(cx + r, cy + k), control_2: Layout.point(cx + k, cy + r), end: Layout.point(cx, cy + r) })
		.cubic_to({ control_1: Layout.point(cx - k, cy + r), control_2: Layout.point(cx - r, cy + k), end: Layout.point(cx - r, cy) })
		.cubic_to({ control_1: Layout.point(cx - r, cy - k), control_2: Layout.point(cx - k, cy - r), end: Layout.point(cx, cy - r) })
		.cubic_to({ control_1: Layout.point(cx + k, cy - r), control_2: Layout.point(cx + r, cy - k), end: Layout.point(cx + r, cy) })
		.close()
		.finish()
}

## The Sprout mark in a 32 pt square: a stem and two leaves.
sprout_mark : Scene.Drawing
sprout_mark = {
	left_leaf = Scene.path({})
		.move_to(Layout.point(16, 14))
		.cubic_to({ control_1: Layout.point(10, 26), control_2: Layout.point(2, 26), end: Layout.point(1, 22) })
		.cubic_to({ control_1: Layout.point(2, 14), control_2: Layout.point(10, 12), end: Layout.point(16, 14) })
		.close()
		.finish()
	right_leaf = Scene.path({})
		.move_to(Layout.point(16, 18))
		.cubic_to({ control_1: Layout.point(20, 30), control_2: Layout.point(28, 32), end: Layout.point(31, 30) })
		.cubic_to({ control_1: Layout.point(30, 22), control_2: Layout.point(24, 16), end: Layout.point(16, 18) })
		.close()
		.finish()
	Scene.rectangle(Scene.drawing({}), Layout.rect(15, 0, 2, 20), forest)
		.path(left_leaf, Scene.solid_fill(leaf))
		.path(right_leaf, Scene.solid_fill(forest))
}

## A board card: a white card with a coloured edge, two grey text lines,
## and an owner dot.
card : Color.SourceValue, I64 -> Scene.Drawing
card = |edge, length| {
	base = Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 136, 38), white), Layout.rect(0, 0, 4, 38), edge)
	lines = Scene.rectangle(Scene.rectangle(base, Layout.rect(12, 24, length, 5), stone), Layout.rect(12, 14, length * 6 // 10, 5), stone)
	lines.path(circle(124, 12, 5), Scene.solid_fill(edge))
}

## The hero: the Sprout board with Proposed, Deciding, and Decided columns
## and the decision log's progress bar, 504 × 190 pt.
hero : Scene.Drawing
hero = {
	column = |name, cards| {
		var $drawing = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 152, 150), sage)
		var $y = 90
		for (edge, length) in cards {
			$drawing = $drawing.group(Layout.point(8, $y), card(edge, length))
			$y = $y - 44
		}
		$drawing.text({ align: Start, color: forest, origin: Layout.point(10, 136), size: points(10), text: name })
	}
	frame = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 504, 190), meadow)
	progress = Scene.rectangle(Scene.rectangle(frame, Layout.rect(16, 14, 380, 8), white), Layout.rect(16, 14, 266, 8), leaf)
	progress
		.text_in(Strong, { align: End, color: forest, origin: Layout.point(488, 13), size: points(8), text: "Decision log 70%" })
		.group(Layout.point(16, 32), column("Proposed", [(clay, 96), (sun, 80), (clay, 104)]))
		.group(Layout.point(176, 32), column("Deciding", [(sun, 88), (sun, 110)]))
		.group(Layout.point(336, 32), column("Decided", [(leaf, 100), (leaf, 76), (leaf, 92)]))
}

## Median days from proposal to decision over the eight pilot weeks, in
## tenths of a day.
cycle_time : List(I64)
cycle_time = [95, 88, 79, 64, 56, 51, 47, 44]

## A line chart, 504 × 126 pt: gridlines every two days from 0 to 10, a
## shaded area under the median, and a marker per week.
line_chart : Scene.Drawing
line_chart = {
	left = 30
	base = 16
	step = 62
	y_of = |tenths| base + tenths * 11 // 10
	var $chart = Scene.drawing({})
	for day in [0, 2, 4, 6, 8, 10] {
		color = if day == 0 charcoal else stone
		$chart = Scene.rectangle($chart, { origin: Layout.point(left, y_of(day * 10)), size: { height: Layout.Unit.millipoints(if day == 0 1000 else 500), width: points(474) } }, color)
		$chart = $chart.text({ align: End, color: charcoal, origin: Layout.point(left - 6, y_of(day * 10) - 3), size: points(8), text: if day == 10 "10 d" else day.to_str() })
	}
	var $area = Scene.path({}).move_to(Layout.point(left + 12, base))
	var $line = Scene.path({})
	var $x = left + 12
	var $first = True
	week_one : U64
	week_one = 1
	var $week = week_one
	for tenths in cycle_time {
		$area = $area.line_to(Layout.point($x, y_of(tenths)))
		$line = if $first $line.move_to(Layout.point($x, y_of(tenths))) else $line.line_to(Layout.point($x, y_of(tenths)))
		$chart = $chart.text({ align: Center, color: charcoal, origin: Layout.point($x, 4), size: points(8), text: "Week ${$week.to_str()}" })
		$first = False
		$x = $x + step
		$week = $week + 1
	}
	$area = $area.line_to(Layout.point($x - step, base)).close()
	$chart = $chart
		.path($area.finish(), Scene.solid_fill(sage))
		.path($line.finish(), Scene.solid_stroke(forest, points(2)))
	var $marker_x = left + 12
	for tenths in cycle_time {
		$chart = $chart.path(circle($marker_x, y_of(tenths), 4), { fill: AuthorSolidFill(white), stroke: AuthorSolidStroke({ color: forest, width: Layout.Unit.millipoints(1500) }) })
		$marker_x = $marker_x + step
	}

	# The target of five days, as a dashed clay rule with its label.
	var $dash = left
	while $dash < left + 474 {
		$chart = Scene.rectangle($chart, Layout.rect($dash, y_of(50), 8, 1), clay)
		$dash = $dash + 14
	}
	$chart.text({ align: End, color: clay, origin: Layout.point(left + 474, y_of(50) + 4), size: points(8), text: "Target: 5 days" })
}

## ---------------------------------------------------------------------
## The "Pilot results" callout: a separately authored custom block (the
## pattern of tests/custom_block/Callout.roc). Rich paragraphs that may
## wrap, measured by the package at the panel's content width, on a
## rounded meadow panel edged in leaf green, or on a forest panel with
## white text.

callout_inset : Layout.Unit
callout_inset = points(14)

Panel : [Meadow, Forest]

key_figures : Pdf.Options, Panel, Str, List(List(Pdf.Inline)) -> Try(Document.Block, Pdf.Error)
key_figures = |options, ground, name, lines| {
	accent = match ground {
		Meadow => Theme.Scope.empty.with_color(Strong, forest).with_color(Quote, forest)
		Forest => Theme.Scope.empty.with_color(Text, Color.srgb8({ red: 255, green: 255, blue: 255 })).with_color(Strong, meadow).with_color(Quote, meadow)
	}
	paragraphs = lines.map(|line| Pdf.rich_paragraph(line))
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-US", width: points(504 - 28) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(504) }
	block = Pdf.custom_block({
		contents: paragraphs,
		fragmentation: Unsplittable,
		inset: callout_inset,
		name,
		panel: rounded_panel(ground, size),
		size,
	})
	Ok(Pdf.scoped(accent, [block]))
}

rounded_panel : Panel, Layout.Size -> Scene.Drawing
rounded_panel = |ground, size| {
	half = 750
	r = 8000
	k = r * 552 // 1000
	left = half
	bottom = half
	right = size.width.raw() - half
	top = size.height.raw() - half
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	outline_path = Scene.path({})
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
	fill = match ground {
		Meadow => meadow
		Forest => forest
	}
	Scene.drawing({}).path(outline_path, { fill: AuthorSolidFill(fill), stroke: AuthorSolidStroke({ color: leaf, width: Layout.Unit.millipoints(1500) }) })
}

## ---------------------------------------------------------------------
## Furniture and navigation.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

## A leaf-green hairline across the measure, under each header.
green_rule : Scene.Drawing
green_rule = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(1000), width: points(504) } }, leaf)

footer : Pdf.Region
footer = Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("sprout.example · Launch brief, not for resale")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(40),
					start: [Pdf.furniture_image(Scene.drawing({}).group(Layout.point(0, 5), sprout_mark))],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("Product brief · October 2026")])],
				}),
				green_rule,
			),
			points(3),
		),
		lead: Pdf.no_lead,
		footer,
		gap: points(16),
	}),
	continuation: Pdf.page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(21),
					start: [Pdf.furniture_text([Pdf.text("Sprout 2.4 · Product brief")])],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("October 2026")])],
				}),
				green_rule,
			),
			points(3),
		),
		footer,
		gap: points(16),
	}),
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "problem", open: True, title: "The problem" },
	{ depth: 0, destination: "new", open: True, title: "What is new in 2.4" },
	{ depth: 0, destination: "pilot", open: True, title: "Pilot results" },
	{ depth: 0, destination: "plans", open: True, title: "Plans and pricing" },
	{ depth: 0, destination: "next", open: True, title: "What comes next" },
	{ depth: 0, destination: "rollout", open: True, title: "Rollout and support" },
]

## ---------------------------------------------------------------------
## Tables.

cycle_table : Document.Block
cycle_table = {
	var $columns = [{ width: Share(3), align: Start }]
	var $weeks = [Pdf.header_cell(Column, [Pdf.text("Pilot week")])]
	var $days = [Pdf.header_cell(Row, [Pdf.text("Median days")])]
	for (label, tenths) in ["1", "2", "3", "4", "5", "6", "7", "8"].map2(cycle_time, |label, tenths| (label, tenths)) {
		$columns = $columns.append({ width: Share(1), align: End })
		$weeks = $weeks.append(Pdf.header_cell(Column, [Pdf.text(label)]))
		$days = $days.append(Pdf.cell([Pdf.text("${(tenths // 10).to_str()}.${(tenths % 10).to_str()}")]))
	}
	Pdf.table({
		caption: Pdf.caption("Table 1. Median days from proposal to decision, by pilot week"),
		columns: $columns,
		header_rows: [Pdf.row($weeks)],
		body_rows: [Pdf.row($days)],
		footer_rows: [],
		row_split: KeepRows,
	})
}

group_row : Str -> Pdf.Row
group_row = |label| Pdf.row([Pdf.shaded(Color.srgb8({ red: 240, green: 247, blue: 240 }), Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.strong([Pdf.text(label)])])))])

## A plan that does not include a capability leaves its cell empty.
plan_row : Str, Str, Str, Str -> Pdf.Row
plan_row = |feature, starter, team, business| Pdf.row([Pdf.header_cell(Row, [Pdf.text(feature)]), plan_cell(starter), plan_cell(team), plan_cell(business)])

plan_cell : Str -> Pdf.Cell
plan_cell = |value| if value.is_empty() Pdf.cell([]) else Pdf.cell([Pdf.text(value)])

## The comparison is kept whole on one page.
plans_table : Document.Block
plans_table = Pdf.keep_together([plans])

plans : Document.Block
plans = Pdf.table({
	caption: Pdf.caption("Table 2. Plans compared"),
	columns: [{ width: Share(5), align: Start }, { width: Share(2), align: Center }, { width: Share(2), align: Center }, { width: Share(2), align: Center }],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Capability")]),
			Pdf.header_cell(Column, [Pdf.text("Starter")]),
			Pdf.header_cell(Column, [Pdf.text("Team")]),
			Pdf.header_cell(Column, [Pdf.text("Business")]),
		]),
	],
	body_rows: [
		group_row("Planning"),
		plan_row("Boards and decision log", "Yes", "Yes", "Yes"),
		plan_row("Typed owners and due dates", "Yes", "Yes", "Yes"),
		plan_row("Dependency map", "", "Yes", "Yes"),
		group_row("Sharing and export"),
		plan_row("Archival PDF export", "Yes", "Yes", "Yes"),
		plan_row("Guest reviewers", "2", "10", "Unlimited"),
		plan_row("Single sign-on and audit log", "", "", "Yes"),
	],
	footer_rows: [
		Pdf.row([
			Pdf.aligned(End, Pdf.header_cell(Row, [Pdf.text("USD per editor, monthly")])),
			Pdf.cell([Pdf.strong([Pdf.text("Free")])]),
			Pdf.cell([Pdf.strong([Pdf.text("$12")])]),
			Pdf.cell([Pdf.strong([Pdf.text("$24")])]),
		]),
	],
	row_split: KeepRows,
})

support_table : Document.Block
support_table = Pdf.table({
	caption: Pdf.caption("Table 4. Support by plan"),
	columns: [{ width: Fixed(points(92)), align: Start }, { width: Share(3), align: Start }, { width: Share(2), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Plan")]), Pdf.header_cell(Column, [Pdf.text("Channels")]), Pdf.header_cell(Column, [Pdf.text("First response")])])],
	body_rows: [
		("Starter", "Help centre and community forum", "Best effort"),
		("Team", "Email and in-app chat, weekdays", "One business day"),
		("Business", "Email, chat, and phone, with a named success manager", "Four business hours"),
	].map(|(plan, channels, response)| Pdf.row([Pdf.header_cell(Row, [Pdf.text(plan)]), Pdf.cell([Pdf.text(channels)]), Pdf.cell([Pdf.text(response)])])),
	footer_rows: [],
	row_split: KeepRows,
})

rollout_table : Document.Block
rollout_table = Pdf.table({
	caption: Pdf.caption("Table 3. Rollout waves"),
	columns: [{ width: Fixed(points(92)), align: Start }, { width: Share(2), align: Start }, { width: Share(3), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Date")]), Pdf.header_cell(Column, [Pdf.text("Wave")]), Pdf.header_cell(Column, [Pdf.text("What changes")])])],
	body_rows: [
		("6 Oct 2026", "Pilot customers", "Decision log and typed owners switch on; export stays in preview."),
		("20 Oct 2026", "Team and Business", "All 2.4 features, including archival export and quiet notifications."),
		("3 Nov 2026", "Starter", "All 2.4 features; the digest defaults to 9 a.m. local time."),
	].map(|(date, wave, change)| Pdf.row([Pdf.header_cell(Row, [Pdf.text(date)]), Pdf.cell([Pdf.text(wave)]), Pdf.cell([Pdf.text(change)])])),
	footer_rows: [],
	row_split: KeepRows,
})

## ---------------------------------------------------------------------

feature : Str, List(Pdf.Inline) -> Pdf.ListItem
feature = |label, rest| {
	var $inlines = [Pdf.strong([Pdf.text(label)]), Pdf.text(" ")]
	for inline in rest {
		$inlines = $inlines.append(inline)
	}
	Pdf.list_item([Pdf.rich_paragraph($inlines)])
}

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| Ok([
	Pdf.title("Sprout 2.4"),
	Pdf.rich_paragraph([
		Pdf.text("Planning software for small teams that prefer "),
		Pdf.strong([Pdf.text("clarity over ceremony")]),
		Pdf.text(". Version 2.4 turns every decision into a record your team can find, trust, and print."),
	]),
	Pdf.figure_fit(
		Pdf.figure(
			hero,
			"The Sprout board: three columns labelled Proposed, Deciding, and Decided holding colour-coded cards, with a progress bar along the bottom showing the decision log about two thirds complete.",
			Pdf.caption("The Sprout board moves each decision from proposed to decided in one visible place."),
		),
		ScaleToFit({ minimum_percent: 80 }),
	),
	key_figures(
		options,
		Meadow,
		"Pilot results",
		[
			[Pdf.strong([Pdf.text("54% faster decisions.")]), Pdf.text(" Median time to decide fell from 9.5 to 4.4 days over eight weeks.")],
			[Pdf.strong([Pdf.text("3 fewer meetings a week.")]), Pdf.text(" Status meetings gave way to the shared decision log.")],
			[Pdf.strong([Pdf.text("41 teams, 612 people.")]), Pdf.text(" The pilot ran from June to August 2026 across four companies.")],
		],
	)?,
	Pdf.section([
		Pdf.destination_heading("problem", 1, "The problem"),
		Pdf.rich_paragraph([
			Pdf.text("Important decisions disappear across chat threads, tickets, and meeting notes. Weeks later nobody can say "),
			Pdf.emphasis([Pdf.text("who")]),
			Pdf.text(" decided, "),
			Pdf.emphasis([Pdf.text("why")]),
			Pdf.text(", or whether the decision still stands, so teams meet again to decide the same thing."),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("new", 1, "What is new in 2.4"),
		Pdf.bullet_list([
			feature("Decision log.", [Pdf.text("Every card that reaches Decided is written to an append-only log with its owner, date, and rationale.")]),
			feature("Typed ownership.", [Pdf.text("Owners are people, not channels; a card without an owner cannot leave Proposed.")]),
			feature("Archival export.", [Pdf.text("Run "), Pdf.code("sprout export --pdf --since 2026-07-01"), Pdf.text(" for a tagged, searchable record that stays readable offline.")]),
			feature("Quiet notifications.", [Pdf.text("One daily digest replaces per-card pings; urgent cards still notify at once.")]),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("pilot", 1, "Pilot results"),
		Pdf.paragraph("Median time to decide halved and crossed the five-day target (dashed) in week 6."),
		Pdf.figure_fit(
			Pdf.figure(
				line_chart,
				"Line chart of median days from proposal to decision over eight pilot weeks, falling steadily from 9.5 days in week 1 to 4.4 days in week 8 and crossing the five-day target in week 6. Values are listed in Table 1.",
				Pdf.caption("Figure 1. Median days to decide, weeks 1 to 8"),
			),
			ScaleToFit({ minimum_percent: 80 }),
		),
		cycle_table,
	]),
	Pdf.section([
		Pdf.destination_heading("plans", 1, "Plans and pricing"),
		Pdf.paragraph("Every plan includes the board, the decision log, and archival export."),
		plans_table,
	]),
	Pdf.section([
		Pdf.destination_heading("next", 1, "What comes next"),
		Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("November. ")]), Pdf.text("Calendar sync, so a decision's due date appears where people plan their week.")])]),
				Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("December. ")]), Pdf.text("Templates for hiring, vendor selection, and architecture reviews.")])]),
				Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Early 2027. ")]), Pdf.text("A read-only API for dashboards, starting with "), Pdf.code("GET /v1/decisions"), Pdf.text(".")])]),
			],
		),
	]),
	Pdf.section([
		Pdf.destination_heading("rollout", 1, "Rollout and support"),
		Pdf.paragraph("Sprout 2.4 reaches every workspace in three waves. Existing boards migrate automatically; nothing needs to be exported or re-imported."),
		rollout_table,
		Pdf.paragraph("Support stays with your plan through the rollout. Business workspaces get a migration review with their success manager before their wave switches on."),
		support_table,
		key_figures(
			options,
			Forest,
			"Customer voice",
			[
				[Pdf.quote([Pdf.text("“We stopped re-deciding things. The log settles arguments before they start.”")])],
				[Pdf.text("Maya Lindqvist, Head of Operations, Fjordline Studio (pilot customer)")],
			],
		)?,
		Pdf.rich_paragraph([
			Pdf.text("Start a free Starter workspace at "),
			Pdf.inline_link([Pdf.text("sprout.example/start")], "https://sprout.example/start"),
			Pdf.text(", compare plans in "),
			Pdf.inline_internal_link([Pdf.text("Plans and pricing")], "plans"),
			Pdf.text(", or email "),
			Pdf.inline_link([Pdf.text("launch@sprout.example")], "mailto:launch@sprout.example"),
			Pdf.text(" to book a walkthrough."),
		]),
	]),
])
