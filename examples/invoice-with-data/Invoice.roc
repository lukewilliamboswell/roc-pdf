import pdf.Document
import pdf.Pdf
import "invoice.xml" as invoice_xml : List(U8)

Invoice :: [].{
	document : Document
	document = {
		Pdf.document({
			contents: [
				Pdf.title("Tax invoice HF-2026-0417"),
				Pdf.paragraph("Harbour & Finch Pty Ltd · ABN 00 123 456 789"),
				Pdf.paragraph("Bill to Northstar Cooperative Ltd. Issued 14 September 2026."),
				Pdf.table({
					caption: Pdf.caption("Items supplied under purchase order PO 88213"),
					columns: [{ width: Share(1), align: Start }, { width: Fixed(90), align: End }, { width: Fixed(100), align: End }],
					header_rows: [
						Pdf.row([Pdf.header_cell(Column, [Pdf.text("Item")]), Pdf.header_cell(Column, [Pdf.text("Quantity")]), Pdf.header_cell(Column, [Pdf.text("Amount (AUD)")])]),
					],
					body_rows: [
						Pdf.row([Pdf.header_cell(Row, [Pdf.text("Standing desk frame")]), Pdf.cell([Pdf.text("4 × 689.00")]), Pdf.cell([Pdf.text("2,756.00")])]),
						Pdf.row([Pdf.header_cell(Row, [Pdf.text("Metropolitan delivery")]), Pdf.cell([Pdf.text("1 × 180.00")]), Pdf.cell([Pdf.text("180.00")])]),
					],
					footer_rows: [total("Subtotal", "2,936.00"), total("GST (10%)", "293.60"), total("Total due (AUD)", "3,229.60")],
				}),
				Pdf.heading(1, "Payment"),
				Pdf.paragraph("Please pay by 14 October 2026. Bank transfer: BSB 000-000, account 1234 5678, reference HF-2026-0417."),
			],
			language: "en-AU",
			title: "Tax invoice HF-2026-0417",
		}).with_associated_files([
			{
				bytes: invoice_xml,
				filename: "invoice.xml",
				media_type: "application/xml",
				modified: "2026-09-14T00:00:00Z",
				description: "Supplemental invoice numbers and item totals for importing into accounting software.",
				relationship: Data,
				necessity: Supplemental,
			},
		])
	}
}

total : Str, Str -> Pdf.Row
total = |label, amount| Pdf.row([Pdf.header_cell(Row, [Pdf.text(label)]).spanning(2), Pdf.cell([Pdf.text(amount)])])
