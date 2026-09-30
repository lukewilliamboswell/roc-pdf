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
import "fonts/PublicSans-Regular.ttf" as regular_bytes : List(U8)
import "fonts/PublicSans-Bold.ttf" as bold_bytes : List(U8)
import "fonts/PublicSans-Italic.ttf" as italic_bytes : List(U8)
import "fonts/SourceCodePro-Regular.ttf" as mono_bytes : List(U8)

## Lumen brand guidelines: a branded multi-page brief set in Public Sans with a
## monospace face for colour and token codes. It shows running headers and
## footers with `Page N of M`, their header text inset above full-width
## header rules, a palette strip
## and section bands as spaced decorations, separately authored "At a
## glance" callouts measured by the package (one light, one on an indigo
## panel), vector
## figures built from grouped drawings (colour swatches with tints and
## logo placements), tables with shaded headers and group rows, rich inline content,
## lists, links, and an outline over named section destinations.
main! = |_args| {
	fonts = register_fonts({})?
	theme = with_faces(base_theme, fonts)
	options = Pdf.Options.default.with_theme(theme).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en", title: "Lumen brand guidelines, edition 3" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "brand-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote brand-brief.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, italic : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }

## Public Sans Regular, Bold, and Italic, and Source Code Pro Regular, each retained
## byte-for-byte from its upstream release in `fonts/` beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin = [Font.Script.from_iso15924("Latn")]
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

## ---------------------------------------------------------------------
## The palette.

Rgb : { blue : U8, green : U8, red : U8 }

indigo_rgb : Rgb
indigo_rgb = { red: 43, green: 45, blue: 110 }

coral_rgb : Rgb
coral_rgb = { red: 242, green: 102, blue: 90 }

amber_rgb : Rgb
amber_rgb = { red: 245, green: 184, blue: 61 }

teal_rgb : Rgb
teal_rgb = { red: 22, green: 120, blue: 114 }

ink_rgb : Rgb
ink_rgb = { red: 30, green: 34, blue: 48 }

indigo : Color.SourceValue
indigo = Color.srgb8(indigo_rgb)

coral : Color.SourceValue
coral = Color.srgb8(coral_rgb)

amber : Color.SourceValue
amber = Color.srgb8(amber_rgb)

ink : Color.SourceValue
ink = Color.srgb8(ink_rgb)

mist : Color.SourceValue
mist = Color.srgb8({ red: 238, green: 240, blue: 248 })

white : Color.SourceValue
white = Color.srgb8({ red: 255, green: 255, blue: 255 })

## `color` mixed toward white by `percent`.
tint : Rgb, U64 -> Color.SourceValue
tint = |rgb, percent| {
	mix = |channel| {
		value = channel.to_u64()
		(value + (255 - value) * percent // 100).to_u8_wrap()
	}
	Color.srgb8({ red: mix(rgb.red), green: mix(rgb.green), blue: mix(rgb.blue) })
}

## A4 with 56 pt sides: a 483 pt measure.
base_theme : Theme
base_theme = {
	body = Theme.body_style(Theme.default)
	heading = Theme.heading_style(Theme.default)
	title = Theme.title_style(Theme.default)
	Theme.default
		.with_body_style({ ..body, color: ink, size: Layout.Unit.from_raw(10500), leading: Layout.Unit.from_raw(15500) })
		.with_heading_style({ ..heading, color: indigo, size: points(16), leading: points(22) })
		.with_title_style({ ..title, color: indigo, size: points(34), leading: points(40) })
		.with_page_margin({ top: points(40), right: points(56), bottom: points(40), left: points(56) })
		.with_paragraph_spacing(points(9))
		.with_bullet_indent(points(16))
		.with_code_color(Color.srgb8({ red: 170, green: 58, blue: 48 }))
		.with_table_header_color(indigo)
		.with_table_header_fill(mist)
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(5))
		.with_table_rule(Rule({ color: indigo, width: Layout.Unit.millipoints(750) }))
		.with_table_body_rule(Rule({ color: tint(indigo_rgb, 82), width: Layout.Unit.millipoints(400) }))
		.with_link_color(indigo)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1500), thickness: Layout.Unit.millipoints(600) }))
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

## The Lumen mark in a `size` square: a disc, a smaller light disc rising
## from its upper right, and a horizon bar.
mark : I64, Color.SourceValue, Color.SourceValue -> Scene.Drawing
mark = |size, disc, light| {
	half = size // 2
	Scene.drawing({})
		.path(circle(half, half, half), Scene.solid_fill(disc))
		.path(circle(size * 64 // 100, size * 64 // 100, size * 18 // 100), Scene.solid_fill(light))
		.path(Scene.path({}).rectangle(Layout.rect(size * 18 // 100, size * 30 // 100, size * 64 // 100, size * 6 // 100)).finish(), Scene.solid_fill(light))
}

## A 483 × 8 pt strip of the five palette colours, kept 12 pt above the
## next block by its decoration spacing.
palette_strip : Scene.Drawing
palette_strip = {
	widths = [(indigo, 193), (teal_source, 97), (coral, 97), (amber, 48), (ink, 48)]
	var $drawing = Scene.drawing({})
	var $x = 0
	for (color, width) in widths {
		$drawing = Scene.rectangle($drawing, Layout.rect($x, 0, width, 8), color)
		$x = $x + width
	}
	$drawing
}

teal_source : Color.SourceValue
teal_source = Color.srgb8(teal_rgb)

## A section band: a short coral bar over a hairline across the measure,
## with 6 pt above it and 6 pt between it and the heading it introduces.
band : Document.Block
band = Pdf.spaced_decoration(
	Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 2, 483, 1), tint(indigo_rgb, 80)), Layout.rect(0, 0, 36, 5), coral),
	{ above: points(6), behind: False, below: points(6) },
)

## One swatch card: the solid colour, named in bold with its hex value in
## the code face, above three tints (75, 50, 25 percent toward white).
swatch : Rgb, Str, Str, Color.SourceValue -> Scene.Drawing
swatch = |rgb, name, hex, label| {
	solid = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 39, 88, 52), Color.srgb8(rgb))
		.text_in(Strong, { align: Start, color: label, origin: Layout.point(6, 77), size: points(8), text: name })
		.text_in(Code, { align: Start, color: label, origin: Layout.point(6, 45), size: points(7), text: hex })
	light = Scene.rectangle(Scene.rectangle(solid, Layout.rect(0, 26, 88, 12), tint(rgb, 25)), Layout.rect(0, 13, 88, 12), tint(rgb, 50))
	Scene.rectangle(light, Layout.rect(0, 0, 88, 12), tint(rgb, 75))
}

swatches : Scene.Drawing
swatches = {
	var $drawing = Scene.drawing({})
	var $x = 0
	for (rgb, name, hex, label) in [(indigo_rgb, "Lumen Indigo", "#2B2D6E", white), (teal_rgb, "Harbour Teal", "#167872", white), (coral_rgb, "Signal Coral", "#F2665A", ink), (amber_rgb, "Dawn Amber", "#F5B83D", ink), (ink_rgb, "Ink", "#1E2230", white)] {
		$drawing = $drawing.group(Layout.point($x, 0), swatch(rgb, name, hex, label))
		$x = $x + 98
	}
	$drawing
}

## The mark on three approved grounds, each named, with its clear space
## outlined on the first panel.
placements : Scene.Drawing
placements = {
	panel = |ground, disc, light, guides, name, label| {
		## A 44 pt mark, its clear space of one sixth of its width on every
		## side (the tinted square), and the coral boundary around both.
		base = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 155, 86), ground)
		framed = if guides {
			square = Scene.path({}).rectangle(Layout.rect(48, 9, 59, 59)).finish()
			base
				.path(Scene.path({}).rectangle(Layout.rect(41, 2, 73, 73)).finish(), Scene.solid_stroke(coral, Layout.Unit.millipoints(750)))
				.path(square, Scene.solid_stroke(tint(coral_rgb, 40), Layout.Unit.millipoints(500)))
		} else {
			base
		}
		framed
			.group(Layout.point(56, 16), mark(44, disc, light))
			.text({ align: Center, color: label, origin: Layout.point(77, 78), size: points(7), text: name })
	}
	Scene.drawing({})
		.group(Layout.point(0, 0), panel(mist, indigo, amber, True, "Clear space", indigo))
		.group(Layout.point(164, 0), panel(indigo, white, amber, False, "Reversed on Indigo", white))
		.group(Layout.point(328, 0), panel(amber, indigo, white, False, "On Dawn Amber", indigo))
}

## ---------------------------------------------------------------------
## The "At a glance" callout: a separately authored custom block (the
## pattern of tests/custom_block/Callout.roc). Its rich paragraphs may wrap:
## the package measures their height at the panel's content width with
## `Pdf.measure_custom_content`, under the same options the document is
## prepared with, and the block paints its panel behind them.

callout_inset : Layout.Unit
callout_inset = points(12)

## A callout's ground: a light Mist panel with a coral edge and Indigo
## labels, or an Indigo panel with white text and Dawn Amber labels.
Ground : [Light, Dark]

at_a_glance : Pdf.Options, Ground, Str, List(List(Pdf.Inline)) -> Try(Document.Block, Pdf.Error)
at_a_glance = |options, ground, name, lines| {
	width = points(483)
	paragraphs = lines.map(|line| Pdf.rich_paragraph(line))
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en", width: Layout.Unit.from_raw(width.raw() - 2 * callout_inset.raw()) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width }
	box = { origin: Layout.point(0, 0), size }
	edge = { origin: Layout.point(0, 0), size: { height: size.height, width: points(4) } }
	panel = match ground {
		Light => Scene.rectangle(Scene.rectangle(Scene.drawing({}), box, mist), edge, coral)
		Dark => Scene.rectangle(Scene.rectangle(Scene.drawing({}), box, indigo), edge, amber)
	}
	block = Pdf.custom_block({ contents: paragraphs, fragmentation: Unsplittable, inset: callout_inset, name, panel, size })

	## Labels are Lumen Indigo on the light ground; on the Indigo ground
	## all text is white and links are Mist. Accents never carry words.
	scope = match ground {
		Light => Theme.Scope.empty.with_color(Strong, indigo)
		Dark => Theme.Scope.empty.with_color(Text, white).with_color(Strong, white).with_color(Link, mist)
	}
	Ok(Pdf.scoped(scope, [block]))
}

## ---------------------------------------------------------------------
## Page furniture.

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("Lumen Labs · Brand Studio")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

## A hairline under each header, as the region's backdrop, beside the
## slots' furniture.
hairline : Scene.Drawing
hairline = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 483, 1), tint(indigo_rgb, 70))

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(44),
					start: [Pdf.furniture_image(Scene.drawing({}).group(Layout.point(0, 5), mark(36, indigo, amber)))],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("Brand guidelines · Edition 3 · September 2026")])],
				}),
				hairline,
			),
			points(3),
		),
		lead: Pdf.no_lead,
		footer,
		gap: points(14),
	}),
	continuation: Pdf.page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(22),
					start: [Pdf.furniture_text([Pdf.text("Lumen brand guidelines")])],
					center: [],
					end: [Pdf.furniture_text([Pdf.text("Edition 3")])],
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
	{ depth: 0, destination: "idea", open: True, title: "1 The idea" },
	{ depth: 0, destination: "colour", open: True, title: "2 Colour" },
	{ depth: 0, destination: "type", open: True, title: "3 Typography" },
	{ depth: 0, destination: "mark", open: True, title: "4 The mark" },
	{ depth: 0, destination: "voice", open: True, title: "5 Voice" },
	{ depth: 0, destination: "checklist", open: True, title: "6 Before you publish" },
]

## ---------------------------------------------------------------------
## Tables.

group_row : Str, U16 -> Pdf.Row
group_row = |label, columns| Pdf.row([Pdf.shaded(tint(indigo_rgb, 90), Pdf.spanning(columns, Pdf.header_cell(Row, [Pdf.strong([Pdf.text(label)])])))])

colour_row : Str, Str, Str, Str, Str -> Pdf.Row
colour_row = |name, role, hex, rgb, contrast| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(name)]),
	Pdf.cell([Pdf.text(role)]),
	Pdf.cell([Pdf.code(hex)]),
	Pdf.cell([Pdf.code(rgb)]),
	Pdf.cell([Pdf.text(contrast)]),
])

palette_table : Document.Block
palette_table = Pdf.table({
	caption: Pdf.caption("Table 1. Palette values and contrast against white"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Share(5), align: Start },
		{ width: Fixed(points(62)), align: Start },
		{ width: Fixed(points(84)), align: Start },
		{ width: Fixed(points(56)), align: End },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Colour")]),
			Pdf.header_cell(Column, [Pdf.text("Role")]),
			Pdf.header_cell(Column, [Pdf.text("Hex")]),
			Pdf.header_cell(Column, [Pdf.text("sRGB")]),
			Pdf.header_cell(Column, [Pdf.text("Contrast")]),
		]),
	],
	body_rows: [
		group_row("Core", 5),
		colour_row("Lumen Indigo", "Headings, the mark, key actions", "#2B2D6E", "43 45 110", "12.3 : 1"),
		colour_row("Harbour Teal", "Secondary actions, data series", "#167872", "22 120 114", "5.3 : 1"),
		colour_row("Ink", "Body text and interface copy", "#1E2230", "30 34 48", "15.8 : 1"),
		group_row("Accent (never for text)", 5),
		colour_row("Signal Coral", "Highlights, bands, one per view", "#F2665A", "242 102 90", "3.1 : 1"),
		colour_row("Dawn Amber", "The light in the mark, charts", "#F5B83D", "245 184 61", "1.8 : 1"),
	],
	footer_rows: [],
	row_split: KeepRows,
})

type_row : Str, Str, Str, Str -> Pdf.Row
type_row = |role, size, leading, use| Pdf.row([Pdf.header_cell(Row, [Pdf.text(role)]), Pdf.cell([Pdf.text(size)]), Pdf.cell([Pdf.text(leading)]), Pdf.cell([Pdf.text(use)])])

type_table : Document.Block
type_table = Pdf.table({
	caption: Pdf.caption("Table 2. The type scale, in points"),
	columns: [{ width: Share(2), align: Start }, { width: Fixed(points(48)), align: End }, { width: Fixed(points(58)), align: End }, { width: Share(5), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Role")]), Pdf.header_cell(Column, [Pdf.text("Size")]), Pdf.header_cell(Column, [Pdf.text("Leading")]), Pdf.header_cell(Column, [Pdf.text("Use")])])],
	body_rows: [
		type_row("Display", "34", "40", "Covers and one bold title per document"),
		type_row("Heading", "16", "22", "Section openings, bold, in Lumen Indigo"),
		type_row("Body", "10.5", "15.5", "Running text and table cells, in Ink"),
		type_row("Caption", "10.5", "15.5", "Figure and table captions"),
	],
	footer_rows: [],
	row_split: KeepRows,
})

voice_table : Document.Block
voice_table = Pdf.table({
	caption: Pdf.caption("Table 3. Voice in practice"),
	columns: [{ width: Share(1), align: Start }, { width: Share(1), align: Start }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("We write")]), Pdf.header_cell(Column, [Pdf.text("We avoid")])])],
	body_rows: [
		("Your export is ready. It has 14 pages.", "Awesome! Your shiny new export is good to go!"),
		("We could not reach the server. Try again in a minute.", "Oops, something went wrong."),
		("Plans start at USD 12 per editor each month.", "Unbeatable value for teams of every size."),
		("Undo restores the last 50 changes.", "Never lose work again, guaranteed."),
	].map(|(good, bad)| Pdf.row([Pdf.cell([Pdf.text(good)]), Pdf.cell([Pdf.text(bad)])])),
	footer_rows: [],
	row_split: KeepRows,
})

## ---------------------------------------------------------------------

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| {
	glance = at_a_glance(
		options,
		Light,
		"At a glance",
		[
			[Pdf.strong([Pdf.text("Promise")]), Pdf.text("  Calm, precise tools that respect people's attention.")],
			[Pdf.strong([Pdf.text("Colour")]), Pdf.text("  Lumen Indigo leads; Signal Coral appears at most once per view.")],
			[Pdf.strong([Pdf.text("Type")]), Pdf.text("  Public Sans for everything people read; Source Code Pro for code.")],
			[Pdf.strong([Pdf.text("Voice")]), Pdf.text("  Direct, never abrupt. Technical, never opaque. Warm, never ornamental.")],
		],
	)?
	studio = at_a_glance(
		options,
		Dark,
		"Brand Studio",
		[
			[Pdf.strong([Pdf.text("Brand Studio")]), Pdf.text("  Ana Okafor, Head of Brand · brand@lumen.example. Ask before you publish anything new that carries the mark.")],
			[Pdf.strong([Pdf.text("Assets")]), Pdf.text("  Logos, tokens, and templates: "), Pdf.inline_link([Pdf.text("lumen.example/brand")], "https://lumen.example/brand")],
		],
	)?
	Ok(body(glance, studio))
}

body : Document.Block, Document.Block -> List(Document.Block)
body = |glance, studio| [
	Pdf.title("Lumen brand guidelines"),
	Pdf.rich_paragraph([
		Pdf.emphasis([Pdf.text("A practical identity for calm, precise software.")]),
		Pdf.text(" Edition 3 replaces every earlier edition from 1 October 2026."),
	]),
	Pdf.spaced_decoration(palette_strip, { above: points(4), behind: False, below: points(12) }),
	Pdf.paragraph("These guidelines describe how Lumen looks and sounds wherever people meet it: in the product, on the website, in documentation, and on the invoices and letters we send. They are short on purpose: when a case is not covered, choose the quieter option."),
	glance,
	Pdf.section([
		band,
		Pdf.destination_heading("idea", 1, "1 The idea"),
		Pdf.rich_paragraph([
			Pdf.text("Lumen started as a planning tool for teams who were tired of noise. The identity keeps that promise: "),
			Pdf.quote([Pdf.text("“a small light that makes the next step obvious”")]),
			Pdf.text(". Every element should help someone see, decide, or act, and nothing should compete for attention without a reason."),
		]),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Clarity first. ")]), Pdf.text("One idea per screen, per slide, per paragraph.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Quiet confidence. ")]), Pdf.text("Generous whitespace instead of loud colour or effects.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Honest detail. ")]), Pdf.text("Real numbers, real screenshots, and plain claims we can prove.")])]),
		]),
	]),
	Pdf.section([
		band,
		Pdf.destination_heading("colour", 1, "2 Colour"),
		Pdf.rich_paragraph([
			Pdf.text("The palette pairs a deep indigo with a warm dawn light. Indigo, Teal, and Ink carry text and interface; Coral and Amber are "),
			Pdf.emphasis([Pdf.text("accents")]),
			Pdf.text(" and never set body text, because neither reaches 4.5:1 contrast on white. Tints serve backgrounds and data series."),
		]),
		Pdf.figure_fit(
			Pdf.figure(
				swatches,
				"Five colour swatches with three lighter tints each: Lumen Indigo, Harbour Teal, Signal Coral, Dawn Amber, and Ink. Values are listed in Table 1.",
				Pdf.caption("Figure 1. The palette with 25, 50, and 75 percent tints"),
			),
			ScaleToFit({ minimum_percent: 80 }),
		),
		palette_table,
	]),
	Pdf.section([
		band,
		Pdf.destination_heading("type", 1, "3 Typography"),
		Pdf.rich_paragraph([
			Pdf.text("Public Sans is our only typeface for reading. Hierarchy comes from size and colour; bold marks a key term and italics a stressed word, never a whole sentence. Code, colour values, and keyboard input use Source Code Pro, as in "),
			Pdf.code("--lumen-indigo: #2B2D6E"),
			Pdf.text(" or "),
			Pdf.code("lumen export --pdf"),
			Pdf.text("."),
		]),
		type_table,
	]),
	Pdf.section([
		band,
		Pdf.destination_heading("mark", 1, "4 The mark"),
		Pdf.paragraph("The mark is a disc with a smaller light rising from its upper right over a horizon line. It always appears whole, upright, and on one of three approved grounds. Keep a clear space of one sixth of its width on every side."),
		Pdf.figure_fit(
			Pdf.figure(
				placements,
				"The Lumen mark on three approved grounds: indigo on a pale mist ground with its clear-space boundary outlined in coral, white on indigo, and indigo on amber.",
				Pdf.caption("Figure 2. The three approved grounds"),
			),
			ScaleToFit({ minimum_percent: 80 }),
		),
		Pdf.keep_together([
			Pdf.numbered_list(
				{ start: 1, style: Decimal },
				[
					Pdf.list_item([Pdf.paragraph("Never place the mark on photography without a solid ground behind it.")]),
					Pdf.list_item([Pdf.paragraph("Never recolour the light: it is Dawn Amber, or white on an amber ground.")]),
					Pdf.list_item([Pdf.paragraph("Never set the mark smaller than 16 pt on paper or 24 px on screen.")]),
				],
			),
		]),
	]),
	Pdf.section([
		band,
		Pdf.destination_heading("voice", 1, "5 Voice"),
		Pdf.paragraph("We write the way a thoughtful colleague speaks: specific, brief, and kind. We name the thing, give the number, and say what happens next."),
		voice_table,
	]),
	Pdf.section([
		band,
		Pdf.destination_heading("checklist", 1, "6 Before you publish"),
		Pdf.paragraph("Run through this list for anything that carries the Lumen name, from a release note to a conference banner."),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Colours come from the tokens in "), Pdf.inline_internal_link([Pdf.text("Table 1")], "colour"), Pdf.text(", never from a picker.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Text is Ink or Indigo on white or Mist; accents never carry words.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("The mark has its clear space and sits on an approved ground.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Every claim has a number, and every number has a source.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Generated files pass "), Pdf.code("lumen lint --brand"), Pdf.text(" with no warnings.")])]),
		]),
		studio,
	]),
]
