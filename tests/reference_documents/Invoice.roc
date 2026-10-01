import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## The reference multi-page tax invoice (docs/reference-documents.md),
## authored through the public `Pdf` constructors exactly as
## `examples/tax-invoice/main.roc` authors it, with the knobs its adverse
## variants change. `ordinary` produces the gallery invoice byte for byte.
Invoice :: [].{
	Arrangement : [Ordinary, KeepItemsWithPayment, BreakInsideKeep]

	Config : {
		arrangement : Arrangement,
		bill_to : List(Str),
		columns : List(Pdf.Column),
		field_width : I64,
		row : U64 -> Pdf.Row,
		row_split : Pdf.RowSplit,
		rows : U64,
		totals : Bool,
	}

	ordinary : Config
	ordinary = {
		arrangement: Ordinary,
		bill_to: ["Northstar Cooperative Ltd", "Attn: Accounts Payable", "42 Kestrel Parade", "Fremantle WA 6160"],
		columns: item_columns,
		field_width: 64,
		row: item_row,
		row_split: KeepRows,
		rows: 32,
		totals: True,
	}

	theme : Theme
	theme = invoice_theme

	options : Pdf.Options
	options = Pdf.Options.{ theme: invoice_theme }

	## Body row `index`: the eight products once per fit-out site.
	item_row : U64 -> Pdf.Row
	item_row = |index| row_with(index, product_description(index), product_code(index))

	## Body row `index` with its description replaced.
	row_with : U64, List(Pdf.Inline), Str -> Pdf.Row
	row_with = |index, description, code| {
		product = product_at(index)
		Pdf.row([
			Pdf.header_cell(Row, [Pdf.text(code)]),
			Pdf.cell(description),
			Pdf.cell([Pdf.text(product.quantity)]),
			Pdf.cell([Pdf.text(product.price)]),
			Pdf.cell([Pdf.text(product.amount)]),
		])
	}

	product_code : U64 -> Str
	product_code = |index| "${product_at(index).code}/L${site_of(index)}"

	product_description : U64 -> List(Pdf.Inline)
	product_description = |index| product_at(index).description.append(Pdf.text(" (Level ${site_of(index)})"))

	document : Config -> Document
	document = |config| {
		var $rows = List.with_capacity(config.rows)
		var $index = 0
		while $index < config.rows {
			$rows = $rows.append((config.row)($index))
			$index = $index + 1
		}
		items = items_section(config, $rows)
		payment = payment_section
		tail = match config.arrangement {
			Ordinary => [items, payment]
			KeepItemsWithPayment => [Pdf.keep_together([items, payment])]
			BreakInsideKeep => [Pdf.keep_together([bill_to_section(config.bill_to), Pdf.page_break, items]), payment]
		}
		head = match config.arrangement {
			BreakInsideKeep => [supplier_block, Pdf.title("Tax invoice"), details_table]
			_ => [supplier_block, Pdf.title("Tax invoice"), details_table, bill_to_section(config.bill_to)]
		}
		Pdf.document({ contents: head.concat(tail), language: "en-AU", title: "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd" })
			.with_page_templates(templates(config.field_width))
			.with_created("2026-09-14T00:00:00Z")
			.with_modified("2026-09-14T00:00:00Z")
	}
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

navy : Color.SourceValue
navy = Color.srgb8({ red: 24, green: 52, blue: 84 })

brass : Color.SourceValue
brass = Color.srgb8({ red: 196, green: 150, blue: 64 })

invoice_theme : Theme
invoice_theme = Theme.{ headings: { all: { color: navy } }, inline: { strong: { color: Themed(navy) } }, page_margin: { top: points(48), right: points(56), bottom: points(48), left: points(56) }, title: { color: navy } }

logo : Scene.Drawing
logo = {
	wing = Scene.PathBuilder.start
		.move_to(Layout.point(8, 12))
		.cubic_to({ control_1: Layout.point(16, 34), control_2: Layout.point(30, 38), end: Layout.point(38, 36) })
		.cubic_to({ control_1: Layout.point(30, 30), control_2: Layout.point(22, 20), end: Layout.point(8, 12) })
		.close()
		.finish()
	tile = Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 44, 44), navy).path(wing, Scene.solid_fill(brass))
	bars = tile.rectangle(Layout.rect(54, 28, 78, 8), navy).rectangle(Layout.rect(54, 16, 60, 6), navy)
	bars.rectangle(Layout.rect(54, 6, 40, 4), brass)
}

## `Page N of M` end-aligned in `width` points: 64 pt holds one-digit
## totals (`Page 9 of 9` is 60.0 pt) and 80 pt two-digit ones.
page_of : I64 -> Pdf.Inline
page_of = |width| Pdf.reserved_width(points(width), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : I64 -> Pdf.Region
footer = |width| Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("ABN 00 123 456 789 · Tax invoice HF-2026-0417")])],
	center: [],
	end: [Pdf.furniture_text([page_of(width)])],
})

templates : I64 -> { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = |width| {
	first: Pdf.first_page_template({
		header: Pdf.region({ height: points(44), start: [Pdf.furniture_image(logo)], center: [], end: [] }),
		lead: Pdf.no_lead,
		footer: footer(width),
		gap: points(12),
	}),
	continuation: Pdf.page_template({
		header: Pdf.region({ height: points(16), start: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd — Tax invoice HF-2026-0417 (continued)")])], center: [], end: [] }),
		footer: footer(width),
		gap: points(12),
	}),
}

products : List({ code : Str, description : List(Pdf.Inline), quantity : Str, price : Str, amount : Str })
products = [
	{ code: "HF-DSK-140", description: [Pdf.text("Standing desk frame, twin motor, 1400 mm")], quantity: "4", price: "689.00", amount: "2,756.00" },
	{ code: "HF-TOP-OAK", description: [Pdf.text("Tasmanian oak desktop, 1400 × 700 mm, oiled")], quantity: "4", price: "412.50", amount: "1,650.00" },
	{ code: "HF-CHR-ERG", description: [Pdf.text("Ergonomic task chair, mesh back, adjustable lumbar support")], quantity: "6", price: "529.00", amount: "3,174.00" },
	{ code: "HF-CAF-ELG", description: [Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")]), Pdf.text(", 1 L, for the staff kitchen")], quantity: "2", price: "64.95", amount: "129.90" },
	{ code: "HF-LMP-LED", description: [Pdf.text("LED task lamp, 4000 K, clamp mount")], quantity: "6", price: "118.00", amount: "708.00" },
	{ code: "HF-CBL-TRY", description: [Pdf.text("Under-desk cable tray, powder-coated steel")], quantity: "8", price: "36.40", amount: "291.20" },
	{ code: "HF-INS-HRS", description: [Pdf.text("Installation labour (hours)")], quantity: "12", price: "95.00", amount: "1,140.00" },
	{ code: "HF-DEL-MET", description: [Pdf.text("Metropolitan delivery, Hobart")], quantity: "1", price: "180.00", amount: "180.00" },
]

product_at : U64 -> { code : Str, description : List(Pdf.Inline), quantity : Str, price : Str, amount : Str }
product_at = |index| match products.get(index % 8) {
	Ok(value) => value
	Err(OutOfBounds) => crash "invoice product index escaped"
}

## Sites cycle through levels 2 to 5, eight rows each.
site_of : U64 -> Str
site_of = |index| (2 + (index // 8) % 4).to_str()

item_columns : List(Pdf.Column)
item_columns = [
	{ width: Content, align: Start },
	{ width: Share(1), align: Start },
	{ width: Fixed(points(36)), align: End },
	{ width: Fixed(points(72)), align: End },
	{ width: Fixed(points(80)), align: End },
]

total_row : Str, List(Pdf.Inline) -> Pdf.Row
total_row = |label, amount| Pdf.row([Pdf.header_cell(Row, [Pdf.text(label)]).spanning(4).aligned(End), Pdf.cell(amount)])

detail_row : Str, Str -> Pdf.Row
detail_row = |label, value| Pdf.row([Pdf.header_cell(Row, [Pdf.text(label)]), Pdf.cell([Pdf.text(value)])])

supplier_block : Document.Block
supplier_block = Pdf.division([
	Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
	Pdf.rich_paragraph([
		Pdf.text("Level 3, 18 Wharf Street"),
		Pdf.line_break,
		Pdf.text("Hobart TAS 7000"),
		Pdf.line_break,
		Pdf.text("ABN 00 123 456 789"),
		Pdf.line_break,
		Pdf.text("accounts@harbourfinch.example · (03) 5550 0142"),
	]),
])

details_table : Document.Block
details_table = Pdf.table({
	caption: Pdf.no_caption,
	columns: [{ width: Content, align: Start }, { width: Share(1), align: Start }],
	header_rows: [],
	body_rows: [
		detail_row("Invoice number", "HF-2026-0417"),
		detail_row("Issue date", "14 September 2026"),
		detail_row("Due date", "14 October 2026"),
		detail_row("Customer reference", "PO 88213"),
	],
	footer_rows: [],
	row_split: KeepRows,
})

## The Bill-to section: one paragraph with a line break between lines.
bill_to_section : List(Str) -> Document.Block
bill_to_section = |lines| {
	var $inlines = List.with_capacity(lines.len() * 2)
	for line in lines {
		$inlines = if $inlines.is_empty() $inlines.append(Pdf.text(line)) else $inlines.append(Pdf.line_break).append(Pdf.text(line))
	}
	Pdf.section([Pdf.heading(1, "Bill to"), Pdf.rich_paragraph($inlines)])
}

items_section : Invoice.Config, List(Pdf.Row) -> Document.Block
items_section = |config, rows| Pdf.section([
	Pdf.heading(1, "Items"),
	Pdf.table({
		caption: Pdf.caption("Items supplied under purchase order PO 88213"),
		columns: config.columns,
		header_rows: [
			Pdf.row([
				Pdf.header_cell(Column, [Pdf.text("Code")]),
				Pdf.header_cell(Column, [Pdf.text("Description")]),
				Pdf.header_cell(Column, [Pdf.text("Qty")]),
				Pdf.header_cell(Column, [Pdf.text("Unit price (AUD)")]),
				Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")]),
			]),
		],
		body_rows: rows,
		footer_rows: if config.totals {
			[
				total_row("Subtotal (excl. GST)", [Pdf.text("40,116.40")]),
				total_row("GST (10%)", [Pdf.text("4,011.64")]),
				total_row("Total due (AUD)", [Pdf.strong([Pdf.text("44,128.04")])]),
			]
		} else {
			[]
		},
		row_split: config.row_split,
	}),
])

payment_section : Document.Block
payment_section = Pdf.section([
	Pdf.heading(1, "Payment"),
	Pdf.paragraph("Please pay by 14 October 2026. Bank transfer: BSB 000-000, account 1234 5678, reference HF-2026-0417."),
	Pdf.rich_paragraph([
		Pdf.text("You can also "),
		Pdf.inline_link([Pdf.text("pay invoice HF-2026-0417 online")], "https://pay.harbourfinch.example/invoices/HF-2026-0417"),
		Pdf.text(" (pay.harbourfinch.example/invoices/HF-2026-0417)."),
	]),
])
