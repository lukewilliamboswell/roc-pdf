import pdf.Color
import pdf.Font
import pdf.KernelColor
import pdf.KernelContent
import pdf.KernelEmit
import pdf.KernelFacadeFragments
import pdf.KernelFacadeOutput
import pdf.KernelFacadeScenes
import pdf.KernelFont
import pdf.KernelFontPlan
import pdf.KernelObjectPlan
import pdf.KernelTaggedTextStructure
import pdf.KernelImage
import pdf.KernelObject
import pdf.KernelPdfFont
import pdf.KernelPdfText
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelStructure
import pdf.KernelTextOwnership
import pdf.KernelTextSemantics
import pdf.Layout
import pdf.Semantics
import pdf.Text
import "../../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Fixture :: [].{
	arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	arena = |repetitions| evidence_arena(repetitions)

	negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	negative = |repetitions| evidence_negative(repetitions)

	prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	prepare = |repetitions| evidence_prepare(repetitions)

	scene_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	scene_validate = |repetitions| evidence_scene_validate(repetitions)

	output_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	output_validate = |repetitions| evidence_output_validate(repetitions)

	validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	validate = |repetitions| evidence_validate(repetitions)
}

evidence_output_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_output_validate = |repetitions| {
	input = synthetic_input(repetitions)?
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| EvidenceFailure
	prepared = { ..input.prepared, text: remap_output_glyphs(input.prepared.text, font) ? |_| EvidenceFailure }
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, prepared, fragment_limits(prepared)) ? |_| EvidenceFailure
	fragments = KernelFacadeFragments.Arena.fragments(arena)
	page_count = prepared.pages.len()
	semantics = KernelTextSemantics.Plan.attach_fragments(input.preliminary, fragments, page_count, page_count, semantic_limits(input.repetitions, fragments.len())) ? |_| EvidenceFailure
	run_count = prepared.text.runs.len()
	styles = List.repeat({ color: Srgb(Rgb({ blue: 0, green: 0, red: 0 })), leading: Layout.Unit.from_raw(12000) }, run_count)
	scenes = KernelFacadeScenes.Plan.build_prepared(
		semantics,
		{
			page_size: { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) },
			pages: prepared.pages,
			placements: prepared.placements,
			styles,
			text: prepared.text,
		},
		scene_limits(run_count, page_count),
	) ? |_| EvidenceFailure
	output = KernelFacadeOutput.Plan.build(scenes, font, descriptor, output_limits(page_count)) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(KernelFacadeOutput.Plan.structure(output)) ? |_| EvidenceFailure
	work = KernelFacadeOutput.Plan.work(output)
	Ok({
		bytes,
		work: [
			repetitions,
			run_count,
			work.glyph_usages,
			work.font_entries,
			work.subset_bytes,
			work.resource_command_visits,
			work.text_runs,
			work.text_glyph_visits,
			work.text_content_bytes,
			work.content_command_visits,
			work.content_bytes,
			work.font_objects,
			work.objects,
			bytes.len(),
		],
	})
}

remap_output_glyphs : Text.Store, KernelFont.Inspection -> Try(Text.Store, [EvidenceFailure])
remap_output_glyphs = |store, font| {
	var $glyphs = List.with_capacity(store.glyphs.len())
	var $index = 0
	while $index < store.glyphs.len() {
		glyph = list_at(store.glyphs, $index)
		scalar = (0x61 + $index % 6).to_u32_wrap()
		glyph_id = match KernelFont.glyph_for_scalar(font, scalar) {
			None => return Err(EvidenceFailure)
			Some(value) => Text.GlyphId.from_raw(value)
		}
		$glyphs = $glyphs.append({ ..glyph, id: glyph_id })
		$index = $index + 1
	}
	Ok({ ..store, glyphs: $glyphs })
}

Input := {
	preliminary : KernelTextSemantics.Plan,
	prepared : KernelFacadeFragments.Prepared,
	repetitions : U64,
}

evidence_prepare : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_prepare = |repetitions| {
	input = synthetic_input(repetitions)?
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	store = input.prepared.text
	Ok({
		bytes,
		work: [
			input.repetitions,
			input.prepared.pages.len(),
			input.prepared.placements.len(),
			store.runs.len(),
			store.clusters.len(),
			store.glyph_indices.len(),
			store.glyphs.len(),
			bytes.len(),
		],
	})
}

evidence_arena : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_arena = |repetitions| {
	input = synthetic_input(repetitions)?
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, input.prepared, fragment_limits(input.prepared)) ? |_| EvidenceFailure
	work = KernelFacadeFragments.Arena.work(arena)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			input.repetitions,
			input.prepared.pages.len(),
			input.prepared.placements.len(),
			work.page_visits,
			work.placement_visits,
			work.fragment_writes,
			work.continuation_reads,
			work.continuation_writes,
			KernelFacadeFragments.Arena.fragments(arena).len(),
			bytes.len(),
		],
	})
}

evidence_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_validate = |repetitions| {
	input = synthetic_input(repetitions)?
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, input.prepared, fragment_limits(input.prepared)) ? |_| EvidenceFailure
	fragments = KernelFacadeFragments.Arena.fragments(arena)
	pages = input.prepared.pages.len()
	validated = KernelTextSemantics.Plan.attach_fragments(input.preliminary, fragments, pages, pages, semantic_limits(input.repetitions, fragments.len())) ? |_| EvidenceFailure
	semantic_plan = KernelTextSemantics.Plan.semantics(validated)
	semantic_store = KernelSemantics.Plan.store(semantic_plan)
	semantic_work = KernelSemantics.Plan.work(semantic_plan)
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			input.repetitions,
			fragments.len(),
			semantic_store.occurrence_fragments.len(),
			semantic_work.fragment_count_visits,
			semantic_work.fragment_validation_visits,
			semantic_work.prefix_steps,
			semantic_work.reverse_writes,
			bytes.len(),
		],
	})
}

evidence_scene_validate : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_scene_validate = |repetitions| {
	input = synthetic_input(repetitions)?
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, input.prepared, fragment_limits(input.prepared)) ? |_| EvidenceFailure
	fragments = KernelFacadeFragments.Arena.fragments(arena)
	page_count = input.prepared.pages.len()
	semantics = KernelTextSemantics.Plan.attach_fragments(input.preliminary, fragments, page_count, page_count, semantic_limits(input.repetitions, fragments.len())) ? |_| EvidenceFailure
	run_count = input.prepared.text.runs.len()
	styles = List.repeat({ color: Srgb(Rgb({ blue: 0, green: 0, red: 0 })), leading: Layout.Unit.from_raw(12000) }, run_count)
	scenes = KernelFacadeScenes.Plan.build_prepared(
		semantics,
		{
			page_size: { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) },
			pages: input.prepared.pages,
			placements: input.prepared.placements,
			styles,
			text: input.prepared.text,
		},
		scene_limits(run_count, page_count),
	) ? |_| EvidenceFailure
	scene_work = KernelFacadeScenes.Plan.work(scenes)
	ownership_work = KernelTextOwnership.Plan.work(KernelFacadeScenes.Plan.ownership(scenes))
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({
		bytes,
		work: [
			repetitions,
			run_count,
			scene_work.command_writes,
			scene_work.group_writes,
			scene_work.page_group_writes,
			scene_work.page_writes,
			ownership_work.command_visits,
			ownership_work.group_visits,
			ownership_work.run_visits,
			ownership_work.fragment_prefix_steps,
			ownership_work.fragment_writes,
			ownership_work.range_checks,
			ownership_work.text_fragments,
			bytes.len(),
		],
	})
}

evidence_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
evidence_negative = |repetitions| {
	input = synthetic_input(repetitions)?
	prepared = input.prepared
	first_placement = list_at(prepared.placements, 0)
	bad_placements = list_set(prepared.placements, 0, { ..first_placement, page: Semantics.PageId.from_index(prepared.pages.len()) })
	bad_page_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, { ..prepared, placements: bad_placements }, fragment_limits(prepared)) {
		Err(InvalidPlacement(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	first_run = list_at(prepared.text.runs, 0)
	bad_runs = list_set(prepared.text.runs, 0, { ..first_run, source: { scalars: Semantics.Range.from_start_and_length(0, 7), utf8_bytes: Semantics.Range.from_start_and_length(0, 7) } })
	bad_source_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, { ..prepared, text: { ..prepared.text, runs: bad_runs } }, fragment_limits(prepared)) {
		Err(SourceRangeMismatch(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	limit_rejected = match KernelFacadeFragments.Arena.build_prepared(input.preliminary, prepared, KernelFacadeFragments.Limits.make({ max_fragments: prepared.text.runs.len() - 1, max_occurrences: repetitions, max_pages: prepared.pages.len() })) {
		Err(LimitExceeded(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	arena = KernelFacadeFragments.Arena.build_prepared(input.preliminary, prepared, fragment_limits(prepared)) ? |_| EvidenceFailure
	pages = prepared.pages.len()
	attached = KernelTextSemantics.Plan.attach_fragments(input.preliminary, KernelFacadeFragments.Arena.fragments(arena), pages, pages, semantic_limits(repetitions, prepared.text.runs.len())) ? |_| EvidenceFailure
	preexisting_rejected = match KernelFacadeFragments.Arena.build_prepared(attached, prepared, fragment_limits(prepared)) {
		Err(InvalidPreliminaryFragments(_)) => 1
		_ => return Err(EvidenceFailure)
	}
	structure = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(structure) ? |_| EvidenceFailure
	Ok({ bytes, work: [bad_page_rejected, bad_source_rejected, limit_rejected, preexisting_rejected, bytes.len()] })
}

synthetic_input : U64 -> Try(Input, [EvidenceFailure, InvalidRepetitions])
synthetic_input = |repetitions| {
	if repetitions == 0 or repetitions > 100000 {
		return Err(InvalidRepetitions)
	}
	preliminary = KernelTextSemantics.Plan.build(
		semantic_store(repetitions),
		0,
		0,
		semantic_limits(repetitions, 0),
		KernelTextSemantics.Limits.make({
			max_text_properties: 0,
			max_text_property_bytes: 0,
			max_text_source_bytes: 6,
			max_text_source_scalars: 6,
			max_text_sources: 1,
		}),
	) ? |_| EvidenceFailure
	Ok({ preliminary, prepared: prepared_text(repetitions), repetitions })
}

semantic_store : U64 -> Semantics.Store
semantic_store = |occurrence_count| {
	var $content = [ChildNode(Semantics.NodeId.from_index(1))]
	var $occurrences = List.with_capacity(occurrence_count)
	var $index = 0
	while $index < occurrence_count {
		$content = $content.append(ContentOccurrence(Semantics.OccurrenceId.from_index($index)))
		$occurrences = $occurrences.append({
			fragments: empty_range,
			id: Semantics.OccurrenceId.from_index($index),
			language: Language("en"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(full_source_range)),
			text_properties: empty_range,
		})
		$index = $index + 1
	}
	{
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $content,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: [],
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: [
			{
				attributes: empty_range,
				content: Semantics.Range.from_start_and_length(0, 1),
				element_identifier: NoElementIdentifier,
				id: Semantics.NodeId.from_index(0),
				language: Language("en"),
				parent: DocumentRoot,
				role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
				structure_element: Semantics.StructureElementId.from_index(0),
				text_properties: empty_range,
			},
			{
				attributes: empty_range,
				content: Semantics.Range.from_start_and_length(1, occurrence_count),
				element_identifier: NoElementIdentifier,
				id: Semantics.NodeId.from_index(1),
				language: Language("en"),
				parent: ParentNode(Semantics.NodeId.from_index(0)),
				role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
				structure_element: Semantics.StructureElementId.from_index(1),
				text_properties: empty_range,
			},
		],
		non_text_sources: [],
		occurrence_fragments: [],
		occurrences: $occurrences,
		relationships: [],
		role_mappings: [],
		text_properties: [],
		text_sources: [{ unicode: "abcdef" }],
	}
}

prepared_text : U64 -> KernelFacadeFragments.Prepared
prepared_text = |occurrence_count| {
	run_count = occurrence_count * 2
	glyph_count = run_count * 3
	var $clusters = List.with_capacity(glyph_count)
	var $glyph_indices = List.with_capacity(glyph_count)
	var $glyphs = List.with_capacity(glyph_count)
	var $placements = List.with_capacity(run_count)
	var $runs = List.with_capacity(run_count)
	var $occurrence_index = 0
	while $occurrence_index < occurrence_count {
		var $line = 0
		while $line < 2 {
			run_index = $runs.len()
			glyph_start = $glyphs.len()
			source_start = $line * 3
			var $local = 0
			while $local < 3 {
				glyph_index = $glyphs.len()
				$clusters = $clusters.append({
					glyphs: Semantics.Range.from_start_and_length($glyph_indices.len(), 1),
					kind: OneToOne,
					source: {
						scalars: Semantics.Range.from_start_and_length(source_start + $local, 1),
						utf8_bytes: Semantics.Range.from_start_and_length(source_start + $local, 1),
					},
				})
				$glyph_indices = $glyph_indices.append(glyph_index)
				$glyphs = $glyphs.append({
					advance_x: Layout.Unit.from_raw(1000),
					advance_y: Layout.Unit.from_raw(0),
					id: Text.GlyphId.from_raw(($local + 1).to_u32_wrap()),
					offset_x: Layout.Unit.from_raw(0),
					offset_y: Layout.Unit.from_raw(0),
				})
				$local = $local + 1
			}
			run_id = Text.RunId.from_index(run_index)
			$runs = $runs.append({
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(glyph_start, 3),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(glyph_start, 3),
				id: run_id,
				instance: Font.InstanceId.from_index(0),
				language: Language("en"),
				occurrence: Semantics.OccurrenceId.from_index($occurrence_index),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(1000),
				source: {
					scalars: Semantics.Range.from_start_and_length(source_start, 3),
					utf8_bytes: Semantics.Range.from_start_and_length(source_start, 3),
				},
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			})
			page_index = run_index / 64
			$placements = $placements.append({
				origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) },
				page: Semantics.PageId.from_index(page_index),
				run: run_id,
			})
			$line = $line + 1
		}
		$occurrence_index = $occurrence_index + 1
	}
	var $pages = []
	var $run_start = 0
	while $run_start < run_count {
		page_index = $pages.len()
		length = U64.min(64, run_count - $run_start)
		$pages = $pages.append({
			id: Semantics.PageId.from_index(page_index),
			runs: Semantics.Range.from_start_and_length($run_start, length),
		})
		$run_start = $run_start + length
	}
	{
		pages: $pages,
		placements: $placements,
		text: {
			clusters: $clusters,
			glyph_indices: $glyph_indices,
			glyphs: $glyphs,
			runs: $runs,
			substitutions: [],
			transformations: [],
		},
	}
}

fragment_limits : KernelFacadeFragments.Prepared -> KernelFacadeFragments.Limits
fragment_limits = |prepared| KernelFacadeFragments.Limits.make({
	max_fragments: prepared.text.runs.len(),
	max_occurrences: prepared.text.runs.len(),
	max_pages: prepared.pages.len(),
})

semantic_limits : U64, U64 -> KernelSemantics.Limits
semantic_limits = |occurrences, fragments| KernelSemantics.Limits.make({
	max_attributes: 0,
	max_content_spine: occurrences + 1,
	max_fragments: fragments,
	max_namespaces: 1,
	max_nodes: 2,
	max_occurrences: occurrences,
	max_semantic_depth: 2,
})

scene_limits : U64, U64 -> KernelFacadeScenes.Limits
scene_limits = |runs, pages| KernelFacadeScenes.Limits.make({
	color: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
	max_commands: runs * 2,
	max_groups: runs,
	max_page_group_edges: runs,
	max_pages: pages,
	scene: KernelScene.Limits.make({ max_commands: runs * 2, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: runs, max_pages: pages, max_path_segments: 0, max_paths: 0 }),
})

output_limits : U64 -> KernelFacadeOutput.Limits
output_limits = |pages| KernelFacadeOutput.Limits.make({
	content: KernelContent.Limits.make({ max_content_bytes: 65536, max_content_streams: pages }),
	font_plan: KernelFontPlan.Limits.make({ max_retained_glyphs: 64 }),
	images: KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	max_objects: 128,
	objects: KernelObjectPlan.Limits.make({ max_objects: 119, max_pages: pages }),
	structure: KernelTaggedTextStructure.Limits.make({
		font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 64, max_unicode_scalars: 128 }),
		object_limits: output_object_limits,
	}),
	text: KernelPdfText.Limits.make({ max_actual_text_scalars: 4096, max_content_bytes: 65536, max_mappings: 64, max_placements: 0, max_source_scalars: 4096 }),
})

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

output_object_limits : KernelObject.Limits
output_object_limits = {
	max_array_items: 256,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 512,
	max_direct_depth: 8,
	max_name_bytes: 4096,
	max_names: 128,
	max_objects: 128,
	max_payload_bytes: 200000,
	max_payloads: 8,
	max_streams: 8,
	max_text_string_bytes: 256,
	max_text_strings: 8,
	max_values: 1024,
}

full_source_range : Semantics.TextRange
full_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 6),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 6),
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-fragment evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated facade-fragment evidence update escaped"
	}
}
