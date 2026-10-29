import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelFacadeFragments
import pdf.KernelFacadeLines
import pdf.KernelFacadeOutput
import pdf.KernelFacadePages
import pdf.KernelFacadeScenes
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeShape
import pdf.KernelFacadeSources
import pdf.KernelFacadeText
import pdf.KernelFontPlan
import pdf.KernelImage
import pdf.KernelLineLayout
import pdf.KernelNavigation
import pdf.KernelObject
import pdf.KernelObjectPlan
import pdf.KernelPageLayout
import pdf.KernelPdfText
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelShape
import pdf.KernelSrgbProfile
import pdf.KernelTaggedTextStructure
import pdf.KernelTextSemantics
import pdf.Color
import pdf.Document
import pdf.Font
import pdf.KernelBuiltInFont
import pdf.KernelFacadePipeline
import pdf.KernelPdfFont
import pdf.Layout
import pdf.Pdf
import pdf.Theme
import pdf.KernelMetadata
import pdf.KernelXmp
import pdf.Scene

Fixture :: [].{
	Error : [PdfFailure(Pdf.Error), PipelineFailure, FontFailure, InvalidCase, MissingRejection(U64)]
	lists : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	lists = |count| list_evidence(count)
	callouts : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	callouts = |count| callout_evidence(count)
	paragraphs : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	paragraphs = |count| paragraph_evidence(count)
	negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	negatives = |context| negative_evidence(context)
	ownership : U64, Bool -> Try({ bytes : List(U8), work : List(U64) }, Error)
	ownership = |count, shared| ownership_evidence(count, shared)
	zero_padding : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	zero_padding = |context| zero_padding_evidence(context)
	scoped_tables : U64, U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	scoped_tables = |count, mode| scoped_table_evidence(count, mode)
}

## Three exact-boundary pages per scope. The opening and continuation frames
## differ, with no furniture gap to hide a decoration outside the body.
scoped_table_evidence : U64, U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
scoped_table_evidence = |count, mode| {
	if count == 0 or count > 20 or mode > 5 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	region = |height, label| Pdf.region({ height, start: [Pdf.furniture_text([Pdf.text(label)])] })
	var $contents = List.with_capacity(count + 1)
	var $index = 0
	while $index < count {
		number = ($index + 1).to_str()
		var $rows = List.with_capacity(80)
		var $row = (0).to_u64()
		while $row < 80 {
			label = "S${number} row ${($row + 1).to_str()}"
			$row = $row + 1
			cells = if mode == 4 {
				[Pdf.header_cell(Row, [Pdf.text(label)]).spanning(2)]
			} else {
				first = Pdf.header_cell(Row, [Pdf.text(label)])
				[if (mode == 1) first.shaded("#e1e8ef") else first, Pdf.cell([Pdf.text("Boundary data")])]
			}
			$rows = $rows.append(Pdf.row(cells))
		}
		header = if mode == 4 {
			[Pdf.header_cell(Both, [Pdf.text("Step")]).spanning(2)]
		} else {
			[Pdf.header_cell(Column, [Pdf.text("Step")]), Pdf.header_cell(Column, if (mode == 5) [Pdf.text("End "), Pdf.page_reference({ destination: "end", width: 24, numbering: Physical, align: End })] else [Pdf.text("Detail")])]
		}
		opening = Pdf.page_template({ header: region(24, "OPEN ${number}"), footer: region(34, "LOW ${number}"), gap: 0 })
		continuation = Pdf.page_template({ header: region(44, "CONT ${number}"), footer: region(54, "LOW ${number}"), gap: 0 })
		$contents = $contents.append(Pdf.page_scope({ page_templates: Templates({ opening, continuation }) }, [Pdf.table({ caption: Pdf.no_caption, columns: [{ width: Fixed(100), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row(header)], body_rows: $rows })]))
		$index = $index + 1
	}
	$contents = $contents.append(Pdf.destination_heading({ name: "end", level: 1, text: "End target" }))
	theme : Theme
	theme = { face: registered.face, body: { size: 10, leading: 14 }, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black), row_gap: 6, header_fill: if (mode == 0 or mode == 5) Fill("#cbd9e4") else NoFill, body_fills: { odd: if (mode == 0 or mode == 5) Fill("#eef2f5") else NoFill, even: if (mode == 0 or mode == 5) Fill("#e1e8ef") else NoFill }, column_rule: if (mode == 0 or mode == 2 or mode == 4 or mode == 5) Rule({ color: Theme.black, width: 0.5 }) else NoRule, frame: if (mode == 0 or mode == 5) Rule({ color: Theme.black, width: 0.5 }) else NoRule, rule: if (mode == 3) Rule({ color: Theme.black, width: 0.5 }) else NoRule, body_rule: if (mode == 3) Rule({ color: Theme.black, width: 0.5 }) else NoRule } }
	prepared_evidence_styled(Pdf.document({ title: "Scoped table paint footprints", language: "en", contents: $contents }), { face: registered.face, registry: registered.registry }, count, theme)
}

ownership_evidence : U64, Bool -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
ownership_evidence = |count, shared| {
	if count == 0 or count > 100 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	make = |number| Pdf.callout({ name: "Reusable note ${number.to_str()}", contents: [Pdf.rich_paragraph([Pdf.strong([Pdf.text("Reusable. ")]), Pdf.text("Shared authoring must preserve independent semantic occurrences.")])] })
	retained = make(0)
	var $contents = List.with_capacity(count)
	var $index = 0
	while $index < count {
		block = if shared {
			retained
		} else {
			make($index + 1)
		}
		$contents = $contents.append(block)
		$index = $index + 1
	}
	prepared_evidence(Pdf.document({ title: "Shared rich callout ownership", language: "en", contents: $contents }), { face: registered.face, registry: registered.registry }, count)
}

zero_padding_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
zero_padding_evidence = |context| {
	if context != 0 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	var $rows = List.with_capacity(80)
	var $row = (0).to_u64()
	while $row < 80 {
		$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("Row ${($row + 1).to_str()}")]), Pdf.cell([Pdf.text("The table frame stays inside the filled panel on every continued page.")])]))
		$row = $row + 1
	}
	document = Pdf.document({ title: "Zero-padding callout table continuation", language: "en", contents: [Pdf.callout({ name: "Flush table panel", padding: 0, panel: { fill: Fill("#eef0f2"), border: NoBorder }, contents: [Pdf.table({ caption: Pdf.caption("Continued table with a flush panel"), columns: [{ width: Fixed(60), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Row")]), Pdf.header_cell(Column, [Pdf.text("Detail")])])], body_rows: $rows, row_split: SplitRows })] })] })
	prepared_evidence_styled(document, { face: registered.face, registry: registered.registry }, 80, { face: registered.face, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black), header_fill: Fill("#dbe4e9"), body_fills: { even: Fill("#e3e9ee") }, frame: Rule({ color: Theme.black, width: 0.5 }), column_rule: Rule({ color: Theme.black, width: 0.5 }) } })
}

negative_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
negative_evidence = |context| {
	if context != 0 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	options : Pdf.Options
	options = { fonts: Registered(registered.registry) }
	make = |block| Pdf.document({ title: "Rich flow diagnostic contracts", language: "en", contents: [block] })
	valid = [Pdf.paragraph("A valid note.")]
	var $deep = Pdf.paragraph("Too deep")
	var $depth = 0
	while $depth < 17 {
		$deep = Pdf.callout({ name: "Nested", contents: [$deep], padding: 1 })
		$depth = $depth + 1
	}
	var $list = Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Last list")])])
	$depth = 1
	while $depth < 5 {
		$list = Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Lead"), Pdf.callout({ name: "A nested list", contents: [$list], padding: 1 })])])
		$depth = $depth + 1
	}
	report_document = make(Pdf.callout({ name: "Budgeted note", contents: valid }))
	report = (Pdf.prepare_with_report(report_document, options) ? PdfFailure).report
	entries = report.facts.pages.len() + report.facts.blocks.len() + report.facts.alternatives.len() + report.facts.outcomes.len() + report.facts.coverage.len() + report.obligations.len()
	report_budget_rejected = match Pdf.prepare_with_report_budget(report_document, { options: options, budget: { max_entries: entries - 1 } }) {
		Err(InvalidDocument(batch)) => batch.diagnostics.any(|diagnostic| diagnostic.feature == Feature("report.budget_exceeded"))
		_ => False
	}
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	page_budget_rejected = match KernelFacadePipeline.probe(Document.normalize(make(Pdf.callout({ name: "Page work bound", contents: [Pdf.paragraph(Str.repeat("Bounded callout continuation. ", 400))] }))), font, { face: registered.face }, page_size, descriptor, pipeline_limits_for(1), PagesReady) {
		Err(Pages(_)) => True
		_ => False
	}
	checks = [
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Empty", contents: [] })), options), "semantics.empty_container"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "", contents: valid })), options), "layout.callout_style"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Negative", contents: valid, padding: -1 })), options), "layout.callout_style"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Border outside padding", contents: valid, padding: 0 })), options), "layout.callout_style"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Unpainted", contents: valid, panel: { fill: NoFill, border: NoBorder } })), options), "layout.callout_style"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Too narrow", contents: valid, padding: 1000 })), options), "layout.callout_width"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Heading", contents: [Pdf.heading(1, "A heading is outside the child subset")] })), options), "semantics.callout_content"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Section", contents: [Pdf.section(valid)] })), options), "semantics.callout_content"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Spacer", contents: [Pdf.paragraph("Before"), Pdf.spacer(3)] })), options), "semantics.callout_content"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Page break", contents: [Pdf.paragraph("Before"), Pdf.page_break, Pdf.paragraph("After")] })), options), "semantics.callout_content"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Whole", contents: [Pdf.paragraph(Str.repeat("Required unsplittable content. ", 400))], fragmentation: Unsplittable })), options), "layout.keep_conflict"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Source", contents: [Pdf.source_block({ face: Face(registered.face), text: Str.repeat("exact\n", 100), fragmentation: Unsplittable })] })), options), "source.oversize"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "Figure", contents: [Pdf.figure({ drawing: Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 450, height: 20 }), color: Theme.black }), alt: "Too wide inside the padding", caption: Pdf.no_caption })] })), options), "document.figure_oversize"),
		rejected(Pdf.to_bytes_with(make($deep), options), "semantics.container_depth"),
		rejected(Pdf.to_bytes_with(make($list), options), "semantics.list_depth"),
		rejected(Pdf.to_bytes_with(make(Pdf.callout({ name: "No fresh-page unit", contents: valid, padding: 80 })), { ..options, page_size: Custom({ width: 595, height: 200 }) }), "layout.oversize_block"),
		report_budget_rejected,
		page_budget_rejected,
	]
	var $passed = 0
	for check in checks {
		if !check {
			return Err(MissingRejection($passed))
		}
		$passed = $passed + 1
	}
	bytes = Pdf.to_bytes_with(make(Pdf.paragraph("All rich-flow rejections returned located diagnostics without output.")), options) ? PdfFailure
	Ok({ bytes, work: [$passed, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, bytes.len()] })
}

rejected : Try(List(U8), Pdf.Error), Str -> Bool
rejected = |outcome, expected| match outcome {
	Err(InvalidDocument(batch)) => batch.diagnostics.any(
		|diagnostic| match diagnostic.feature {
			Feature(feature) => feature == expected and !diagnostic.details.is_empty()
			NoFeature => False
		},
	)
	_ => False
}

callout_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
callout_evidence = |count| {
	if count == 0 or count > 100 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	var $contents = List.with_capacity(count)
	var $index = 0
	while $index < count {
		var $rows = []
		var $row = (0).to_u64()
		while $row < 25 {
			$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("Task ${($row + 1).to_str()}")]), Pdf.cell([Pdf.text("This cell remains inside both panels and its numbered instruction.")])]))
			$row = $row + 1
		}
		$contents = $contents.append(
			Pdf.callout({
				name: "Outer ${(1 + $index).to_str()}",
				padding: 10,
				contents: [
					Pdf.rich_paragraph([Pdf.strong([Pdf.text("Warning. ")]), Pdf.text("Preserve the complete procedure and its examples."), Pdf.inline_link([Pdf.text("Reference")], "https://example.test/manual")]),
					Pdf.numbered_list(
						{ start: 100 },
						[
							Pdf.list_item([
								Pdf.paragraph("The inner callout belongs to instruction 100."),
								Pdf.callout({
									name: "Inner ${(1 + $index).to_str()}",
									padding: 8,
									contents: [
										Pdf.paragraph("Inner paragraph before the exact source."),
										Pdf.source_block({ face: Face(registered.face), text: Str.repeat("  exact = source  \n\n", 25), padding: 6 }),
										Pdf.figure({ drawing: Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 120, height: 35 }), color: Theme.black }), alt: "A bounded procedure diagram", caption: Pdf.caption("Inner diagram") }),
										Pdf.table({ caption: Pdf.caption("Inner tasks"), columns: [{ width: Fixed(60), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Task")]), Pdf.header_cell(Column, [Pdf.text("Detail")])])], body_rows: $rows, row_split: SplitRows }),
										Pdf.paragraph("Inner paragraph after the continued table."),
									],
								}),
								Pdf.paragraph("Finish the instruction without generating another label."),
							]),
							Pdf.list_item([Pdf.paragraph("The next generated label is 101.")]),
						],
					),
					Pdf.paragraph("Outer paragraph after the complete numbered procedure."),
				],
			}),
		)
		$index = $index + 1
	}
	prepared_evidence(Pdf.document({ title: "Rich continued callouts", language: "en", contents: $contents }), { face: registered.face, registry: registered.registry }, count)
}

paragraph_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
paragraph_evidence = |count| {
	if count == 0 or count > 500 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	var $contents = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.strong([Pdf.text("Note ${($index + 1).to_str()}. ")]), Pdf.text(Str.repeat("This wrapped paragraph belongs to one logical callout. ", 6))]))
		$index = $index + 1
	}
	prepared_evidence(Pdf.document({ title: "Paragraph callout continuation", language: "en", contents: [Pdf.paragraph("Before the callout."), Pdf.callout({ name: "Long note", contents: $contents }), Pdf.paragraph("After the callout.")] }), { face: registered.face, registry: registered.registry }, count)
}

probe_facts : Document -> Try(KernelMetadata.PlanFacts, Fixture.Error)
probe_facts = |document| {
	validated = KernelMetadata.validate({ created: Omitted, modified: Omitted, title: Document.metadata_title(document), language: Document.language(document) }, KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })) ? |_| PipelineFailure
	xmp = KernelXmp.Packet.build_identified(validated.facts, PdfA4Identification, 16384) ? |_| PipelineFailure
	Ok(WithDocumentFacts({ condition_identifier: KernelMetadata.srgb_condition_identifier, profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name, language: validated.facts.language, xmp: KernelXmp.Packet.bytes(xmp) }))
}

prepared_evidence : Document, { registry : Font.Registry, face : Font.FaceId }, U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
prepared_evidence = |document, registered, count| {
	theme : Theme
	theme = { face: registered.face, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black) } }
	prepared_evidence_styled(document, registered, count, theme)
}

prepared_evidence_styled : Document, { registry : Font.Registry, face : Font.FaceId }, U64, Theme -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
prepared_evidence_styled = |document, registered, count, theme| {
	{ prepared, report } = Pdf.prepare_with_report(document, { theme, fonts: Registered(registered.registry) }) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? PdfFailure
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	styled = { faces: [registered.face], fonts: [font], inline_faces: [], face_indexes: [], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, probe_facts(document)?, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)
	var $panels = 0
	for outcome in report.facts.outcomes {
		match outcome {
			CalloutFragmentPlaced(_) => {
				$panels = $panels + 1
			}
			_ => {}
		}
	}
	Ok({ bytes, work: [count, flow.shaped_runs, flow.lines, flow.pages, flow.final_runs, flow.fragments, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, $panels, flow.callout_contexts, flow.callout_ancestors, flow.callout_updates, flow.callout_fragments, bytes.len()] })
}

list_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
list_evidence = |count| {
	if count == 0 or count > 100 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register({ bytes: KernelBuiltInFont.bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, limits: Font.ValidationLimits.default }) ? |_| FontFailure
	var $items = List.with_capacity(count)
	var $index = 0
	while $index < count {
		var $rows = List.with_capacity(8)
		var $row = (0).to_u64()
		while $row < 8 {
			$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("Part ${($row + 1).to_str()}")]), Pdf.cell([Pdf.text("Measured inside this numbered instruction.")])]))
			$row = $row + 1
		}
		$items = $items.append(
			Pdf.list_item([
				Pdf.paragraph("Instruction ${($index + 1).to_str()}: prepare the workflow."),
				Pdf.source_block({ face: Face(registered.face), text: Str.repeat("  keep = exact_source  \n\n", 15), padding: 8, foregrounds: [{ start: 2, end: 6, color: "#8000c0" }] }),
				Pdf.paragraph("The source and diagram belong to this instruction."),
				Pdf.figure({ drawing: Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 110, height: 30 }), color: Theme.black }), alt: "A rectangular workflow stage", caption: Pdf.caption("Workflow stage") }),
				Pdf.table({ caption: Pdf.caption("Instruction parts"), columns: [{ width: Fixed(65), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Part")]), Pdf.header_cell(Column, [Pdf.text("Instruction detail")])])], body_rows: $rows }),
				Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Check the nested result."), Pdf.source_block({ face: Face(registered.face), text: "nested = preserved" })])]),
				Pdf.paragraph("Complete this instruction before the next generated label."),
			]),
		)
		$index = $index + 1
	}
	document = Pdf.document({ title: "Rich numbered procedures", language: "en", contents: [Pdf.numbered_list({ start: 100 }, $items)] })
	theme : Theme
	theme = { face: registered.face, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black) } }
	{ prepared, report } = Pdf.prepare_with_report(document, { theme, fonts: Registered(registered.registry) }) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? PdfFailure
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	styled = { faces: [registered.face], fonts: [font], inline_faces: [], face_indexes: [], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, probe_facts(document)?, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)
	Ok({ bytes, work: [count, flow.shaped_runs, flow.lines, flow.pages, flow.final_runs, flow.fragments, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, report.facts.outcomes.len(), flow.callout_contexts, flow.callout_ancestors, flow.callout_updates, flow.callout_fragments, bytes.len()] })
}

page_size : Layout.Size
page_size = { height: 842, width: 595 }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = pipeline_limits_for(1024)

pipeline_limits_for : U64 -> KernelFacadePipeline.Limits
pipeline_limits_for = |max_pages| KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 65536, max_content_spine: 65536 + 65536, max_fragments: 1000000, max_namespaces: 2, max_nodes: 16384, max_occurrences: 16384, max_semantic_depth: 48 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 1000000, max_occurrences: 16384, max_pages: 1024 }),
	navigation: KernelNavigation.standard_limits,
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
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 16000000, max_content_streams: 1024 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 10000 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 67108864, max_encoded_bytes: 67108864, max_height: 16384, max_markers: 4096, max_resources: 2048, max_width: 16384 }),
		max_objects: 65536,
		objects: KernelObjectPlan.Limits.make({ max_objects: 65527, max_pages: 1024 }),
		structure: KernelTaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 1000000, max_unicode_mappings: 10000, max_unicode_scalars: 1000000 }),
			object_limits: object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 1000000, max_content_bytes: 16000000, max_mappings: 10000, max_placements: 0, max_source_scalars: 16000000 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 16384,
		max_rows: 1000000,
		page: KernelPageLayout.Limits.make({ max_blocks: 16384, max_fragments: 1000000, max_lines: 1000000, max_pages, max_placements: 1000000 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 2, max_tags: KernelSrgbProfile.tag_count }),
		max_commands: 2000000,
		max_groups: 1000000,
		max_page_group_edges: 1000000,
		max_pages: 1024,
		scene: KernelScene.Limits.make({ max_commands: 2000000, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1000000, max_pages: 1024, max_path_segments: 1000000, max_paths: 1000000 }),
	}),
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
	text: KernelFacadeText.Limits.make({ max_clusters: 1000000, max_glyph_indices: 1000000, max_glyphs: 1000000, max_pages: 1024, max_placements: 1000000, max_runs: 1000000 }),
})

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 4000000,
	max_byte_string_bytes: 8388608,
	max_byte_strings: 1000000,
	max_dictionary_entries: 4000000,
	max_direct_depth: 8,
	max_name_bytes: 8388608,
	max_names: 1000000,
	max_objects: 65536,
	max_payload_bytes: 16000000,
	max_payloads: 100000,
	max_streams: 100000,
	max_text_string_bytes: 1000000,
	max_text_strings: 16384,
	max_values: 4000000,
}
