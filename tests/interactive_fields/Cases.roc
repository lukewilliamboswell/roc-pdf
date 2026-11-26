import intake.Intake
import pdf.Document
import pdf.Layout
import pdf.Pdf

Cases :: [].{
	Case : [Intake, Defaults, Scale({ count : U64 }), Rejections({ count : U64 }), Wtpdf, Mixed, CheckboxDefaults, MixedScale({ count : U64 }), CheckboxRejections, MixedWtpdf]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |selected| {
		result = match selected {
			Intake => evidence(Intake.document(False), options, 0)
			Wtpdf => evidence(Intake.document(False), { profile: AccessibleForm, wtpdf: DeclareAccessibility }, 0)
			Scale({ count }) => evidence(scale_document(count), options, 0)
			Defaults => default_equivalence({})
			Rejections({ count }) => rejections(count)
			Mixed => evidence(Intake.mixed_document(False), options, 0)
			CheckboxDefaults => checkbox_default_equivalence({})
			MixedScale({ count }) => evidence(mixed_scale(count), options, 0)
			CheckboxRejections => checkbox_rejections({})
			MixedWtpdf => evidence(Intake.mixed_document(False), { profile: AccessibleForm, wtpdf: DeclareAccessibility }, 0)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "interactive field fixture failed: ${Str.inspect(error)}"
		}
	}
}

options : Pdf.Options
options = { profile: AccessibleForm }

scale_document : U64 -> Document
scale_document = |count| {
	var $pages = []
	var $index = 0
	while $index < count {
		page_number = $pages.len()
		var $page = Pdf.fixed_page({ width: 595, height: 842 })
			.place({ block: Pdf.title("Service intake page ${(page_number + 1).to_str()}"), frame: Layout.rect({ x: 56, y: 746, width: 480, height: 48 }) })
		var $slot = 0
		while $index < count and $slot < 6 {
			index = $index
			x = Layout.Unit.points(56)
			y = Layout.Unit.points(680 - $slot.to_i64_wrap() * 64)
			$page = $page.place_text_field({
				field: { id: "field_${index.to_str()}", label: "Intake label ${index.to_str()}", width: 200, value: if (index % 2 == 0) Blank else Prefilled("Ref ${index.to_str()}") },
				origin: { x, y },
			})
			$index = $index + 1
			$slot = $slot + 1
		}
		$pages = $pages.append($page.finish())
	}
	Pdf.fixed_document({ pages: $pages, language: "en", title: "Intake scale" })
}

single : Pdf.TextFieldProps, Layout.Point -> Document
single = |field, origin| {
	page = Pdf.fixed_page({ width: 595, height: 842 })
		.place({ block: Pdf.title("Field defaults"), frame: Layout.rect({ x: 56, y: 730, width: 482, height: 48 }) })
		.place_text_field({ field, origin })
		.finish()
	Pdf.fixed_document({ pages: [page], language: "en", title: "Field defaults" })
}

default_equivalence : {} -> Try(Cases.Stats, Pdf.Error)
default_equivalence = |_| {
	origin = { x: Layout.Unit.points(56), y: Layout.Unit.points(650) }
	implicit = single({ id: "name", label: "Name", width: 200 }, origin)
	explicit = single({ id: "name", label: "Name", width: 200, value: Blank }, origin)
	empty = single({ id: "name", label: "Name", width: 200, value: Prefilled("") }, origin)
	prepared = evidence(implicit, options, 0)?
	explicit_bytes = Pdf.to_bytes_with(explicit, options)?
	empty_bytes = Pdf.to_bytes_with(empty, options)?
	if prepared.bytes != explicit_bytes or prepared.bytes != empty_bytes {
		crash "blank forms must be byte-identical"
	}
	Ok(prepared)
}

evidence : Document, Pdf.Options, U64 -> Try(Cases.Stats, Pdf.Error)
evidence = |document, active, rejected| {
	{ prepared, report } = Pdf.prepare_with_report(document, { options: active })?
	fields = report.facts.blocks.count_if(|block| block.role == "Lbl")
	bytes = Pdf.to_bytes_prepared(prepared)?
	chunks = chunk_match(bytes, Pdf.to_chunks_prepared(prepared, ShareUnchangedResources)?)
	Ok({ bytes, work: [report.facts.pages.len(), fields, chunks, bytes.len(), rejected] })
}

chunk_match : List(U8), Pdf.Encode -> U64
chunk_match = |expected, encoder| {
	var $encoder = encoder
	var $count = 0
	var $offset = 0
	while True {
		match Pdf.next_chunk($encoder) {
			Done => {
				if $offset != expected.len() {
					crash "incomplete form stream"
				}
				return $count
			}
			Emit(chunk, next) => {
				if chunk.is_empty() or chunk.len() > expected.len() - $offset or expected.sublist({ start: $offset, len: chunk.len() }) != chunk {
					crash "form chunk differs from buffered output"
				}
				$count = $count + 1
				$offset = $offset + chunk.len()
				$encoder = next
			}
		}
	}
}

rejections : U64 -> Try(Cases.Stats, Pdf.Error)
rejections = |count| {
	origin = { x: Layout.Unit.points(56), y: Layout.Unit.points(650) }
	samples = [
		(Intake.document(False), Pdf.Options.{}, "form.profile", "pages[0].placements[2].field"),
		(Intake.document(False), Pdf.Options.{ profile: Archive }, "form.profile", "pages[0].placements[2].field"),
		(Intake.document(False), Pdf.Options.{ profile: Standard }, "form.profile", "pages[0].placements[2].field"),
		(Intake.document(True), options, "form.text.duplicate_id", "pages[0].placements[3].field.id"),
		(single({ id: "name.with.dot", label: "Name", width: 200 }, origin), options, "form.text.id", "pages[0].placements[1].field.id"),
		(single({ id: "name", label: " ", width: 200 }, origin), options, "form.text.label", "pages[0].placements[1].field.label"),
		(single({ id: "name", label: "Name", width: 200, value: Prefilled("é") }, origin), options, "form.text.value", "pages[0].placements[1].field.value"),
		(single({ id: "name", label: "Name", width: 200, value: Prefilled(Str.from_utf8(List.repeat(65, 65)) ?? "") }, origin), options, "form.text.value", "pages[0].placements[1].field.value"),
		(single({ id: "name", label: "Name", width: 48, value: Prefilled("WWWWWWWW") }, origin), options, "form.text.fit", "pages[0].placements[1].field.value"),
		(single({ id: "name", label: "Name", width: 47.999 }, origin), options, "form.text.frame", "pages[0].placements[1]"),
		(single({ id: "name", label: "Name", width: 48 }, { x: Layout.Unit.millipoints(547001), y: 794 }), options, "form.text.frame", "pages[0].placements[1]"),
		(Pdf.document({ title: "No fields", language: "en", contents: [Pdf.paragraph("No fields")] }), options, "form.fields_required", "options.profile"),
	]
	for (document, selection, feature, path) in samples {
		if !rejects(Pdf.prepare(document, selection), feature, path)
			or !rejects(Pdf.to_bytes_with(document, selection), feature, path)
			or !rejects(Pdf.to_chunks_with(document, selection), feature, path)
			or !rejects(Pdf.prepare_with_report(document, { options: selection }), feature, path) {
			crash "expected atomic form rejection: ${feature} at ${path}"
		}
	}
	# The width and both page endpoint checks meet at an accepted boundary.
	_ = Pdf.prepare(single({ id: "name", label: "Name", width: 48 }, { x: Layout.Unit.points(547), y: 794 }), options)?
	_ = Pdf.prepare(scale_document(128), options)?
	if !rejects(Pdf.prepare(scale_document(count), options), "form.text.count", "pages") {
		crash "form field-count budget must reject"
	}
	evidence(Intake.document(False), options, samples.len() * 4 + 1)
}

rejects : Try(a, Pdf.Error), Str, Str -> Bool
rejects = |result, feature, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(actual), details: [location], .. }], truncation: Complete, .. })) => actual == feature and location == path
	_ => False
}

mixed_scale : U64 -> Document
mixed_scale = |count| {
	var $pages = []
	var $index = 0
	while $index < count {
		var $page = Pdf.fixed_page({ width: 595, height: 842 })
			.place({ block: Pdf.title("Intake checklist"), frame: Layout.rect({ x: 56, y: 746, width: 480, height: 48 }) })
		var $slot = 0
		while $index < count and $slot < 6 {
			index = $index
			origin = { x: Layout.Unit.points(56), y: Layout.Unit.points(680 - $slot.to_i64_wrap() * 64) }
			id = "mixed_${index.to_str()}"
			label = "Option ${index.to_str()}"
			if index % 2 == 0 {
				$page = $page.place_checkbox({ field: { id, label, state: if (index % 4 == 0) Checked else Unchecked }, origin })
			} else {
				$page = $page.place_text_field({ field: { id, label, width: 200, value: Prefilled("Ref ${index.to_str()}") }, origin })
			}
			$index = $index + 1
			$slot = $slot + 1
		}
		$pages = $pages.append($page.finish())
	}
	Pdf.fixed_document({ pages: $pages, language: "en", title: "Intake checklist" })
}

one_checkbox : Pdf.CheckboxProps, Layout.Point -> Document
one_checkbox = |field, origin| {
	page = Pdf.fixed_page({ width: 595, height: 842 })
		.place({ block: Pdf.title("Checkbox defaults"), frame: Layout.rect({ x: 56, y: 730, width: 482, height: 48 }) })
		.place_checkbox({ field, origin })
		.finish()
	Pdf.fixed_document({ pages: [page], language: "en", title: "Checkbox defaults" })
}

checkbox_default_equivalence : {} -> Try(Cases.Stats, Pdf.Error)
checkbox_default_equivalence = |_| {
	origin = { x: Layout.Unit.points(56), y: Layout.Unit.points(650) }
	implicit = one_checkbox({ id: "visit", label: "Request a site visit" }, origin)
	explicit = one_checkbox({ id: "visit", label: "Request a site visit", state: Unchecked }, origin)
	prepared = evidence(implicit, options, 0)?
	explicit_bytes = Pdf.to_bytes_with(explicit, options)?
	if prepared.bytes != explicit_bytes {
		crash "omitted and explicit Unchecked must be byte-identical"
	}
	Ok(prepared)
}

checkbox_rejections : {} -> Try(Cases.Stats, Pdf.Error)
checkbox_rejections = |_| {
	origin = { x: Layout.Unit.points(56), y: Layout.Unit.points(650) }
	field = Pdf.CheckboxProps.{ id: "visit", label: "Request a site visit" }
	valid = one_checkbox(field, origin)
	samples = [
		(valid, Pdf.Options.{}, "form.profile", "pages[0].placements[1].field"),
		(valid, Pdf.Options.{ profile: Standard }, "form.profile", "pages[0].placements[1].field"),
		(Intake.mixed_document(True), options, "form.checkbox.duplicate_id", "pages[0].placements[5].field.id"),
		(one_checkbox({ id: "visit.option", label: "Request a site visit" }, origin), options, "form.checkbox.id", "pages[0].placements[1].field.id"),
		(one_checkbox({ id: "visit", label: "   " }, origin), options, "form.checkbox.label", "pages[0].placements[1].field.label"),
		(one_checkbox(field, { x: Layout.Unit.millipoints(329001), y: 650 }), options, "form.checkbox.frame", "pages[0].placements[1]"),
		(one_checkbox(field, { x: 56, y: Layout.Unit.millipoints(818001) }), options, "form.checkbox.frame", "pages[0].placements[1]"),
		(mixed_scale(129), options, "form.count", "pages"),
	]
	for (document, selection, feature, path) in samples {
		if !rejects(Pdf.prepare(document, selection), feature, path)
			or !rejects(Pdf.to_bytes_with(document, selection), feature, path)
			or !rejects(Pdf.to_chunks_with(document, selection), feature, path) {
			crash "expected atomic checkbox rejection: ${feature} at ${path}"
		}
	}
	_ = Pdf.prepare(one_checkbox(field, { x: 329, y: 818 }), options)?
	_ = Pdf.prepare(mixed_scale(128), options)?
	evidence(Intake.mixed_document(False), options, samples.len() * 3)
}
