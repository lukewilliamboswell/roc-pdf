import Callout
import Invoice
import Letter
import Report
import pdf.Color
import pdf.Conformance
import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.Layout
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)

## The reference invoice, report, and letter and every adverse variant of
## `reference-documents-v10`, authored only through the public `Pdf`,
## `Scene`, `Layout`, `Theme`, and `Font` surface (the report's callout
## through the separately authored `Callout` extension).
##
## - The three ordinary documents are the gallery examples:
##   `scripts/check_reference_documents.py` proves their snapshots are
##   byte-identical to `examples/tax-invoice/tax-invoice.pdf`,
##   `examples/business-report/business-report.pdf`, and `examples/warranty-letter/warranty-letter.pdf`, and
##   `scripts/check_gallery.py` that the example programs regenerate those.
## - Every accepted variant is prepared with `Pdf.prepare_with_report` and
##   its policy outcome is checked through the report's mechanical facts,
##   each mapped back to an authored path; placement variants also prepare
##   a control that proves the triggering condition.
## - `atomic_negatives`: every rejected variant with its stable code and
##   authored paths, no prepared document, and no bytes.
## - Scale pairs: invoice rows 50/500 (INV-A3 is the large case), report
##   sections 10/100, and letter paragraphs 20/200.
##
## Work comes from the report's own counts: pages, fragments, reading-order
## blocks, outcomes, repeated headers, relaxations, obligations, coverage
## entries, observations, and output bytes.
Fixture :: [].{
	EvidenceError : [EvidenceFailure(Str), InvalidScale, MissingObservation(U64), MissingRejection(U64, Str)]

	invoice : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice = |_context| evidence(Invoice.document(Invoice.ordinary), Invoice.options, invoice_observations)

	report : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report = |_context| evidence(Report.document(Report.ordinary), Report.options, report_observations)

	letter : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	letter = |_context| evidence(Letter.document(Letter.ordinary), Letter.options, letter_observations)

	## INV-A1: long customer, address lines, and one long description.
	invoice_long_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice_long_text = |_context| {
		config = {
			..Invoice.ordinary,
			bill_to: [
				"The Northstar Regional Housing and Community Development Cooperative (Western Australia) Ltd",
				"Attention: Accounts Payable Team, Finance and Procurement Division, Level 7 Harbourside Tower",
				"Building C, Kestrel Parade Business Park, 42 Kestrel Parade, off Marine Terrace and Beach Street",
				"Fremantle, Western Australia 6160, Australia (deliveries by the loading dock on Beach Street only)",
			],
			row: |index| if index == 2 Invoice.row_with(index, [Pdf.text(long_description)], Invoice.product_code(index)) else Invoice.item_row(index),
		}
		evidence(Invoice.document(config), Invoice.options, long_text_observations)
	}

	## INV-A2a: a code wider than its content column's share.
	invoice_wide_code : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice_wide_code = |_context| {
		config = { ..Invoice.ordinary, row: |index| if index == 0 Invoice.row_with(index, Invoice.product_description(index), "HF-DSK-140-TASMANIAN-OAK/L2") else Invoice.item_row(index) }
		evidence(Invoice.document(config), Invoice.options, wide_code_observations)
	}

	## INV-A4b: a 9,000-character description under `SplitRows`.
	invoice_split_row : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice_split_row = |_context| evidence(Invoice.document({ ..Invoice.ordinary, row: oversize_row, row_split: SplitRows }), Invoice.options, split_row_observations)

	## INV-A5: the last body row fits on its page but the totals do not.
	invoice_totals_carry : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice_totals_carry = |_context| {
		config = { ..Invoice.ordinary, rows: carry_rows }
		control = Pdf.prepare_with_report(Invoice.document({ ..config, totals: False }), Invoice.options) ? |_| EvidenceFailure("totals control")
		evidence(Invoice.document(config), Invoice.options, |observed| carry_observations(observed, control.report))
	}

	## INV-A3 and the invoice scale pair: `rows` body rows.
	invoice_rows : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	invoice_rows = |rows| {
		if rows < 32 or rows > 500 {
			return Err(InvalidScale)
		}
		evidence(Invoice.document({ ..Invoice.ordinary, rows, field_width: 80 }), Invoice.options, |observed| rows_observations(observed, rows))
	}

	## REP-A1: section 2's heading falls on the last line of a page.
	report_heading_keep : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_heading_keep = |_context| {
		prefix = fresh_page(heading_space)
		control = Pdf.prepare_with_report(Report.framed([Pdf.paragraph("Lead.")].concat(prefix).append(Pdf.heading(1, "2 Sales performance"))), Report.options) ? |_| EvidenceFailure("heading control")
		evidence(Report.document({ ..Report.ordinary, before_sales: prefix }), Report.options, |observed| heading_keep_observations(observed, control.report))
	}

	## REP-A2: Figure 1 fits where its caption does not.
	report_figure_caption : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_figure_caption = |_context| {
		prefix = fresh_page(figure_space)
		uncaptioned = Pdf.figure({ drawing: Report.chart, alt: "Bar chart comparing revenue by region.", caption: Pdf.no_caption })
		control = Pdf.prepare_with_report(Report.framed([Pdf.paragraph("Lead.")].concat(prefix).append(uncaptioned)), Report.options) ? |_| EvidenceFailure("figure control")
		evidence(Report.document({ ..Report.ordinary, before_figure1: prefix }), Report.options, |observed| figure_caption_observations(observed, control.report))
	}

	## REP-A3: only two of Table 1's body rows fit.
	report_table_break : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_table_break = |_context| evidence(Report.document({ ..Report.ordinary, before_table1: fresh_page(table_space) }), Report.options, table_break_observations)

	## REP-A5: an ordered policy of a caller-registered Latin face and a
	## Han face, with a nested `zh-Hans` span in section 3.2.
	report_ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_ordered = |_context| {
		faces = register_faces({}) ? |_| EvidenceFailure("register faces")
		options = { ..Report.options, theme: { ..Report.theme, font_selection: Policy(faces.policy) }, fonts: Registered(faces.registry) }
		extra = [Pdf.text(" The Shanghai office marks approved stock with "), Pdf.in_language("zh-Hans", [Pdf.text("中")]), Pdf.text(" on every board.")]
		evidence(Report.document({ ..Report.ordinary, timber_extra: extra }), options, ordered_observations)
	}

	## REP-A6b: a 600 × 900 pt Figure 1 scaled to fit.
	report_scaled_figure : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_scaled_figure = |_context| evidence(Report.document({ ..Report.ordinary, figure1: tall_figure(50) }), Report.options, scaled_observations)

	## The report-sections scale pair.
	report_sections : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	report_sections = |count| {
		if count == 0 or count > 100 {
			return Err(InvalidScale)
		}
		evidence(Report.sections_document(count, 90, False), Report.options, |observed| sections_observations(observed, count))
	}

	## LET-A1: recipient lines of 80–110 characters.
	letter_long_recipient : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	letter_long_recipient = |_context| {
		recipient = [
			"Ms Priya Raman-Whitcombe, Operations Manager and Acting Director of Facilities and Workplace Services",
			"Northstar Regional Housing and Community Development Cooperative (Western Australia) Limited",
			"Building C, Level 7, Harbourside Tower, Kestrel Parade Business Park, 42 Kestrel Parade",
			"Fremantle, Western Australia 6160, Australia (deliveries via the Beach Street loading dock)",
		]
		evidence(Letter.document({ ..Letter.ordinary, recipient }), Letter.options, long_recipient_observations)
	}

	## LET-A2 and the letter scale pair: `paragraphs` body paragraphs.
	letter_paragraphs : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	letter_paragraphs = |paragraphs| {
		if paragraphs < 6 or paragraphs > 200 {
			return Err(InvalidScale)
		}
		evidence(Letter.document({ ..Letter.ordinary, paragraphs }), Letter.options, |observed| paragraphs_observations(observed, paragraphs))
	}

	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |_context| run_negatives({})
}

points : I64 -> Layout.Unit
points = |value| Layout.Unit.points(value)

long_description : Str
long_description = "Ergonomic task chair with a breathable mesh back, adjustable lumbar support, four-dimensional armrests, a synchronised tilt mechanism with five locking positions, seat depth adjustment, a class four gas lift, a polished aluminium base, and dual-wheel castors suited to both carpet and hard floors, supplied fully assembled, labelled by workstation, and delivered to each level of the fit-out."

## A description of 9,000 characters for row 5 (INV-A4a and INV-A4b).
oversize_row : U64 -> Pdf.Row
oversize_row = |index| if index == 5 {
	sentence = "Under-desk cable tray, powder-coated steel, with a hinged lid, grommets, and clips for every desk. "
	Invoice.row_with(index, [Pdf.text(Str.trim(Str.repeat(sentence, 90)))], Invoice.product_code(index))
} else {
	Invoice.item_row(index)
}

## The body-row count of INV-A5 (recorded from the reviewed layout).
carry_rows : U64
carry_rows = 30

## A fresh continuation page holding one filler line and then `space`
## points of authored space. A continuation page's flow region is
## 746 − (24 + 12) − (16 + 12) = 682 pt; the filler line and its paragraph
## spacing take 22 pt.
fresh_page : I64 -> List(Document.Block)
fresh_page = |space| [Pdf.page_break, Pdf.paragraph("Filler."), Pdf.spacer(points(space))]

## REP-A1: 22 + 630 + 18 = 670 ≤ 682 leaves room for the heading line,
## but not for it and one body line (670 + 8 + 14 = 692).
heading_space : I64
heading_space = 630

## REP-A2: 22 + 430 + 220 = 672 ≤ 682 fits the figure, but not its
## caption (672 + 8 + 14 = 694).
figure_space : I64
figure_space = 430

## REP-A3: authored space that leaves room for Table 1's caption, header,
## and two body rows (recorded from the reviewed layout).
table_space : I64
table_space = 580

## A 600 × 900 pt plan drawing (REP-A6), scaled to fit with `floor` percent.
tall_figure : U8 -> Document.Block
tall_figure = |floor| {
	ink = Color.srgb8({ red: 40, green: 40, blue: 40 })
	slate = Color.srgb8({ red: 128, green: 146, blue: 166 })
	plan = Scene.Drawing.empty
		.path(Scene.PathBuilder.start.rectangle(Layout.rect(2, 2, 596, 896)).finish(), Scene.solid_stroke(ink, points(4)))
	Pdf.figure({
		drawing: plan.rectangle(Layout.rect(60, 60, 480, 780), slate),
		alt: "Bar chart of revenue by region, drawn at poster size.",
		caption: Pdf.caption("Figure 1. Revenue by region, AUD thousands"),
		fit: if floor == 0 Exact else ScaleToFit({ minimum_percent: floor }),
	})
}

## The packaged Latin face registered as a caller face, then a Han face.
register_faces : {} -> Try({ policy : Font.PolicyId, registry : Font.Registry }, [RegistrationFailed])
register_faces = |{}| {
	limits = Font.ValidationLimits.default
	latin = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits) ? |_| RegistrationFailed
	cjk = latin.registry.register(cjk_font_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, limits) ? |_| RegistrationFailed
	configured = cjk.registry.with_policy([latin.face, cjk.face]) ? |_| RegistrationFailed
	Ok({ policy: configured.policy, registry: configured.registry })
}

## Prepare once with the report; bytes come from the prepared document.
evidence : Document, Pdf.Options, (Pdf.Report -> List(Bool)) -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
evidence = |document, options, observe| {
	{ prepared, report } = match Pdf.prepare_with_report(document, options) {
		Ok(value) => value
		Err(error) => return Err(EvidenceFailure(Str.inspect(error)))
	}
	bytes = Pdf.to_bytes_prepared(prepared) ? |_| EvidenceFailure("emit")
	observed = observe(report)
	var $index = 0
	for held in observed {
		if !held {
			return Err(MissingObservation($index))
		}
		$index = $index + 1
	}
	facts = report.facts
	Ok({
		bytes,
		work: [
			facts.pages.len(),
			facts.pages.map(|page| page.fragments).sum(),
			facts.blocks.len(),
			facts.outcomes.len(),
			repeated_headers(report),
			relaxations(report),
			report.obligations.len(),
			facts.coverage.len(),
			observed.len(),
			bytes.len(),
		],
	})
}

## ---------------------------------------------------------------------
## Report queries, each by authored path.

block_at : Pdf.Report, Str -> Pdf.ReportBlock
block_at = |report, path| match report.facts.blocks.find_first(|block| block.path == path) {
	Ok(value) => value
	Err(NotFound) => { first_page: 0, fragments: 0, last_page: 0, path, role: "" }
}

first_page : Pdf.Report, Str -> U64
first_page = |report, path| block_at(report, path).first_page

last_page : Pdf.Report, Str -> U64
last_page = |report, path| block_at(report, path).last_page

## Every cell of a row lies on `page`.
row_on : Pdf.Report, Str, U64 -> Bool
row_on = |report, row, page| {
	cells = report.facts.blocks.keep_if(|block| block.path.starts_with("${row}.cells["))
	!cells.is_empty() and cells.all(|block| block.first_page == page and block.last_page == page)
}

has_role : Pdf.Report, Str, Str -> Bool
has_role = |report, path, role| {
	block = block_at(report, path)
	block.role == role and block.fragments > 0
}

has_obligation : Pdf.Report, Str, [AlternativeTextMeaningful, ExpansionAccurate, LanguageAccurate, LinkPurposeMeaningful, ReadingOrderMeaningful, TableHeadersMeaningful] -> Bool
has_obligation = |report, path, obligation| report.obligations.any(|entry| entry.path == path and entry.obligation == obligation)

has_alternative : Pdf.Report, Str, Str -> Bool
has_alternative = |report, path, text| report.facts.alternatives.any(|entry| entry.path == path and entry.text == text)

repeated_headers : Pdf.Report -> U64
repeated_headers = |report| report.facts.outcomes.count_if(
	|outcome| match outcome {
		RepeatedHeader(_) => True
		_ => False
	},
)

repeated_on : Pdf.Report, Str, U64 -> Bool
repeated_on = |report, table, page| report.facts.outcomes.any(
	|outcome| match outcome {
		RepeatedHeader({ page: at, path, rows }) => path == table and at == page and rows == 1
		_ => False
	},
)

relaxations : Pdf.Report -> U64
relaxations = |report| report.facts.outcomes.count_if(
	|outcome| match outcome {
		PreferenceRelaxed(_) => True
		_ => False
	},
)

continued_rows : Pdf.Report, Str -> U64
continued_rows = |report, row| report.facts.outcomes.count_if(
	|outcome| match outcome {
		RowContinued({ path, page: _ }) => path == row
		_ => False
	},
)

figure_scale : Pdf.Report, Str -> U64
figure_scale = |report, figure| match report.facts.outcomes.find_first(
	|outcome| match outcome {
		FigureScale({ path, fit: _, scale: _ }) => path == figure
		_ => False
	},
) {
	Ok(FigureScale({ scale, .. })) => scale
	_ => 0
}

## `holds` for every page from `from` to `to` inclusive.
pages_between : U64, U64, (U64 -> Bool) -> Bool
pages_between = |from, to, holds| {
	var $page = from
	while $page <= to {
		if !holds($page) {
			return False
		}
		$page = $page + 1
	}
	True
}

page_count : Pdf.Report -> U64
page_count = |report| report.facts.pages.len()

## ---------------------------------------------------------------------
## Observations.

items_table : Str
items_table = "contents[4].contents[1]"

invoice_observations : Pdf.Report -> List(Bool)
invoice_observations = |report| {
	facts = report.facts
	last = "${items_table}.table.body_rows[31]"
	[
		facts.title == "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd" and facts.language == "en-AU",
		page_count(report) == 3,
		has_role(report, "contents[1]", "Title"),
		repeated_on(report, items_table, 2) and repeated_on(report, items_table, 3) and repeated_headers(report) == 2,
		row_on(report, "${items_table}.table.footer_rows[0]", last_page(report, "${last}.cells[0]")),
		row_on(report, "${items_table}.table.footer_rows[2]", first_page(report, "${last}.cells[0]")),
		first_page(report, "contents[5].contents[0]") == first_page(report, "contents[5].contents[1]"),
		relaxations(report) == 0,
		has_alternative(report, "${items_table}.table.body_rows[3].cells[1].inlines[0]", "fr"),
		has_obligation(report, "contents[5].contents[2].inlines[1]", LinkPurposeMeaningful),
		has_obligation(report, items_table, TableHeadersMeaningful),
		has_obligation(report, "contents[2]", TableHeadersMeaningful),
	]
}

report_observations : Pdf.Report -> List(Bool)
report_observations = |report| {
	facts = report.facts
	figure_one = "contents[3].contents[3]"
	figure_two = "contents[4].contents[3].contents[2]"
	table_one = "contents[3].contents[2]"
	table_two = "contents[6].contents[2]"
	headings = ["contents[2]", "contents[3]", "contents[4]", "contents[4].contents[2]", "contents[4].contents[3]", "contents[5]", "contents[6]"]
	[
		facts.title == "Harbour & Finch quarterly operations report, Q1 FY2027" and facts.language == "en-AU",
		page_count(report) == 5,
		headings.all(|section| has_role(report, "${section}.contents[0]", "H1") or has_role(report, "${section}.contents[0]", "H2")),
		headings.all(|section| first_page(report, "${section}.contents[0]") == first_page(report, "${section}.contents[1]")),
		first_page(report, figure_one) == first_page(report, "${figure_one}.caption"),
		first_page(report, figure_two) == first_page(report, "${figure_two}.caption"),
		first_page(report, "${table_one}.caption") == last_page(report, "${table_one}.table.footer_rows[0].cells[3]"),
		repeated_headers(report) == 2 and repeated_on(report, table_two, page_count(report)),
		facts.outcomes.any(
			|outcome| match outcome {
				CustomBlockPlaced({ name, path, page, height }) => name == "Key figures" and path == "contents[2].contents[3]" and page == 1 and height == Callout.measure(Report.theme, 3, points(483)).height
				_ => False
			},
		),
		relaxations(report) == 0,
		has_alternative(report, "contents[1].inlines[1]", "financial year 2027"),
		has_alternative(report, "contents[3].contents[1].inlines[1]", "Goods and Services Tax"),
		has_obligation(report, figure_one, AlternativeTextMeaningful) and has_obligation(report, figure_two, AlternativeTextMeaningful),
		has_obligation(report, "contents[2].contents[1].inlines[5]", LinkPurposeMeaningful),
		has_obligation(report, "contents[5].contents[1].inlines[1]", LinkPurposeMeaningful),
		has_obligation(report, table_one, TableHeadersMeaningful) and has_obligation(report, table_two, TableHeadersMeaningful),
		has_obligation(report, "contents[4].contents[3].contents[0].inlines[1]", LanguageAccurate) or has_obligation(report, "contents[4].contents[3].contents[1].inlines[1]", LanguageAccurate),
	]
}

letter_observations : Pdf.Report -> List(Bool)
letter_observations = |report| {
	facts = report.facts
	signature = "contents[14]"
	[
		facts.title == "Letter to Northstar Cooperative about the warranty extension, 21 September 2026",
		page_count(report) == 3,
		!facts.blocks.any(|block| block.role == "Title"),
		match facts.blocks.first() {
			Ok(first) => first.path == "templates.first.lead.contents[0]" and first.first_page == 1
			Err(ListWasEmpty) => False
		},
		first_page(report, "${signature}.contents[0]") == last_page(report, "${signature}.contents[3]"),
		first_page(report, "contents[17].contents[0]") == 3,
		relaxations(report) == 0,
		has_obligation(report, "document", ReadingOrderMeaningful),
	]
}

long_text_observations : Pdf.Report -> List(Bool)
long_text_observations = |report| {
	long_row = "${items_table}.table.body_rows[2]"
	[
		block_at(report, "contents[3].contents[1]").fragments > 4,
		row_on(report, long_row, first_page(report, "${long_row}.cells[1]")),
		block_at(report, "${long_row}.cells[1]").fragments > 5,
	]
}

wide_code_observations : Pdf.Report -> List(Bool)
wide_code_observations = |report| {
	row = "${items_table}.table.body_rows[0]"
	[
		block_at(report, "${row}.cells[0]").fragments >= 1,
		row_on(report, row, first_page(report, "${row}.cells[0]")),
		page_count(report) >= 3,
	]
}

split_row_observations : Pdf.Report -> List(Bool)
split_row_observations = |report| {
	row = "${items_table}.table.body_rows[5]"
	cell = block_at(report, "${row}.cells[1]")
	[
		continued_rows(report, row) >= 2,
		cell.last_page >= cell.first_page + 2,
		pages_between(cell.first_page + 1, cell.last_page, |page| repeated_on(report, items_table, page)),
	]
}

carry_observations : Pdf.Report, Pdf.Report -> List(Bool)
carry_observations = |report, control| {
	last = "${items_table}.table.body_rows[${(carry_rows - 1).to_str()}]"
	previous = "${items_table}.table.body_rows[${(carry_rows - 2).to_str()}]"
	page = first_page(report, "${last}.cells[0]")
	[

		## Without totals, the last body row fits on the second-last row's page.
		first_page(control, "${last}.cells[0]") == first_page(control, "${previous}.cells[0]"),

		## With them, it carries to the next page with the totals group.
		page == first_page(report, "${previous}.cells[0]") + 1,
		row_on(report, "${items_table}.table.footer_rows[2]", page),
		repeated_on(report, items_table, page),
		relaxations(report) == 0,
	]
}

rows_observations : Pdf.Report, U64 -> List(Bool)
rows_observations = |report, rows| {
	last = "${items_table}.table.body_rows[${(rows - 1).to_str()}]"
	table_pages = first_page(report, "${items_table}.table.footer_rows[2].cells[0]")
	[
		repeated_headers(report) == table_pages - 1,
		pages_between(2, table_pages, |page| repeated_on(report, items_table, page)),
		first_page(report, "${last}.cells[0]") == table_pages,
	]
}

heading_keep_observations : Pdf.Report, Pdf.Report -> List(Bool)
heading_keep_observations = |report, control| {
	filler = "contents[4]"
	heading = "contents[6].contents[0]"
	[

		## Alone, the heading fits on the filler's page.
		first_page(control, "contents[4]") == first_page(control, "contents[2]"),
		first_page(report, heading) == first_page(report, filler) + 1,
		first_page(report, heading) == first_page(report, "contents[6].contents[1]"),
		relaxations(report) == 0,
	]
}

figure_caption_observations : Pdf.Report, Pdf.Report -> List(Bool)
figure_caption_observations = |report, control| {
	filler = "contents[3].contents[4]"
	figure = "contents[3].contents[6]"
	[

		## Without its caption, the figure fits on the filler's page.
		first_page(control, "contents[4]") == first_page(control, "contents[2]"),
		first_page(report, figure) == first_page(report, filler) + 1,
		first_page(report, "${figure}.caption") == first_page(report, figure),
		relaxations(report) == 0,
	]
}

table_break_observations : Pdf.Report -> List(Bool)
table_break_observations = |report| {
	table = "contents[3].contents[5]"
	page = first_page(report, "contents[3].contents[3]")
	[
		first_page(report, "${table}.caption") == page,
		row_on(report, "${table}.table.body_rows[1]", page),
		row_on(report, "${table}.table.body_rows[2]", page + 1),
		row_on(report, "${table}.table.footer_rows[0]", page + 1),
		repeated_on(report, table, page + 1),
		relaxations(report) == 0,
	]
}

ordered_observations : Pdf.Report -> List(Bool)
ordered_observations = |report| {
	timber = "contents[4].contents[3].contents[1]"
	[
		report.facts.coverage.any(|covered| covered.path == timber and covered.script == "Hani" and covered.scalars == 1),
		report.facts.coverage.any(|covered| covered.path == timber and covered.script == "Latn"),
		has_alternative(report, "${timber}.inlines[6]", "zh-Hans"),
		has_obligation(report, "${timber}.inlines[6]", LanguageAccurate),
	]
}

scaled_observations : Pdf.Report -> List(Bool)
scaled_observations = |report| {
	figure = "contents[3].contents[3]"

	## min(483/600, (682 − 8 − 14)/900) in thousandths: the continuation
	## frame is the smaller, and the caption line and its spacing stay.
	[
		figure_scale(report, figure) == 733,
		first_page(report, "${figure}.caption") == first_page(report, figure),
	]
}

sections_observations : Pdf.Report, U64 -> List(Bool)
sections_observations = |report, count| [
	report.facts.blocks.count_if(|block| block.role == "H1") == count,
	report.obligations.count_if(|entry| entry.obligation == LinkPurposeMeaningful) == count,
	page_count(report) > 1,
]

long_recipient_observations : Pdf.Report -> List(Bool)
long_recipient_observations = |report| [
	block_at(report, "contents[1]").fragments >= 8,
	first_page(report, "contents[17].contents[0]") == page_count(report),
]

paragraphs_observations : Pdf.Report, U64 -> List(Bool)
paragraphs_observations = |report, paragraphs| {
	signature = "contents[${(paragraphs + 8).to_str()}]"
	[
		first_page(report, "${signature}.contents[0]") == last_page(report, "${signature}.contents[3]"),
		first_page(report, "contents[${(paragraphs + 11).to_str()}].contents[0]") == page_count(report),
		report.facts.blocks.count_if(|block| block.role == "P") >= paragraphs,
	]
}

## ---------------------------------------------------------------------
## Rejected variants.

Expected : [Code(Conformance.DiagnosticCode, Str, List(Str)), Located(Conformance.DiagnosticCode, Str, List(Str), Str), Navigation, Metadata]

## One rejection: the stable code and paths, no prepared document, and no
## report.
check_rejection : Document, Pdf.Options, Expected -> Try({}, Str)
check_rejection = |document, options, expected| {
	actual = Pdf.prepare_with_report(document, options)
	held = match (expected, actual) {
		(Code(code, feature, paths), Err(InvalidDocument({ diagnostics: [{ code: got, details, feature: Feature(named), location: Document, .. }], truncation: Complete, .. }))) => got == code and named == feature and details == paths
		(Located(code, feature, paths, fragment), Err(InvalidDocument({ diagnostics: [{ code: got, details, feature: Feature(named), location: Document, message, .. }], truncation: Complete, .. }))) => got == code and named == feature and details == paths and message.contains(fragment)
		(Navigation, Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 })))) => True
		(Metadata, Err(InvalidMetadata(_))) => True
		_ => False
	}
	if held {
		Ok({})
	} else {
		match actual {
			Ok(_) => Err("accepted")
			Err(error) => Err(Str.inspect(error))
		}
	}
}

run_negatives : {} -> Try({ bytes : List(U8), work : List(U64) }, Fixture.EvidenceError)
run_negatives = |{}| {
	invoice_with = |config| Invoice.document(config)
	row_override = |target, replacement| |index| if index == target replacement(index) else Invoice.item_row(index)
	serial = Str.repeat("0123456789abcdef", 8)
	wide_columns = [
		{ width: Content, align: Start },
		{ width: Share(1), align: Start },
		{ width: Fixed(points(120)), align: End },
		{ width: Fixed(points(140)), align: End },
		{ width: Fixed(points(160)), align: End },
	]
	letter_with = |config| Letter.document(config)
	report_with = |config| Report.document(config)
	oversize_callout = Callout.with_height(Report.theme, { height: points(900), lines: ["Revenue: AUD 9.22 m (+5.0%)"], name: "Key figures", width: points(483) })
	items = items_table
	checks = [

		## INV-A2b: a 128-hex-digit serial in a description.
		(invoice_with({ ..Invoice.ordinary, row: row_override(4, |index| Invoice.row_with(index, [Pdf.text("LED task lamp, serial ${serial}")], Invoice.product_code(index))) }), Invoice.options, Code(LayoutConstraintViolated, "layout.unbreakable_token", ["${items}.table.body_rows[4].cells[1]"])),

		## INV-A2c: fixed widths plus minima exceed the table width.
		(invoice_with({ ..Invoice.ordinary, columns: wide_columns }), Invoice.options, Code(LayoutConstraintViolated, "layout.table_width", [items])),

		## INV-A3 with the ordinary 64 pt page field: `Page 1 of 10` does not fit.
		(invoice_with({ ..Invoice.ordinary, rows: 500 }), Invoice.options, Code(LayoutConstraintViolated, "layout.field_overflow", ["templates.first.footer.end[0].inlines[0].inlines[1]"])),

		## INV-A4a: a row taller than a continuation page under KeepRows.
		(invoice_with({ ..Invoice.ordinary, row: oversize_row }), Invoice.options, Code(LayoutConstraintViolated, "layout.oversize_row", ["${items}.table.body_rows[5]"])),

		## INV-A6a: Arabic in the customer name.
		(invoice_with({ ..Invoice.ordinary, bill_to: ["شركة الشمال Northstar Cooperative Ltd", "42 Kestrel Parade"] }), Invoice.options, Code(FontCoverageMissing, "text.unsupported_script", ["contents[3].contents[1].inlines[0]"])),

		## INV-A6b: Han in the address with the packaged face only.
		(invoice_with({ ..Invoice.ordinary, bill_to: ["Northstar Cooperative Ltd", "42 Kestrel Parade, 北京"] }), Invoice.options, Code(FontCoverageMissing, "text.coverage_missing", ["contents[3].contents[1].inlines[2]"])),

		## INV-A7a: Items and Payment kept together beyond one page.
		(invoice_with({ ..Invoice.ordinary, arrangement: KeepItemsWithPayment }), Invoice.options, Code(LayoutConstraintViolated, "layout.keep_conflict", ["contents[4]", "contents[4].contents[0].contents[0]", "contents[4].contents[1].contents[2]"])),

		## INV-A7b: an explicit break inside a required keep.
		(invoice_with({ ..Invoice.ordinary, arrangement: BreakInsideKeep }), Invoice.options, Code(LayoutConstraintViolated, "layout.keep_conflict", ["contents[3].contents[1]", "contents[3]"])),

		## INV-A8: a row of five cells and a two-column span.
		(invoice_with({ ..Invoice.ordinary, row: row_override(6, |index| Pdf.row([Pdf.header_cell(Row, [Pdf.text(Invoice.product_code(index))]), Pdf.cell([Pdf.text("Installation")]), Pdf.cell([Pdf.text("12")]), Pdf.cell([Pdf.text("95.00")]), Pdf.cell([Pdf.text("1,140.00")]), Pdf.cell([Pdf.text("extra")]).spanning(2)])) }), Invoice.options, Code(InvalidRelationship, "table.grid_mismatch", ["${items}.table.body_rows[6]"])),

		## INV-A9: a row span.
		(invoice_with({ ..Invoice.ordinary, row: row_override(7, |index| Pdf.row([Pdf.header_cell(Row, [Pdf.text(Invoice.product_code(index))]).row_spanning(2), Pdf.cell([Pdf.text("Delivery")]), Pdf.cell([Pdf.text("1")]), Pdf.cell([Pdf.text("180.00")]), Pdf.cell([Pdf.text("180.00")])])) }), Invoice.options, Code(FeatureUnavailable, "table.row_span", ["${items}.table.body_rows[7].cells[0]"])),

		## REP-A4: a three-digit page number in a reserved width sized for
		## two digits (16 pt; the widest two-digit value, `40`, is 14.045 pt).
		(Report.sections_document(100, 16, True), Report.options, Located(LayoutConstraintViolated, "layout.field_overflow", ["templates.continuation.footer.end[0].inlines[0].inlines[0]"], "on page 100: its resolved value 100")),

		## REP-A6a: an Exact 600 × 900 pt Figure 1.
		(report_with({ ..Report.ordinary, figure1: tall_figure(0) }), Report.options, Code(LayoutConstraintViolated, "document.figure_oversize", ["contents[3].contents[3]"])),

		## REP-A6c: the same figure with a 90% floor.
		(report_with({ ..Report.ordinary, figure1: tall_figure(90) }), Report.options, Code(LayoutConstraintViolated, "document.figure_oversize", ["contents[3].contents[3]"])),

		## REP-A7: an H3 directly after the H1 of section 3.
		(report_with({ ..Report.ordinary, freight_level: 3 }), Report.options, Code(InvalidRelationship, "semantics.heading_skip", ["contents[4].contents[0]", "contents[4].contents[2].contents[0]"])),

		## REP-A8: an internal link to the undeclared destination `risks`.
		(report_with({ ..Report.ordinary, summary_link: "risks" }), Report.options, Navigation),

		## REP-A9: Figure 2 with empty alternative text.
		(report_with({ ..Report.ordinary, figure2_alternative: "" }), Report.options, Code(InvalidRelationship, "document.figure_alternative_empty", ["contents[4].contents[3].contents[2]"])),

		## REP-A10: the callout reports a height beyond the body frame.
		(report_with({ ..Report.ordinary, callout: oversize_callout }), Report.options, Code(LayoutConstraintViolated, "layout.oversize_block", ["contents[2].contents[3]"])),

		## LET-A3a: a 640 pt lead region.
		(letter_with({ ..Letter.ordinary, lead_height: 640 }), Letter.options, Code(LayoutConstraintViolated, "layout.template_body_space", ["templates.first"])),

		## LET-A3b: twelve letterhead lines in the 60 pt lead region.
		(letter_with({ ..Letter.ordinary, letterhead_lines: 9 }), Letter.options, Code(LayoutConstraintViolated, "layout.template_region_overflow", ["templates.first.lead"])),

		## LET-A3c: continuation header slots wider than the region.
		(letter_with({ ..Letter.ordinary, continuation_start: "Northstar Regional Housing and Community Cooperative Ltd · 21 September 2026" }), Letter.options, Code(LayoutConstraintViolated, "layout.template_region_overflow", ["templates.continuation.header"])),

		## LET-A4: the letter under AccessibleArchive before Gate 7.
		(letter_with(Letter.ordinary), { ..Letter.options, profile: AccessibleArchive }, Code(FeatureUnavailable, "profile.accessible_archive", [])),

		## LET-A5: an empty metadata title.
		(letter_with({ ..Letter.ordinary, title: "" }), Letter.options, Metadata),

		## LET-A6: a signature block taller than a continuation body.
		(letter_with({ ..Letter.ordinary, signature_space: 700 }), Letter.options, Code(LayoutConstraintViolated, "layout.keep_conflict", ["contents[14]", "contents[14].contents[0]", "contents[14].contents[3]"])),

		## LET-A7: a page field in a body paragraph.
		(letter_with({ ..Letter.ordinary, body_field: True }), Letter.options, Code(FeatureUnavailable, "document.generated_reference", ["contents[5].inlines[1]"])),
	]
	var $index = 0
	for (document, options, expected) in checks {
		match check_rejection(document, options, expected) {
			Ok({}) => {}
			Err(actual) => return Err(MissingRejection($index, actual))
		}
		$index = $index + 1
	}
	{ prepared, report } = Pdf.prepare_with_report(Pdf.document({ contents: [Pdf.title("Reference variant rejections"), Pdf.paragraph("Every rejected variant returned its stable diagnostic and no bytes.")], language: "en-AU", title: "Reference variant rejections" }), Invoice.options) ? |_| EvidenceFailure("carrier")
	carrier = Pdf.to_bytes_prepared(prepared) ? |_| EvidenceFailure("carrier emit")
	Ok({ bytes: carrier, work: [$index, report.obligations.len(), carrier.len()] })
}
