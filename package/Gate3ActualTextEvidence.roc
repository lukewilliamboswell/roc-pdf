import Color
import Font
import KernelEmit
import KernelContent
import KernelColor
import KernelFont
import KernelFontPlan
import KernelFontSubset
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
import Layout
import Semantics
import Scene
import Text
import Image
import "../tests/assets/CallerFont-Regular.ttf" as caller_font_bytes : List(U8)

Gate3ActualTextEvidence :: [].{
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
				sample.registration.input_bytes,
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
	font_plan : KernelFontPlan.Plan,
	ownership : KernelTextOwnership.Plan,
	registration : Font.RegistrationWork,
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
	shape = KernelShape.validate_advanced(
		font,
		source,
		store,
		{ instance: registered.instance, occurrence: Semantics.OccurrenceId.from_index(0) },
		KernelShape.AdvancedLimits.make({
			max_clusters: 2,
			max_glyph_indices: 2,
			max_glyphs: 2,
			max_runs: 1,
			max_scalars: 2,
			max_source_bytes: 2,
			max_substitutions: 0,
			max_transformations: 0,
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
		KernelPdfText.Limits.make({ max_actual_text_scalars: 2, max_content_bytes: 1024, max_mappings: 8, max_placements: 0, max_source_scalars: 2 }),
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
			font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 2048, max_unicode_mappings: 8, max_unicode_scalars: 8 }),
			object_limits: tagged_object_limits,
		}),
	) ? |_| StructureFailure
	Ok({ content, font_plan, ownership, registration: registered.work, resource_use, scene, semantic, shape, structure, subset, text })
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

text_range : U64, U64 -> Semantics.TextRange
text_range = |start, length| {
	{
		scalars: Semantics.Range.from_start_and_length(start, length),
		utf8_bytes: Semantics.Range.from_start_and_length(start, length),
	}
}

source_range : Semantics.TextRange
source_range = text_range(0, 2)

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
