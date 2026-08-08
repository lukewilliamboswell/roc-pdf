import Document
import KernelColor
import KernelContent
import KernelEmit
import KernelFacadeFragments
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
import KernelFacadePipeline
import KernelFacadeScenes
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelFont
import KernelFontPlan
import KernelGate2Objects
import KernelGate3TaggedTextStructure
import KernelImage
import KernelLineLayout
import KernelObject
import KernelPageLayout
import KernelPdfFont
import KernelPdfText
import KernelScene
import KernelSemantics
import KernelShape
import KernelStructure
import KernelTextSemantics
import Layout
import Theme
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3FacadeOutputEvidence :: [].{
	probe : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	probe = |stage_code| {
		stage = match stage_code {
			0 => SemanticsReady
			1 => ShapeReady
			2 => LinesReady
			3 => PagesReady
			4 => TextReady
			5 => FragmentsReady
			6 => ScenesReady
			7 => OutputReady
			_ => return Err(InvalidRuntimeGuard)
		}
		document = Document.from_blocks({
			contents: [Document.paragraph("Café PDF generation in pure Roc.")],
			language: "en-AU",
			title: "Gate 3 facade output",
		})
		authoring = Document.normalize(document)
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		work = KernelFacadePipeline.probe(authoring, font, Theme.default, page_size, descriptor, pipeline_limits, stage) ? |_| EvidenceFailure
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [stage_code, work.occurrences, work.shaped_runs, work.lines, work.pages, work.final_runs, work.fragments, work.scene_commands, work.objects] })
	}

	visible : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	visible = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		document = Document.from_blocks({
			contents: [Document.paragraph("Café PDF generation in pure Roc.")],
			language: "en-AU",
			title: "Gate 3 facade output",
		})
		authoring = Document.normalize(document)
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		pipeline = KernelFacadePipeline.Plan.build(
			authoring,
			font,
			Theme.default,
			page_size,
			descriptor,
			pipeline_limits,
		) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelFacadePipeline.Plan.structure(pipeline)) ? |_| EvidenceFailure
		work = KernelFacadePipeline.Plan.work(pipeline)
		output_work = KernelFacadeOutput.Plan.work(KernelFacadePipeline.Plan.output(pipeline))
		Ok({
			bytes,
			work: [
				authoring.blocks.len(),
				work.occurrences,
				work.shaped_runs,
				work.lines,
				work.pages,
				work.final_runs,
				work.fragments,
				work.scene_commands,
				output_work.glyph_usages,
				output_work.font_entries,
				output_work.subset_bytes,
				output_work.text_glyph_visits,
				output_work.content_command_visits,
				output_work.content_bytes,
				work.objects,
				bytes.len(),
			],
		})
	}
}

page_size : Layout.Size
page_size = { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) }

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

pipeline_limits : KernelFacadePipeline.Limits
pipeline_limits = KernelFacadePipeline.Limits.make({
	fragment_semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 128, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
	fragments: KernelFacadeFragments.Limits.make({ max_fragments: 128, max_occurrences: 1, max_pages: 128 }),
	lines: KernelFacadeLines.Limits.make({
		line: KernelLineLayout.BatchLimits.make({
			line: KernelLineLayout.Limits.make({ max_boundaries: 129, max_candidates: 256, max_clusters: 128, max_glyph_indices: 128, max_glyphs: 128, max_lines: 128 }),
			max_key_probes: 64,
			max_lines: 128,
			max_runs: 1,
			max_table_slots: 8,
			max_templates: 1,
		}),
		max_blocks: 1,
		max_runs: 1,
	}),
	output: KernelFacadeOutput.Limits.make({
		content: KernelContent.Limits.make({ max_content_bytes: 65536, max_content_streams: 128 }),
		font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 256 }),
		images: KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
		max_objects: 512,
		objects: KernelGate2Objects.Limits.make({ max_objects: 503, max_pages: 128 }),
		structure: KernelGate3TaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 16384, max_unicode_mappings: 256, max_unicode_scalars: 512 }),
			object_limits: output_object_limits,
		}),
		text: KernelPdfText.Limits.make({ max_actual_text_scalars: 256, max_content_bytes: 65536, max_mappings: 256, max_placements: 0, max_source_scalars: 256 }),
	}),
	pages: KernelFacadePages.Limits.make({
		max_blocks: 1,
		max_rows: 128,
		page: KernelPageLayout.Limits.make({ max_blocks: 1, max_fragments: 128, max_lines: 128, max_pages: 128, max_placements: 128 }),
	}),
	scenes: KernelFacadeScenes.Limits.make({
		color: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
		max_commands: 256,
		max_groups: 128,
		max_page_group_edges: 128,
		max_pages: 128,
		scene: KernelScene.Limits.make({ max_commands: 256, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 128, max_pages: 128, max_path_segments: 0, max_paths: 0 }),
	}),
	semantics: KernelFacadeSemantics.Limits.make({
		max_artifacts: 0,
		max_content_spine: 2,
		max_nodes: 2,
		max_occurrences: 1,
		max_properties: 0,
		max_source_inputs: 1,
		semantics: KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 0, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		sources: KernelFacadeSources.Limits.make({
			max_hash_probes: 16,
			max_inputs: 1,
			max_source_bytes: 128,
			max_source_scalars: 128,
			max_table_slots: 8,
			max_unique_sources: 1,
			unicode: { max_graphemes: 128, max_line_boundaries: 129, max_scalars: 128, max_script_runs: 8 },
		}),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 128, max_text_source_scalars: 128, max_text_sources: 1 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 1, shape: KernelShape.Limits.make({ max_clusters: 128, max_glyphs: 128, max_scalars: 128, max_source_bytes: 128 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 128, max_glyph_indices: 128, max_glyphs: 128, max_pages: 128, max_placements: 128, max_runs: 128 }),
})

output_object_limits : KernelObject.Limits
output_object_limits = {
	max_array_items: 512,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 1024,
	max_direct_depth: 8,
	max_name_bytes: 8192,
	max_names: 256,
	max_objects: 512,
	max_payload_bytes: 200000,
	max_payloads: 256,
	max_streams: 256,
	max_text_string_bytes: 256,
	max_text_strings: 8,
	max_values: 2048,
}
