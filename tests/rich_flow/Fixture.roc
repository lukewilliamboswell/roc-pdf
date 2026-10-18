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
import pdf.Scene

Fixture :: [].{
	Error : [PdfFailure(Pdf.Error), PipelineFailure, FontFailure, InvalidCase]
	lists : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	lists = |count| list_evidence(count)
	callouts : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	callouts = |count| callout_evidence(count)
	paragraphs : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	paragraphs = |count| paragraph_evidence(count)
}

callout_evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
callout_evidence = |count| {
	if count == 0 or count > 100 {
		return Err(InvalidCase)
	}
	registered = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	var $contents = List.with_capacity(count)
	var $index = 0
	while $index < count {
		var $rows = []
		var $row = 0
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
										Pdf.source_block({ face: registered.face, text: Str.repeat("  exact = source  \n\n", 25), padding: 6 }),
										Pdf.figure({ drawing: Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 120, 35), Theme.black), alt: "A bounded procedure diagram", caption: Pdf.caption("Inner diagram") }),
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
	registered = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	var $contents = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$contents = $contents.append(Pdf.rich_paragraph([Pdf.strong([Pdf.text("Note ${($index + 1).to_str()}. ")]), Pdf.text(Str.repeat("This wrapped paragraph belongs to one logical callout. ", 6))]))
		$index = $index + 1
	}
	prepared_evidence(Pdf.document({ title: "Paragraph callout continuation", language: "en", contents: [Pdf.paragraph("Before the callout."), Pdf.callout({ name: "Long note", contents: $contents }), Pdf.paragraph("After the callout.")] }), { face: registered.face, registry: registered.registry }, count)
}

prepared_evidence : Document, { registry : Font.Registry, face : Font.FaceId }, U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
prepared_evidence = |document, registered, count| {
	theme : Theme
	theme = { face: registered.face, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black) } }
	{ prepared, report } = Pdf.prepare_with_report(document, { theme, fonts: Registered(registered.registry) }) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared) ? PdfFailure
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	styled = { faces: [registered.face], fonts: [font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, NoDocumentFacts, pipeline_limits) ? |_| PipelineFailure
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
	registered = Font.Registry.empty.register(KernelBuiltInFont.bytes, { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] }, Font.ValidationLimits.default) ? |_| FontFailure
	var $items = List.with_capacity(count)
	var $index = 0
	while $index < count {
		var $rows = List.with_capacity(8)
		var $row = 0
		while $row < 8 {
			$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("Part ${($row + 1).to_str()}")]), Pdf.cell([Pdf.text("Measured inside this numbered instruction.")])]))
			$row = $row + 1
		}
		$items = $items.append(
			Pdf.list_item([
				Pdf.paragraph("Instruction ${($index + 1).to_str()}: prepare the workflow."),
				Pdf.source_block({ face: registered.face, text: Str.repeat("  keep = exact_source  \n\n", 15), padding: 8 }),
				Pdf.paragraph("The source and diagram belong to this instruction."),
				Pdf.figure({ drawing: Scene.Drawing.empty.rectangle(Layout.rect(0, 0, 110, 30), Theme.black), alt: "A rectangular workflow stage", caption: Pdf.caption("Workflow stage") }),
				Pdf.table({ caption: Pdf.caption("Instruction parts"), columns: [{ width: Fixed(65), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Part")]), Pdf.header_cell(Column, [Pdf.text("Instruction detail")])])], body_rows: $rows }),
				Pdf.bullet_list([Pdf.list_item([Pdf.paragraph("Check the nested result."), Pdf.source_block({ face: registered.face, text: "nested = preserved" })])]),
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
	styled = { faces: [registered.face], fonts: [font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	pipeline = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, NoDocumentFacts, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(pipeline)
	Ok({ bytes, work: [count, flow.shaped_runs, flow.lines, flow.pages, flow.final_runs, flow.fragments, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, report.facts.outcomes.len(), flow.callout_contexts, flow.callout_ancestors, flow.callout_updates, flow.callout_fragments, bytes.len()] })
}

page_size : Layout.Size
page_size = { height: 842, width: 595 }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
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
		page: KernelPageLayout.Limits.make({ max_blocks: 16384, max_fragments: 1000000, max_lines: 1000000, max_pages: 1024, max_placements: 1000000 }),
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
