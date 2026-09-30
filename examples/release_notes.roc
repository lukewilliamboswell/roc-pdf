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

## Release notes for a fictional load-testing tool, on US Letter: a
## decorative version banner, a highlights callout and a breaking-change
## callout through the custom-block seam, versioned sections in the
## outline, change lists with inline code and issue links, a latency
## chart, a compatibility table, and running headers and footers.
main! = |_args| {
	document = Pdf.document({ contents, language: "en-US", title: "Kestrel 3.0 release notes" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	options = Pdf.Options.default.with_theme(theme).with_page_size(Letter)
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "release-notes.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote release-notes.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## ---------------------------------------------------------------------
## Palette and theme. US Letter (612 × 792 pt) with 60 pt side margins: a
## 492 pt measure.

indigo : Color.SourceValue
indigo = Color.srgb8({ red: 67, green: 56, blue: 202 })

night : Color.SourceValue
night = Color.srgb8({ red: 30, green: 27, blue: 75 })

ink : Color.SourceValue
ink = Color.srgb8({ red: 39, green: 39, blue: 42 })

pink : Color.SourceValue
pink = Color.srgb8({ red: 190, green: 24, blue: 93 })

lilac : Color.SourceValue
lilac = Color.srgb8({ red: 199, green: 210, blue: 254 })

haze : Color.SourceValue
haze = Color.srgb8({ red: 212, green: 212, blue: 216 })

white : Color.SourceValue
white = Color.srgb8({ red: 255, green: 255, blue: 255 })

measure : I64
measure = 492

theme : Theme
theme = {
	body = Theme.body_style(Theme.default)
	heading = Theme.heading_style(Theme.default)
	title = Theme.title_style(Theme.default)
	Theme.default
		.with_body_style({ ..body, color: ink, size: points(10), leading: points(15) })
		.with_heading_style({ ..heading, color: indigo, size: points(15), leading: points(21) })
		.with_title_style({ ..title, color: night, size: points(30), leading: points(36) })
		.with_page_margin({ top: points(48), right: points(60), bottom: points(46), left: points(60) })
		.with_paragraph_spacing(points(7))
		.with_bullet_indent(points(18))
		.with_strong_color(night)
		.with_emphasis_color(indigo)
		.with_code_color(pink)
		.with_table_header_color(indigo)
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(1))
		.with_table_rule(Rule({ color: haze, width: Layout.Unit.millipoints(700) }))
}

## ---------------------------------------------------------------------
## Running furniture.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(72), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("kestrel.example/releases/3.0.0")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

header_mark : Scene.Drawing
header_mark = Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 8, 8), indigo), Layout.rect(10, 0, 8, 8), pink)

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({ header: Pdf.no_region, lead: Pdf.no_lead, footer, gap: points(14) }),
	continuation: Pdf.page_template({
		header: Pdf.region({
			height: points(16),
			start: [Pdf.furniture_text([Pdf.text("Kestrel 3.0 release notes")])],
			center: [],
			end: [Pdf.furniture_image(header_mark)],
		}),
		footer,
		gap: points(16),
	}),
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "highlights", open: True, title: "Highlights" },
	{ depth: 0, destination: "v3-0-0", open: True, title: "3.0.0 (30 September 2026)" },
	{ depth: 1, destination: "breaking", open: True, title: "Breaking changes" },
	{ depth: 1, destination: "added", open: True, title: "Added" },
	{ depth: 1, destination: "fixed", open: True, title: "Fixed" },
	{ depth: 1, destination: "deprecated", open: True, title: "Deprecated" },
	{ depth: 1, destination: "known-issues", open: True, title: "Known issues" },
	{ depth: 0, destination: "compatibility", open: True, title: "Compatibility" },
	{ depth: 0, destination: "upgrading", open: True, title: "Upgrading from 2.x" },
	{ depth: 0, destination: "v2-9-2", open: True, title: "2.9.2 (12 August 2026)" },
	{ depth: 0, destination: "v2-9-1", open: True, title: "2.9.1 (29 July 2026)" },
	{ depth: 0, destination: "thanks", open: True, title: "Thanks" },
]

## ---------------------------------------------------------------------
## Callouts: the custom-block pattern of tests/custom_block/Callout.roc.
## Every paragraph is one line, so the extension measures its height as
## twice the inset, one leading per line, and the paragraph spacing
## between lines. The panel is a rounded tint with a thicker top rule.

CalloutStyle : { accent : Color.SourceValue, fill : Color.SourceValue }

highlight_style : CalloutStyle
highlight_style = { accent: indigo, fill: Color.srgb8({ red: 238, green: 242, blue: 255 }) }

breaking_style : CalloutStyle
breaking_style = { accent: pink, fill: Color.srgb8({ red: 253, green: 242, blue: 248 }) }

callout_inset : Layout.Unit
callout_inset = points(14)

callout : Str, CalloutStyle, List(Document.Block) -> Document.Block
callout = |name, style, paragraphs| {
	leading = Theme.body_style(theme).leading.raw()
	spacing = Theme.paragraph_spacing(theme).raw()
	count = paragraphs.len().to_i64_wrap()
	size = { height: Layout.Unit.from_raw(callout_inset.raw() * 2 + leading * count + spacing * (count - 1)), width: points(measure) }
	Pdf.custom_block({ contents: paragraphs, fragmentation: Unsplittable, inset: callout_inset, name, panel: callout_panel(style, size), size })
}

## A rounded panel with a 3 pt accent along its top edge.
callout_panel : CalloutStyle, Layout.Size -> Scene.Drawing
callout_panel = |style, size| {
	r = 6000
	k = r * 552 // 1000
	right = size.width.raw()
	top = size.height.raw()
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	body = Scene.path({})
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
	cap = Scene.path({})
		.move_to(point(0, top - 3000))
		.line_to(point(0, top - r))
		.cubic_to({ control_1: point(0, top - r + k), control_2: point(r - k, top), end: point(r, top) })
		.line_to(point(right - r, top))
		.cubic_to({ control_1: point(right - r + k, top), control_2: point(right, top - r + k), end: point(right, top - r) })
		.line_to(point(right, top - 3000))
		.close()
		.finish()
	Scene.drawing({}).path(body, Scene.solid_fill(style.fill)).path(cap, Scene.solid_fill(style.accent))
}

## ---------------------------------------------------------------------
## The version banner: a night-blue band carrying "3.0" in large
## seven-segment vector digits and a row of release dots.

digit : U64, Color.SourceValue -> Scene.Drawing
digit = |value, color| {
	a = (0, 32, 18, 4)
	b = (14, 16, 4, 20)
	c = (14, 0, 4, 20)
	d = (0, 0, 18, 4)
	e = (0, 0, 4, 20)
	f = (0, 16, 4, 20)
	g = (0, 16, 18, 4)
	segments = match value {
		0 => [a, b, c, d, e, f]
		1 => [b, c]
		2 => [a, b, g, e, d]
		3 => [a, b, g, c, d]
		_ => [a, b, c, d, e, f, g]
	}
	var $drawing = Scene.drawing({})
	for (x, y, w, h) in segments {
		$drawing = Scene.rectangle($drawing, Layout.rect(x, y, w, h), color)
	}
	$drawing
}

## A small seven-segment digit, 1 pt strokes in a 5 × 9 pt cell.
small_digit : U64, Color.SourceValue -> Scene.Drawing
small_digit = |value, color| {
	a = (0, 8, 5, 1)
	b = (4, 4, 1, 5)
	c = (4, 0, 1, 5)
	d = (0, 0, 5, 1)
	e = (0, 0, 1, 5)
	f = (0, 4, 1, 5)
	g = (0, 4, 5, 1)
	segments = match value {
		0 => [a, b, c, d, e, f]
		1 => [b, c]
		2 => [a, b, g, e, d]
		3 => [a, b, g, c, d]
		4 => [f, g, b, c]
		5 => [a, f, g, c, d]
		6 => [a, f, g, e, c, d]
		7 => [a, b, c]
		8 => [a, b, c, d, e, f, g]
		_ => [a, b, c, d, f, g]
	}
	var $drawing = Scene.drawing({})
	for (x, y, w, h) in segments {
		$drawing = Scene.rectangle($drawing, Layout.rect(x, y, w, h), color)
	}
	$drawing
}

## A three-digit value label starting at (x, y).
value_label : Scene.Drawing, U64, I64, I64, Color.SourceValue -> Scene.Drawing
value_label = |drawing, value, x, y, color| {
	drawing
		.group(Layout.point(x, y), small_digit(value // 100, color))
		.group(Layout.point(x + 8, y), small_digit((value // 10) % 10, color))
		.group(Layout.point(x + 16, y), small_digit(value % 10, color))
}

banner : Document.Block
banner = {
	## The band sits 14 pt above the title, which the decoration's height
	## includes: the drawing leaves its lowest 14 pt empty.
	var $d = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 14, measure, 64), night)
	$d = Scene.rectangle($d, Layout.rect(0, 14, 6, 64), pink)
	$d = $d.group(Layout.point(24, 28), digit(3, white))
	$d = Scene.rectangle($d, Layout.rect(48, 28, 4, 4), white)
	$d = $d.group(Layout.point(58, 28), digit(0, white))
	## Twelve release dots: minor releases in lilac, this major in pink.
	var $x = 300
	var $i = 0
	while $i < 12 {
		$d = Scene.rectangle($d, Layout.rect($x, 42, 8, 8), if $i == 11 pink else lilac)
		$x = $x + 15
		$i = $i + 1
	}
	Pdf.decoration(Scene.rectangle($d, Layout.rect(300, 36, 173, 1), lilac))
}

## ---------------------------------------------------------------------
## Figure 1: p99 latency of the reference scenario by release, as
## horizontal bars on a light grid (shorter is better).

latency_chart : Scene.Drawing
latency_chart = {
	## Milliseconds for 2.8, 2.9, and 3.0.
	values = [(412, haze), (356, lilac), (188, indigo)]
	var $d = Scene.drawing({})
	for step in [0, 1, 2, 3, 4] {
		x = 20 + step * 100
		$d = Scene.rectangle($d, { origin: Layout.point(x, 0), size: { height: points(118), width: Layout.Unit.millipoints(600) } }, haze)
	}
	var $y = 84
	for (value, color) in values {
		$d = Scene.rectangle($d, Layout.rect(20, $y, value, 24), color)
		$d = value_label($d, value.to_u64_wrap(), 28 + value, $y + 8, ink)
		$y = $y - 36
	}
	## Arrow from the 2.9 bar end back to the 3.0 bar end: the improvement.
	$d
		.path(Scene.path({}).move_to(Layout.point(376, 60)).line_to(Layout.point(376, 36)).line_to(Layout.point(256, 36)).finish(), Scene.solid_stroke(pink, Layout.Unit.millipoints(1500)))
		.path(Scene.path({}).move_to(Layout.point(248, 36)).line_to(Layout.point(256, 40)).line_to(Layout.point(256, 32)).close().finish(), Scene.solid_fill(pink))
}

## ---------------------------------------------------------------------
## Change entries.

issue : U64 -> Pdf.Inline
issue = |number| Pdf.inline_link([Pdf.emphasis([Pdf.text("#${number.to_str()}")])], "https://github.example/kestrel/kestrel/issues/${number.to_str()}")

change : List(Pdf.Inline), U64 -> Pdf.ListItem
change = |inlines, number| Pdf.list_item([Pdf.rich_paragraph(inlines.concat([Pdf.text(" ("), issue(number), Pdf.text(")")]))])

compat_row : Str, Str, Str, Str -> Pdf.Row
compat_row = |target, old, new, note| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(target)]),
	Pdf.cell([Pdf.text(old)]),
	Pdf.cell([Pdf.strong([Pdf.text(new)])]),
	Pdf.cell([Pdf.text(note)]),
])

compatibility_table : Document.Block
compatibility_table = Pdf.table({
	caption: Pdf.caption("Table 1. Supported platforms and minimum versions"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Fixed(points(64)), align: Center },
		{ width: Fixed(points(64)), align: Center },
		{ width: Share(4), align: Start },
	],
	header_rows: [Pdf.row([
		Pdf.header_cell(Column, [Pdf.text("Platform")]),
		Pdf.header_cell(Column, [Pdf.text("2.9")]),
		Pdf.header_cell(Column, [Pdf.text("3.0")]),
		Pdf.header_cell(Column, [Pdf.text("Notes")]),
	])],
	body_rows: [
		compat_row("Linux x86-64 (glibc)", "2.28", "2.31", "Ubuntu 20.04, RHEL 9 and later"),
		compat_row("Linux arm64 (glibc)", "2.28", "2.31", "Graviton and Ampere tested"),
		compat_row("Linux x86-64 (musl)", "—", "1.2", "New static build for containers"),
		compat_row("macOS arm64", "12", "13", "Ventura and later"),
		compat_row("macOS x86-64", "12", "—", "Removed; use 2.9 LTS"),
		compat_row("Windows x86-64", "10", "10", "Server 2019 and later"),
		compat_row("Kubernetes operator", "1.26", "1.28", "Helm chart 5.x"),
	],
	footer_rows: [Pdf.row([
		Pdf.spanning(4, Pdf.aligned(Start, Pdf.cell([Pdf.text("2.9 LTS receives security fixes until 30 September 2027.")]))),
	])],
	row_split: KeepRows,
})

contents : List(Document.Block)
contents = [
	banner,
	Pdf.title("Kestrel 3.0 release notes"),
	Pdf.rich_paragraph([
		Pdf.text("Released 30 September 2026 · "),
		Pdf.inline_link([Pdf.emphasis([Pdf.text("Download")])], "https://kestrel.example/download/3.0.0"),
		Pdf.text(" · "),
		Pdf.inline_link([Pdf.emphasis([Pdf.text("Full changelog")])], "https://github.example/kestrel/kestrel/compare/v2.9.2...v3.0.0"),
		Pdf.text(" · "),
		Pdf.inline_internal_link([Pdf.emphasis([Pdf.text("Upgrade guide")])], "upgrading"),
	]),
	Pdf.section([
		Pdf.destination_heading("highlights", 1, "Highlights"),
		Pdf.rich_paragraph([
			Pdf.text("Kestrel 3.0 is the first major release in two years. It replaces the scenario engine, halves tail latency under load, and makes every run reproducible from a single "),
			Pdf.code("kestrel.lock"),
			Pdf.text(" file."),
		]),
		callout(
			"Highlights",
			highlight_style,
			[
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("47% lower p99 latency")]), Pdf.text(" in the reference scenario, from 356 ms to 188 ms.")]),
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Reproducible runs")]), Pdf.text(": seeds, versions, and targets are pinned in "), Pdf.code("kestrel.lock"), Pdf.text(".")]),
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Scenario files in TOML")]), Pdf.text(", checked by "), Pdf.code("kestrel check"), Pdf.text(" before a run starts.")]),
			],
		),
		Pdf.figure(
			latency_chart,
			"Horizontal bar chart of p99 latency in the reference scenario: 412 ms in 2.8, 356 ms in 2.9, and 188 ms in 3.0. An arrow marks the 47% reduction from 2.9 to 3.0.",
			Pdf.caption("Figure 1. p99 latency in the reference scenario for 2.8, 2.9, and 3.0 (shorter is better)"),
		),
	]),
	Pdf.section([
		Pdf.destination_heading("v3-0-0", 1, "3.0.0 · 30 September 2026"),
		Pdf.section([
			Pdf.destination_heading("breaking", 2, "Breaking changes"),
			callout(
				"Breaking changes",
				breaking_style,
				[
					Pdf.rich_paragraph([Pdf.strong([Pdf.text("Action required.")]), Pdf.text(" YAML scenarios no longer load. Convert them before upgrading:")]),
					Pdf.rich_paragraph([Pdf.code("kestrel migrate scenarios/ --to toml --write")]),
				],
			),
			Pdf.bullet_list([
				change([Pdf.text("Scenario files are TOML; "), Pdf.code("kestrel migrate"), Pdf.text(" converts YAML files in place.")], 2210),
				change([Pdf.text("The "), Pdf.code("--rps"), Pdf.text(" flag is now "), Pdf.code("--rate"), Pdf.text(" and accepts units such as "), Pdf.code("500/s"), Pdf.text(".")], 2187),
				change([Pdf.text("Metrics are exported as OpenTelemetry by default; set "), Pdf.code("export = \"statsd\""), Pdf.text(" to keep the old format.")], 2143),
				change([Pdf.text("macOS on Intel is no longer supported; the 2.9 LTS line remains available.")], 2231),
			]),
		]),
		Pdf.section([
			Pdf.destination_heading("added", 2, "Added"),
			Pdf.bullet_list([
				change([Pdf.code("kestrel.lock"), Pdf.text(" pins the random seed, target versions, and plugin hashes for every run.")], 2102),
				change([Pdf.code("kestrel check"), Pdf.text(" validates scenarios, including unreachable steps and unused variables.")], 2125),
				Pdf.list_item([
					Pdf.rich_paragraph([Pdf.text("New open-loop arrival models:")]),
					Pdf.bullet_list([
						change([Pdf.code("poisson"), Pdf.text(" for independent arrivals;")], 2166),
						change([Pdf.code("ramp"), Pdf.text(" and "), Pdf.code("step"), Pdf.text(" for capacity searches.")], 2167),
					]),
				]),
				change([Pdf.text("A static musl build for minimal container images.")], 2198),
				change([Pdf.text("Live terminal dashboard, enabled with "), Pdf.code("--watch"), Pdf.text(".")], 2204),
			]),
		]),
		Pdf.section([
			Pdf.destination_heading("fixed", 2, "Fixed"),
			Pdf.bullet_list([
				change([Pdf.text("Coordinated omission no longer hides stalls longer than the sampling interval.")], 2091),
				change([Pdf.text("HTTP/2 connections are reused across scenario steps instead of per step.")], 2118),
				change([Pdf.text("Reports keep their percentile order when a run is interrupted with "), Pdf.code("Ctrl-C"), Pdf.text(".")], 2150),
			]),
		]),
		Pdf.section([
			Pdf.destination_heading("deprecated", 2, "Deprecated"),
		Pdf.bullet_list([
			change([Pdf.text("The "), Pdf.code("--duration"), Pdf.text(" flag; set "), Pdf.code("duration"), Pdf.text(" in the scenario file instead. Removal is planned for 4.0.")], 2215),
			change([Pdf.text("The Graphite exporter, in favour of OpenTelemetry.")], 2144),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("known-issues", 2, "Known issues"),
		Pdf.bullet_list([
			change([Pdf.text("The live dashboard flickers in terminals narrower than 80 columns.")], 2240),
			change([Pdf.code("kestrel migrate"), Pdf.text(" drops YAML comments; review converted files before committing them.")], 2236),
		]),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("compatibility", 1, "Compatibility"),
		Pdf.paragraph("Kestrel 3.0 raises the minimum versions on most platforms. Check Table 1 before you upgrade agents on older hosts."),
		compatibility_table,
	]),
	Pdf.section([
		Pdf.destination_heading("upgrading", 1, "Upgrading from 2.x"),
		Pdf.keep_together([
			Pdf.numbered_list(
				{ start: 1, style: Decimal },
				[
					Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Upgrade to 2.9.2 first and run your suite once; it warns about every deprecated flag.")])]),
					Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Convert scenarios with "), Pdf.code("kestrel migrate scenarios/ --to toml --write"), Pdf.text(".")])]),
					Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Install 3.0 and run "), Pdf.code("kestrel check"), Pdf.text(" on every converted scenario.")])]),
					Pdf.list_item([
						Pdf.rich_paragraph([Pdf.text("Run once to create "), Pdf.code("kestrel.lock"), Pdf.text(", then commit it beside the scenarios.")]),
					]),
				],
			),
		]),
		Pdf.rich_paragraph([
			Pdf.text("Questions are welcome in "),
			Pdf.inline_link([Pdf.emphasis([Pdf.text("the discussion forum")])], "https://github.example/kestrel/kestrel/discussions"),
			Pdf.text("."),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("v2-9-2", 1, "2.9.2 · 12 August 2026"),
		Pdf.bullet_list([
			change([Pdf.text("Warns when a scenario uses a flag removed in 3.0.")], 2176),
			change([Pdf.text("Fixed a crash when a target returned an empty "), Pdf.code("Content-Type"), Pdf.text(" header.")], 2171),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("v2-9-1", 1, "2.9.1 · 29 July 2026"),
		Pdf.bullet_list([
			change([Pdf.text("Security: updated the bundled TLS library to address "), Pdf.expansion("CVE-2026-31337", "Common Vulnerabilities and Exposures entry 2026-31337"), Pdf.text(".")], 2160),
			change([Pdf.text("Histogram buckets above 60 s are no longer merged.")], 2158),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("thanks", 1, "Thanks"),
		Pdf.rich_paragraph([
			Pdf.text("Kestrel 3.0 includes work from 64 contributors, 23 of them new. Special thanks to "),
			Pdf.strong([Pdf.text("Amara Okafor")]),
			Pdf.text(" for the arrival models, "),
			Pdf.strong([Pdf.text("Tomás Ribeiro")]),
			Pdf.text(" for the TOML migration, and "),
			Pdf.strong([Pdf.text("Yuki Tanaka")]),
			Pdf.text(" for the coordinated-omission fix. Kestrel is released under the "),
			Pdf.expansion("MPL-2.0", "Mozilla Public License, version 2.0"),
			Pdf.text("."),
		]),
	]),
]
