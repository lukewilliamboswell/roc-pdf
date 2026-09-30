import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.KernelFacadeLines
import pdf.KernelFacadePages
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeTables
import pdf.KernelFacadeText
import pdf.KernelFont
import pdf.KernelLineLayout
import pdf.KernelPageLayout
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Theme
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## Ordinary tables through the public `Pdf` constructors.
##
## - `invoice xN`: the reference invoice's key/value details table (row
##   headers, no header rows) and its items table (caption, one column
##   header row, N body rows with row-header item codes and end-aligned
##   amounts, a French span, and three totals rows whose labels span four
##   columns and are end-aligned with `Pdf.aligned`),
##   continued across pages with the header row repainted as an artifact.
##   The 50/500 pair is the linear scale pair.
## - `spans`: a two-row header whose `Both`-scoped corner and spanning
##   `Column` header head the cells below them, a centered spanning data
##   cell, a
##   themed header color, and U+2212 minus signs in end-aligned cells.
## - `split_rows`: `SplitRows` with a row taller than the rest of its page:
##   the row breaks at a line boundary and continues under the repainted
##   header.
## - `footer_carry`: the totals group does not fit after the last body row,
##   so R3 carries that row to the next page with the totals.
## - `ordered`: numeric and spaced cells whose script stays Common under an
##   ordered Latin and Han policy, beside a Han span.
## - `atomic_negatives`: every table rejection with its stable dotted code
##   and authored path, and no bytes.
Fixture :: [].{
	EvidenceError : [EvidenceFailure, InvalidScale, MissingRejection(U64)]

	invoice : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice = |rows| {
		if rows == 0 or rows > 500 {
			return Err(InvalidScale)
		}
		evidence(invoice_document(rows), Theme.default, BuiltInFace)
	}

	spans : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	spans = |context| {
		blue : Color.SourceValue
		blue = Srgb(Rgb({ blue: 36000, green: 18000, red: 4000 }))
		evidence(spans_document(context), Theme.with_table_header_color(Theme.default, blue), BuiltInFace)
	}

	split_rows : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	split_rows = |context| evidence(split_document(context), Theme.default, BuiltInFace)

	footer_carry : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	footer_carry = |context| evidence(carry_document(context), Theme.default, BuiltInFace)

	ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	ordered = |context| {
		registered = register_faces(context)?
		evidence(ordered_document(context), Theme.with_font_policy(Theme.default, registered.policy), Policy(registered))
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |context| run_negatives(context)
}

Faces : [BuiltInFace, Policy({ policy : Font.PolicyId, registry : Font.Registry })]

## The reference invoice's eight products: code, description, quantity,
## unit price, and amount, all caller-formatted.
products : List({ amount : Str, code : Str, description : Str, price : Str, quantity : Str })
products = [
	{ amount: "2,756.00", code: "HF-DSK-140", description: "Standing desk frame, twin motor, 1400 mm", price: "689.00", quantity: "4" },
	{ amount: "1,650.00", code: "HF-TOP-OAK", description: "Tasmanian oak desktop, 1400 × 700 mm, oiled", price: "412.50", quantity: "4" },
	{ amount: "3,174.00", code: "HF-CHR-ERG", description: "Ergonomic task chair, mesh back, adjustable lumbar support", price: "529.00", quantity: "6" },
	{ amount: "129.90", code: "HF-CAF-ELG", description: "", price: "64.95", quantity: "2" },
	{ amount: "708.00", code: "HF-LMP-LED", description: "LED task lamp, 4000 K, clamp mount", price: "118.00", quantity: "6" },
	{ amount: "291.20", code: "HF-CBL-TRY", description: "Under-desk cable tray, powder-coated steel", price: "36.40", quantity: "8" },
	{ amount: "1,140.00", code: "HF-INS-HRS", description: "Installation labour (hours)", price: "95.00", quantity: "12" },
	{ amount: "180.00", code: "HF-DEL-MET", description: "Metropolitan delivery, Hobart", price: "180.00", quantity: "1" },
]

## Body row `index`: the products cycle once per fit-out site, and the
## Cafetière's name is a French span.
item_row : U64 -> Pdf.Row
item_row = |index| {
	product = match products.get(index % 8) {
		Ok(value) => value
		Err(OutOfBounds) => crash "invoice product index escaped"
	}
	site = 2 + (index // 8) % 4
	description = if product.description.is_empty() {
		[Pdf.in_language("fr", [Pdf.text("Cafetière « Élégance »")]), Pdf.text(", 1 L, for the staff kitchen (Level ${site.to_str()})")]
	} else {
		[Pdf.text("${product.description} (Level ${site.to_str()})")]
	}
	Pdf.row([
		Pdf.header_cell(Row, [Pdf.text("${product.code}/L${site.to_str()}")]),
		Pdf.cell(description),
		Pdf.cell([Pdf.text(product.quantity)]),
		Pdf.cell([Pdf.text(product.price)]),
		Pdf.cell([Pdf.text(product.amount)]),
	])
}

invoice_columns : List(Pdf.Column)
invoice_columns = [
	{ align: Start, width: Content },
	{ align: Start, width: Share(1) },
	{ align: End, width: Fixed(Layout.Unit.points(36)) },
	{ align: End, width: Fixed(Layout.Unit.points(72)) },
	{ align: End, width: Fixed(Layout.Unit.points(80)) },
]

invoice_header : Pdf.Row
invoice_header = Pdf.row([
	Pdf.header_cell(Column, [Pdf.text("Code")]),
	Pdf.header_cell(Column, [Pdf.text("Description")]),
	Pdf.header_cell(Column, [Pdf.text("Qty")]),
	Pdf.header_cell(Column, [Pdf.text("Unit price (AUD)")]),
	Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")]),
])

total_row : Str, List(Pdf.Inline) -> Pdf.Row
total_row = |label, amount| Pdf.row([Pdf.aligned(End, Pdf.spanning(4, Pdf.header_cell(Row, [Pdf.text(label)]))), Pdf.cell(amount)])

invoice_totals : List(Pdf.Row)
invoice_totals = [
	total_row("Subtotal (excl. GST)", [Pdf.text("40,116.40")]),
	total_row("GST (10%)", [Pdf.text("4,011.64")]),
	total_row("Total due (AUD)", [Pdf.strong([Pdf.text("44,128.04")])]),
]

items_table : List(Pdf.Row) -> Document.Block
items_table = |rows| Pdf.table({
	body_rows: rows,
	caption: Pdf.caption("Items supplied under purchase order PO 88213"),
	columns: invoice_columns,
	footer_rows: invoice_totals,
	header_rows: [invoice_header],
	row_split: KeepRows,
})

detail_row : Str, Str -> Pdf.Row
detail_row = |label, value| Pdf.row([Pdf.header_cell(Row, [Pdf.text(label)]), Pdf.cell([Pdf.text(value)])])

invoice_document : U64 -> Document
invoice_document = |count| {
	var $rows = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$rows = $rows.append(item_row($index))
		$index = $index + 1
	}
	Pdf.document({
		contents: [
			Pdf.division([
				Pdf.rich_paragraph([Pdf.strong([Pdf.text("Harbour & Finch Pty Ltd")])]),
				Pdf.rich_paragraph([Pdf.text("Level 3, 18 Wharf Street"), Pdf.line_break, Pdf.text("Hobart TAS 7000"), Pdf.line_break, Pdf.text("ABN 00 123 456 789")]),
			]),
			Pdf.title("Tax invoice"),
			Pdf.table({
				body_rows: [
					detail_row("Invoice number", "HF-2026-0417"),
					detail_row("Issue date", "14 September 2026"),
					detail_row("Due date", "14 October 2026"),
					detail_row("Customer reference", "PO 88213"),
				],
				caption: Pdf.no_caption,
				columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }],
				footer_rows: [],
				header_rows: [],
				row_split: KeepRows,
			}),
			Pdf.section([Pdf.heading(1, "Bill to"), Pdf.rich_paragraph([Pdf.text("Northstar Cooperative Ltd"), Pdf.line_break, Pdf.text("42 Kestrel Parade"), Pdf.line_break, Pdf.text("Fremantle WA 6160")])]),
			Pdf.section([Pdf.heading(1, "Items"), items_table($rows)]),
			Pdf.section([
				Pdf.heading(1, "Payment"),
				Pdf.paragraph("Please pay by 14 October 2026. Bank transfer: BSB 000-000, account 1234 5678, reference HF-2026-0417."),
			]),
		],
		language: "en-AU",
		title: "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd (${count.to_str()} rows)",
	})
}

region_row : Str, Str, Str, Str -> Pdf.Row
region_row = |region, before, after, change| Pdf.row([Pdf.header_cell(Row, [Pdf.text(region)]), Pdf.cell([Pdf.text(before)]), Pdf.cell([Pdf.text(after)]), Pdf.cell([Pdf.text(change)])])

spans_document : U64 -> Document
spans_document = |context| {
	suffix = if context == 0 "" else " (${context.to_str()})"
	Pdf.document({
		contents: [
			Pdf.heading(1, "2 Sales performance${suffix}"),
			Pdf.paragraph("Revenue by region, in AUD thousands, for the first quarter of each financial year."),
			Pdf.table({
				body_rows: [
					region_row("Tasmania", "1,284", "1,412", "+10.0%"),
					region_row("Victoria", "2,905", "3,118", "+7.3%"),
					region_row("New South Wales", "3,462", "3,390", "−2.1%"),
					region_row("Queensland", "1,127", "1,301", "+15.4%"),
					Pdf.row([Pdf.header_cell(Row, [Pdf.text("Northern Territory")]), Pdf.aligned(Center, Pdf.spanning(3, Pdf.cell([Pdf.text("Opened in October 2026; no first-quarter figures are reported.")])))]),
				],
				caption: Pdf.caption("Table 1. Revenue by region, AUD thousands"),
				columns: [
					{ align: Start, width: Content },
					{ align: End, width: Share(1) },
					{ align: End, width: Share(1) },
					{ align: Center, width: Fixed(Layout.Unit.points(72)) },
				],
				footer_rows: [region_row("Total", "8,778", "9,221", "+5.0%")],
				header_rows: [
					Pdf.row([
						Pdf.header_cell(Both, [Pdf.text("Region")]),
						Pdf.spanning(2, Pdf.header_cell(Column, [Pdf.text("Revenue")])),
						Pdf.header_cell(Column, [Pdf.text("Change")]),
					]),
					Pdf.row([
						Pdf.header_cell(Column, [Pdf.text("State or territory")]),
						Pdf.header_cell(Column, [Pdf.text("Q1 FY2026")]),
						Pdf.header_cell(Column, [Pdf.text("Q1 FY2027")]),
						Pdf.header_cell(Column, [Pdf.text("Per cent")]),
					]),
				],
				row_split: KeepRows,
			}),
			Pdf.paragraph("Negative values use the minus sign."),
		],
		language: "en-AU",
		title: "Sales performance${suffix}",
	})
}

split_document : U64 -> Document
split_document = |context| {
	long = Str.repeat("The warranty covers the frame, the motors, and the control unit for the full term. ", 150 + U64.mod_by(context, 1))
	row = |code, text| Pdf.row([Pdf.header_cell(Row, [Pdf.text(code)]), Pdf.cell([Pdf.text(text)]), Pdf.cell([Pdf.text("14 October 2031")])])
	Pdf.document({
		contents: [
			Pdf.heading(1, "Schedule 1. Covered items"),
			Pdf.table({
				body_rows: [row("HF-DSK-140", "Standing desk frame, twin motor, 1400 mm"), row("HF-CHR-ERG", long), row("HF-LMP-LED", "LED task lamp, 4000 K, clamp mount")],
				caption: Pdf.caption("Items covered by the extended warranty"),
				columns: [{ align: Start, width: Content }, { align: Start, width: Share(1) }, { align: End, width: Fixed(Layout.Unit.points(96)) }],
				footer_rows: [],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Code")]), Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Warranty until")])])],
				row_split: SplitRows,
			}),
		],
		language: "en-AU",
		title: "Warranty schedule",
	})
}

## The body rows are sized so the last one fits on the first page but the
## three totals rows do not: R3 carries the last body row to the second
## page with the totals, which repaints the header row first.
carry_document : U64 -> Document
carry_document = |context| {
	count = 32 + U64.mod_by(context, 1)
	var $rows = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("HF-${(1 + $index).to_str()}")]), Pdf.cell([Pdf.text("Service visit")]), Pdf.cell([Pdf.text("1")]), Pdf.cell([Pdf.text("95.00")]), Pdf.cell([Pdf.text("95.00")])]))
		$index = $index + 1
	}
	Pdf.document({
		contents: [Pdf.title("Service invoice"), items_table($rows)],
		language: "en-AU",
		title: "Totals near a page break",
	})
}

ordered_document : U64 -> Document
ordered_document = |context| {
	suffix = if context == 0 "" else " ${context.to_str()}"
	Pdf.document({
		contents: [
			Pdf.rich_paragraph([Pdf.text("Café "), Pdf.in_language("zh-Hans", [Pdf.text("中")]), Pdf.text(" PDF${suffix}")]),
			Pdf.table({
				body_rows: [
					Pdf.row([Pdf.header_cell(Row, [Pdf.text("Café 中 PDF")]), Pdf.cell([Pdf.text("1,284")]), Pdf.cell([Pdf.text("+10.0%")])]),
					Pdf.row([Pdf.header_cell(Row, [Pdf.in_language("zh-Hans", [Pdf.text("中")])]), Pdf.cell([Pdf.text("3,390")]), Pdf.cell([Pdf.text("-2.1%")])]),
				],
				caption: Pdf.no_caption,
				columns: [{ align: Start, width: Content }, { align: End, width: Share(1) }, { align: End, width: Share(1) }],
				footer_rows: [],
				header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Name")]), Pdf.header_cell(Column, [Pdf.text("1,000")]), Pdf.header_cell(Column, [Pdf.text("%")])])],
				row_split: KeepRows,
			}),
		],
		language: "en-AU",
		title: "Ordered numeric cells",
	})
}

## The packaged Latin face registered as a caller face, then a Han face.
register_faces : U64 -> Try({ policy : Font.PolicyId, registry : Font.Registry }, Fixture.EvidenceError)
register_faces = |context| {
	limits = if context == 0 Font.ValidationLimits.default else Font.ValidationLimits.make({ max_bytes: 0, max_cmap_mappings: 0, max_glyphs: 0, max_tables: 0 })
	latin = match Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	cjk = match latin.registry.register(cjk_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, limits) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	configured = match cjk.registry.with_policy([latin.face, cjk.face]) {
		Err(_) => return Err(EvidenceFailure)
		Ok(value) => value
	}
	Ok({ policy: configured.policy, registry: configured.registry })
}

## Bytes come from `Pdf.to_bytes_with`. Work comes from one semantic
## planning pass and the shaping, table, line, page, and text stages over
## the same normalized authoring.
evidence : Document, Theme, Faces -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, theme, faces| {
	options = match faces {
		BuiltInFace => Pdf.Options.with_theme(Pdf.Options.default, theme)
		Policy(policy) => Pdf.Options.with_font_registry(Pdf.Options.with_theme(Pdf.Options.default, theme), policy.registry)
	}
	bytes = Pdf.to_bytes_with(document, options) ? |_| EvidenceFailure
	authoring = Document.normalize(document)
	semantics = KernelFacadeSemantics.Plan.build(authoring, semantic_limits) ? |_| EvidenceFailure
	work = KernelFacadeSemantics.Plan.work(semantics)
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(semantics)))
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	staged = match faces {
		BuiltInFace => {
			font = KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 })) ? |_| EvidenceFailure
			shape = KernelFacadeShape.Plan.build(authoring, KernelFacadeSemantics.Plan.block_ownership(semantics), store, source_store, font, theme, shape_limits) ? |_| EvidenceFailure
			lines = KernelFacadeLines.Plan.build_authoring(authoring, shape, source_store, page_size, theme, line_limits) ? |_| EvidenceFailure
			{ lines, shape }
		}
		Policy(policy) => {
			shape = KernelFacadeShape.Plan.build_ordered(authoring, KernelFacadeSemantics.Plan.block_ownership(semantics), store, source_store, policy, theme, shape_limits) ? |_| EvidenceFailure
			lines = KernelFacadeLines.Plan.build_ordered_authoring(authoring, shape, source_store, page_size, theme, line_limits) ? |_| EvidenceFailure
			{ lines, shape }
		}
	}
	pages = KernelFacadePages.Plan.build(authoring, staged.shape, staged.lines, page_size, theme, page_limits) ? |_| EvidenceFailure
	text = KernelFacadeText.Plan.build(staged.shape, staged.lines, pages, text_limits) ? |_| EvidenceFailure
	page_work = KernelFacadePages.Plan.work(pages)
	table_work = match KernelFacadeLines.Plan.geometry(staged.lines) {
		WithTables(tables) => KernelFacadeTables.Plan.work(tables)
		NoTables => { cell_measurements: 0, column_width_passes: 0, measurement_cache_hits: 0, row_visits: 0 }
	}
	final_runs = KernelFacadeText.Plan.text(text).runs.len()
	artifact_runs = KernelFacadeText.Plan.artifact_runs(text).len()
	Ok({
		bytes,
		work: [
			work.node_writes,
			work.occurrence_writes,
			work.tables,
			work.table_cells,
			work.header_association_edges,
			table_work.cell_measurements,
			table_work.measurement_cache_hits,
			table_work.column_width_passes,
			table_work.row_visits,
			KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(staged.lines)).len(),
			page_work.page.page_writes,
			page_work.page.candidate_visits,
			page_work.repeated_header_paints,
			final_runs - artifact_runs,
			artifact_runs,
			bytes.len(),
		],
	})
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

rejects : Document, Conformance.DiagnosticCode, Str, List(Str) -> U64
rejects = |document, expected_code, expected_feature, expected_paths| match Pdf.to_bytes(document) {
	Err(InvalidDocument({ diagnostics: [{ code, details, feature: Feature(feature), location: Document, stage: AuthoringValidation, .. }], truncation: Complete, .. })) => if code == expected_code and feature == expected_feature and details == expected_paths 1 else 0
	_ => 0
}

## Each document differs from a valid table in one table fact. Every
## rejection is transactional: a stable code, the authored path of each
## participating source, and no bytes.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |context| {
	title = if context == 0 "Table negatives" else "guarded"
	document = |contents| Pdf.document({ contents, language: "en-AU", title })
	offset = U64.mod_by(context, 1)
	lead = Pdf.paragraph("Lead")
	columns = [{ align: Start, width: Content }, { align: Start, width: Share(1) }, { align: End, width: Fixed(Layout.Unit.points(60)) }]
	header = Pdf.row([Pdf.header_cell(Column, [Pdf.text("Code")]), Pdf.header_cell(Column, [Pdf.text("Description")]), Pdf.header_cell(Column, [Pdf.text("Amount")])])
	body = |text| Pdf.row([Pdf.header_cell(Row, [Pdf.text("A1")]), Pdf.cell([Pdf.text(text)]), Pdf.cell([Pdf.text("1.00")])])
	table = |rows, split| Pdf.table({ body_rows: rows, caption: Pdf.no_caption, columns, footer_rows: [], header_rows: [header], row_split: split })
	sentence = "A long description that keeps going and going. "
	checks = [
		rejects(document([lead, Pdf.table({ body_rows: [Pdf.row([Pdf.cell([Pdf.text("a")]), Pdf.cell([Pdf.text("b")]), Pdf.cell([Pdf.text("c")])])], caption: Pdf.no_caption, columns, footer_rows: [], header_rows: [], row_split: KeepRows })]), InvalidRelationship, "table.header_missing", ["contents[1]"]),
		rejects(document([lead, table([body("b"), Pdf.row([Pdf.header_cell(Row, [Pdf.text("A2")]), Pdf.cell([Pdf.text("b")]), Pdf.spanning(2, Pdf.cell([Pdf.text("c")]))])], KeepRows)]), InvalidRelationship, "table.grid_mismatch", ["contents[1].table.body_rows[1]"]),
		rejects(document([lead, table([Pdf.row([])], KeepRows)]), InvalidRelationship, "table.grid_mismatch", ["contents[1].table.body_rows[0]"]),
		rejects(document([lead, table([Pdf.row([Pdf.header_cell(Row, [Pdf.text("A1")]), Pdf.spanning(0, Pdf.cell([Pdf.text("b")])), Pdf.spanning(2, Pdf.cell([Pdf.text("c")]))])], KeepRows)]), InvalidRelationship, "table.grid_mismatch", ["contents[1].table.body_rows[0]"]),
		rejects(document([lead, table([Pdf.row([Pdf.row_spanning(2, Pdf.header_cell(Row, [Pdf.text("A1")])), Pdf.cell([Pdf.text("b")]), Pdf.cell([Pdf.text("c")])])], KeepRows)]), FeatureUnavailable, "table.row_span", ["contents[1].table.body_rows[0].cells[0]"]),
		rejects(document([lead, table([], KeepRows)]), InvalidRelationship, "table.empty", ["contents[1]"]),
		rejects(document([lead, Pdf.table({ body_rows: [], caption: Pdf.no_caption, columns: [], footer_rows: [], header_rows: [], row_split: KeepRows })]), InvalidRelationship, "table.empty", ["contents[1]"]),
		rejects(document([lead, table([Pdf.row([Pdf.header_cell(Row, [Pdf.text("A1")]), Pdf.cell([]), Pdf.cell([Pdf.text("c")])])], KeepRows)]), InvalidRelationship, "table.cell_empty", ["contents[1].table.body_rows[0].cells[1]"]),
		rejects(document([lead, table([body("short"), body(Str.repeat(sentence, 400 + offset))], KeepRows)]), LayoutConstraintViolated, "layout.oversize_row", ["contents[1].table.body_rows[1]"]),
		rejects(document([lead, table([body(Str.repeat("0123456789abcdef", 8 + offset))], KeepRows)]), LayoutConstraintViolated, "layout.unbreakable_token", ["contents[1].table.body_rows[0].cells[1]"]),
		rejects(document([lead, Pdf.table({ body_rows: [Pdf.row([Pdf.header_cell(Row, [Pdf.text("a")]), Pdf.cell([Pdf.text("b")])])], caption: Pdf.no_caption, columns: [{ align: Start, width: Fixed(Layout.Unit.points(300)) }, { align: Start, width: Fixed(Layout.Unit.points(300)) }], footer_rows: [], header_rows: [], row_split: KeepRows })]), LayoutConstraintViolated, "layout.table_width", ["contents[1]"]),
		rejects(document([Pdf.keep_together([lead, table(List.repeat(body("row"), 60 + offset), KeepRows)])]), LayoutConstraintViolated, "layout.keep_conflict", ["contents[0]", "contents[0].contents[0]", "contents[0].contents[1]"]),
		rejects(document([lead, Pdf.section([table([body("b")], KeepRows), Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Item")]), Pdf.list_item([table([body("b")], KeepRows)])])])]), InvalidRelationship, "semantics.list_item_content", ["contents[1].contents[1].items[1]"]),
	]
	passed = checks.sum()
	if passed != checks.len() {
		return Err(MissingRejection(passed))
	}

	## A table whose cells cross the facade's content-occurrence bound is a
	## located budget diagnostic, not an unlocated authoring error.
	many = List.repeat(body("row"), 5500 + offset)
	bounded = rejects(document([lead, table(many, KeepRows)]), BudgetExceeded, "document.content_limit", ["contents[1]"])
	if bounded != 1 {
		return Err(MissingRejection(passed))
	}
	carrier = Pdf.to_bytes(document([Pdf.title("Table carrier"), table([body("A valid row.")], KeepRows)])) ? |_| EvidenceFailure
	Ok({ bytes: carrier, work: [passed + bounded, carrier.len()] })
}

shape_limits : KernelFacadeShape.Limits
shape_limits = KernelFacadeShape.Limits.make({ max_requests: 65536, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) })

line_limits : KernelFacadeLines.Limits
line_limits = KernelFacadeLines.Limits.make({
	line: KernelLineLayout.BatchLimits.make({
		line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
		max_key_probes: 4000000,
		max_lines: 1000000,
		max_runs: 65536,
		max_table_slots: 262144,
		max_templates: 65536,
	}),
	max_blocks: 16384,
	max_runs: 65536,
})

page_limits : KernelFacadePages.Limits
page_limits = KernelFacadePages.Limits.make({
	max_blocks: 16384,
	max_rows: 1000000,
	page: KernelPageLayout.Limits.make({ max_blocks: 16384, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
})

text_limits : KernelFacadeText.Limits
text_limits = KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 })

## The facade's semantic-planning limits (package/Pdf.roc).
semantic_limits : KernelFacadeSemantics.Limits
semantic_limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 16,
	max_content_spine: 65536,
	max_inline_depth: 8,
	max_nodes: 16384,
	max_occurrences: 16384,
	max_properties: 16384,
	max_source_inputs: 16384,
	semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536, max_fragments: 0, max_namespaces: 1, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 4000000,
		max_inputs: 16384,
		max_source_bytes: 1000000,
		max_source_scalars: 1000000,
		max_table_slots: 65536,
		max_unique_sources: 16384,
		unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 16384, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 16384 }),
})
