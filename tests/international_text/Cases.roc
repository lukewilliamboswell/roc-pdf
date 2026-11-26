import invoice.Invoice
import hindi.Statement
import thai.Notice
import arabic.Invoice as ArabicInvoice
import pdf.Document
import pdf.Pdf

Cases :: [].{
	Case : [Arabic({ wtpdf : Bool }), ArabicAtomic, Atomic, Hindi({ wtpdf : Bool }), HindiAtomic, Thai({ wtpdf : Bool }), ThaiAtomic, Invoice({ wtpdf : Bool }), Wrap({ count : U64 })]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Arabic({ wtpdf }) => encode(ArabicInvoice.document({}), selected_profile(require_fixture(ArabicInvoice.options({})), wtpdf), 0)
			ArabicAtomic => arabic_atomic(require_fixture(ArabicInvoice.options({})))
			Hindi({ wtpdf }) => encode(Statement.document({}), selected_profile(require_fixture(Statement.options({})), wtpdf), 0)
			HindiAtomic => hindi_atomic(require_fixture(Statement.options({})))
			Thai({ wtpdf }) => encode(Notice.document({}), selected_profile(require_fixture(Notice.options({})), wtpdf), 0)
			ThaiAtomic => thai_atomic(require_fixture(Notice.options({})))
			Invoice({ wtpdf }) => encode(Invoice.document({}), selected_profile(require_fixture(Invoice.options({})), wtpdf), 0)
			Wrap({ count }) => encode(wrap_document(count), require_fixture(Invoice.options({})), count)
			Atomic => atomic(require_fixture(Invoice.options({})))
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
	registry = match options.fonts {
		Registered(value) => value
		_ => crash "INTERNATIONAL_FIXTURE_HAS_NO_REGISTRY"
	}
	policy = match options.theme.font_selection {
		Policy(value) => value
		_ => crash "INTERNATIONAL_FIXTURE_HAS_NO_POLICY"
	}
	ordered = require_fixture(registry.policy_faces(policy))
	first = require_fixture(ordered.get(0))
	selected = require_fixture(registry.with_policy([first]))
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

selected_profile : Pdf.Options, Bool -> Pdf.Options
selected_profile = |options, wtpdf| { ..options, wtpdf: if (wtpdf) DeclareAccessibility else NoWtpdfDeclaration }

arabic_atomic : Pdf.Options -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
arabic_atomic = |options| {
	cases = [
		{ example: Pdf.rich_paragraph([Pdf.in_language("ar", [Pdf.text("ال"), Pdf.strong([Pdf.text("سلام")])])]), diagnostics: "text.international_joining_boundary" },
		{ example: Pdf.paragraph("اَلْعَرَبِيَّة"), diagnostics: "text.international_cluster" },
		{ example: Pdf.paragraph("Aאב"), diagnostics: "text.international_script" },
	]
	for case in cases {
		document = Pdf.document({ title: "Unsupported Arabic text", language: "ar", contents: [case.example] })
		if !reports(Pdf.to_bytes_with(document, options), case.diagnostics) or !reports(Pdf.to_chunks_with(document, options), case.diagnostics) {
			crash "ARABIC_REJECTION_NOT_ATOMIC_OR_LOCATED"
		}
	}
	result = encode(ArabicInvoice.document({}), options, 0)?
	Ok({ ..result, work: result.work.append(cases.len() * 2) })
}

hindi_atomic : Pdf.Options -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
hindi_atomic = |options| {
	cases = [
		{ example: Pdf.paragraph("जमा शेष"), language: "mr", diagnosis: "text.international_language", path: "contents[0]" },
		{ example: Pdf.paragraph("रक्कम ৳"), language: "hi", diagnosis: "text.international_script", path: "contents[0]" },
		{ example: Pdf.rich_paragraph([Pdf.text("वि"), Pdf.strong([Pdf.text("त्")]), Pdf.text("तीय")]), language: "hi", diagnosis: "text.unsupported_cluster", path: "contents[0].inlines[1].inlines[0]" },
	]
	for case in cases {
		document = Pdf.document({ title: "Unsupported Hindi text", language: case.language, contents: [case.example] })
		if !reported_at(Pdf.to_bytes_with(document, options), case.diagnosis, case.path) or !reported_at(Pdf.to_chunks_with(document, options), case.diagnosis, case.path) {
			crash "HINDI_REJECTION_NOT_ATOMIC_OR_LOCATED"
		}
	}
	result = encode(Statement.document({}), options, 0)?
	Ok({ ..result, work: result.work.append(cases.len() * 2) })
}

reported_at : Try(a, Pdf.Error), Str, Str -> Bool
reported_at = |result, name, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(feature), details: [source_path], .. }], .. })) => feature == name and source_path == path
	_ => False
}

thai_atomic : Pdf.Options -> Try({ bytes : List(U8), work : List(U64) }, Pdf.Error)
thai_atomic = |options| {
	bad_dictionary : Pdf.Options
	bad_dictionary = { ..options, theme: { ..options.theme, international_text: ThaiLatin({ revision: "", words: ["กรุณา"] }) } }
	uncovered_dictionary : Pdf.Options
	uncovered_dictionary = { ..options, theme: { ..options.theme, international_text: ThaiLatin({ revision: "uncovered-v1", words: [] }) } }
	wrong_language = Pdf.document({ title: "Thai range in wrong language", language: "en", contents: [Pdf.paragraph("ชำระ")] })
	cases = [
		{ document: Notice.document({}), selection: bad_dictionary, diagnosis: "text.thai_dictionary", path: "theme.international_text" },
		{ document: Notice.document({}), selection: uncovered_dictionary, diagnosis: "layout.international_unbreakable", path: "contents[2].contents[0]" },
		{ document: wrong_language, selection: options, diagnosis: "text.international_language", path: "contents[0]" },
	]
	for case in cases {
		document = case.document
		if !reported_at(Pdf.to_bytes_with(document, case.selection), case.diagnosis, case.path) or !reported_at(Pdf.to_chunks_with(document, case.selection), case.diagnosis, case.path) {
			crash "THAI_REJECTION_NOT_ATOMIC_OR_LOCATED: ${Str.inspect(Pdf.to_bytes_with(document, case.selection))}"
		}
	}
	result = encode(Notice.document({}), options, 0)?
	Ok({ ..result, work: result.work.append(cases.len() * 2) })
}
