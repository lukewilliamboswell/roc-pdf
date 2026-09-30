app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "fonts/Literata-Regular.ttf" as regular_bytes : List(U8)
import "fonts/Literata-Bold.ttf" as bold_bytes : List(U8)
import "fonts/Literata-Italic.ttf" as italic_bytes : List(U8)

## A pocket field guide to the shorebirds of a tidal estuary: a vector
## habitat cross-section and bird plates built from grouped `Scene` paths,
## species accounts that are outline destinations and cross-reference one
## another, identification lists, a survey sheet kept on one page (a
## details table and a framed, column-ruled checklist whose blank cells
## are empty `TD`s for the surveyor to fill in), callouts through the
## custom-block seam measured by the package, page labels, and running
## headers and footers with the header text inset above a ruled backdrop.
main! = |_args| {
	fonts = register_fonts({})?
	options = Pdf.Options.default.with_theme(with_faces(theme, fonts)).with_font_registry(fonts.registry)
	blocks = contents(options).map_err(|err| PdfFailed(err))?
	document = Pdf.document({ contents: blocks, language: "en-AU", title: "Coastal field guide: shorebirds of the Derwent estuary" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_page_labels([{ prefix: "FG-", start_number: 1, start_page: 0, style: DecimalArabic }])
		.with_created("2026-11-02T00:00:00Z")
		.with_modified("2026-11-02T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "field-guide.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Ok({})
}

Faces : { regular : Font.FaceId, bold : Font.FaceId, italic : Font.FaceId, registry : Font.Registry }

## Literata Regular, Bold, and Italic, each retained
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
## Italic for `Pdf.emphasis`. Level-2 headings (the species accounts) are
## smaller and set in ink.
with_faces : Theme, Faces -> Theme
with_faces = |base, faces| {
	title = Theme.title_style(base)
	heading = Theme.heading_style(base)
	base
		.with_font(faces.regular)
		.with_title_style({ ..title, font: faces.bold })
		.with_heading_level_style(H1, { ..heading, font: faces.bold })
		.with_heading_level_style(H2, { ..heading, font: faces.bold, color: ink, size: points(13), leading: points(18) })
		.with_inline_font(Strong, faces.bold)
		.with_inline_font(Emphasis, faces.italic)
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

rgb : U8, U8, U8 -> Color.SourceValue
rgb = |red, green, blue| Color.srgb8({ red, green, blue })

coastal : Color.SourceValue
coastal = rgb(10, 96, 98)

ink : Color.SourceValue
ink = rgb(33, 41, 44)

sand : Color.SourceValue
sand = rgb(226, 204, 158)

## A4 with a wide binding margin: a 459 pt measure.
body_width : I64
body_width = 459

theme : Theme
theme = {
	base_title = Theme.title_style(Theme.default)
	base_heading = Theme.heading_style(Theme.default)
	base_body = Theme.body_style(Theme.default)
	Theme.default
		.with_page_margin({ top: points(44), right: points(56), bottom: points(40), left: points(80) })
		.with_title_style({ ..base_title, color: coastal, size: points(32), leading: points(38) })
		.with_heading_style({ ..base_heading, color: coastal, size: points(16), leading: points(21) })
		.with_body_style({ ..base_body, color: ink, size: points(10), leading: points(14) })
		.with_paragraph_spacing(points(7))
		.with_table_header_color(coastal)
		.with_table_header_fill(rgb(232, 242, 241))
		.with_table_body_fills({ odd: NoFill, even: Fill(rgb(249, 246, 239)) })
		.with_table_rule(Rule({ color: rgb(120, 170, 168), width: points(1) }))
		.with_table_column_rule(Rule({ color: rgb(214, 226, 224), width: Layout.Unit.millipoints(600) }))
		.with_table_frame(Rule({ color: rgb(120, 170, 168), width: Layout.Unit.millipoints(800) }))
		.with_table_cell_padding(points(4))
		.with_link_color(coastal)
		.with_link_underline(Underline({ offset: Layout.Unit.millipoints(1300), thickness: Layout.Unit.millipoints(500) }))
}

## ---------------------------------------------------------------------
## Page furniture.

wave_mark : Scene.Drawing
wave_mark = {
	wave = |y| Scene.path({})
		.move_to(Layout.point(1, y))
		.cubic_to({ control_1: Layout.point(5, y + 5), control_2: Layout.point(9, y + 5), end: Layout.point(13, y) })
		.cubic_to({ control_1: Layout.point(17, y - 5), control_2: Layout.point(21, y - 5), end: Layout.point(25, y) })
		.finish()
	Scene.drawing({})
		.path(wave(6), Scene.solid_stroke(coastal, Layout.Unit.millipoints(1500)))
		.path(wave(12), Scene.solid_stroke(rgb(120, 170, 168), Layout.Unit.millipoints(1500)))
}

rule : Scene.Drawing
rule = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(600), width: points(body_width) } }, rgb(120, 170, 168))

footer : Pdf.Region
footer = Pdf.region({
	height: points(14),
	start: [Pdf.furniture_text([Pdf.text("Derwent Estuary Bird Group · 2026 edition")])],
	center: [],
	end: [Pdf.furniture_text([Pdf.reserved_width(points(40), End, [Pdf.text("FG-"), Pdf.page_number(Decimal)])])],
})

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({ header: Pdf.no_region, lead: Pdf.no_lead, footer, gap: points(12) }),
	continuation: Pdf.page_template({
		header: Pdf.with_slot_inset(
			Pdf.with_backdrop(
				Pdf.region({
					height: points(21),
					start: [Pdf.furniture_text([Pdf.text("Coastal field guide · Shorebirds")])],
					center: [],
					end: [Pdf.furniture_image(wave_mark)],
				}),
				rule,
			),
			points(3),
		),
		footer,
		gap: points(14),
	}),
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "habitat", open: True, title: "Reading the estuary" },
	{ depth: 0, destination: "kit", open: True, title: "Before you go" },
	{ depth: 0, destination: "species", open: True, title: "Species accounts" },
	{ depth: 1, destination: "oystercatcher", open: True, title: "Pied oystercatcher" },
	{ depth: 1, destination: "plover", open: True, title: "Red-capped plover" },
	{ depth: 1, destination: "curlew", open: True, title: "Far Eastern curlew" },
	{ depth: 0, destination: "survey", open: True, title: "Running a survey" },
	{ depth: 0, destination: "checklist", open: True, title: "Survey checklist" },
]

## ---------------------------------------------------------------------
## Drawing helpers.

point : I64, I64 -> Layout.Point
point = |x, y| Layout.point(x, y)

## An ellipse centred on (cx, cy) as four cubic arcs.
ellipse : I64, I64, I64, I64 -> Scene.AuthorPath
ellipse = |cx, cy, rx, ry| {
	kx = rx * 552 // 1000
	ky = ry * 552 // 1000
	Scene.path({})
		.move_to(point(cx + rx, cy))
		.cubic_to({ control_1: point(cx + rx, cy + ky), control_2: point(cx + kx, cy + ry), end: point(cx, cy + ry) })
		.cubic_to({ control_1: point(cx - kx, cy + ry), control_2: point(cx - rx, cy + ky), end: point(cx - rx, cy) })
		.cubic_to({ control_1: point(cx - rx, cy - ky), control_2: point(cx - kx, cy - ry), end: point(cx, cy - ry) })
		.cubic_to({ control_1: point(cx + kx, cy - ry), control_2: point(cx + rx, cy - ky), end: point(cx + rx, cy) })
		.close()
		.finish()
}

line : I64, I64, I64, I64 -> Scene.AuthorPath
line = |x1, y1, x2, y2| Scene.path({}).move_to(point(x1, y1)).line_to(point(x2, y2)).finish()

## ---------------------------------------------------------------------
## Figure 1: a cross-section of the estuary from dune crest to channel,
## with the high- and low-tide lines and the feeding zones of each species.

habitat_section : Scene.Drawing
habitat_section = {
	w = body_width
	sky = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, w, 190), rgb(226, 240, 244))
	dune = Scene.path({})
		.move_to(point(0, 0))
		.line_to(point(0, 120))
		.cubic_to({ control_1: point(40, 150), control_2: point(90, 150), end: point(130, 110) })
		.cubic_to({ control_1: point(170, 75), control_2: point(220, 60), end: point(300, 48) })
		.cubic_to({ control_1: point(360, 40), control_2: point(410, 34), end: point(w, 30) })
		.line_to(point(w, 0))
		.close()
		.finish()
	water = Scene.path({})
		.move_to(point(180, 0))
		.line_to(point(180, 72))
		.line_to(point(w, 72))
		.line_to(point(w, 0))
		.close()
		.finish()
	shallows = Scene.rectangle(Scene.drawing({}), Layout.rect(300, 0, w - 300, 48), rgb(70, 150, 160))
	var $scene = sky
		.path(water, Scene.solid_fill(rgb(150, 205, 210)))
		.group(point(0, 0), shallows)
		.path(dune, Scene.solid_fill(sand))

	## Marram grass tufts on the dune crest.
	for x in [30, 52, 74, 96] {
		$scene = $scene
			.path(line(x, 136, x - 5, 152), Scene.solid_stroke(rgb(96, 128, 60), points(1)))
			.path(line(x, 136, x, 156), Scene.solid_stroke(rgb(96, 128, 60), points(1)))
			.path(line(x, 136, x + 5, 152), Scene.solid_stroke(rgb(96, 128, 60), points(1)))
	}

	# The high-tide line (dashed) and the low-tide line.
	var $x = 184
	while $x < w - 6 {
		$scene = $scene.path(line($x, 72, $x + 6, 72), Scene.solid_stroke(coastal, points(1)))
		$x = $x + 10
	}
	$scene = $scene.path(line(300, 48, w - 2, 48), Scene.solid_stroke(rgb(12, 70, 80), points(1)))

	## Feeding-zone brackets above the flats: oystercatcher (black), plover (rust), curlew (brown).
	$scene = $scene
		.group(point(150, 160), zone(rgb(20, 20, 20), 150))
		.group(point(104, 172), zone(rgb(176, 72, 40), 80))
		.group(point(240, 148), zone(rgb(120, 84, 50), 200))

	## Zone names above their brackets and the tide lines' names.
	label = |x, y, align, color, text| { align, color, origin: point(x, y), size: points(7), text }
	$scene = $scene
		.text(label(225, 171, Center, rgb(20, 20, 20), "Oystercatcher"))
		.text(label(104, 182, Start, rgb(176, 72, 40), "Plover"))
		.text(label(w - 6, 158, End, rgb(120, 84, 50), "Curlew"))
		.text(label(w - 6, 76, End, coastal, "High tide"))
		.text(label(w - 6, 38, End, rgb(250, 252, 252), "Low tide"))
		.text(label(8, 20, Start, rgb(120, 96, 50), "Dune"))
		.text(label(w - 6, 6, End, rgb(250, 252, 252), "Channel"))

	## Small birds at work on the flats.
	$scene
		.group(point(220, 60), oystercatcher_small)
		.group(point(160, 78), plover_small)
		.group(point(350, 50), curlew_small)
}

zone : Color.SourceValue, I64 -> Scene.Drawing
zone = |color, width| Scene.drawing({})
	.path(Scene.path({}).move_to(point(1, 0)).line_to(point(1, 6)).line_to(point(width - 1, 6)).line_to(point(width - 1, 0)).finish(), Scene.solid_stroke(color, Layout.Unit.millipoints(1500)))

oystercatcher_small : Scene.Drawing
oystercatcher_small = Scene.drawing({})
	.path(line(10, 1, 10, 10), Scene.solid_stroke(rgb(230, 130, 140), points(1)))
	.path(line(14, 1, 14, 10), Scene.solid_stroke(rgb(230, 130, 140), points(1)))
	.path(ellipse(12, 14, 9, 5), Scene.solid_fill(rgb(20, 20, 20)))
	.path(ellipse(22, 19, 3, 3), Scene.solid_fill(rgb(20, 20, 20)))
	.path(line(24, 19, 32, 16), Scene.solid_stroke(rgb(214, 70, 40), Layout.Unit.millipoints(1500)))

plover_small : Scene.Drawing
plover_small = Scene.drawing({})
	.path(line(7, 1, 7, 5), Scene.solid_stroke(ink, Layout.Unit.millipoints(800)))
	.path(ellipse(8, 8, 6, 3), Scene.solid_fill(rgb(200, 180, 150)))
	.path(ellipse(14, 11, 2, 2), Scene.solid_fill(rgb(176, 72, 40)))

curlew_small : Scene.Drawing
curlew_small = Scene.drawing({})
	.path(line(12, 1, 12, 12), Scene.solid_stroke(ink, points(1)))
	.path(line(16, 1, 16, 12), Scene.solid_stroke(ink, points(1)))
	.path(ellipse(14, 17, 11, 6), Scene.solid_fill(rgb(150, 112, 72)))
	.path(ellipse(26, 23, 3, 3), Scene.solid_fill(rgb(150, 112, 72)))
	.path(Scene.path({}).move_to(point(28, 23)).cubic_to({ control_1: point(34, 22), control_2: point(38, 18), end: point(40, 12) }).finish(), Scene.solid_stroke(ink, points(1)))

## ---------------------------------------------------------------------
## Species plates: a large, labelled-by-caption silhouette on a tinted card.

bird : { bill : Scene.AuthorPath, body : Color.SourceValue, belly : Color.SourceValue, height : I64, leg : Color.SourceValue, length : I64 } -> Scene.Drawing
bird = |{ bill, body, belly, height, leg, length }| {
	cx = length // 2 + 6
	cy = height + 20
	rx = length // 2
	ry = length // 4
	head = length // 7
	legs = Scene.drawing({})
		.path(line(cx - 4, 2, cx - 2, cy - ry + 4), Scene.solid_stroke(leg, points(2)))
		.path(line(cx + 5, 2, cx + 3, cy - ry + 4), Scene.solid_stroke(leg, points(2)))
	legs
		.path(ellipse(cx, cy, rx, ry), Scene.solid_fill(body))
		.path(ellipse(cx + 2, cy - ry // 3, rx - 6, ry // 2), Scene.solid_fill(belly))
		.path(ellipse(cx + rx - head // 2, cy + ry, head, head), Scene.solid_fill(body))
		.path(ellipse(cx + rx - head // 2 + head // 3, cy + ry + head // 4, 2, 2), Scene.solid_fill(rgb(250, 250, 250)))
		.path(bill, Scene.solid_fill(body))
}

card : Scene.Drawing, Color.SourceValue, Str -> Scene.Drawing
card = |figure, tint, name| Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 145, 130), tint)
	.path(line(10, 18, 135, 18), Scene.solid_stroke(sand, points(2)))
	.group(point(18, 16), figure)
	.text({ align: Center, color: ink, origin: point(72, 5), size: points(8), text: name })

oystercatcher_plate : Scene.Drawing
oystercatcher_plate = {
	## Body 80 pt long; the bill leaves the head at (95, 76).
	bill = Scene.path({}).move_to(point(88, 78)).line_to(point(116, 74)).line_to(point(88, 72)).close().finish()
	base = bird({ bill, body: rgb(22, 22, 24), belly: rgb(246, 246, 244), height: 36, leg: rgb(228, 128, 138), length: 80 })
	base.path(Scene.path({}).move_to(point(88, 78)).line_to(point(116, 74)).line_to(point(88, 72)).close().finish(), Scene.solid_fill(rgb(222, 72, 36)))
}

plover_plate : Scene.Drawing
plover_plate = {
	bill = Scene.path({}).move_to(point(58, 50)).line_to(point(68, 48)).line_to(point(58, 46)).close().finish()
	base = bird({ bill, body: rgb(196, 172, 138), belly: rgb(250, 248, 242), height: 20, leg: rgb(40, 40, 40), length: 52 })

	## The rufous cap and the dark shoulder patch.
	base
		.path(ellipse(54, 58, 7, 3), Scene.solid_fill(rgb(182, 74, 38)))
		.path(ellipse(46, 40, 3, 6), Scene.solid_fill(rgb(40, 40, 40)))
}

curlew_plate : Scene.Drawing
curlew_plate = {
	bill = Scene.path({})
		.move_to(point(90, 72))
		.cubic_to({ control_1: point(104, 72), control_2: point(112, 62), end: point(116, 46) })
		.line_to(point(114, 46))
		.cubic_to({ control_1: point(110, 60), control_2: point(102, 68), end: point(90, 68) })
		.close()
		.finish()
	bird({ bill, body: rgb(146, 108, 70), belly: rgb(214, 190, 150), height: 34, leg: rgb(70, 76, 80), length: 84 })
}

plates : Scene.Drawing
plates = Scene.drawing({})
	.group(point(0, 0), card(oystercatcher_plate, rgb(236, 243, 242), "Pied oystercatcher"))
	.group(point(157, 0), card(plover_plate, rgb(244, 238, 230), "Red-capped plover"))
	.group(point(314, 0), card(curlew_plate, rgb(240, 236, 228), "Far Eastern curlew"))

## ---------------------------------------------------------------------
## A callout following `tests/custom_block/Callout.roc`: paragraphs that
## may wrap, measured by the package at the panel's content width, over a
## tinted rounded panel.

callout_inset : Layout.Unit
callout_inset = points(12)

## Each line is a label and its text; the callout scopes its `Strong`
## labels to its accent colour.
callout : Pdf.Options, Str, Color.SourceValue, List((Str, Str)) -> Try(Document.Block, Pdf.Error)
callout = |options, name, accent, lines| {
	paragraphs = lines.map(|(label, text)| Pdf.rich_paragraph([Pdf.strong([Pdf.text(label)]), Pdf.text(" ${text}")]))
	content = Pdf.measure_custom_content(options, { contents: paragraphs, language: "en-AU", width: points(body_width - 24) })?
	size = { height: Layout.Unit.from_raw(content.raw() + 2 * callout_inset.raw()), width: points(body_width) }
	block = Pdf.custom_block({
		contents: paragraphs,
		fragmentation: Unsplittable,
		inset: callout_inset,
		name,
		panel: callout_panel(size),
		size,
	})
	Ok(Pdf.scoped(Theme.Scope.empty.with_color(Strong, accent), [block]))
}

callout_panel : Layout.Size -> Scene.Drawing
callout_panel = |size| {
	half = 500
	r = 8000
	k = r * 552 // 1000
	left = half
	bottom = half
	right = size.width.raw() - half
	top = size.height.raw() - half
	at = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	outline_path = Scene.path({})
		.move_to(at(left + r, bottom))
		.line_to(at(right - r, bottom))
		.cubic_to({ control_1: at(right - r + k, bottom), control_2: at(right, bottom + r - k), end: at(right, bottom + r) })
		.line_to(at(right, top - r))
		.cubic_to({ control_1: at(right, top - r + k), control_2: at(right - r + k, top), end: at(right - r, top) })
		.line_to(at(left + r, top))
		.cubic_to({ control_1: at(left + r - k, top), control_2: at(left, top - r + k), end: at(left, top - r) })
		.line_to(at(left, bottom + r))
		.cubic_to({ control_1: at(left, bottom + r - k), control_2: at(left + r - k, bottom), end: at(left + r, bottom) })
		.close()
		.finish()
	Scene.drawing({}).path(outline_path, { fill: AuthorSolidFill(rgb(246, 241, 228)), stroke: AuthorSolidStroke({ color: rgb(200, 170, 110), width: points(1) }) })
}

## A thin sand-coloured rule with a centred wave, set 6 pt below the
## account before it and above each species account.
divider : Document.Block
divider = Pdf.spaced_decoration(
	Scene.drawing({})
		.path(line(1, 7, 210, 7), Scene.solid_stroke(sand, points(1)))
		.group(point(217, 0), wave_mark)
		.path(line(249, 7, body_width - 1, 7), Scene.solid_stroke(sand, points(1))),
	{ above: points(6), behind: False, below: points(0) },
)

## ---------------------------------------------------------------------

id_list : List(Pdf.Inline), List(Pdf.Inline), List(Pdf.Inline) -> Document.Block
id_list = |size, marks, voice| Pdf.bullet_list([
	Pdf.list_item([Pdf.rich_paragraph(List.concat([Pdf.strong([Pdf.text("Size: ")])], size))]),
	Pdf.list_item([Pdf.rich_paragraph(List.concat([Pdf.strong([Pdf.text("Field marks: ")])], marks))]),
	Pdf.list_item([Pdf.rich_paragraph(List.concat([Pdf.strong([Pdf.text("Call: ")])], voice))]),
])

check_row : Str, Str, Str, Str -> Pdf.Row
check_row = |name, scientific, season, status| Pdf.row([
	Pdf.header_cell(Row, [Pdf.text(name)]),
	Pdf.cell([Pdf.emphasis([Pdf.in_language("la", [Pdf.text(scientific)])])]),
	Pdf.cell([Pdf.text(season)]),
	threatened(status),
	Pdf.cell([]),
])

## A threatened status is set in bold on a warm tint.
threatened : Str -> Pdf.Cell
threatened = |status| if status == "Endangered" or status == "Vulnerable" Pdf.shaded(rgb(250, 232, 222), Pdf.cell([Pdf.strong([Pdf.text(status)])])) else Pdf.cell([Pdf.text(status)])

## The survey sheet is kept whole so a surveyor can print one page: the
## details to fill in, then the checklist with its blank count column and
## two blank rows for other species.
checklist : Document.Block
checklist = Pdf.keep_together([survey_details, table_of_species])

## Blank cells are what the sheet means: the surveyor writes the values in.
survey_details : Document.Block
survey_details = Pdf.table({
	caption: Pdf.caption("Table 1. Survey details"),
	columns: [
		{ width: Fixed(points(78)), align: Start },
		{ width: Share(1), align: Start },
		{ width: Fixed(points(78)), align: Start },
		{ width: Share(1), align: Start },
	],
	header_rows: [],
	body_rows: [
		Pdf.row([Pdf.header_cell(Row, [Pdf.text("Observer")]), Pdf.cell([]), Pdf.header_cell(Row, [Pdf.text("Date")]), Pdf.cell([])]),
		Pdf.row([Pdf.header_cell(Row, [Pdf.text("Start time")]), Pdf.cell([]), Pdf.header_cell(Row, [Pdf.text("High tide")]), Pdf.cell([])]),
		Pdf.row([Pdf.header_cell(Row, [Pdf.text("Site code")]), Pdf.cell([Pdf.code("DERW-04")]), Pdf.header_cell(Row, [Pdf.text("Weather")]), Pdf.cell([])]),
	],
	footer_rows: [],
	row_split: KeepRows,
})

## A blank row for a species not on the list.
other_row : Pdf.Row
other_row = Pdf.row([Pdf.header_cell(Row, []), Pdf.cell([]), Pdf.cell([]), Pdf.cell([]), Pdf.cell([])])

table_of_species : Document.Block
table_of_species = Pdf.table({
	caption: Pdf.caption("Table 2. Shorebirds recorded on the estuary, with a column for your count"),
	columns: [
		{ width: Share(3), align: Start },
		{ width: Share(3), align: Start },
		{ width: Share(2), align: Start },
		{ width: Share(2), align: Start },
		{ width: Fixed(points(44)), align: End },
	],
	header_rows: [
		Pdf.row([
			Pdf.header_cell(Column, [Pdf.text("Species")]),
			Pdf.header_cell(Column, [Pdf.text("Scientific name")]),
			Pdf.header_cell(Column, [Pdf.text("Season")]),
			Pdf.header_cell(Column, [Pdf.text("Status")]),
			Pdf.header_cell(Column, [Pdf.text("Count")]),
		]),
	],
	body_rows: [
		check_row("Pied oystercatcher", "Haematopus longirostris", "All year", "Resident"),
		check_row("Sooty oystercatcher", "Haematopus fuliginosus", "All year", "Resident"),
		check_row("Red-capped plover", "Charadrius ruficapillus", "All year", "Resident"),
		check_row("Hooded plover", "Thinornis cucullatus", "All year", "Vulnerable"),
		check_row("Masked lapwing", "Vanellus miles", "All year", "Resident"),
		check_row("Far Eastern curlew", "Numenius madagascariensis", "Sep to Apr", "Endangered"),
		check_row("Bar-tailed godwit", "Limosa lapponica", "Sep to Apr", "Vulnerable"),
		check_row("Red-necked stint", "Calidris ruficollis", "Sep to Apr", "Migrant"),
		check_row("Double-banded plover", "Charadrius bicinctus", "Mar to Aug", "Migrant"),
		other_row,
		other_row,
	],
	footer_rows: [],
	row_split: KeepRows,
})

contents : Pdf.Options -> Try(List(Document.Block), Pdf.Error)
contents = |options| {
	windows = callout(
		options,
		"Best counting windows",
		coastal,
		[
			("Roost counts", "from two hours before to one hour after high tide, when birds pack together above the tide line."),
			("Feeding counts", "on the falling tide, three to five hours after high water."),
			("Wind", "avoid days above 25 km/h; birds hunker down and are hard to see."),
		],
	)?
	etiquette = callout(
		options,
		"Field etiquette",
		rgb(176, 72, 40),
		[
			("Distance", "stay at least 50 m from roosting and nesting birds, and further from a curlew roost."),
			("Dogs", "keep them on a lead; dogs are banned from the spit all year."),
			("Alarm", "if birds take flight or call in alarm, you are too close."),
		],
	)?
	Ok(body(windows, etiquette))
}

body : Document.Block, Document.Block -> List(Document.Block)
body = |windows, etiquette| [
	Pdf.title("Coastal field guide"),
	Pdf.rich_paragraph([
		Pdf.strong([Pdf.text("Shorebirds of the Derwent estuary")]),
		Pdf.text(" · A pocket companion for volunteer surveyors"),
	]),
	Pdf.figure_fit(
		Pdf.figure(
			habitat_section,
			"Cross-section of the estuary from a grassy dune crest down across sand flats to the channel, with a dashed high-tide line and a solid low-tide line. Brackets above the flats mark where oystercatchers, red-capped plovers, and curlews feed, and a small bird of each species is shown in its zone.",
			Pdf.caption("Figure 1. From dune to channel: where each species feeds"),
		),
		ScaleToFit({ minimum_percent: 60 }),
	),
	Pdf.section([
		Pdf.destination_heading("habitat", 1, "Reading the estuary"),
		Pdf.rich_paragraph([
			Pdf.text("Shorebirds follow the tide. Most feed on the "),
			Pdf.emphasis([Pdf.text("falling")]),
			Pdf.text(" tide, when fresh mud is exposed, and roost above the high-tide line in the two hours either side of high water. Plan counts around the roost: birds are packed together and easy to tally. The three species described in "),
			Pdf.inline_internal_link([Pdf.text("Species accounts")], "species"),
			Pdf.text(" between them use every zone in Figure 1."),
		]),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Dune and upper beach")]), Pdf.text(": nesting plovers from August to January. Keep to the wet sand.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Sand flats")]), Pdf.text(": oystercatchers probing for pipis and worms.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Soft mud and shallows")]), Pdf.text(": curlews and godwits working the channel edge.")])]),
		]),
		windows,
	]),
	Pdf.section([
		Pdf.destination_heading("kit", 1, "Before you go"),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Tide table")]), Pdf.text(": the Hobart port times, plus about 20 minutes for the inner flats.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Optics")]), Pdf.text(": 8 × 42 binoculars for the roost, and a telescope for the far channel edge.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Survey sheet")]), Pdf.text(": the checklist in "), Pdf.inline_internal_link([Pdf.text("Survey checklist")], "checklist"), Pdf.text(", printed on one page, and a pencil.")])]),
			Pdf.list_item([Pdf.rich_paragraph([Pdf.strong([Pdf.text("Clothing")]), Pdf.text(": dull colours, a hat, and boots for the wet sand.")])]),
		]),
		Pdf.paragraph("A count is called off when the Bureau of Meteorology issues a strong wind warning for the Derwent. The coordinator confirms every count in the group's channel by 7 am on the day."),
	]),
	Pdf.page_break,
	Pdf.section([
		Pdf.destination_heading("species", 1, "Species accounts"),
		Pdf.paragraph("Each plate below is drawn to the same scale, so relative size is a first clue. Compare bill shape next: it tells you how, and where, a bird feeds."),
		Pdf.figure(
			plates,
			"Three bird silhouettes on tinted cards, drawn to scale. Left: a black-and-white oystercatcher with a long straight orange-red bill and pink legs. Centre: a small pale plover with a rust cap and a short bill. Right: a large brown curlew with a very long down-curved bill.",
			Pdf.caption("Figure 2. Plates to scale: pied oystercatcher, red-capped plover, and Far Eastern curlew"),
		),
		divider,
		Pdf.section([
			Pdf.destination_heading("oystercatcher", 2, "Pied oystercatcher"),
			Pdf.rich_paragraph([
				Pdf.text("A bold black-and-white wader that feeds in pairs across the open flats. Its all-black cousin, the sooty oystercatcher, prefers rocky shores. Compare the "),
				Pdf.inline_internal_link([Pdf.text("curlew")], "curlew"),
				Pdf.text(", which shares the flats but probes deeper."),
			]),
			id_list(
				[Pdf.text("42 to 50 cm; the largest black-and-white bird on the flats.")],
				[Pdf.text("long straight "), Pdf.emphasis([Pdf.text("orange-red")]), Pdf.text(" bill, red eye-ring, pink legs.")],
				[Pdf.text("a loud, piping "), Pdf.quote([Pdf.text("“kleep kleep”")]), Pdf.text(" when disturbed.")],
			),
		]),
		divider,
		Pdf.section([
			Pdf.destination_heading("plover", 2, "Red-capped plover"),
			Pdf.rich_paragraph([
				Pdf.text("A tiny, fast-running plover that nests in a bare scrape on the upper beach. Eggs and chicks are almost invisible against the sand, so follow the "),
				Pdf.inline_internal_link([Pdf.text("field etiquette")], "survey"),
				Pdf.text(" closely during the nesting season."),
			]),
			id_list(
				[Pdf.text("14 to 16 cm; smaller than a sparrow.")],
				[Pdf.text("pale grey-brown above, white below; adult males have a "), Pdf.emphasis([Pdf.text("rufous")]), Pdf.text(" cap and a dark bar across the shoulder.")],
				[Pdf.text("a thin, sharp "), Pdf.quote([Pdf.text("“tik”")]), Pdf.text(" as it runs ahead of you.")],
			),
		]),
		divider,
		Pdf.section([
			Pdf.destination_heading("curlew", 2, "Far Eastern curlew"),
			Pdf.rich_paragraph([
				Pdf.text("The world's largest shorebird, and an endangered migrant that flies from breeding grounds in Siberia each September. It is wary: record it from a distance and never approach a roost. Unlike the "),
				Pdf.inline_internal_link([Pdf.text("oystercatcher")], "oystercatcher"),
				Pdf.text(", it feeds alone."),
			]),
			id_list(
				[Pdf.text("53 to 66 cm; the bill alone can reach 18 cm.")],
				[Pdf.text("streaked brown all over, with a very long "), Pdf.emphasis([Pdf.text("down-curved")]), Pdf.text(" bill.")],
				[Pdf.text("a mournful, rising "), Pdf.quote([Pdf.text("“cur-lee”")]), Pdf.text(" carried across the water.")],
			),
		]),
	]),
	Pdf.section([
		Pdf.keep_with_next(Required, Pdf.destination_heading("survey", 1, "Running a survey")),
		Pdf.rich_paragraph([
			Pdf.text("Counts are held on the second Sunday of each month, starting one hour before high tide. Enter your results in the national database with the site code "),
			Pdf.code("DERW-04"),
			Pdf.text(", or send your sheet to the survey coordinator."),
		]),
		Pdf.numbered_list(
			{ start: 1, style: Decimal },
			[
				Pdf.list_item([Pdf.paragraph("Note the time, the tide height, the weather, and any disturbance.")]),
				Pdf.list_item([
					Pdf.paragraph("Scan the roost from one end to the other, counting in blocks of ten:"),
					Pdf.bullet_list([
						Pdf.list_item([Pdf.paragraph("count the large species first,")]),
						Pdf.list_item([Pdf.paragraph("then sweep again for the small ones.")]),
					]),
				]),
				Pdf.list_item([Pdf.paragraph("Record colour-banded birds with the band colours, top to bottom, left leg first.")]),
				Pdf.list_item([Pdf.paragraph("Enter a zero for every species you looked for and did not find.")]),
			],
		),
		etiquette,
	]),
	Pdf.section([
		Pdf.keep_with_next(Required, Pdf.destination_heading("checklist", 1, "Survey checklist")),
		Pdf.rich_paragraph([
			Pdf.text("The species most often recorded on the estuary. Status follows the national threatened species list; see "),
			Pdf.inline_link([Pdf.text("the Atlas of Living Australia")], "https://www.ala.org.au/"),
			Pdf.text(" for maps and records."),
		]),
		checklist,
	]),
]
