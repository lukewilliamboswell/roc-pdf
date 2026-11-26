import pdf.Document
import pdf.Pdf

Cases :: [].{
	Case : [Entries({ count : U64 }), FlowReference({ long : Bool }), FlowRejections, Wtpdf, Rejections]
	Stats : { bytes : List(U8), work : List(U64) }

	run : Case -> Stats
	run = |case| {
		result = match case {
			Entries({ count }) if count == 2 or count == 40 => evidence(count, options)
			Entries(_) => crash "CASE_SCALE_INVALID"
			FlowReference({ long }) => flow_evidence(if (long) LongLabel else ShortLabel)
			FlowRejections => reject_flow({})
			Wtpdf => evidence(2, { ..options, wtpdf: DeclareAccessibility })
			Rejections => reject_cases({})
		}
		match result {
			Ok(stats) => stats
			Err(error) => crash "GENERATED_CONTENTS_REJECTED: ${Str.inspect(error)}"
		}
	}
}

options : Pdf.Options
options = {
	page_size: Custom({ width: 320, height: 300 }),
	theme: { page_margin: { left: 32, right: 32, top: 32, bottom: 32 } },
}

props : Pdf.GeneratedContentsProps
props = {
	scope: Under("procedures"),
	depth: 1,
	page_width: 36,
	numbering: PageLabel,
	leader: Dots,
	overrides: [{ target: "recovery-2", title: "Follow-up recovery checks" }],
}

evidence : U64, Pdf.Options -> Try(Cases.Stats, Pdf.Error)
evidence = |count, result_options| {
	doc = handbook(count, props)
	{ prepared, report } = Pdf.prepare_with_report(doc, { options: result_options })?
	bytes = Pdf.to_bytes_prepared(prepared)?
	var $references = 0
	for outcome in report.facts.outcomes {
		match outcome {
			PageReferenceResolved({ destination, page, value, .. }) => {
				$references = $references + 1
				if destination != "recovery-${$references.to_str()}" or page < 2 or value != "S-${page.to_str()}" {
					crash "CONTENTS_REFERENCE_DRIFT"
				}
			}
			_ => {}
		}
	}
	if $references != count {
		crash "CONTENTS_ENTRY_COUNT_DRIFT"
	}
	Ok({ bytes, work: [report.facts.pages.len(), report.facts.blocks.len(), $references, bytes.len()] })
}

reject_cases : {} -> Try(Cases.Stats, Pdf.Error)
reject_cases = |_| {
	inputs = [
		({ ..props, depth: 0 }, "contents[0].depth"),
		({ ..props, scope: Under("no-procedure") }, "contents[0].scope"),
		({ ..props, scope: Under("appendix"), overrides: [] }, "contents[0].scope"),
		({ ..props, overrides: [{ target: "wrong", title: "Wrong target" }] }, "contents[0].overrides[0]"),
		({ ..props, overrides: [{ target: "recovery-1", title: "First" }, { target: "recovery-1", title: "Second" }] }, "contents[0].overrides[1]"),
	]
	for (selection, path) in inputs {
		doc = handbook(2, selection)
		if !rejects(Pdf.to_bytes_with(doc, options), path) or !rejects(Pdf.to_chunks_with(doc, options), path) {
			crash "GENERATED_CONTENTS_EXPECTED_REJECTION: ${path}"
		}
	}
	carrier = evidence(2, options)?
	Ok({ ..carrier, work: carrier.work.append(inputs.len()).append(inputs.len()) })
}

rejects : Try(a, Pdf.Error), Str -> Bool
rejects = |result, path| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature("document.generated_contents"), details, .. }], truncation: Complete, .. })) => details == [path]
	_ => False
}

handbook : U64, Pdf.GeneratedContentsProps -> Document
handbook = |count, selection| {
	var $body = [Pdf.destination_heading({ name: "procedures", level: 1, text: "Recovery procedures" })]
	var $index = 1.U64
	while $index <= count {
		if $index == 2 {
			$body = $body.append(Pdf.page_break)
		}
		name = "recovery-${$index.to_str()}"
		title = if ($index <= 2) "Recovery checks" else "Regional check ${$index.to_str()}"
		$body = $body.append(Pdf.destination_heading({ level: 2, text: title, name }))
		$body = $body.append(Pdf.paragraph("Document the result for region ${$index.to_str()}."))
		$index = $index + 1
	}
	Pdf.document({
		title: "Recovery checks handbook",
		language: "en-AU",
		page_labels: [{ start_page: 0, start_number: 1, prefix: "S-", style: DecimalArabic }],
		contents: [
			Pdf.generated_contents(selection),
			Pdf.page_break,
			Pdf.part($body),
			Pdf.destination_heading({ name: "appendix", level: 1, text: "Administrative appendix" }),
		],
	})
}

FlowCase : [LongLabel, ShortLabel, Cycle, Missing]

flow_options : Pdf.Options
flow_options = {
	page_size: Custom({ width: 254, height: 90 }),
	theme: { page_margin: { left: 18, right: 18, top: 16, bottom: 16 }, paragraph_spacing: 4 },
}

flow_document : FlowCase -> Document
flow_document = |variation| {
	target = if (variation == Missing) "unregistered" else "recovery"
	base = if (variation == LongLabel or variation == Cycle) "RECOVERY-CHECKS-" else "A-"
	first : Document.PageLabelRange
	first = { start_page: 0, start_number: 1, prefix: base, style: DecimalArabic }
	labels = if (variation == Cycle) [first, { start_page: 1, start_number: 2, prefix: "A-", style: DecimalArabic }] else [first]
	body = [
		Pdf.rich_paragraph([
			Pdf.text("For the regional recovery checks, see "),
			Pdf.inline_internal_link([Pdf.flow_page_reference({ destination: target, numbering: PageLabel })], "recovery"),
		]),
		Pdf.destination_heading({ level: 1, name: "recovery", text: "Recovery checks" }),
		Pdf.paragraph("Verify replica health."),
	]
	contents = if (variation == Cycle) body.append(Pdf.page_break).append(Pdf.paragraph("Appendix")) else body
	Pdf.document({
		language: "en-AU",
		title: "Recovery handbook",
		page_labels: labels,
		contents,
	})
}

flow_evidence : FlowCase -> Try(Cases.Stats, Pdf.Error)
flow_evidence = |variation| {
	{ prepared, report } = Pdf.prepare_with_report(flow_document(variation), { options: flow_options })?
	evidence_value = if (variation == LongLabel) "RECOVERY-CHECKS-2" else "A-1"
	evidence_page = if (variation == LongLabel) 2 else 1
	var $resolved = 0
	for outcome in report.facts.outcomes {
		match outcome {
			PageReferenceResolved({ destination: "recovery", page, value, path }) if page == evidence_page and value == evidence_value and path == "contents[0].inlines[1].inlines[0]" => {
				$resolved = $resolved + 1
			}
			_ => {}
		}
	}
	if $resolved != 1 {
		crash "FLOW_REFERENCE_RESOLUTION_DRIFT"
	}
	bytes = Pdf.to_bytes_prepared(prepared)?
	Ok({ bytes, work: [report.facts.pages.len(), report.facts.blocks.len(), $resolved, bytes.len()] })
}

reject_flow : {} -> Try(Cases.Stats, Pdf.Error)
reject_flow = |_| {
	cases = [(Cycle, "layout.reference_cycle"), (Missing, "navigation.reference_destination")]
	for (scenario, feature) in cases {
		doc = flow_document(scenario)
		selected = if (scenario == Cycle) { ..flow_options, page_size: Custom({ width: 260, height: 90 }) } else flow_options
		if !rejects_flow(Pdf.to_bytes_with(doc, selected), feature) or !rejects_flow(Pdf.to_chunks_with(doc, selected), feature) {
			crash "FLOW_REFERENCE_EXPECTED_REJECTION"
		}
	}
	carrier = flow_evidence(LongLabel)?
	Ok({ ..carrier, work: carrier.work.append(cases.len()).append(cases.len()) })
}

rejects_flow : Try(a, Pdf.Error), Str -> Bool
rejects_flow = |result, expected| match result {
	Err(InvalidDocument({ diagnostics: [{ feature: Feature(feature), details, .. }], truncation: Complete, .. })) => {
		if feature != expected or details != ["contents[0].inlines[1].inlines[0]"] {
			crash Str.inspect({ expected, feature, details })
		}
		True
	}
	Err(error) => crash Str.inspect(error)
	Ok(_) => crash "flow reference unexpectedly accepted"
}
