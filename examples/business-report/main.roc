app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## The reference business report (docs/reference-documents.md): numbered
## sections that are outline and link destinations, rich inline content
## with expansions, a French quotation and code, nested lists, a
## separately authored "Key figures" callout through the custom-block
## seam, a captioned vector bar chart and a captioned JPEG photograph, and
## a 40-row supplier register that continues across pages with its header
## row repeated. Continuation pages carry a running header and rule.
main! = |_args| {
	document = Pdf.document({ contents, language: "en-AU", title: "Harbour & Finch quarterly operations report, Q1 FY2027" })
		.with_page_templates(templates)
		.with_outline(outline)
		.with_created("2026-10-12T00:00:00Z")
		.with_modified("2026-10-12T00:00:00Z")
	bytes = Pdf.to_bytes_with(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	output : Path
	output = "business-report.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote business-report.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

navy : Color.SourceValue
navy = Color.srgb8({ red: 24, green: 52, blue: 84 })

slate : Color.SourceValue
slate = Color.srgb8({ red: 128, green: 146, blue: 166 })

oak : Color.SourceValue
oak = Color.srgb8({ red: 190, green: 132, blue: 64 })

ink : Color.SourceValue
ink = Color.srgb8({ red: 40, green: 40, blue: 40 })

## A4 with 48 pt top and bottom and 56 pt side margins: a 483 × 746 pt body.
theme : Theme
theme = Theme.default
	.with_page_margin({ top: points(48), right: points(56), bottom: points(48), left: points(56) })
	.with_title_color(navy)
	.with_heading_color(navy)
	.with_strong_color(navy)
	.with_code_color(Color.srgb8({ red: 120, green: 60, blue: 20 }))

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({ height: points(16), start: [], center: [], end: [Pdf.furniture_text([page_of])] })

## A full-width 0.5 pt rule under the running header.
rule : Scene.Drawing
rule = Scene.rectangle(Scene.drawing({}), { origin: Layout.point(0, 0), size: { height: Layout.Unit.millipoints(500), width: points(483) } }, slate)

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({ header: Pdf.no_region, lead: Pdf.no_lead, footer, gap: points(12) }),
	continuation: Pdf.page_template({
		header: Pdf.region({ height: points(24), start: [Pdf.furniture_text([Pdf.text("Quarterly operations report · Q1 FY2027")]), Pdf.furniture_image(rule)], center: [], end: [] }),
		footer,
		gap: points(12),
	}),
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
## The "Key figures" callout: a separately authored custom block. It
## measures itself from the theme's public metrics (one body line per
## figure, paragraph spacing between them, a 10 pt inset) and paints a
## tinted rounded panel behind its paragraphs. The package lays the
## paragraphs out and proves they fit the measured box.

callout_inset : Layout.Unit
callout_inset = points(10)

key_figures : List(Str), Layout.Unit -> Document.Block
key_figures = |lines, width| {
	leading = Theme.body_style(theme).leading.raw()
	spacing = Theme.paragraph_spacing(theme).raw()
	count = lines.len().to_i64_wrap()
	size = { height: Layout.Unit.from_raw(callout_inset.raw() * 2 + leading * count + spacing * (count - 1)), width }
	Pdf.custom_block({
		contents: lines.map(|line| Pdf.paragraph(line)),
		fragmentation: Unsplittable,
		inset: callout_inset,
		name: "Key figures",
		panel: callout_panel(size),
		size,
	})
}

## A rounded rectangle filling the measured box, with a 1 pt outline kept
## inside it.
callout_panel : Layout.Size -> Scene.Drawing
callout_panel = |size| {
	half = 500
	r = 6000
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
	fill = Color.srgb8({ red: 236, green: 244, blue: 250 })
	stroke = Color.srgb8({ red: 150, green: 170, blue: 190 })
	Scene.drawing({}).path(outline_path, { fill: AuthorSolidFill(fill), stroke: AuthorSolidStroke({ color: stroke, width: points(1) }) })
}

## ---------------------------------------------------------------------
## Figure 1: paired bars per region, an axis, gridlines, and tick labels
## drawn as seven-segment vector digits (values in AUD thousands).

## The rectangles of one seven-segment digit, 5 × 9 pt from its origin.
digit : U64 -> Scene.Drawing
digit = |value| {
	segments = if value == 0 {
		[(0, 8, 5, 1), (4, 4, 1, 5), (4, 0, 1, 5), (0, 0, 5, 1), (0, 0, 1, 5), (0, 4, 1, 5)]
	} else if value == 1 {
		[(4, 4, 1, 5), (4, 0, 1, 5)]
	} else if value == 2 {
		[(0, 8, 5, 1), (4, 4, 1, 5), (0, 4, 5, 1), (0, 0, 1, 5), (0, 0, 5, 1)]
	} else if value == 3 {
		[(0, 8, 5, 1), (4, 4, 1, 5), (0, 4, 5, 1), (4, 0, 1, 5), (0, 0, 5, 1)]
	} else {
		[(0, 4, 1, 5), (0, 4, 5, 1), (4, 4, 1, 5), (4, 0, 1, 5)]
	}
	var $drawing = Scene.drawing({})
	for (x, y, w, h) in segments {
		$drawing = Scene.rectangle($drawing, Layout.rect(x, y, w, h), ink)
	}
	$drawing
}

## A tick label for `lead` thousand: its digits end at `x`, bottom at `y`.
tick_label : Scene.Drawing, U64, I64, I64 -> Scene.Drawing
tick_label = |drawing, lead, x, y| {
	digits = if lead == 0 [0] else [lead, 0, 0, 0]
	var $drawing = drawing
	var $at = x - 7 * digits.len().to_i64_wrap()
	for value in digits {
		$drawing = $drawing.group(Layout.point($at, y), digit(value))
		$at = $at + 7
	}
	$drawing
}

## Revenue by region (Q1 FY2026, Q1 FY2027) in AUD thousands.
revenue : List((I64, I64))
revenue = [(1284, 1412), (2905, 3118), (3462, 3390), (1127, 1301)]

## The plotted height of `value` thousand above the axis.
plotted : I64 -> I64
plotted = |value| value * 186 // 4000

bar_chart : Scene.Drawing
bar_chart = {
	base : I64
	base = 24
	var $chart = Scene.drawing({})
	for step in [1, 2, 3, 4] {
		$chart = Scene.rectangle($chart, { origin: Layout.point(40, base + plotted(step * 1000)), size: { height: Layout.Unit.millipoints(500), width: points(440) } }, slate)
	}
	$chart = $chart
		.path(Scene.path({}).move_to(Layout.point(40, base)).line_to(Layout.point(480, base)).finish(), Scene.solid_stroke(ink, points(1)))
		.path(Scene.path({}).move_to(Layout.point(40, base)).line_to(Layout.point(40, base + 196)).finish(), Scene.solid_stroke(ink, points(1)))
	for lead in [0, 1, 2, 3, 4] {
		$chart = tick_label($chart, lead, 34, base - 4 + plotted(lead.to_i64_wrap() * 1000))
	}
	var $x = 72
	for (before, after) in revenue {
		$chart = Scene.rectangle(Scene.rectangle($chart, Layout.rect($x, base, 36, plotted(before)), slate), Layout.rect($x + 40, base, 36, plotted(after)), oak)
		$x = $x + 108
	}

	## A legend under the axis: the earlier quarter in slate, the later in oak.
	Scene.rectangle(Scene.rectangle($chart, Layout.rect(380, 4, 12, 8), slate), Layout.rect(420, 4, 12, 8), oak)
}

## ---------------------------------------------------------------------
## Figure 2: a caller-supplied baseline sRGB JPEG (128 × 69 pixels) of
## stacked boards drying under a roof.
drying_photo : List(U8)
drying_photo = hex_bytes(
	Str.join_with(
		[
			"ffd8ffe000104a46494600010100000100010000ffdb0043000a07070807060a0808080b0a0a0b0e18100e0d0d0e1d15",
			"161118231f2524221f2221262b372f26293429212230413134393b3e3e3e252e4449433c48373d3e3bffdb0043010a0b",
			"0b0e0d0e1c10101c3b2822283b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b",
			"3b3b3b3b3b3b3b3b3b3b3b3b3b3bffc00011080045008003012200021101031101ffc4001b0000020301010100000000",
			"0000000000000003020507040601ffc4003e100001030202030a0c060301000000000001000203041105d11221541315",
			"16314151529193a30622263442717292a1a2a4b21423325361813362b1c1ffc400190101000301010000000000000000",
			"000000000102050304ffc40023110002010206030101000000000000000000011102f00312132151a141617132d1ffda",
			"000c03010002110311003f00f7365c18863786e172b62acaa11bdcdd20dd12e36e7d5c4a58d62f060b87baa65b39e7c5",
			"8a3beb7bb9bd5ceb2babab9ebaaa4aaa8797cb21bb8ffe7a976391a3f0bb02dbbba7e48e17605b7774fc9667ad163cc5",
			"44930699c2ec0b6eee9f92385d816dddd3f2599d8f31458f314910699c2ec0b6eee9f92385d816dddd3f2599d8f31458",
			"f314910699c2ec0b6eee9f92385d816dddd3f2599d8f31458f314910699c2ec0b6eee9f92385d816dddd3f2599d8f314",
			"58f314910699c2ec0b6eee9f92385d816dddd3f2599d8f3146b49106ad87e398662933a1a3aa1248d6e916e8969b7f63",
			"5ab0b2c7a96aa6a2aa8ea69de592c6ed26b82d4f03c621c6f0f6d44766c8df1658effa1d9732920b32c0ee3683eb1754",
			"78631a7c2ac6868b6c1b0f27faabfb2a3c2c79598e7b307daa1f82508c5cc7154cae167b85bf29a3c63a87f5f1490d87",
			"688ba8e49f8cc6d755cdb9ddb36ab39dadbc43938fe291b9d35bf44bef8c96362c6a55f7d9ab87391068c3b445d4ec94",
			"267451c4e7b5ed948f4180dcf58014f73a6e84bef8c94268a3313841a4d9390bce90ea002e7b5c97dee09e8c3b445d47",
			"2468c3b445d4ec91b9d37425f7c648dce9ba12fbe3253b7aec8dee084ce8a388bdaf6cc47a0c06e7ac00a7a30dbce22e",
			"a76497345198888349b272179d21d40053dce9ba12fbe3251b5c93bdc1f7461da22ea764a133a28e22f6b9b291e8301b",
			"9eb0029ee74dd097df1925cd14662220d26c9c85e7487500136b91bdc0cb436f388ba8e49b8618df89866ab3789c46a7",
			"ea3c5eafe6c95b9d35bf44bef8c93b0a8dadc55a75e8dff2c728d46f73cbf05d30e33d3f7d94ae723f83315634784f81",
			"8d16eb74dc9feaaf0303789a07a8595362c3ca8c0bda9bed57965b2bc994c9d9516163cadc73d983ed5e82ca870a1e57",
			"e3becc1f6a3f011cb8f1904f3ee80c7078b7940d1b717a5ebfe5281aeb6aa6ee064ba31b7323ab99da42470d1fca68f1",
			"8ea1cfabe2b9c08ade771fcd92c8c46f3bfe9a787f85fc3edebf66fa7192455baa0533ff0010c30c5ab49e19b9db5f4a",
			"da93ad16d71fcd925cee8e385ce12b6623d060373d6005ce5db2fb5a180d7585a9be9c648bd7ecdf4e3240115bcee3f9",
			"b245a2dae3f9b2532ed885684d59a814cffc430c316ad27866e76d7d2b6a4e06bac2d4df4e32509dd1c70b9c256cc47a",
			"0c06e7ac00a768b6b8fe6c944bb636b417afd9be9c6493566a0533ff0010c30c5aaef0cdcedafa56164eb45b5c7f3649",
			"73ba38e1739b2b6623d060373d6004976c42b4301aeb0b537d38c93308321c68820e9eadd5b6fd1a8db57a37f8a5da2b",
			"79dc7f3649f84b98ec5dac0e1e29d4eb6a9351e2f57f3657c36f3d3f792b5fe1fce0762e3ca9c07da9bed57b65498b8f",
			"2ab00f6a6fb55f596c2f265b276541850f2c31ef660fb5799e15e37b6f76dc973c38ee2505654564753a33d4e8895da0",
			"df1b44586ab6a5c9e2a2f919e971d8d8ead9f73bb66f16ce71bb7887271fc572ee74b6ff001cdda0c9533fc20c4a5797",
			"c92c6f71e3261613ff0017cdfcafe9c5d83325e1af09d55373d1eca7152a5282ef73a4fdb9bb41925cd144e89c200f64",
			"9c864707347f400551bf95fd38bb06648dfcafe9c5d833255d17cf45b59705d08e939639bb4192fbb9d27edcdda0c952",
			"6fe57f4e2ec199237f2bfa71760cc9345f3d0d65c16f3451189c200f649c86470701fd003fea66e749cb1cdda0c9526f",
			"e57f4e2ec199237f2bfa71760cc9345f3d0d65c177b9d27edcdda0c92e68a23138401ec9390c8e0e03fa007fd551bf95",
			"fd38bb06648dfcafe9c5d83324d17cf4359705d88e92dae39bb4192e8c1e368c61aed7a04fe58beb6ea37b9e5f82f39b",
			"fb8874e2ec1992facf083128de1f1cb1b5c388885808f82b5384d549cf456ac54e96a0f598c0f2afc1ff006a7fb15fd9",
			"665363b895455d3d5cb53a535317189da0d1a37163aadad7470af1bdb7bb6e4bdfaa8f1e465421085e73a82108400842",
			"100210840084210021084008421002108407ffd9",
		],
		"",
	),
)

## Decodes pairs of lowercase hexadecimal digits.
hex_bytes : Str -> List(U8)
hex_bytes = |text| {
	digits = Str.to_utf8(text)
	nibble = |c| if c >= 97 c - 87 else c - 48
	var $bytes = List.with_capacity(digits.len() // 2)
	var $index = 0
	while $index + 1 < digits.len() {
		high = match digits.get($index) {
			Ok(c) => nibble(c)
			Err(OutOfBounds) => 0
		}
		low = match digits.get($index + 1) {
			Ok(c) => nibble(c)
			Err(OutOfBounds) => 0
		}
		$bytes = $bytes.append(high * 16 + low)
		$index = $index + 2
	}
	$bytes
}

## ---------------------------------------------------------------------

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
	row_split: KeepRows,
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
			{ width: Share(3), align: Start },
			{ width: Share(2), align: Start },
			{ width: Share(2), align: Start },
			{ width: Fixed(points(80)), align: End },
			{ width: Fixed(points(56)), align: Center },
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
		footer_rows: [],
		row_split: KeepRows,
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
		key_figures(["Revenue: AUD 9.22 m (+5.0%)", "On-time delivery: 96.4%", "Certified timber: 88%"], points(483)),
	]),
	Pdf.section([
		Pdf.destination_heading("sales", 1, "2 Sales performance"),
		Pdf.rich_paragraph([
			Pdf.text("Table 1 compares revenue by region with the same quarter last year. Revenue is reported excluding "),
			Pdf.expansion("GST", "Goods and Services Tax"),
			Pdf.text("."),
		]),
		revenue_table,
		Pdf.figure(
			bar_chart,
			"Bar chart comparing revenue by region for Q1 FY2026 and Q1 FY2027. Queensland grew most, by 15.4%; New South Wales fell by 2.1%. Values are given in Table 1.",
			Pdf.caption("Figure 1. Revenue by region, AUD thousands"),
		),
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
			Pdf.figure(
				Scene.drawing({}).image(Image.Source.jpeg_srgb(drying_photo, RequireDisplayReady), Layout.rect(0, 0, 483, 260)),
				"Stacked Tasmanian oak boards air-drying under cover at the Moonah yard.",
				Pdf.caption("Figure 2. Air drying at the Moonah yard"),
			),
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
			{ start: 1, style: Decimal },
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
