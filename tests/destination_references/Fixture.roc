import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.KernelFacadeFurniture
import pdf.KernelFacadeLines
import pdf.KernelFacadePages
import pdf.KernelFacadeReferences
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelLineLayout
import pdf.KernelNavigation
import pdf.KernelPageLayout
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Pdf
import pdf.Theme
import "../assets/NotoSansMono-Code-Fixture.ttf" as mono_bytes : List(U8)
import "../assets/NotoSansSC-CJK-Fixture.ttf" as cjk_bytes : List(U8)

Fixture :: [].{
	Error : [InvalidCase, PdfFailure(Pdf.Error), FontFailure, ReferenceFailure(KernelFacadeReferences.Error), TemplateFailure, ExpectedRejection(U64)]
	references : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	references = |sections| {
		if sections != 2 and sections != 20 {
			return Err(InvalidCase)
		}
		registered = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
		font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
		evidence(reference_document(sections), theme, { theme: theme }, Single(font))
	}
	styled : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	styled = |context| {
		if context != 0 {
			return Err(InvalidCase)
		}
		body = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
		mono = body.registry.register(mono_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
		body_font = mono.registry.prepared_face(body.face) ? |_| FontFailure
		mono_font = mono.registry.prepared_face(mono.face) ? |_| FontFailure
		styled_theme : Theme
		styled_theme = { ..theme, face: body.face, inline: { emphasis: { font: Face(mono.face), scale: Percent(75) } } }
		document = Pdf.document({ title: "Reference inherited face and scale", language: "en", contents: [Pdf.destination_heading("start", 1, "Styled references"), Pdf.rich_paragraph([Pdf.text("Scaled label "), Pdf.emphasis([Pdf.in_language("fr", [Pdf.page_reference({ destination: "end", width: 60, numbering: PageLabel })])]), Pdf.text(" ends here.")]), Pdf.page_break, Pdf.destination_heading("end", 1, "Styled target")], page_labels: [{ start_page: 0, style: DecimalArabic, prefix: "m-", start_number: 8 }] })
		selection = Styled({ faces: [body.face, mono.face], fonts: [body_font, mono_font], roles: { code: Inherited, emphasis: Candidate(1), quote: Inherited, strong: Inherited } })
		evidence(document, styled_theme, { theme: styled_theme, fonts: Registered(mono.registry) }, selection)
	}
	ordered : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	ordered = |context| {
		if context != 0 {
			return Err(InvalidCase)
		}
		body = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
		cjk = body.registry.register(cjk_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, Font.ValidationLimits.default) ? |_| FontFailure
		configured = cjk.registry.with_policy([body.face, cjk.face]) ? |_| FontFailure
		selected_theme : Theme
		selected_theme = { ..theme, font_selection: Policy(configured.policy) }
		document = Pdf.document({ title: "Ordered mixed-face references", language: "en", contents: [Pdf.destination_heading("start", 1, "Ordered references"), Pdf.rich_paragraph([Pdf.text("Ordered label "), Pdf.in_language("zh-Hans", [Pdf.inline_internal_link([reference("end", PageLabel, 60)], "end")]), Pdf.line_break, Pdf.text("Physical "), reference("end", Physical, 24), Pdf.text(".")]), Pdf.page_break, Pdf.destination_heading("end", 1, "Ordered target")], page_labels: [{ start_page: 0, style: NoNumber, prefix: "p中", start_number: 1 }] })
		evidence(document, selected_theme, { theme: selected_theme, fonts: Registered(configured.registry) }, Ordered({ policy: configured.policy, registry: configured.registry }))
	}
	negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	negatives = |context| run_negatives(context)
}

theme : Theme
theme = { body: { size: 10, leading: 13 }, paragraph_spacing: 3, page_margin: { top: 40, bottom: 40, left: 50, right: 50 } }

page_size : Layout.Size
page_size = { width: 595, height: 842 }

reference : Str, Document.PageReferenceNumbering, Layout.Unit -> Pdf.Inline
reference = |destination, numbering, width| Pdf.page_reference({ destination, numbering, width })

reference_document : U64 -> Document
reference_document = |sections| {
	var $contents = [Pdf.destination_heading("toc", 1, "Destination reference evidence")]
	var $index = 1
	while $index <= sections {
		name = "section-${$index.to_str()}"
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("TOC ${$index.to_str()}: "), Pdf.inline_internal_link([reference(name, PageLabel, 48)], name), Pdf.text(" / physical "), reference(name, Physical, 24), Pdf.text(".")]))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.rich_paragraph([Pdf.inline_internal_link([reference("section-1", PageLabel, 48)], "section-1"), Pdf.line_break, reference("toc", Physical, 24)]))
	$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Adjacent "), reference("section-1", Physical, 24), reference("section-${sections.to_str()}", Physical, 24), Pdf.text(".")]))
	$contents = $contents.append(
		Pdf.numbered_list(
			{ start: 7 },
			[
				Pdf.list_item([
					Pdf.rich_paragraph([Pdf.text("List target "), Pdf.strong([reference("section-1", PageLabel, 48)]), Pdf.text(".")]),
					Pdf.callout({ name: "Referenced instruction", padding: 6, contents: [Pdf.rich_paragraph([Pdf.text("Callout target "), reference("section-${sections.to_str()}", PageLabel, 48), Pdf.text(".")]), Pdf.table({ caption: Pdf.caption("Reference-only table cell"), columns: [{ width: Content, align: End }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Page")]), Pdf.header_cell(Column, [Pdf.text("Meaning")])])], body_rows: [Pdf.row([Pdf.cell([Pdf.inline_internal_link([reference("section-1", PageLabel, 48)], "section-1")]), Pdf.cell([Pdf.text("One fixed atom belongs to the first section.")])])] })] }),
				]),
			],
		),
	)
	$index = 1
	while $index <= sections {
		$contents = $contents.append(Pdf.page_break)
		$contents = $contents.append(Pdf.destination_heading("section-${$index.to_str()}", 1, "Section ${$index.to_str()}"))
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.text("Back to "), Pdf.inline_internal_link([reference("toc", PageLabel, 48)], "toc"), Pdf.text("; final "), reference("section-${sections.to_str()}", Physical, 24), Pdf.text(".")]))
		$index = $index + 1
	}
	footer = Pdf.region({ height: 14, center: [Pdf.furniture_text([Pdf.text("Label "), Pdf.reserved_width(80, End, [Pdf.page_label]), Pdf.text(" | "), Pdf.page_number(Decimal)])] })
	Pdf.document({ title: "Exact destination page references", language: "en", contents: $contents, page_labels: [{ start_page: 0, style: RomanLower, prefix: "pré-", start_number: 1 }, { start_page: 1, style: LettersUpper, prefix: "A-", start_number: 27 }], page_templates: Templates({ first: Pdf.first_page_template({ footer, gap: 6 }), continuation: Pdf.page_template({ footer, gap: 6 }) }) })
}

evidence : Document, Theme, Pdf.Options, KernelFacadeShape.FontSelection -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
evidence = |document, selected_theme, options, selection| {
	bytes = Pdf.to_bytes_with(document, options) ? PdfFailure
	authoring = Document.normalize(document)
	flow = match authoring.templates {
		NoTemplates => NoFlowTemplate
		Templates(_) => {
			static = KernelFacadeFurniture.Static.build(authoring, selected_theme, page_size) ? |_| TemplateFailure
			WithFlowTemplate(KernelFacadeFurniture.Static.flow(static))
		}
	}
	plan = KernelFacadeReferences.Plan.build(authoring, selection, selected_theme, page_size, flow, reference_limits) ? ReferenceFailure
	view = KernelFacadeReferences.Plan.view(plan)
	work = view.work
	Ok({ bytes, work: [work.reference_atoms, work.normalization_chunks, work.literal_shape_requests, work.measured_items, work.measured_rows, work.committed_row_visits, work.anchor_item_visits, work.registry_lookup_steps, work.resolved_labels, work.resolved_label_bytes, work.mapping_cluster_visits, work.mapping_glyph_visits, work.reference_fit_run_visits, work.positioned_pieces, work.shape_metric_reads, work.measurement.hold_scalars, work.measurement.measured_items, work.measurement.wrapped_items, work.measurement.boundaries, work.measurement.row_items, work.separator_run_visits, work.separator_override_writes, bytes.len()] })
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
run_negatives = |context| {
	if context != 0 {
		return Err(InvalidCase)
	}
	make = |inlines, labels| Pdf.document({ title: "Reference rejection ${context.to_str()}", language: "en", contents: [Pdf.destination_paragraph("target", "Target."), Pdf.rich_paragraph(inlines)], page_labels: labels })
	plain = |destination, width| [reference(destination, Physical, width)]
	label = [reference("target", PageLabel, 60)]
	too_wide_cell = Pdf.document({ title: "Reference table rejection", language: "en", contents: [Pdf.destination_paragraph("target", "Target."), Pdf.table({ caption: Pdf.no_caption, columns: [{ width: Fixed(40), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Page")])])], body_rows: [Pdf.row([Pdf.cell(plain("target", 60))])] })] })
	bad_furniture = Pdf.document({ title: "Reference furniture rejection", language: "en", contents: [Pdf.destination_paragraph("target", "Target.")], page_templates: Templates({ first: Pdf.first_page_template({ header: Pdf.region({ height: 14, start: [Pdf.furniture_text(plain("target", 24))] }) }), continuation: Pdf.page_template({}) }) })
	checks = [
		{ document: make(plain("target", 0), []), feature: "document.page_reference", path: "contents[1].inlines[0]" },
		{ document: make(plain("target", -1), []), feature: "document.page_reference", path: "contents[1].inlines[0]" },
		{ document: make(plain("", 24), []), feature: "document.page_reference", path: "contents[1].inlines[0]" },
		{ document: make(plain("missing", 24), []), feature: "navigation.reference_destination", path: "contents[1].inlines[0]" },
		{ document: make(plain("target", 0.001), []), feature: "layout.reference_field_overflow", path: "contents[1].inlines[0]" },
		{ document: make(plain("target", 1000), []), feature: "layout.reference_items", path: "contents[1]" },
		{ document: make(label, [{ start_page: 0, style: NoNumber, prefix: "", start_number: 1 }]), feature: "layout.reference_label", path: "contents[1].inlines[0]" },
		{ document: make(label, [{ start_page: 0, style: LettersUpper, prefix: "", start_number: U64.highest }]), feature: "layout.reference_label", path: "contents[1].inlines[0]" },
		{ document: make(label, [{ start_page: 0, style: NoNumber, prefix: "p中", start_number: 1 }]), feature: "text.coverage_missing", path: "contents[1].inlines[0]" },
		{ document: too_wide_cell, feature: "layout.unbreakable_reference_items", path: "contents[1].table.body_rows[0].cells[0]" },
		{ document: bad_furniture, feature: "layout.furniture_inline", path: "templates.first.header.start[0].inlines[0]" },
	]
	var $passed = 0
	for check in checks {
		match Pdf.to_bytes_with(check.document, { theme: theme }) {
			Err(InvalidDocument({ diagnostics: [{ feature: Feature(found), details, .. }], truncation: Complete, .. })) if found == check.feature and details.any(|detail| detail == check.path) => {
				$passed = $passed + 1
			}
			_ => return Err(ExpectedRejection($passed))
		}
	}
	body = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	cjk = body.registry.register(cjk_bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Hani")] }, Font.ValidationLimits.default) ? |_| FontFailure
	configured = cjk.registry.with_policy([body.face, cjk.face]) ? |_| FontFailure
	ordered_options : Pdf.Options
	ordered_options = { theme: { ..theme, font_selection: Policy(configured.policy) }, fonts: Registered(configured.registry) }
	for check in [
		{ document: make(label, [{ start_page: 0, style: NoNumber, prefix: "中-", start_number: 1 }]), feature: "text.coverage_missing" },
		{ document: make(label, [{ start_page: 0, style: DecimalArabic, prefix: "ا", start_number: 1 }]), feature: "text.unsupported_script" },
	] {
		match Pdf.to_bytes_with(check.document, ordered_options) {
			Err(InvalidDocument({ diagnostics: [{ feature: Feature(found), details, .. }], truncation: Complete, .. })) if found == check.feature and details.any(|detail| detail == "contents[1].inlines[0]") => {
				$passed = $passed + 1
			}
			_ => return Err(ExpectedRejection($passed))
		}
	}
	bytes = Pdf.to_bytes(Pdf.document({ title: "Destination reference rejections ${$passed.to_str()}", language: "en", contents: [Pdf.paragraph("Invalid destination-reference inputs fail before emission.")] })) ? PdfFailure
	Ok({ bytes, work: [$passed] })
}

reference_limits : KernelFacadeReferences.Limits
reference_limits = {
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 65536,
		max_inline_depth: 8,
		max_nodes: 16384,
		max_occurrences: 16384,
		max_properties: 16384,
		max_source_inputs: 16384,
		semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536, max_fragments: 0, max_namespaces: 2, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 4000000,
			max_inputs: 16384,
			max_source_bytes: 1000000,
			max_source_scalars: 1000000,
			max_table_slots: 65536,
			max_unique_sources: 16384,
			unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 16384, max_text_property_bytes: 1000000, max_text_source_bytes: 1000000, max_text_source_scalars: 1000000, max_text_sources: 16384 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 65536, shape: KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 }) }),
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 1000001, max_candidates: 2000000, max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_lines: 1000000 }),
			max_key_probes: 4000000,
			max_lines: 1000000,
			max_runs: 65536,
			max_table_slots: 262144,
			max_templates: 65536,
		}),
		max_blocks: 16384,
		max_runs: 65536,
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 16384,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 16384, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
	}),
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
	navigation: KernelNavigation.standard_limits,
	max_reference_bytes: 128,
}
