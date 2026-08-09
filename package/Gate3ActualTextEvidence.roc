import Color
import Font
import KernelEmit
import KernelContent
import KernelDiscretionaryHyphen
import KernelColor
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelGsub
import KernelGate2Objects
import KernelGate3FontObjects
import KernelGate3TaggedTextStructure
import KernelImage
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelShape
import KernelStructure
import KernelTagged
import KernelTextSemantics
import KernelTextOwnership
import KernelUnicode
import Layout
import Semantics
import Scene
import Text
import Image
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)
import "../vendor/fonts/Inter-4.1-Regular.ttf" as supplementary_font_bytes : List(U8)
import "../tests/assets/NotoSansSC-CJK-Fixture.ttf" as cjk_font_bytes : List(U8)
import "../tests/assets/IBMPlexSerif-FiLigature-Fixture.ttf" as ligature_font_bytes : List(U8)

Gate3ActualTextEvidence :: [].{
	ligature_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	ligature_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_ligature_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.work.run_visits,
				sample.shape.work.cluster_visits,
				sample.shape.work.glyph_visits,
				sample.shape.work.glyph_index_visits,
				text_work.source_scalar_visits,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	## The exact parsed `liga` fact is part of the advanced boundary. Mutating
	## only its output makes the otherwise valid `fi` run fail before a scene or
	## PDF plan can be constructed.
	ligature_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	ligature_negative = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = ligature_font({}) ? |_| EvidenceFailure
		f_glyph = required_glyph(font, 0x0066) ? |_| EvidenceFailure
		i_glyph = required_glyph(font, 0x0069) ? |_| EvidenceFailure
		fact = KernelGsub.validate_ligature(font, { feature: liga_feature, input: [f_glyph, i_glyph], language: Default, output: ligature_output_glyph, script: latin_script_tag }, ligature_gsub_limits({})) ? |_| EvidenceFailure
		store = ligature_store(Font.InstanceId.from_index(0), ligature_output_glyph)
		rejected = match KernelShape.validate_advanced_with_ligature_fact(
			font,
			ligature_source,
			store,
			{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
			{ ..fact.fact, output: i_glyph },
			ligature_shape_limits({}),
		) {
			Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 })) => Bool.True
			_ => Bool.False
		}
		if !rejected {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [1, bytes.len()] })
	}

	supplementary_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	supplementary_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_supplementary_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.work.run_visits,
				sample.shape.work.cluster_visits,
				sample.shape.work.glyph_visits,
				sample.shape.work.glyph_index_visits,
				text_work.source_scalar_visits,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	## An explicit U+00AD is source text. A selected visible hyphen is a
	## presentation fact, so ActualText restores that original source scalar
	## rather than making U+002D the extracted replacement.
	soft_hyphen_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	soft_hyphen_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		selection = selected_soft_hyphen({}) ? |_| EvidenceFailure
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		semantic = KernelTextSemantics.Plan.build(
			soft_hyphen_semantics,
			1,
			1,
			KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
			KernelTextSemantics.Limits.make({ max_text_properties: 1, max_text_property_bytes: 1, max_text_source_bytes: 11, max_text_source_scalars: 10, max_text_sources: 1 }),
		) ? |_| EvidenceFailure
		glyphs = [
			required_glyph(font, 0x0063) ? |_| EvidenceFailure,
			required_glyph(font, 0x006f) ? |_| EvidenceFailure,
			required_glyph(font, 0x002d) ? |_| EvidenceFailure,
			required_glyph(font, 0x006f) ? |_| EvidenceFailure,
			required_glyph(font, 0x0070) ? |_| EvidenceFailure,
			required_glyph(font, 0x0065) ? |_| EvidenceFailure,
			required_glyph(font, 0x0072) ? |_| EvidenceFailure,
			required_glyph(font, 0x0061) ? |_| EvidenceFailure,
			required_glyph(font, 0x0074) ? |_| EvidenceFailure,
			required_glyph(font, 0x0065) ? |_| EvidenceFailure,
		]
		store = soft_hyphen_store(Font.InstanceId.from_index(0), glyphs, selection)
		sample = build_sample_from_with_source_limits(font, semantic, soft_hyphen_source, store, 10, 11, 1, 16, 10) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				1,
				1,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	## An external line-break provider supplies this exact zero-width boundary;
	## it supplies neither a dictionary nor a language guess. The selected
	## presentation glyph is typed as an inserted discretionary hyphen, while
	## ActualText keeps the occurrence's unchanged logical `ab` source.
	external_discretionary_hyphen_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	external_discretionary_hyphen_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		selection = selected_external_discretionary_hyphen({}) ? |_| EvidenceFailure
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		semantic = KernelTextSemantics.Plan.build(
			external_discretionary_hyphen_semantics,
			1,
			1,
			KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
			KernelTextSemantics.Limits.make({ max_text_properties: 1, max_text_property_bytes: 1, max_text_source_bytes: 2, max_text_source_scalars: 2, max_text_sources: 1 }),
		) ? |_| EvidenceFailure
		glyphs = [
			required_glyph(font, 0x0061) ? |_| EvidenceFailure,
			required_glyph(font, 0x002d) ? |_| EvidenceFailure,
			required_glyph(font, 0x0062) ? |_| EvidenceFailure,
		]
		store = external_discretionary_hyphen_store(Font.InstanceId.from_index(0), glyphs, selection)
		sample = build_sample_from_with_source_limits(font, semantic, external_discretionary_hyphen_source, store, 2, 2, 1, 3, 3) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				1,
				1,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	soft_hyphen_negative : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	soft_hyphen_negative = |mode, runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		rejected = match mode {
			"malformed" => malformed_soft_hyphen_rejected({}) ? |_| EvidenceFailure
			"unselected" => unselected_soft_hyphen_rejected({}) ? |_| EvidenceFailure
			"external-malformed" => malformed_external_hyphen_rejected({}) ? |_| EvidenceFailure
			"external-unselected" => unselected_external_hyphen_rejected({}) ? |_| EvidenceFailure
			_ => Bool.False
		}
		if !rejected {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [1, bytes.len()] })
	}

	supplementary_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	supplementary_negative = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = KernelFont.inspect(
			supplementary_font_bytes,
			KernelFont.Limits.make({ max_bytes: 500000, max_cmap_mappings: 10000, max_glyphs: 5000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		glyph = required_glyph(font, 0x1f12f) ? |_| EvidenceFailure
		store = supplementary_store(Font.InstanceId.from_index(0), glyph)
		cluster = list_at(store.clusters, 0)
		bad_store = { ..store, clusters: [{ ..cluster, source: { ..supplementary_source_range, utf8_bytes: Semantics.Range.from_start_and_length(0, 3) } }] }
		rejected = match KernelShape.validate_advanced(
			font,
			supplementary_source,
			bad_store,
			{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
			KernelShape.AdvancedLimits.make({ max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_runs: 1, max_scalars: 1, max_source_bytes: 4, max_substitutions: 0, max_transformations: 0 }),
		) {
			Err(AdvancedClusterInvalid({ cluster: 0, reason: SourceRange })) => Bool.True
			_ => Bool.False
		}
		if !rejected {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [1, bytes.len()] })
	}

	## The CJK fixture is a test-only, caller-style static TrueType subset. Its
	## single Han glyph and source fact cross the advanced boundary together.
	cjk_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	cjk_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_cjk_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.work.run_visits,
				sample.shape.work.cluster_visits,
				sample.shape.work.glyph_visits,
				sample.shape.work.glyph_index_visits,
				text_work.source_scalar_visits,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	cjk_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	cjk_negative = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = KernelFont.inspect(
			cjk_font_bytes,
			KernelFont.Limits.make({ max_bytes: 4096, max_cmap_mappings: 16, max_glyphs: 16, max_tables: 32 }),
		) ? |_| EvidenceFailure
		glyph = required_glyph(font, 0x4e2d) ? |_| EvidenceFailure
		store = cjk_store(Font.InstanceId.from_index(0), glyph)
		cluster = list_at(store.clusters, 0)
		bad_store = { ..store, clusters: [{ ..cluster, source: { ..cjk_source_range, utf8_bytes: Semantics.Range.from_start_and_length(0, 2) } }] }
		rejected = match KernelShape.validate_advanced(
			font,
			cjk_source,
			bad_store,
			{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
			KernelShape.AdvancedLimits.make({ max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_runs: 1, max_scalars: 1, max_source_bytes: 3, max_substitutions: 0, max_transformations: 0 }),
		) {
			Err(AdvancedClusterInvalid({ cluster: 0, reason: SourceRange })) => Bool.True
			_ => Bool.False
		}
		if !rejected {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [1, bytes.len()] })
	}

	combining_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	combining_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_combining_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.work.run_visits,
				sample.shape.work.cluster_visits,
				sample.shape.work.glyph_visits,
				sample.shape.work.glyph_index_visits,
				text_work.source_scalar_visits,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mappings,
				KernelContent.Plan.work(sample.content).bytes_emitted,
				KernelGate3TaggedTextStructure.Plan.work(sample.structure).objects,
				bytes.len(),
			],
		})
	}

	combining_negative : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	combining_negative = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_combining_sample({}) ? |_| EvidenceFailure
		cluster = list_at(sample.shape.store.clusters, 0)
		bad_store = { ..sample.shape.store, clusters: [{ ..cluster, source: { ..combining_source_range, utf8_bytes: Semantics.Range.from_start_and_length(0, 2) } }] }
		rejected = match KernelShape.validate_advanced(
			sample.font,
			combining_source,
			bad_store,
			{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
			KernelShape.AdvancedLimits.make({ max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_runs: 1, max_scalars: 2, max_source_bytes: 3, max_substitutions: 0, max_transformations: 0 }),
		) {
			Err(AdvancedClusterInvalid({ cluster: 0, reason: SourceRange })) => Bool.True
			_ => Bool.False
		}
		if !rejected {
			return Err(EvidenceFailure)
		}
		blank = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(blank) ? |_| EvidenceFailure
		Ok({ bytes, work: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, bytes.len()] })
	}

	reordered_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	reordered_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TaggedTextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		content_work = KernelContent.Plan.work(sample.content)
		resource_work = KernelResourceUse.TextPlan.work(sample.resource_use)
		scene_work = KernelScene.Plan.work(sample.scene)
		semantic_work = KernelTextSemantics.Plan.work(sample.semantic)
		semantic_plan_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(sample.semantic))
		tagged_work = KernelTagged.Plan.work(KernelTextOwnership.Plan.tagged(sample.ownership))
		ownership_work = KernelTextOwnership.Plan.work(sample.ownership)
		structure_work = KernelGate3TaggedTextStructure.Plan.work(sample.structure)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.work.run_visits,
				sample.shape.work.cluster_visits,
				sample.shape.work.glyph_visits,
				sample.shape.work.glyph_index_visits,
				scene_work.command_visits,
				scene_work.color_references,
				scene_work.text_placements,
				scene_work.max_graphics_depth,
				semantic_plan_work.attribute_visits,
				semantic_plan_work.content_visits,
				semantic_plan_work.fragment_count_visits,
				semantic_plan_work.fragment_validation_visits,
				semantic_plan_work.max_semantic_depth,
				semantic_plan_work.namespace_visits,
				semantic_plan_work.node_visits,
				semantic_plan_work.occurrence_visits,
				semantic_plan_work.prefix_steps,
				semantic_plan_work.reverse_writes,
				semantic_work.property_bytes,
				semantic_work.property_visits,
				semantic_work.source_bytes,
				semantic_work.source_scalars,
				semantic_work.source_visits,
				tagged_work.artifact_groups,
				tagged_work.fragment_groups,
				tagged_work.k_items,
				tagged_work.node_k_ranges,
				tagged_work.occurrence_owner_edges,
				tagged_work.paint_edges,
				tagged_work.parent_prefix_steps,
				tagged_work.parent_writes,
				ownership_work.command_visits,
				ownership_work.group_visits,
				ownership_work.run_visits,
				ownership_work.fragment_prefix_steps,
				ownership_work.fragment_writes,
				ownership_work.range_checks,
				ownership_work.text_fragments,
				resource_work.command_visits,
				resource_work.color_space_resources,
				resource_work.text_color_references,
				content_work.command_visits,
				content_work.text_placements,
				content_work.bytes_emitted,
				sample.font_plan.entries.len(),
				sample.subset.work.output_bytes,
				text_work.source_scalar_visits,
				text_work.run_visits,
				text_work.placement_visits,
				text_work.glyph_visits,
				text_work.actual_text_runs,
				text_work.actual_text_scalars,
				text_work.mapping_conflicts_resolved,
				text_work.mappings,
				text_work.content_bytes,
				structure_work.fonts,
				structure_work.font_objects,
				structure_work.objects,
				structure_work.font_program_bytes + structure_work.content_bytes,
				bytes.len(),
			],
		})
	}
}

Sample := {
	content : KernelContent.Plan,
	font : KernelFont.Inspection,
	font_plan : KernelFontPlan.Plan,
	ownership : KernelTextOwnership.Plan,
	resource_use : KernelResourceUse.TextPlan,
	shape : KernelShape.Validated,
	scene : KernelScene.Plan,
	semantic : KernelTextSemantics.Plan,
	structure : KernelGate3TaggedTextStructure.Plan,
	subset : KernelFontSubset.Subset,
	text : KernelPdfText.ScenePlan,
}

build_sample : {} -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample = |_| {
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	) ? |_| FontFailure
	font = registered.registry.prepared_face(registered.face) ? |_| FontFailure
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 2, max_text_source_scalars: 2, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	f_glyph = required_glyph(font, 0x66) ? |_| FontFailure
	a_glyph = required_glyph(font, 0x61) ? |_| FontFailure
	store = reordered_store(registered.instance, f_glyph, a_glyph)
	build_sample_from(font, semantic, source, store)
}

build_combining_sample : {} -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_combining_sample = |_| {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| FontFailure
	semantic = KernelTextSemantics.Plan.build(
		combining_semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 3, max_text_source_scalars: 2, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	agrave_glyph = required_glyph(font, 0x00c0) ? |_| FontFailure
	store = combining_store(Font.InstanceId.from_index(0), agrave_glyph)
	build_sample_from(font, semantic, combining_source, store)
}

## IBM Plex Serif is a test-only advanced font fixture. Its subset retains the
## parsed Type-4 `latn` default `liga` relation f(4) + i(5) -> glyph 6; the
## run can cross this boundary only while that exact fact agrees with its
## source cluster, substitution range, and painted glyph.
build_ligature_sample : {} -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_ligature_sample = |_| {
	font = ligature_font({}) ? |_| FontFailure
	semantic = KernelTextSemantics.Plan.build(
		ligature_semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 2, max_text_source_scalars: 2, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	f_glyph = required_glyph(font, 0x0066) ? |_| FontFailure
	i_glyph = required_glyph(font, 0x0069) ? |_| FontFailure
	fact = KernelGsub.validate_ligature(font, { feature: liga_feature, input: [f_glyph, i_glyph], language: Default, output: ligature_output_glyph, script: latin_script_tag }, ligature_gsub_limits({})) ? |_| ShapeFailure
	store = ligature_store(Font.InstanceId.from_index(0), ligature_output_glyph)
	build_ligature_sample_from(font, semantic, store, fact.fact)
}

build_ligature_sample_from : KernelFont.Inspection, KernelTextSemantics.Plan, Text.Store, KernelGsub.Fact -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_ligature_sample_from = |font, semantic, store, fact| {
	shape = KernelShape.validate_advanced_with_ligature_fact(
		font,
		ligature_source,
		store,
		{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
		fact,
		ligature_shape_limits({}),
	) ? |_| ShapeFailure
	build_sample_after_shape(font, semantic, shape)
}

## This fixture is an advanced-boundary caller asset, not a built-in-theme
## resource. Its cmap contains U+1F12F, so the final ToUnicode row must use a
## UTF-16 surrogate pair without the PDF layer inventing any Unicode relation.
build_supplementary_sample : {} -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_supplementary_sample = |_| {
	font = KernelFont.inspect(
		supplementary_font_bytes,
		KernelFont.Limits.make({ max_bytes: 500000, max_cmap_mappings: 10000, max_glyphs: 5000, max_tables: 32 }),
	) ? |_| FontFailure
	semantic = KernelTextSemantics.Plan.build(
		supplementary_semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 4, max_text_source_scalars: 1, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	glyph = required_glyph(font, 0x1f12f) ? |_| FontFailure
	store = supplementary_store(Font.InstanceId.from_index(0), glyph)
	build_sample_from_with_source_limits(font, semantic, supplementary_source, store, 1, 4, 0, 8, 2)
}

build_cjk_sample : {} -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_cjk_sample = |_| {
	font = KernelFont.inspect(
		cjk_font_bytes,
		KernelFont.Limits.make({ max_bytes: 4096, max_cmap_mappings: 16, max_glyphs: 16, max_tables: 32 }),
	) ? |_| FontFailure
	semantic = KernelTextSemantics.Plan.build(
		cjk_semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 3, max_text_source_scalars: 1, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	glyph = required_glyph(font, 0x4e2d) ? |_| FontFailure
	store = cjk_store(Font.InstanceId.from_index(0), glyph)
	build_sample_from_with_source_limits(font, semantic, cjk_source, store, 1, 3, 0, 8, 2)
}

build_sample_from : KernelFont.Inspection, KernelTextSemantics.Plan, Str, Text.Store -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample_from = |font, semantic, source_text, store| {
	build_sample_from_with_source_limits(font, semantic, source_text, store, 2, 3, 0, 8, 2)
}

build_sample_from_with_source_limits : KernelFont.Inspection, KernelTextSemantics.Plan, Str, Text.Store, U64, U64, U64, U64, U64 -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample_from_with_source_limits = |font, semantic, source_text, store, max_scalars, max_source_bytes, max_transformations, max_mappings, max_glyphs| {
	shape = KernelShape.validate_advanced(
		font,
		source_text,
		store,
		{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0) },
		KernelShape.AdvancedLimits.make({
			max_clusters: max_glyphs,
			max_glyph_indices: max_glyphs,
			max_glyphs,
			max_runs: 1,
			max_scalars,
			max_source_bytes,
			max_substitutions: 0,
			max_transformations,
		}),
	) ? |_| ShapeFailure
	scene = KernelScene.Plan.build(
		text_scene,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: shape.store.runs.len() }),
		KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	) ? |_| SceneFailure
	ownership = KernelTextOwnership.Plan.build(semantic, scene, shape.store) ? |_| OwnershipFailure
	font_plan = KernelFontPlan.plan(font, glyph_usages(shape.store.glyphs), KernelFontPlan.Limits.make({ max_retained_glyphs: 16 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	colors = KernelColor.Plan.build(text_colors, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? |_| ColorFailure
	images = KernelImage.Plan.build(
		empty_image_sources,
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ? |_| ImageFailure
	resource_use = KernelResourceUse.TextPlan.build(scene, colors, images) ? |_| ResourceFailure
	text = KernelPdfText.ScenePlan.build(
		ownership,
		[font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: max_scalars, max_content_bytes: 1024, max_mappings, max_placements: 0, max_source_scalars: max_scalars }),
	) ? |_| TextFailure
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	content = KernelContent.Plan.build_with_text(
		tagged,
		KernelPdfText.ScenePlan.content(text),
		KernelContent.Limits.make({ max_content_bytes: 2048, max_content_streams: 1 }),
	) ? |_| ContentFailure
	base_objects = KernelGate2Objects.Plan.build_with_text(
		tagged,
		colors,
		images,
		resource_use,
		content,
		KernelGate2Objects.Limits.make({ max_objects: 32, max_pages: 1 }),
	) ? |_| ObjectFailure
	font_objects = KernelGate3FontObjects.Plan.build(base_objects, 1, 32) ? |_| FontObjectFailure
	structure = KernelGate3TaggedTextStructure.Plan.build(
		tagged,
		colors,
		images,
		content,
		font_objects,
		text,
		[{ descriptor, font, plan: font_plan, subset }],
		KernelGate3TaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 2048, max_unicode_mappings: max_mappings, max_unicode_scalars: max_mappings }),
			object_limits: tagged_object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ content, font, font_plan, ownership, resource_use, scene, semantic, shape, structure, subset, text })
}

## The fact-consuming ligature path reuses the ordinary post-shaping pipeline;
## only its earlier advanced-shaping validation differs. It retains no parsed
## GSUB tables or closures after the validated one-glyph run has been formed.
build_sample_after_shape : KernelFont.Inspection, KernelTextSemantics.Plan, KernelShape.Validated -> Try(Sample, [ColorFailure, ContentFailure, FontFailure, FontObjectFailure, FontPlanFailure, ImageFailure, ObjectFailure, OwnershipFailure, ResourceFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample_after_shape = |font, semantic, shape| {
	scene = KernelScene.Plan.build(
		text_scene,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: shape.store.runs.len() }),
		KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	) ? |_| SceneFailure
	ownership = KernelTextOwnership.Plan.build(semantic, scene, shape.store) ? |_| OwnershipFailure
	font_plan = KernelFontPlan.plan(font, glyph_usages(shape.store.glyphs), KernelFontPlan.Limits.make({ max_retained_glyphs: 16 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	colors = KernelColor.Plan.build(text_colors, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? |_| ColorFailure
	images = KernelImage.Plan.build(empty_image_sources, colors, KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 })) ? |_| ImageFailure
	resource_use = KernelResourceUse.TextPlan.build(scene, colors, images) ? |_| ResourceFailure
	text = KernelPdfText.ScenePlan.build(ownership, [font_plan], KernelPdfText.Limits.make({ max_actual_text_scalars: 2, max_content_bytes: 1024, max_mappings: 8, max_placements: 0, max_source_scalars: 2 })) ? |_| TextFailure
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	content = KernelContent.Plan.build_with_text(tagged, KernelPdfText.ScenePlan.content(text), KernelContent.Limits.make({ max_content_bytes: 2048, max_content_streams: 1 })) ? |_| ContentFailure
	base_objects = KernelGate2Objects.Plan.build_with_text(tagged, colors, images, resource_use, content, KernelGate2Objects.Limits.make({ max_objects: 32, max_pages: 1 })) ? |_| ObjectFailure
	font_objects = KernelGate3FontObjects.Plan.build(base_objects, 1, 32) ? |_| FontObjectFailure
	structure = KernelGate3TaggedTextStructure.Plan.build(
		tagged,
		colors,
		images,
		content,
		font_objects,
		text,
		[{ descriptor, font, plan: font_plan, subset }],
		KernelGate3TaggedTextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 2048, max_unicode_mappings: 8, max_unicode_scalars: 8 }),
			object_limits: tagged_object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ content, font, font_plan, ownership, resource_use, scene, semantic, shape, structure, subset, text })
}

text_scene : Scene.Store
text_scene = {
	commands: [
		Transform({
			children: Semantics.Range.from_start_and_length(1, 1),
			matrix: { a: Layout.Unit.from_raw(1000), b: Layout.Unit.from_raw(0), c: Layout.Unit.from_raw(0), d: Layout.Unit.from_raw(1000), e: Layout.Unit.from_raw(72000), f: Layout.Unit.from_raw(700000) },
		}),
		DrawText({
			paint: {
				fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
				mode: Fill,
				opacity: 65535,
				stroke: NoStroke,
			},
			run: Text.RunId.from_index(0),
		}),
	],
	dash_lengths: [],
	groups: [{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }],
	page_groups: [Scene.GroupId.from_index(0)],
	pages: [
		{
			boxes: { art: a4_box, bleed: a4_box, crop: a4_box, media: a4_box, trim: a4_box },
			id: Semantics.PageId.from_index(0),
			paint_order: Semantics.Range.from_start_and_length(0, 1),
			rotation: Rotate0,
		},
	],
	path_segments: [],
	paths: [],
}

a4_box : Layout.Rect
a4_box = { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, size: { height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) } }

text_colors : Color.Store
text_colors = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

empty_image_sources : Image.SourceStore
empty_image_sources = { resources: [] }

required_glyph : KernelFont.Inspection, U32 -> Try(U32, [FontFailure])
required_glyph = |font, scalar| match KernelFont.glyph_for_scalar(font, scalar) {
	None => Err(FontFailure)
	Some(0) => Err(FontFailure)
	Some(glyph) => Ok(glyph)
}

reordered_store : Font.InstanceId, U32, U32 -> Text.Store
reordered_store = |instance, f_glyph, a_glyph| {
	zero = Layout.Unit.from_raw(0)
	advance = Layout.Unit.from_raw(6000)
	{
		clusters: [
			{
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				kind: Reordered,
				source: text_range(0, 1),
			},
			{
				glyphs: Semantics.Range.from_start_and_length(1, 1),
				kind: Reordered,
				source: text_range(1, 1),
			},
		],
		glyph_indices: [1, 0],
		glyphs: [
			{ advance_x: advance, advance_y: zero, id: Text.GlyphId.from_raw(a_glyph), offset_x: zero, offset_y: zero },
			{ advance_x: advance, advance_y: zero, id: Text.GlyphId.from_raw(f_glyph), offset_x: zero, offset_y: zero },
		],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 2),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 2),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: text_range(0, 2),
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
}

## The advanced boundary carries the original two-scalar decomposed source and
## one positioned precomposed glyph. The CID's ToUnicode row retains both
## source scalars; no serializer-side normalization or glyph-ID inference occurs.
combining_store : Font.InstanceId, U32 -> Text.Store
combining_store = |instance, agrave_glyph| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: [
			{
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				kind: ManyToOne,
				source: combining_source_range,
			},
		],
		glyph_indices: [0],
		glyphs: [
			{ advance_x: Layout.Unit.from_raw(7500), advance_y: zero, id: Text.GlyphId.from_raw(agrave_glyph), offset_x: zero, offset_y: zero },
		],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 1),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: combining_source_range,
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
}

ligature_store : Font.InstanceId, U32 -> Text.Store
ligature_store = |instance, fi_glyph| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: [{ glyphs: Semantics.Range.from_start_and_length(0, 1), kind: Ligature, source: source_range }],
		glyph_indices: [0],
		glyphs: [{ advance_x: Layout.Unit.from_raw(6963), advance_y: zero, id: Text.GlyphId.from_raw(fi_glyph), offset_x: zero, offset_y: zero }],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 1),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: source_range,
				substitutions: Semantics.Range.from_start_and_length(0, 1),
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [{ feature: Text.FeatureTag.from_raw(liga_feature), glyphs: Semantics.Range.from_start_and_length(0, 1), source: source_range }],
		transformations: [],
	}
}

supplementary_store : Font.InstanceId, U32 -> Text.Store
supplementary_store = |instance, glyph| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: [
			{
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				kind: OneToOne,
				source: supplementary_source_range,
			},
		],
		glyph_indices: [0],
		glyphs: [
			{ advance_x: Layout.Unit.from_raw(11000), advance_y: zero, id: Text.GlyphId.from_raw(glyph), offset_x: zero, offset_y: zero },
		],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 1),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: supplementary_source_range,
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
}

cjk_store : Font.InstanceId, U32 -> Text.Store
cjk_store = |instance, glyph| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: [
			{
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				kind: OneToOne,
				source: cjk_source_range,
			},
		],
		glyph_indices: [0],
		glyphs: [
			{ advance_x: Layout.Unit.from_raw(11000), advance_y: zero, id: Text.GlyphId.from_raw(glyph), offset_x: zero, offset_y: zero },
		],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 1),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 1),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("zh-Hans"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Hani"),
				size: Layout.Unit.from_raw(11000),
				source: cjk_source_range,
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
}

soft_hyphen_store : Font.InstanceId, List(U32), KernelDiscretionaryHyphen.Selected -> Text.Store
soft_hyphen_store = |instance, glyph_ids, selection| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: List.map([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], |index| { glyphs: Semantics.Range.from_start_and_length(index, 1), kind: OneToOne, source: soft_hyphen_scalar_range(index) }),
		glyph_indices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
		glyphs: List.map(glyph_ids, |glyph_id| { advance_x: Layout.Unit.from_raw(6000), advance_y: zero, id: Text.GlyphId.from_raw(glyph_id), offset_x: zero, offset_y: zero }),
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 10),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 10),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				script: Font.Script.from_iso15924("Latn"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				size: Layout.Unit.from_raw(11000),
				source: soft_hyphen_full_source_range,
				substitutions: empty_range,
				transformations: Semantics.Range.from_start_and_length(0, 1),
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [{ glyphs: Semantics.Range.from_start_and_length(2, 1), kind: SelectedSoftHyphen, source: selection.source }],
	}
}

external_discretionary_hyphen_store : Font.InstanceId, List(U32), KernelDiscretionaryHyphen.Selected -> Text.Store
external_discretionary_hyphen_store = |instance, glyph_ids, selection| {
	zero = Layout.Unit.from_raw(0)
	{
		clusters: [
			{ glyphs: Semantics.Range.from_start_and_length(0, 1), kind: OneToOne, source: external_discretionary_scalar_range(0) },
			{
				glyphs: Semantics.Range.from_start_and_length(1, 1),
				kind: GeneratedDiscretionaryHyphen({ property: Semantics.TextPropertyId.from_index(0), transformation: 0 }),
				source: selection.source,
			},
			{ glyphs: Semantics.Range.from_start_and_length(2, 1), kind: OneToOne, source: external_discretionary_scalar_range(1) },
		],
		glyph_indices: [0, 1, 2],
		glyphs: List.map(glyph_ids, |glyph_id| { advance_x: Layout.Unit.from_raw(6000), advance_y: zero, id: Text.GlyphId.from_raw(glyph_id), offset_x: zero, offset_y: zero }),
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 3),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 3),
				id: Text.RunId.from_index(0),
				instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: external_discretionary_hyphen_full_source_range,
				substitutions: empty_range,
				transformations: Semantics.Range.from_start_and_length(0, 1),
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [{ glyphs: Semantics.Range.from_start_and_length(1, 1), kind: InsertedDiscretionaryHyphen, source: selection.source }],
	}
}

glyph_usages : List(Text.Glyph) -> List(KernelFontPlan.Usage)
glyph_usages = |glyphs| {
	var $usages = List.with_capacity(glyphs.len())
	var $index = 0
	while $index < glyphs.len() {
		$usages = $usages.append({ glyph: list_at(glyphs, $index).id.raw() })
		$index = $index + 1
	}
	$usages
}

source : Str
source = "fa"

ligature_source : Str
ligature_source = "fi"

combining_source : Str
combining_source = "À"

supplementary_source : Str
supplementary_source = "🄯"

cjk_source : Str
cjk_source = "中"

## U+00AD is intentionally retained in source. Its selected presentation is
## the hyphen glyph supplied by the validated font, never a rewritten source.
soft_hyphen_source : Str
soft_hyphen_source = "co­operate"

external_discretionary_hyphen_source : Str
external_discretionary_hyphen_source = "ab"

text_range : U64, U64 -> Semantics.TextRange
text_range = |start, length| {
	{
		scalars: Semantics.Range.from_start_and_length(start, length),
		utf8_bytes: Semantics.Range.from_start_and_length(start, length),
	}
}

source_range : Semantics.TextRange
source_range = text_range(0, 2)

combining_source_range : Semantics.TextRange
combining_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 2),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
}

supplementary_source_range : Semantics.TextRange
supplementary_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 1),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 4),
}

cjk_source_range : Semantics.TextRange
cjk_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 1),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
}

soft_hyphen_source_range : Semantics.TextRange
soft_hyphen_source_range = {
	scalars: Semantics.Range.from_start_and_length(2, 1),
	utf8_bytes: Semantics.Range.from_start_and_length(2, 2),
}

soft_hyphen_full_source_range : Semantics.TextRange
soft_hyphen_full_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 10),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 11),
}

external_discretionary_hyphen_boundary : Semantics.TextRange
external_discretionary_hyphen_boundary = {
	scalars: Semantics.Range.from_start_and_length(1, 0),
	utf8_bytes: Semantics.Range.from_start_and_length(1, 0),
}

external_discretionary_hyphen_full_source_range : Semantics.TextRange
external_discretionary_hyphen_full_source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 2),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 2),
}

soft_hyphen_scalar_range : U64 -> Semantics.TextRange
soft_hyphen_scalar_range = |index| {
	byte_start = match index {
		0 => 0
		1 => 1
		2 => 2
		3 => 4
		4 => 5
		5 => 6
		6 => 7
		7 => 8
		8 => 9
		9 => 10
		_ => crash "validated soft-hyphen scalar index escaped"
	}
	byte_length = if index == 2 2 else 1
	{ scalars: Semantics.Range.from_start_and_length(index, 1), utf8_bytes: Semantics.Range.from_start_and_length(byte_start, byte_length) }
}

external_discretionary_scalar_range : U64 -> Semantics.TextRange
external_discretionary_scalar_range = |index| {
	if index >= 2 {
		crash "validated external discretionary scalar index escaped"
	}
	{ scalars: Semantics.Range.from_start_and_length(index, 1), utf8_bytes: Semantics.Range.from_start_and_length(index, 1) }
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

semantics : Semantics.Store
semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [],
	fragments: [
		{
			content_stream: Semantics.ContentStreamId.from_index(0),
			continuation_index: 0,
			id: Semantics.FragmentId.from_index(0),
			occurrence: Semantics.OccurrenceId.from_index(0),
			page: Semantics.PageId.from_index(0),
			source_range: UnicodeRange(source_range),
		},
	],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [
		{
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(0, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(0),
			language: Language("en-AU"),
			parent: DocumentRoot,
			role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(0),
			text_properties: empty_range,
		},
		{
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(1, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(1),
			language: Language("en-AU"),
			parent: ParentNode(Semantics.NodeId.from_index(0)),
			role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(1),
			text_properties: empty_range,
		},
	],
	non_text_sources: [],
	occurrence_fragments: [Semantics.FragmentId.from_index(0)],
	occurrences: [
		{
			fragments: Semantics.Range.from_start_and_length(0, 1),
			id: Semantics.OccurrenceId.from_index(0),
			language: Language("en-AU"),
			source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(source_range)),
			text_properties: empty_range,
		},
	],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [{ unicode: source }],
}

combining_semantics : Semantics.Store
combining_semantics = {
	..semantics,
	fragments: [{ ..list_at(semantics.fragments, 0), source_range: UnicodeRange(combining_source_range) }],
	occurrences: [{ ..list_at(semantics.occurrences, 0), source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(combining_source_range)) }],
	text_sources: [{ unicode: combining_source }],
}

ligature_semantics : Semantics.Store
ligature_semantics = { ..semantics, text_sources: [{ unicode: ligature_source }] }

supplementary_semantics : Semantics.Store
supplementary_semantics = {
	..semantics,
	fragments: [{ ..list_at(semantics.fragments, 0), source_range: UnicodeRange(supplementary_source_range) }],
	occurrences: [{ ..list_at(semantics.occurrences, 0), source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(supplementary_source_range)) }],
	text_sources: [{ unicode: supplementary_source }],
}

cjk_semantics : Semantics.Store
cjk_semantics = {
	..semantics,
	fragments: [{ ..list_at(semantics.fragments, 0), source_range: UnicodeRange(cjk_source_range) }],
	occurrences: [{ ..list_at(semantics.occurrences, 0), language: Language("zh-Hans"), source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(cjk_source_range)) }],
	text_sources: [{ unicode: cjk_source }],
}

soft_hyphen_semantics : Semantics.Store
soft_hyphen_semantics = {
	..semantics,
	fragments: [{ ..list_at(semantics.fragments, 0), source_range: UnicodeRange(soft_hyphen_full_source_range) }],
	occurrences: [{ ..list_at(semantics.occurrences, 0), source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(soft_hyphen_full_source_range)), text_properties: Semantics.Range.from_start_and_length(0, 1) }],
	text_properties: [SourceToPresentation({ kind: SelectedSoftHyphen, presentation: "-", source: soft_hyphen_source_range })],
	text_sources: [{ unicode: soft_hyphen_source }],
}

external_discretionary_hyphen_semantics : Semantics.Store
external_discretionary_hyphen_semantics = {
	..semantics,
	fragments: [{ ..list_at(semantics.fragments, 0), source_range: UnicodeRange(external_discretionary_hyphen_full_source_range) }],
	occurrences: [{ ..list_at(semantics.occurrences, 0), source: Text(Semantics.TextSourceId.from_index(0), UnicodeRange(external_discretionary_hyphen_full_source_range)), text_properties: Semantics.Range.from_start_and_length(0, 1) }],
	text_properties: [SourceToPresentation({ kind: InsertedDiscretionaryHyphen, presentation: "-", source: external_discretionary_hyphen_boundary })],
	text_sources: [{ unicode: external_discretionary_hyphen_source }],
}

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

liga_feature : U32
liga_feature = 0x6c696761

latin_script_tag : U32
latin_script_tag = 0x6c61746e

## This is the generated fixture's original-glyph identifier. It is not a
## caller choice: `KernelGsub.validate_ligature` proves it from the selected
## fixture table before the advanced run is accepted.
ligature_output_glyph : U32
ligature_output_glyph = 6

ligature_font : {} -> Try(KernelFont.Inspection, [FontFailure])
ligature_font = |_| {
	font = KernelFont.inspect(
		ligature_font_bytes,
		KernelFont.Limits.make({ max_bytes: 4096, max_cmap_mappings: 16, max_glyphs: 16, max_tables: 32 }),
	) ? |_| FontFailure
	Ok(font)
}

ligature_gsub_limits : {} -> KernelGsub.Limits
ligature_gsub_limits = |_| KernelGsub.Limits.make({ max_feature_lookups: 2, max_ligature_components: 2, max_ligatures: 4, max_subtables: 2 })

ligature_shape_limits : {} -> KernelShape.AdvancedLimits
ligature_shape_limits = |_| KernelShape.AdvancedLimits.make({ max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_runs: 1, max_scalars: 2, max_source_bytes: 2, max_substitutions: 1, max_transformations: 0 })

tagged_object_limits : KernelObject.Limits
tagged_object_limits = {
	max_array_items: 64,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 128,
	max_direct_depth: 8,
	max_name_bytes: 3072,
	max_names: 96,
	max_objects: 32,
	max_payload_bytes: 200000,
	max_payloads: 4,
	max_streams: 4,
	max_text_string_bytes: 64,
	max_text_strings: 4,
	max_values: 256,
}

selected_soft_hyphen : {} -> Try(KernelDiscretionaryHyphen.Selected, [EvidenceFailure])
selected_soft_hyphen = |_| {
	analysis = KernelUnicode.analyze(soft_hyphen_source, { max_graphemes: 10, max_line_boundaries: 11, max_scalars: 10, max_script_runs: 3 }) ? |_| EvidenceFailure
	plan = KernelDiscretionaryHyphen.Plan.build(
		soft_hyphen_source,
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExplicitSoftHyphen, source: soft_hyphen_source_range }],
		[SelectVisibleHyphen],
	) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.selected(plan, KernelDiscretionaryHyphen.OpportunityId.from_index(0)) {
		Ok(selected) => Ok(selected)
		Err(_) => Err(EvidenceFailure)
	}
}

selected_external_discretionary_hyphen : {} -> Try(KernelDiscretionaryHyphen.Selected, [EvidenceFailure])
selected_external_discretionary_hyphen = |_| {
	analysis = KernelUnicode.analyze(external_discretionary_hyphen_source, { max_graphemes: 2, max_line_boundaries: 3, max_scalars: 2, max_script_runs: 1 }) ? |_| EvidenceFailure
	plan = KernelDiscretionaryHyphen.Plan.build(
		external_discretionary_hyphen_source,
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExternalHyphenation, source: external_discretionary_hyphen_boundary }],
		[SelectVisibleHyphen],
	) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.selected(plan, KernelDiscretionaryHyphen.OpportunityId.from_index(0)) {
		Ok({ kind: ExternalHyphenation, source: selected_source }) => if selected_source.scalars.length() == 0 and selected_source.utf8_bytes.length() == 0 Ok({ kind: ExternalHyphenation, source: selected_source }) else Err(EvidenceFailure)
		_ => Err(EvidenceFailure)
	}
}

malformed_soft_hyphen_rejected : {} -> Try(Bool, [EvidenceFailure])
malformed_soft_hyphen_rejected = |_| {
	analysis = KernelUnicode.analyze("-", { max_graphemes: 1, max_line_boundaries: 2, max_scalars: 1, max_script_runs: 1 }) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.build(
		"-",
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExplicitSoftHyphen, source: { scalars: Semantics.Range.from_start_and_length(0, 1), utf8_bytes: Semantics.Range.from_start_and_length(0, 1) } }],
		[SelectVisibleHyphen],
	) {
		Err(InvalidExplicitSoftHyphen({ opportunity: 0 })) => Ok(Bool.True)
		_ => Ok(Bool.False)
	}
}

unselected_soft_hyphen_rejected : {} -> Try(Bool, [EvidenceFailure])
unselected_soft_hyphen_rejected = |_| {
	analysis = KernelUnicode.analyze(soft_hyphen_source, { max_graphemes: 10, max_line_boundaries: 11, max_scalars: 10, max_script_runs: 3 }) ? |_| EvidenceFailure
	plan = KernelDiscretionaryHyphen.Plan.build(
		soft_hyphen_source,
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExplicitSoftHyphen, source: soft_hyphen_source_range }],
		[NotSelected],
	) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.selected(plan, KernelDiscretionaryHyphen.OpportunityId.from_index(0)) {
		Err(UnselectedOpportunity({ opportunity: 0 })) => Ok(Bool.True)
		_ => Ok(Bool.False)
	}
}

malformed_external_hyphen_rejected : {} -> Try(Bool, [EvidenceFailure])
malformed_external_hyphen_rejected = |_| {
	analysis = KernelUnicode.analyze(external_discretionary_hyphen_source, { max_graphemes: 2, max_line_boundaries: 3, max_scalars: 2, max_script_runs: 1 }) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.build(
		external_discretionary_hyphen_source,
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExternalHyphenation, source: { scalars: Semantics.Range.from_start_and_length(1, 1), utf8_bytes: Semantics.Range.from_start_and_length(1, 1) } }],
		[SelectVisibleHyphen],
	) {
		Err(InvalidSourceRange({ opportunity: 0 })) => Ok(Bool.True)
		_ => Ok(Bool.False)
	}
}

unselected_external_hyphen_rejected : {} -> Try(Bool, [EvidenceFailure])
unselected_external_hyphen_rejected = |_| {
	analysis = KernelUnicode.analyze(external_discretionary_hyphen_source, { max_graphemes: 2, max_line_boundaries: 3, max_scalars: 2, max_script_runs: 1 }) ? |_| EvidenceFailure
	plan = KernelDiscretionaryHyphen.Plan.build(
		external_discretionary_hyphen_source,
		analysis,
		[{ id: KernelDiscretionaryHyphen.OpportunityId.from_index(0), kind: ExternalHyphenation, source: external_discretionary_hyphen_boundary }],
		[NotSelected],
	) ? |_| EvidenceFailure
	match KernelDiscretionaryHyphen.Plan.selected(plan, KernelDiscretionaryHyphen.OpportunityId.from_index(0)) {
		Err(UnselectedOpportunity({ opportunity: 0 })) => Ok(Bool.True)
		_ => Ok(Bool.False)
	}
}

expect {
	sample = build_sample({})?
	work = KernelPdfText.ScenePlan.work(sample.text)
	structure = KernelGate3TaggedTextStructure.Plan.structure(sample.structure)
	font_objects = KernelGate3TaggedTextStructure.Plan.font_objects(sample.structure)
	first = list_at(font_objects, 0)
	work.actual_text_runs == 1 and
		work.actual_text_scalars == 2 and
			work.mappings == 2 and
				KernelStructure.Plan.object_count(structure) == 20 and
					KernelObject.ObjectId.number(first.font_file) == 12 and
						KernelObject.ObjectId.number(first.type0) == 20
}

## A many-to-many advanced cluster is accepted only with occurrence-derived
## ActualText; every painted CID still receives a deterministic ToUnicode map.
expect {
	sample = build_sample({})?
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	)?
	font = registered.registry.prepared_face(registered.face)?
	base_run = list_at(sample.shape.store.runs, 0)
	multi_store = {
		..sample.shape.store,
		clusters: [
			{
				glyphs: Semantics.Range.from_start_and_length(0, 2),
				kind: ManyToMany,
				source: source_range,
			},
		],
		glyph_indices: [0, 1],
		runs: [{ ..base_run, clusters: Semantics.Range.from_start_and_length(0, 1) }],
	}
	validated = KernelShape.validate_advanced(
		font,
		source,
		multi_store,
		{ instance: registered.instance, occurrence: Semantics.OccurrenceId.from_index(0) },
		KernelShape.AdvancedLimits.make({
			max_clusters: 1,
			max_glyph_indices: 2,
			max_glyphs: 2,
			max_runs: 1,
			max_scalars: 2,
			max_source_bytes: 2,
			max_substitutions: 0,
			max_transformations: 0,
		}),
	)?
	plan = KernelPdfText.Plan.build(
		semantics,
		validated.store,
		[sample.font_plan],
		[{ origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, run: Text.RunId.from_index(0) }],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 2, max_content_bytes: 512, max_mappings: 2, max_placements: 1, max_source_scalars: 2 }),
	)?
	work = KernelPdfText.Plan.work(plan)
	work.actual_text_runs == 1 and work.actual_text_scalars == 2 and work.mappings == 2
}

## An explicit semantic override is resolved only through the occurrence's
## owned text-property range, and its scalar budget fails atomically.
expect {
	sample = build_sample({})?
	occurrence = list_at(semantics.occurrences, 0)
	override_semantics = {
		..semantics,
		occurrences: [{ ..occurrence, text_properties: Semantics.Range.from_start_and_length(0, 1) }],
		text_properties: [ActualText("logical")],
	}
	run = list_at(sample.shape.store.runs, 0)
	override_store = {
		..sample.shape.store,
		runs: [{ ..run, actual_text: SemanticOverride(Semantics.TextPropertyId.from_index(0)) }],
	}
	placement = { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, run: Text.RunId.from_index(0) }
	accepted = KernelPdfText.Plan.build(
		override_semantics,
		override_store,
		[sample.font_plan],
		[placement],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 7, max_content_bytes: 512, max_mappings: 2, max_placements: 1, max_source_scalars: 2 }),
	)?
	accepted_work = KernelPdfText.Plan.work(accepted)
	bounded = match KernelPdfText.Plan.build(
		override_semantics,
		override_store,
		[sample.font_plan],
		[placement],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 6, max_content_bytes: 512, max_mappings: 2, max_placements: 1, max_source_scalars: 2 }),
	) {
		Err(LimitExceeded({ attempted: 7, dimension: ActualTextScalars, limit: 6 })) => Bool.True
		_ => Bool.False
	}
	accepted_work.actual_text_runs == 1 and accepted_work.actual_text_scalars == 7 and bounded
}

## A font-level CID cannot carry two occurrence mappings. The plain twin is
## rejected; the reordered twin has exact ActualText, retains the first CMap
## fallback deterministically, and reports the resolved conflict.
expect {
	registered = Font.Registry.empty.register(
		caller_font_bytes,
		{ provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn")] },
		Font.ValidationLimits.default,
	)?
	font = registered.registry.prepared_face(registered.face)?
	f_glyph = required_glyph(font, 0x66)?
	zero = Layout.Unit.from_raw(0)
	advance = Layout.Unit.from_raw(6000)
	base_store = {
		clusters: [
			{ glyphs: Semantics.Range.from_start_and_length(0, 1), kind: OneToOne, source: text_range(0, 1) },
			{ glyphs: Semantics.Range.from_start_and_length(1, 1), kind: OneToOne, source: text_range(1, 1) },
		],
		glyph_indices: [0, 1],
		glyphs: [
			{ advance_x: advance, advance_y: zero, id: Text.GlyphId.from_raw(f_glyph), offset_x: zero, offset_y: zero },
			{ advance_x: advance, advance_y: zero, id: Text.GlyphId.from_raw(f_glyph), offset_x: zero, offset_y: zero },
		],
		runs: [
			{
				actual_text: FromOccurrence,
				clusters: Semantics.Range.from_start_and_length(0, 2),
				direction: LeftToRight,
				glyphs: Semantics.Range.from_start_and_length(0, 2),
				id: Text.RunId.from_index(0),
				instance: registered.instance,
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				source: source_range,
				substitutions: empty_range,
				transformations: empty_range,
				writing_mode: Horizontal,
			},
		],
		substitutions: [],
		transformations: [],
	}
	context = { instance: registered.instance, occurrence: Semantics.OccurrenceId.from_index(0) }
	shape_limits = KernelShape.AdvancedLimits.make({
		max_clusters: 2,
		max_glyph_indices: 2,
		max_glyphs: 2,
		max_runs: 1,
		max_scalars: 2,
		max_source_bytes: 2,
		max_substitutions: 0,
		max_transformations: 0,
	})
	plain = KernelShape.validate_advanced(font, source, base_store, context, shape_limits)?
	font_plan = KernelFontPlan.plan(font, glyph_usages(plain.store.glyphs), KernelFontPlan.Limits.make({ max_retained_glyphs: 8 }))?
	placement = { origin: { x: zero, y: zero }, run: Text.RunId.from_index(0) }
	limits = KernelPdfText.Limits.make({ max_actual_text_scalars: 2, max_content_bytes: 512, max_mappings: 2, max_placements: 1, max_source_scalars: 2 })
	plain_rejected = match KernelPdfText.Plan.build(semantics, plain.store, [font_plan], [placement], limits) {
		Err(UnicodeMappingConflict({ cid: _, font: 0 })) => Bool.True
		_ => Bool.False
	}
	reordered_clusters = List.map(base_store.clusters, |cluster| { ..cluster, kind: Reordered })
	conflict_store = { ..base_store, clusters: reordered_clusters }
	reordered = KernelShape.validate_advanced(font, source, conflict_store, context, shape_limits)?
	accepted = KernelPdfText.Plan.build(semantics, reordered.store, [font_plan], [placement], limits)?
	work = KernelPdfText.Plan.work(accepted)
	plain_rejected and work.mapping_conflicts_resolved == 1 and work.mappings == 1
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 ActualText evidence index escaped"
	}
	Ok(value) => value
}
