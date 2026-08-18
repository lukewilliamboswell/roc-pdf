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

## Gate 4 shading and tiling-pattern evidence.
##
## Every scenario authors a validated paint-aware scene, runs the whole
## canonical pipeline (paint validation, the derived function layout, the two
## resource-graph runs with shading/function/pattern nodes, canonical paint
## identity, content lowering with `sh` paints and `/Pattern` fills, object
## planning, emission, sealing), and emits real PDF bytes plus the
## deterministic work vector.
##
## - `showcase`  : one page proving two-stop, multi-stop, radial, calibrated
##                 gray, deduplicating twins, a one-fact-distinct shading,
##                 opacity over a shading, pattern fills on the page and
##                 through a transformed form, a pattern cell using a
##                 shading, and cross-shading segment-function sharing —
##                 with a reversed authored-ID twin that must produce
##                 identical bytes.
## - `share xN`  : N shading paints over one canonical shading.
## - `distinct xN`: N distinct two-stop shadings stay N canonical shadings.
## - `stops xN`  : one shading with N stops isolates per-stop and
##                 per-function work.
## - `pshare xN` : N pattern fills over one canonical pattern.
## - `pdistinct xN`: N distinct patterns stay N canonical patterns.
## - `pcells xN` : one pattern whose cell paints N squares isolates
##                 per-cell-command work.
## - `unique`/`shared` : the one-shot ownership path versus the same
##                 retained authored input planned twice.
Gate4ShadingPatternEvidence :: [].{
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
	## single-shading document as its snapshot payload.
	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |runtime_context| run_negatives(runtime_context)
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

point : I64, I64 -> Layout.Point
point = |x, y| { x: unit(x), y: unit(y) }

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

pattern_fill : U64 -> Scene.PathStyle
pattern_fill = |pattern| { fill: PatternFill({ pattern: Scene.PatternId.from_index(pattern), rule: Nonzero }), stroke: NoStroke }

identity : Scene.Matrix
identity = { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(0), f: unit(0) }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

scale_matrix : I64 -> Scene.Matrix
scale_matrix = |factor| { a: unit(factor), b: unit(0), c: unit(0), d: unit(factor), e: unit(0), f: unit(0) }

rgb_stop : U16, U16, U16, U16 -> Scene.GradientStop
rgb_stop = |offset, red, green, blue| { channels: Rgb({ blue, green, red }), offset }

gray_stop : U16, U16 -> Scene.GradientStop
gray_stop = |offset, level| { channels: Gray(level), offset }

axial : I64, I64, I64, I64 -> Scene.ShadingGeometry
axial = |x0, y0, x1, y1| Axial({ end: point(x1, y1), start: point(x0, y0) })

shading_record : U64, Scene.ShadingGeometry, U64, U64, U64, Bool, Bool -> Scene.Shading
shading_record = |id, geometry, space, stops_start, stops_length, extend_start, extend_end| {
	extend_end,
	extend_start,
	geometry,
	id: Scene.ShadingId.from_index(id),
	space: Color.SpaceId.from_index(space),
	stops: span(stops_start, stops_length),
}

paint_shading : U64 -> Scene.Command
paint_shading = |shading| PaintShading({ shading: Scene.ShadingId.from_index(shading) })

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
	patterns : Scene.PatternStore,
	scene : Scene.Store,
	semantics : Semantics.Store,
	shadings : Scene.ShadingStore,
}

Built := {
	bytes : List(U8),
	colors : KernelColor.Plan,
	content : KernelContent.Plan,
	facts : KernelForm.Facts,
	form_plan : KernelForm.Plan,
	images : KernelImage.Plan,
	paint_scene : KernelScene.PaintPlan,
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
	max_path_segments: 8192,
	max_paths: 4096,
})

form_scene_limits : KernelScene.FormLimits
form_scene_limits = KernelScene.FormLimits.make({ max_form_commands: 65536, max_forms: 4096 })

paint_limits : KernelScene.PaintLimits
paint_limits = KernelScene.PaintLimits.make({ max_pattern_commands: 65536, max_patterns: 1024, max_shading_stops: 256, max_shadings: 1024 })

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
	PaintSceneFailure(KernelScene.Error),
	ImageFailure(KernelImage.Error),
	ObjectFailure(KernelGate2Objects.Error),
	FormObjectFailure(KernelGate4FormObjects.Error),
	EmitFailure,
	ResourceUseFailure(KernelResourceUse.Error),
	SemanticFailure(KernelSemantics.Error),
	StructureFailure(KernelGate4FormStructure.Error),
	TaggedFailure(KernelTagged.Error),
]

paint_resources : Scenario -> KernelScene.Resources
paint_resources = |input| KernelScene.Resources.with_paints({
	color_spaces: input.colors.spaces.len(),
	forms: input.form_store.forms.len(),
	images: input.images.resources.len(),
	patterns: input.patterns.cells.len(),
	shadings: input.shadings.shadings.len(),
	text_runs: 0,
})

run_pipeline : Scenario -> Try(Built, BuildFailure)
run_pipeline = |input| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	paint_scene = KernelScene.PaintPlan.build(input.scene, input.form_store, input.shadings, input.patterns, paint_resources(input), scene_limits, form_scene_limits, paint_limits) ? PaintSceneFailure
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? ColorFailure
	images = KernelImage.Plan.build(input.images, colors, input.image_limits) ? ImageFailure
	facts = KernelForm.Facts.build_with_paints(paint_scene, { colors, font_count: 0, images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(KernelScene.PaintPlan.forms(paint_scene))) ? TaggedFailure
	form_plan = KernelForm.Plan.build_with_paints(paint_scene, facts, { colors, fonts: [], images }, NoText, tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, paint_context(form_plan, input.form_store, input.patterns), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_paints(paint_scene, colors, images, KernelForm.Facts.blending(facts)) ? ResourceUseFailure
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
	objects = KernelGate4FormObjects.Plan.build_with_paints(
		base,
		KernelForm.Plan.canonical_form_count(form_plan),
		KernelForm.Plan.canonical_state_count(form_plan),
		{
			functions: KernelForm.Plan.canonical_function_count(form_plan),
			patterns: KernelForm.Plan.canonical_pattern_count(form_plan),
			shadings: KernelForm.Plan.canonical_shading_count(form_plan),
		},
		0,
		8192,
	) ? FormObjectFailure
	structure = KernelGate4FormStructure.Plan.build_with_paints(tagged, colors, images, content, form_plan, objects, NoTextObjects, input.shadings, structure_limits) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, colors, content, facts, form_plan, images, paint_scene, structure, tagged })
}

paint_context : KernelForm.Plan, Scene.FormStore, Scene.PatternStore -> KernelContent.FormContext
paint_context = |form_plan, form_store, pattern_store| {
	count = KernelForm.Plan.canonical_form_count(form_plan)
	var $streams = List.with_capacity(count)
	var $ordinal = 0
	while $ordinal < count {
		$streams = $streams.append(KernelForm.Plan.canonical_form(form_plan, $ordinal).commands)
		$ordinal = $ordinal + 1
	}
	pattern_count = KernelForm.Plan.canonical_pattern_count(form_plan)
	var $pattern_streams = List.with_capacity(pattern_count)
	var $pattern_ordinal = 0
	while $pattern_ordinal < pattern_count {
		$pattern_streams = $pattern_streams.append(KernelForm.Plan.canonical_pattern(form_plan, $pattern_ordinal).commands)
		$pattern_ordinal = $pattern_ordinal + 1
	}
	{
		arena: form_store.commands,
		color_names: KernelForm.Plan.color_names(form_plan),
		form_names: KernelForm.Plan.form_names(form_plan),
		form_states: KernelForm.Plan.form_command_states(form_plan),
		image_names: KernelForm.Plan.image_names(form_plan),
		page_states: KernelForm.Plan.page_command_states(form_plan),
		pattern_arena: pattern_store.commands,
		pattern_names: KernelForm.Plan.pattern_names(form_plan),
		pattern_streams: $pattern_streams,
		shading_names: KernelForm.Plan.shading_names(form_plan),
		streams: $streams,
	}
}

work_vector : Built -> List(U64)
work_vector = |built| {
	paint_work = KernelScene.PaintPlan.work(built.paint_scene)
	scene_work = KernelScene.Plan.work(KernelScene.FormPlan.page(KernelScene.PaintPlan.forms(built.paint_scene)))
	form_scene_work = KernelScene.FormPlan.work(KernelScene.PaintPlan.forms(built.paint_scene))
	facts_work = KernelForm.Facts.work(built.facts)
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	content_work = KernelContent.Plan.work(built.content)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		paint_work.shading_visits,
		paint_work.shading_stop_visits,
		scene_work.shading_paints + form_scene_work.form_shading_paints + paint_work.cell_shading_paints,
		scene_work.pattern_fills + form_scene_work.form_pattern_fills,
		paint_work.cell_visits,
		paint_work.cell_command_visits,
		facts_work.derived_functions,
		facts_work.pattern_cell_use_visits,
		facts_work.pattern_sweep_visits,
		plan_work.authored_shadings,
		plan_work.canonical_shadings,
		plan_work.deduplicated_shadings,
		plan_work.authored_functions,
		plan_work.canonical_functions,
		plan_work.deduplicated_functions,
		plan_work.authored_patterns,
		plan_work.canonical_patterns,
		plan_work.deduplicated_patterns,
		plan_work.shading_recipe_bytes,
		plan_work.function_recipe_bytes,
		plan_work.pattern_recipe_bytes,
		plan_work.dictionary_entries,
		plan_work.pattern_dictionary_entries,
		facts_work.direct_edges,
		facts_work.use_command_visits,
		graph_work.hashes,
		graph_work.bytes_hashed,
		graph_work.retained_payload_bytes,
		content_work.shading_paints,
		content_work.pattern_fills,
		content_work.pattern_streams,
		content_work.pattern_stream_bytes,
		structure_work.shading_objects,
		structure_work.function_objects,
		structure_work.pattern_objects,
		structure_work.objects,
		built.bytes.len(),
	]
}

showcase_space_count : U64
showcase_space_count = 2

showcase_shading_count : U64
showcase_shading_count = 7

showcase_pattern_count : U64
showcase_pattern_count = 3

## Logical shading facts: geometry, space, and stops, written into the store
## in dense-ID order for either authoring direction.
showcase_stops : U64 -> List(Scene.GradientStop)
showcase_stops = |logical| {
	if logical == 0 or logical == 4 {

		## The canonical two-stop red-to-blue axis and its authored twin.
		[rgb_stop(0, 65535, 0, 0), rgb_stop(65535, 0, 0, 65535)]
	} else if logical == 1 {

		## Asymmetric multi-stop: red, yellow at 1/4, green at 3/4, blue.
		[rgb_stop(0, 65535, 0, 0), rgb_stop(16384, 65535, 65535, 0), rgb_stop(49152, 0, 65535, 0), rgb_stop(65535, 0, 0, 65535)]
	} else if logical == 2 {

		## The radial blue-to-white cone.
		[rgb_stop(0, 0, 0, 65535), rgb_stop(65535, 65535, 65535, 65535)]
	} else if logical == 3 {

		## Calibrated gray black-to-white.
		[gray_stop(0, 0), gray_stop(65535, 65535)]
	} else if logical == 5 {

		## One visual fact away from logical 0: the colors swap.
		[rgb_stop(0, 0, 0, 65535), rgb_stop(65535, 65535, 0, 0)]
	} else {

		## The pattern cell's yellow-to-green ramp, whose segment function
		## must deduplicate with the multi-stop gradient's middle segment.
		[rgb_stop(0, 65535, 65535, 0), rgb_stop(65535, 0, 65535, 0)]
	}
}

showcase_geometry : U64, U64 -> { extend_end : Bool, extend_start : Bool, geometry : Scene.ShadingGeometry, space : U64 }
showcase_geometry = |logical, srgb_space| {
	if logical == 2 {
		{
			extend_end: Bool.True,
			extend_start: Bool.True,
			geometry: Radial({ end_center: point(60000, 59000), end_radius: unit(12000), start_center: point(30000, 59000), start_radius: unit(2000) }),
			space: srgb_space,
		}
	} else if logical == 3 {
		{ extend_end: Bool.False, extend_start: Bool.False, geometry: axial(10000, 0, 90000, 0), space: srgb_space + 1 - 2 * U64.mod_by(srgb_space, 2) }
	} else if logical == 6 {
		{ extend_end: Bool.False, extend_start: Bool.False, geometry: axial(5000, 0, 10000, 0), space: srgb_space }
	} else if logical == 1 {

		## The multi-stop gradient runs diagonally across its band so axis
		## direction errors are visible, and its unextended corners knock
		## out exactly.
		{ extend_end: Bool.False, extend_start: Bool.False, geometry: axial(10000, 70000, 90000, 80000), space: srgb_space }
	} else {
		{ extend_end: Bool.False, extend_start: Bool.False, geometry: axial(10000, 0, 90000, 0), space: srgb_space }
	}
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

## The pattern cell content: a solid indigo square at the cell origin and a
## small yellow-to-green gradient square at the opposite corner, so tile
## boundaries, gaps, and the in-cell shading are all visible.
showcase_cell_commands : U64, U64, U64, U64 -> List(Scene.Command)
showcase_cell_commands = |start, srgb_space, cell_shading, clip_path| [
	DrawPath({ path: Scene.PathId.from_index(clip_path + 1), style: fill_with(rgb_value(8224, 8224, 49344, srgb_space)) }),
	Clip({ children: span(start + 2, 1), path: Scene.PathId.from_index(clip_path) }),
	paint_shading(cell_shading),
]

## One page exercising every supported shading and pattern shape. Logical
## shadings: 0 = two-stop red-to-blue; 1 = asymmetric multi-stop; 2 = radial;
## 3 = calibrated gray; 4 = the authored twin of 0; 5 = distinct by one
## color fact; 6 = the pattern cell's ramp. Logical patterns: 0 = the base
## cell at identity; 1 = the same cell under a doubling matrix; 2 = the
## authored twin of 0, filled through the placed form.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	space = |logical| match direction {
		Forward => logical
		Reversed => showcase_space_count - 1 - logical
	}
	shading_of = |logical| match direction {
		Forward => logical
		Reversed => showcase_shading_count - 1 - logical
	}
	pattern_of = |logical| match direction {
		Forward => logical
		Reversed => showcase_pattern_count - 1 - logical
	}

	## The shading store in dense-ID order; only dense IDs permute.
	var $stops = []
	var $shadings = List.with_capacity(showcase_shading_count)
	var $dense = 0
	while $dense < showcase_shading_count {
		logical = match direction {
			Forward => $dense
			Reversed => showcase_shading_count - 1 - $dense
		}
		stop_list = showcase_stops(logical)
		geometry = showcase_geometry(logical, space(1))
		start = $stops.len()
		$stops = $stops.concat(stop_list)
		$shadings = $shadings.append({
			extend_end: geometry.extend_end,
			extend_start: geometry.extend_start,
			geometry: geometry.geometry,
			id: Scene.ShadingId.from_index($dense),
			space: Color.SpaceId.from_index(geometry.space),
			stops: span(start, stop_list.len()),
		})
		$dense = $dense + 1
	}

	## The pattern store in dense-ID order: cells 0 and 2 are byte-identical
	## twins at the identity matrix, cell 1 differs only by its matrix.
	var $cells = List.with_capacity(showcase_pattern_count)
	var $cell_arena = []
	var $cell_dense = 0
	while $cell_dense < showcase_pattern_count {
		logical = match direction {
			Forward => $cell_dense
			Reversed => showcase_pattern_count - 1 - $cell_dense
		}
		start = $cell_arena.len()
		$cell_arena = $cell_arena.concat(showcase_cell_commands(start, space(1), shading_of(6), 8))
		matrix = if logical == 1 scale_matrix(2000) else identity
		$cells = $cells.append({
			bbox: rect(0, 0, 10000, 10000),
			commands: span(start, 2),
			id: Scene.PatternId.from_index($cell_dense),
			matrix,
			x_step: unit(10000),
			y_step: unit(10000),
		})
		$cell_dense = $cell_dense + 1
	}

	## One placed form filling with the twin pattern and painting the shared
	## two-stop shading through its own clip.
	form_commands = [
		DrawPath({ path: Scene.PathId.from_index(10), style: pattern_fill(pattern_of(2)) }),
		Clip({ children: span(2, 1), path: Scene.PathId.from_index(11) }),
		paint_shading(shading_of(0)),
	]
	form_store = {
		commands: form_commands,
		forms: [{ bbox: rect(0, 0, 80000, 6000), commands: span(0, 2), group: NoGroup, id: Scene.FormId.from_index(0) }],
	}

	page_commands = [
		Clip({ children: span(1, 1), path: Scene.PathId.from_index(0) }),
		paint_shading(shading_of(0)),
		Clip({ children: span(3, 1), path: Scene.PathId.from_index(1) }),
		paint_shading(shading_of(1)),
		Clip({ children: span(5, 1), path: Scene.PathId.from_index(2) }),
		paint_shading(shading_of(2)),
		Clip({ children: span(7, 1), path: Scene.PathId.from_index(3) }),
		paint_shading(shading_of(3)),
		Clip({ children: span(9, 1), path: Scene.PathId.from_index(4) }),
		paint_shading(shading_of(4)),
		Opacity({ children: span(11, 1), opacity: 32768 }),
		Clip({ children: span(12, 1), path: Scene.PathId.from_index(5) }),
		paint_shading(shading_of(5)),
		DrawPath({ path: Scene.PathId.from_index(6), style: pattern_fill(pattern_of(0)) }),
		DrawPath({ path: Scene.PathId.from_index(7), style: pattern_fill(pattern_of(1)) }),
		PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(10000, 0) }),
	]

	scene = {
		commands: page_commands,
		dash_lengths: [],
		groups: [
			{ commands: span(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: span(2, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
			{ commands: span(4, 1), id: Scene.GroupId.from_index(2), owner: Fragment(Semantics.FragmentId.from_index(1)) },
			{ commands: span(6, 1), id: Scene.GroupId.from_index(3), owner: Fragment(Semantics.FragmentId.from_index(2)) },
			{ commands: span(8, 1), id: Scene.GroupId.from_index(4), owner: PageArtifact(Watermark) },
			{ commands: span(10, 1), id: Scene.GroupId.from_index(5), owner: Fragment(Semantics.FragmentId.from_index(3)) },
			{ commands: span(13, 1), id: Scene.GroupId.from_index(6), owner: Fragment(Semantics.FragmentId.from_index(4)) },
			{ commands: span(14, 1), id: Scene.GroupId.from_index(7), owner: PageArtifact(Decoration) },
			{ commands: span(15, 1), id: Scene.GroupId.from_index(8), owner: Fragment(Semantics.FragmentId.from_index(5)) },
		],
		page_groups: [
			Scene.GroupId.from_index(0),
			Scene.GroupId.from_index(1),
			Scene.GroupId.from_index(2),
			Scene.GroupId.from_index(3),
			Scene.GroupId.from_index(4),
			Scene.GroupId.from_index(5),
			Scene.GroupId.from_index(6),
			Scene.GroupId.from_index(7),
			Scene.GroupId.from_index(8),
		],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: span(0, 9),
				rotation: Rotate0,
			},
		],
		path_segments: [
			Rectangle(rect(10000, 84000, 80000, 8000)),
			Rectangle(rect(10000, 70000, 80000, 10000)),
			Rectangle(rect(10000, 52000, 80000, 14000)),
			Rectangle(rect(10000, 40000, 80000, 8000)),
			Rectangle(rect(10000, 30000, 80000, 6000)),
			Rectangle(rect(10000, 22000, 80000, 6000)),
			Rectangle(rect(10000, 6000, 30000, 12000)),
			Rectangle(rect(50000, 6000, 30000, 12000)),
			Rectangle(rect(5000, 5000, 5000, 5000)),
			Rectangle(rect(0, 0, 5000, 5000)),
			Rectangle(rect(0, 0, 40000, 6000)),
			Rectangle(rect(40000, 0, 40000, 6000)),
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
			{ id: Scene.PathId.from_index(8), segments: span(8, 1) },
			{ id: Scene.PathId.from_index(9), segments: span(9, 1) },
			{ id: Scene.PathId.from_index(10), segments: span(10, 1) },
			{ id: Scene.PathId.from_index(11), segments: span(11, 1) },
		],
	}
	{
		color_limits: showcase_color_limits,
		colors: showcase_colors(direction),
		form_store,
		image_limits: no_image_limits,
		images: { resources: [] },
		patterns: { cells: $cells, commands: $cell_arena },
		scene,
		semantics: build_semantics(6, [1, 0, 2, 3, 5, 4]),
		shadings: { shadings: $shadings, stops: $stops },
	}
}

scaled_colors : Color.Store
scaled_colors = showcase_colors(Forward)

## Pattern-only scaled scenarios contain no gradient and no transparency, so
## they declare only the calibrated-gray space the cells and anchor paint
## with; an undeclared-but-unused sRGB space would be an unreachable
## resource.
pattern_colors : Color.Store
pattern_colors = { profiles: [], spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }], tags: [] }

pattern_color_limits : KernelColor.Limits
pattern_color_limits = KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })

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
		path_segments: [Rectangle(rect(0, 95000, 4000, 4000)), Rectangle(rect(10000, 10000, 80000, 80000)), Rectangle(rect(0, 0, 4000, 4000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: span(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: span(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: span(2, 1) },
		],
	}
}

scaled_scenario : Scene.Store, Scene.ShadingStore, Scene.PatternStore -> Scenario
scaled_scenario = |scene, shadings, patterns| {
	{
		color_limits: if patterns.cells.len() > 0 pattern_color_limits else showcase_color_limits,
		colors: if patterns.cells.len() > 0 pattern_colors else scaled_colors,
		form_store: Scene.no_forms,
		image_limits: no_image_limits,
		images: { resources: [] },
		patterns,
		scene,
		semantics: build_semantics(1, [0]),
		shadings,
	}
}

two_stop_shading : U64, U64 -> Scene.Shading
two_stop_shading = |id, stops_start| shading_record(id, axial(10000, 0, 90000, 0), 1, stops_start, 2, Bool.False, Bool.False)

## N shading paints over one two-stop shading (`Reuse`) or over N distinct
## two-stop shadings whose first stop color varies (`Distinct`).
shading_grid : U64, [Distinct, Reuse] -> Scenario
shading_grid = |scale, variant| {
	shading_count = match variant {
		Reuse => 1
		Distinct => scale
	}
	var $stops = []
	var $shadings = List.with_capacity(shading_count)
	var $shading = 0
	while $shading < shading_count {
		start = $stops.len()
		red = (255 * ($shading + 1)).to_u16_wrap()
		$stops = $stops.append(rgb_stop(0, red, 0, 0))
		$stops = $stops.append(rgb_stop(65535, 0, 0, 65535))
		$shadings = $shadings.append(two_stop_shading($shading, start))
		$shading = $shading + 1
	}
	var $commands = [anchor_command]
	var $group = 0
	while $group < scale {
		$commands = $commands.append(Clip({ children: span(1 + scale + $group, 1), path: Scene.PathId.from_index(1) }))
		$group = $group + 1
	}
	$group = 0
	while $group < scale {
		target = match variant {
			Reuse => 0
			Distinct => $group
		}
		$commands = $commands.append(paint_shading(target))
		$group = $group + 1
	}
	scaled_scenario(scaled_scene($commands, scale), { shadings: $shadings, stops: $stops }, Scene.no_patterns)
}

## One shading whose stop count scales: exact interior offsets at k/N in the
## `U16` domain, colors alternating so no adjacent pair repeats.
stop_ramp : U64 -> Scenario
stop_ramp = |stop_count| {
	var $stops = List.with_capacity(stop_count)
	var $stop = 0
	while $stop < stop_count {
		offset = if $stop == stop_count - 1 65535 else (U64.div_by($stop * 65535, stop_count - 1)).to_u16_wrap()
		level = if U64.mod_by($stop, 2) == 0 (($stop * 977).to_u16_wrap()) else (65535 - ($stop * 449).to_u16_wrap())
		$stops = $stops.append(rgb_stop(offset, level, 32768, 65535 - level))
		$stop = $stop + 1
	}
	shadings = [shading_record(0, axial(10000, 0, 90000, 0), 1, 0, stop_count, Bool.False, Bool.False)]
	commands = [
		anchor_command,
		Clip({ children: span(2, 1), path: Scene.PathId.from_index(1) }),
		paint_shading(0),
	]
	scaled_scenario(scaled_scene(commands, 1), { shadings, stops: $stops }, Scene.no_patterns)
}

scaled_cell : U64, U64, U64 -> { cell : Scene.PatternCell, commands : List(Scene.Command) }
scaled_cell = |start, id, shade| {
	{
		cell: {
			bbox: rect(0, 0, 10000, 10000),
			commands: span(start, 1),
			id: Scene.PatternId.from_index(id),
			matrix: identity,
			x_step: unit(10000),
			y_step: unit(10000),
		},
		commands: [DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(shade.to_u64().to_u16_wrap(), 0)) })],
	}
}

## N pattern fills over one pattern (`Reuse`) or N distinct patterns whose
## cell shade varies (`Distinct`).
pattern_grid : U64, [Distinct, Reuse] -> Scenario
pattern_grid = |scale, variant| {
	pattern_count = match variant {
		Reuse => 1
		Distinct => scale
	}
	var $cells = List.with_capacity(pattern_count)
	var $cell_arena = []
	var $cell = 0
	while $cell < pattern_count {
		built = scaled_cell($cell_arena.len(), $cell, 128 * $cell + 977)
		$cell_arena = $cell_arena.concat(built.commands)
		$cells = $cells.append(built.cell)
		$cell = $cell + 1
	}
	var $commands = [anchor_command]
	var $fill = 0
	while $fill < scale {
		target = match variant {
			Reuse => 0
			Distinct => $fill
		}
		$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index(1), style: pattern_fill(target) }))
		$fill = $fill + 1
	}
	scaled_scenario(scaled_scene($commands, scale), Scene.no_shadings, { cells: $cells, commands: $cell_arena })
}

## One pattern whose cell paints N small squares: per-cell-command work.
cell_ramp : U64 -> Scenario
cell_ramp = |command_count| {
	var $cell_arena = List.with_capacity(command_count)
	var $command = 0
	while $command < command_count {
		$cell_arena = $cell_arena.append(DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value((512 * $command).to_u16_wrap(), 0)) }))
		$command = $command + 1
	}
	cells = [
		{
			bbox: rect(0, 0, 10000, 10000),
			commands: span(0, command_count),
			id: Scene.PatternId.from_index(0),
			matrix: identity,
			x_step: unit(10000),
			y_step: unit(10000),
		},
	]
	commands = [
		anchor_command,
		DrawPath({ path: Scene.PathId.from_index(1), style: pattern_fill(0) }),
	]
	scaled_scenario(scaled_scene(commands, 1), Scene.no_shadings, { cells, commands: $cell_arena })
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4ShadingPatternEvidence.EvidenceError)
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
		built = run_pipeline(shading_grid(scale, Reuse)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_shadings != 1 or work.canonical_functions != 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "distinct" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(shading_grid(scale, Distinct)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_shadings != scale or work.canonical_functions != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "stops" {
		if scale < 3 or scale > 256 {
			return Err(InvalidScale)
		}
		built = run_pipeline(stop_ramp(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_shadings != 1 or work.canonical_functions != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "pshare" {
		if scale < 1 or scale > 1000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(pattern_grid(scale, Reuse)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_patterns != 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "pdistinct" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(pattern_grid(scale, Distinct)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_patterns != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "pcells" {
		if scale < 1 or scale > 256 {
			return Err(InvalidScale)
		}
		built = run_pipeline(cell_ramp(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_patterns != 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The showcase must produce exactly the deduplicated canonical facts: the
## authored twin shading and twin pattern collapse, the swapped-color
## shading stays distinct, and the multi-stop gradient's middle segment is
## shared with the pattern cell's ramp.
check_showcase_sharing : Built -> Try({}, Gate4ShadingPatternEvidence.EvidenceError)
check_showcase_sharing = |built| {
	plan_work = KernelForm.Plan.work(built.form_plan)
	if plan_work.authored_shadings != 7 or plan_work.canonical_shadings != 6 or plan_work.deduplicated_shadings != 1 {
		return Err(SharingDiverged)
	}
	if plan_work.authored_functions != 10 or plan_work.canonical_functions != 8 or plan_work.deduplicated_functions != 2 {
		return Err(SharingDiverged)
	}
	if plan_work.authored_patterns != 3 or plan_work.canonical_patterns != 2 or plan_work.deduplicated_patterns != 1 {
		return Err(SharingDiverged)
	}
	if plan_work.canonical_forms != 1 or plan_work.canonical_ext_g_states != 1 {
		return Err(SharingDiverged)
	}
	content_work = KernelContent.Plan.work(built.content)
	if content_work.shading_paints != 9 or content_work.pattern_fills != 3 or content_work.pattern_streams != 2 {
		return Err(SharingDiverged)
	}
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	if structure_work.shading_objects != 6 or structure_work.function_objects != 8 or structure_work.pattern_objects != 2 {
		return Err(SharingDiverged)
	}
	Ok({})
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4ShadingPatternEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	rejections = check_negatives(context)?
	carrier = run_pipeline(shading_grid(context, Reuse)) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [rejections, 0, carrier.bytes.len()] })
}

expect_paint_rejection : U64, Scenario, (KernelScene.Error -> Bool) -> Try({}, Gate4ShadingPatternEvidence.EvidenceError)
expect_paint_rejection = |ordinal, input, matches| {
	match KernelScene.PaintPlan.build(input.scene, input.form_store, input.shadings, input.patterns, paint_resources(input), scene_limits, form_scene_limits, paint_limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_facts_rejection : U64, Scenario, KernelForm.Limits, (KernelForm.Error -> Bool) -> Try({}, Gate4ShadingPatternEvidence.EvidenceError)
expect_facts_rejection = |ordinal, input, limits, matches| {
	paint_scene = KernelScene.PaintPlan.build(input.scene, input.form_store, input.shadings, input.patterns, paint_resources(input), scene_limits, form_scene_limits, paint_limits) ? |_| MissingRejection(ordinal)
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? |_| MissingRejection(ordinal)
	images = KernelImage.Plan.build(input.images, colors, input.image_limits) ? |_| MissingRejection(ordinal)
	match KernelForm.Facts.build_with_paints(paint_scene, { colors, font_count: 0, images }, NoTextStore, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

## A minimal shaped-run store: enough typed evidence for use collection to
## reach the pattern-ownership rules, which reject before any recipe or
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

with_shading : Scenario, Scene.Shading -> Scenario
with_shading = |base, shading| {
	{ ..base, shadings: { shadings: [shading], stops: base.shadings.stops } }
}

## Each negative twin below changes exactly one fact of a valid scene and
## must fail with its own structured diagnostic before any plan or byte
## escapes.
check_negatives : U64 -> Try(U64, Gate4ShadingPatternEvidence.EvidenceError)
check_negatives = |context| {

	## The runtime context threads through the authored scenes so no
	## rejection can be resolved at compile time.
	base = shading_grid(context, Reuse)
	pattern_base = pattern_grid(context, Reuse)

	## 1: shading paints stay rejected under the Gate 2 resource constructor.
	gate2_rejected = match KernelScene.Plan.build(base.scene, KernelScene.Resources.make({ color_spaces: 2, images: 0 }), scene_limits) {
		Err(UnsupportedCommand({ command })) => command == 1 + context
		_ => Bool.False
	}
	if !gate2_rejected {
		return Err(MissingRejection(1))
	}

	## 2: pattern fills stay rejected under the Gate 4 form constructor.
	form_gate_rejected = match KernelScene.Plan.build(pattern_base.scene, KernelScene.Resources.with_forms({ color_spaces: 1, forms: 0, images: 0, text_runs: 0 }), scene_limits) {
		Err(UnsupportedCommand({ command })) => command == context
		_ => Bool.False
	}
	if !form_gate_rejected {
		return Err(MissingRejection(2))
	}

	## 3: a shading reference outside the declared store.
	expect_paint_rejection(
		3,
		{
			..base,
			scene: {
				..base.scene,
				commands: [
					anchor_command,
					Clip({ children: span(2, 1), path: Scene.PathId.from_index(1) }),
					paint_shading(context + 6),
				],
			},
		},
		|error| match error {
			IndexOutOfRange({ available: 1, index, kind: ShadingIndex }) => index == context + 6
			_ => Bool.False
		},
	)?

	## 4: a pattern reference outside the declared store.
	expect_paint_rejection(
		4,
		{
			..pattern_base,
			scene: {
				..pattern_base.scene,
				commands: [
					anchor_command,
					DrawPath({ path: Scene.PathId.from_index(1), style: pattern_fill(context + 4) }),
				],
			},
		},
		|error| match error {
			IndexOutOfRange({ available: 1, index, kind: PatternIndex }) => index == context + 4
			_ => Bool.False
		},
	)?

	## 5: a single-stop gradient.
	expect_paint_rejection(
		5,
		with_shading(base, shading_record(0, axial(10000, 0, 90000, 0), 1, 0, 1, Bool.False, Bool.False)),
		|error| match error {
			TooFewShadingStops({ shading: 0, stops: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: a first stop away from the domain start.
	first_off = {
		..base,
		shadings: {
			shadings: base.shadings.shadings,
			stops: [rgb_stop(1, 65535, 0, 0), rgb_stop(65535, 0, 0, 65535)],
		},
	}
	expect_paint_rejection(
		6,
		first_off,
		|error| match error {
			ShadingStopEndpointInvalid({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 7: a last stop away from the domain end.
	last_off = {
		..base,
		shadings: {
			shadings: base.shadings.shadings,
			stops: [rgb_stop(0, 65535, 0, 0), rgb_stop(65534, 0, 0, 65535)],
		},
	}
	expect_paint_rejection(
		7,
		last_off,
		|error| match error {
			ShadingStopEndpointInvalid({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 8: equal adjacent stop offsets.
	equal_stops = {
		..base,
		shadings: {
			shadings: [shading_record(0, axial(10000, 0, 90000, 0), 1, 0, 3, Bool.False, Bool.False)],
			stops: [rgb_stop(0, 65535, 0, 0), rgb_stop(0, 0, 65535, 0), rgb_stop(65535, 0, 0, 65535)],
		},
	}
	expect_paint_rejection(
		8,
		equal_stops,
		|error| match error {
			ShadingStopsNotIncreasing({ shading: 0, stop: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 9: degenerate linear geometry.
	expect_paint_rejection(
		9,
		with_shading(base, shading_record(0, axial(10000, 0, 10000, 0), 1, 0, 2, Bool.False, Bool.False)),
		|error| match error {
			DegenerateShadingGeometry({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 10: a negative radius.
	expect_paint_rejection(
		10,
		with_shading(base, shading_record(0, Radial({ end_center: point(50000, 50000), end_radius: unit(10000), start_center: point(40000, 50000), start_radius: unit(-1) }), 1, 0, 2, Bool.False, Bool.False)),
		|error| match error {
			NegativeShadingRadius({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 11: coincident radial circles.
	expect_paint_rejection(
		11,
		with_shading(base, shading_record(0, Radial({ end_center: point(40000, 50000), end_radius: unit(10000), start_center: point(40000, 50000), start_radius: unit(10000) }), 1, 0, 2, Bool.False, Bool.False)),
		|error| match error {
			DegenerateShadingGeometry({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 12: both radii zero.
	expect_paint_rejection(
		12,
		with_shading(base, shading_record(0, Radial({ end_center: point(50000, 50000), end_radius: unit(0), start_center: point(40000, 50000), start_radius: unit(0) }), 1, 0, 2, Bool.False, Bool.False)),
		|error| match error {
			DegenerateShadingGeometry({ shading: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 13: the per-shading stop budget.
	over_budget = stop_ramp(256 + context)
	stops_rejected = match KernelScene.PaintPlan.build(over_budget.scene, over_budget.form_store, over_budget.shadings, over_budget.patterns, paint_resources(over_budget), scene_limits, form_scene_limits, paint_limits) {
		Err(LimitExceeded({ attempted, dimension: ShadingStops, limit: 256 })) => attempted == 256 + context
		_ => Bool.False
	}
	if !stops_rejected {
		return Err(MissingRejection(13))
	}

	## 14: a gradient stop whose channels disagree with the declared space.
	mismatched = {
		..base,
		shadings: {
			shadings: base.shadings.shadings,
			stops: [rgb_stop(0, 65535, 0, 0), { channels: Gray(0), offset: 65535 }],
		},
	}
	mismatch_scene = KernelScene.PaintPlan.build(mismatched.scene, mismatched.form_store, mismatched.shadings, mismatched.patterns, paint_resources(mismatched), scene_limits, form_scene_limits, paint_limits) ? |_| MissingRejection(14)
	mismatch_colors = KernelColor.Plan.build(mismatched.colors, mismatched.color_limits) ? |_| MissingRejection(14)
	mismatch_images = KernelImage.Plan.build(mismatched.images, mismatch_colors, mismatched.image_limits) ? |_| MissingRejection(14)
	arity_rejected = match KernelResourceUse.TextPlan.build_with_paints(mismatch_scene, mismatch_colors, mismatch_images, NoBlending) {
		Err(ShadingStopComponentMismatch({ actual: One, expected: Three, shading: 0, stop: 1 })) => Bool.True
		_ => Bool.False
	}
	if !arity_rejected {
		return Err(MissingRejection(14))
	}

	## 15: a non-positive pattern step.
	flat_step = {
		..pattern_base,
		patterns: {
			cells: [{ ..list_at(pattern_base.patterns.cells, 0), x_step: unit(0) }],
			commands: pattern_base.patterns.commands,
		},
	}
	expect_paint_rejection(
		15,
		flat_step,
		|error| match error {
			PatternStepInvalid({ pattern: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 16: a singular pattern matrix.
	singular = {
		..pattern_base,
		patterns: {
			cells: [{ ..list_at(pattern_base.patterns.cells, 0), matrix: { a: unit(1000), b: unit(0), c: unit(0), d: unit(0), e: unit(0), f: unit(0) } }],
			commands: pattern_base.patterns.commands,
		},
	}
	expect_paint_rejection(
		16,
		singular,
		|error| match error {
			PatternMatrixSingular({ pattern: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 17: an empty pattern bounding box.
	flat_bounds = {
		..pattern_base,
		patterns: {
			cells: [{ ..list_at(pattern_base.patterns.cells, 0), bbox: rect(0, 0, 0, 10000) }],
			commands: pattern_base.patterns.commands,
		},
	}
	expect_paint_rejection(
		17,
		flat_bounds,
		|error| match error {
			NonPositiveRect({ index: 0, kind: PatternIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 18: an empty pattern cell.
	empty_cell = {
		..pattern_base,
		patterns: {
			cells: [{ ..list_at(pattern_base.patterns.cells, 0), commands: span(0, 0) }],
			commands: [],
		},
	}
	expect_paint_rejection(
		18,
		empty_cell,
		|error| match error {
			EmptyPatternCell({ pattern: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 19: semantic text inside a pattern cell.
	text_cell = {
		..pattern_base,
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [
				DrawText({
					paint: { fill: gray_value(0, 0), mode: Fill, opacity: 65535, stroke: NoStroke },
					run: Text.RunId.from_index(0),
				}),
			],
		},
	}
	text_cell_rejected = match KernelScene.PaintPlan.build(
		text_cell.scene,
		text_cell.form_store,
		text_cell.shadings,
		text_cell.patterns,
		KernelScene.Resources.with_paints({ color_spaces: 1, forms: 0, images: 0, patterns: 1, shadings: 0, text_runs: 1 }),
		scene_limits,
		form_scene_limits,
		paint_limits,
	) {
		Err(TextInPatternCell({ command: 0 })) => Bool.True
		_ => Bool.False
	}
	if !text_cell_rejected {
		return Err(MissingRejection(19))
	}

	## 20: transparency inside a pattern cell.
	opacity_cell = {
		..pattern_base,
		patterns: {
			cells: [{ ..list_at(pattern_base.patterns.cells, 0), commands: span(0, 1) }],
			commands: [
				Opacity({ children: span(1, 1), opacity: 32768 }),
				DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }),
			],
		},
	}
	expect_paint_rejection(
		20,
		opacity_cell,
		|error| match error {
			TransparencyInPatternCell({ command: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 21: a nested pattern fill inside a pattern cell.
	nested_cell = {
		..pattern_base,
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [DrawPath({ path: Scene.PathId.from_index(2), style: pattern_fill(0) })],
		},
	}
	expect_paint_rejection(
		21,
		nested_cell,
		|error| match error {
			PatternInPatternCell({ command: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 22: semantic text reachable through a form placed by a pattern cell.
	text_form_pattern = {
		..pattern_base,
		form_store: {
			commands: [
				DrawText({
					paint: { fill: gray_value(0, 0), mode: Fill, opacity: 65535, stroke: NoStroke },
					run: Text.RunId.from_index(0),
				}),
			],
			forms: [{ bbox: rect(0, 0, 10000, 10000), commands: span(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
		},
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) })],
		},
	}
	text_form_scene = KernelScene.PaintPlan.build(
		text_form_pattern.scene,
		text_form_pattern.form_store,
		text_form_pattern.shadings,
		text_form_pattern.patterns,
		KernelScene.Resources.with_paints({ color_spaces: 1, forms: 1, images: 0, patterns: 1, shadings: 0, text_runs: 1 }),
		scene_limits,
		form_scene_limits,
		paint_limits,
	) ? |_| MissingRejection(22)
	text_form_colors = KernelColor.Plan.build(text_form_pattern.colors, text_form_pattern.color_limits) ? |_| MissingRejection(22)
	text_form_images = KernelImage.Plan.build(text_form_pattern.images, text_form_colors, text_form_pattern.image_limits) ? |_| MissingRejection(22)
	text_form_rejected = match KernelForm.Facts.build_with_paints(text_form_scene, { colors: text_form_colors, font_count: 1, images: text_form_images }, WithTextStore(minimal_text_store), form_limits) {
		Err(TextInPatternForm({ form: 0 })) => Bool.True
		_ => Bool.False
	}
	if !text_form_rejected {
		return Err(MissingRejection(22))
	}

	## 23: transparency reachable through a form placed by a pattern cell.
	transparent_form_pattern = {
		..pattern_base,
		form_store: {
			commands: [
				Opacity({ children: span(1, 1), opacity: 32768 }),
				DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }),
			],
			forms: [{ bbox: rect(0, 0, 10000, 10000), commands: span(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
		},
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) })],
		},
	}
	expect_facts_rejection(
		23,
		transparent_form_pattern,
		form_limits,
		|error| match error {
			TransparencyInPattern({ form: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 24: nested pattern invocation through a placed form.
	nested_invocation = {
		..pattern_base,
		form_store: {
			commands: [DrawPath({ path: Scene.PathId.from_index(2), style: pattern_fill(1) })],
			forms: [{ bbox: rect(0, 0, 10000, 10000), commands: span(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
		},
		patterns: {
			cells: pattern_base.patterns.cells.append({
				bbox: rect(0, 0, 10000, 10000),
				commands: span(1, 1),
				id: Scene.PatternId.from_index(1),
				matrix: identity,
				x_step: unit(10000),
				y_step: unit(10000),
			}),
			commands: [
				PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) }),
				DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(gray_value(0, 0)) }),
			],
		},
		scene: {
			..pattern_base.scene,
			commands: [
				anchor_command,
				DrawPath({ path: Scene.PathId.from_index(1), style: pattern_fill(0) }),
			],
		},
	}
	expect_facts_rejection(
		24,
		nested_invocation,
		form_limits,
		|error| match error {
			NestedPatternInvocation({ form: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 25: an alpha image drawn directly inside a pattern cell.
	alpha_pattern = {
		..pattern_base,
		image_limits: KernelImage.Limits.make({ max_decoded_bytes: 4, max_encoded_bytes: 0, max_height: 1, max_markers: 0, max_resources: 1, max_width: 1 }),
		images: {
			resources: [
				{
					id: Image.Id.from_index(0),
					payload: PackedPixels({
						alpha: PackedAlpha({ bytes: [128], row_stride: 1 }),
						color_space: Color.SpaceId.from_index(0),
						dimensions: { height: 1, width: 1 },
						format: Gray8,
						pixels: [127],
						row_stride: 1,
					}),
				},
			],
		},
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 5000, 5000) })],
		},
	}
	expect_facts_rejection(
		25,
		alpha_pattern,
		form_limits,
		|error| match error {
			AlphaImageInPattern({ image: 0, pattern: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 26: a pattern-form cycle: the page fills with a pattern whose cell
	## places a form whose stream fills with the same pattern.
	cycle = {
		..pattern_base,
		form_store: {
			commands: [DrawPath({ path: Scene.PathId.from_index(2), style: pattern_fill(0) })],
			forms: [{ bbox: rect(0, 0, 10000, 10000), commands: span(0, 1), group: NoGroup, id: Scene.FormId.from_index(0) }],
		},
		patterns: {
			cells: pattern_base.patterns.cells,
			commands: [PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) })],
		},
	}
	expect_facts_rejection(
		26,
		cycle,
		form_limits,
		|error| match error {
			Graph(DependencyCycle(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 27: a declared shading no stream ever paints.
	unreachable = {
		..base,
		scene: {
			..base.scene,
			commands: [
				anchor_command,
				DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(rgb_value(65535, 0, 0, 1)) }),
			],
		},
	}
	expect_facts_rejection(
		27,
		unreachable,
		form_limits,
		|error| match error {
			Graph(UnreachableResource(_)) => Bool.True
			_ => Bool.False
		},
	)?

	Ok(context * 27)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 shading-pattern evidence index escaped"
	}
}

## The showcase deduplicates the authored twin shading and twin pattern,
## shares the yellow-to-green segment function across shadings, keeps the
## one-fact-distinct shading separate, and emits identical bytes for both
## authored orders.
expect {
	result = Gate4ShadingPatternEvidence.scenario("showcase", 0)?
	result.work.get(9) == Ok(7) and result.work.get(10) == Ok(6) and result.work.get(11) == Ok(1) and result.work.get(12) == Ok(10) and result.work.get(13) == Ok(8) and result.work.get(14) == Ok(2) and result.work.get(15) == Ok(3) and result.work.get(16) == Ok(2) and result.work.get(17) == Ok(1)
}

## Repeated shading paints share one canonical shading and function.
expect {
	result = Gate4ShadingPatternEvidence.scenario("share", 5)?
	result.work.get(2) == Ok(5) and result.work.get(10) == Ok(1) and result.work.get(13) == Ok(1) and result.work.get(32) == Ok(1)
}

## Distinct shadings stay distinct canonical shadings and objects.
expect {
	result = Gate4ShadingPatternEvidence.scenario("distinct", 5)?
	result.work.get(10) == Ok(5) and result.work.get(13) == Ok(5) and result.work.get(32) == Ok(5) and result.work.get(33) == Ok(5)
}

## One shading with N stops derives N-1 segments plus one stitch.
expect {
	result = Gate4ShadingPatternEvidence.scenario("stops", 5)?
	result.work.get(1) == Ok(5) and result.work.get(6) == Ok(5) and result.work.get(13) == Ok(5) and result.work.get(10) == Ok(1)
}

## Repeated pattern fills share one canonical pattern and stream.
expect {
	result = Gate4ShadingPatternEvidence.scenario("pshare", 5)?
	result.work.get(3) == Ok(5) and result.work.get(16) == Ok(1) and result.work.get(30) == Ok(1) and result.work.get(34) == Ok(1)
}

## Distinct patterns stay distinct canonical patterns and streams.
expect {
	result = Gate4ShadingPatternEvidence.scenario("pdistinct", 5)?
	result.work.get(16) == Ok(5) and result.work.get(30) == Ok(5) and result.work.get(34) == Ok(5)
}

## Per-cell-command work scales inside one canonical pattern.
expect {
	result = Gate4ShadingPatternEvidence.scenario("pcells", 5)?
	result.work.get(5) == Ok(5) and result.work.get(7) == Ok(5) and result.work.get(16) == Ok(1)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4ShadingPatternEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(27) and result.work.get(1) == Ok(0)
}
