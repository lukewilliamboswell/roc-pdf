app [main!] {
	pf: platform "../platform/main.roc",
	pdf: "../../package/all.roc",
}

import Fixture
import pf.Metrics

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

CaseSpec : { case : Case, schema_version : U64 }

main! : List(Str) => { bytes : List(U8), work : List(U64) }
main! = |args| {
	case_json = match args.get(1) {
		Ok(text) => text
		Err(OutOfBounds) => crash "CASE_SPEC_MISSING: reference_documents requires exactly one JSON case argument"
	}
	if args.len() != 2 {
		crash "CASE_SPEC_ARITY: reference_documents requires exactly one JSON case argument"
	}
	parsed : Try(CaseSpec, [InvalidJson(Str), MissingRequiredField(Str)])
	parsed = Json.parse(case_json)
	spec = match parsed {
		Ok(value) => value
		Err(InvalidJson(detail)) => crash "CASE_SPEC_INVALID_JSON: ${detail}"
		Err(MissingRequiredField(field)) => crash "CASE_SPEC_MISSING_FIELD: ${field}"
	}
	if spec.schema_version != 1 {
		crash "CASE_SPEC_UNSUPPORTED_VERSION: reference_documents supports schema_version 1"
	}
	if Json.to_str(spec) != case_json {
		crash "CASE_SPEC_NON_CANONICAL: reference_documents rejects unknown fields and non-canonical JSON"
	}
	Metrics.reset_allocations!()
	result = match spec.case {
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
