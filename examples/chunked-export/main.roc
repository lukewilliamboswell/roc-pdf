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
import "fonts/SourceCodePro-Regular.ttf" as regular_bytes : List(U8)
import "fonts/SourceCodePro-Bold.ttf" as bold_bytes : List(U8)

## A cold-chain telemetry export for one refrigerated shipment, emitted
## incrementally. The document is prepared once, then drained chunk by
## chunk from `Pdf.to_chunks_prepared`; the chunks concatenate to exactly
## the bytes `Pdf.to_bytes_prepared` would return. The export itself has
## a summary callout measured by the package, a generated temperature
## chart with its safe band, and a 48-row readings table with zebra rows
## and shaded excursions that continues across pages with its header
## repeated and a summary footer, under a running header inset above its
## rule.
main! = |_args| {
	fonts = register_fonts({})?
	options = Pdf.Options.default.with_theme(with_faces(theme, fonts)).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-AU", title: "Cold-chain telemetry export, shipment RX-40718" })
		.with_page_templates(templates)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	prepared = Pdf.prepare(document, options).map_err(|err| PdfFailed(err))?
	encoder = Pdf.to_chunks_prepared(prepared, ShareUnchangedResources).map_err(|err| EmitFailed(err))?
	collected = collect(encoder)
	output : Path
	output = "chunked-export.pdf"
	output.write_bytes!(collected.bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote chunked-export.pdf from ${collected.chunks.to_str()} chunks (${collected.bytes.len().to_str()} bytes)").map_err(|err| OutputFailed(err))?
	Ok({})
}

## Drain the encoder, appending each chunk's bytes to one uniquely owned
## buffer and counting the chunks.
collect : Pdf.Encode -> { bytes : List(U8), chunks : U64 }
collect = |encoder| {
	var $bytes = []
	var $chunks = 0
	var $encoder = encoder
	var $running = True
	while $running {
		match Pdf.next_chunk($encoder) {
			Done => {
				$running = False
			}
			Emit(chunk, next) => {
				for byte in chunk {
					$bytes = $bytes.append(byte)
				}
				$chunks = $chunks + 1
				$encoder = next
			}
		}
	}
	{ bytes: $bytes, chunks: $chunks }
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, registry : Font.Registry }

## Source Code Pro Regular and Bold, each retained
## byte-for-byte from its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin = [Font.Script.from_iso15924("Latn")]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	Ok({ regular: regular.face, bold: bold.face, registry: bold.registry })
}

## Regular for body text; Bold for the title, headings, and `Pdf.strong`.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	heading = Theme.heading_style(base)
	title = Theme.title_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_style({ ..heading, font: faces.bold })
		.with_inline_font(Strong, faces.bold)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

## ---------------------------------------------------------------------
## Palette and theme. A4 with 50 pt margins: a 495 pt measure.

spruce : Color.SourceValue
spruce = Color.srgb8({ red: 21, green: 94, blue: 117 })

slate : Color.SourceValue
slate = Color.srgb8({ red: 51, green: 65, blue: 85 })

frost : Color.SourceValue
frost = Color.srgb8({ red: 203, green: 213, blue: 225 })

alarm : Color.SourceValue
alarm = Color.srgb8({ red: 200, green: 30, blue: 30 })

measure : I64
measure = 495

theme : Theme
theme = {
	body = Theme.body_style(Theme.default)
	heading = Theme.heading_style(Theme.default)
	title = Theme.title_style(Theme.default)
	Theme.default
		.with_body_style({ ..body, color: slate, size: points(9), leading: points(13) })
		.with_heading_style({ ..heading, color: spruce, size: points(13), leading: points(18) })
		.with_title_style({ ..title, color: slate, size: points(22), leading: points(27) })
		.with_page_margin({ top: points(44), right: points(50), bottom: points(40), left: points(50) })
		.with_paragraph_spacing(points(6))
		.with_bullet_indent(points(16))
		.with_strong_color(alarm)
		.with_emphasis_color(spruce)
		.with_code_color(spruce)
		.with_table_header_color(spruce)
		.with_table_header_fill(Color.srgb8({ red: 226, green: 238, blue: 242 }))
		.with_table_body_fills({ odd: NoFill, even: Fill(Color.srgb8({ red: 246, green: 248, blue: 250 })) })
		.with_table_footer_fill(Color.srgb8({ red: 236, green: 241, blue: 245 }))
		.with_table_cell_padding(points(3))
		.with_table_row_gap(points(2))
		.with_table_rule(Rule({ color: frost, width: Layout.Unit.millipoints(500) }))
}

## ---------------------------------------------------------------------
## Running furniture.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(14),
	start: [Pdf.furniture_text([Pdf.text("Exported 30 September 2026 06:00 AEST · Logger CL-7 serial 00418")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({ header: Pdf.no_region, lead: Pdf.no_lead, footer, gap: points(12) }),
	continuation: Pdf.page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(17),
					start: [Pdf.furniture_text([Pdf.text("Shipment RX-40718 · Melbourne to Hobart · Telemetry export")])],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("Vaccines, 2 to 8 °C")])],
				}),
				Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(500), width: points(measure) } }, frost),
			),
			points(3),
		),
		footer,
		gap: points(12),
	}),
}

## ---------------------------------------------------------------------
## The readings: 48 half-hourly samples from 06:00, in tenths of a degree
## Celsius. A loading-dock delay at 20:00 briefly lifts both probes above
## the 8.0 °C limit.

probe_a : U64 -> U64
probe_a = |slot| match slot {
	28 => 64
	29 => 86
	30 => 91
	31 => 84
	32 => 56
	_ => 36 + (slot * 37) % 11
}

probe_b : U64 -> U64
probe_b = |slot| match slot {
	28 => 58
	29 => 79
	30 => 84
	31 => 69
	32 => 52
	_ => 34 + (slot * 13) % 9
}

humidity : U64 -> U64
humidity = |slot| 82 + (slot * 7) % 9

tenths : U64 -> Str
tenths = |value| "${(value // 10).to_str()}.${(value % 10).to_str()}"

clock : U64 -> Str
clock = |slot| {
	minutes = 360 + slot * 30
	hour = (minutes // 60) % 24
	minute = minutes % 60
	pad = |n| if n < 10 "0${n.to_str()}" else n.to_str()
	"${pad(hour)}:${pad(minute)}"
}

limit : U64
limit = 80

reading_row : U64 -> Pdf.Row
reading_row = |slot| {
	a = probe_a(slot)
	b = probe_b(slot)
	over = a > limit or b > limit
	value = |v| if v > limit Pdf.strong([Pdf.text(tenths(v))]) else Pdf.text(tenths(v))
	Pdf.row([
		Pdf.header_cell(Row, [Pdf.text(clock(slot))]),
		Pdf.cell([value(a)]),
		Pdf.cell([value(b)]),
		Pdf.cell([Pdf.text(humidity(slot).to_str())]),
		Pdf.cell([Pdf.text(if slot >= 28 and slot <= 30 "Open" else "Closed")]),
		if over Pdf.shaded(Color.srgb8({ red: 254, green: 226, blue: 226 }), Pdf.cell([Pdf.strong([Pdf.text("Excursion")])])) else Pdf.cell([Pdf.text("In range")]),
	])
}

readings_table : Document.Block
readings_table = {
	var $rows = List.with_capacity(48)
	var $slot = 0
	while $slot < 48 {
		$rows = $rows.append(reading_row($slot))
		$slot = $slot + 1
	}
	Pdf.table({
		caption: Pdf.caption("Table 1. Half-hourly readings, 06:00 29 September to 05:30 30 September"),
		columns: [
			{ width: Fixed(points(56)), align: Start },
			{ width: Share(1), align: End },
			{ width: Share(1), align: End },
			{ width: Share(1), align: End },
			{ width: Share(1), align: Center },
			{ width: Share(1), align: Start },
		],
		header_rows: [
			Pdf.row([
				Pdf.header_cell(Column, [Pdf.text("Time")]),
				Pdf.header_cell(Column, [Pdf.text("Probe A (°C)")]),
				Pdf.header_cell(Column, [Pdf.text("Probe B (°C)")]),
				Pdf.header_cell(Column, [Pdf.text("Humidity (%)")]),
				Pdf.header_cell(Column, [Pdf.text("Door")]),
				Pdf.header_cell(Column, [Pdf.text("Status")]),
			]),
		],
		body_rows: $rows,
		footer_rows: [
			Pdf.row([
				Pdf.header_cell(Row, [Pdf.text("Minimum")]),
				Pdf.cell([Pdf.text("3.6")]),
				Pdf.cell([Pdf.text("3.4")]),
				Pdf.cell([Pdf.text("82")]),
				Pdf.spanning(2, Pdf.cell([Pdf.text("Door open 90 min")])),
			]),
			Pdf.row([
				Pdf.header_cell(Row, [Pdf.text("Maximum")]),
				Pdf.cell([Pdf.strong([Pdf.text("9.1")])]),
				Pdf.cell([Pdf.strong([Pdf.text("8.4")])]),
				Pdf.cell([Pdf.text("90")]),
				Pdf.spanning(2, Pdf.cell([Pdf.text("3 samples over limit")])),
			]),
		],
		row_split: KeepRows,
	})
}

## ---------------------------------------------------------------------
## Figure 1: both probes over 24 hours against the 2 to 8 °C safe band.
## Twenty points per degree from a baseline at y = 24; nine points per
## half-hour slot from x = 40, leaving a column for the axis labels.

plot_y : U64 -> I64
plot_y = |value| 24 + value.to_i64_wrap() * 2

plot_x : U64 -> I64
plot_x = |slot| 40 + slot.to_i64_wrap() * 9

series : (U64 -> U64) -> Scene.AuthorPath
series = |probe| {
	var $path = Scene.path({}).move_to(Layout.point(plot_x(0), plot_y(probe(0))))
	var $slot = 1
	while $slot < 48 {
		$path = $path.line_to(Layout.point(plot_x($slot), plot_y(probe($slot))))
		$slot = $slot + 1
	}
	$path.finish()
}

## A legend entry: a short line in the series colour and its name.
legend : Scene.Drawing, I64, I64, Color.SourceValue, Layout.Unit, Str -> Scene.Drawing
legend = |drawing, x, y, color, width, name|
	drawing
		.path(Scene.path({}).move_to(Layout.point(x, y + 3)).line_to(Layout.point(x + 16, y + 3)).finish(), Scene.solid_stroke(color, width))
		.text({ align: Start, color: slate, origin: Layout.point(x + 21, y), size: points(7), text: name })

temperature_chart : Scene.Drawing
temperature_chart = {
	band = Color.srgb8({ red: 226, green: 244, blue: 236 })
	grid = Color.srgb8({ red: 226, green: 232, blue: 240 })
	light = Color.srgb8({ red: 125, green: 180, blue: 200 })
	right = plot_x(48)

	## The safe band (2.0 to 8.0 °C), labelled gridlines every 2 °C, and
	## hour ticks labelled every 6 hours.
	var $d = Scene.rectangle(Scene.drawing({}), Layout.rect(plot_x(0), plot_y(20), right - plot_x(0), plot_y(80) - plot_y(20)), band)
	for degrees in [0, 2, 4, 6, 8] {
		$d = Scene.rectangle($d, { origin: Layout.point(plot_x(0), plot_y(degrees * 10)), size: { height: Layout.Unit.millipoints(500), width: points(right - plot_x(0)) } }, grid)
		$d = $d.text({ align: End, color: slate, origin: Layout.point(plot_x(0) - 5, plot_y(degrees * 10) - 2), size: points(7), text: "${degrees.to_str()} °C" })
	}
	var $tick = 0
	while $tick <= 48 {
		major = $tick % 12 == 0
		$d = Scene.rectangle($d, { origin: Layout.point(plot_x($tick), if major 16 else 20), size: { height: points(if major 8 else 4), width: Layout.Unit.millipoints(600) } }, slate)
		if major {
			## The last label ends at the axis end so it stays in the chart.
			$d = $d.text({ align: if $tick == 48 End else Center, color: slate, origin: Layout.point(plot_x($tick), 5), size: points(7), text: clock($tick) })
		}
		$tick = $tick + 4
	}

	## The 8.0 °C limit as a solid alarm line, and the excursion window.
	$d = Scene.rectangle($d, { origin: Layout.point(plot_x(0), plot_y(80)), size: { height: Layout.Unit.millipoints(1200), width: points(right - plot_x(0)) } }, alarm)
	$d = Scene.rectangle($d, Layout.rect(plot_x(28), plot_y(80), plot_x(32) - plot_x(28), plot_y(95) - plot_y(80)), Color.srgb8({ red: 254, green: 226, blue: 226 }))
	$d = $d.text({ align: End, color: alarm, origin: Layout.point(right, plot_y(80) + 4), size: points(7), text: "8.0 °C limit" })
	$d = $d.text_in(Strong, { align: Center, color: alarm, origin: Layout.point((plot_x(28) + plot_x(32)) // 2, plot_y(95) + 4), size: points(7), text: "Excursion" })
	$d = legend($d, plot_x(0), plot_y(100), spruce, points(2), "Probe A")
	$d = legend($d, plot_x(0) + 76, plot_y(100), light, Layout.Unit.millipoints(1500), "Probe B")
	$d
		.path(series(probe_b), Scene.solid_stroke(light, Layout.Unit.millipoints(1500)))
		.path(series(probe_a), Scene.solid_stroke(spruce, points(2)))
		.path(Scene.path({}).move_to(Layout.point(plot_x(0), 24)).line_to(Layout.point(right, 24)).finish(), Scene.solid_stroke(slate, Layout.Unit.millipoints(800)))
}

## ---------------------------------------------------------------------
## The summary callout: the custom-block pattern of
## tests/custom_block/Callout.roc, measured by the package at the panel's
## content width under the options the export is prepared with.

callout_inset : Layout.Unit
callout_inset = points(12)

summary : Pdf.Options, List(Document.Block) -> Try(Document.Block, Pdf.Error)
summary = |options, paragraphs| {
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-AU", width: points(measure - 24) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(measure) }
	panel = Scene.drawing({})
		.path(Scene.path({}).rectangle({ origin: Layout.point(0, 0), size }).finish(), Scene.solid_fill(Color.srgb8({ red: 240, green: 247, blue: 250 })))
	Ok(
		Pdf.custom_block({
			contents: paragraphs,
			fragmentation: Unsplittable,
			inset: callout_inset,
			name: "Shipment summary",
			panel: Scene.rectangle(panel, { origin: Layout.point(0, 0), size: { height: size.height, width: points(3) } }, spruce),
			size,
		}),
	)
}

fact : Str, Str -> Document.Block
fact = |label, value| Pdf.rich_paragraph([Pdf.emphasis([Pdf.text(label)]), Pdf.text("  ${value}")])

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| {
	shipment = summary(
		options,
		[
			fact("Status", "Delivered 30 September 05:40 · 1 excursion, about 90 min above 8.0 °C"),
			fact("Probe A", "min 3.6 °C · max 9.1 °C · mean 4.4 °C"),
			fact("Probe B", "min 3.4 °C · max 8.4 °C · mean 4.1 °C"),
			fact("Assessment", "Within the manufacturer's stability budget; quarantine not required"),
		],
	)?
	Ok(body(shipment))
}

body : Document.Block -> List(Document.Block)
body = |shipment| [
	Pdf.spaced_decoration(Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 120, 4), spruce), Layout.rect(124, 0, 24, 4), alarm), { above: points(0), behind: Bool.False, below: points(6) }),
	Pdf.title("Cold-chain telemetry export"),
	Pdf.rich_paragraph([
		Pdf.text("Shipment "),
		Pdf.code("RX-40718"),
		Pdf.text(" · Vaccines, 2 to 8 °C · Melbourne distribution centre to Royal Hobart Hospital pharmacy"),
	]),
	shipment,
	Pdf.section([
		Pdf.heading(1, "Temperature over the journey"),
		Pdf.rich_paragraph([
			Pdf.text("Both probes stayed inside the safe band except during the loading-dock delay at Devonport, when the door was held open for 90 minutes. The logger raised alarm "),
			Pdf.code("TEMP_HIGH"),
			Pdf.text(" at 20:30 and cleared it at 22:00."),
		]),
		Pdf.figure(
			temperature_chart,
			"Line chart of probe temperatures over 24 hours from 06:00. Both probes hold between 3.4 and 4.6 °C, inside the 2 to 8 °C safe band, except from 20:30 to 21:30, when probe A peaks at 9.1 °C and probe B at 8.4 °C before returning to the band by 22:00.",
			Pdf.caption("Figure 1. Probe A and probe B against the 2 to 8 °C band; ticks every 2 hours from 06:00"),
		),
	]),
	Pdf.section([
		Pdf.heading(1, "Excursion record"),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("20:00")]), Pdf.text(" trailer door opened for transfer to the Bass Strait ferry.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("21:00")]), Pdf.text(" peak of 9.1 °C at probe A, nearest the door.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("22:00")]), Pdf.text(" both probes back below 8.0 °C; alarm cleared.")])]),
		]),
	]),
	Pdf.section([
		Pdf.heading(1, "Readings"),
		Pdf.paragraph("Readings in red exceed the 8.0 °C limit. The logger samples every minute; the table shows the half-hourly values the carrier reports."),
		readings_table,
	]),
]
