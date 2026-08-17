import Color
import Font
import Image
import KernelColor
import KernelContent
import KernelEmit
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelForm
import KernelGate2Objects
import KernelGate4FormObjects
import KernelGate4FormStructure
import KernelImage
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelResourceGraph
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelShape
import KernelTagged
import KernelTextOwnership
import KernelTextSemantics
import KernelUnicode
import Layout
import Scene
import Semantics
import Text
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

## Gate 4 text-inside-a-form evidence.
##
## One meaningful paragraph's shaped run is painted inside a Form XObject that
## is placed once by the paragraph's fragment-owned group. The run resolves to
## that fragment through the form ownership sweep, the placement-site MCID
## wraps the `Do` invocation in the page stream, and the form's own direct
## dictionary carries the Type 0 font. Every existing Unicode, CID,
## `ToUnicode`, and `ActualText` behavior is produced by the unchanged Gate 3
## text lowering.
##
## The same scenario also proves the two text-specific rejections before any
## byte exists: a text-bearing form placed twice, and a text-bearing form
## reachable only under an artifact owner.
Gate4FormTextEvidence :: [].{
	EvidenceError : [EvidenceFailure, InvalidRuntimeGuard, MissingRejection(U64)]

	text_form : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	text_form = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		prelude = build_prelude({}) ? |_| EvidenceFailure
		rejections = check_text_negatives(prelude)?
		sample = build_sample(prelude, single_placement_scene({})) ? |_| EvidenceFailure
		text_work = KernelPdfText.ScenePlan.work(sample.text)
		content_work = KernelContent.Plan.work(sample.content)
		plan_work = KernelForm.Plan.work(sample.form_plan)
		facts_work = KernelForm.Facts.work(sample.facts)
		ownership_work = KernelTextOwnership.Plan.work(sample.ownership)
		structure_work = KernelGate4FormStructure.Plan.work(sample.structure)
		Ok({
			bytes: sample.bytes,
			work: [
				plan_work.authored_forms,
				plan_work.canonical_forms,
				plan_work.semantic_placements,
				plan_work.artifact_placements,
				facts_work.text_forms,
				facts_work.page_form_placements,
				plan_work.dictionary_entries,
				plan_work.nested_dictionary_entries,
				plan_work.recipe_bytes,
				ownership_work.run_visits,
				ownership_work.text_fragments,
				text_work.glyph_visits,
				text_work.mappings,
				text_work.content_bytes,
				content_work.form_placements,
				content_work.form_stream_bytes,
				content_work.text_placements,
				structure_work.font_program_bytes,
				structure_work.objects,
				rejections,
				sample.bytes.len(),
			],
		})
	}
}

Sample := {
	bytes : List(U8),
	content : KernelContent.Plan,
	facts : KernelForm.Facts,
	form_plan : KernelForm.Plan,
	ownership : KernelTextOwnership.Plan,
	structure : KernelGate4FormStructure.Plan,
	text : KernelPdfText.ScenePlan,
}

BuildFailure := [
	AnalysisFailure,
	ColorFailure,
	ContentFailure,
	FactsFailure(KernelForm.Error),
	FontFailure,
	FontPlanFailure,
	FormObjectFailure,
	FormPlanFailure(KernelForm.Error),
	FormSceneFailure(KernelScene.Error),
	ImageFailure,
	ObjectFailure,
	OwnershipFailure(KernelTextOwnership.Error),
	EmitFailure,
	ResourceUseFailure,
	SemanticFailure,
	ShapeFailure,
	StructureFailure(KernelGate4FormStructure.Error),
	SubsetFailure,
	TextFailure,
]

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

a4_box : Layout.Rect
a4_box = rect(0, 0, 595000, 842000)

source : Str
source = "Café PDF"

source_range : Semantics.TextRange
source_range = {
	scalars: Semantics.Range.from_start_and_length(0, 8),
	utf8_bytes: Semantics.Range.from_start_and_length(0, 9),
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

text_colors : Color.Store
text_colors = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

empty_image_sources : Image.SourceStore
empty_image_sources = { resources: [] }

## The validated color and image plans this scenario derives its leaf
## identity from.
build_text_stores : {} -> Try({ colors : KernelColor.Plan, images : KernelImage.Plan }, BuildFailure)
build_text_stores = |_| {
	colors = KernelColor.Plan.build(text_colors, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? |_| ColorFailure
	images = KernelImage.Plan.build(
		empty_image_sources,
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ? |_| ImageFailure
	Ok({ colors, images })
}

## Exactly one function body restores the packed font-bytes literal; every
## consumer goes through it. This shape was introduced for the packed-constant
## restore defect in the former pinned compiler (roc-lang/roc#10697 family).
font_bytes : {} -> List(U8)
font_bytes = |_| built_in_font_bytes

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

text_paint : Scene.TextPaint
text_paint = {
	fill: { channels: Gray(0), space: Color.SpaceId.from_index(0) },
	mode: Fill,
	opacity: 65535,
	stroke: NoStroke,
}

## The text form's bounding box covers the run's ascent and descent around the
## baseline at its local origin.
text_form_store : Scene.FormStore
text_form_store = {
	commands: [DrawText({ paint: text_paint, run: Text.RunId.from_index(0) })],
	forms: [{ bbox: rect(0, -3000, 60000, 17000), commands: Semantics.Range.from_start_and_length(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
}

single_placement_scene : {} -> Scene.Store
single_placement_scene = |_| {
	commands: [PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(72000, 700000) })],
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

graph_limits : KernelResourceGraph.Limits
graph_limits = {
	max_collision_entries: 64,
	max_edges: 64,
	max_equality_bytes: 1048576,
	max_hash_bytes: 1048576,
	max_hashes: 64,
	max_ordering_work: 1048576,
	max_payload_bytes: 1048576,
	max_placements: 64,
	max_resources: 64,
	max_roots: 4,
	max_root_uses: 64,
	max_topological_work: 4096,
}

form_limits : KernelForm.Limits
form_limits = KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 4, max_opacity_depth: 64, max_recipe_bytes: 65536 })

scene_limits : KernelScene.Limits
scene_limits = KernelScene.Limits.make({
	max_commands: 8,
	max_dash_lengths: 0,
	max_graphics_depth: 2,
	max_groups: 4,
	max_pages: 1,
	max_path_segments: 0,
	max_paths: 0,
})

form_scene_limits : KernelScene.FormLimits
form_scene_limits = KernelScene.FormLimits.make({ max_form_commands: 8, max_forms: 2 })

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 128,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 256,
	max_direct_depth: 8,
	max_name_bytes: 4096,
	max_names: 128,
	max_objects: 32,
	max_payload_bytes: 262144,
	max_payloads: 8,
	max_streams: 8,
	max_text_string_bytes: 64,
	max_text_strings: 4,
	max_values: 1024,
}

structure_limits : KernelGate4FormStructure.Limits
structure_limits = KernelGate4FormStructure.Limits.make({
	font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 8192, max_unicode_mappings: 64, max_unicode_scalars: 128 }),
	object_limits,
})

font_descriptor : KernelPdfFont.Descriptor
font_descriptor = { flags: 32, italic_angle: 0, stem_v: 80 }

Prelude := { analysis : KernelUnicode.UnicodeAnalysis, font : KernelFont.Inspection, shape : KernelShape.Shape }

## Exactly one function body performs the const-evaluable Unicode analysis,
## font inspection, and shaping calls; every consumer receives the result.
## (This shape also avoids the packed-constant restore defect present in the
## former pinned compiler, from the roc-lang/roc#10697 family.)
build_prelude : {} -> Try(Prelude, BuildFailure)
build_prelude = |_| {
	analysis = KernelUnicode.analyze(
		source,
		{ max_graphemes: 32, max_line_boundaries: 33, max_scalars: 32, max_script_runs: 8 },
	) ? |_| AnalysisFailure
	font = KernelFont.inspect(
		font_bytes({}),
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
	Ok(Prelude.{ analysis, font, shape })
}

build_sample : Prelude, Scene.Store -> Try(Sample, BuildFailure)
build_sample = |prelude, scene_store| {
	font = prelude.font
	shape = prelude.shape
	semantic = KernelTextSemantics.Plan.build(
		semantics,
		1,
		1,
		KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 }),
		KernelTextSemantics.Limits.make({ max_text_properties: 0, max_text_property_bytes: 0, max_text_source_bytes: 9, max_text_source_scalars: 8, max_text_sources: 1 }),
	) ? |_| SemanticFailure
	resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: 1, images: 0, text_runs: shape.store.runs.len() })
	form_scene = KernelScene.FormPlan.build(scene_store, text_form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_text_stores({})?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 1, images: stores.images }, WithTextStore(shape.store), form_limits) ? FactsFailure
	ownership = KernelTextOwnership.Plan.build_with_forms(semantic, KernelScene.FormPlan.page(form_scene), shape.store, KernelForm.Facts.run_fragments(facts)) ? OwnershipFailure
	usages = glyph_usages(shape.store.glyphs)
	font_plan = KernelFontPlan.plan(font, usages, KernelFontPlan.Limits.make({ max_retained_glyphs: 64 })) ? |_| FontPlanFailure
	subset = KernelFontSubset.build(font, font_plan) ? |_| SubsetFailure
	text = KernelPdfText.ScenePlan.build(
		ownership,
		[font_plan],
		KernelPdfText.Limits.make({ max_actual_text_scalars: 64, max_content_bytes: 4096, max_mappings: 64, max_placements: 0, max_source_scalars: 64 }),
	) ? |_| TextFailure
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	font_leaf = { descriptor: { bit_depth: 0, components: 0, flags: 0, height: 0, kind: Font, subtype: 0, width: 0 }, payload: font.bytes }
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors: stores.colors, fonts: [font_leaf], images: stores.images }, WithText(KernelPdfText.ScenePlan.content(text)), tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms_and_text(
		tagged,
		KernelPdfText.ScenePlan.content(text),
		form_context(form_plan),
		KernelContent.Limits.make({ max_content_bytes: 8192, max_content_streams: 1 }),
	) ? |_| ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, stores.colors, stores.images) ? |_| ResourceUseFailure
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(form_plan)
	base = KernelGate2Objects.Plan.build_canonical(
		tagged,
		stores.colors,
		stores.images,
		resource_use,
		content,
		{ color_spaces: leaf_counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(form_plan), profiles: leaf_counts.profiles },
		KernelGate2Objects.Limits.make({ max_objects: 32, max_pages: 1 }),
	) ? |_| ObjectFailure
	objects = KernelGate4FormObjects.Plan.build_with_states(base, KernelForm.Plan.canonical_form_count(form_plan), KernelForm.Plan.canonical_state_count(form_plan), 1, 32) ? |_| FormObjectFailure
	structure = KernelGate4FormStructure.Plan.build(
		tagged,
		stores.colors,
		stores.images,
		content,
		form_plan,
		objects,
		WithTextObjects({ fonts: [{ descriptor: font_descriptor, font, plan: font_plan, subset }], text }),
		structure_limits,
	) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, content, facts, form_plan, ownership, structure, text })
}

form_context : KernelForm.Plan -> KernelContent.FormContext
form_context = |form_plan| {
	count = KernelForm.Plan.canonical_form_count(form_plan)
	var $streams = List.with_capacity(count)
	var $ordinal = 0
	while $ordinal < count {
		$streams = $streams.append(KernelForm.Plan.canonical_form(form_plan, $ordinal).commands)
		$ordinal = $ordinal + 1
	}
	{
		arena: text_form_store.commands,
		color_names: KernelForm.Plan.color_names(form_plan),
		form_names: KernelForm.Plan.form_names(form_plan),
		form_states: KernelForm.Plan.form_command_states(form_plan),
		image_names: KernelForm.Plan.image_names(form_plan),
		page_states: KernelForm.Plan.page_command_states(form_plan),
		pattern_arena: [],
		pattern_names: [],
		pattern_streams: [],
		shading_names: [],
		streams: $streams,
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

## The two text-specific rejections fire in the ownership sweep, before any
## recipe, content, or PDF byte exists.
check_text_negatives : Prelude -> Try(U64, Gate4FormTextEvidence.EvidenceError)
check_text_negatives = |prelude| {
	base_scene = single_placement_scene({})

	## 1: a text-bearing form placed twice.
	twice = {
		..base_scene,
		commands: [
			PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(72000, 700000) }),
			PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(72000, 650000) }),
		],
		groups: [{ commands: Semantics.Range.from_start_and_length(0, 2), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }],
	}
	twice_rejected = match build_facts_for(prelude, twice) {
		Err(TextFormMultiplyPlaced({ form: 0, instances: 2 })) => Bool.True
		_ => Bool.False
	}
	if !twice_rejected {
		return Err(MissingRejection(1))
	}

	## 2: a text-bearing form reachable only under an artifact owner.
	artifact = {
		..base_scene,
		groups: [{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: PageArtifact(Header) }],
	}
	artifact_rejected = match build_facts_for(prelude, artifact) {
		Err(ArtifactTextInForm({ form: 0 })) => Bool.True
		_ => Bool.False
	}
	if !artifact_rejected {
		return Err(MissingRejection(2))
	}

	Ok(2)
}

build_facts_for : Prelude, Scene.Store -> Try(KernelForm.Facts, KernelForm.Error)
build_facts_for = |prelude, scene_store| {
	resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: 1, images: 0, text_runs: prelude.shape.store.runs.len() })
	form_scene = KernelScene.FormPlan.build(scene_store, text_form_store, resources, scene_limits, form_scene_limits) ? |_| ArithmeticOverflow
	stores = build_text_stores({}) ? |_| ArithmeticOverflow
	KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 1, images: stores.images }, WithTextStore(prelude.shape.store), form_limits)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 form text evidence index escaped"
	}
}

## Text painted inside a meaningful form keeps its run, mapping, ActualText,
## and font behavior while the form's own dictionary carries the font.
expect {
	result = Gate4FormTextEvidence.text_form(0)?
	result.work.get(0) == Ok(1) and result.work.get(1) == Ok(1) and result.work.get(2) == Ok(1) and result.work.get(4) == Ok(1) and result.work.get(12) == Ok(8) and result.work.get(19) == Ok(2)
}
