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
import "fonts/NotoSans-Regular.ttf" as regular_bytes : List(U8)
import "fonts/NotoSans-Bold.ttf" as bold_bytes : List(U8)
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## Release notes for a fictional load-testing tool, on US Letter: a
## decorative version banner spaced from the title, a night-blue
## highlights callout and a breaking-change callout through the
## custom-block seam, measured by the package, versioned sections in the
## outline, change lists with inline code and issue links, a latency
## chart, a striped compatibility table, and running headers over a ruled
## backdrop and footers.
main! = |_args| {
	fonts = register_fonts({})?
	options = Pdf.Options.default.with_theme(with_faces(theme, fonts)).with_font_registry(fonts.registry).with_page_size(Letter)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-US", title: "Kestrel 3.0 release notes" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "release-notes.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote release-notes.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }

## Noto Sans Regular and Bold, and Source Code Pro Regular, each retained
## byte-for-byte from its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin = [Font.Script.from_iso15924("Latn")]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	mono = add(bold.registry, mono_bytes)?
	Ok({ regular: regular.face, bold: bold.face, mono: mono.face, registry: mono.registry })
}

## Regular for body text; Bold for the title, both heading levels, and
## `Pdf.strong`; the monospace face for `Pdf.code`, at 88% of the text
## around it so its larger letters match the body. Level-1 headings are
## larger than level-2 headings. `Pdf.emphasis` keeps a colour: no italic
## face is vendored beside this example.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	heading = Theme.heading_style(base)
	title = Theme.title_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_level_style(H1, { ..heading, font: faces.bold, color: night, size: points(17), leading: points(23) })
		.with_heading_level_style(H2, { ..heading, font: faces.bold, color: indigo, size: points(12), leading: points(18) })
		.with_inline_font(Strong, faces.bold)
		.with_inline_font(Code, faces.mono)
		.with_inline_scale(Code, 88)
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
		.with_emphasis_color(indigo)
		.with_code_color(pink)
		.with_table_header_color(indigo)
		.with_table_header_fill(Color.srgb8({ red: 238, green: 242, blue: 255 }))
		.with_table_body_fills({ odd: NoFill, even: Fill(Color.srgb8({ red: 248, green: 248, blue: 250 })) })
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(2))
		.with_table_rule(Rule({ color: haze, width: Layout.Unit.millipoints(700) }))
		.with_link_color(indigo)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1500), thickness: Layout.Unit.millipoints(600) }))
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
		header: Pdf.with_backdrop(
			Pdf.region({
				height: points(16),
				start: [Pdf.furniture_text([Pdf.text("Kestrel 3.0 release notes")])],
				center: [],
				end: [Pdf.furniture_image(Scene.drawing({}).group(Layout.point(0, 4), header_mark))],
			}),
			Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(600), width: points(measure) } }, haze),
		),
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
## The package measures each callout's paragraphs at the panel's content
## width, so they may wrap. The panel is a rounded tint with a thicker top
## rule; the highlights sit in white on the banner's night blue.

CalloutStyle : { accent : Color.SourceValue, fill : Color.SourceValue, label : Color.SourceValue, text : Color.SourceValue }

highlight_style : CalloutStyle
highlight_style = { accent: pink, fill: night, label: lilac, text: Color.srgb8({ red: 255, green: 255, blue: 255 }) }

breaking_style : CalloutStyle
breaking_style = { accent: pink, fill: Color.srgb8({ red: 253, green: 242, blue: 248 }), label: pink, text: ink }

callout_inset : Layout.Unit
callout_inset = points(14)

## Each callout is scoped so its `Strong` labels take its label colour
## and its text and code its text colour.
callout : Pdf.Options, Str, CalloutStyle, List(Document.Block) -> Try(Document.Block, Pdf.Error)
callout = |options, name, style, paragraphs| {
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-US", width: points(measure - 28) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(measure) }
	block = Pdf.custom_block({ contents: paragraphs, fragmentation: Unsplittable, inset: callout_inset, name, panel: callout_panel(style, size), size })
	scope = Theme.Scope.empty.with_color(Strong, style.label).with_color(Text, style.text)
	Ok(Pdf.scoped(if style.text == ink scope else scope.with_color(Code, style.label), [block]))
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
## The version banner: a night-blue band with a pink edge and a row of
## release dots. It is decoration; the version is in the title below.

banner : Document.Block
banner = {
	## The band keeps 14 pt between itself and the title through its
	## decoration spacing, not empty drawing area.
	var $d = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, measure, 64), night)
	$d = Scene.rectangle($d, Layout.rect(0, 0, 6, 64), pink)

	## Twelve release dots: minor releases in lilac, this major in pink.
	var $x = 300
	var $i = 0
	while $i < 12 {
		$d = Scene.rectangle($d, Layout.rect($x, 28, 8, 8), if $i == 11 pink else lilac)
		$x = $x + 15
		$i = $i + 1
	}
	Pdf.spaced_decoration(Scene.rectangle($d, Layout.rect(300, 22, 173, 1), lilac), { above: points(0), behind: Bool.False, below: points(14) })
}

## ---------------------------------------------------------------------
## Figure 1: p99 latency of the reference scenario by release, as
## horizontal bars on a light grid (shorter is better).

latency_chart : Scene.Drawing
latency_chart = {
	## Milliseconds for 2.8, 2.9, and 3.0, drawn at 0.9 pt per millisecond
	## from a 44 pt label column, with a grid line every 100 ms.
	values = [("2.8", 412, haze), ("2.9", 356, lilac), ("3.0", 188, indigo)]
	left = 44
	bar = |value| value * 9 // 10
	var $d = Scene.drawing({})
	for step in [0, 1, 2, 3, 4] {
		x = left + bar(step * 100)
		$d = Scene.rectangle($d, { origin: Layout.point(x, 16), size: { height: points(118), width: Layout.Unit.millipoints(600) } }, haze)
		$d = $d.text({ align: Center, color: ink, origin: Layout.point(x, 4), size: points(7), text: if step == 4 "400 ms" else (step * 100).to_str() })
	}
	var $y = 100
	for (release, value, color) in values {
		$d = Scene.rectangle($d, Layout.rect(left, $y, bar(value), 24), color)
		$d = $d.text({ align: End, color: ink, origin: Layout.point(left - 8, $y + 9), size: points(9), text: release })
		$d = $d.text({ align: Start, color: ink, origin: Layout.point(left + bar(value) + 6, $y + 9), size: points(8), text: "${value.to_str()} ms" })
		$y = $y - 36
	}

	## Arrow from the 2.9 bar end back to the 3.0 bar end: the improvement.
	end_29 = left + bar(356)
	end_30 = left + bar(188)
	$d
		.path(Scene.path({}).move_to(Layout.point(end_29, 76)).line_to(Layout.point(end_29, 52)).line_to(Layout.point(end_30 + 8, 52)).finish(), Scene.solid_stroke(pink, Layout.Unit.millipoints(1500)))
		.path(Scene.path({}).move_to(Layout.point(end_30, 52)).line_to(Layout.point(end_30 + 8, 56)).line_to(Layout.point(end_30 + 8, 48)).close().finish(), Scene.solid_fill(pink))
		.text({ align: Start, color: pink, origin: Layout.point(end_29 + 6, 60), size: points(8), text: "−47%" })
		.path(Scene.path({}).move_to(Layout.point(left, 16)).line_to(Layout.point(measure - 1, 16)).finish(), Scene.solid_stroke(ink, Layout.Unit.millipoints(700)))
}

## ---------------------------------------------------------------------
## Change entries.

issue : U64 -> Pdf.Inline
issue = |number| Pdf.inline_link([Pdf.emphasis([Pdf.text("#${number.to_str()}")])], "https://github.example/kestrel/kestrel/issues/${number.to_str()}")

change : List(Pdf.Inline), U64 -> Pdf.ListItem
change = |inlines, number| Pdf.list_item([Pdf.rich_paragraph(inlines.concat([Pdf.text(" ("), issue(number), Pdf.text(")")]))])

## The new version is strong, in the bold face.
compat_row : Str, Str, Str, Str -> Pdf.Row
compat_row = |target, old, new, note| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(target)]),
	Pdf.cell([Pdf.text(old)]),
	Pdf.cell([Pdf.strong([Pdf.text(new)])]),
	if new == "—" Pdf.shaded(Color.srgb8({ red: 253, green: 242, blue: 248 }), Pdf.cell([Pdf.text(note)])) else Pdf.cell([Pdf.text(note)]),
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
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Platform")]),
			Pdf.header_cell(Column, [Pdf.text("2.9")]),
			Pdf.header_cell(Column, [Pdf.text("3.0")]),
			Pdf.header_cell(Column, [Pdf.text("Notes")]),
		]),
	],
	body_rows: [
		compat_row("Linux x86-64 (glibc)", "2.28", "2.31", "Ubuntu 20.04, RHEL 9 and later"),
		compat_row("Linux arm64 (glibc)", "2.28", "2.31", "Graviton and Ampere tested"),
		compat_row("Linux x86-64 (musl)", "—", "1.2", "New static build for containers"),
		compat_row("macOS arm64", "12", "13", "Ventura and later"),
		compat_row("macOS x86-64", "12", "—", "Removed; use 2.9 LTS"),
		compat_row("Windows x86-64", "10", "10", "Server 2019 and later"),
		compat_row("Kubernetes operator", "1.26", "1.28", "Helm chart 5.x"),
	],
	footer_rows: [
		Pdf.row([
			Pdf.spanning(4, Pdf.aligned(Start, Pdf.cell([Pdf.text("2.9 LTS receives security fixes until 30 September 2027.")]))),
		]),
	],
	row_split: KeepRows,
})

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| Ok([
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
			options,
			"Highlights",
			highlight_style,
			[
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("47% lower p99 latency")]), Pdf.text(" in the reference scenario, from 356 ms to 188 ms.")]),
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Reproducible runs")]), Pdf.text(": seeds, versions, and targets are pinned in "), Pdf.code("kestrel.lock"), Pdf.text(".")]),
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Scenario files in TOML")]), Pdf.text(", checked by "), Pdf.code("kestrel check"), Pdf.text(" before a run starts.")]),
			],
		)?,
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
				options,
				"Breaking changes",
				breaking_style,
				[
					Pdf.rich_paragraph([Pdf.strong([Pdf.text("Action required.")]), Pdf.text(" YAML scenarios no longer load. Convert them before upgrading:")]),
					Pdf.rich_paragraph([Pdf.code("kestrel migrate scenarios/ --to toml --write")]),
				],
			)?,
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
])
