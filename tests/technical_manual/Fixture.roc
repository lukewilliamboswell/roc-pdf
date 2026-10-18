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

import diagram.PreparedDiagram
import "../../examples/vector-diagrams/fonts/Inter-Regular.ttf" as inter_bytes : List(U8)

Fixture :: [].{
	Error : [PdfFailure(Pdf.Error), PipelineFailure, FontFailure, InvalidScale]
	manual : U64 -> Try({ bytes : List(U8), work : List(U64) }, Error)
	manual = |count| evidence(count)
}

evidence : U64 -> Try({ bytes : List(U8), work : List(U64) }, Fixture.Error)
evidence = |count| {
	if count == 0 or count > 20 {
		return Err(InvalidScale)
	}
	registered = Font.Registry.empty.register(inter_bytes, { provision: BuiltIn, scripts: ["Latn"] }, Font.ValidationLimits.default) ? |_| FontFailure
	face = registered.face
	footer = |kind| Pdf.region({ height: 18, end: [Pdf.furniture_text([Pdf.text("${kind} "), Pdf.reserved_width(44, End, [Pdf.page_label]), Pdf.text(" | "), Pdf.page_number(Decimal), Pdf.text("/"), Pdf.total_pages(Decimal)])] })
	header = Pdf.region({ height: 30, start: [Pdf.furniture_text([Pdf.reserved_width(400, Start, [Pdf.running_label])])] })
	opening = Pdf.page_template({ footer: footer("OPEN"), gap: 8 })
	continuation = Pdf.page_template({ footer: footer("CONT"), gap: 8, header })
	var $contents = [Pdf.destination_heading("contents", 1, "Technical manual contents")]
	var $outline = [{ depth: 0, destination: "contents", open: True, title: "Contents" }]
	var $chapter = 0
	while $chapter < count {
		number = $chapter + 1
		name = "chapter-${number.to_str()}"
		$contents = $contents.append(
			Pdf.rich_paragraph([
				Pdf.inline_internal_link([Pdf.text("Procedure ${number.to_str()}")], name),
				Pdf.text(" — label "),
				Pdf.page_reference({ destination: name, width: 44, numbering: PageLabel, align: End }),
				Pdf.text("; physical "),
				Pdf.page_reference({ destination: name, width: 24, numbering: Physical, align: End }),
			]),
		)
		$outline = $outline.append({ depth: 0, destination: name, open: True, title: "Procedure ${number.to_str()}" })
		$chapter = $chapter + 1
	}
	$chapter = 0
	while $chapter < count {
		number = $chapter + 1
		name = "chapter-${number.to_str()}"
		var $rows = List.with_capacity(40)
		var $row = (0).to_u64()
		while $row < 40 {
			$rows = $rows.append(Pdf.row([Pdf.header_cell(Row, [Pdf.text("Step ${($row + 1).to_str()}")]), Pdf.cell([Pdf.text("Retain the procedure, its boxed instructions and the measured table columns.")])]))
			$row = $row + 1
		}
		body = [
			Pdf.destination_heading(name, 1, "Procedure ${number.to_str()}"),
			Pdf.rich_paragraph([Pdf.text("Contents physical "), Pdf.page_reference({ destination: "contents", width: 24, numbering: Physical, align: Start }), Pdf.text("; final procedure label "), Pdf.page_reference({ destination: "chapter-${count.to_str()}", width: 44, numbering: PageLabel, align: Center }), Pdf.text("; final physical "), Pdf.page_reference({ destination: "chapter-${count.to_str()}", width: 24, numbering: Physical, align: End }), Pdf.text(".")]),
			Pdf.callout({
				name: "Procedure panel ${number.to_str()}",
				padding: 8,
				contents: [
					Pdf.paragraph("One logical procedure keeps its numbered instruction and rich children together in reading order."),
					Pdf.numbered_list(
						{ start: 100 },
						[
							Pdf.list_item([
								Pdf.paragraph("Prepare procedure ${number.to_str()} without losing source whitespace."),
								Pdf.source_block({ face, text: Str.repeat("  verify = procedure_${number.to_str()}  \n\n", 16), padding: 6, foregrounds: [{ start: 2, end: 8, color: "#8000c0" }] }),
								Pdf.figure({ drawing: PreparedDiagram.drawing({}), alt: "Café: receive an order, check stock or order timber, then dispatch.", caption: Pdf.caption("Prepared procedure diagram ${number.to_str()}"), fit: ScaleToFit({ minimum_percent: 50 }) }),
								Pdf.callout({
									name: "Instruction detail ${number.to_str()}",
									padding: 6,
									contents: [
										Pdf.paragraph("The continued table remains inside the instruction and both callout panels."),
										Pdf.table({ caption: Pdf.caption("Procedure ${number.to_str()} checklist"), columns: [{ width: Fixed(66), align: Start }, { width: Share(1), align: Start }], header_rows: [Pdf.row([Pdf.header_cell(Column, [Pdf.text("Step")]), Pdf.header_cell(Column, [Pdf.text("Contents label "), Pdf.page_reference({ destination: "contents", width: 44, numbering: PageLabel, align: Start })])])], body_rows: $rows, row_split: SplitRows }),
										Pdf.paragraph("The inner callout closes after the complete checklist."),
									],
								}),
								Pdf.paragraph("Complete procedure ${number.to_str()} before the next chapter begins."),
							]),
						],
					),
					Pdf.paragraph("The outer callout closes after its one logical instruction."),
				],
			}),
		]
		$contents = $contents.append(Pdf.page_scope({ running_label: Label("Procedure ${number.to_str()} running"), page_templates: Templates({ opening, continuation }) }, body))
		$chapter = $chapter + 1
	}
	document = Pdf.document({ title: "Integrated technical manual", language: "en", contents: $contents, outline: $outline, page_labels: [{ prefix: "M-", start_number: 1, start_page: 0, style: DecimalArabic }], page_templates: Templates({ first: Pdf.first_page_template({ footer: footer("FRONT"), gap: 8 }), continuation: Pdf.page_template({ footer: footer("FRONT"), gap: 8 }) }) })
	theme : Theme
	theme = { face, table: { header_color: Themed(Theme.black), row_header_color: Themed(Theme.black), header_fill: Fill("#dbe4e9"), body_fills: { even: Fill("#e3e9ee") }, frame: Rule({ color: Theme.black, width: 0.5 }), column_rule: Rule({ color: Theme.black, width: 0.5 }) } }
	prepared = Pdf.prepare_with_report(document, { theme, fonts: Registered(registered.registry) }) ? PdfFailure
	bytes = Pdf.to_bytes_prepared(prepared.prepared) ? PdfFailure
	font = registered.registry.prepared_face(face) ? |_| FontFailure
	styled = { faces: [face], fonts: [font], roles: { code: Inherited, emphasis: Inherited, quote: Inherited, strong: Inherited } }
	plan = KernelFacadePipeline.Plan.build_styled_with_facts(Document.normalize(document), styled, theme, page_size, descriptor, probe_facts(document)?, pipeline_limits) ? |_| PipelineFailure
	flow = KernelFacadePipeline.Plan.work(plan)
	Ok({ bytes, work: [count, count * 40, count * PreparedDiagram.drawing({}).command_count(), flow.shaped_runs, flow.lines, flow.pages, flow.fragments, flow.final_runs, flow.scene_commands, flow.objects, flow.shape_metric_reads, flow.line_candidate_visits, flow.page_candidate_visits, flow.callout_contexts, flow.callout_ancestors, flow.callout_updates, flow.callout_fragments, flow.scope_visits, flow.template_region_visits, flow.reference_passes, flow.field_resolutions, flow.furniture_items, bytes.len()] })
}

probe_facts : Document -> Try(KernelMetadata.PlanFacts, Fixture.Error)
probe_facts = |document| {
	validated = KernelMetadata.validate({ created: Omitted, modified: Omitted, title: Document.metadata_title(document), language: Document.language(document) }, KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })) ? |_| PipelineFailure
	xmp = KernelXmp.Packet.build_identified(validated.facts, PdfA4Identification, 16384) ? |_| PipelineFailure
	Ok(WithDocumentFacts({ condition_identifier: KernelMetadata.srgb_condition_identifier, profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name, language: validated.facts.language, xmp: KernelXmp.Packet.bytes(xmp) }))
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
