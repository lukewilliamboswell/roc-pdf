import fuzz.Fuzz
import pdf.Document
import pdf.Layout
import pdf.Pdf

FootnoteProperty := [].{
	target = Fuzz.target({
		name: "roc-pdf-first-citation-footnotes",
		examples: [
			Fuzz.example({ name: "whole-note", revision: "1", make: || Input.{ surface: 0, length: 1, height: 80 } }),
			Fuzz.example({ name: "repeated-after-break", revision: "1", make: || Input.{ surface: 1, length: 15, height: 80 } }),
			Fuzz.example({ name: "whole-note-does-not-fit", revision: "1", make: || Input.{ surface: 0, length: 63, height: 0 } }),
			Fuzz.example({ name: "dangling-target", revision: "1", make: || Input.{ surface: 2, length: 1, height: 0 } }),
			Fuzz.example({ name: "duplicate-definition", revision: "1", make: || Input.{ surface: 3, length: 1, height: 0 } }),
			Fuzz.example({ name: "uncited-note", revision: "1", make: || Input.{ surface: 4, length: 1, height: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	})
}

Input := { surface : U8, length : U8, height : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { surface: Fuzz.u8, length: Fuzz.u8, height: Fuzz.u8 }.Fuzz
}

test : Input -> Fuzz.Outcome
test = |input| {
	variant = input.surface % 5
	marker = Pdf.rich_paragraph([Pdf.text("Clock "), Pdf.footnote_marker({ id: "clock", text: "[1]" })])
	note_body = (Str.from_utf8(List.repeat(120, 5 * ((input.length % 64).to_u64() + 1))) ?? "").replace_each("xxxxx", "note ")
	note = Pdf.footnote_definition({ id: "clock", label: "[1]", body: note_body })
	contents = match variant {
		0 => [marker, note]
		1 => [marker, Pdf.page_break, marker, note]
		2 => [marker]
		3 => [marker, note, note]
		_ => [Pdf.paragraph("Clock"), note]
	}
	document = Pdf.document({ contents, title: "Footnote fuzz", language: "en" })
	page_height = Layout.Unit.points(49 + input.height.to_i64())
	options = Pdf.Options.{ page_size: Custom({ width: 330, height: page_height }), theme: { page_margin: { top: 15, bottom: 15, left: 20, right: 20 } } }
	if variant >= 2 {
		feature = match variant {
			2 => "document.footnote.missing"
			3 => "document.footnote.duplicate"
			_ => "document.footnote.uncited"
		}
		return reject_result(document, options, feature)
	}
	match Pdf.prepare_with_report(document, { options: options }) {
		Ok({ prepared, report }) => {
			notes = report.facts.blocks.keep_if(|block| block.role == "FENote")
			note_report = notes.get(0) ?? crash "footnote group missing"
			if notes.len() == 1 and note_report.first_page == 1 and note_report.last_page == 1
				and Pdf.to_bytes_prepared(prepared).is_ok() {
				return Fuzz.keep
			}
		}
		Err(InvalidDocument({ diagnostics: [{ feature: Feature("document.footnote.fit"), .. }], .. })) => return reject_result(document, options, "document.footnote.fit")
		_ => {}
	}
	crash "first-citation footnote did not agree with its authoring"
}

reject_result : Document, Pdf.Options, Str -> Fuzz.Outcome
reject_result = |document, options, expected| {
	if rejects(Pdf.to_chunks_with(document, options), expected) and rejects(Pdf.to_bytes_with(document, options), expected) {
		Fuzz.keep
	} else {
		crash "footnote did not reject atomically"
	}
}

rejects : Try(a, Pdf.Error), Str -> Bool
rejects = |result, expected| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), .. }], truncation: Complete, .. })) => actual == expected
	_ => False
}
