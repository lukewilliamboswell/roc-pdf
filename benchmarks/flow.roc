app [main!] {
	pdf: "../package/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.11.0/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}
import Bench
import pdf.Document
import pdf.Pdf

main! = |args| Bench.run!(
	args,
	{
		name: "pdf-flow-bench",
		description: "Prepare and emit a tagged maintenance report with one rich paragraph and one ledger row per unit.",
		default_units: 128,
	},
	document,
)

document : U64, U64 -> Document
document = |units, iteration| Pdf.document({
	title: "Facilities maintenance report, run ${iteration.to_str()}",
	language: "en-AU",
	contents: [
		Pdf.title("Facilities maintenance report"),
		Pdf.section(notes(units)),
		Pdf.section([Pdf.heading(1, "Work order ledger"), ledger(units)]),
	],
})

notes : U64 -> List(Document.Block)
notes = |units| {
	var $blocks = [Pdf.heading(1, "Inspection notes")]
	var $index = 0
	while $index < units {
		reference = (24001 + $index).to_str()
		$blocks = $blocks.append(
			Pdf.rich_paragraph([
				Pdf.strong([Pdf.text("Work order ${reference}. ")]),
				Pdf.text("The technician inspected the supply fan and checked inlet pressure against the service history. The supervisor requested "),
				Pdf.emphasis([Pdf.text("a second reading after startup")]),
				Pdf.text(" before releasing the equipment."),
			]),
		)
		$index = $index + 1
	}
	$blocks
}

ledger : U64 -> Document.Block
ledger = |units| {
	var $rows = []
	var $index = 0
	while $index < units {
		reference = (24001 + $index).to_str()
		location = (1 + $index % 24).to_str()
		minutes = (45 + $index % 90).to_str()
		status = if ($index % 3 == 0) "Recheck" else "Recorded"
		$rows = $rows.append(
			Pdf.row([
				Pdf.header_cell(Row, [Pdf.text("WO-${reference}")]),
				Pdf.cell([Pdf.text("Plant room ${location}")]),
				Pdf.cell([Pdf.text(minutes)]),
				Pdf.cell([Pdf.text(status)]),
			]),
		)
		$index = $index + 1
	}
	Pdf.table({
		caption: Pdf.caption("Work orders by maintenance reference"),
		columns: [
			{ width: Content, align: Start },
			{ width: Share(1), align: Start },
			{ width: Content, align: End },
			{ width: Content, align: Start },
		],
		header_rows: [
			Pdf.row([
				Pdf.header_cell(Column, [Pdf.text("Work order")]),
				Pdf.header_cell(Column, [Pdf.text("Location")]),
				Pdf.header_cell(Column, [Pdf.text("Minutes")]),
				Pdf.header_cell(Column, [Pdf.text("Status")]),
			]),
		],
		body_rows: $rows,
	})
}
