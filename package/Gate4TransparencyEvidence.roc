import Color
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

## Gate 4 transparency evidence.
##
## Every scenario authors a validated scene whose constant-opacity groups,
## alpha imagery, and transparency-group forms run the whole canonical
## pipeline (scene validation, the opacity pre-pass, the two resource-graph
## runs, canonical ExtGState identity, page/form transparency groups, content
## lowering, object planning, emission, sealing) and emits real PDF bytes
## plus the deterministic work vector.
##
## - `showcase`  : one page exercising an intermediate constant on a path,
##                 exactly multiplying nested opacity (0.75 x 2/3 collapsing
##                 to the same canonical state as a directly authored 0.5),
##                 the fully opaque identity normalizing away, zero opacity,
##                 opacity over an alpha image, opacity around a plain form
##                 placement, opacity inside a form, and an isolated-group
##                 form with internal opacity placed under page opacity —
##                 with meaningful and artifact placements, and a reversed
##                 authored-ID twin that must produce identical bytes.
## - `share xN`  : N opacity groups sharing one constant collapse to one
##                 canonical ExtGState while every group keeps its own
##                 balanced `q .. gs .. Q` operators.
## - `states xN` : N distinct constants stay N canonical states and objects.
## - `nest xN`   : one N-deep nested chain of distinct effective products.
## - `forms xN`  : N distinct forms each carrying one opacity group over one
##                 shared constant: per-form dictionaries and form-to-state
##                 edges scale while the canonical state count stays one.
## - `unique`/`shared` : the one-shot ownership path versus the same
##                 retained authored input planned twice.
Gate4TransparencyEvidence :: [].{
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
	## single-group document as its snapshot payload.
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

gray_pixels : List(U8)
gray_pixels = [0, 64, 128, 255]

alpha_pixels : List(U8)
alpha_pixels = [255, 255, 0, 0]

identity_transform : Scene.Matrix
identity_transform = { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

opacity : U16, U64, U64 -> Scene.Command
opacity = |alpha, start, length| Opacity({ children: span(start, length), opacity: alpha })

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
		font_names: KernelForm.Plan.font_names(form_plan),
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

work_vector : Built -> List(U64)
work_vector = |built| {
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	content_work = KernelContent.Plan.work(built.content)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		facts_work.opacity_commands,
		facts_work.opacity_groups,
		facts_work.opaque_normalized,
		facts_work.distinct_opacity_values,
		plan_work.canonical_ext_g_states,
		plan_work.deduplicated_opacity_groups,
		facts_work.max_opacity_depth,
		facts_work.transparency_pages,
		structure_work.transparency_page_groups,
		plan_work.isolated_canonical_forms,
		structure_work.state_objects,
		plan_work.state_recipe_bytes,
		facts_work.blending_probe_bytes,
		facts_work.closure_uses,
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
		plan_work.semantic_placements,
		plan_work.artifact_placements,
		structure_work.objects,
		built.bytes.len(),
	]
}

## The showcase color stores under one authored-ID direction: the packaged
## sRGB profile, a calibrated-gray space, and the ICCBased sRGB space whose
## dense IDs swap under `Reversed`.
showcase_space_count : U64
showcase_space_count = 2

dense_space : U64, [Forward, Reversed] -> U64
dense_space = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_space_count - 1 - logical
}

showcase_form_count : U64
showcase_form_count = 3

dense_form : U64, [Forward, Reversed] -> U64
dense_form = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_form_count - 1 - logical
}

showcase_stores : [Forward, Reversed] -> { colors : Color.Store, images : Image.SourceStore }
showcase_stores = |direction| {
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
	{
		colors: { profiles: [KernelSrgbProfile.profile(0, 0)], spaces: $spaces, tags: KernelSrgbProfile.tags },
		images: {
			resources: [
				{
					id: Image.Id.from_index(0),
					payload: PackedPixels({
						alpha: PackedAlpha({ bytes: alpha_pixels, row_stride: 2 }),
						color_space: Color.SpaceId.from_index(dense_space(0, direction)),
						dimensions: { height: 2, width: 2 },
						format: Gray8,
						pixels: gray_pixels,
						row_stride: 2,
					}),
				},
			],
		},
	}
}

showcase_color_limits : KernelColor.Limits
showcase_color_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count,
	max_profiles: 1,
	max_spaces: 2,
	max_tags: KernelSrgbProfile.tag_count,
})

showcase_image_limits : KernelImage.Limits
showcase_image_limits = KernelImage.Limits.make({
	max_decoded_bytes: 8,
	max_encoded_bytes: 0,
	max_height: 2,
	max_markers: 0,
	max_resources: 1,
	max_width: 2,
})

## One page exercising every supported opacity shape. Logical forms:
## 0 = a plain path form placed under opacity; 1 = a form with internal
## opacity placed at top level; 2 = an isolated transparency group with
## internal opacity and an overlapping opaque path, placed under opacity.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	stores = showcase_stores(direction)
	space = |logical| dense_space(logical, direction)
	form = |logical| Scene.FormId.from_index(dense_form(logical, direction))
	page_commands = [
		opacity(32768, 1, 1),
		DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(rgb_value(65535, 0, 0, space(1))) }),
		opacity(49152, 3, 2),
		DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(16448, space(0))) }),
		opacity(43690, 5, 1),
		DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(49344, space(0))) }),
		opacity(65535, 7, 1),
		opacity(32768, 8, 1),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(40000, 80000, 20000, 10000) }),
		opacity(0, 10, 1),
		DrawPath({ path: Scene.PathId.from_index(3), style: fill_with(rgb_value(0, 0, 65535, space(1))) }),
		opacity(32768, 12, 1),
		PlaceForm({ form: form(0), transform: translate(10000, 40000) }),
		PlaceForm({ form: form(1), transform: translate(40000, 40000) }),
		opacity(16384, 15, 1),
		PlaceForm({ form: form(2), transform: translate(70000, 40000) }),
	]

	## The form arena is authored in dense-ID order so once-each ownership
	## holds under either direction; commands per logical form are fixed.
	logical_form_commands = [
		[DrawPath({ path: Scene.PathId.from_index(4), style: fill_with(rgb_value(0, 49344, 0, space(1))) })],
		[
			opacity(16384, 0, 1),
			DrawPath({ path: Scene.PathId.from_index(4), style: fill_with(gray_value(32896, space(0))) }),
		],
		[
			opacity(32768, 0, 1),
			DrawPath({ path: Scene.PathId.from_index(5), style: fill_with(rgb_value(65535, 32896, 0, space(1))) }),
			DrawPath({ path: Scene.PathId.from_index(4), style: fill_with(rgb_value(0, 0, 65535, space(1))) }),
		],
	]
	logical_boxes = [rect(0, 0, 20000, 10000), rect(0, 0, 20000, 10000), rect(0, 0, 20000, 12000)]
	logical_groups = [NoGroup, NoGroup, IsolatedGroup]
	var $form_arena = []
	var $forms = List.with_capacity(showcase_form_count)
	var $dense_index = 0
	while $dense_index < showcase_form_count {
		logical = match direction {
			Forward => $dense_index
			Reversed => showcase_form_count - 1 - $dense_index
		}
		start = $form_arena.len()
		commands = list_at(logical_form_commands, logical)
		if logical == 1 {

			## Root owns the opacity command; its child follows.
			$form_arena = $form_arena.append(opacity(16384, start + 1, 1))
			$form_arena = $form_arena.append(list_at(commands, 1))
			$forms = $forms.append({ bbox: list_at(logical_boxes, logical), commands: span(start, 1), group: list_at(logical_groups, logical), id: Scene.FormId.from_index($dense_index) })
		} else if logical == 2 {

			## Root owns the opacity command and the overlapping opaque path;
			## the opacity child follows both top-level commands.
			$form_arena = $form_arena.append(opacity(32768, start + 2, 1))
			$form_arena = $form_arena.append(list_at(commands, 2))
			$form_arena = $form_arena.append(list_at(commands, 1))
			$forms = $forms.append({ bbox: list_at(logical_boxes, logical), commands: span(start, 2), group: list_at(logical_groups, logical), id: Scene.FormId.from_index($dense_index) })
		} else {
			$form_arena = $form_arena.append(list_at(commands, 0))
			$forms = $forms.append({ bbox: list_at(logical_boxes, logical), commands: span(start, 1), group: list_at(logical_groups, logical), id: Scene.FormId.from_index($dense_index) })
		}
		$dense_index = $dense_index + 1
	}

	scene = {
		commands: page_commands,
		dash_lengths: [],
		groups: [
			{ commands: span(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: span(2, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
			{ commands: span(6, 1), id: Scene.GroupId.from_index(2), owner: PageArtifact(Decoration) },
			{ commands: span(9, 1), id: Scene.GroupId.from_index(3), owner: Fragment(Semantics.FragmentId.from_index(1)) },
			{ commands: span(11, 1), id: Scene.GroupId.from_index(4), owner: Fragment(Semantics.FragmentId.from_index(2)) },
			{ commands: span(13, 1), id: Scene.GroupId.from_index(5), owner: PageArtifact(Watermark) },
			{ commands: span(14, 1), id: Scene.GroupId.from_index(6), owner: Fragment(Semantics.FragmentId.from_index(3)) },
		],
		page_groups: [
			Scene.GroupId.from_index(0),
			Scene.GroupId.from_index(1),
			Scene.GroupId.from_index(2),
			Scene.GroupId.from_index(3),
			Scene.GroupId.from_index(4),
			Scene.GroupId.from_index(5),
			Scene.GroupId.from_index(6),
		],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: span(0, 7),
				rotation: Rotate0,
			},
		],
		path_segments: [
			Rectangle(rect(10000, 84000, 20000, 8000)),
			Rectangle(rect(10000, 62000, 24000, 10000)),
			Rectangle(rect(22000, 58000, 24000, 10000)),
			Rectangle(rect(70000, 80000, 15000, 10000)),
			Rectangle(rect(0, 0, 20000, 10000)),
			Rectangle(rect(6000, 2000, 14000, 10000)),
		],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: span(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: span(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: span(2, 1) },
			{ id: Scene.PathId.from_index(3), segments: span(3, 1) },
			{ id: Scene.PathId.from_index(4), segments: span(4, 1) },
			{ id: Scene.PathId.from_index(5), segments: span(5, 1) },
		],
	}
	{
		color_limits: showcase_color_limits,
		colors: stores.colors,
		form_store: { commands: $form_arena, forms: $forms },
		image_limits: showcase_image_limits,
		images: stores.images,
		scene,
		semantics: build_semantics(4, [1, 0, 2, 3]),
	}
}

## Scaled color stores: content paints only calibrated gray, while the
## packaged ICCBased sRGB space exists solely as the transparency blending
## space, reachable through the page group's closure-only use.
scaled_colors : Color.Store
scaled_colors = {
	profiles: [KernelSrgbProfile.profile(0, 0)],
	spaces: [
		{ id: Color.SpaceId.from_index(0), space: cal_gray },
		{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(0)) },
	],
	tags: KernelSrgbProfile.tags,
}

scaled_color_limits : KernelColor.Limits
scaled_color_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count,
	max_profiles: 1,
	max_spaces: 2,
	max_tags: KernelSrgbProfile.tag_count,
})

no_image_limits : KernelImage.Limits
no_image_limits = KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 })

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
		path_segments: [Rectangle(rect(0, 95000, 4000, 4000)), Rectangle(rect(1000, 1000, 3000, 3000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: span(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: span(1, 1) },
		],
	}
}

scaled_scenario : Scene.Store, Scene.FormStore -> Scenario
scaled_scenario = |scene, form_store| {
	{
		color_limits: scaled_color_limits,
		colors: scaled_colors,
		form_store,
		image_limits: no_image_limits,
		images: { resources: [] },
		scene,
		semantics: build_semantics(1, [0]),
	}
}

## N opacity groups over one shared constant (`Shared`) or N distinct
## constants (`Distinct`): the anchor path, then N top-level opacity
## commands whose child paths follow the top-level run.
group_grid : U64, [Distinct, Shared] -> Scenario
group_grid = |scale, variant| {
	var $commands = [anchor_command]
	var $group = 0
	while $group < scale {
		alpha = match variant {
			Shared => 32768
			Distinct => (100 + $group * 61).to_u16_wrap()
		}
		$commands = $commands.append(opacity(alpha, 1 + scale + $group, 1))
		$group = $group + 1
	}
	$group = 0
	while $group < scale {
		$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }))
		$group = $group + 1
	}
	scaled_scenario(scaled_scene($commands, scale), Scene.no_forms)
}

## One N-deep nested opacity chain: each level multiplies by 65534/65535, so
## every level's effective product is distinct while the chain stays inside
## the declared opacity-depth budget.
nest_chain : U64 -> Scenario
nest_chain = |depth| {
	var $commands = [anchor_command]
	var $level = 0
	while $level < depth {
		$commands = $commands.append(opacity(65534, 2 + $level, 1))
		$level = $level + 1
	}
	$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(4112, 0)) }))
	scaled_scenario(scaled_scene($commands, 1), Scene.no_forms)
}

## N distinct forms (distinct bounding boxes) each carrying one opacity
## group over one shared constant, each placed once as an artifact.
form_grid : U64 -> Scenario
form_grid = |scale| {
	var $commands = [anchor_command]
	var $form_arena = []
	var $forms = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		column = (U64.mod_by($index, 10) * 10000).to_i64_wrap()
		row = (U64.mod_by(U64.div_by($index, 10), 9) * 10000).to_i64_wrap()
		$commands = $commands.append(PlaceForm({ form: Scene.FormId.from_index($index), transform: translate(column, row) }))
		start = $form_arena.len()
		$form_arena = $form_arena.append(opacity(32768, start + 1, 1))
		$form_arena = $form_arena.append(DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }))
		$forms = $forms.append({
			bbox: rect(0, 0, (4000 + $index.to_i64_wrap()), 4000),
			commands: span(start, 1),
			group: NoGroup,
			id: Scene.FormId.from_index($index),
		})
		$index = $index + 1
	}
	scaled_scenario(scaled_scene($commands, scale), { commands: $form_arena, forms: $forms })
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4TransparencyEvidence.EvidenceError)
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
	} else if mode == "share" {
		if scale < 1 or scale > 1000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(group_grid(scale, Shared)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_ext_g_states != 1 or work.deduplicated_opacity_groups != scale - 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "states" {
		if scale < 1 or scale > 1000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(group_grid(scale, Distinct)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_ext_g_states != scale or work.deduplicated_opacity_groups != 0 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "nest" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(nest_chain(scale)) ? |_| EvidenceFailure
		facts_work = KernelForm.Facts.work(built.facts)
		if facts_work.max_opacity_depth != scale or facts_work.distinct_opacity_values != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "forms" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(form_grid(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_forms != scale or work.canonical_ext_g_states != 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The showcase must produce exactly the deduplicated canonical facts: the
## direct 0.5, the exact nested 0.75 x 2/3 product, the image group, the
## placement group, and both in-form 0.5 groups collapse to one canonical
## state; the opaque identity emits nothing; zero and the two remaining
## constants stay distinct; the isolated group survives as one canonical
## form; and every transparency fact reaches the page group.
check_showcase_sharing : Built -> Try({}, Gate4TransparencyEvidence.EvidenceError)
check_showcase_sharing = |built| {
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	if facts_work.opacity_commands != 10 or facts_work.opacity_groups != 9 or facts_work.opaque_normalized != 1 {
		return Err(SharingDiverged)
	}
	if plan_work.canonical_ext_g_states != 4 or plan_work.deduplicated_opacity_groups != 5 {
		return Err(SharingDiverged)
	}
	if facts_work.max_opacity_depth != 2 or facts_work.transparency_pages != 1 {
		return Err(SharingDiverged)
	}
	if plan_work.isolated_canonical_forms != 1 or plan_work.canonical_forms != 3 {
		return Err(SharingDiverged)
	}
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	if structure_work.transparency_page_groups != 1 or structure_work.state_objects != 4 {
		return Err(SharingDiverged)
	}
	Ok({})
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4TransparencyEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	rejections = check_negatives(context)?
	carrier = run_pipeline(group_grid(context, Shared)) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [rejections, 0, carrier.bytes.len()] })
}

expect_facts_rejection : U64, Scenario, KernelForm.Limits, (KernelForm.Error -> Bool) -> Try({}, Gate4TransparencyEvidence.EvidenceError)
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

expect_scene_rejection : U64, Scenario, (KernelScene.Error -> Bool) -> Try({}, Gate4TransparencyEvidence.EvidenceError)
expect_scene_rejection = |ordinal, input, matches| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: input.colors.spaces.len(),
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	match KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_plan_rejection : U64, Scenario, KernelForm.Limits, (BuildFailure -> Bool) -> Try({}, Gate4TransparencyEvidence.EvidenceError)
expect_plan_rejection = |ordinal, input, limits, matches| {
	match build_plan_with_limits(input, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

build_plan_with_limits : Scenario, KernelForm.Limits -> Try(KernelForm.Plan, BuildFailure)
build_plan_with_limits = |input, limits| {
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
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	plan = KernelForm.Plan.build(form_scene, facts, { colors, fonts: [], images }, NoText, tagged, limits) ? FormPlanFailure
	Ok(plan)
}

## The calibrated-only twin of the scaled stores: identical except that no
## authored space declares the packaged sRGB profile.
calibrated_only : Scenario -> Scenario
calibrated_only = |base| {
	{
		..base,
		color_limits: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
		colors: { profiles: [], spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }], tags: [] },
	}
}

## A minimal scene placing one form under page opacity, with the form's
## content supplied by the caller.
ambient_form_scenario : List(Scene.Command), Semantics.Range, Scene.FormGroup -> Scenario
ambient_form_scenario = |form_commands, root, group| {
	commands = [
		anchor_command,
		opacity(32768, 2, 1),
		PlaceForm({ form: Scene.FormId.from_index(0), transform: identity_transform }),
	]
	scene = {
		..scaled_scene(commands, 2),
		groups: [
			anchor_group,
			{ commands: span(1, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Watermark) },
		],
	}
	scaled = scaled_scenario(scene, { commands: form_commands, forms: [{ bbox: rect(0, 0, 4000, 4000), commands: root, group, id: Scene.FormId.from_index(0) }] })
	scaled
}

## Each negative twin below changes exactly one fact of a valid scene and
## must fail with its own structured diagnostic before any plan or byte
## escapes.
check_negatives : U64 -> Try(U64, Gate4TransparencyEvidence.EvidenceError)
check_negatives = |context| {

	## The runtime context threads through the authored scenes so no
	## rejection can be resolved at compile time.
	base = group_grid(context, Shared)

	## 1: opacity stays rejected under the Gate 2 resource constructor.
	gate2_rejected = match KernelScene.Plan.build(base.scene, KernelScene.Resources.make({ color_spaces: 2, images: 0 }), scene_limits) {
		Err(UnsupportedCommand({ command })) => command == context
		_ => Bool.False
	}
	if !gate2_rejected {
		return Err(MissingRejection(1))
	}

	## 2: per-run text paint opacity stays a separate rejected capability.
	text_paint_rejected = match KernelScene.Plan.build(
		{
			..base.scene,
			commands: [
				DrawText({
					paint: { fill: gray_value(0, 0), mode: Fill, opacity: 65534, stroke: NoStroke },
					run: Text.RunId.from_index(context - 1),
				}),
				opacity(32768, 2, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			],
		},
		KernelScene.Resources.with_forms({ color_spaces: 2, forms: 0, images: 0, text_runs: 1 }),
		scene_limits,
	) {
		Err(TextPaintInvalid({ command: 0, reason: OpacityNotOpaque })) => Bool.True
		_ => Bool.False
	}
	if !text_paint_rejected {
		return Err(MissingRejection(2))
	}

	## 3: an empty opacity group owns no commands.
	expect_scene_rejection(
		3,
		{
			..base,
			scene: {
				..base.scene,
				commands: [anchor_command, opacity(32768, 0, 0), DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) })],
			},
		},
		|error| match error {
			EmptyCommandRange({ group: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 4: a transparency page without the packaged sRGB blending space.
	expect_facts_rejection(
		4,
		calibrated_only(base),
		form_limits,
		|error| match error {
			MissingBlendingSpace({ page: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 5: an isolated-group form alone makes its page a transparency page,
	## so it needs the blending space even with fully opaque content.
	plain_isolated = ambient_form_scenario(
		[DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) })],
		span(0, 1),
		IsolatedGroup,
	)
	plain_scene = {
		..plain_isolated.scene,
		commands: [
			anchor_command,
			PlaceForm({ form: Scene.FormId.from_index(0), transform: identity_transform }),
		],
	}
	expect_facts_rejection(
		5,
		calibrated_only({ ..plain_isolated, scene: plain_scene }),
		form_limits,
		|error| match error {
			MissingBlendingSpace({ page: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: a non-group form with its own opacity placed under page opacity.
	expect_facts_rejection(
		6,
		ambient_form_scenario(
			[
				opacity(16384, 1, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			],
			span(0, 1),
			NoGroup,
		),
		form_limits,
		|error| match error {
			FormOpacityInAmbient({ form: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 7: the same conflict through nesting: an opacity-bearing child form
	## placed by a plain parent that executes under page opacity.
	nested_parent = ambient_form_scenario(
		[PlaceForm({ form: Scene.FormId.from_index(1), transform: identity_transform })],
		span(0, 1),
		NoGroup,
	)
	nested_scenario = {
		..nested_parent,
		form_store: {
			commands: [
				PlaceForm({ form: Scene.FormId.from_index(1), transform: identity_transform }),
				opacity(16384, 2, 1),
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) }),
			],
			forms: [
				{ bbox: rect(0, 0, 4000, 4000), commands: span(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) },
				{ bbox: rect(0, 0, 4000, 4000), commands: span(1, 1), group: NoGroup, id: Scene.FormId.from_index(1) },
			],
		},
	}
	expect_facts_rejection(
		7,
		nested_scenario,
		form_limits,
		|error| match error {
			FormOpacityInAmbient({ form: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 8: the per-stream opacity nesting budget.
	expect_facts_rejection(
		8,
		nest_chain(3),
		KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 4, max_opacity_depth: 2, max_recipe_bytes: 4194304 }),
		|error| match error {
			OpacityDepthExceeded({ attempted: 3, limit: 2 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 9: an opacity-bearing form recipe still consumes the recipe budget.
	expect_plan_rejection(
		9,
		form_grid(1),
		KernelForm.Limits.make({ graph: graph_limits, max_mask_depth: 4, max_opacity_depth: 64, max_recipe_bytes: 8 }),
		|error| match error {
			FormPlanFailure(RecipeByteLimitExceeded({ attempted: _, limit: 8 })) => Bool.True
			_ => Bool.False
		},
	)?

	## 10: derived graphics-state nodes consume the graph resource budget.
	expect_facts_rejection(
		10,
		base,
		KernelForm.Limits.make({
			graph: { ..graph_limits, max_resources: 3 },
			max_mask_depth: 4,
			max_opacity_depth: 64,
			max_recipe_bytes: 4194304,
		}),
		|error| match error {
			Graph(ResourceLimitExceeded({ attempted: 4, limit: 3 })) => Bool.True
			_ => Bool.False
		},
	)?

	## 11: an authored isolated-group form no page places is unreachable.
	unplaced = {
		..base,
		form_store: {
			commands: [DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(gray_value(24672, 0)) })],
			forms: [{ bbox: rect(0, 0, 4000, 4000), commands: span(0, 1), group: IsolatedGroup, id: Scene.FormId.from_index(0) }],
		},
	}
	expect_facts_rejection(
		11,
		unplaced,
		form_limits,
		|error| match error {
			Graph(UnreachableResource(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 12: the blending-space closure use consumes the shared root-use
	## budget transactionally.
	expect_facts_rejection(
		12,
		base,
		KernelForm.Limits.make({
			graph: { ..graph_limits, max_root_uses: 2 },
			max_mask_depth: 4,
			max_opacity_depth: 64,
			max_recipe_bytes: 4194304,
		}),
		|error| match error {
			Graph(RootUseLimitExceeded({ attempted: 3, limit: 2 })) => Bool.True
			_ => Bool.False
		},
	)?

	Ok(context * 12)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 transparency evidence index escaped"
	}
}

## The showcase collapses six non-opaque groups over 0.5-equivalent products
## into one canonical state, keeps four distinct states, normalizes the
## opaque identity away, and emits identical bytes for both authored orders.
expect {
	result = Gate4TransparencyEvidence.scenario("showcase", 0)?
	result.work.get(0) == Ok(10) and result.work.get(1) == Ok(9) and result.work.get(2) == Ok(1) and result.work.get(4) == Ok(4) and result.work.get(5) == Ok(5) and result.work.get(8) == Ok(1) and result.work.get(9) == Ok(1)
}

## Shared constants collapse to one canonical ExtGState.
expect {
	result = Gate4TransparencyEvidence.scenario("share", 5)?
	result.work.get(1) == Ok(5) and result.work.get(4) == Ok(1) and result.work.get(5) == Ok(4) and result.work.get(10) == Ok(1)
}

## Distinct constants stay distinct canonical states and objects.
expect {
	result = Gate4TransparencyEvidence.scenario("states", 5)?
	result.work.get(4) == Ok(5) and result.work.get(5) == Ok(0) and result.work.get(10) == Ok(5)
}

## A nested chain records its depth and its distinct effective products.
expect {
	result = Gate4TransparencyEvidence.scenario("nest", 4)?
	result.work.get(6) == Ok(4) and result.work.get(3) == Ok(4) and result.work.get(4) == Ok(4)
}

## Per-form opacity over one shared constant keeps one canonical state while
## forms and their state edges scale.
expect {
	result = Gate4TransparencyEvidence.scenario("forms", 3)?
	result.work.get(4) == Ok(1) and result.work.get(25) == Ok(3) and result.work.get(14) == Ok(3)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4TransparencyEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(12) and result.work.get(1) == Ok(0)
}
