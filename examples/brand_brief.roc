app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../package/main.roc",
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
import "../vendor/fonts/Inter-4.1-Regular.ttf" as inter_bytes : List(U8)
import "../tests/assets/NotoSansMono-Code-Fixture.ttf" as mono_bytes : List(U8)

## Lumen brand guidelines: a branded multi-page brief set in Inter with a
## monospace face for colour and token codes. It shows running headers and
## footers with `Page N of M`, a palette strip and section bands as
## decorations, a separately authored "At a glance" callout, vector
## figures built from grouped drawings (colour swatches with tints and
## logo placements), tables with spanning group rows, rich inline content,
## lists, links, and an outline over named section destinations.
main! = |_args| {
	fonts = register_fonts({})?
	theme = base_theme.with_font(fonts.body).with_inline_font(Code, fonts.mono)
	document = Pdf.document({ contents: contents(theme), language: "en", title: "Lumen brand guidelines, edition 3" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-09-30T00:00:00Z")
		.with_modified("2026-09-30T00:00:00Z")
	options = Pdf.Options.default.with_theme(theme).with_font_registry(fonts.registry)
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "brand-brief.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote brand-brief.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

## Inter for every text role and Noto Sans Mono for `Pdf.code`.
register_fonts : {} -> Try({ body : Font.FaceId, mono : Font.FaceId, registry : Font.Registry }, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin = [Font.Script.from_iso15924("Latn")]
	body = Font.Registry.empty.register(inter_bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))?
	mono = body.registry.register(mono_bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))?
	Ok({ body: body.face, mono: mono.face, registry: mono.registry })
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
		.with_strong_color(indigo)
		.with_code_color(Color.srgb8({ red: 170, green: 58, blue: 48 }))
		.with_table_header_color(indigo)
		.with_table_cell_padding(points(5))
		.with_table_row_gap(points(5))
		.with_table_rule(Rule({ color: indigo, width: Layout.Unit.millipoints(750) }))
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

## A 483 × 8 pt strip, raised 12 pt above the next block, of the five palette colours.
palette_strip : Scene.Drawing
palette_strip = {
	widths = [(indigo, 193), (teal_source, 97), (coral, 97), (amber, 48), (ink, 48)]
	var $drawing = Scene.drawing({})
	var $x = 0
	for (color, width) in widths {
		$drawing = Scene.rectangle($drawing, Layout.rect($x, 12, width, 8), color)
		$x = $x + width
	}
	$drawing
}

teal_source : Color.SourceValue
teal_source = Color.srgb8(teal_rgb)

## A section band: a short coral bar over a hairline across the measure,
## raised 6 pt above the heading it introduces.
band : Scene.Drawing
band = Scene.rectangle(Scene.rectangle(Scene.drawing({}), Layout.rect(0, 8, 483, 1), tint(indigo_rgb, 80)), Layout.rect(0, 6, 36, 5), coral)

## One swatch card: the solid colour above three tints (75, 50, 25 percent
## toward white).
swatch : Rgb -> Scene.Drawing
swatch = |rgb| {
	solid = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 39, 88, 52), Color.srgb8(rgb))
	light = Scene.rectangle(Scene.rectangle(solid, Layout.rect(0, 26, 88, 12), tint(rgb, 25)), Layout.rect(0, 13, 88, 12), tint(rgb, 50))
	Scene.rectangle(light, Layout.rect(0, 0, 88, 12), tint(rgb, 75))
}

swatches : Scene.Drawing
swatches = {
	var $drawing = Scene.drawing({})
	var $x = 0
	for rgb in [indigo_rgb, teal_rgb, coral_rgb, amber_rgb, ink_rgb] {
		$drawing = $drawing.group(Layout.point($x, 0), swatch(rgb))
		$x = $x + 98
	}
	$drawing
}

## The mark on three approved grounds, with its clear space outlined on
## the first panel.
placements : Scene.Drawing
placements = {
	panel = |ground, disc, light, guides| {
		base = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 155, 124), ground)
		framed = if guides {
			square = Scene.path({}).rectangle(Layout.rect(35, 20, 84, 84)).finish()
			base
				.path(Scene.path({}).rectangle(Layout.rect(25, 10, 104, 104)).finish(), Scene.solid_stroke(coral, Layout.Unit.millipoints(750)))
				.path(square, Scene.solid_stroke(tint(coral_rgb, 40), Layout.Unit.millipoints(500)))
		} else {
			base
		}
		framed.group(Layout.point(45, 30), mark(64, disc, light))
	}
	Scene.drawing({})
		.group(Layout.point(0, 0), panel(mist, indigo, amber, True))
		.group(Layout.point(164, 0), panel(indigo, white, amber, False))
		.group(Layout.point(328, 0), panel(amber, indigo, white, False))
}

## ---------------------------------------------------------------------
## The "At a glance" callout: a separately authored custom block (the
## pattern of tests/custom_block/Callout.roc). Each line is one rich
## paragraph that must fit one body line; the block measures its height
## from the theme's public metrics and paints a tinted panel with a coral
## edge behind its content.

callout_inset : Layout.Unit
callout_inset = points(12)

at_a_glance : Theme, List(List(Pdf.Inline)) -> Document.Block
at_a_glance = |theme, lines| {
	leading = Theme.body_style(theme).leading.raw()
	spacing = Theme.paragraph_spacing(theme).raw()
	count = lines.len().to_i64_wrap()
	size = { height: Layout.Unit.from_raw(callout_inset.raw() * 2 + leading * count + spacing * (count - 1)), width: points(483) }
	Pdf.custom_block({
		contents: lines.map(|line| Pdf.rich_paragraph(line)),
		fragmentation: Unsplittable,
		inset: callout_inset,
		name: "At a glance",
		panel: Scene.rectangle(Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size }, mist), { origin: Layout.point(0, 0), size: { height: size.height, width: points(4) } }, coral),
		size,
	})
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

hairline : Scene.Drawing
hairline = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 483, 1), tint(indigo_rgb, 70))

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.region({
			height: points(36),
			start: [Pdf.furniture_image(mark(36, indigo, amber))],
			center: [],
			end: [Pdf.furniture_text([Pdf.text("Brand guidelines · Edition 3 · September 2026")])],
		}),
		lead: Pdf.no_lead,
		footer,
		gap: points(14),
	}),
	continuation: Pdf.page_template({
		header: Pdf.region({
			height: points(22),
			start: [Pdf.furniture_text([Pdf.text("Lumen brand guidelines")]), Pdf.furniture_image(hairline)],
			center: [],
			end: [],
		}),
		footer,
		gap: points(18),
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
group_row = |label, columns| Pdf.row([Pdf.spanning(columns, Pdf.header_cell(Row, [Pdf.strong([Pdf.text(label)])]))])

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
		type_row("Display", "34", "40", "Covers and one title per document"),
		type_row("Heading", "16", "22", "Section openings, in Lumen Indigo"),
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

contents : Theme -> List(Document.Block)
contents = |theme| [
	Pdf.title("Lumen brand guidelines"),
	Pdf.rich_paragraph([
		Pdf.emphasis([Pdf.text("A practical identity for calm, precise software.")]),
		Pdf.text(" Edition 3 replaces every earlier edition from 1 October 2026."),
	]),
	Pdf.decoration(palette_strip),
	Pdf.paragraph("These guidelines describe how Lumen looks and sounds wherever people meet it: in the product, on the website, in documentation, and on the invoices and letters we send. They are short on purpose: when a case is not covered, choose the quieter option."),
	at_a_glance(
		theme,
		[
			[Pdf.strong([Pdf.text("Promise")]), Pdf.text("  Calm, precise tools that respect people's attention.")],
			[Pdf.strong([Pdf.text("Colour")]), Pdf.text("  Lumen Indigo leads; Signal Coral appears at most once per view.")],
			[Pdf.strong([Pdf.text("Type")]), Pdf.text("  Inter for everything people read; a monospace face for code.")],
			[Pdf.strong([Pdf.text("Voice")]), Pdf.text("  Direct, never abrupt. Technical, never opaque. Warm, never ornamental.")],
		],
	),
	Pdf.section([
		Pdf.decoration(band),
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
		Pdf.decoration(band),
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
		Pdf.decoration(band),
		Pdf.destination_heading("type", 1, "3 Typography"),
		Pdf.rich_paragraph([
			Pdf.text("Inter is our only typeface for reading, set in its regular weight; hierarchy comes from size and colour, not from bold or italics. Code, colour values, and keyboard input use a monospace face, as in "),
			Pdf.code("--lumen-indigo: #2B2D6E"),
			Pdf.text(" or "),
			Pdf.code("lumen export --pdf"),
			Pdf.text("."),
		]),
		type_table,
	]),
	Pdf.section([
		Pdf.decoration(band),
		Pdf.destination_heading("mark", 1, "4 The mark"),
		Pdf.paragraph("The mark is a disc with a smaller light rising from its upper right over a horizon line. It always appears whole, upright, and on one of three approved grounds. Keep a clear space of one sixth of its width on every side."),
		Pdf.figure_fit(
			Pdf.figure(
				placements,
				"The Lumen mark on three approved grounds: indigo on a pale mist ground with its clear-space boundary outlined in coral, white on indigo, and indigo on amber.",
				Pdf.caption("Figure 2. Approved grounds, with the clear space outlined on the first"),
			),
			ScaleToFit({ minimum_percent: 80 }),
		),
		Pdf.keep_together([Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				Pdf.list_item([Pdf.paragraph("Never place the mark on photography without a solid ground behind it.")]),
				Pdf.list_item([Pdf.paragraph("Never recolour the light: it is Dawn Amber, or white on an amber ground.")]),
				Pdf.list_item([Pdf.paragraph("Never set the mark smaller than 16 pt on paper or 24 px on screen.")]),
			],
		)]),
	]),
	Pdf.section([
		Pdf.decoration(band),
		Pdf.destination_heading("voice", 1, "5 Voice"),
		Pdf.paragraph("We write the way a thoughtful colleague speaks: specific, brief, and kind. We name the thing, give the number, and say what happens next."),
		voice_table,
	]),
	Pdf.section([
		Pdf.decoration(band),
		Pdf.destination_heading("checklist", 1, "6 Before you publish"),
		Pdf.paragraph("Run through this list for anything that carries the Lumen name, from a release note to a conference banner."),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Colours come from the tokens in "), Pdf.inline_internal_link([Pdf.text("Table 1")], "colour"), Pdf.text(", never from a picker.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Text is Ink or Indigo on white or Mist; accents never carry words.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("The mark has its clear space and sits on an approved ground.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Every claim has a number, and every number has a source.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.text("Generated files pass "), Pdf.code("lumen lint --brand"), Pdf.text(" with no warnings.")])]),
		]),
		at_a_glance(
			theme,
			[
				[Pdf.strong([Pdf.text("Brand Studio")]), Pdf.text("  Ana Okafor, Head of Brand · brand@lumen.example")],
				[Pdf.strong([Pdf.text("Assets")]), Pdf.text("  Logos, tokens, and templates: "), Pdf.inline_link([Pdf.text("lumen.example/brand")], "https://lumen.example/brand")],
			],
		),
	]),
]
