import fuzz.Fuzz
import pdf.Document
import pdf.Layout
import pdf.Pdf

CheckboxFormsProperty := [].{
	target = Fuzz.target({
		name: "roc-pdf-fillable-checkboxes",
		examples: [
			Fuzz.example({ name: "initially-checked", revision: "1", make: || Input.{ variant: 0, states: 1 } }),
			Fuzz.example({ name: "initially-unchecked", revision: "1", make: || Input.{ variant: 0, states: 0 } }),
			Fuzz.example({ name: "mixed-distinct-labels", revision: "1", make: || Input.{ variant: 2, states: 3 } }),
			Fuzz.example({ name: "duplicate-with-text", revision: "1", make: || Input.{ variant: 3, states: 1 } }),
			Fuzz.example({ name: "invalid-checkbox-id", revision: "1", make: || Input.{ variant: 4, states: 0 } }),
			Fuzz.example({ name: "exact-page-boundary", revision: "1", make: || Input.{ variant: 1, states: 0 } }),
			Fuzz.example({ name: "past-page-boundary", revision: "1", make: || Input.{ variant: 5, states: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	})
}

Input := { variant : U8, states : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { variant: Fuzz.u8, states: Fuzz.u8 }.Fuzz
}

test : Input -> Fuzz.Outcome
test = |input| {
	variant = input.variant % 6
	x = match variant {
		1 => Layout.Unit.points(329)
		5 => Layout.Unit.millipoints(329001)
		_ => Layout.Unit.points(56)
	}
	id = match variant {
		3 => "reference"
		4 => "inspection.report"
		_ => "inspection_report"
	}
	field = Pdf.CheckboxProps.{ id, label: "Inspection report", state: if (input.states % 2 == 1) Checked else Unchecked }
	page = Pdf.fixed_page({ width: 595, height: 842 })
		.place_checkbox({ field, origin: { x, y: 818 } })
	if variant == 3 {
		return rejection(
			page.place_text_field({ field: { id: "reference", label: "Reference", width: 100 }, origin: { x: 56, y: 650 } }).finish(),
			"form.text.duplicate_id",
		)
	}
	if variant > 3 {
		return rejection(page.finish(), if (variant == 4) "form.checkbox.id" else "form.checkbox.frame")
	}
	finished = if variant == 2 {
		page.place_text_field({ field: { id: "reference", label: "Reference", width: 100 }, origin: { x: 56, y: 650 } })
			.place_checkbox({ field: { id: "site_visit", label: "Site visit", state: if (input.states.bitwise_and(2) == 2) Checked else Unchecked }, origin: { x: 56, y: 550 } })
			.finish()
	} else {
		page.finish()
	}
	doc = Pdf.fixed_document({ pages: [finished], language: "en", title: "Checkbox fuzz witness" })
	options = Pdf.Options.{ profile: AccessibleForm }
	match Pdf.prepare_with_report(doc, { options: options }) {
		Ok({ prepared, report }) if report.facts.blocks.len() == (if (variant == 2) 3 else 1) => {
			if report.facts.blocks.all(|block| block.role == "Lbl" and block.first_page == 1) and Pdf.to_bytes_prepared(prepared).is_ok() {
				return Fuzz.keep
			}
		}
		_ => {}
	}
	crash "checkbox preparation lost its label or appearance"
}

rejection : Document.FixedPage, Str -> Fuzz.Outcome
rejection = |page, expected| {
	doc = Pdf.fixed_document({ pages: [page], language: "en", title: "Checkbox fuzz rejection" })
	options = Pdf.Options.{ profile: AccessibleForm }
	if rejects(Pdf.to_bytes_with(doc, options), expected) and rejects(Pdf.to_chunks_with(doc, options), expected) {
		Fuzz.keep
	} else {
		crash "checkbox authoring did not reject atomically"
	}
}

rejects : Try(a, Pdf.Error), Str -> Bool
rejects = |result, expected| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), .. }], truncation: Complete, .. })) => actual == expected
	_ => False
}
