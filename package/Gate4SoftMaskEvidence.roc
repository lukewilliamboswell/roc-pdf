import Color
import Font
import Image
import KernelColor
import KernelContent
import KernelEmit
import KernelForm
import KernelGate2Objects
import KernelGate4FormObjects
import KernelGate4FormStructure
import KernelImage
import KernelObject
import KernelPdfFont
import KernelResourceGraph
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelSrgbProfile
import KernelTagged
import Layout
import Scene
import Semantics
import Text

## Gate 4 Form-backed alpha soft-mask evidence.
##
## Every scenario authors a validated scene whose soft-mask groups reference
## isolated-group mask Forms, runs the whole canonical pipeline (scene
## validation, the derived-state pre-pass, the two resource-graph runs with
## state-to-mask-form edges, canonical mask-state identity, page transparency
## groups, content lowering, object planning, emission, sealing), and emits
## real PDF bytes plus the deterministic work vector.
##
## - `showcase`  : one page whose shared mask Form (an isolated group with a
##                 half-opacity band, an opaque band, and implicit zero
##                 coverage outside them) masks a meaningful path, an
##                 artifact path through an authored twin mask that must
##                 deduplicate, a constant-alpha times mask product, a plain
##                 form placement, and an isolated-group form whose internal
##                 mask composes with the outer one — with a reversed
##                 authored-ID twin that must produce identical bytes.
## - `reuse xN`  : N soft-mask groups over one mask Form collapse to one
##                 canonical mask state and one mask form object.
## - `masks xN`  : N distinct mask Forms stay N canonical states/objects.
## - `chain xN`  : a mask Form whose rendering applies the next mask, N deep,
##                 inside the declared chain budget.
## - `unique`/`shared` : the one-shot ownership path versus the same
##                 retained authored input planned twice.
Gate4SoftMaskEvidence :: [].{
	EvidenceError : [
		AdversarialOrderDiverged,
		EvidenceFailure,
		InvalidScale,
		MissingRejection(U64),
		SharingDiverged,
		SharedInputDiverged,
	]

	scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scenario = |mode, scale| run_scenario(mode, scale)

	## Atomic negative twins: each input differs from a valid scene in exactly
	## one fact, every rejection is a distinct structured diagnostic, and no
	## partial plan or PDF byte escapes. The fixture emits only an unrelated
	## single-mask document as its snapshot payload.
	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |runtime_context| run_negatives(runtime_context)
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

span : U64, U64 -> Semantics.Range
span = |start, length| Semantics.Range.from_start_and_length(start, length)

page_box : Layout.Rect
page_box = rect(0, 0, 100000, 100000)

d65_white : Color.Tristimulus
d65_white = { x: 950000, y: 1000000, z: 1089000 }

cal_gray : Color.Space
cal_gray = CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: d65_white })

gray_value : U16, U64 -> Color.Value
gray_value = |level, space| { channels: Gray(level), space: Color.SpaceId.from_index(space) }

rgb_value : U16, U16, U16, U64 -> Color.Value
rgb_value = |red, green, blue, space| { channels: Rgb({ blue, green, red }), space: Color.SpaceId.from_index(space) }

fill_with : Color.Value -> Scene.PathStyle
fill_with = |color| { fill: SolidFill({ color, rule: Nonzero }), stroke: NoStroke }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

opacity : U16, U64, U64 -> Scene.Command
opacity = |alpha, start, length| Opacity({ children: span(start, length), opacity: alpha })

soft_mask : U64, U64, U64 -> Scene.Command
soft_mask = |mask, start, length| SoftMask({ children: span(start, length), mask: Scene.FormId.from_index(mask) })

## The semantic store for `fragments` meaningful paragraphs whose logical
## order deliberately differs from paint order.
build_semantics : U64, List(U64) -> Semantics.Store
build_semantics = |fragment_count, logical_order| {
	var $spine = List.with_capacity(fragment_count)
	var $order_index = 0
	while $order_index < logical_order.len() {
		$spine = $spine.append(ChildNode(Semantics.NodeId.from_index(list_at(logical_order, $order_index) + 1)))
		$order_index = $order_index + 1
	}
	var $nodes = List.with_capacity(fragment_count + 1)
	$nodes = $nodes.append({
		attributes: empty_range,
		content: span(0, fragment_count),
		element_identifier: NoElementIdentifier,
		id: Semantics.NodeId.from_index(0),
		language: Inherited,
		parent: DocumentRoot,
		role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
		structure_element: Semantics.StructureElementId.from_index(0),
		text_properties: empty_range,
	})
	var $content_spine = $spine
	var $occurrences = List.with_capacity(fragment_count)
	var $occurrence_fragments = List.with_capacity(fragment_count)
	var $fragments = List.with_capacity(fragment_count)
	var $paragraph = 0
	while $paragraph < fragment_count {
		$content_spine = $content_spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index($paragraph)))
		$occurrences = $occurrences.append({
			fragments: span($paragraph, 1),
			id: Semantics.OccurrenceId.from_index($paragraph),
			language: Inherited,
			source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(empty_range)),
			text_properties: empty_range,
		})
		$occurrence_fragments = $occurrence_fragments.append(Semantics.FragmentId.from_index($paragraph))
		$fragments = $fragments.append({
			content_stream: Semantics.ContentStreamId.from_index(0),
			continuation_index: 0,
			id: Semantics.FragmentId.from_index($paragraph),
			occurrence: Semantics.OccurrenceId.from_index($paragraph),
			page: Semantics.PageId.from_index(0),
			source_range: ByteRange(empty_range),
		})
		$nodes = $nodes.append({
			attributes: empty_range,
			content: span(fragment_count + $paragraph, 1),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index($paragraph + 1),
			language: Inherited,
			parent: ParentNode(Semantics.NodeId.from_index(0)),
			role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index($paragraph + 1),
			text_properties: empty_range,
		})
		$paragraph = $paragraph + 1
	}
	{
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $content_spine,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: $fragments,
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: $nodes,
		non_text_sources: [[]],
		occurrence_fragments: $occurrence_fragments,
		occurrences: $occurrences,
		relationships: [],
		role_mappings: [],
		text_properties: [],
		text_sources: [],
	}
}

Scenario := {
	color_limits : KernelColor.Limits,
	colors : Color.Store,
	form_store : Scene.FormStore,
	image_limits : KernelImage.Limits,
	images : Image.SourceStore,
	scene : Scene.Store,
	semantics : Semantics.Store,
}

Built := {
	bytes : List(U8),
	colors : KernelColor.Plan,
	content : KernelContent.Plan,
	facts : KernelForm.Facts,
	form_plan : KernelForm.Plan,
	form_scene : KernelScene.FormPlan,
	images : KernelImage.Plan,
	structure : KernelGate4FormStructure.Plan,
	tagged : KernelTagged.Plan,
}

graph_limits : KernelResourceGraph.Limits
graph_limits = {
	max_collision_entries: 8192,
	max_edges: 16384,
	max_equality_bytes: 8388608,
	max_hash_bytes: 8388608,
	max_hashes: 8192,
	max_ordering_work: 8388608,
	max_payload_bytes: 8388608,
	max_placements: 8192,
	max_resources: 8192,
	max_root_uses: 8192,
	max_roots: 8,
	max_topological_work: 1048576,
}

form_limits : KernelForm.Limits
form_limits = KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 4, max_opacity_depth: 64, max_recipe_bytes: 4194304 })

scene_limits : KernelScene.Limits
scene_limits = KernelScene.Limits.make({
	max_commands: 65536,
	max_dash_lengths: 0,
	max_graphics_depth: 512,
	max_groups: 4096,
	max_pages: 1,
	max_path_segments: 4096,
	max_paths: 1024,
})

form_scene_limits : KernelScene.FormLimits
form_scene_limits = KernelScene.FormLimits.make({ max_form_commands: 65536, max_forms: 4096 })

content_limits : KernelContent.Limits
content_limits = KernelContent.Limits.make({ max_content_bytes: 1048576, max_content_streams: 1 })

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 65536,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 65536,
	max_direct_depth: 8,
	max_name_bytes: 65536,
	max_names: 8192,
	max_objects: 8192,
	max_payload_bytes: 2097152,
	max_payloads: 4096,
	max_streams: 4096,
	max_text_string_bytes: 64,
	max_text_strings: 1,
	max_values: 262144,
}

structure_limits : KernelGate4FormStructure.Limits
structure_limits = KernelGate4FormStructure.Limits.make({
	font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 0, max_unicode_mappings: 0, max_unicode_scalars: 0 }),
	object_limits,
})

semantic_limits : U64, U64, U64 -> KernelSemantics.Limits
semantic_limits = |nodes, spine, fragments| KernelSemantics.Limits.make({
	max_attributes: 0,
	max_content_spine: spine,
	max_fragments: fragments,
	max_namespaces: 1,
	max_nodes: nodes,
	max_occurrences: nodes,
	max_semantic_depth: 2,
})

BuildFailure := [
	ColorFailure(KernelColor.Error),
	ContentFailure(KernelContent.Error),
	FactsFailure(KernelForm.Error),
	FormPlanFailure(KernelForm.Error),
	FormSceneFailure(KernelScene.Error),
	ImageFailure(KernelImage.Error),
	ObjectFailure(KernelGate2Objects.Error),
	FormObjectFailure(KernelGate4FormObjects.Error),
	EmitFailure,
	ResourceUseFailure(KernelResourceUse.Error),
	SemanticFailure(KernelSemantics.Error),
	StructureFailure(KernelGate4FormStructure.Error),
	TaggedFailure(KernelTagged.Error),
]

run_pipeline : Scenario -> Try(Built, BuildFailure)
run_pipeline = |input| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: input.colors.spaces.len(),
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? ColorFailure
	images = KernelImage.Plan.build(input.images, colors, input.image_limits) ? ImageFailure
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors, fonts: [], images }, NoText, tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan, input.form_store), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms_and_blending(form_scene, colors, images, KernelForm.Facts.blending(facts)) ? ResourceUseFailure
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(form_plan)
	base = KernelGate2Objects.Plan.build_canonical(
		tagged,
		colors,
		images,
		resource_use,
		content,
		{ color_spaces: leaf_counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(form_plan), profiles: leaf_counts.profiles },
		KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 1 }),
	) ? ObjectFailure
	objects = KernelGate4FormObjects.Plan.build_with_states(base, KernelForm.Plan.canonical_form_count(form_plan), KernelForm.Plan.canonical_state_count(form_plan), 0, 8192) ? FormObjectFailure
	structure = KernelGate4FormStructure.Plan.build(tagged, colors, images, content, form_plan, objects, NoTextObjects, structure_limits) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, colors, content, facts, form_plan, form_scene, images, structure, tagged })
}

form_context : KernelForm.Plan, Scene.FormStore -> KernelContent.FormContext
form_context = |form_plan, form_store| {
	count = KernelForm.Plan.canonical_form_count(form_plan)
	var $streams = List.with_capacity(count)
	var $ordinal = 0
	while $ordinal < count {
		$streams = $streams.append(KernelForm.Plan.canonical_form(form_plan, $ordinal).commands)
		$ordinal = $ordinal + 1
	}
	{
		arena: form_store.commands,
		color_names: KernelForm.Plan.color_names(form_plan),
		form_names: KernelForm.Plan.form_names(form_plan),
		form_states: KernelForm.Plan.form_command_states(form_plan),
		image_names: KernelForm.Plan.image_names(form_plan),
		page_states: KernelForm.Plan.page_command_states(form_plan),
		streams: $streams,
	}
}

work_vector : Built -> List(U64)
work_vector = |built| {
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	content_work = KernelContent.Plan.work(built.content)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		facts_work.soft_mask_commands,
		facts_work.mask_states,
		plan_work.canonical_mask_states,
		plan_work.deduplicated_mask_states,
		facts_work.max_mask_chain,
		facts_work.mask_chain_sweep_visits,
		facts_work.opacity_commands,
		facts_work.opacity_groups,
		plan_work.canonical_ext_g_states,
		facts_work.transparency_pages,
		structure_work.transparency_page_groups,
		plan_work.isolated_canonical_forms,
		structure_work.state_objects,
		plan_work.state_recipe_bytes,
		facts_work.closure_uses,
		content_work.mask_groups,
		content_work.opacity_groups,
		content_work.graphics_state_pairs,
		plan_work.dictionary_entries,
		plan_work.nested_dictionary_entries,
		facts_work.direct_edges,
		facts_work.use_command_visits,
		facts_work.transparency_sweep_visits,
		graph_work.hashes,
		graph_work.bytes_hashed,
		graph_work.retained_payload_bytes,
		graph_work.closure_uses,
		plan_work.canonical_forms,
		plan_work.authored_forms,
		plan_work.deduplicated_forms,
		plan_work.semantic_placements,
		plan_work.artifact_placements,
		structure_work.objects,
		built.bytes.len(),
	]
}

showcase_space_count : U64
showcase_space_count = 2

dense_space : U64, [Forward, Reversed] -> U64
dense_space = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_space_count - 1 - logical
}

showcase_form_count : U64
showcase_form_count = 4

dense_form : U64, [Forward, Reversed] -> U64
dense_form = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_form_count - 1 - logical
}

showcase_colors : [Forward, Reversed] -> Color.Store
showcase_colors = |direction| {
	var $spaces = List.with_capacity(showcase_space_count)
	var $dense = 0
	while $dense < showcase_space_count {
		logical = match direction {
			Forward => $dense
			Reversed => showcase_space_count - 1 - $dense
		}
		space = if logical == 0 cal_gray else Srgb(Color.ProfileId.from_index(0))
		$spaces = $spaces.append({ id: Color.SpaceId.from_index($dense), space })
		$dense = $dense + 1
	}
	{ profiles: [KernelSrgbProfile.profile(0, 0)], spaces: $spaces, tags: KernelSrgbProfile.tags }
}

showcase_color_limits : KernelColor.Limits
showcase_color_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count,
	max_profiles: 1,
	max_spaces: 2,
	max_tags: KernelSrgbProfile.tag_count,
})

no_image_limits : KernelImage.Limits
no_image_limits = KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 })

## The shared mask Form: an isolated group whose bounding box spans the page
## with a half-opacity band at x 20..50, an opaque band at x 50..80, and
## implicit zero coverage elsewhere, so masked content shows its three
## zones. Fills paint calibrated black; an alpha mask reads coverage, not
## color.
mask_band_commands : U64, U64 -> List(Scene.Command)
mask_band_commands = |start, space| [
	opacity(32768, start + 2, 1),
	DrawPath({ path: Scene.PathId.from_index(4), style: fill_with(gray_value(0, space)) }),
	DrawPath({ path: Scene.PathId.from_index(3), style: fill_with(gray_value(0, space)) }),
]

## One page exercising every supported soft-mask shape. Logical forms:
## 0 = the shared band mask (isolated group); 1 = its authored twin, which
## must deduplicate; 2 = an isolated content form whose internal mask
## composes with the outer one; 3 = a plain form masked at its placement.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	space = |logical| dense_space(logical, direction)
	mask_of = |logical| dense_form(logical, direction)
	page_commands = [
		soft_mask(mask_of(0), 1, 1),
		DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(rgb_value(65535, 0, 0, space(1))) }),
		soft_mask(mask_of(1), 3, 1),
		DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(rgb_value(0, 0, 65535, space(1))) }),
		opacity(32768, 5, 1),
		soft_mask(mask_of(0), 6, 1),
		DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(49344, space(0))) }),
		soft_mask(mask_of(0), 8, 1),
		PlaceForm({ form: Scene.FormId.from_index(mask_of(3)), transform: translate(10000, 26000) }),
		soft_mask(mask_of(0), 10, 1),
		PlaceForm({ form: Scene.FormId.from_index(mask_of(2)), transform: translate(10000, 8000) }),
		DrawPath({ path: Scene.PathId.from_index(5), style: fill_with(gray_value(24672, space(0))) }),
	]

	## The form arena in dense-ID order. Logical content is fixed; only the
	## dense IDs (and therefore arena order and references) permute.
	var $form_arena = []
	var $forms = List.with_capacity(showcase_form_count)
	var $dense_index = 0
	while $dense_index < showcase_form_count {
		logical = match direction {
			Forward => $dense_index
			Reversed => showcase_form_count - 1 - $dense_index
		}
		start = $form_arena.len()
		if logical == 0 or logical == 1 {
			$form_arena = $form_arena.concat(mask_band_commands(start, space(0)))
			$forms = $forms.append({ bbox: rect(0, 0, 100000, 100000), commands: span(start, 2), group: IsolatedGroup, id: Scene.FormId.from_index($dense_index) })
		} else if logical == 2 {
			$form_arena = $form_arena.append(soft_mask(mask_of(0), start + 1, 1))
			$form_arena = $form_arena.append(DrawPath({ path: Scene.PathId.from_index(6), style: fill_with(rgb_value(0, 0, 65535, space(1))) }))
			$forms = $forms.append({ bbox: rect(0, 0, 80000, 10000), commands: span(start, 1), group: IsolatedGroup, id: Scene.FormId.from_index($dense_index) })
		} else {
			$form_arena = $form_arena.append(DrawPath({ path: Scene.PathId.from_index(7), style: fill_with(rgb_value(0, 49344, 0, space(1))) }))
			$forms = $forms.append({ bbox: rect(0, 0, 80000, 8000), commands: span(start, 1), group: NoGroup, id: Scene.FormId.from_index($dense_index) })
		}
		$dense_index = $dense_index + 1
	}

	scene = {
		commands: page_commands,
		dash_lengths: [],
		groups: [
			{ commands: span(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: span(2, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
			{ commands: span(4, 1), id: Scene.GroupId.from_index(2), owner: Fragment(Semantics.FragmentId.from_index(1)) },
			{ commands: span(7, 1), id: Scene.GroupId.from_index(3), owner: Fragment(Semantics.FragmentId.from_index(2)) },
			{ commands: span(9, 1), id: Scene.GroupId.from_index(4), owner: PageArtifact(Watermark) },
			{ commands: span(11, 1), id: Scene.GroupId.from_index(5), owner: Fragment(Semantics.FragmentId.from_index(3)) },
		],
		page_groups: [
			Scene.GroupId.from_index(0),
			Scene.GroupId.from_index(1),
			Scene.GroupId.from_index(2),
			Scene.GroupId.from_index(3),
			Scene.GroupId.from_index(4),
			Scene.GroupId.from_index(5),
		],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: span(0, 6),
				rotation: Rotate0,
			},
		],
		path_segments: [
			Rectangle(rect(10000, 84000, 80000, 8000)),
			Rectangle(rect(10000, 62000, 80000, 10000)),
			Rectangle(rect(10000, 44000, 80000, 10000)),
			Rectangle(rect(20000, 0, 30000, 100000)),
			Rectangle(rect(50000, 0, 30000, 100000)),
			Rectangle(rect(2000, 2000, 6000, 6000)),
			Rectangle(rect(0, 0, 80000, 10000)),
			Rectangle(rect(0, 0, 80000, 8000)),
		],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: span(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: span(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: span(2, 1) },
			{ id: Scene.PathId.from_index(3), segments: span(3, 1) },
			{ id: Scene.PathId.from_index(4), segments: span(4, 1) },
			{ id: Scene.PathId.from_index(5), segments: span(5, 1) },
			{ id: Scene.PathId.from_index(6), segments: span(6, 1) },
			{ id: Scene.PathId.from_index(7), segments: span(7, 1) },
		],
	}
	{
		color_limits: showcase_color_limits,
		colors: showcase_colors(direction),
		form_store: { commands: $form_arena, forms: $forms },
		image_limits: no_image_limits,
		images: { resources: [] },
		scene,
		semantics: build_semantics(4, [1, 0, 2, 3]),
	}
}

scaled_colors : Color.Store
scaled_colors = showcase_colors(Forward)

anchor_group : Scene.OwnedGroup
anchor_group = { commands: span(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }

anchor_command : Scene.Command
anchor_command = DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(gray_value(8224, 0)) })

scaled_scene : List(Scene.Command), U64 -> Scene.Store
scaled_scene = |commands, top_level| {
	{
		commands,
		dash_lengths: [],
		groups: [
			anchor_group,
			{ commands: span(1, top_level), id: Scene.GroupId.from_index(1), owner: PageArtifact(Watermark) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: span(0, 2),
				rotation: Rotate0,
			},
		],
		path_segments: [Rectangle(rect(0, 95000, 4000, 4000)), Rectangle(rect(1000, 1000, 3000, 3000)), Rectangle(rect(0, 0, 4000, 4000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: span(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: span(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: span(2, 1) },
		],
	}
}

scaled_scenario : Scene.Store, Scene.FormStore -> Scenario
scaled_scenario = |scene, form_store| {
	{
		color_limits: showcase_color_limits,
		colors: scaled_colors,
		form_store,
		image_limits: no_image_limits,
		images: { resources: [] },
		scene,
		semantics: build_semantics(1, [0]),
	}
}

## One isolated-group band mask covering the small grid cell, at authored
## form index `form`.
scaled_mask_form : U64, U64, I64 -> { commands : List(Scene.Command), form : Scene.Form }
scaled_mask_form = |start, form, width| {
	{
		commands: [
			opacity(32768, start + 1, 1),
			DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }),
		],
		form: { bbox: rect(0, 0, width, 4000), commands: span(start, 1), group: IsolatedGroup, id: Scene.FormId.from_index(form) },
	}
}

## N soft-mask groups over one mask Form (`Reuse`) or over N distinct mask
## Forms (`Distinct`): the anchor path, then N top-level mask commands whose
## child paths follow the top-level run.
mask_grid : U64, [Distinct, Reuse] -> Scenario
mask_grid = |scale, variant| {
	mask_forms = match variant {
		Reuse => 1
		Distinct => scale
	}
	var $commands = [anchor_command]
	var $group = 0
	while $group < scale {
		mask = match variant {
			Reuse => 0
			Distinct => $group
		}
		$commands = $commands.append(soft_mask(mask, 1 + scale + $group, 1))
		$group = $group + 1
	}
	$group = 0
	while $group < scale {
		$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }))
		$group = $group + 1
	}
	var $form_arena = []
	var $forms = List.with_capacity(mask_forms)
	var $form_index = 0
	while $form_index < mask_forms {
		built = scaled_mask_form($form_arena.len(), $form_index, 4000 + $form_index.to_i64_wrap())
		$form_arena = $form_arena.concat(built.commands)
		$forms = $forms.append(built.form)
		$form_index = $form_index + 1
	}
	scaled_scenario(scaled_scene($commands, scale), { commands: $form_arena, forms: $forms })
}

## A mask chain N deep: the page masks through form 0, and each mask Form's
## rendering applies the next mask, ending in a plain isolated band.
mask_chain : U64 -> Scenario
mask_chain = |depth| {
	commands = [
		anchor_command,
		soft_mask(0, 2, 1),
		DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
	]
	var $form_arena = []
	var $forms = List.with_capacity(depth)
	var $form_index = 0
	while $form_index < depth {
		start = $form_arena.len()
		if $form_index + 1 < depth {
			$form_arena = $form_arena.append(soft_mask($form_index + 1, start + 1, 1))
			$form_arena = $form_arena.append(DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }))
			$forms = $forms.append({ bbox: rect(0, 0, 4000, 4000), commands: span(start, 1), group: IsolatedGroup, id: Scene.FormId.from_index($form_index) })
		} else {
			$form_arena = $form_arena.append(opacity(32768, start + 1, 1))
			$form_arena = $form_arena.append(DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }))
			$forms = $forms.append({ bbox: rect(0, 0, 4000, 4000), commands: span(start, 1), group: IsolatedGroup, id: Scene.FormId.from_index($form_index) })
		}
		$form_index = $form_index + 1
	}
	scaled_scenario(scaled_scene(commands, 1), { commands: $form_arena, forms: $forms })
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4SoftMaskEvidence.EvidenceError)
run_scenario = |mode, scale| {
	if mode == "showcase" {
		forward = run_pipeline(showcase_scenario(Forward)) ? |_| EvidenceFailure
		reversed = run_pipeline(showcase_scenario(Reversed)) ? |_| EvidenceFailure
		if forward.bytes != reversed.bytes {
			return Err(AdversarialOrderDiverged)
		}
		check_showcase_sharing(forward)?
		Ok({ bytes: forward.bytes, work: work_vector(forward) })
	} else if mode == "unique" {
		built = run_pipeline(showcase_scenario(Forward)) ? |_| EvidenceFailure
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "shared" {
		scenario_input = showcase_scenario(Forward)
		first = run_pipeline(scenario_input) ? |_| EvidenceFailure
		second = run_pipeline(scenario_input) ? |_| EvidenceFailure
		if first.bytes != second.bytes {
			return Err(SharedInputDiverged)
		}
		Ok({ bytes: first.bytes, work: work_vector(first) })
	} else if mode == "reuse" {
		if scale < 1 or scale > 1000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(mask_grid(scale, Reuse)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_mask_states != 1 or work.canonical_forms != 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "masks" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(mask_grid(scale, Distinct)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_mask_states != scale or work.canonical_forms != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "chain" {
		if scale < 1 or scale > 4 {
			return Err(InvalidScale)
		}
		built = run_pipeline(mask_chain(scale)) ? |_| EvidenceFailure
		facts_work = KernelForm.Facts.work(built.facts)
		if facts_work.max_mask_chain != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The showcase must produce exactly the deduplicated canonical facts: the
## authored twin mask collapses (four authored forms, three canonical), all
## six mask groups share one canonical mask state, the constant-alpha group
## stays a separate alpha state, and the page carries its transparency
## group.
check_showcase_sharing : Built -> Try({}, Gate4SoftMaskEvidence.EvidenceError)
check_showcase_sharing = |built| {
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	if facts_work.soft_mask_commands != 6 or facts_work.mask_states != 2 {
		return Err(SharingDiverged)
	}
	if plan_work.canonical_mask_states != 1 or plan_work.deduplicated_mask_states != 1 {
		return Err(SharingDiverged)
	}
	if plan_work.canonical_ext_g_states != 2 or plan_work.authored_forms != 4 or plan_work.canonical_forms != 3 {
		return Err(SharingDiverged)
	}
	if facts_work.max_mask_chain != 1 or facts_work.transparency_pages != 1 {
		return Err(SharingDiverged)
	}
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	if structure_work.transparency_page_groups != 1 or structure_work.state_objects != 2 {
		return Err(SharingDiverged)
	}
	content_work = KernelContent.Plan.work(built.content)
	if content_work.mask_groups != 6 or content_work.opacity_groups != 2 {
		return Err(SharingDiverged)
	}
	Ok({})
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4SoftMaskEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	rejections = check_negatives(context)?
	carrier = run_pipeline(mask_grid(context, Reuse)) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [rejections, 0, carrier.bytes.len()] })
}

expect_facts_rejection : U64, Scenario, KernelForm.Limits, (KernelForm.Error -> Bool) -> Try({}, Gate4SoftMaskEvidence.EvidenceError)
expect_facts_rejection = |ordinal, input, limits, matches| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: input.colors.spaces.len(),
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? |_| MissingRejection(ordinal)
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? |_| MissingRejection(ordinal)
	images = KernelImage.Plan.build(input.images, colors, input.image_limits) ? |_| MissingRejection(ordinal)
	match KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

## A minimal shaped-run store: enough typed evidence for use collection to
## reach the mask-ownership rules, which reject before any recipe or
## lowering consumes the run.
minimal_text_store : Text.Store
minimal_text_store = {
	clusters: [],
	glyph_indices: [],
	glyphs: [],
	runs: [
		{
			actual_text: FromOccurrence,
			clusters: empty_range,
			direction: LeftToRight,
			glyphs: empty_range,
			id: Text.RunId.from_index(0),
			instance: Font.InstanceId.from_index(0),
			language: Inherited,
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: unit(12000),
			source: { scalars: empty_range, utf8_bytes: empty_range },
			substitutions: empty_range,
			transformations: empty_range,
			writing_mode: Horizontal,
		},
	],
	substitutions: [],
	transformations: [],
}

## Each negative twin below changes exactly one fact of a valid scene and
## must fail with its own structured diagnostic before any plan or byte
## escapes.
check_negatives : U64 -> Try(U64, Gate4SoftMaskEvidence.EvidenceError)
check_negatives = |context| {

	## The runtime context threads through the authored scenes so no
	## rejection can be resolved at compile time.
	base = mask_grid(context, Reuse)

	## 1: soft masks stay rejected under the Gate 2 resource constructor.
	gate2_rejected = match KernelScene.Plan.build(base.scene, KernelScene.Resources.make({ color_spaces: 2, images: 0 }), scene_limits) {
		Err(UnsupportedCommand({ command })) => command == context
		_ => Bool.False
	}
	if !gate2_rejected {
		return Err(MissingRejection(1))
	}

	## 2: a mask reference outside the declared form store.
	out_of_range = {
		..base,
		scene: {
			..base.scene,
			commands: [
				anchor_command,
				soft_mask(context + 6, 2, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			],
		},
	}
	scene_rejected = match KernelScene.FormPlan.build(
		out_of_range.scene,
		out_of_range.form_store,
		KernelScene.Resources.with_forms({ color_spaces: 2, forms: 1, images: 0, text_runs: 0 }),
		scene_limits,
		form_scene_limits,
	) {
		Err(IndexOutOfRange({ available: 1, index, kind: FormIndex })) => index == context + 6
		_ => Bool.False
	}
	if !scene_rejected {
		return Err(MissingRejection(2))
	}

	## 3: a mask referencing a form without an isolated group.
	plain_mask = {
		..base,
		form_store: {
			commands: base.form_store.commands,
			forms: [{ ..list_at(base.form_store.forms, 0), group: NoGroup }],
		},
	}
	expect_facts_rejection(
		3,
		plain_mask,
		form_limits,
		|error| match error {
			MaskFormNotIsolated({ command: 1, form: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 4: a soft-mask group nested under another within one stream.
	nested = {
		..base,
		scene: {
			..base.scene,
			commands: [
				anchor_command,
				soft_mask(0, 2, 1),
				soft_mask(0, 3, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			],
		},
	}
	expect_facts_rejection(
		4,
		nested,
		form_limits,
		|error| match error {
			NestedSoftMask({ command: 2 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 5: a non-group form applying its own mask under an ambient mask.
	masked_form = {
		..base,
		scene: {
			..base.scene,
			commands: [
				anchor_command,
				soft_mask(0, 2, 1),
				PlaceForm({ form: Scene.FormId.from_index(1), transform: translate(0, 0) }),
			],
		},
		form_store: {
			commands: base.form_store.commands.concat([
				soft_mask(0, 3, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			]),
			forms: base.form_store.forms.append({ bbox: rect(0, 0, 4000, 4000), commands: span(2, 1), group: NoGroup, id: Scene.FormId.from_index(1) }),
		},
	}
	expect_facts_rejection(
		5,
		masked_form,
		form_limits,
		|error| match error {
			FormMaskInAmbient({ form: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: semantic text transitively reachable inside a mask rendering.
	text_mask = {
		..base,
		form_store: {
			commands: [
				opacity(32768, 1, 1),
				DrawText({
					paint: { fill: gray_value(0, 0), mode: Fill, opacity: 65535, stroke: NoStroke },
					run: Text.RunId.from_index(0),
				}),
			],
			forms: base.form_store.forms,
		},
	}
	text_resources = KernelScene.Resources.with_forms({ color_spaces: 2, forms: 1, images: 0, text_runs: 1 })
	text_scene = KernelScene.FormPlan.build(text_mask.scene, text_mask.form_store, text_resources, scene_limits, form_scene_limits) ? |_| MissingRejection(6)
	text_colors = KernelColor.Plan.build(text_mask.colors, text_mask.color_limits) ? |_| MissingRejection(6)
	text_images = KernelImage.Plan.build(text_mask.images, text_colors, text_mask.image_limits) ? |_| MissingRejection(6)
	text_rejected = match KernelForm.Facts.build(text_scene, { colors: text_colors, font_count: 1, images: text_images }, WithTextStore(minimal_text_store), form_limits) {
		Err(TextInMaskForm({ form: 0 })) => Bool.True
		_ => Bool.False
	}
	if !text_rejected {
		return Err(MissingRejection(6))
	}

	## 7: the mask chain budget.
	expect_facts_rejection(
		7,
		mask_chain(3),
		KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 2, max_opacity_depth: 64, max_recipe_bytes: 4194304 }),
		|error| match error {
			MaskDepthExceeded({ attempted: 3, limit: 2 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 8: a mask cycle: two isolated forms masking through each other.
	cycle = {
		..base,
		scene: {
			..base.scene,
			commands: [
				anchor_command,
				PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) }),
			],
		},
		form_store: {
			commands: [
				soft_mask(1, 1, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
				soft_mask(0, 3, 1),
				DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }),
			],
			forms: [
				{ bbox: rect(0, 0, 4000, 4000), commands: span(0, 1), group: IsolatedGroup, id: Scene.FormId.from_index(0) },
				{ bbox: rect(0, 0, 4000, 4000), commands: span(2, 1), group: IsolatedGroup, id: Scene.FormId.from_index(1) },
			],
		},
	}
	expect_facts_rejection(
		8,
		cycle,
		form_limits,
		|error| match error {
			Graph(DependencyCycle(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 9: a masked page without the packaged sRGB blending space.
	expect_facts_rejection(
		9,
		{
			..base,
			color_limits: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
			colors: { profiles: [], spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }], tags: [] },
		},
		form_limits,
		|error| match error {
			MissingBlendingSpace({ page: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	Ok(context * 9)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 soft-mask evidence index escaped"
	}
}

## The showcase deduplicates the authored twin mask into one canonical mask
## state over one canonical mask form, keeps the constant-alpha state
## separate, and emits identical bytes for both authored orders.
expect {
	result = Gate4SoftMaskEvidence.scenario("showcase", 0)?
	result.work.get(0) == Ok(6) and result.work.get(1) == Ok(2) and result.work.get(2) == Ok(1) and result.work.get(3) == Ok(1) and result.work.get(8) == Ok(2) and result.work.get(10) == Ok(1) and result.work.get(28) == Ok(4) and result.work.get(27) == Ok(3)
}

## Repeated mask groups over one mask Form share one canonical mask state;
## the mask Form's internal half-opacity band adds the one alpha state.
expect {
	result = Gate4SoftMaskEvidence.scenario("reuse", 5)?
	result.work.get(0) == Ok(5) and result.work.get(2) == Ok(1) and result.work.get(15) == Ok(5) and result.work.get(12) == Ok(2)
}

## Distinct mask Forms stay distinct canonical mask states and objects,
## while their identical internal bands share one alpha state.
expect {
	result = Gate4SoftMaskEvidence.scenario("masks", 5)?
	result.work.get(2) == Ok(5) and result.work.get(12) == Ok(6) and result.work.get(27) == Ok(5)
}

## A mask chain records its exact depth.
expect {
	result = Gate4SoftMaskEvidence.scenario("chain", 3)?
	result.work.get(4) == Ok(3) and result.work.get(2) == Ok(3)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4SoftMaskEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(9) and result.work.get(1) == Ok(0)
}
