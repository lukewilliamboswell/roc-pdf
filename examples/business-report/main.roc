app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "fonts/SourceSans3-Regular.ttf" as regular_bytes : List(U8)
import "fonts/SourceSans3-Bold.ttf" as bold_bytes : List(U8)
import "fonts/SourceSans3-It.ttf" as italic_bytes : List(U8)
import "fonts/SourceCodePro-Regular.ttf" as code_bytes : List(U8)
import "drying-yard.jpg" as drying_photo : List(U8)

## The reference business report (docs/reference-documents.md): a navy
## cover band with the reversed mark, numbered sections that are outline
## and link destinations, rich inline content with expansions, a French
## quotation, and code, nested lists, a separately authored "Key figures"
## callout through the custom-block seam, a captioned vector bar chart
## with real text labels and a captioned JPEG photograph, shaded and
## ruled tables, and a 40-row supplier register that continues across
## pages with its header row repeated. Continuation pages carry a running
## header inset above a hairline.
main! = |_args| {
	fonts = register_fonts({})?
	options : Pdf.Options
	options = { theme: theme(fonts), fonts: Registered(fonts.registry) }
	document = Pdf.document({
		contents,
		language: "en-AU",
		title: "Harbour & Finch quarterly operations report, Q1 FY2027",
		page_templates: Templates(templates),
		outline,
		created: Explicit("2026-10-12T00:00:00Z"),
		modified: Explicit("2026-10-12T00:00:00Z"),
	})
	bytes = Pdf.to_bytes_with(document, options).map_err(|err| PdfFailed(err))?
	output : Path
	output = "business-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote business-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

Faces : { bold : Font.FaceId, code : Font.FaceId, italic : Font.FaceId, regular : Font.FaceId, registry : Font.Registry }

## Source Sans 3 Regular, Bold, and Italic and Source Code Pro Regular,
## each retained byte-for-byte from its upstream release in `fonts/`
## beside this file.
register_fonts : {} -> Try(Faces, [FontRejected(Font.ResourceError)])
register_fonts = |_| {
	latin : List(Font.Script)
	latin = ["Latn"]
	add = |registry, bytes| registry.register(bytes, { provision: BuiltIn, scripts: latin }, Font.ValidationLimits.default).map_err(|err| FontRejected(err))
	regular = add(Font.Registry.empty, regular_bytes)?
	bold = add(regular.registry, bold_bytes)?
	italic = add(bold.registry, italic_bytes)?
	code = add(italic.registry, code_bytes)?
	Ok({ bold: bold.face, code: code.face, italic: italic.face, regular: regular.face, registry: code.registry })
}

navy : Color.SourceValue
navy = "#183454"

brass : Color.SourceValue
brass = "#C49640"

slate : Color.SourceValue
slate = "#8C9BAD"

oak : Color.SourceValue
oak = "#BE8440"

ink : Color.SourceValue
ink = "#22282F"

grid : Color.SourceValue
grid = "#DCE2E9"

white : Color.SourceValue
white = "#FFFFFF"

## A4 with 48 pt top and bottom and 56 pt side margins: a 483 × 746 pt
## body. Regular for body text; Bold for the title, headings, and
## `Pdf.strong`; Italic for `Pdf.emphasis`; and Source Code Pro for
## `Pdf.code`, scaled to the body.
theme : Faces -> Theme
theme = |faces| {
	face: faces.regular,
	body: { color: ink, size: 10.5, leading: 15 },
	title: { color: navy, face: Face(faces.bold), size: 28, leading: 34 },
	headings: {
		all: { color: navy, face: Face(faces.bold), size: 16, leading: 21 },
		h2: Own({ color: "#2E5A87", face: Face(faces.bold), size: 12.5, leading: 17 }),
	},
	inline: {
		strong: { color: Themed(navy), font: Face(faces.bold) },
		emphasis: { font: Face(faces.italic) },
		code: { color: Themed("#8A4B14"), font: Face(faces.code), scale: Percent(90) },
	},
	page_margin: { top: 48, right: 56, bottom: 48, left: 56 },
	link: { color: Themed("#1F6F8B"), underline: Underline({ offset: 1.5, thickness: 0.5 }) },
	table: {
		header_color: Themed(navy),
		header_fill: Fill("#E6ECF3"),
		row_header_color: Themed(navy),
		body_fills: { even: Fill("#F6F8FA") },
		body_rule: Rule({ color: grid, width: 0.5 }),
		footer_fill: Fill("#F7F1E6"),
		rule: Rule({ color: navy, width: 1 }),
		cell_padding: 5,
		row_gap: 3,
	},
}

## `Page N of M` in 50 pt: in Source Sans 3 at 10.5 pt, `Page 9 of 9` is
## 47.229 pt.
page_field : Pdf.Inline
page_field = Pdf.reserved_width(50, End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

## The Harbour & Finch mark in reverse, 72 × 24 pt: a brass-winged tile
## beside three bars, for the navy cover band.
reverse_mark : Scene.Drawing
reverse_mark = {
	wing = Scene.PathBuilder.start
		.move_to(Layout.point(4, 6))
		.cubic_to({ control_1: Layout.point(8, 18), control_2: Layout.point(15, 20), end: Layout.point(20, 19) })
		.cubic_to({ control_1: Layout.point(15, 16), control_2: Layout.point(11, 11), end: Layout.point(4, 6) })
		.close()
		.finish()
	Scene.Drawing.empty
		.rectangle(Layout.rect(0, 0, 24, 24), "#2A4F7A")
		.path(wing, Scene.solid_fill(brass))
		.rectangle(Layout.rect(30, 15, 42, 4), white)
		.rectangle(Layout.rect(30, 9, 32, 3), white)
		.rectangle(Layout.rect(30, 4, 22, 2), brass)
}

## The first page's cover band: a navy field over a brass keyline, the
## full 483 pt width, with the reversed mark at its end.
cover_band : Scene.Drawing
cover_band = Scene.Drawing.empty
	.rectangle(Layout.rect(0, 4, 483, 32), navy)
	.rectangle(Layout.rect(0, 0, 483, 2), brass)
	.group(Layout.point(399, 8), reverse_mark)

## A 0.6 pt hairline the full width of the body, `y` points up.
hairline : I64 -> Scene.Drawing
hairline = |y| Scene.Drawing.empty.rectangle({ origin: Layout.point(0, y), size: { height: 0.6, width: 483 } }, "#B8C2CE")

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	footer = Pdf.region({
		height: 20,
		start: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd · Operations")])],
		end: [Pdf.furniture_text([page_field])],
		backdrop: Backdrop(hairline(19)),
		slot_inset: 5,
	})
	{
		first: Pdf.first_page_template({ header: Pdf.region({ height: 36, backdrop: Backdrop(cover_band) }), footer, gap: 14 }),
		continuation: Pdf.page_template({
			header: Pdf.region({
				height: 21,
				start: [Pdf.furniture_text([Pdf.text("Quarterly operations report · Q1 FY2027")])],
				end: [Pdf.furniture_text([Pdf.text("Harbour & Finch")])],
				backdrop: Backdrop(hairline(0)),
				slot_inset: 4,
			}),
			footer,
			gap: 14,
		}),
	}
}

outline : List(Document.OutlineEntry)
outline = [
	{ depth: 0, destination: "summary", open: True, title: "1 Summary" },
	{ depth: 0, destination: "sales", open: True, title: "2 Sales performance" },
	{ depth: 0, destination: "supply-chain", open: True, title: "3 Supply chain" },
	{ depth: 1, destination: "freight", open: True, title: "3.1 Freight" },
	{ depth: 1, destination: "timber", open: True, title: "3.2 Timber sourcing" },
	{ depth: 0, destination: "outlook", open: True, title: "4 Outlook" },
	{ depth: 0, destination: "appendix-a", open: True, title: "Appendix A. Supplier register" },
]

## ---------------------------------------------------------------------
## A "key figures" callout through the custom-block seam, measured by the
## extension itself: each figure is one paragraph (its label in `Strong`)
## that fits one line of the body style inside the panel, so the height is
## twice the inset plus one leading per figure and the paragraph spacing
## between them. The package lays the paragraphs out and proves they fit.

key_figures : Document.Block
key_figures = {
	figures = [("Revenue", "AUD 9.22 m (+5.0%)"), ("On-time delivery", "96.4%"), ("Certified timber", "88%")]
	leading = 15000
	spacing = 8000
	count = figures.len().to_i64_wrap()
	size = { height: Layout.Unit.from_raw(inset.raw() * 2 + leading * count + spacing * (count - 1)), width: 483 }
	Pdf.custom_block({
		contents: figures.map(|(label, value)| Pdf.rich_paragraph([Pdf.strong([Pdf.text("${label}:")]), Pdf.text(" ${value}")])),
		inset: inset,
		name: "Key figures",
		panel: panel(size),
		size,
	})
}

## Content sits 10 pt inside the panel on every side.
inset : Layout.Unit
inset = 10

## A rounded rectangle filling the measured box, with a 1 pt outline kept
## inside it (the stroke's half width is the path's margin), and a 4 pt
## accent bar along its start edge between the corners.
panel : Layout.Size -> Scene.Drawing
panel = |size| {
	half = 500
	r = 6000
	k = r * 552 // 1000
	left = half
	bottom = half
	right = size.width.raw() - half
	top = size.height.raw() - half
	point = |x, y| { x: Layout.Unit.from_raw(x), y: Layout.Unit.from_raw(y) }
	outline_path = Scene.PathBuilder.start
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
	bar = Scene.PathBuilder.start.rectangle({ origin: point(left, bottom + r), size: { height: Layout.Unit.from_raw(top - bottom - 2 * r), width: 4 } }).finish()
	Scene.Drawing.empty
		.path(outline_path, { fill: AuthorSolidFill("#F7F1E6"), stroke: AuthorSolidStroke({ color: "#DCC69A", width: 1 }) })
		.path(bar, Scene.solid_fill(navy))
}

figure1 : Document.Block
figure1 = Pdf.figure({ drawing: bar_chart, alt: figure1_alt, caption: Pdf.caption("Figure 1. Revenue by region, AUD thousands") })

figure1_alt : Str
figure1_alt = "Bar chart comparing revenue by region for Q1 FY2026 and Q1 FY2027. Queensland grew most, by 15.4%; New South Wales fell by 2.1%. Values are given in Table 1."

## Revenue by region (Q1 FY2026, Q1 FY2027) in AUD thousands.
revenue : List({ after : I64, before : I64, region : Str })
revenue = [
	{ region: "Tasmania", before: 1284, after: 1412 },
	{ region: "Victoria", before: 2905, after: 3118 },
	{ region: "New South Wales", before: 3462, after: 3390 },
	{ region: "Queensland", before: 1127, after: 1301 },
]

## The plotted height of `value` thousand above the axis.
plotted : I64 -> I64
plotted = |value| value * 160 // 4000

## A number with a thousands separator, such as `3,462`.
thousands : I64 -> Str
thousands = |value| if value >= 1000 {
	rest = value % 1000
	pad = if rest < 10 "00" else if rest < 100 "0" else ""
	"${(value // 1000).to_str()},${pad}${rest.to_str()}"
} else {
	value.to_str()
}

## A legend key: a swatch and its name.
key : Scene.Drawing, I64, Color.SourceValue, Str -> Scene.Drawing
key = |drawing, x, color, name| drawing.rectangle(Layout.rect(x, 205, 10, 8), color).text({ color: ink, origin: Layout.point(x + 14, 206), size: 8.5, text: name })

## Figure 1: paired bars per region over a gridded axis in AUD thousands,
## each bar labelled with its value, the regions named under their pairs,
## and a legend naming the two quarters.
bar_chart : Scene.Drawing
bar_chart = {
	left = 44
	base = 30
	var $chart = Scene.Drawing.empty
	for step in [1, 2, 3, 4] {
		$chart = $chart.rectangle({ origin: Layout.point(left, base + plotted(step * 1000)), size: { height: 0.5, width: Layout.Unit.points(483 - left) } }, grid)
	}
	for step in [0, 1, 2, 3, 4] {
		value = step.to_i64_wrap() * 1000
		$chart = $chart.text({ align: End, color: ink, origin: Layout.point(left - 6, base - 3 + plotted(value)), size: 8, text: thousands(value) })
	}
	slot = (483 - left) // 4
	var $index = 0
	for { region, before, after } in revenue {
		x = left + $index * slot + (slot - 80) // 2
		$chart = $chart
			.rectangle(Layout.rect(x, base, 38, plotted(before)), slate)
			.rectangle(Layout.rect(x + 42, base, 38, plotted(after)), oak)
			.text({ align: Center, color: ink, origin: Layout.point(x + 19, base + plotted(before) + 4), size: 7.5, text: thousands(before) })
			.text_in(Strong, { align: Center, color: ink, origin: Layout.point(x + 61, base + plotted(after) + 4), size: 7.5, text: thousands(after) })
			.text({ align: Center, color: ink, origin: Layout.point(x + 40, 12), size: 9, text: region })
		$index = $index + 1
	}
	$chart = $chart.path(Scene.PathBuilder.start.move_to(Layout.point(left, base)).line_to(Layout.point(482, base)).finish(), Scene.solid_stroke(ink, 1))
	$chart = $chart.text({ color: ink, origin: Layout.point(0, 206), size: 8.5, text: "AUD thousands" })
	$chart = key($chart, 330, slate, "Q1 FY2026")
	key($chart, 408, oak, "Q1 FY2027")
}

region_row : Str, Str, Str, Str -> Pdf.Row
region_row = |region, before, after, change| Pdf.row([Pdf.header_cell(Row, [Pdf.text(region)]), Pdf.cell([Pdf.text(before)]), Pdf.cell([Pdf.text(after)]), Pdf.cell([Pdf.text(change)])])

revenue_table : Document.Block
revenue_table = Pdf.table({
	caption: Pdf.caption("Table 1. Revenue by region, AUD thousands"),
	columns: [{ width: Content, align: Start }, { width: Share(1), align: End }, { width: Share(1), align: End }, { width: Share(1), align: End }],
	header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Region")]), Pdf.header_cell(Column, [Pdf.text("Q1 FY2026")]), Pdf.header_cell(Column, [Pdf.text("Q1 FY2027")]), Pdf.header_cell(Column, [Pdf.text("Change")])])],
	body_rows: [
		region_row("Tasmania", "1,284", "1,412", "+10.0%"),
		region_row("Victoria", "2,905", "3,118", "+7.3%"),
		region_row("New South Wales", "3,462", "3,390", "−2.1%"),
		region_row("Queensland", "1,127", "1,301", "+15.4%"),
	],
	footer_rows: [region_row("Total", "8,778", "9,221", "+5.0%")],
})

suppliers : List({ category : Str, location : Str, name : Str })
suppliers = [
	{ name: "Derwent Valley Sawmills", location: "New Norfolk TAS", category: "Timber" },
	{ name: "Huon Pine Traders", location: "Huonville TAS", category: "Timber" },
	{ name: "Tamar Joinery Supplies", location: "Launceston TAS", category: "Hardware" },
	{ name: "Kestrel Steelworks", location: "Fremantle WA", category: "Steel" },
	{ name: "Moonah Kiln Services", location: "Moonah TAS", category: "Services" },
	{ name: "Southern Cross Castors", location: "Dandenong VIC", category: "Hardware" },
	{ name: "Bass Strait Freight", location: "Devonport TAS", category: "Freight" },
	{ name: "Atelier Beaulieu", location: "Lyon, France", category: "Timber" },
	{ name: "Gippsland Veneers", location: "Morwell VIC", category: "Timber" },
	{ name: "Riverina Oils", location: "Wagga Wagga NSW", category: "Finishes" },
]

## Register row `index`: ten suppliers, each with up to four sites.
supplier_row : U64 -> Pdf.Row
supplier_row = |index| {
	supplier = match suppliers.get(index % 10) {
		Ok(value) => value
		Err(OutOfBounds) => crash "supplier index escaped"
	}
	site = index // 10
	name = if index == 7 {
		Pdf.in_language("fr", [Pdf.text(supplier.name)])
	} else if site == 0 {
		Pdf.text(supplier.name)
	} else {
		Pdf.text("${supplier.name} (site ${(site + 1).to_str()})")
	}
	Pdf.row([
		Pdf.header_cell(Row, [name]),
		Pdf.cell([Pdf.text(supplier.location)]),
		Pdf.cell([Pdf.text(supplier.category)]),
		Pdf.cell([Pdf.text((120 + (index * 37) % 400).to_str())]),
		Pdf.cell([Pdf.text(if index % 5 == 3 "No" else "Yes")]),
	])
}

supplier_table : Document.Block
supplier_table = {
	var $rows = List.with_capacity(40)
	var $index = 0
	while $index < 40 {
		$rows = $rows.append(supplier_row($index))
		$index = $index + 1
	}
	Pdf.table({
		caption: Pdf.caption("Table 2. Active suppliers at 30 September 2026"),
		columns: [
			{ width: Share(4), align: Start },
			{ width: Share(3), align: Start },
			{ width: Share(2), align: Start },
			{ width: Fixed(80), align: End },
			{ width: Fixed(56), align: Center },
		],
		header_rows: [
			Pdf.row([
				Pdf.header_cell(Column, [Pdf.text("Supplier")]),
				Pdf.header_cell(Column, [Pdf.text("Location")]),
				Pdf.header_cell(Column, [Pdf.text("Category")]),
				Pdf.header_cell(Column, [Pdf.text("Spend (AUD thousands)")]),
				Pdf.header_cell(Column, [Pdf.text("Certified")]),
			]),
		],
		body_rows: $rows,
	})
}

contents : List(Document.Block)
contents = [
	Pdf.title("Quarterly operations report"),
	Pdf.rich_paragraph([
		Pdf.text("Q1 "),
		Pdf.expansion("FY2027", "financial year 2027"),
		Pdf.text(": July to September 2026 · Prepared by the Operations team, 12 October 2026"),
	]),
	Pdf.section([
		Pdf.destination_heading("summary", 1, "1 Summary"),
		Pdf.rich_paragraph([
			Pdf.text("Revenue rose "),
			Pdf.strong([Pdf.text("5.0%")]),
			Pdf.text(" to AUD 9.22 million, led by "),
			Pdf.emphasis([Pdf.text("Queensland")]),
			Pdf.text(". Freight costs fell for the second quarter; see "),
			Pdf.inline_internal_link([Pdf.text("section 3, Supply chain")], "supply-chain"),
			Pdf.text("."),
		]),
		Pdf.bullet_list([
			Pdf.list_item([Pdf.paragraph("On-time delivery reached 96.4%.")]),
			Pdf.list_item([
				Pdf.paragraph("Timber purchasing moved further toward certified sources:"),
				Pdf.bullet_list([
					Pdf.list_item([Pdf.paragraph("88% of oak by volume is certified.")]),
					Pdf.list_item([Pdf.paragraph("All veneer suppliers are now audited annually.")]),
				]),
			]),
			Pdf.list_item([Pdf.paragraph("Warranty claims fell to 0.6% of units shipped.")]),
		]),
		key_figures,
	]),
	Pdf.section([
		Pdf.destination_heading("sales", 1, "2 Sales performance"),
		Pdf.rich_paragraph([
			Pdf.text("Table 1 compares revenue by region with the same quarter last year. Revenue is reported excluding "),
			Pdf.expansion("GST", "Goods and Services Tax"),
			Pdf.text("."),
		]),
		revenue_table,
		figure1,
	]),
	Pdf.section([
		Pdf.destination_heading("supply-chain", 1, "3 Supply chain"),
		Pdf.paragraph("Freight and timber sourcing both improved this quarter. The two subsections below summarise the changes and the suppliers involved."),
		Pdf.section([
			Pdf.destination_heading("freight", 2, "3.1 Freight"),
			Pdf.paragraph("Consolidated sailings across Bass Strait reduced the number of part-loaded containers by a third. Average freight cost per shipped unit fell from AUD 41.20 to AUD 37.85."),
			Pdf.rich_paragraph([
				Pdf.text("Pick lists now come directly from the warehouse system "),
				Pdf.code("WMS-7"),
				Pdf.text(", which removed a manual re-keying step and halved picking errors at the Moonah yard."),
			]),
		]),
		Pdf.section([
			Pdf.destination_heading("timber", 2, "3.2 Timber sourcing"),
			Pdf.rich_paragraph([
				Pdf.text("Our partner "),
				Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
				Pdf.text(" puts it simply: "),
				Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois demande de la patience. »")])]),
				Pdf.text(" (“Timber asks for patience.”)"),
			]),
			Pdf.figure({ drawing: Scene.Drawing.empty.image(Image.Source.jpeg_srgb(drying_photo, RequireDisplayReady), Layout.rect(0, 0, 483, 260)), alt: "Stacked Tasmanian oak boards air-drying under cover at the Moonah yard.", caption: Pdf.caption("Figure 2. Air drying at the Moonah yard") }),
		]),
	]),
	Pdf.section([
		Pdf.destination_heading("outlook", 1, "4 Outlook"),
		Pdf.rich_paragraph([
			Pdf.text("Next quarter's priorities follow "),
			Pdf.inline_link([Pdf.text("our published sustainability commitments")], "https://www.harbourfinch.example/sustainability"),
			Pdf.text("."),
		]),
		Pdf.numbered_list(
			{},
			[
				Pdf.list_item([Pdf.paragraph("Commission the third kiln chamber at Moonah by November.")]),
				Pdf.list_item([
					Pdf.paragraph("Extend certified sourcing to every timber category:"),
					Pdf.bullet_list([
						Pdf.list_item([Pdf.paragraph("audit the remaining two veneer mills;")]),
						Pdf.list_item([Pdf.paragraph("require chain-of-custody records for recovered oak.")]),
					]),
				]),
				Pdf.list_item([Pdf.paragraph("Hold on-time delivery above 96% through the December peak.")]),
			],
		),
	]),
	Pdf.section([
		Pdf.destination_heading("appendix-a", 1, "Appendix A. Supplier register"),
		Pdf.paragraph("The register lists every supplier active at the end of the quarter, with spend in the quarter and certification status."),
		supplier_table,
	]),
]
