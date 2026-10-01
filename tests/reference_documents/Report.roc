import Callout
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.Image
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../../examples/business-report/fonts/SourceSans3-Regular.ttf" as regular_bytes : List(U8)
import "../../examples/business-report/fonts/SourceSans3-Bold.ttf" as bold_bytes : List(U8)
import "../../examples/business-report/fonts/SourceSans3-It.ttf" as italic_bytes : List(U8)
import "../../examples/business-report/fonts/SourceCodePro-Regular.ttf" as code_bytes : List(U8)
import "../../examples/business-report/drying-yard.jpg" as drying_photo : List(U8)

## The reference business report (docs/reference-documents.md), authored
## through the public `Pdf` constructors exactly as
## `examples/business-report/main.roc` authors it (its "Key figures" callout
## through the separately authored `Callout` extension), with the knobs
## its adverse variants change. `ordinary` produces the gallery report
## byte for byte.
Report :: [].{
	Config : {
		before_figure1 : List(Document.Block),
		before_sales : List(Document.Block),
		before_table1 : List(Document.Block),
		callout : Document.Block,
		figure1 : Document.Block,
		figure2_alternative : Str,
		freight_level : U8,
		summary_link : Str,
		timber_extra : List(Pdf.Inline),
	}

	Faces : { bold : Font.FaceId, code : Font.FaceId, italic : Font.FaceId, regular : Font.FaceId, registry : Font.Registry }

	ordinary : Config
	ordinary = {
		before_figure1: [],
		before_sales: [],
		before_table1: [],
		callout: key_figures,
		figure1: figure1,
		figure2_alternative: "Stacked Tasmanian oak boards air-drying under cover at the Moonah yard.",
		freight_level: 2,
		summary_link: "supply-chain",
		timber_extra: [],
	}

	## Source Sans 3 Regular, Bold, and Italic and Source Code Pro
	## Regular, each retained byte-for-byte from its upstream release in
	## `examples/business-report/fonts/`. `guard` is a runtime zero, so
	## registration runs when the case runs and never at compile time.
	register : U64 -> Try(Faces, [RegistrationFailed])
	register = |guard| {
		limits = Font.ValidationLimits.make({ max_bytes: 2000000 + guard, max_cmap_mappings: 1200000, max_glyphs: 65535, max_tables: 128 })
		latin : List(Font.Script)
		latin = ["Latn"]
		regular = Font.Registry.empty.register(regular_bytes, { provision: BuiltIn, scripts: latin }, limits) ? |_| RegistrationFailed
		bold = regular.registry.register(bold_bytes, { provision: BuiltIn, scripts: latin }, limits) ? |_| RegistrationFailed
		italic = bold.registry.register(italic_bytes, { provision: BuiltIn, scripts: latin }, limits) ? |_| RegistrationFailed
		code = italic.registry.register(code_bytes, { provision: BuiltIn, scripts: latin }, limits) ? |_| RegistrationFailed
		Ok({ bold: bold.face, code: code.face, italic: italic.face, regular: regular.face, registry: code.registry })
	}

	## The report's regular face bytes, for a caller-assembled registry
	## (REP-A5's ordered policy).
	regular_face_bytes : List(U8)
	regular_face_bytes = regular_bytes

	theme : Faces -> Theme
	theme = |faces| report_theme(faces.regular, { bold: Face(faces.bold), italic: Face(faces.italic), code: Face(faces.code) })

	## The report theme over one face with no title, heading, or inline
	## role faces, for an ordered font policy whose faces cover every
	## cluster (REP-A5).
	single_face_theme : Font.FaceId -> Theme
	single_face_theme = |face| report_theme(face, { bold: ThemeFace, italic: Inherited, code: Inherited })

	options : Faces -> Pdf.Options
	options = |faces| { theme: theme(faces), fonts: Registered(faces.registry) }

	## Figure 1 of the ordinary report.
	chart_figure : Document.Block
	chart_figure = figure1

	## The bar chart drawing of Figure 1 (483 × 220 pt).
	chart : Scene.Drawing
	chart = bar_chart

	## Figure 1 with its bars, grid, and legend swatches but no text
	## labels. Under an ordered font policy drawing labels have no face
	## (`text.drawing_label_policy`), so REP-A5 places this figure; its
	## alternative text and caption still carry what the chart shows.
	unlabelled_chart_figure : Document.Block
	unlabelled_chart_figure = Pdf.figure({ drawing: chart_drawing(Unlabelled), alt: figure1_alt, caption: Pdf.caption("Figure 1. Revenue by region, AUD thousands") })

	## The report's frame, templates, and metadata around arbitrary
	## contents, without the outline (placement controls and probes).
	framed : List(Document.Block) -> Document
	framed = |contents| Pdf.document({
		contents,
		language: "en-AU",
		title: "Harbour & Finch quarterly operations report, Q1 FY2027",
		page_templates: Templates(templates(50)),
		created: Explicit("2026-10-12T00:00:00Z"),
		modified: Explicit("2026-10-12T00:00:00Z"),
	})

	document : Config -> Document
	document = |config| Pdf.document({
		contents: contents(config),
		language: "en-AU",
		title: "Harbour & Finch quarterly operations report, Q1 FY2027",
		page_templates: Templates(templates(50)),
		outline: outline(config.freight_level),
		created: Explicit("2026-10-12T00:00:00Z"),
		modified: Explicit("2026-10-12T00:00:00Z"),
	})

	## The report-sections scale workload: `count` sections, each an `H1`
	## destination, three paragraphs, a four-row table, and an internal
	## link to the next section, each with an outline entry. The footer's
	## page field has `field_width` points (`Page 100 of 100` needs about
	## 72 pt; below 50 pt only the page number is reserved). With
	## `breaks`, every section after the first starts a new page (REP-A4).
	sections_document : U64, I64, Bool -> Document
	sections_document = |count, field_width, breaks| {
		var $contents = List.with_capacity(count * 2 + 1)
		var $entries = List.with_capacity(count)
		$contents = $contents.append(Pdf.title("Quarterly operations report"))
		var $index = 0
		while $index < count {
			number = ($index + 1).to_str()
			name = "section-${number}"
			next = if $index + 1 < count "section-${($index + 2).to_str()}" else "section-1"
			if breaks and $index > 0 {
				$contents = $contents.append(Pdf.page_break)
			}
			$contents = $contents.append(
				Pdf.section([
					Pdf.destination_heading(name, 1, "${number} Operations area ${number}"),
					Pdf.paragraph("Area ${number} shipped on time in every week of the quarter. Freight costs per unit fell again as consolidated sailings replaced part-loaded containers across Bass Strait."),
					Pdf.paragraph("Timber purchasing for area ${number} moved further toward certified sources, and the Moonah kilns dried every delivery to the agreed moisture content before it left the yard."),
					Pdf.rich_paragraph([Pdf.text("Warranty claims stayed below one percent of units shipped. Continue to "), Pdf.inline_internal_link([Pdf.text("the next operations area")], next), Pdf.text(".")]),
					area_table($index),
				]),
			)
			$entries = $entries.append({ depth: 0, destination: name, open: True, title: "${number} Operations area ${number}" })
			$index = $index + 1
		}
		Pdf.document({
			contents: $contents,
			language: "en-AU",
			title: "Harbour & Finch quarterly operations report, Q1 FY2027",
			page_templates: Templates(templates(field_width)),
			outline: $entries,
			created: Explicit("2026-10-12T00:00:00Z"),
			modified: Explicit("2026-10-12T00:00:00Z"),
		})
	}
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
## body. `face` sets body text; `roles` are the Bold face of the title,
## headings, and `Pdf.strong`, the Italic face of `Pdf.emphasis`, and the
## monospace face of `Pdf.code`, scaled to the body.
report_theme : Font.FaceId, { bold : Theme.FaceChoice, code : Theme.InlineFont, italic : Theme.InlineFont } -> Theme
report_theme = |face, roles| {
	face,
	body: { color: ink, size: 10.5, leading: 15 },
	title: { color: navy, face: roles.bold, size: 28, leading: 34 },
	headings: {
		all: { color: navy, face: roles.bold, size: 16, leading: 21 },
		h2: Own({ color: "#2E5A87", face: roles.bold, size: 12.5, leading: 17 }),
	},
	inline: {
		strong: { color: Themed(navy), font: bold_font(roles.bold) },
		emphasis: { font: roles.italic },
		code: { color: Themed("#8A4B14"), font: roles.code, scale: code_scale(roles.code) },
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

## The Strong role takes the Bold face whenever the title and headings do.
bold_font : Theme.FaceChoice -> Theme.InlineFont
bold_font = |choice| match choice {
	Face(face) => Face(face)
	ThemeFace => Inherited
}

## Code is set at 90% of the body size whenever it has its own face.
code_scale : Theme.InlineFont -> Theme.InlineScale
code_scale = |font| match font {
	Face(_) => Percent(90)
	Inherited => Inherited
}

## `Page N of M` in a reserved width: in Source Sans 3 at 10.5 pt, 50 pt
## holds one-digit totals (`Page 9 of 9` is 47.229 pt). Below 50 pt
## (REP-A4) only the page number is reserved; its two-digit values are
## 10.437 pt and its three-digit values 15.656 pt.
page_field : I64 -> Pdf.Inline
page_field = |width| if width >= 50 {
	Pdf.reserved_width(Layout.Unit.points(width), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])
} else {
	Pdf.reserved_width(Layout.Unit.points(width), End, [Pdf.page_number(Decimal)])
}

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

templates : I64 -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = |field_width| {
	footer = Pdf.region({
		height: 20,
		start: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd · Operations")])],
		end: [Pdf.furniture_text([page_field(field_width)])],
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

outline : U8 -> List(Document.OutlineEntry)
outline = |freight_level| [
	{ depth: 0, destination: "summary", open: True, title: "1 Summary" },
	{ depth: 0, destination: "sales", open: True, title: "2 Sales performance" },
	{ depth: 0, destination: "supply-chain", open: True, title: "3 Supply chain" },
	{ depth: (freight_level - 1).to_u64(), destination: "freight", open: True, title: "3.1 Freight" },
	{ depth: 1, destination: "timber", open: True, title: "3.2 Timber sourcing" },
	{ depth: 0, destination: "outlook", open: True, title: "4 Outlook" },
	{ depth: 0, destination: "appendix-a", open: True, title: "Appendix A. Supplier register" },
]

## The callout's figures. Its height is measured from the theme's body
## metrics, which every face choice of the report shares.
key_figures : Document.Block
key_figures = Callout.key_figures(report_theme(Font.FaceId.from_index(0), { bold: ThemeFace, italic: Inherited, code: Inherited }), { figures: [("Revenue", "AUD 9.22 m (+5.0%)"), ("On-time delivery", "96.4%"), ("Certified timber", "88%")], name: "Key figures", width: 483 })

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
bar_chart = chart_drawing(Labelled)

## The chart, with or without its text labels.
chart_drawing : [Labelled, Unlabelled] -> Scene.Drawing
chart_drawing = |labels| {
	left = 44
	base = 30
	labelled = labels == Labelled
	var $chart = Scene.Drawing.empty
	for step in [1, 2, 3, 4] {
		$chart = $chart.rectangle({ origin: Layout.point(left, base + plotted(step * 1000)), size: { height: 0.5, width: Layout.Unit.points(483 - left) } }, grid)
	}
	if labelled {
		for step in [0, 1, 2, 3, 4] {
			value = step.to_i64_wrap() * 1000
			$chart = $chart.text({ align: End, color: ink, origin: Layout.point(left - 6, base - 3 + plotted(value)), size: 8, text: thousands(value) })
		}
	}
	slot = (483 - left) // 4
	var $index = 0
	for { region, before, after } in revenue {
		x = left + $index * slot + (slot - 80) // 2
		$chart = $chart
			.rectangle(Layout.rect(x, base, 38, plotted(before)), slate)
			.rectangle(Layout.rect(x + 42, base, 38, plotted(after)), oak)
		if labelled {
			$chart = $chart
				.text({ align: Center, color: ink, origin: Layout.point(x + 19, base + plotted(before) + 4), size: 7.5, text: thousands(before) })
				.text_in(Strong, { align: Center, color: ink, origin: Layout.point(x + 61, base + plotted(after) + 4), size: 7.5, text: thousands(after) })
				.text({ align: Center, color: ink, origin: Layout.point(x + 40, 12), size: 9, text: region })
		}
		$index = $index + 1
	}
	$chart = $chart.path(Scene.PathBuilder.start.move_to(Layout.point(left, base)).line_to(Layout.point(482, base)).finish(), Scene.solid_stroke(ink, 1))
	if labelled {
		$chart = $chart.text({ color: ink, origin: Layout.point(0, 206), size: 8.5, text: "AUD thousands" })
		$chart = key($chart, 330, slate, "Q1 FY2026")
		key($chart, 408, oak, "Q1 FY2027")
	} else {
		$chart.rectangle(Layout.rect(330, 205, 10, 8), slate).rectangle(Layout.rect(408, 205, 10, 8), oak)
	}
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

## A four-row table of the sections workload.
area_table : U64 -> Document.Block
area_table = |index| {
	number = (index + 1).to_str()
	Pdf.table({
		caption: Pdf.caption("Table ${number}. Area ${number} deliveries"),
		columns: [{ width: Content, align: Start }, { width: Share(1), align: End }, { width: Share(1), align: End }],
		header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Month")]), Pdf.header_cell(Column, [Pdf.text("Orders")]), Pdf.header_cell(Column, [Pdf.text("On time")])])],
		body_rows: ["July", "August", "September", "Quarter"].map(|month| Pdf.row([Pdf.header_cell(Row, [Pdf.text(month)]), Pdf.cell([Pdf.text("${(40 + index % 17).to_str()}")]), Pdf.cell([Pdf.text("96.${(index % 10).to_str()}%")])])),
	})
}

contents : Report.Config -> List(Document.Block)
contents = |config| [
	[
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
				Pdf.inline_internal_link([Pdf.text("section 3, Supply chain")], config.summary_link),
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
			config.callout,
		]),
	],
	config.before_sales,
	[
		Pdf.section(
			[
				[
					Pdf.destination_heading("sales", 1, "2 Sales performance"),
					Pdf.rich_paragraph([
						Pdf.text("Table 1 compares revenue by region with the same quarter last year. Revenue is reported excluding "),
						Pdf.expansion("GST", "Goods and Services Tax"),
						Pdf.text("."),
					]),
				],
				config.before_table1,
				[revenue_table],
				config.before_figure1,
				[config.figure1],
			].join(),
		),
		Pdf.section([
			Pdf.destination_heading("supply-chain", 1, "3 Supply chain"),
			Pdf.paragraph("Freight and timber sourcing both improved this quarter. The two subsections below summarise the changes and the suppliers involved."),
			Pdf.section([
				Pdf.destination_heading("freight", config.freight_level, "3.1 Freight"),
				Pdf.paragraph("Consolidated sailings across Bass Strait reduced the number of part-loaded containers by a third. Average freight cost per shipped unit fell from AUD 41.20 to AUD 37.85."),
				Pdf.rich_paragraph([
					Pdf.text("Pick lists now come directly from the warehouse system "),
					Pdf.code("WMS-7"),
					Pdf.text(", which removed a manual re-keying step and halved picking errors at the Moonah yard."),
				]),
			]),
			Pdf.section([
				Pdf.destination_heading("timber", 2, "3.2 Timber sourcing"),
				Pdf.rich_paragraph(
					[
						Pdf.text("Our partner "),
						Pdf.in_language("fr", [Pdf.text("Atelier Beaulieu")]),
						Pdf.text(" puts it simply: "),
						Pdf.quote([Pdf.in_language("fr", [Pdf.text("« Le bois demande de la patience. »")])]),
						Pdf.text(" (“Timber asks for patience.”)"),
					].concat(config.timber_extra),
				),
				Pdf.figure({ drawing: Scene.Drawing.empty.image(Image.Source.jpeg_srgb(drying_photo, RequireDisplayReady), Layout.rect(0, 0, 483, 260)), alt: config.figure2_alternative, caption: Pdf.caption("Figure 2. Air drying at the Moonah yard") }),
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
	],
].join()
