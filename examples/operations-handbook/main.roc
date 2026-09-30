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
import "fonts/SourceSans3-Regular.ttf" as regular_bytes : List(U8)
import "fonts/SourceSans3-Bold.ttf" as bold_bytes : List(U8)
import "fonts/SourceSans3-It.ttf" as italic_bytes : List(U8)
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## An on-call runbook for a payments platform: running headers and footers
## with `Page N of M`, an outline over numbered sections, a severity matrix
## and an escalation table with shaded levels and striped rows, numbered
## procedures with nested steps and inline commands, warning and note
## callouts and dark console panels authored through the custom-block seam
## and measured by the package, a vector service-topology diagram, and
## appendices of commands and procedure drills (a drill never run leaves
## its cell empty).
main! = |_args| {
	fonts = register_fonts({})?
	options = Pdf.Options.default.with_theme(with_faces(theme, fonts)).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-AU", title: "Payments platform on-call runbook" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "operations-handbook.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote operations-handbook.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, italic : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }

## Source Sans 3 Regular, Bold, and Italic, and Source Code Pro Regular, each retained
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
## Italic for `Pdf.emphasis`; the monospace face for `Pdf.code`, at 88% of
## the text around it. Level-2 headings are smaller and charcoal.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	title = Theme.title_style(base)
	heading = Theme.heading_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_level_style(H1, { ..heading, font: faces.bold })
		.with_heading_level_style(H2, { ..heading, font: faces.bold, color: charcoal, size: points(12), leading: points(17) })
		.with_inline_font(Strong, faces.bold)
		.with_inline_font(Emphasis, faces.italic)
		.with_inline_font(Code, faces.mono)
		.with_inline_scale(Code, 88)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## ---------------------------------------------------------------------
## Palette and theme. A4 with 52 pt margins: a 491 pt measure.

teal : Color.SourceValue
teal = Color.srgb8({ red: 0, green: 105, blue: 112 })

charcoal : Color.SourceValue
charcoal = Color.srgb8({ red: 33, green: 41, blue: 52 })

mist : Color.SourceValue
mist = Color.srgb8({ red: 176, green: 190, blue: 197 })

rust : Color.SourceValue
rust = Color.srgb8({ red: 158, green: 62, blue: 20 })

white : Color.SourceValue
white = Color.srgb8({ red: 255, green: 255, blue: 255 })

measure : I64
measure = 491

theme : Theme
theme = {
	body = Theme.body_style(Theme.default)
	heading = Theme.heading_style(Theme.default)
	title = Theme.title_style(Theme.default)
	Theme.default
		.with_body_style({ ..body, color: charcoal, size: points(10), leading: points(14) })
		.with_heading_style({ ..heading, color: teal, size: points(14), leading: points(20) })
		.with_title_style({ ..title, color: charcoal, size: points(26), leading: points(32) })
		.with_page_margin({ top: points(44), right: points(52), bottom: points(44), left: points(52) })
		.with_paragraph_spacing(points(7))
		.with_bullet_indent(points(20))
		.with_code_color(rust)
		.with_table_header_color(teal)
		.with_table_header_fill(Color.srgb8({ red: 232, green: 245, blue: 246 }))
		.with_table_body_fills({ odd: NoFill, even: Fill(Color.srgb8({ red: 248, green: 249, blue: 250 })) })
		.with_table_body_rule(Rule({ color: Color.srgb8({ red: 226, green: 230, blue: 234 }), width: Layout.Unit.millipoints(400) }))
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(3))
		.with_table_rule(Rule({ color: mist, width: Layout.Unit.millipoints(600) }))
		.with_link_color(teal)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1400), thickness: Layout.Unit.millipoints(500) }))
}

## ---------------------------------------------------------------------
## Running furniture: a footer on every page, a header with a rule on
## continuation pages.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(72), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("Payments platform · Runbook PAY-OPS-004 · Revision 4.2")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

## The continuation header's backdrop: a teal accent over its start edge
## and a hairline along its foot, beneath the slots' text.
header_rule : Scene.Drawing
header_rule = Scene.rectangle(
	Scene.rectangle(Scene.drawing({}), Layout.rect(0, 20, 40, 2), teal),
	{ origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(600), width: points(measure) } },
	mist,
)

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({ header: Pdf.no_region, lead: Pdf.no_lead, footer, gap: points(14) }),
	continuation: Pdf.page_template({
		header: Pdf.region({ height: points(22), start: [Pdf.furniture_text([Pdf.text("On-call runbook · Payments platform")])], center: [], end: [Pdf.furniture_text([Pdf.text("PAY-OPS-004 · Revision 4.2")])], backdrop: Backdrop(header_rule), slot_inset: points(3) }),
		footer,
		gap: points(14),
	}),
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "scope", open: True, title: "1 Scope and on-call duties" },
	{ depth: 0, destination: "topology", open: True, title: "2 Service topology" },
	{ depth: 0, destination: "severity", open: True, title: "3 Severity levels" },
	{ depth: 0, destination: "response", open: True, title: "4 Incident response procedure" },
	{ depth: 1, destination: "triage", open: True, title: "4.1 Triage" },
	{ depth: 1, destination: "rollback", open: True, title: "4.2 Rolling back a release" },
	{ depth: 1, destination: "failover", open: True, title: "4.3 Database failover" },
	{ depth: 0, destination: "escalation", open: True, title: "5 Escalation" },
	{ depth: 0, destination: "review", open: True, title: "6 After the incident" },
	{ depth: 0, destination: "commands", open: True, title: "Appendix A. Command reference" },
	{ depth: 0, destination: "drills", open: True, title: "Appendix B. Procedure drills" },
]

## ---------------------------------------------------------------------
## Callouts: a separately authored extension of the custom-block seam (the
## pattern of tests/custom_block/Callout.roc). The package measures each
## callout's content at the panel's content width with
## `Pdf.measure_custom_content`, so its paragraphs may wrap. A coloured bar
## runs down the start edge of a tinted rounded panel; console panels are
## dark, with light code.

CalloutStyle : { accent : Color.SourceValue, fill : Color.SourceValue, stroke : Color.SourceValue }

warning_style : CalloutStyle
warning_style = {
	accent: Color.srgb8({ red: 214, green: 120, blue: 0 }),
	fill: Color.srgb8({ red: 255, green: 246, blue: 232 }),
	stroke: Color.srgb8({ red: 240, green: 200, blue: 150 }),
}

note_style : CalloutStyle
note_style = {
	accent: teal,
	fill: Color.srgb8({ red: 232, green: 245, blue: 246 }),
	stroke: Color.srgb8({ red: 160, green: 205, blue: 208 }),
}

console_style : CalloutStyle
console_style = {
	accent: Color.srgb8({ red: 120, green: 200, blue: 190 }),
	fill: Color.srgb8({ red: 32, green: 38, blue: 46 }),
	stroke: Color.srgb8({ red: 32, green: 38, blue: 46 }),
}

callout_inset : Layout.Unit
callout_inset = points(14)

## The measured box of a callout's paragraphs: their height at the panel's
## content width (inside the inset and clear of the accent bar), plus the
## inset above and below.
measured : Pdf.Options, List(Document.Block) -> Try(Layout.Size, Pdf.Error)
measured = |options, paragraphs| {
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-AU", width: points(measure - 28) })?
	Ok({ height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(measure) })
}

## A callout of paragraphs that may wrap.
callout : Pdf.Options, Str, CalloutStyle, List(Document.Block) -> Try(Document.Block, Pdf.Error)
callout = |options, name, style, paragraphs| {
	size = measured(options, paragraphs)?
	block = Pdf.custom_block({ contents: paragraphs, fragmentation: Unsplittable, inset: callout_inset, name, panel: callout_panel(style, size), size })

	## Each callout's labels take its accent colour: a warning's amber, a
	## note's teal.
	Ok(Pdf.scoped(Theme.Scope.empty.with_color(Strong, style.accent), [block]))
}

## A dark command panel: one rich paragraph whose lines are separated by
## explicit line breaks, its code set light on the panel.
console : Pdf.Options, List(Str) -> Try(Document.Block, Pdf.Error)
console = |options, commands| {
	var $inlines = List.with_capacity(commands.len() * 2)
	for command in commands {
		if !$inlines.is_empty() {
			$inlines = $inlines.append(Pdf.line_break)
		}
		$inlines = $inlines.append(Pdf.code(command))
	}
	paragraphs = [Pdf.rich_paragraph($inlines)]
	size = measured(options, paragraphs)?
	block = Pdf.custom_block({ contents: paragraphs, fragmentation: Unsplittable, inset: callout_inset, name: "Commands", panel: callout_panel(console_style, size), size })
	light = Color.srgb8({ red: 226, green: 232, blue: 240 })
	Ok(Pdf.scoped(Theme.Scope.empty.with_color(Text, light).with_color(Code, light), [block]))
}

labelled : Str, List(Pdf.Inline) -> Document.Block
labelled = |label, inlines| Pdf.rich_paragraph([Pdf.strong([Pdf.text(label)]), Pdf.text("  ")].concat(inlines))

## A rounded panel filling the measured box with a 4 pt accent bar along
## its start edge. The outline stays inside the box.
callout_panel : CalloutStyle, Layout.Size -> Scene.Drawing
callout_panel = |style, size| {
	half = 500
	r = 5000
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
	bar = Scene.path({})
		.move_to(point(left + r, bottom))
		.line_to(point(left + 4000, bottom))
		.line_to(point(left + 4000, top))
		.line_to(point(left + r, top))
		.cubic_to({ control_1: point(left + r - k, top), control_2: point(left, top - r + k), end: point(left, top - r) })
		.line_to(point(left, bottom + r))
		.cubic_to({ control_1: point(left, bottom + r - k), control_2: point(left + r - k, bottom), end: point(left + r, bottom) })
		.close()
		.finish()
	Scene.drawing({})
		.path(outline_path, { fill: AuthorSolidFill(style.fill), stroke: AuthorSolidStroke({ color: style.stroke, width: points(1) }) })
		.path(bar, Scene.solid_fill(style.accent))
}

## ---------------------------------------------------------------------
## Figure 1: the service topology. Each tier is a rounded box with a
## numbered badge and its name; the numbered list after the figure
## describes every tier.

## A rounded rectangle path at (x, y) of size w × h, radius r, in points.
rounded : I64, I64, I64, I64, I64 -> Scene.AuthorPath
rounded = |x, y, w, h, r| {
	k = r * 552 // 1000
	p = |px, py| { x: Layout.Unit.from_raw(px), y: Layout.Unit.from_raw(py) }
	l = x * 1000
	b = y * 1000
	rt = (x + w) * 1000
	t = (y + h) * 1000
	rr = r * 1000
	kk = k * 1000
	Scene.path({})
		.move_to(p(l + rr, b))
		.line_to(p(rt - rr, b))
		.cubic_to({ control_1: p(rt - rr + kk, b), control_2: p(rt, b + rr - kk), end: p(rt, b + rr) })
		.line_to(p(rt, t - rr))
		.cubic_to({ control_1: p(rt, t - rr + kk), control_2: p(rt - rr + kk, t), end: p(rt - rr, t) })
		.line_to(p(l + rr, t))
		.cubic_to({ control_1: p(l + rr - kk, t), control_2: p(l, t - rr + kk), end: p(l, t - rr) })
		.line_to(p(l, b + rr))
		.cubic_to({ control_1: p(l, b + rr - kk), control_2: p(l + rr - kk, b), end: p(l + rr, b) })
		.close()
		.finish()
}

## A tier box: tinted body, coloured header strip, a numbered badge, and
## the tier's name.
tier : Scene.Drawing, { x : I64, y : I64, w : I64, h : I64, n : U64, name : Str, color : Color.SourceValue, tint : Color.SourceValue } -> Scene.Drawing
tier = |drawing, { x, y, w, h, n, name, color, tint }| {
	base = drawing
		.path(rounded(x, y, w, h, 6), { fill: AuthorSolidFill(tint), stroke: AuthorSolidStroke({ color, width: points(1) }) })
		.path(rounded(x + 8, y + h - 34, 26, 26, 13), Scene.solid_fill(color))
		.text_in(Strong, { align: Center, color: white, origin: Layout.point(x + 21, y + h - 25), size: points(11), text: n.to_str() })
	Scene.rectangle(base, Layout.rect(x + 42, y + h - 18, w - 52, 4), color)
		.text({ align: Center, color: charcoal, origin: Layout.point(x + w // 2, y + 9), size: points(8), text: name })
}

## A horizontal arrow from x1 to x2 at height y, with a filled head.
arrow_right : Scene.Drawing, I64, I64, I64 -> Scene.Drawing
arrow_right = |drawing, x1, x2, y| {
	head = Scene.path({}).move_to(Layout.point(x2, y)).line_to(Layout.point(x2 - 7, y + 4)).line_to(Layout.point(x2 - 7, y - 4)).close().finish()
	drawing
		.path(Scene.path({}).move_to(Layout.point(x1, y)).line_to(Layout.point(x2 - 6, y)).finish(), Scene.solid_stroke(charcoal, Layout.Unit.millipoints(1200)))
		.path(head, Scene.solid_fill(charcoal))
}

## A vertical arrow from y1 down to y2 at x.
arrow_down : Scene.Drawing, I64, I64, I64 -> Scene.Drawing
arrow_down = |drawing, x, y1, y2| {
	head = Scene.path({}).move_to(Layout.point(x, y2)).line_to(Layout.point(x - 4, y2 + 7)).line_to(Layout.point(x + 4, y2 + 7)).close().finish()
	drawing
		.path(Scene.path({}).move_to(Layout.point(x, y1)).line_to(Layout.point(x, y2 + 6)).finish(), Scene.solid_stroke(charcoal, Layout.Unit.millipoints(1200)))
		.path(head, Scene.solid_fill(charcoal))
}

topology : Scene.Drawing
topology = {
	edge = Color.srgb8({ red: 88, green: 101, blue: 242 })
	edge_tint = Color.srgb8({ red: 238, green: 240, blue: 254 })
	app_tint = Color.srgb8({ red: 229, green: 243, blue: 244 })
	data = Color.srgb8({ red: 176, green: 96, blue: 16 })
	data_tint = Color.srgb8({ red: 253, green: 243, blue: 230 })
	zone = Color.srgb8({ red: 248, green: 249, blue: 250 })

	# The production zone behind the application tiers, dashed by short bars.
	var $d = Scene.drawing({})
		.path(rounded(128, 2, 358, 172, 8), { fill: AuthorSolidFill(zone), stroke: AuthorSolidStroke({ color: mist, width: Layout.Unit.millipoints(800) }) })
	$d = tier($d, { x: 4, y: 106, w: 100, h: 58, n: 1, name: "Edge load balancer", color: edge, tint: edge_tint })
	$d = tier($d, { x: 144, y: 106, w: 100, h: 58, n: 2, name: "API gateway", color: edge, tint: edge_tint })
	$d = tier($d, { x: 268, y: 106, w: 100, h: 58, n: 3, name: "Payments API", color: teal, tint: app_tint })
	$d = tier($d, { x: 382, y: 106, w: 96, h: 58, n: 4, name: "Acquirer adapters", color: teal, tint: app_tint })
	$d = tier($d, { x: 144, y: 12, w: 100, h: 58, n: 5, name: "Ledger database", color: data, tint: data_tint })
	$d = tier($d, { x: 382, y: 12, w: 96, h: 58, n: 6, name: "Settlement queue", color: data, tint: data_tint })
	$d = tier($d, { x: 268, y: 12, w: 100, h: 58, n: 7, name: "Settlement worker", color: teal, tint: app_tint })
	$d = arrow_right($d, 104, 144, 135)
	$d = arrow_right($d, 244, 268, 135)
	$d = arrow_right($d, 368, 382, 135)

	## The adapters publish to the queue below them.
	$d = arrow_down($d, 430, 106, 70)

	## The payments API writes to the ledger: down, left, and down again.
	ledger_head = Scene.path({}).move_to(Layout.point(194, 70)).line_to(Layout.point(190, 77)).line_to(Layout.point(198, 77)).close().finish()
	$d = $d
		.path(Scene.path({}).move_to(Layout.point(296, 106)).line_to(Layout.point(296, 88)).line_to(Layout.point(194, 88)).line_to(Layout.point(194, 76)).finish(), Scene.solid_stroke(charcoal, Layout.Unit.millipoints(1200)))
		.path(ledger_head, Scene.solid_fill(charcoal))

	## The settlement worker drains the queue and reconciles against the
	## ledger: arrows into it from both sides.
	left_head = |x| Scene.path({}).move_to(Layout.point(x, 41)).line_to(Layout.point(x + 7, 45)).line_to(Layout.point(x + 7, 37)).close().finish()
	$d
		.path(Scene.path({}).move_to(Layout.point(382, 41)).line_to(Layout.point(374, 41)).finish(), Scene.solid_stroke(charcoal, Layout.Unit.millipoints(1200)))
		.path(left_head(368), Scene.solid_fill(charcoal))
		.path(Scene.path({}).move_to(Layout.point(268, 41)).line_to(Layout.point(250, 41)).finish(), Scene.solid_stroke(charcoal, Layout.Unit.millipoints(1200)))
		.path(left_head(244), Scene.solid_fill(charcoal))
}

## ---------------------------------------------------------------------
## Tables.

## Each level's cell is tinted by its urgency.
severity_row : Str, Str, Str, Str -> Pdf.Row
severity_row = |level, meaning, response, example| Pdf.row([
	Pdf.shaded(severity_tint(level), Pdf.header_cell(Row, [Pdf.strong([Pdf.text(level)])])),
	Pdf.cell([Pdf.text(meaning)]),
	Pdf.cell([Pdf.text(response)]),
	Pdf.cell([Pdf.emphasis([Pdf.text(example)])]),
])

severity_tint : Str -> Color.SourceValue
severity_tint = |level| match level {
	"SEV1" => Color.srgb8({ red: 253, green: 222, blue: 222 })
	"SEV2" => Color.srgb8({ red: 255, green: 236, blue: 214 })
	"SEV3" => Color.srgb8({ red: 255, green: 247, blue: 214 })
	_ => Color.srgb8({ red: 236, green: 244, blue: 236 })
}

severity_table : Document.Block
severity_table = Pdf.table({
	caption: Pdf.caption("Table 1. Severity levels and response targets"),
	columns: [
		{ width: Fixed(points(46)), align: Start },
		{ width: Share(3), align: Start },
		{ width: Share(2), align: Start },
		{ width: Share(3), align: Start },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Level")]),
			Pdf.header_cell(Column, [Pdf.text("Meaning")]),
			Pdf.header_cell(Column, [Pdf.text("Response")]),
			Pdf.header_cell(Column, [Pdf.text("Example")]),
		]),
	],
	body_rows: [
		severity_row("SEV1", "Customers cannot pay, or money is at risk.", "Page now; bridge in 5 min; updates every 15 min.", "Card authorisations failing in every region."),
		severity_row("SEV2", "A major feature is degraded for many customers.", "Page now; updates every 30 min.", "Refunds delayed by more than an hour."),
		severity_row("SEV3", "Minor impact with a workaround.", "Next business day.", "One acquirer returns slow responses."),
		severity_row("SEV4", "No customer impact yet.", "Ticket in the team queue.", "A certificate expires in 21 days."),
	],
	footer_rows: [],
	row_split: KeepRows,
})

contact_row : Str, Str, Str, Str -> Pdf.Row
contact_row = |after, role, who, channel| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(after)]),
	Pdf.cell([Pdf.strong([Pdf.text(role)])]),
	Pdf.cell([Pdf.text(who)]),
	Pdf.cell([Pdf.code(channel)]),
])

escalation_table : Document.Block
escalation_table = Pdf.table({
	caption: Pdf.caption("Table 2. Escalation path for SEV1 and SEV2 incidents"),
	columns: [
		{ width: Fixed(points(64)), align: Start },
		{ width: Share(3), align: Start },
		{ width: Share(3), align: Start },
		{ width: Share(3), align: Start },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("After")]),
			Pdf.header_cell(Column, [Pdf.text("Escalate to")]),
			Pdf.header_cell(Column, [Pdf.text("Who")]),
			Pdf.header_cell(Column, [Pdf.text("Channel")]),
		]),
	],
	body_rows: [
		contact_row("0 min", "Primary on-call", "Payments rota (PagerDuty)", "#inc-payments"),
		contact_row("10 min", "Secondary on-call", "Payments rota, backup", "page: pay-secondary"),
		contact_row("20 min", "Incident commander", "Duty engineering manager", "page: ic-duty"),
		contact_row("30 min", "Database specialist", "Data platform rota", "page: dba-oncall"),
		contact_row("45 min", "Head of Payments", "Priya Raman", "+61 3 9000 4417"),
		contact_row("60 min", "Customer comms lead", "Support duty manager", "#status-updates"),
	],
	footer_rows: [
		Pdf.row([
			Pdf.spanning(4, Pdf.aligned(Start, Pdf.cell([Pdf.emphasis([Pdf.text("Escalate earlier whenever you are unsure. Nobody is ever blamed for paging.")])]))),
		]),
	],
	row_split: KeepRows,
})

## A procedure never drilled leaves its last-drill cell empty.
drill_row : Str, Str, Str, Str -> Pdf.Row
drill_row = |procedure, owner, last, next| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(procedure)]),
	Pdf.cell([Pdf.text(owner)]),
	if last.is_empty() Pdf.cell([]) else Pdf.cell([Pdf.text(last)]),
	Pdf.cell([Pdf.text(next)]),
])

drill_table : Document.Block
drill_table = Pdf.table({
	caption: Pdf.caption("Table 4. Drill schedule"),
	columns: [
		{ width: Share(4), align: Start },
		{ width: Share(3), align: Start },
		{ width: Fixed(points(78)), align: Start },
		{ width: Fixed(points(78)), align: Start },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Procedure")]),
			Pdf.header_cell(Column, [Pdf.text("Owner")]),
			Pdf.header_cell(Column, [Pdf.text("Last drill")]),
			Pdf.header_cell(Column, [Pdf.text("Next drill")]),
		]),
	],
	body_rows: [
		drill_row("4.1 Triage", "Payments Reliability", "12 Aug 2026", "11 Nov 2026"),
		drill_row("4.2 Rolling back a release", "Release engineering", "2 Sep 2026", "2 Dec 2026"),
		drill_row("4.3 Database failover", "Data platform", "", "14 Oct 2026"),
		drill_row("5 Escalation", "Duty engineering managers", "19 Aug 2026", "18 Nov 2026"),
	],
	footer_rows: [],
	row_split: KeepRows,
})

command_row : Str, Str, Str -> Pdf.Row
command_row = |command, purpose, changes| Pdf.row([
	Pdf.header_cell(Row, [Pdf.code(command)]),
	Pdf.cell([Pdf.text(purpose)]),
	Pdf.cell([Pdf.text(changes)]),
])

command_table : Document.Block
command_table = Pdf.table({
	caption: Pdf.caption("Table 3. Commands used in this runbook"),
	columns: [
		{ width: Content, align: Start },
		{ width: Share(1), align: Start },
		{ width: Fixed(points(48)), align: Center },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Command")]),
			Pdf.header_cell(Column, [Pdf.text("Purpose")]),
			Pdf.header_cell(Column, [Pdf.text("Writes")]),
		]),
	],
	body_rows: [
		command_row("/incident open payments", "Open an incident channel and start the timeline.", "Yes"),
		command_row("kubectl get pods -l tier=api", "List API pods with their node and restart count.", "No"),
		command_row("kubectl logs deploy/payments-api", "Stream recent API logs.", "No"),
		command_row("payctl acquirer status", "Show authorisation rate per acquirer.", "No"),
		command_row("payctl acquirer disable NAME", "Stop routing to a failing acquirer.", "Yes"),
		command_row("payctl freeze --reason INC", "Block all deploys to the payments namespace.", "Yes"),
		command_row("payctl migrations --pending", "List ledger migrations applied since the last release.", "No"),
		command_row("kubectl rollout undo", "Return a deployment to an earlier revision.", "Yes"),
		command_row("ledgerctl replicas --lag", "Show replication lag for each ledger replica.", "No"),
		command_row("ledgerctl promote --replica", "Promote a replica to ledger primary.", "Yes"),
	],
	footer_rows: [],
	row_split: KeepRows,
})

## ---------------------------------------------------------------------

step : Str -> Pdf.ListItem
step = |text| Pdf.list_item([Pdf.paragraph(text)])

rich_step : List(Pdf.Inline) -> Pdf.ListItem
rich_step = |inlines| Pdf.list_item([Pdf.rich_paragraph(inlines)])

accent_band : Document.Block
accent_band = Pdf.decoration({
	drawing: Scene.rectangle(
		Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 10, 56, 6), teal), Layout.rect(60, 10, 18, 6), rust),
		{ origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(600), width: points(measure) } },
		mist,
	),
})

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| Ok([
	accent_band,
	Pdf.title("Payments platform on-call runbook"),
	Pdf.rich_paragraph([
		Pdf.emphasis([Pdf.text("Runbook PAY-OPS-004, revision 4.2 · Owner: Payments Reliability · Reviewed 30 September 2026")]),
	]),
	callout(
		options,
		"At a glance",
		note_style,
		[
			labelled("Bridge", [Pdf.text("Join "), Pdf.code("#inc-payments"), Pdf.text(" and the standing video bridge before anything else.")]),
			labelled("Dashboards", [Pdf.inline_link([Pdf.text("grafana.example/d/payments-overview")], "https://grafana.example/d/payments-overview")]),
			labelled("Status page", [Pdf.text("Customer updates go out through the support duty manager only.")]),
		],
	)?,
	Pdf.section([
		Pdf.destination_heading("scope", 1, "1 Scope and on-call duties"),
		Pdf.rich_paragraph([
			Pdf.text("This runbook covers the card, wallet, and bank-transfer paths of the payments platform in both production regions. It tells the on-call engineer "),
			Pdf.strong([Pdf.text("what to check, in what order, and when to escalate")]),
			Pdf.text(". It does not replace judgement: if a step makes things worse, stop and escalate using "),
			Pdf.inline_internal_link([Pdf.text("section 5")], "escalation"),
			Pdf.text("."),
		]),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.paragraph("Acknowledge every page within five minutes, day or night.")]),
			Pdf.list_item([
				Pdf.rich_paragraph([Pdf.text("Keep a laptop with a working "), Pdf.expansion("VPN", "virtual private network"), Pdf.text(" and hardware key within reach.")]),
			]),
			Pdf.list_item([
				Pdf.paragraph("Hand over at 09:00 local time with a written summary:"),
				Pdf.bullet_list([
					Pdf.list_item([Pdf.paragraph("open incidents and their current severity;")]),
					Pdf.list_item([Pdf.paragraph("changes frozen, rolled back, or still in flight.")]),
				]),
			]),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("topology", 1, "2 Service topology"),
		Pdf.paragraph("Every payment enters through the edge, is authorised by the payments API, and is written to the ledger before any acquirer is told to capture funds. Figure 1 shows the tiers you will meet during an incident."),
		Pdf.figure({ drawing: topology, alt: "Diagram of the payments request path. Traffic flows left to right from the edge load balancer (1) through the API gateway (2) and payments API (3) to the acquirer adapters (4). The payments API writes to the ledger database (5), and the adapters publish to the settlement queue (6), which the settlement worker (7) consumes before reconciling against the ledger.", caption: Pdf.caption("Figure 1. Request path through the production zone (shaded)") }),
		Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				rich_step([Pdf.strong([Pdf.text("Edge load balancer")]), Pdf.text(" terminates TLS and applies rate limits.")]),
				rich_step([Pdf.strong([Pdf.text("API gateway")]), Pdf.text(" authenticates merchants and routes by region.")]),
				rich_step([Pdf.strong([Pdf.text("Payments API")]), Pdf.text(" validates, deduplicates, and authorises each payment.")]),
				rich_step([Pdf.strong([Pdf.text("Acquirer adapters")]), Pdf.text(" speak each bank's protocol and own the retries.")]),
				rich_step([Pdf.strong([Pdf.text("Ledger database")]), Pdf.text(" is the system of record; a primary with two replicas.")]),
				rich_step([Pdf.strong([Pdf.text("Settlement queue")]), Pdf.text(" buffers captures for the nightly settlement run.")]),
				rich_step([Pdf.strong([Pdf.text("Settlement worker")]), Pdf.text(" drains the queue and reconciles against the ledger.")]),
			],
		),
	]),
	Pdf.section([
		Pdf.destination_heading("severity", 1, "3 Severity levels"),
		Pdf.paragraph("Declare the severity as soon as the impact is understood, and change it as soon as the impact changes. Response targets run from the moment the page fires, not from acknowledgement."),
		severity_table,
	]),
	Pdf.section([
		Pdf.destination_heading("response", 1, "4 Incident response procedure"),
		Pdf.paragraph("Work through the steps in order. Record every action, with the time, in the incident channel as you take it: the timeline is written from those messages."),
		Pdf.section([
			Pdf.destination_heading("triage", 2, "4.1 Triage"),
			Pdf.numbered_list(
				{ start: 1, style: Decimal },
				[
					rich_step([Pdf.text("Acknowledge the page and open the incident with "), Pdf.code("/incident open payments"), Pdf.text(".")]),
					step("Check the overview dashboard for the three golden signals: authorisation rate, p99 latency, and error rate."),
					Pdf.list_item([
						Pdf.paragraph("Decide whether the fault is ours or upstream:"),
						Pdf.numbered_list(
							{ start: 1, style: LowerAlpha },
							[
								step("if one acquirer is failing, disable it and let routing fail over;"),
								step("if every acquirer is failing, suspect the payments API or the ledger;"),
								step("if only one region is failing, drain it at the edge."),
							],
						),
					]),
					rich_step([Pdf.text("Declare the severity using "), Pdf.inline_internal_link([Pdf.text("Table 1")], "severity"), Pdf.text(" and page the next level if the target is at risk.")]),
				],
			),
			console(
				options,
				[
					"$ kubectl -n payments get pods -l tier=api -o wide",
					"$ kubectl -n payments logs deploy/payments-api --since=15m",
					"$ payctl acquirer status --region ap-southeast-2",
				],
			)?,
		]),
		Pdf.section([
			Pdf.destination_heading("rollback", 2, "4.2 Rolling back a release"),
			Pdf.rich_paragraph([
				Pdf.text("Most incidents start within an hour of a deploy. If the timing fits, "),
				Pdf.strong([Pdf.text("roll back first and investigate afterwards")]),
				Pdf.text("."),
			]),
			Pdf.numbered_list(
				{ start: 1, style: Decimal },
				[
					rich_step([Pdf.text("Freeze deploys with "), Pdf.code("payctl freeze --reason INC"), Pdf.text(".")]),
					rich_step([Pdf.text("Find the last good revision with "), Pdf.code("kubectl rollout history"), Pdf.text(".")]),
					rich_step([Pdf.text("Roll back with "), Pdf.code("kubectl rollout undo --to-revision=N"), Pdf.text(" and watch the pods restart.")]),
					step("Confirm the authorisation rate has recovered for ten minutes before you lift the freeze."),
				],
			),
			callout(
				options,
				"Warning",
				warning_style,
				[
					labelled("Warning", [Pdf.text("Never roll back across a ledger schema migration.")]),
					Pdf.rich_paragraph([Pdf.text("Check "), Pdf.code("payctl migrations --pending"), Pdf.text(" first. If a migration ran, escalate to the database specialist.")]),
				],
			)?,
		]),
		Pdf.section([
			Pdf.destination_heading("failover", 2, "4.3 Database failover"),
			Pdf.paragraph("Fail the ledger over only when the primary is unreachable for more than two minutes and the incident commander agrees. Failover is automatic in most cases; these steps are for when it is not."),
			Pdf.numbered_list(
				{ start: 1, style: Decimal },
				[
					step("Confirm replication lag on both replicas is below one second."),
					rich_step([Pdf.text("Promote the healthier replica with "), Pdf.code("ledgerctl promote --replica"), Pdf.text(".")]),
					step("Repoint the payments API by restarting it; it resolves the primary at start-up."),
					step("Fence the old primary so it cannot accept writes if it returns."),
				],
			),
			console(
				options,
				[
					"$ ledgerctl replicas --lag",
					"$ ledgerctl promote --replica ledger-2 --confirm",
					"$ kubectl -n payments rollout restart deploy/payments-api",
				],
			)?,
			callout(
				options,
				"Note",
				note_style,
				[
					labelled("Note", [Pdf.text("A failover loses no committed payment: writes are synchronous to one replica.")]),
				],
			)?,
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("escalation", 1, "5 Escalation"),
		Pdf.paragraph("Escalate on the clock, not on a feeling. If an incident is still open at the time shown, page the next role even if you believe a fix is close."),
		escalation_table,
	]),
	Pdf.section([
		Pdf.destination_heading("review", 1, "6 After the incident"),
		Pdf.paragraph("Close the incident only when the metrics have been healthy for thirty minutes. Within two business days:"),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.paragraph("write the timeline from the incident channel;")]),
			Pdf.list_item([Pdf.paragraph("hold a blameless review with everyone who was paged;")]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("file follow-up actions against the "), Pdf.code("PAY-REL"), Pdf.text(" board with an owner and a date;")])]),
			Pdf.list_item([Pdf.paragraph("update this runbook if any step was wrong, missing, or slow.")]),
		]),
		Pdf.rich_paragraph([Pdf.text("Suggest changes to this runbook in "), Pdf.code("#payments-reliability"), Pdf.text(".")]),
	]),
	Pdf.section([
		Pdf.destination_heading("commands", 1, "Appendix A. Command reference"),
		Pdf.keep_with_next(Required, Pdf.paragraph("Every command below is read-only unless it is marked as a write. Run writes only while the incident is open and announced in the channel.")),
		command_table,
	]),
	Pdf.section([
		Pdf.destination_heading("drills", 1, "Appendix B. Procedure drills"),
		Pdf.paragraph("Each procedure is rehearsed in the staging region on the schedule below. A procedure with no drill date has not been rehearsed since it was added; run it with its owner before you rely on it."),
		drill_table,
	]),
])
