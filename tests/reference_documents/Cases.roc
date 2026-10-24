import Fixture

## The reference_documents family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Invoice({ context : U64 }),
		Report({ context : U64 }),
		Letter({ context : U64 }),
		InvoiceLongText({ context : U64 }),
		InvoiceWideCode({ context : U64 }),
		InvoiceSplitRow({ context : U64 }),
		InvoiceTotalsCarry({ context : U64 }),
		InvoiceRows({ rows : U64 }),
		ReportHeadingKeep({ context : U64 }),
		ReportFigureCaption({ context : U64 }),
		ReportTableBreak({ context : U64 }),
		ReportOrdered({ context : U64 }),
		ReportScaledFigure({ context : U64 }),
		ReportSections({ sections : U64 }),
		LetterLongRecipient({ context : U64 }),
		LetterParagraphs({ paragraphs : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Invoice({ context }) => Fixture.invoice(context)
			Report({ context }) => Fixture.report(context)
			Letter({ context }) => Fixture.letter(context)
			InvoiceLongText({ context }) => Fixture.invoice_long_text(context)
			InvoiceWideCode({ context }) => Fixture.invoice_wide_code(context)
			InvoiceSplitRow({ context }) => Fixture.invoice_split_row(context)
			InvoiceTotalsCarry({ context }) => Fixture.invoice_totals_carry(context)
			InvoiceRows({ rows }) => Fixture.invoice_rows(rows)
			ReportHeadingKeep({ context }) => Fixture.report_heading_keep(context)
			ReportFigureCaption({ context }) => Fixture.report_figure_caption(context)
			ReportTableBreak({ context }) => Fixture.report_table_break(context)
			ReportOrdered({ context }) => Fixture.report_ordered(context)
			ReportScaledFigure({ context }) => Fixture.report_scaled_figure(context)
			ReportSections({ sections }) => Fixture.report_sections(sections)
			LetterLongRecipient({ context }) => Fixture.letter_long_recipient(context)
			LetterParagraphs({ paragraphs }) => Fixture.letter_paragraphs(paragraphs)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: reference_documents fixture rejected the typed case: ${Str.inspect(error)}"
		}
	}
}
