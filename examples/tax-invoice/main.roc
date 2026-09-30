app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst",
	pdf: "../../package/main.roc",
}
import pf.Path
import pf.Stdout
import pdf.Color
import pdf.Document
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme

## The reference multi-page tax invoice (docs/reference-documents.md):
## first-page and continuation templates with a vector logo and exact
## `Page N of M` fields, a key/value details table, and a 32-row items
## table with a repeated header row, end-aligned amounts, and a totals
## group that keeps with the last body row. The document is prepared once
## and then emitted.
main! = |_args| {
	document = Pdf.document({ contents, language: "en-AU", title: "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd" })
		.with_page_templates(templates)
		.with_created("2026-09-14T00:00:00Z")
		.with_modified("2026-09-14T00:00:00Z")
	prepared = Pdf.prepare(document, Pdf.Options.default.with_theme(theme)).map_err(|err| PdfFailed(err))?
	bytes = Pdf.to_bytes_prepared(prepared).map_err(|err| EmitFailed(err))?
	output : Path
	output = "tax-invoice.pdf"
	output.write_bytes!(bytes).map_err(|err| WriteFailed(err))?
	Stdout.line!("Wrote tax-invoice.pdf").map_err(|err| OutputFailed(err))?
	Ok({})
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

navy : Color.SourceValue
navy = Color.srgb8({ red: 24, green: 52, blue: 84 })

brass : Color.SourceValue
brass = Color.srgb8({ red: 196, green: 150, blue: 64 })

## A4 with 48 pt top and bottom and 56 pt side margins: a 483 × 746 pt body.
theme : Theme
theme = Theme.default
	.with_page_margin({ top: points(48), right: points(56), bottom: points(48), left: points(56) })
	.with_title_color(navy)
	.with_heading_color(navy)
	.with_strong_color(navy)

## The Harbour & Finch mark, 132 × 44 pt: a navy tile holding a brass
## finch's wing, beside three navy bars.
logo : Scene.Drawing
logo = {
	wing = Scene.path({})
		.move_to(Layout.point(8, 12))
		.cubic_to({ control_1: Layout.point(16, 34), control_2: Layout.point(30, 38), end: Layout.point(38, 36) })
		.cubic_to({ control_1: Layout.point(30, 30), control_2: Layout.point(22, 20), end: Layout.point(8, 12) })
		.close()
		.finish()
	tile = Scene.rectangle(Scene.drawing({}), Layout.rect(0, 0, 44, 44), navy).path(wing, Scene.solid_fill(brass))
	bars = Scene.rectangle(Scene.rectangle(tile, Layout.rect(54, 28, 78, 8), navy), Layout.rect(54, 16, 60, 6), navy)
	Scene.rectangle(bars, Layout.rect(54, 6, 40, 4), brass)
}

page_of : Pdf.Inline
page_of = Pdf.reserved_width(points(64), End, [Pdf.text("Page "), Pdf.page_number(Decimal), Pdf.text(" of "), Pdf.total_pages(Decimal)])

footer : Pdf.Region
footer = Pdf.region({
	height: points(16),
	start: [Pdf.furniture_text([Pdf.text("ABN 00 123 456 789 · Tax invoice HF-2026-0417")])],
	center: [],
	end: [Pdf.furniture_text([page_of])],
})

templates : { continuation : Pdf.PageTemplate, first : Pdf.FirstPageTemplate }
templates = {
	first: Pdf.first_page_template({
		header: Pdf.region({ height: points(44), start: [Pdf.furniture_image(logo)], center: [], end: [] }),
		lead: Pdf.no_lead,
		footer,
		gap: points(12),
	}),
	continuation: Pdf.page_template({
		header: Pdf.region({ height: points(16), start: [Pdf.furniture_text([Pdf.text("Harbour & Finch Pty Ltd — Tax invoice HF-2026-0417 (continued)")])], center: [], end: [] }),
		footer,
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

## The eight products once for each fit-out site, levels 2 to 5.
item_rows : List(Pdf.Row)
item_rows = ["2", "3", "4", "5"].map(
	|site| {
		products.map(
			|product| Pdf.row([
				Pdf.header_cell(Row, [Pdf.text("${product.code}/L${site}")]),
				Pdf.cell(product.description.append(Pdf.text(" (Level ${site})"))),
				Pdf.cell([Pdf.text(product.quantity)]),
				Pdf.cell([Pdf.text(product.price)]),
				Pdf.cell([Pdf.text(product.amount)]),
			]),
		)
	},
).join()

total_row : Str, List(Pdf.Inline) -> Pdf.Row
total_row = |label, amount| Pdf.row([Pdf.aligned(End, Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.text(label)]))), Pdf.cell(amount)])

detail_row : Str, Str -> Pdf.Row
detail_row = |label, value| Pdf.row([Pdf.header_cell(Row, [Pdf.text(label)]), Pdf.cell([Pdf.text(value)])])

contents : List(Document.Block)
contents = [
	Pdf.division([
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
	]),
	Pdf.title("Tax invoice"),
	Pdf.table({
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
	}),
	Pdf.section([
		Pdf.heading(1, "Bill to"),
		Pdf.rich_paragraph([
			Pdf.text("Northstar Cooperative Ltd"),
			Pdf.line_break,
			Pdf.text("Attn: Accounts Payable"),
			Pdf.line_break,
			Pdf.text("42 Kestrel Parade"),
			Pdf.line_break,
			Pdf.text("Fremantle WA 6160"),
		]),
	]),
	Pdf.section([
		Pdf.heading(1, "Items"),
		Pdf.table({
			caption: Pdf.caption("Items supplied under purchase order PO 88213"),
			columns: [
				{ width: Content, align: Start },
				{ width: Share(1), align: Start },
				{ width: Fixed(points(36)), align: End },
				{ width: Fixed(points(72)), align: End },
				{ width: Fixed(points(80)), align: End },
			],
			header_rows: [
				Pdf.row([
					Pdf.header_cell(Column, [Pdf.text("Code")]),
					Pdf.header_cell(Column, [Pdf.text("Description")]),
					Pdf.header_cell(Column, [Pdf.text("Qty")]),
					Pdf.header_cell(Column, [Pdf.text("Unit price (AUD)")]),
					Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")]),
				]),
			],
			body_rows: item_rows,
			footer_rows: [
				total_row("Subtotal (excl. GST)", [Pdf.text("40,116.40")]),
				total_row("GST (10%)", [Pdf.text("4,011.64")]),
				total_row("Total due (AUD)", [Pdf.strong([Pdf.text("44,128.04")])]),
			],
			row_split: KeepRows,
		}),
	]),
	Pdf.section([
		Pdf.heading(1, "Payment"),
		Pdf.paragraph("Please pay by 14 October 2026. Bank transfer: BSB 000-000, account 1234 5678, reference HF-2026-0417."),
		Pdf.rich_paragraph([
			Pdf.text("You can also "),
			Pdf.inline_link([Pdf.text("pay invoice HF-2026-0417 online")], "https://pay.harbourfinch.example/invoices/HF-2026-0417"),
			Pdf.text(" (pay.harbourfinch.example/invoices/HF-2026-0417)."),
		]),
	]),
]
