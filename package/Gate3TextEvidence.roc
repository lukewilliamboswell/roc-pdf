import Color
import Font
import KernelEmit
import KernelContent
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelGate3TextStructure
import KernelObject
import KernelPdfFont
import KernelPdfText
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
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3TextEvidence :: [].{
	visible_text : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	visible_text = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		sample = build_sample({}) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(KernelGate3TextStructure.Plan.structure(sample.structure)) ? |_| EvidenceFailure
		text_work = KernelPdfText.Plan.work(sample.text)
		scene_work = KernelScene.Plan.work(sample.scene)
		semantic_work = KernelTextSemantics.Plan.work(sample.semantic)
		semantic_plan_work = KernelSemantics.Plan.work(KernelTextSemantics.Plan.semantics(sample.semantic))
		tagged_work = KernelTagged.Plan.work(KernelTextOwnership.Plan.tagged(sample.ownership))
		ownership_work = KernelTextOwnership.Plan.work(sample.ownership)
		structure_work = KernelGate3TextStructure.Plan.work(sample.structure)
		Ok({
			bytes,
			work: [
				sample.font.bytes.len(),
				sample.shape.store.runs.len(),
				sample.shape.store.glyphs.len(),
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
				sample.font_plan.entries.len(),
				sample.subset.work.output_bytes,
				text_work.source_scalar_visits,
				text_work.run_visits,
				text_work.placement_visits,
				text_work.glyph_visits,
				text_work.mappings,
				text_work.content_bytes,
				structure_work.fonts,
				structure_work.font_objects,
				structure_work.objects,
				structure_work.payload_bytes,
				bytes.len(),
			],
		})
	}
}

Sample := {
	font : KernelFont.Inspection,
	font_plan : KernelFontPlan.Plan,
	ownership : KernelTextOwnership.Plan,
	shape : KernelShape.Shape,
	scene : KernelScene.Plan,
	semantic : KernelTextSemantics.Plan,
	structure : KernelGate3TextStructure.Plan,
	subset : KernelFontSubset.Subset,
	text : KernelPdfText.Plan,
}

build_sample : {} -> Try(Sample, [AnalysisFailure, FontFailure, FontPlanFailure, OwnershipFailure, SceneFailure, SemanticFailure, ShapeFailure, StructureFailure, SubsetFailure, TextFailure])
build_sample = |_| {
	analysis = KernelUnicode.analyze(
		source,
		{ max_graphemes: 32, max_line_boundaries: 33, max_scalars: 32, max_script_runs: 8 },
	) ? |_| AnalysisFailure
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 9, max_text_source_scalars: 8, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	) ? |_| FontFailure
	shape = KernelShape.shape_simple(
		font,
		source,
		analysis,
		{
			direction: LeftToRight,
			instance: Font.InstanceId.from_index(0),
			language: Language("en-AU"),
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(11000),
			writing_mode: Horizontal,
		},
		KernelShape.Limits.make({ max_clusters: 32, max_glyphs: 32, max_scalars: 32, max_source_bytes: 128 }),
	) ? |_| ShapeFailure
	scene = KernelScene.Plan.build(
		text_scene,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: shape.store.runs.len() }),
		KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	) ? |_| SceneFailure
	ownership = KernelTextOwnership.Plan.build(semantic, scene, shape.store) ? |_| OwnershipFailure
	usages = glyph_usages(shape.store.glyphs)
	font_plan = KernelFontPlan.plan(font, usages, KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	text = KernelPdfText.Plan.build(
		semantics,
		shape.store,
		[font_plan],
		[{ origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) }, run: Text.RunId.from_index(0) }],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 8, max_source_scalars: 64 }),
	) ? |_| TextFailure
	structure = KernelGate3TextStructure.Plan.build(
		text,
		[{ descriptor, font, plan: font_plan, subset }],
		{ height: Layout.Unit.from_raw(842000), width: Layout.Unit.from_raw(595000) },
		KernelGate3TextStructure.Limits.make({
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 64, max_unicode_scalars: 128 }),
			object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ font, font_plan, ownership, scene, semantic, shape, structure, subset, text })
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
				fill: { channels: Rgb({ blue: 0, green: 0, red: 0 }), space: Color.SpaceId.from_index(0) },
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
source = "Café PDF"

source_range : Semantics.TextRange
source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 8),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 9),
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

descriptor : KernelPdfFont.Descriptor
descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 64,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 128,
	max_direct_depth: 8,
	max_name_bytes: 2048,
	max_names: 64,
	max_objects: 14,
	max_payload_bytes: 200000,
	max_payloads: 4,
	max_streams: 4,
	max_text_string_bytes: 32,
	max_text_strings: 2,
	max_values: 256,
}

expect {
	sample = build_sample({})?
	structure = KernelGate3TextStructure.Plan.structure(sample.structure)
	font_objects = KernelGate3TextStructure.Plan.font_objects(sample.structure)
	first = list_at(font_objects, 0)
	KernelStructure.Plan.object_count(structure) == 14 and
		KernelObject.ObjectId.number(first.font_file) == 6 and
			KernelObject.ObjectId.number(first.type0) == 14 and
				KernelPdfText.Plan.mappings(sample.text).len() == 1 and
					list_at(KernelPdfText.Plan.mappings(sample.text), 0).len() == 8
}

## Placement and ActualText failures are atomic rather than guessed or omitted.
expect {
	sample = build_sample({})?
	placement = { origin: { x: Layout.Unit.from_raw(72000), y: Layout.Unit.from_raw(700000) }, run: Text.RunId.from_index(0) }
	limits = KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 8, max_source_scalars: 64 })
	missing_rejected = match KernelPdfText.Plan.build(semantics, sample.shape.store, [sample.font_plan], [], limits) {
		Err(RunInvalid({ run: 0 })) => Bool.True
		_ => Bool.False
	}
	duplicate_rejected = match KernelPdfText.Plan.build(semantics, sample.shape.store, [sample.font_plan], [placement, placement], limits) {
		Err(PlacementInvalid({ placement: 1 })) => Bool.True
		_ => Bool.False
	}
	run = list_at(sample.shape.store.runs, 0)
	override_store = { ..sample.shape.store, runs: [{ ..run, actual_text: SemanticOverride(Semantics.TextPropertyId.from_index(0)) }] }
	override_rejected = match KernelPdfText.Plan.build(semantics, override_store, [sample.font_plan], [placement], limits) {
		Err(ActualTextRequired({ run: 0 })) => Bool.True
		_ => Bool.False
	}
	missing_rejected and duplicate_rejected and override_rejected
}

## Scene text lowering prepares every owned run once in local coordinates.
expect {
	sample = build_sample({})?
	plan = KernelPdfText.ScenePlan.build(
		sample.ownership,
		[sample.font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	)?
	work = KernelPdfText.ScenePlan.work(plan)
	run = KernelPdfText.ScenePlan.run(plan, Text.RunId.from_index(0))
	KernelPdfText.ScenePlan.run_count(plan) == 1 and
		run.body.len() > 0 and
			run.actual_text_begin.len() == 0 and
				!run.close_actual_text and
					KernelPdfText.ScenePlan.mappings(plan) == KernelPdfText.Plan.mappings(sample.text) and
						work.run_visits == 1 and
							work.placement_visits == 0 and
								work.glyph_visits == 8
}

## The scene plan applies its content-byte bound cumulatively across runs.
expect {
	sample = build_sample({})?
	accepted = KernelPdfText.ScenePlan.build(
		sample.ownership,
		[sample.font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	)?
	required = KernelPdfText.ScenePlan.work(accepted).content_bytes
	match KernelPdfText.ScenePlan.build(
		sample.ownership,
		[sample.font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: required - 1, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	) {
		Err(LimitExceeded({ attempted: _, dimension: ContentBytes, limit: _ })) => True
		_ => False
	}
}

## Tagged content lowering consumes scene placement, typed paint, and prepared glyph operators.
expect {
	sample = build_sample({})?
	text = KernelPdfText.ScenePlan.build(
		sample.ownership,
		[sample.font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	)?
	content = KernelContent.Plan.build_with_text(
		KernelTextOwnership.Plan.tagged(sample.ownership),
		KernelPdfText.ScenePlan.content(text),
		KernelContent.Limits.make({ max_content_bytes: 4096, max_content_streams: 1 }),
	)?
	stream = KernelContent.Plan.stream(content, Semantics.ContentStreamId.from_index(0))
	work = KernelContent.Plan.work(content)
	prefix = Str.to_utf8("/P <</MCID 0>> BDC\nq\n1 0 0 1 72 700 cm\n/CS1_0 cs\n0 0 0 scn\nBT\n0 Tr\n/F1_0 11 Tf\n")
	starts_with(stream.bytes, prefix) and
		work.command_visits == 2 and
			work.graphics_state_pairs == 1 and
				work.marked_fragment_groups == 1 and
					work.text_placements == 1
}

## Every shaped run must have exactly one fragment-owned scene placement.
expect {
	sample = build_sample({})?
	run = list_at(sample.shape.store.runs, 0)
	orphaned_text = { ..sample.shape.store, runs: [run, { ..run, id: Text.RunId.from_index(1) }] }
	match KernelTextOwnership.Plan.build(sample.semantic, sample.scene, orphaned_text) {
		Err(OrphanRun({ run: 1 })) => True
		_ => False
	}
}

## Run occurrence identity and fragment source coverage are explicit join facts.
expect {
	sample = build_sample({})?
	run = list_at(sample.shape.store.runs, 0)
	wrong_occurrence = { ..sample.shape.store, runs: [{ ..run, occurrence: Semantics.OccurrenceId.from_index(1) }] }
	short_source = {
		..sample.shape.store,
		runs: [{ ..run, source: { scalars: Semantics.Range.from_start_and_length(0, 7), utf8_bytes: Semantics.Range.from_start_and_length(0, 8) } }],
	}
	occurrence_rejected = match KernelTextOwnership.Plan.build(sample.semantic, sample.scene, wrong_occurrence) {
		Err(OccurrenceMismatch({ fragment: 0, run: 0 })) => True
		_ => False
	}
	coverage_rejected = match KernelTextOwnership.Plan.build(sample.semantic, sample.scene, short_source) {
		Err(FragmentTextCoverageMismatch({ fragment: 0 })) => True
		_ => False
	}
	occurrence_rejected and coverage_rejected
}

## Duplicate run placement and artifact-owned text are rejected before lowering.
expect {
	sample = build_sample({})?
	draw = list_at(text_scene.commands, 1)
	transform = list_at(text_scene.commands, 0)
	duplicate_transform = match transform {
		Transform({ matrix, children: _ }) => Transform({ children: Semantics.Range.from_start_and_length(1, 2), matrix })
		_ => transform
	}
	duplicate_store = { ..text_scene, commands: [duplicate_transform, draw, draw] }
	duplicate_scene = KernelScene.Plan.build(
		duplicate_store,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: 1 }),
		KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 1, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	)?
	page = list_at(text_scene.pages, 0)
	artifact_store = {
		..text_scene,
		commands: [draw, draw],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: PageArtifact(Header) },
			{ commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.GroupId.from_index(1), owner: Fragment(Semantics.FragmentId.from_index(0)) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
		pages: [{ ..page, paint_order: Semantics.Range.from_start_and_length(0, 2) }],
	}
	artifact_scene = KernelScene.Plan.build(
		artifact_store,
		KernelScene.Resources.with_text({ color_spaces: 1, images: 0, text_runs: 1 }),
		KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 1, max_groups: 2, max_pages: 1, max_path_segments: 0, max_paths: 0 }),
	)?
	duplicate_rejected = match KernelTextOwnership.Plan.build(sample.semantic, duplicate_scene, sample.shape.store) {
		Err(DuplicateRunOwnership({ run: 0 })) => True
		_ => False
	}
	artifact_rejected = match KernelTextOwnership.Plan.build(sample.semantic, artifact_scene, sample.shape.store) {
		Err(ArtifactTextUnsupported({ group: 0, run: 0 })) => True
		_ => False
	}
	duplicate_rejected and artifact_rejected
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 text evidence index escaped"
	}
	Ok(value) => value
}

starts_with : List(U8), List(U8) -> Bool
starts_with = |bytes, prefix| {
	if prefix.len() > bytes.len() {
		False
	} else {
		var $index = 0
		var $same = True
		while $index < prefix.len() and $same {
			$same = list_at(bytes, $index) == list_at(prefix, $index)
			$index = $index + 1
		}
		$same
	}
}
