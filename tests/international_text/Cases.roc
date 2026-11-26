import invoice.Invoice
import pdf.Document
import pdf.Font
import pdf.Pdf
import pdf.RocFont

Cases :: [].{
	Case : [Atomic, Invoice({ wtpdf : Bool }), Wrap({ count : U64 })]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		options = require_fixture(Invoice.options({}))
		result = match case {
			Invoice({ wtpdf }) => encode(Invoice.document({}), { ..options, wtpdf: if (wtpdf) DeclareAccessibility else NoWtpdfDeclaration }, 0)
			Wrap({ count }) => encode(wrap_document(count), options, count)
			Atomic => atomic(options)
		}
		match result {
			Ok(view) => view
			Err(error) => crash "INTERNATIONAL_TEXT_FAILED: ${Str.inspect(error)}"
		}
	}
}

wrap_document : U64 -> Document
wrap_document = |count| {
	block = Pdf.custom_block({
		name: "Wrap checked per address",
		inset: 4,
		size: { width: 164, height: 46 },
		contents: [
			Pdf.rich_paragraph([
				Pdf.strong([Pdf.in_language("he", [Pdf.text("נועה לוי רחוב הרצל 24 תל אביב")]), Pdf.text(" (PO-1042)")]),
				Pdf.in_language("he", [Pdf.text(" ישראל")]),
			]),
		],
	})
	alternate = Pdf.custom_block({
		name: "Wrap checked per address",
		inset: 4,
		size: { width: 164, height: 46 },
		contents: [
			Pdf.rich_paragraph([
				Pdf.in_language("he", [Pdf.text("לוי נועה רחוב הרצל 24 תל אביב")]),
				Pdf.text(" (PO-4021)"),
				Pdf.in_language("he", [Pdf.text(" ישראל")]),
			]),
		],
	})
	var $blocks = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$blocks = $blocks.append(if ($index % 2 == 0) block else alternate)
		$index = $index + 1
	}
	Pdf.document({ title: "Hebrew and Latin wrap", language: "en-AU", contents: $blocks })
}

encode : Document, Pdf.Options, U64 -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
encode = |document, selected, count| {
	reported = Pdf.prepare_with_report(document, { options: selected })?
	bytes = Pdf.to_bytes_prepared(reported.prepared)?
	ordinary = Pdf.to_bytes_with(document, selected)?
	if bytes != ordinary {
		crash "INTERNATIONAL_REPORT_CHANGED_OUTPUT"
	}
	facts = reported.report.facts
	if count > 0 and (facts.blocks.len() != count or !facts.blocks.all(|block| block.role == "P" and block.fragments == 20)) {
		crash "INTERNATIONAL_REPORT_LOST_WRAPPED_OWNERS"
	}
	fragments = facts.pages.map(|page| page.fragments).sum()
	Ok({ bytes, work: [facts.pages.len(), facts.blocks.len(), fragments, count, bytes.len()] })
}

atomic : Pdf.Options -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
atomic = |options| {
	latin = require_fixture(RocFont.register(Font.Registry.empty, Font.ValidationLimits.default))
	selected = require_fixture(latin.registry.with_policy([latin.body]))
	latin_only : Pdf.Options
	latin_only = { fonts: Registered(selected.registry), theme: { font_selection: Policy(selected.policy), international_text: HebrewLatin } }
	cases = [
		{ text: "שָ", selected_options: options, diagnostics: "text.international_cluster" },
		{ text: "A\u(2067)אב", selected_options: options, diagnostics: "text.international_control" },
		{ text: "Aم", selected_options: options, diagnostics: "text.international_script" },
		{ text: "שלום", selected_options: latin_only, diagnostics: "text.international_coverage" },
	]
	for case in cases {
		document = Pdf.document({ title: "Unsupported writing", language: "en-AU", contents: [Pdf.paragraph(case.text)] })
		if !reports(Pdf.to_bytes_with(document, case.selected_options), case.diagnostics) or !reports(Pdf.to_chunks_with(document, case.selected_options), case.diagnostics) {
			crash "INTERNATIONAL_REJECTION_NOT_ATOMIC_OR_LOCATED"
		}
	}
	# A policy may include an approved face that remains unused.
	_ = Pdf.to_bytes_with(Pdf.document({ title: "English only", language: "en-AU", contents: [Pdf.paragraph("English only.")] }), options)?
	result = encode(wrap_document(2), options, 2)?
	Ok({ ..result, work: result.work.append(cases.len() * 2) })
}

reports : Try(a, Pdf.Error), Str -> Bool
reports = |result, name| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(feature), details: ["contents[0]"], .. }], .. })) => feature == name
	_ => False
}

require_fixture : Try(a, e) -> a
require_fixture = |result| match result {
	Ok(value) => value
	Err(error) => crash "INTERNATIONAL_FIXTURE_SETUP_FAILED: ${Str.inspect(error)}"
}
