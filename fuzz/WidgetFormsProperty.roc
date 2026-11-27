import fuzz.Fuzz
import pdf.Pdf
import pdf.Layout

WidgetFormsProperty := [].{
	target = Fuzz.target({
		name: "roc-pdf-fillable-text-fields",
		examples: [
			Fuzz.example({ name: "blank", revision: "1", make: || Input.{ variant: 0, value: 0, width: 0 } }),
			Fuzz.example({ name: "prefilled", revision: "1", make: || Input.{ variant: 0, value: 3, width: 6 } }),
			Fuzz.example({ name: "width-below-minimum", revision: "1", make: || Input.{ variant: 1, value: 3, width: 47 } }),
			Fuzz.example({ name: "invalid-field-id", revision: "1", make: || Input.{ variant: 2, value: 6, width: 9 } }),
			Fuzz.example({ name: "duplicate-field-id", revision: "1", make: || Input.{ variant: 3, value: 1, width: 2 } }),
			Fuzz.example({ name: "outside-editable-repertoire", revision: "1", make: || Input.{ variant: 4, value: 0, width: 1 } }),
			Fuzz.example({ name: "too-many-characters", revision: "1", make: || Input.{ variant: 5, value: 0, width: 1 } }),
			Fuzz.example({ name: "value-exceeds-field-fit", revision: "1", make: || Input.{ variant: 6, value: 0, width: 0 } }),
		],
		test,
		show: |input| Str.inspect(input),
	})
}

Input := { value : U8, variant : U8, width : U8 }.{
	parser_for : _
	encoder_for : _

	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { value: Fuzz.u8, variant: Fuzz.u8, width: Fuzz.u8 }.Fuzz
}

test : Input -> Fuzz.Outcome
test = |input| {
	variant = input.variant % 7
	width = Layout.Unit.points(
		match variant {
			1 => (input.width % 48).to_i64()
			6 => 48
			_ => 48 + input.width.to_i64()
		},
	)
	value = match variant {
		4 => "é"
		5 => Str.from_utf8(List.repeat(65, 65 + (input.value % 4).to_u64())) ?? ""
		6 => Str.from_utf8(List.repeat(87, 64)) ?? ""
		_ => Str.from_utf8(List.repeat(65 + input.value % 26, (input.value % 4).to_u64())) ?? ""
	}
	first = Pdf.fixed_page({ width: 595, height: 842 })
		.place_text_field({
			field: { id: if (variant == 2) "name.bad" else "name", label: "Name", width, value: if (value.is_empty()) Blank else Prefilled(value) },
			origin: { x: 56, y: 650 },
		})
	page = if variant == 3 {
		first.place_text_field({ field: { id: "name", label: "Second name", width: 180 }, origin: { x: 56, y: 580 } }).finish()
	} else {
		first.finish()
	}
	document = Pdf.fixed_document({ pages: [page], language: "en", title: "Editable field fuzz witness" })
	options = Pdf.Options.{ profile: AccessibleForm }
	result = Pdf.prepare_with_report(document, { options: options })
	if variant == 0 {
		match result {
			Ok({ prepared, report }) if report.facts.blocks.len() == 1 => {
				block = report.facts.blocks.get(0) ?? crash "widget label report entry"
				if block.role == "Lbl" and block.first_page == 1 and Pdf.to_bytes_prepared(prepared).is_ok() {
					return Fuzz.keep
				}
			}
			_ => {}
		}
		crash "valid field did not prepare with its labelled placement"
	}
	wanted = match variant {
		1 => "form.text.frame"
		2 => "form.text.id"
		3 => "form.text.duplicate_id"
		4 | 5 => "form.text.value"
		_ => "form.text.fit"
	}
	if rejects(result, wanted) and rejects(Pdf.to_chunks_with(document, options), wanted) {
		Fuzz.keep
	} else {
		crash "form preparation did not reject the malformed widget atomically"
	}
}

rejects : Try(a, Pdf.Error), Str -> Bool
rejects = |result, expected| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), .. }], truncation: Complete, .. })) => actual == expected
	_ => False
}
