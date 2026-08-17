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
import KernelTagged
import Layout
import Scene
import Semantics

## Gate 4 Form XObject evidence.
##
## Every scenario authors a typed scene with a flat form store, runs the whole
## form pipeline — scene validation, use derivation, the two resource-graph
## runs, canonical recipes, content lowering, object planning, assembly,
## sealing — and emits real PDF bytes plus the deterministic work vector.
##
## - `showcase`  : one page interleaving ordinary content with artifact reuse,
##                 identical visuals under distinct semantic fragments, one
##                 occurrence split across two placements, semantic-plus-
##                 artifact reuse of one visual, nested forms, and a shared
##                 nested dependency; reading order deliberately differs from
##                 paint order. The same document is also authored in reversed
##                 dense-ID order and must produce identical bytes.
## - `repeat xN` : one artifact form placed N times at explicit transforms.
## - `dag xK`    : K distinct parent forms sharing four nested base forms.
## - `deep xN`   : a legal nested chain of depth N, proving iterative
##                 traversal.
## - `unique`/`shared` : the ordinary one-shot ownership path versus the same
##                 retained authored stores planned twice.
Gate4FormEvidence :: [].{
	EvidenceError : [
		AdversarialOrderDiverged,
		EvidenceFailure,
		InvalidScale,
		MissingRejection(U64),
		SharedInputDiverged,
		SharingDiverged,
	]

	scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scenario = |mode, scale| run_scenario(mode, scale)

	## Atomic negative twins: each input differs from a valid scenario in
	## exactly one fact, every rejection is a distinct structured diagnostic,
	## and no partial plan or PDF byte escapes. The fixture emits only an
	## unrelated blank document as its snapshot payload.
	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |runtime_context| run_negatives(runtime_context)
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

translate : I64, I64 -> Scene.Matrix
translate = |x, y| { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(x), f: unit(y) }

gray : U16 -> Color.Value
gray = |level| { channels: Gray(level), space: Color.SpaceId.from_index(0) }

fill_style : U16 -> Scene.PathStyle
fill_style = |level| { fill: SolidFill({ color: gray(level), rule: Nonzero }), stroke: NoStroke }

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

page_box : Layout.Rect
page_box = rect(0, 0, 100000, 100000)

color_store : Color.Store
color_store = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

image_pixels : List(U8)
image_pixels = [0, 64, 128, 255]

image_sources : Image.SourceStore
image_sources = {
	resources: [
		{
			id: Image.Id.from_index(0),
			payload: PackedPixels({
				alpha: NoAlpha,
				color_space: Color.SpaceId.from_index(0),
				dimensions: { height: 2, width: 2 },
				format: Gray8,
				pixels: image_pixels,
				row_stride: 2,
			}),
		},
	],
}

empty_image_sources : Image.SourceStore
empty_image_sources = { resources: [] }

image_descriptor : KernelResourceGraph.Descriptor
image_descriptor = { bit_depth: 8, components: 1, flags: 0, height: 2, kind: Image, subtype: 0, width: 2 }

## A second calibrated store used only by the mismatched-store negative twin.
two_space_color_store : Color.Store
two_space_color_store = {
	profiles: [],
	spaces: [
		{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) },
		{ id: Color.SpaceId.from_index(1), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 964200, y: 1000000, z: 825100 } }) },
	],
	tags: [],
}

## The validated color and image plans every scenario derives its leaf
## identity from.
build_stores : Image.SourceStore -> Try({ colors : KernelColor.Plan, images : KernelImage.Plan }, BuildFailure)
build_stores = |sources| {
	colors = KernelColor.Plan.build(color_store, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? ColorFailure
	images = KernelImage.Plan.build(
		sources,
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 16, max_encoded_bytes: 0, max_height: 2, max_markers: 0, max_resources: 1, max_width: 2 }),
	) ? ImageFailure
	Ok({ colors, images })
}

leaf_objects : KernelForm.Plan -> KernelGate2Objects.LeafObjectCounts
leaf_objects = |plan| {
	counts = KernelForm.Plan.canonical_leaf_counts(plan)
	{ color_spaces: counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(plan), profiles: counts.profiles }
}

## The semantic store for `fragments` meaningful paragraphs in an explicit
## logical order that need not match paint order. Each paragraph owns one
## occurrence; `split` optionally gives the last paragraph a second fragment,
## representing one occurrence fragmented across two placements.
build_semantics : U64, List(U64), Bool -> Semantics.Store
build_semantics = |fragment_count, logical_order, split| {
	paragraph_count = if split fragment_count - 1 else fragment_count
	var $spine = List.with_capacity(paragraph_count)
	var $order_index = 0
	while $order_index < logical_order.len() {
		$spine = $spine.append(ChildNode(Semantics.NodeId.from_index(list_at(logical_order, $order_index) + 1)))
		$order_index = $order_index + 1
	}
	var $nodes = List.with_capacity(paragraph_count + 1)
	$nodes = $nodes.append({
		attributes: empty_range,
		content: Semantics.Range.from_start_and_length(0, paragraph_count),
		element_identifier: NoElementIdentifier,
		id: Semantics.NodeId.from_index(0),
		language: Inherited,
		parent: DocumentRoot,
		role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) },
		structure_element: Semantics.StructureElementId.from_index(0),
		text_properties: empty_range,
	})
	var $content_spine = $spine
	var $occurrences = List.with_capacity(paragraph_count)
	var $occurrence_fragments = List.with_capacity(fragment_count)
	var $fragments = List.with_capacity(fragment_count)
	var $paragraph = 0
	var $fragment = 0
	while $paragraph < paragraph_count {
		fragment_share = if split and $paragraph == paragraph_count - 1 2 else 1
		$content_spine = $content_spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index($paragraph)))
		$occurrences = $occurrences.append({
			fragments: Semantics.Range.from_start_and_length($fragment, fragment_share),
			id: Semantics.OccurrenceId.from_index($paragraph),
			language: Inherited,
			source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(empty_range)),
			text_properties: empty_range,
		})
		var $share = 0
		while $share < fragment_share {
			$occurrence_fragments = $occurrence_fragments.append(Semantics.FragmentId.from_index($fragment))
			$fragments = $fragments.append({
				content_stream: Semantics.ContentStreamId.from_index(0),
				continuation_index: $share,
				id: Semantics.FragmentId.from_index($fragment),
				occurrence: Semantics.OccurrenceId.from_index($paragraph),
				page: Semantics.PageId.from_index(0),
				source_range: ByteRange(empty_range),
			})
			$fragment = $fragment + 1
			$share = $share + 1
		}
		$nodes = $nodes.append({
			attributes: empty_range,
			content: Semantics.Range.from_start_and_length(paragraph_count + $paragraph, 1),
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
	form_store : Scene.FormStore,
	images : Image.SourceStore,
	scene : Scene.Store,
	semantics : Semantics.Store,
}

Built := {
	bytes : List(U8),
	content : KernelContent.Plan,
	facts : KernelForm.Facts,
	form_plan : KernelForm.Plan,
	form_scene : KernelScene.FormPlan,
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
form_limits = KernelForm.Limits.make({ graph: graph_limits, max_recipe_bytes: 4194304 })

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
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_stores(input.images)?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors: stores.colors, fonts: [], images: stores.images }, NoText, tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan, input.form_store), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, stores.colors, stores.images) ? ResourceUseFailure
	base = KernelGate2Objects.Plan.build_canonical(tagged, stores.colors, stores.images, resource_use, content, leaf_objects(form_plan), KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 1 })) ? ObjectFailure
	objects = KernelGate4FormObjects.Plan.build(base, KernelForm.Plan.canonical_form_count(form_plan), 0, 8192) ? FormObjectFailure
	structure = KernelGate4FormStructure.Plan.build(tagged, stores.colors, stores.images, content, form_plan, objects, NoTextObjects, structure_limits) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, content, facts, form_plan, form_scene, structure, tagged })
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
		image_names: KernelForm.Plan.image_names(form_plan),
		streams: $streams,
	}
}

work_vector : Built -> List(U64)
work_vector = |built| {
	plan_work = KernelForm.Plan.work(built.form_plan)
	facts_work = KernelForm.Facts.work(built.facts)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	content_work = KernelContent.Plan.work(built.content)
	form_scene_work = KernelScene.FormPlan.work(built.form_scene)
	tagged_work = KernelTagged.Plan.work(built.tagged)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		plan_work.authored_forms,
		plan_work.canonical_forms,
		plan_work.deduplicated_forms,
		plan_work.semantically_duplicated_forms,
		plan_work.shared_artifact_forms,
		plan_work.semantic_placements,
		plan_work.artifact_placements,
		facts_work.page_form_placements,
		facts_work.nested_form_placements,
		plan_work.nested_form_edges,
		facts_work.root_uses,
		facts_work.direct_edges,
		facts_work.use_command_visits,
		facts_work.ownership_sweep_visits,
		form_scene_work.form_command_visits,
		plan_work.recipe_bytes,
		plan_work.leaf_digests,
		plan_work.form_digests,
		plan_work.dictionary_entries,
		plan_work.nested_dictionary_entries,
		graph_work.resources,
		graph_work.node_visits,
		graph_work.edge_visits,
		graph_work.hashes,
		graph_work.bytes_hashed,
		graph_work.retained_payload_bytes,
		graph_work.copied_payload_bytes,
		content_work.form_placements,
		content_work.form_streams,
		content_work.form_stream_bytes,
		content_work.graphics_state_pairs,
		tagged_work.parent_writes,
		structure_work.dictionary_references,
		structure_work.objects,
		built.bytes.len(),
	]
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4FormEvidence.EvidenceError)
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
	} else if mode == "repeat" {
		if scale < 1 or scale > 20000 {
			return Err(InvalidScale)
		}
		built = run_pipeline(repeat_scenario(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_forms != 1 or work.artifact_placements != scale or work.shared_artifact_forms != (if scale > 1 1 else 0) {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "dag" {

		## Marker distinctness spans 10 columns by 15 exact eight-bit levels.
		if scale < 1 or scale > 128 {
			return Err(InvalidScale)
		}
		built = run_pipeline(dag_scenario(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_forms != scale + 4 or work.nested_form_edges != scale * 4 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "deep" {
		if scale < 2 or scale > 400 {
			return Err(InvalidScale)
		}
		built = run_pipeline(deep_scenario(scale)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_forms != scale or work.nested_form_edges != scale - 1 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The showcase must physically share exactly the deduplicated visuals while
## keeping every placement's ownership distinct: nine authored forms collapse
## to five physical ones, five semantic placements keep five distinct MCIDs,
## and no placement-specific association is merged.
check_showcase_sharing : Built -> Try({}, Gate4FormEvidence.EvidenceError)
check_showcase_sharing = |built| {
	work = KernelForm.Plan.work(built.form_plan)
	placements = KernelForm.Plan.placements(built.form_plan)
	if work.authored_forms != 9 or work.canonical_forms != 5 or work.deduplicated_forms != 4 {
		return Err(SharingDiverged)
	}
	if work.semantic_placements != 5 or work.artifact_placements != 4 or work.semantically_duplicated_forms != 0 {
		return Err(SharingDiverged)
	}

	## Every semantic placement carries a distinct fragment and MCID, so no
	## placement-specific association was merged by deduplication.
	var $semantic_keys = []
	var $index = 0
	while $index < placements.len() {
		placement = list_at(placements, $index)
		match placement.ownership {
			Semantic(semantic) => {
				key = Semantics.FragmentId.index(semantic.fragment) * 1024 + semantic.mcid
				var $probe = 0
				while $probe < $semantic_keys.len() {
					if list_at($semantic_keys, $probe) == key {
						return Err(SharingDiverged)
					}
					$probe = $probe + 1
				}
				$semantic_keys = $semantic_keys.append(key)
			}
			Artifact(_) => {}
		}
		$index = $index + 1
	}

	## All five authored B visuals share one canonical physical form.
	names = KernelForm.Plan.form_names(built.form_plan)
	b_ordinal = list_at(names, 1)
	if list_at(names, 2) != b_ordinal or list_at(names, 3) != b_ordinal or list_at(names, 4) != b_ordinal or list_at(names, 5) != b_ordinal {
		return Err(SharingDiverged)
	}
	Ok({})
}

## `direction` renumbers every authored form ID (and its command-arena layout)
## while describing the same logical document, so the canonical plan and the
## final bytes must not be able to tell the two apart.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	form_count = 9
	dense = |logical| match direction {
		Forward => logical
		Reversed => form_count - 1 - logical
	}

	## Logical form contents, addressed by logical index:
	## 0=A artifact square, 1..5=B visuals, 6=C nested, 7=D base, 8=E nested.
	b_command = DrawPath({ path: Scene.PathId.from_index(1), style: fill_style(16448) })
	logical_commands = [
		[DrawPath({ path: Scene.PathId.from_index(0), style: fill_style(32896) })],
		[b_command],
		[b_command],
		[b_command],
		[b_command],
		[b_command],
		[PlaceForm({ form: Scene.FormId.from_index(dense(7)), transform: translate(20000, 0) }), DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 20000, 10000) })],
		[DrawPath({ path: Scene.PathId.from_index(2), style: fill_style(49344) })],
		[DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 20000, 10000) }), PlaceForm({ form: Scene.FormId.from_index(dense(7)), transform: translate(20000, 0) })],
	]
	logical_boxes = [
		rect(0, 0, 10000, 10000),
		rect(0, 0, 20000, 10000),
		rect(0, 0, 20000, 10000),
		rect(0, 0, 20000, 10000),
		rect(0, 0, 20000, 10000),
		rect(0, 0, 20000, 10000),
		rect(0, 0, 30000, 10000),
		rect(0, 0, 10000, 10000),
		rect(0, 0, 30000, 10000),
	]

	## The arena is written in dense-ID order, so the two directions place the
	## same logical content at different arena offsets and dense IDs.
	var $arena = []
	var $forms = List.with_capacity(form_count)
	var $dense_index = 0
	while $dense_index < form_count {
		logical = match direction {
			Forward => $dense_index
			Reversed => form_count - 1 - $dense_index
		}
		commands = list_at(logical_commands, logical)
		start = $arena.len()
		$arena = $arena.concat(commands)
		$forms = $forms.append({
			bbox: list_at(logical_boxes, logical),
			commands: Semantics.Range.from_start_and_length(start, commands.len()),
			id: Scene.FormId.from_index($dense_index),
		})
		$dense_index = $dense_index + 1
	}

	place = |logical, x, y| PlaceForm({ form: Scene.FormId.from_index(dense(logical)), transform: translate(x, y) })
	page_commands = [
		place(1, 0, 90000),
		DrawPath({ path: Scene.PathId.from_index(3), style: fill_style(8224) }),
		place(0, 0, 75000),
		place(0, 15000, 75000),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(60000, 90000, 20000, 10000) }),
		place(2, 30000, 75000),
		place(6, 0, 60000),
		place(3, 60000, 75000),
		place(8, 0, 45000),
		place(4, 0, 30000),
		place(5, 30000, 30000),
	]
	groups = [
		{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
		{ commands: Semantics.Range.from_start_and_length(1, 4), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
		{ commands: Semantics.Range.from_start_and_length(5, 1), id: Scene.GroupId.from_index(2), owner: Fragment(Semantics.FragmentId.from_index(1)) },
		{ commands: Semantics.Range.from_start_and_length(6, 1), id: Scene.GroupId.from_index(3), owner: Fragment(Semantics.FragmentId.from_index(2)) },
		{ commands: Semantics.Range.from_start_and_length(7, 2), id: Scene.GroupId.from_index(4), owner: PageArtifact(Decoration) },
		{ commands: Semantics.Range.from_start_and_length(9, 1), id: Scene.GroupId.from_index(5), owner: Fragment(Semantics.FragmentId.from_index(3)) },
		{ commands: Semantics.Range.from_start_and_length(10, 1), id: Scene.GroupId.from_index(6), owner: Fragment(Semantics.FragmentId.from_index(4)) },
	]
	scene = {
		commands: page_commands,
		dash_lengths: [],
		groups,
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
				paint_order: Semantics.Range.from_start_and_length(0, 7),
				rotation: Rotate0,
			},
		],
		path_segments: [
			Rectangle(rect(0, 0, 10000, 10000)),
			Rectangle(rect(0, 0, 20000, 10000)),
			Rectangle(rect(0, 0, 10000, 10000)),
			Rectangle(rect(40000, 90000, 10000, 10000)),
		],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: Semantics.Range.from_start_and_length(2, 1) },
			{ id: Scene.PathId.from_index(3), segments: Semantics.Range.from_start_and_length(3, 1) },
		],
	}

	## Logical reading order deliberately differs from paint order: the second
	## painted paragraph reads first.
	{
		form_store: { commands: $arena, forms: $forms },
		images: image_sources,
		scene,
		semantics: build_semantics(5, [1, 0, 2, 3], Bool.True),
	}
}

repeat_scenario : U64 -> Scenario
repeat_scenario = |scale| {
	var $page_commands = [DrawPath({ path: Scene.PathId.from_index(1), style: fill_style(8224) })]
	var $index = 0
	while $index < scale {
		column = U64.mod_by($index, 10) * 10000
		row = U64.mod_by(U64.div_by($index, 10), 9) * 10000
		$page_commands = $page_commands.append(
			PlaceForm({
				form: Scene.FormId.from_index(0),
				transform: translate(column.to_i64_wrap(), row.to_i64_wrap()),
			}),
		)
		$index = $index + 1
	}
	scene = {
		commands: $page_commands,
		dash_lengths: [],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: Semantics.Range.from_start_and_length(1, scale), id: Scene.GroupId.from_index(1), owner: PageArtifact(Watermark) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: Semantics.Range.from_start_and_length(0, 2),
				rotation: Rotate0,
			},
		],
		path_segments: [Rectangle(rect(0, 0, 4000, 4000)), Rectangle(rect(0, 95000, 4000, 4000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
		],
	}
	{
		form_store: {
			commands: [DrawPath({ path: Scene.PathId.from_index(0), style: fill_style(32896) })],
			forms: [{ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.FormId.from_index(0) }],
		},
		images: empty_image_sources,
		scene,
		semantics: build_semantics(1, [0], Bool.False),
	}
}

dag_scenario : U64 -> Scenario
dag_scenario = |scale| {

	## Four shared base forms, then `scale` distinct parents that each place
	## all four and additionally paint one parent-specific integer-position
	## marker, so parents never deduplicate while every painted edge stays on
	## an exact pixel boundary for the zero-tolerance renderer expectation.
	var $arena = []
	var $forms = []
	var $base = 0
	while $base < 4 {
		start = $arena.len()
		$arena = $arena.append(DrawPath({ path: Scene.PathId.from_index($base), style: fill_style((($base + 1) * 8224).to_u16_wrap()) }))
		$forms = $forms.append({ bbox: rect(0, 0, 2000, 2000), commands: Semantics.Range.from_start_and_length(start, 1), id: Scene.FormId.from_index($base) })
		$base = $base + 1
	}
	var $parent = 0
	while $parent < scale {
		start = $arena.len()
		var $child = 0
		while $child < 4 {
			$arena = $arena.append(
				PlaceForm({
					form: Scene.FormId.from_index($child),
					transform: translate($child.to_i64_wrap() * 2000, 0),
				}),
			)
			$child = $child + 1
		}
		marker_level = ((U64.div_by($parent, 10) + 1) * 4112).to_u16_wrap()
		$arena = $arena.append(DrawPath({ path: Scene.PathId.from_index(5 + $parent), style: fill_style(marker_level) }))
		$forms = $forms.append({ bbox: rect(0, 0, 10000, 4000), commands: Semantics.Range.from_start_and_length(start, 5), id: Scene.FormId.from_index(4 + $parent) })
		$parent = $parent + 1
	}
	var $page_commands = [DrawPath({ path: Scene.PathId.from_index(4), style: fill_style(8224) })]
	$parent = 0
	while $parent < scale {
		column = U64.mod_by($parent, 10) * 10000
		row = (U64.mod_by(U64.div_by($parent, 10), 8) + 1) * 10000
		$page_commands = $page_commands.append(
			PlaceForm({
				form: Scene.FormId.from_index(4 + $parent),
				transform: translate(column.to_i64_wrap(), row.to_i64_wrap()),
			}),
		)
		$parent = $parent + 1
	}
	var $path_segments = [
		Rectangle(rect(0, 0, 2000, 2000)),
		Rectangle(rect(0, 0, 2000, 1000)),
		Rectangle(rect(0, 0, 1000, 2000)),
		Rectangle(rect(1000, 0, 1000, 2000)),
		Rectangle(rect(0, 95000, 4000, 4000)),
	]
	var $paths = [
		{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
		{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
		{ id: Scene.PathId.from_index(2), segments: Semantics.Range.from_start_and_length(2, 1) },
		{ id: Scene.PathId.from_index(3), segments: Semantics.Range.from_start_and_length(3, 1) },
		{ id: Scene.PathId.from_index(4), segments: Semantics.Range.from_start_and_length(4, 1) },
	]
	$parent = 0
	while $parent < scale {
		marker_x = (U64.mod_by($parent, 10) * 1000).to_i64_wrap()
		$path_segments = $path_segments.append(Rectangle(rect(marker_x, 3000, 1000, 1000)))
		$paths = $paths.append({ id: Scene.PathId.from_index(5 + $parent), segments: Semantics.Range.from_start_and_length(5 + $parent, 1) })
		$parent = $parent + 1
	}
	scene = {
		commands: $page_commands,
		dash_lengths: [],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: Semantics.Range.from_start_and_length(1, scale), id: Scene.GroupId.from_index(1), owner: PageArtifact(Decoration) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: Semantics.Range.from_start_and_length(0, 2),
				rotation: Rotate0,
			},
		],
		path_segments: $path_segments,
		paths: $paths,
	}
	{
		form_store: { commands: $arena, forms: $forms },
		images: empty_image_sources,
		scene,
		semantics: build_semantics(1, [0], Bool.False),
	}
}

deep_scenario : U64 -> Scenario
deep_scenario = |scale| {

	## A legal chain: form i places form i + 1 and paints its own small step;
	## the last form paints only. The whole chain is placed once.
	var $arena = []
	var $forms = []
	var $index = 0
	while $index < scale {
		start = $arena.len()
		$arena = $arena.append(DrawPath({ path: Scene.PathId.from_index(0), style: fill_style(((U64.mod_by($index, 8) + 1) * 4112).to_u16_wrap()) }))
		commands = if $index + 1 < scale {
			$arena = $arena.append(PlaceForm({ form: Scene.FormId.from_index($index + 1), transform: translate(1000, 1000) }))
			2
		} else {
			1
		}
		$forms = $forms.append({
			bbox: rect(0, 0, (scale.to_i64_wrap() - $index.to_i64_wrap() + 1) * 1000, (scale.to_i64_wrap() - $index.to_i64_wrap() + 1) * 1000),
			commands: Semantics.Range.from_start_and_length(start, commands),
			id: Scene.FormId.from_index($index),
		})
		$index = $index + 1
	}
	scene = {
		commands: [
			DrawPath({ path: Scene.PathId.from_index(1), style: fill_style(8224) }),
			PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) }),
		],
		dash_lengths: [],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: Semantics.Range.from_start_and_length(0, 2),
				rotation: Rotate0,
			},
		],
		path_segments: [Rectangle(rect(0, 0, 800, 800)), Rectangle(rect(0, 95000, 4000, 4000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
		],
	}
	{
		form_store: { commands: $arena, forms: $forms },
		images: empty_image_sources,
		scene,
		semantics: build_semantics(1, [0], Bool.False),
	}
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4FormEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	rejections = check_negatives(context)?
	blank = run_pipeline(repeat_scenario(context)) ? |_| EvidenceFailure
	Ok({ bytes: blank.bytes, work: [rejections, 0, blank.bytes.len()] })
}

## Each negative twin below changes exactly one fact of a valid scenario and
## must fail with its own structured diagnostic before any plan or byte
## escapes.
check_negatives : U64 -> Try(U64, Gate4FormEvidence.EvidenceError)
check_negatives = |context| {
	base = repeat_scenario(context)

	## 1: a placement referencing a form outside the dense store.
	missing_form = { ..base, scene: replace_command(base.scene, 1, PlaceForm({ form: Scene.FormId.from_index(7), transform: translate(0, 0) })) }
	expect_scene_rejection(
		1,
		missing_form,
		|error| match error {
			IndexOutOfRange({ available: _, index: 7, kind: FormIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 2: a non-dense form identity.
	sparse = { ..base, form_store: { ..base.form_store, forms: [{ ..list_at(base.form_store.forms, 0), id: Scene.FormId.from_index(3) }] } }
	expect_scene_rejection(
		2,
		sparse,
		|error| match error {
			NonDenseIdentity({ actual: 3, expected: 0, kind: FormIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 3: an empty form content range.
	empty_form = { ..base, form_store: { ..base.form_store, forms: [{ ..list_at(base.form_store.forms, 0), commands: Semantics.Range.from_start_and_length(0, 0) }] } }
	expect_scene_rejection(
		3,
		empty_form,
		|error| match error {
			EmptyForm({ form: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 4: a form content range escaping the arena.
	escaping = { ..base, form_store: { ..base.form_store, forms: [{ ..list_at(base.form_store.forms, 0), commands: Semantics.Range.from_start_and_length(0, 2) }] } }
	expect_scene_rejection(
		4,
		escaping,
		|error| match error {
			SpanOutOfRange({ kind: FormCommandIndex, available: _, length: _, owner: _, start: _ }) => Bool.True
			_ => Bool.False
		},
	)?

	## 5: an empty bounding box.
	flat_box = { ..base, form_store: { ..base.form_store, forms: [{ ..list_at(base.form_store.forms, 0), bbox: rect(0, 0, 4000, 0) }] } }
	expect_scene_rejection(
		5,
		flat_box,
		|error| match error {
			NonPositiveRect({ index: 0, kind: FormIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: a singular placement transform.
	singular = { ..base, scene: replace_command(base.scene, 1, PlaceForm({ form: Scene.FormId.from_index(0), transform: { a: unit(1000), b: unit(0), c: unit(0), d: unit(0), e: unit(0), f: unit(0) } })) }
	expect_scene_rejection(
		6,
		singular,
		|error| match error {
			FormTransformSingular({ command: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 7: an overflowing placement determinant.
	overflowing = { ..base, scene: replace_command(base.scene, 1, PlaceForm({ form: Scene.FormId.from_index(0), transform: { a: unit(I64.highest), b: unit(0), c: unit(0), d: unit(I64.highest), e: unit(0), f: unit(0) } })) }
	expect_scene_rejection(
		7,
		overflowing,
		|error| match error {
			ArithmeticOverflow => Bool.True
			_ => Bool.False
		},
	)?

	## 8: a command owned by no form.
	orphan_arena = { ..base, form_store: { ..base.form_store, commands: base.form_store.commands.append(list_at(base.form_store.commands, 0)) } }
	expect_scene_rejection(
		8,
		orphan_arena,
		|error| match error {
			Orphaned({ index: 1, kind: FormCommandIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 9: two forms claiming one arena command.
	double_owned = {
		..base,
		form_store: {
			..base.form_store,
			forms: base.form_store.forms.append({ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.FormId.from_index(1) }),
		},
	}
	expect_scene_rejection(
		9,
		double_owned,
		|error| match error {
			DuplicateOwnership({ index: 0, kind: FormCommandIndex }) => Bool.True
			_ => Bool.False
		},
	)?

	## 10: unsupported transparency inside form content.
	transparent = { ..base, form_store: { ..base.form_store, commands: [Opacity({ children: Semantics.Range.from_start_and_length(0, 0), opacity: 32768 })] } }
	expect_scene_rejection(
		10,
		transparent,
		|error| match error {
			UnsupportedCommand({ command: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 11: the form-count limit.
	expect_form_limit_rejection(
		11,
		base,
		KernelScene.FormLimits.make({ max_form_commands: 65536, max_forms: 0 }),
		|error| match error {
			LimitExceeded({ attempted: 1, dimension: Forms, limit: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 12: the form-command limit.
	expect_form_limit_rejection(
		12,
		base,
		KernelScene.FormLimits.make({ max_form_commands: 0, max_forms: 4096 }),
		|error| match error {
			LimitExceeded({ attempted: 1, dimension: FormCommands, limit: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 13: graphics depth inside form content.
	nested_depth = {
		..base,
		form_store: {
			commands: [
				Transform({ children: Semantics.Range.from_start_and_length(1, 1), matrix: translate(0, 0) }),
				Transform({ children: Semantics.Range.from_start_and_length(2, 1), matrix: translate(0, 0) }),
				DrawPath({ path: Scene.PathId.from_index(0), style: fill_style(32896) }),
			],
			forms: [{ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.FormId.from_index(0) }],
		},
	}
	shallow = KernelScene.Limits.make({
		max_commands: 65536,
		max_dash_lengths: 0,
		max_graphics_depth: 2,
		max_groups: 4096,
		max_pages: 1,
		max_path_segments: 4096,
		max_paths: 1024,
	})
	scene_resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: 1, images: 0, text_runs: 0 })
	depth_rejected = match KernelScene.FormPlan.build(nested_depth.scene, nested_depth.form_store, scene_resources, shallow, form_scene_limits) {
		Err(LimitExceeded({ attempted: 3, dimension: GraphicsDepth, limit: 2 })) => Bool.True
		_ => Bool.False
	}
	if !depth_rejected {
		return Err(MissingRejection(13))
	}

	## 14: a self-cycle propagated from the resource graph.
	self_cycle = {
		..base,
		form_store: {
			commands: [PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) })],
			forms: [{ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.FormId.from_index(0) }],
		},
	}
	expect_facts_rejection(
		14,
		self_cycle,
		|error| match error {
			Graph(SelfCycle(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 15: a two-form cycle propagated from the resource graph.
	two_cycle = {
		..base,
		form_store: {
			commands: [
				PlaceForm({ form: Scene.FormId.from_index(1), transform: translate(0, 0) }),
				PlaceForm({ form: Scene.FormId.from_index(0), transform: translate(0, 0) }),
			],
			forms: [
				{ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.FormId.from_index(0) },
				{ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.FormId.from_index(1) },
			],
		},
	}
	expect_facts_rejection(
		15,
		two_cycle,
		|error| match error {
			Graph(DependencyCycle(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 16: an authored form no content stream can reach.
	unplaced = {
		..base,
		form_store: {
			commands: base.form_store.commands.append(DrawPath({ path: Scene.PathId.from_index(0), style: fill_style(16448) })),
			forms: base.form_store.forms.append({ bbox: rect(0, 0, 4000, 4000), commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.FormId.from_index(1) }),
		},
	}
	expect_facts_rejection(
		16,
		unplaced,
		|error| match error {
			Graph(UnreachableResource(_)) => Bool.True
			_ => Bool.False
		},
	)?

	## 17: sharing a placement-specific semantic association is rejected by
	## the resource graph's ownership guard. The runtime context flows into
	## the payload so the whole rejection is evaluated and measured at runtime.
	merge_rejected = match KernelResourceGraph.Plan.build(
		{
			digest_policy: DomainSeparatedSha256,
			edges: [],
			payload_bytes: [context.to_u8_wrap(), 2, 3, 4, 5, 6, 7, 8],
			placements: [{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(0), mcid: 0 }), resource: 0, reuse: Reusable }],
			resources: [{ descriptor: image_descriptor, length: 8, start: 0 }],
			root_count: 1,
			root_uses: [{ resource: 0, root: 0 }],
		},
		graph_limits,
	) {
		Err(SemanticOwnershipMerge({ placement: 0, resource: 0 })) => Bool.True
		_ => Bool.False
	}
	if !merge_rejected {
		return Err(MissingRejection(17))
	}

	## 18: one fragment claiming two painted groups (illegal semantic reuse).
	duplicated_fragment = {
		..base,
		scene: {
			..base.scene,
			groups: [
				list_at(base.scene.groups, 0),
				{ ..list_at(base.scene.groups, 1), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			],
		},
	}
	expect_tagged_rejection(
		18,
		duplicated_fragment,
		|error| match error {
			DuplicateFragmentOwnership({ fragment: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 19: content bytes exhausted by form streams, transactionally.
	tight_content = KernelContent.Limits.make({ max_content_bytes: 64, max_content_streams: 1 })
	content_rejected = match build_content(base, tight_content) {
		Err(ContentFailure(LimitExceeded({ dimension: ContentBytes, attempted: _, limit: 64 }))) => Bool.True
		_ => Bool.False
	}
	if !content_rejected {
		return Err(MissingRejection(19))
	}

	## 20: the object budget cannot admit the planned form objects.
	object_rejected = match build_objects(base, 5) {
		Err(FormObjectFailure(LimitExceeded({ attempted: _, limit: 5 }))) => Bool.True
		_ => Bool.False
	}
	if !object_rejected {
		return Err(MissingRejection(20))
	}

	## 21: the recipe byte budget is enforced before the canonical run.
	recipe_rejected = match build_form_plan_with_limits(base, KernelForm.Limits.make({ graph: graph_limits, max_recipe_bytes: 8 })) {
		Err(FormPlanFailure(RecipeByteLimitExceeded({ attempted: _, limit: 8 }))) => Bool.True
		_ => Bool.False
	}
	if !recipe_rejected {
		return Err(MissingRejection(21))
	}

	## 22: the canonical run's stores must be the stores its facts were
	## derived from; a color store with a different space count is rejected
	## before any leaf identity exists.
	mismatched_stores = match build_form_plan_with_mismatched_stores(base) {
		Err(FormPlanFailure(StoreCountMismatch({ declared: 1, kind: ColorSpaces, supplied: 2 }))) => Bool.True
		_ => Bool.False
	}
	if !mismatched_stores {
		return Err(MissingRejection(22))
	}

	Ok(context * 22)
}

replace_command : Scene.Store, U64, Scene.Command -> Scene.Store
replace_command = |scene, index, command| { ..scene, commands: list_set(scene.commands, index, command) }

expect_scene_rejection : U64, Scenario, (KernelScene.Error -> Bool) -> Try({}, Gate4FormEvidence.EvidenceError)
expect_scene_rejection = |ordinal, input, matches| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	match KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_form_limit_rejection : U64, Scenario, KernelScene.FormLimits, (KernelScene.Error -> Bool) -> Try({}, Gate4FormEvidence.EvidenceError)
expect_form_limit_rejection = |ordinal, input, limits, matches| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	match KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_facts_rejection : U64, Scenario, (KernelForm.Error -> Bool) -> Try({}, Gate4FormEvidence.EvidenceError)
expect_facts_rejection = |ordinal, input, matches| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? |_| MissingRejection(ordinal)
	stores = build_stores(input.images) ? |_| MissingRejection(ordinal)
	match KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_tagged_rejection : U64, Scenario, (KernelTagged.Error -> Bool) -> Try({}, Gate4FormEvidence.EvidenceError)
expect_tagged_rejection = |ordinal, input, matches| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? |_| MissingRejection(ordinal)
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? |_| MissingRejection(ordinal)
	match KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

build_content : Scenario, KernelContent.Limits -> Try(KernelContent.Plan, BuildFailure)
build_content = |input, limits| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_stores(input.images)?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors: stores.colors, fonts: [], images: stores.images }, NoText, tagged, form_limits) ? FormPlanFailure
	plan = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan, input.form_store), limits) ? ContentFailure
	Ok(plan)
}

build_objects : Scenario, U64 -> Try(KernelGate4FormObjects.Plan, BuildFailure)
build_objects = |input, max_objects| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_stores(input.images)?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors: stores.colors, fonts: [], images: stores.images }, NoText, tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan, input.form_store), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, stores.colors, stores.images) ? ResourceUseFailure
	base = KernelGate2Objects.Plan.build_canonical(tagged, stores.colors, stores.images, resource_use, content, leaf_objects(form_plan), KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 1 })) ? ObjectFailure
	plan = KernelGate4FormObjects.Plan.build(base, KernelForm.Plan.canonical_form_count(form_plan), 0, max_objects) ? FormObjectFailure
	Ok(plan)
}

build_form_plan_with_limits : Scenario, KernelForm.Limits -> Try(KernelForm.Plan, BuildFailure)
build_form_plan_with_limits = |input, limits| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_stores(input.images)?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	plan = KernelForm.Plan.build(form_scene, facts, { colors: stores.colors, fonts: [], images: stores.images }, NoText, tagged, limits) ? FormPlanFailure
	Ok(plan)
}

build_form_plan_with_mismatched_stores : Scenario -> Try(KernelForm.Plan, BuildFailure)
build_form_plan_with_mismatched_stores = |input| {
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	stores = build_stores(input.images)?
	facts = KernelForm.Facts.build(form_scene, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	two_spaces = KernelColor.Plan.build(two_space_color_store, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 2, max_tags: 0 })) ? ColorFailure
	plan = KernelForm.Plan.build(form_scene, facts, { colors: two_spaces, fonts: [], images: stores.images }, NoText, tagged, form_limits) ? FormPlanFailure
	Ok(plan)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 form evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "Gate 4 form evidence update escaped"
	}
}

## The showcase deduplicates nine authored forms into five physical ones while
## keeping five distinct semantic placements and four artifact placements.
expect {
	result = Gate4FormEvidence.scenario("showcase", 0)?
	result.work.get(0) == Ok(9) and result.work.get(1) == Ok(5) and result.work.get(2) == Ok(4) and result.work.get(3) == Ok(0) and result.work.get(5) == Ok(5) and result.work.get(6) == Ok(4)
}

## Repeated artifact placement shares one physical form at any scale.
expect {
	result = Gate4FormEvidence.scenario("repeat", 5)?
	result.work.get(1) == Ok(1) and result.work.get(4) == Ok(1) and result.work.get(6) == Ok(5)
}

## The nested DAG keeps exactly its direct edges and shared base forms.
expect {
	result = Gate4FormEvidence.scenario("dag", 3)?
	result.work.get(1) == Ok(7) and result.work.get(9) == Ok(12)
}

## A deep legal chain plans iteratively without recursion.
expect {
	result = Gate4FormEvidence.scenario("deep", 8)?
	result.work.get(1) == Ok(8) and result.work.get(9) == Ok(7)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4FormEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(22) and result.work.get(1) == Ok(0)
}
