import Color
import Document
import KernelColor
import KernelContent
import KernelEmit
import KernelForm
import KernelGate2Objects
import KernelGate4FormObjects
import KernelGate4FormStructure
import KernelImage
import KernelMetadata
import KernelObject
import KernelPdfFont
import KernelResourceGraph
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelSrgbProfile
import KernelStructure
import KernelTagged
import KernelXmp
import Layout
import Metadata
import Pdf
import Scene
import Semantics

## Gate 4 metadata, document-language, and output-intent evidence.
##
## Every positive scenario validates authored metadata facts once, serializes
## the canonical XMP packet once, runs the whole canonical Gate 4 pipeline
## with document facts (catalog `/Lang`, `/Metadata`, and `/OutputIntents`
## entries, the uncompressed XMP stream, and the packaged sRGB output intent
## sharing the canonical deduplicated ICC profile stream with the painted
## ICCBased color spaces), and emits real PDF bytes plus the deterministic
## work vector.
##
## - `showcase` : one page painting calibrated gray, an `Srgb` space, and an
##                equivalent `IccBased` space over the packaged profile
##                authored twice; the output intent references one authored
##                profile and must resolve to the single canonical stream.
##                The same document authored with the profile references and
##                the intent target swapped must produce identical bytes.
## - `minimal`  : the showcase facts with both timestamps omitted — the XMP
##                packet deterministically omits the timestamp properties and
##                their namespace declaration.
## - `share xN` : N fragments each painted in its own authored `Srgb` space
##                over its own authored copy of the packaged profile; all N
##                collapse to one canonical space and one canonical profile
##                stream that the output intent also references.
## - `title xN` : the showcase document with an escape-heavy title of N
##                two-byte segments, isolating per-metadata-byte work.
## - `unique`/`shared` : the ordinary one-shot ownership path versus the same
##                retained authored input planned twice.
Gate4MetadataEvidence :: [].{
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

	## Atomic negative twins: each input differs from a valid request in
	## exactly one fact, every rejection is a distinct typed error, and no
	## partial plan or PDF byte escapes. The fixture emits the unrelated
	## showcase document as its snapshot payload.
	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |runtime_context| run_negatives(runtime_context)
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

page_box : Layout.Rect
page_box = rect(0, 0, 100000, 100000)

d65_white : Color.Tristimulus
d65_white = { x: 950000, y: 1000000, z: 1089000 }

zero_black : Color.Tristimulus
zero_black = { x: 0, y: 0, z: 0 }

cal_gray : Color.Space
cal_gray = CalibratedGray({ black_point: zero_black, white_point: d65_white })

gray_value : U16, U64 -> Color.Value
gray_value = |level, space| { channels: Gray(level), space: Color.SpaceId.from_index(space) }

rgb_value : U16, U16, U16, U64 -> Color.Value
rgb_value = |red, green, blue, space| { channels: Rgb({ blue, green, red }), space: Color.SpaceId.from_index(space) }

fill_with : Color.Value -> Scene.PathStyle
fill_with = |color| { fill: SolidFill({ color, rule: Nonzero }), stroke: NoStroke }

metadata_limits : KernelMetadata.Limits
metadata_limits = KernelMetadata.Limits.make({ max_language_bytes: 64, max_title_bytes: 2048 })

max_xmp_bytes : U64
max_xmp_bytes = 16384

showcase_title : Str
showcase_title = "Café Metadata & <Intent> — 概要"

showcase_language : Str
showcase_language = "en-AU"

showcase_created : Metadata.TimestampInput
showcase_created = Explicit("2026-01-02T03:04:05Z")

showcase_modified : Metadata.TimestampInput
showcase_modified = Explicit("2026-08-18T09:30:00Z")

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
	max_text_string_bytes: 128,
	max_text_strings: 4,
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
		content: Semantics.Range.from_start_and_length(0, fragment_count),
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
			fragments: Semantics.Range.from_start_and_length($paragraph, 1),
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
			content: Semantics.Range.from_start_and_length(fragment_count + $paragraph, 1),
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
	intent_profile : Color.ProfileId,
	metadata : { created : Metadata.TimestampInput, language : Str, modified : Metadata.TimestampInput, title : Str },
	scene : Scene.Store,
	semantics : Semantics.Store,
}

Built := {
	bytes : List(U8),
	colors : KernelColor.Plan,
	form_plan : KernelForm.Plan,
	intent_work : KernelMetadata.IntentWork,
	metadata_work : KernelMetadata.Work,
	packet : KernelXmp.Packet,
	structure : KernelGate4FormStructure.Plan,
}

BuildFailure := [
	ColorFailure(KernelColor.Error),
	ContentFailure(KernelContent.Error),
	EmitFailure,
	FactsFailure(KernelForm.Error),
	FormObjectFailure(KernelGate4FormObjects.Error),
	FormPlanFailure(KernelForm.Error),
	FormSceneFailure(KernelScene.Error),
	ImageFailure(KernelImage.Error),
	IntentFailure(KernelMetadata.IntentError),
	MetadataFailure(Metadata.Error),
	ObjectFailure(KernelGate2Objects.Error),
	PacketFailure(KernelXmp.Error),
	ResourceUseFailure(KernelResourceUse.Error),
	SemanticFailure(KernelSemantics.Error),
	StructureFailure(KernelGate4FormStructure.Error),
	TaggedFailure(KernelTagged.Error),
]

no_images : KernelColor.Plan -> Try(KernelImage.Plan, BuildFailure)
no_images = |colors| {
	plan = KernelImage.Plan.build(
		{ resources: [] },
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ? ImageFailure
	Ok(plan)
}

## The canonical Gate 4 pipeline with document facts: metadata validation and
## XMP serialization happen exactly once before planning, and the structure
## builder receives the already-validated facts.
run_pipeline : Scenario -> Try(Built, BuildFailure)
run_pipeline = |input| {
	validated = KernelMetadata.validate(input.metadata, metadata_limits) ? MetadataFailure
	packet = KernelXmp.Packet.build(validated.facts, max_xmp_bytes) ? PacketFailure
	intent_work = KernelMetadata.validate_intent(
		{ profile: input.intent_profile, registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		input.colors,
	) ? IntentFailure
	semantic = KernelSemantics.Plan.build(
		input.semantics,
		1,
		1,
		semantic_limits(input.semantics.nodes.len(), input.semantics.content_spine.len(), input.semantics.fragments.len()),
	) ? SemanticFailure
	resources = KernelScene.Resources.with_forms({
		color_spaces: input.colors.spaces.len(),
		forms: 0,
		images: 0,
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, Scene.no_forms, resources, scene_limits, form_scene_limits) ? FormSceneFailure
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? ColorFailure
	images = no_images(colors)?
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build(form_scene, facts, { colors, fonts: [], images }, NoText, tagged, form_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, colors, images) ? ResourceUseFailure
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
	plan_facts = WithDocumentFacts({
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		profile: input.intent_profile,
		registry_name: KernelMetadata.icc_registry_name,
		language: validated.facts.language,
		xmp: KernelXmp.Packet.bytes(packet),
	})
	structure = KernelGate4FormStructure.Plan.build_with_facts(
		tagged,
		colors,
		images,
		content,
		form_plan,
		objects,
		NoTextObjects,
		Scene.no_shadings,
		plan_facts,
		structure_limits,
	) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, colors, form_plan, intent_work, metadata_work: validated.work, packet, structure })
}

form_context : KernelForm.Plan -> KernelContent.FormContext
form_context = |form_plan| {
	arena: [],
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
	streams: [],
}

work_vector : Built -> List(U64)
work_vector = |built| {
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	packet_work = KernelXmp.Packet.work(built.packet)
	[
		plan_work.authored_profiles,
		plan_work.canonical_profiles,
		plan_work.deduplicated_profiles,
		plan_work.authored_color_spaces,
		plan_work.canonical_color_spaces,
		built.metadata_work.language_bytes,
		built.metadata_work.title_bytes,
		built.metadata_work.timestamp_bytes,
		built.intent_work.intent_bytes_compared,
		packet_work.packet_bytes,
		packet_work.properties,
		packet_work.title_escapes,
		structure_work.metadata_bytes,
		structure_work.metadata_objects,
		structure_work.resources.profile_bytes,
		graph_work.bytes_hashed,
		structure_work.objects,
		built.bytes.len(),
	]
}

## The showcase authors the packaged profile twice; `Reversed` swaps which
## authored profile each space and the output intent reference, which must
## not change one emitted byte.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	first = match direction {
		Forward => 0
		Reversed => 1
	}
	second = 1 - first
	colors : Color.Store
	colors = {
		profiles: [KernelSrgbProfile.profile(0, 0), KernelSrgbProfile.profile(1, KernelSrgbProfile.tag_count)],
		spaces: [
			{ id: Color.SpaceId.from_index(0), space: cal_gray },
			{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(first)) },
			{ id: Color.SpaceId.from_index(2), space: IccBased({ components: Three, profile: Color.ProfileId.from_index(second) }) },
		],
		tags: KernelSrgbProfile.tags.concat(KernelSrgbProfile.tags),
	}
	scene : Scene.Store
	scene = {
		commands: [
			DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(gray_value(57568, 0)) }),
			DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(rgb_value(65535, 16448, 8224, 1)) }),
			DrawPath({ path: Scene.PathId.from_index(2), style: fill_with(rgb_value(8224, 16448, 65535, 2)) }),
		],
		dash_lengths: [],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) },
			{ commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.GroupId.from_index(1), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: Semantics.Range.from_start_and_length(2, 1), id: Scene.GroupId.from_index(2), owner: Fragment(Semantics.FragmentId.from_index(1)) },
		],
		page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1), Scene.GroupId.from_index(2)],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: Semantics.Range.from_start_and_length(0, 3),
				rotation: Rotate0,
			},
		],
		path_segments: [
			Rectangle(rect(0, 0, 100000, 100000)),
			Rectangle(rect(10000, 55000, 80000, 30000)),
			Rectangle(rect(10000, 15000, 80000, 30000)),
		],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
			{ id: Scene.PathId.from_index(2), segments: Semantics.Range.from_start_and_length(2, 1) },
		],
	}
	{
		color_limits: KernelColor.Limits.make({
			max_icc_bytes: KernelSrgbProfile.byte_count * 2,
			max_profiles: 2,
			max_spaces: 3,
			max_tags: KernelSrgbProfile.tag_count * 2,
		}),
		colors,
		intent_profile: Color.ProfileId.from_index(first),
		metadata: { created: showcase_created, language: showcase_language, modified: showcase_modified, title: showcase_title },
		scene,
		semantics: build_semantics(2, [1, 0]),
	}
}

## `scale` fragments, each painted in its own authored `Srgb` space over its
## own authored copy of the packaged profile bytes.
share_scenario : U64 -> Scenario
share_scenario = |scale| {
	var $profiles = List.with_capacity(scale)
	var $spaces = List.with_capacity(scale)
	var $commands = List.with_capacity(scale)
	var $groups = List.with_capacity(scale)
	var $page_groups = List.with_capacity(scale)
	var $segments = List.with_capacity(scale)
	var $paths = List.with_capacity(scale)
	var $order = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		$profiles = $profiles.append(KernelSrgbProfile.profile($index, $index * KernelSrgbProfile.tag_count))
		$spaces = $spaces.append({ id: Color.SpaceId.from_index($index), space: Srgb(Color.ProfileId.from_index($index)) })
		column = U64.mod_by($index, 8) * 12000
		row = U64.mod_by(U64.div_by($index, 8), 8) * 12000
		$segments = $segments.append(Rectangle(rect(column.to_i64_wrap(), row.to_i64_wrap(), 10000, 10000)))
		$paths = $paths.append({ id: Scene.PathId.from_index($index), segments: Semantics.Range.from_start_and_length($index, 1) })
		$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index($index), style: fill_with(rgb_value(65535, 32896, 8224, $index)) }))
		$groups = $groups.append({ commands: Semantics.Range.from_start_and_length($index, 1), id: Scene.GroupId.from_index($index), owner: Fragment(Semantics.FragmentId.from_index($index)) })
		$page_groups = $page_groups.append(Scene.GroupId.from_index($index))
		$order = $order.append($index)
		$index = $index + 1
	}
	var $tags = List.with_capacity(scale * KernelSrgbProfile.tag_count)
	var $tag_round = 0
	while $tag_round < scale {
		$tags = $tags.concat(KernelSrgbProfile.tags)
		$tag_round = $tag_round + 1
	}
	{
		color_limits: KernelColor.Limits.make({
			max_icc_bytes: KernelSrgbProfile.byte_count * scale,
			max_profiles: scale,
			max_spaces: scale,
			max_tags: KernelSrgbProfile.tag_count * scale,
		}),
		colors: { profiles: $profiles, spaces: $spaces, tags: $tags },
		intent_profile: Color.ProfileId.from_index(0),
		metadata: { created: showcase_created, language: showcase_language, modified: showcase_modified, title: showcase_title },
		scene: {
			commands: $commands,
			dash_lengths: [],
			groups: $groups,
			page_groups: $page_groups,
			pages: [
				{
					boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
					id: Semantics.PageId.from_index(0),
					paint_order: Semantics.Range.from_start_and_length(0, scale),
					rotation: Rotate0,
				},
			],
			path_segments: $segments,
			paths: $paths,
		},
		semantics: build_semantics(scale, $order),
	}
}

## The showcase with an escape-heavy title of `scale` two-byte `A&` segments.
title_scenario : U64 -> Scenario
title_scenario = |scale| {
	var $title = List.reserve([], scale * 2)
	var $index = 0
	while $index < scale {
		$title = $title.append(0x41).append(0x26)
		$index = $index + 1
	}
	title = match Str.from_utf8($title) {
		Ok(value) => value
		Err(_) => {
			crash "scaled metadata title construction failed"
		}
	}
	base = showcase_scenario(Forward)
	Scenario.{
		color_limits: base.color_limits,
		colors: base.colors,
		intent_profile: base.intent_profile,
		metadata: { created: showcase_created, language: showcase_language, modified: showcase_modified, title },
		scene: base.scene,
		semantics: base.semantics,
	}
}

minimal_scenario : {} -> Scenario
minimal_scenario = |_| {
	base = showcase_scenario(Forward)
	Scenario.{
		color_limits: base.color_limits,
		colors: base.colors,
		intent_profile: base.intent_profile,
		metadata: { created: Omitted, language: showcase_language, modified: Omitted, title: showcase_title },
		scene: base.scene,
		semantics: base.semantics,
	}
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4MetadataEvidence.EvidenceError)
run_scenario = |mode, scale| {

	## Always zero at runtime, but derived from a runtime argument, so the
	## measured pipelines cannot be evaluated at compile time.
	guard = U64.mod_by(scale, 1)
	if mode == "showcase" {
		forward = run_pipeline(guarded(showcase_scenario(Forward), guard)) ? |_| EvidenceFailure
		reversed = run_pipeline(guarded(showcase_scenario(Reversed), guard)) ? |_| EvidenceFailure
		if forward.bytes != reversed.bytes {
			return Err(AdversarialOrderDiverged)
		}
		check_sharing(forward, 2, 1)?
		Ok({ bytes: forward.bytes, work: work_vector(forward) })
	} else if mode == "minimal" {
		built = run_pipeline(guarded(minimal_scenario({}), guard)) ? |_| EvidenceFailure
		if KernelXmp.Packet.work(built.packet).properties != 2 {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "unique" {
		built = run_pipeline(guarded(showcase_scenario(Forward), guard)) ? |_| EvidenceFailure
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "shared" {
		scenario_input = guarded(showcase_scenario(Forward), guard)
		first = run_pipeline(scenario_input) ? |_| EvidenceFailure
		second = run_pipeline(scenario_input) ? |_| EvidenceFailure
		if first.bytes != second.bytes {
			return Err(SharedInputDiverged)
		}
		Ok({ bytes: first.bytes, work: work_vector(first) })
	} else if mode == "share" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(guarded(share_scenario(scale), guard)) ? |_| EvidenceFailure
		check_sharing(built, scale, 1)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "title" {
		if scale < 1 or scale > 256 {
			return Err(InvalidScale)
		}
		built = run_pipeline(guarded(title_scenario(scale), guard)) ? |_| EvidenceFailure
		if KernelXmp.Packet.work(built.packet).title_escapes != scale {
			return Err(SharingDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The guard is always zero; folding it into one scene bound keeps the
## pipeline a runtime computation without changing any limit.
guarded : Scenario, U64 -> Scenario
guarded = |input, guard| {
	Scenario.{
		color_limits: input.color_limits,
		colors: input.colors,
		intent_profile: Color.ProfileId.from_index(input.intent_profile.index() + guard),
		metadata: input.metadata,
		scene: input.scene,
		semantics: input.semantics,
	}
}

## Every scenario must collapse its authored packaged-profile copies to one
## canonical profile that both the color spaces and the output intent share,
## and must lower exactly one metadata stream.
check_sharing : Built, U64, U64 -> Try({}, Gate4MetadataEvidence.EvidenceError)
check_sharing = |built, authored, canonical| {
	work = KernelForm.Plan.work(built.form_plan)
	if work.authored_profiles != authored or work.canonical_profiles != canonical {
		return Err(SharingDiverged)
	}
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	if structure_work.resources.profiles != canonical or structure_work.metadata_objects != 2 {
		return Err(SharingDiverged)
	}
	if structure_work.metadata_bytes != KernelXmp.Packet.work(built.packet).packet_bytes {
		return Err(SharingDiverged)
	}

	## The xref object must sit exactly one past the stored objects,
	## including the appended metadata stream and its length.
	plan = KernelGate4FormStructure.Plan.structure(built.structure)
	if KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)) != structure_work.objects + 1 {
		return Err(SharingDiverged)
	}
	Ok({})
}

## Numbered atomic rejections. Every attempt differs from a valid request in
## exactly one fact; each must fail with its distinct typed error.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4MetadataEvidence.EvidenceError)
run_negatives = |runtime_context| {
	if runtime_context != 1 {
		return Err(InvalidScale)
	}

	## Always zero at runtime, but derived from the runtime argument, so the
	## exercised rejections cannot be evaluated at compile time.
	guard = U64.mod_by(runtime_context, 2) - 1
	valid = { created: showcase_created, language: showcase_language, modified: showcase_modified, title: showcase_title }
	expect_metadata_rejection(1, { ..valid, language: "en_AU" }, |error| error == MalformedLanguageTag({ offset: 2 }))?
	expect_metadata_rejection(2, { ..valid, language: "en-au" }, |error| error == LanguageNotCanonicalCase({ offset: 3 }))?
	expect_metadata_rejection(3, { ..valid, language: "en-x-priv" }, |error| error == UnsupportedLanguageForm({ offset: 3 }))?
	expect_metadata_rejection(4, { ..valid, language: "" }, |error| error == EmptyLanguage)?
	expect_metadata_rejection(5, { ..valid, language: "en-AU-with-a-very-long-invalid-remainder-exceeding-sixty-four-bytes" }, |error| error == LanguageTooLong({ attempted: 67, limit: 64 }))?
	expect_metadata_rejection(6, { ..valid, title: "" }, |error| error == EmptyTitle)?
	expect_metadata_rejection(7, { ..valid, title: "Bad\u(0007)title" }, |error| error == InvalidTitleScalar({ offset: 3 }))?
	expect_metadata_rejection(8, { ..valid, created: Explicit("2026-02-30T00:00:00Z") }, |error| error == InvalidTimestamp({ field: Created, offset: 8 }))?
	expect_metadata_rejection(9, { ..valid, modified: Explicit("2026-08-18T09:30:00+10:00") }, |error| error == InvalidTimestamp({ field: Modified, offset: 25 }))?

	## 10: an oversized title rejects at the metadata bound, and the packet
	## bound independently rejects a packet larger than its budget.
	oversized = title_scenario(1200)
	expect_metadata_rejection(10, oversized.metadata, |error| error == TitleTooLong({ attempted: 2400, limit: 2048 }))?
	small_facts = {
		created: Omitted,
		language: showcase_language,
		modified: Omitted,
		title: showcase_title,
		title_escapes: { amps: 1, gts: 1, lts: 1 },
	}
	match KernelXmp.Packet.build(small_facts, 64 + guard) {
		Err(PacketTooLarge(_)) => {}
		_ => return Err(MissingRejection(11))
	}

	## 12-16: output-intent configuration rejections against the showcase
	## color store.
	store = showcase_scenario(Forward)
	expect_intent_rejection(
		12,
		{ profile: Color.ProfileId.from_index(0), registry_name: "https://example.com/registry" },
		KernelMetadata.srgb_condition_identifier,
		store.colors,
		|error| error == UnsupportedIntentRegistry,
	)?
	expect_intent_rejection(
		13,
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		"AdobeRGB1998",
		store.colors,
		|error| error == UnsupportedConditionIdentifier,
	)?
	expect_intent_rejection(
		14,
		{ profile: Color.ProfileId.from_index(7), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		store.colors,
		|error| error == IntentProfileOutOfRange({ attempted: 7, profiles: 2 }),
	)?
	altered_bytes = match KernelSrgbProfile.bytes.set(200 + guard, 7) {
		Ok(bytes) => bytes
		Err(OutOfBounds) => {
			crash "packaged profile mutation failed"
		}
	}
	altered_store = { ..store.colors, profiles: [{ ..KernelSrgbProfile.profile(0, 0), bytes: altered_bytes }] }
	expect_intent_rejection(
		15,
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		altered_store,
		|error| error == IntentProfileMismatch({ bytes_compared: 201, profile: 0 }),
	)?
	truncated_store = { ..store.colors, profiles: [{ ..KernelSrgbProfile.profile(0, 0), bytes: KernelSrgbProfile.bytes.sublist({ start: 0, len: 2000 }) }] }
	expect_intent_rejection(
		16,
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		truncated_store,
		|error| error == IntentProfileMismatch({ bytes_compared: 0, profile: 0 }),
	)?
	gray_store = { ..store.colors, profiles: [{ ..KernelSrgbProfile.profile(0, 0), components: One }] }
	expect_intent_rejection(
		17,
		{ profile: Color.ProfileId.from_index(0), registry_name: KernelMetadata.icc_registry_name },
		KernelMetadata.srgb_condition_identifier,
		gray_store,
		|error| error == IntentComponentMismatch({ expected: 3, profile: 0 }),
	)?

	## 18: the public facade rejects invalid metadata atomically with no
	## bytes; the typed error carries the exact validation fact.
	facade_title = if guard == 0 "Facade negative" else "guarded"
	facade_document = Pdf.document({ contents: [Pdf.paragraph("Facade negative")], language: "en-au", title: facade_title })
	match Pdf.to_bytes(facade_document) {
		Err(InvalidMetadata(LanguageNotCanonicalCase({ offset: 3 }))) => {}
		_ => return Err(MissingRejection(18))
	}

	carrier = run_pipeline(guarded(showcase_scenario(Forward), guard)) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [18, 0, carrier.bytes.len()] })
}

expect_metadata_rejection : U64, { created : Metadata.TimestampInput, language : Str, modified : Metadata.TimestampInput, title : Str }, (Metadata.Error -> Bool) -> Try({}, Gate4MetadataEvidence.EvidenceError)
expect_metadata_rejection = |index, input, matches| match KernelMetadata.validate(input, metadata_limits) {
	Err(error) => if matches(error) Ok({}) else Err(MissingRejection(index))
	Ok(_) => Err(MissingRejection(index))
}

expect_intent_rejection : U64, Color.OutputIntent, Str, Color.Store, (KernelMetadata.IntentError -> Bool) -> Try({}, Gate4MetadataEvidence.EvidenceError)
expect_intent_rejection = |index, intent, identifier, store, matches| match KernelMetadata.validate_intent(intent, identifier, store) {
	Err(error) => if matches(error) Ok({}) else Err(MissingRejection(index))
	Ok(_) => Err(MissingRejection(index))
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "metadata evidence index escaped"
	}
}

## The adversarial showcase, sharing checks, and atomic negatives hold under
## `roc test`; the harness re-runs them as compiled scenarios with exact
## allocation and work baselines.
expect match Gate4MetadataEvidence.scenario("showcase", 0) {
	Ok(result) => result.bytes.len() > 0 and list_at(result.work, 0) == 2 and list_at(result.work, 1) == 1
	Err(_) => False
}

expect match Gate4MetadataEvidence.scenario("share", 5) {
	Ok(result) => list_at(result.work, 0) == 5 and list_at(result.work, 1) == 1
	Err(_) => False
}

expect match Gate4MetadataEvidence.scenario("minimal", 0) {
	Ok(result) => list_at(result.work, 10) == 2
	Err(_) => False
}

expect match Gate4MetadataEvidence.scenario("title", 8) {
	Ok(result) => list_at(result.work, 11) == 8
	Err(_) => False
}

expect match Gate4MetadataEvidence.atomic_negatives(1) {
	Ok(result) => list_at(result.work, 0) == 18
	Err(_) => False
}

## The blank facade path carries the same facts: this pins the public
## structural kernel boundary the facade uses for empty documents.
expect {
	facts = {
		condition_identifier: KernelMetadata.srgb_condition_identifier,
		language: showcase_language,
		profile_bytes: KernelSrgbProfile.bytes,
		profile_components: 3,
		registry_name: KernelMetadata.icc_registry_name,
		xmp: Str.to_utf8("<?xpacket?>"),
	}
	plan = KernelStructure.build_blank_with_facts(1, A4, facts)?

	KernelStructure.Plan.object_count(plan) == 9
}
