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

## Gate 4 color and image leaf evidence.
##
## Every scenario authors validated color and image stores — the packaged
## ICCBased sRGB profile, calibrated grayscale, packed rasters with and
## without alpha, and a sanitized DCT stream — runs the whole canonical leaf
## pipeline (store validation, use derivation, the two resource-graph runs,
## derived leaf identity, canonical object planning, emission, sealing), and
## emits real PDF bytes plus the deterministic work vector.
##
## - `showcase` : one page pairing the packaged sRGB profile authored twice,
##                an `Srgb` and an equivalent `IccBased` declaration, a
##                duplicated calibrated-gray space, an RGB raster authored
##                compact and again padded under the twin sRGB space, a
##                gray-plus-alpha raster authored twice, and a 3-component
##                JPEG — every authored twin must collapse to one canonical
##                object while placements keep distinct ownership. The same
##                document is also authored in reversed dense-ID order and
##                must produce identical bytes.
## - `dedup xN`   : N byte-identical authored rasters collapse to one
##                  canonical image emitted once.
## - `distinct xN`: N distinct rasters stay N canonical images.
## - `unique`/`shared` : the ordinary one-shot ownership path versus the same
##                retained authored stores planned twice.
Gate4ColorImageEvidence :: [].{
	EvidenceError : [
		AdversarialOrderDiverged,
		DeduplicationDiverged,
		EvidenceFailure,
		InvalidScale,
		MissingRejection(U64),
		SharedInputDiverged,
	]

	scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	scenario = |mode, scale| run_scenario(mode, scale)

	## Atomic negative twins: each input differs from a valid store in exactly
	## one fact, every rejection is a distinct structured diagnostic, and no
	## partial plan or PDF byte escapes. The fixture emits only an unrelated
	## single-image document as its snapshot payload.
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

## The RGB showcase raster: four exact 8-bit primaries, row 0 on top.
rgb_pixels : List(U8)
rgb_pixels = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]

## The same pixels padded to an 8-byte row stride; compaction must give the
## padded twin the compact twin's identity.
rgb_pixels_padded : List(U8)
rgb_pixels_padded = [255, 0, 0, 0, 255, 0, 9, 9, 0, 0, 255, 255, 255, 255, 9, 9]

gray_pixels : List(U8)
gray_pixels = [0, 64, 128, 255]

alpha_pixels : List(U8)
alpha_pixels = [255, 255, 0, 0]

## A minimal deterministic baseline JPEG: 1x1, three 8-bit components, one
## all-ones quantization table, one-symbol DC and AC Huffman tables, and a
## single DC-only MCU, so every conforming decoder produces the exact flat
## value 128 per channel.
showcase_jpeg : {} -> List(U8)
showcase_jpeg = |_| {
	var $out = [0xff, 0xd8]
	$out = $out.concat([0xff, 0xdb, 0x00, 0x43, 0x00])
	$out = $out.concat(List.repeat(1, 64))
	$out = $out.concat([0xff, 0xc0, 0x00, 0x11, 8, 0, 1, 0, 1, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0])
	counts = [1].concat(List.repeat(0, 15))
	dc_table = [0x00].concat(counts).concat([0])
	ac_table = [0x10].concat(counts).concat([0])
	$out = $out.concat([0xff, 0xc4, 0x00, 0x26]).concat(dc_table).concat(ac_table)
	$out = $out.concat([0xff, 0xda, 0x00, 0x0c, 3, 1, 0x00, 2, 0x00, 3, 0x00, 0, 0x3f, 0])
	$out = $out.append(0x00)
	$out.concat([0xff, 0xd9])
}

## A gray single-component variant of the same baseline JPEG for the negative
## twins that need a valid starting stream.
gray_jpeg : {} -> List(U8)
gray_jpeg = |_| {
	var $out = [0xff, 0xd8]
	$out = $out.concat([0xff, 0xdb, 0x00, 0x43, 0x00])
	$out = $out.concat(List.repeat(1, 64))
	$out = $out.concat([0xff, 0xc0, 0x00, 0x0b, 8, 0, 1, 0, 1, 1, 1, 0x11, 0])
	counts = [1].concat(List.repeat(0, 15))
	dc_table = [0x00].concat(counts).concat([0])
	ac_table = [0x10].concat(counts).concat([0])
	$out = $out.concat([0xff, 0xc4, 0x00, 0x26]).concat(dc_table).concat(ac_table)
	$out = $out.concat([0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, 0])
	$out.concat([0xff, 0xd9])
}

showcase_color_limits : KernelColor.Limits
showcase_color_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count * 2,
	max_profiles: 2,
	max_spaces: 4,
	max_tags: KernelSrgbProfile.tag_count * 2,
})

showcase_image_limits : KernelImage.Limits
showcase_image_limits = KernelImage.Limits.make({
	max_decoded_bytes: 64,
	max_encoded_bytes: 256,
	max_height: 2,
	max_markers: 16,
	max_resources: 5,
	max_width: 2,
})

## Authored showcase images, addressed by logical index:
## 0 = compact RGB raster in the `Srgb` space; 1 = gray-plus-alpha raster in
## calibrated gray; 2 = the 3-component JPEG in the `IccBased` twin space;
## 3 = the padded RGB twin under the twin space; 4 = the gray-plus-alpha twin.
logical_image_payload : U64, [Forward, Reversed] -> [EncodedJpeg(Image.JpegSource), PackedPixels(Image.PackedRaster)]
logical_image_payload = |logical, direction| {
	space = |logical_space| Color.SpaceId.from_index(dense_space(logical_space, direction))
	if logical == 0 {
		PackedPixels({
			alpha: NoAlpha,
			color_space: space(1),
			dimensions: { height: 2, width: 2 },
			format: Rgb8,
			pixels: rgb_pixels,
			row_stride: 6,
		})
	} else if logical == 1 {
		PackedPixels({
			alpha: PackedAlpha({ bytes: alpha_pixels, row_stride: 2 }),
			color_space: space(0),
			dimensions: { height: 2, width: 2 },
			format: Gray8,
			pixels: gray_pixels,
			row_stride: 2,
		})
	} else if logical == 2 {
		EncodedJpeg({
			bytes: showcase_jpeg({}),
			color_space: space(2),
			orientation_policy: RequireDisplayReady,
		})
	} else if logical == 3 {
		PackedPixels({
			alpha: NoAlpha,
			color_space: space(2),
			dimensions: { height: 2, width: 2 },
			format: Rgb8,
			pixels: rgb_pixels_padded,
			row_stride: 8,
		})
	} else {
		PackedPixels({
			alpha: PackedAlpha({ bytes: alpha_pixels, row_stride: 2 }),
			color_space: space(3),
			dimensions: { height: 2, width: 2 },
			format: Gray8,
			pixels: gray_pixels,
			row_stride: 2,
		})
	}
}

showcase_image_count : U64
showcase_image_count = 5

showcase_space_count : U64
showcase_space_count = 4

showcase_profile_count : U64
showcase_profile_count = 2

dense_space : U64, [Forward, Reversed] -> U64
dense_space = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_space_count - 1 - logical
}

dense_image : U64, [Forward, Reversed] -> U64
dense_image = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_image_count - 1 - logical
}

dense_profile : U64, [Forward, Reversed] -> U64
dense_profile = |logical, direction| match direction {
	Forward => logical
	Reversed => showcase_profile_count - 1 - logical
}

## The showcase stores under one authored-ID direction. Authored twins are
## deliberate: the second profile is the packaged sRGB profile authored
## again, one space declares the same ICCBased sRGB through the twin profile,
## and another duplicates the calibrated gray, so normalization must collapse
## them without merging any placement fact. `Reversed` renumbers every
## profile, space, and image while describing the same logical document, so
## the canonical plan and the final bytes must not be able to tell the two
## apart.
showcase_stores : [Forward, Reversed] -> { colors : Color.Store, images : Image.SourceStore }
showcase_stores = |direction| {
	logical_space = |dense| match direction {
		Forward => dense
		Reversed => showcase_space_count - 1 - dense
	}
	var $spaces = List.with_capacity(showcase_space_count)
	var $dense = 0
	while $dense < showcase_space_count {
		logical = logical_space($dense)
		space = if logical == 0 or logical == 3 {
			cal_gray
		} else if logical == 1 {
			Srgb(Color.ProfileId.from_index(dense_profile(0, direction)))
		} else {
			IccBased({ components: Three, profile: Color.ProfileId.from_index(dense_profile(1, direction)) })
		}
		$spaces = $spaces.append({ id: Color.SpaceId.from_index($dense), space })
		$dense = $dense + 1
	}
	var $profiles = List.with_capacity(showcase_profile_count)
	var $profile = 0
	while $profile < showcase_profile_count {
		$profiles = $profiles.append(KernelSrgbProfile.profile($profile, $profile * KernelSrgbProfile.tag_count))
		$profile = $profile + 1
	}
	var $images = List.with_capacity(showcase_image_count)
	var $image = 0
	while $image < showcase_image_count {
		logical = match direction {
			Forward => $image
			Reversed => showcase_image_count - 1 - $image
		}
		$images = $images.append({ id: Image.Id.from_index($image), payload: logical_image_payload(logical, direction) })
		$image = $image + 1
	}
	{
		colors: { profiles: $profiles, spaces: $spaces, tags: KernelSrgbProfile.tags.concat(KernelSrgbProfile.tags) },
		images: { resources: $images },
	}
}

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
	objects = KernelGate4FormObjects.Plan.build(base, KernelForm.Plan.canonical_form_count(form_plan), 0, 8192) ? FormObjectFailure
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
		image_names: KernelForm.Plan.image_names(form_plan),
		streams: $streams,
	}
}

work_vector : Built -> List(U64)
work_vector = |built| {
	plan_work = KernelForm.Plan.work(built.form_plan)
	graph_work = KernelForm.Plan.graph_work(built.form_plan)
	color_work = KernelColor.Plan.work(built.colors)
	image_work = KernelImage.Plan.work(built.images)
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	content_work = KernelContent.Plan.work(built.content)
	[
		plan_work.authored_profiles,
		plan_work.canonical_profiles,
		plan_work.deduplicated_profiles,
		plan_work.authored_color_spaces,
		plan_work.canonical_color_spaces,
		plan_work.deduplicated_color_spaces,
		plan_work.authored_images,
		plan_work.canonical_images,
		plan_work.deduplicated_images,
		plan_work.leaf_digests,
		plan_work.copied_leaf_bytes,
		plan_work.leaf_recipe_bytes,
		color_work.bytes_checked,
		color_work.tags_checked,
		image_work.bytes_checked,
		image_work.markers_checked,
		image_work.rows_checked,
		graph_work.hashes,
		graph_work.bytes_hashed,
		graph_work.collision_entries,
		graph_work.equality_comparisons,
		graph_work.bytes_compared,
		graph_work.unique_payloads,
		graph_work.deduplicated_payloads,
		graph_work.retained_payload_bytes,
		graph_work.copied_payload_bytes,
		structure_work.resources.profiles,
		structure_work.resources.color_spaces,
		structure_work.resources.images,
		structure_work.resources.profile_bytes,
		structure_work.resources.raster_bytes,
		structure_work.resources.image_rows,
		structure_work.resources.soft_mask_rows,
		plan_work.dictionary_entries,
		plan_work.nested_dictionary_entries,
		content_work.image_placements,
		structure_work.dictionary_references,
		structure_work.objects,
		built.bytes.len(),
	]
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4ColorImageEvidence.EvidenceError)
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
	} else if mode == "dedup" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(grid_scenario(scale, Duplicated)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_images != 1 or work.deduplicated_images != scale - 1 {
			return Err(DeduplicationDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "distinct" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(grid_scenario(scale, Distinct)) ? |_| EvidenceFailure
		work = KernelForm.Plan.work(built.form_plan)
		if work.canonical_images != scale or work.deduplicated_images != 0 {
			return Err(DeduplicationDiverged)
		}
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else {
		Err(InvalidScale)
	}
}

## The showcase must physically share exactly the deduplicated leaves: two
## profiles collapse to one, four spaces to two, five images to three, and
## the padded raster twin shares the compact twin's canonical identity.
check_showcase_sharing : Built -> Try({}, Gate4ColorImageEvidence.EvidenceError)
check_showcase_sharing = |built| {
	work = KernelForm.Plan.work(built.form_plan)
	if work.authored_profiles != 2 or work.canonical_profiles != 1 or work.deduplicated_profiles != 1 {
		return Err(DeduplicationDiverged)
	}
	if work.authored_color_spaces != 4 or work.canonical_color_spaces != 2 or work.deduplicated_color_spaces != 2 {
		return Err(DeduplicationDiverged)
	}
	if work.authored_images != 5 or work.canonical_images != 3 or work.deduplicated_images != 2 {
		return Err(DeduplicationDiverged)
	}

	## The padded RGB twin and the compact RGB raster share one canonical
	## name; the two gray-plus-alpha twins share another.
	image_names = KernelForm.Plan.image_names(built.form_plan)
	if list_at(image_names, 0) != list_at(image_names, 3) or list_at(image_names, 1) != list_at(image_names, 4) {
		return Err(DeduplicationDiverged)
	}
	color_names = KernelForm.Plan.color_names(built.form_plan)
	if list_at(color_names, 0) != list_at(color_names, 3) or list_at(color_names, 1) != list_at(color_names, 2) {
		return Err(DeduplicationDiverged)
	}
	Ok({})
}

## One page interleaving meaningful and artifact paint over the deduplicated
## resources: the RGB raster (fragment), the background path in the duplicated
## calibrated space plus the gray-alpha raster (artifact), a form placing the
## padded RGB twin and filling in the ICCBased twin space (fragment), the
## JPEG (fragment), and the gray-alpha twin placed again as decoration.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	stores = showcase_stores(direction)
	image = |logical| Image.Id.from_index(dense_image(logical, direction))
	space = |logical| dense_space(logical, direction)
	page_commands = [
		DrawImage({ image: image(0), placement: rect(10000, 80000, 20000, 10000) }),
		DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(gray_value(32896, space(3))) }),
		DrawImage({ image: image(1), placement: rect(40000, 80000, 20000, 10000) }),
		PlaceForm({ form: Scene.FormId.from_index(0), transform: { a: unit(1000), b: unit(0), c: unit(0), d: unit(1000), e: unit(10000), f: unit(40000) } }),
		DrawImage({ image: image(2), placement: rect(70000, 80000, 10000, 10000) }),
		DrawImage({ image: image(4), placement: rect(40000, 60000, 20000, 10000) }),
	]
	form_commands = [
		DrawImage({ image: image(3), placement: rect(0, 0, 20000, 10000) }),
		DrawPath({ path: Scene.PathId.from_index(1), style: fill_with(rgb_value(16448, 16448, 49344, space(2))) }),
	]
	scene = {
		commands: page_commands,
		dash_lengths: [],
		groups: [
			{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
			{ commands: Semantics.Range.from_start_and_length(1, 2), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
			{ commands: Semantics.Range.from_start_and_length(3, 1), id: Scene.GroupId.from_index(2), owner: Fragment(Semantics.FragmentId.from_index(1)) },
			{ commands: Semantics.Range.from_start_and_length(4, 1), id: Scene.GroupId.from_index(3), owner: Fragment(Semantics.FragmentId.from_index(2)) },
			{ commands: Semantics.Range.from_start_and_length(5, 1), id: Scene.GroupId.from_index(4), owner: PageArtifact(Decoration) },
		],
		page_groups: [
			Scene.GroupId.from_index(0),
			Scene.GroupId.from_index(1),
			Scene.GroupId.from_index(2),
			Scene.GroupId.from_index(3),
			Scene.GroupId.from_index(4),
		],
		pages: [
			{
				boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
				id: Semantics.PageId.from_index(0),
				paint_order: Semantics.Range.from_start_and_length(0, 5),
				rotation: Rotate0,
			},
		],
		path_segments: [Rectangle(rect(10000, 10000, 30000, 10000)), Rectangle(rect(20000, 0, 10000, 10000))],
		paths: [
			{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) },
			{ id: Scene.PathId.from_index(1), segments: Semantics.Range.from_start_and_length(1, 1) },
		],
	}
	{
		color_limits: showcase_color_limits,
		colors: stores.colors,
		form_store: {
			commands: form_commands,
			forms: [{ bbox: rect(0, 0, 30000, 10000), commands: Semantics.Range.from_start_and_length(0, 2), id: Scene.FormId.from_index(0) }],
		},
		image_limits: showcase_image_limits,
		images: stores.images,
		scene,
		semantics: build_semantics(3, [1, 0, 2]),
	}
}

GridVariant := [Distinct, Duplicated]

## `scale` authored gray rasters placed once each in a watermark grid; the
## duplicated variant authors byte-identical rasters that must collapse to
## one canonical image, the distinct variant varies one pixel per raster.
grid_scenario : U64, GridVariant -> Scenario
grid_scenario = |scale, variant| {
	var $images = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		first_pixel = match variant {
			Duplicated => 0
			Distinct => $index.to_u8_wrap()
		}
		$images = $images.append({
			id: Image.Id.from_index($index),
			payload: PackedPixels({
				alpha: NoAlpha,
				color_space: Color.SpaceId.from_index(0),
				dimensions: { height: 2, width: 2 },
				format: Gray8,
				pixels: [first_pixel, 64, 128, 255],
				row_stride: 2,
			}),
		})
		$index = $index + 1
	}
	var $page_commands = [DrawPath({ path: Scene.PathId.from_index(0), style: fill_with(gray_value(8224, 0)) })]
	$index = 0
	while $index < scale {
		column = U64.mod_by($index, 10) * 10000
		row = U64.mod_by(U64.div_by($index, 10), 9) * 10000
		$page_commands = $page_commands.append(
			DrawImage({
				image: Image.Id.from_index($index),
				placement: rect(column.to_i64_wrap(), row.to_i64_wrap(), 8000, 8000),
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
		path_segments: [Rectangle(rect(0, 95000, 4000, 4000))],
		paths: [{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) }],
	}
	{
		color_limits: KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
		colors: {
			profiles: [],
			spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }],
			tags: [],
		},
		form_store: Scene.no_forms,
		image_limits: KernelImage.Limits.make({
			max_decoded_bytes: 4 * scale,
			max_encoded_bytes: 0,
			max_height: 2,
			max_markers: 0,
			max_resources: scale,
			max_width: 2,
		}),
		images: { resources: $images },
		scene,
		semantics: build_semantics(1, [0]),
	}
}

run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4ColorImageEvidence.EvidenceError)
run_negatives = |context| {
	if context != 1 {
		return Err(EvidenceFailure)
	}
	rejections = check_negatives(context)?
	carrier = run_pipeline(grid_scenario(context, Duplicated)) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [rejections, 0, carrier.bytes.len()] })
}

valid_single_profile_store : Color.Store
valid_single_profile_store = {
	profiles: [KernelSrgbProfile.profile(0, 0)],
	spaces: [
		{ id: Color.SpaceId.from_index(0), space: cal_gray },
		{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(0)) },
	],
	tags: KernelSrgbProfile.tags,
}

single_profile_limits : KernelColor.Limits
single_profile_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count,
	max_profiles: 1,
	max_spaces: 2,
	max_tags: KernelSrgbProfile.tag_count,
})

expect_color_rejection : U64, Color.Store, KernelColor.Limits, (KernelColor.Error -> Bool) -> Try({}, Gate4ColorImageEvidence.EvidenceError)
expect_color_rejection = |ordinal, store, limits, matches| {
	match KernelColor.Plan.build(store, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

expect_image_rejection : U64, Image.SourceStore, KernelImage.Limits, (KernelImage.Error -> Bool) -> Try({}, Gate4ColorImageEvidence.EvidenceError)
expect_image_rejection = |ordinal, sources, limits, matches| {
	colors = KernelColor.Plan.build(valid_single_profile_store, single_profile_limits) ? |_| MissingRejection(ordinal)
	match KernelImage.Plan.build(sources, colors, limits) {
		Err(error) => if matches(error) Ok({}) else Err(MissingRejection(ordinal))
		Ok(_) => Err(MissingRejection(ordinal))
	}
}

negative_image_limits : KernelImage.Limits
negative_image_limits = KernelImage.Limits.make({
	max_decoded_bytes: 64,
	max_encoded_bytes: 256,
	max_height: 2,
	max_markers: 16,
	max_resources: 2,
	max_width: 2,
})

gray_raster_source : Image.SourceResource
gray_raster_source = {
	id: Image.Id.from_index(0),
	payload: PackedPixels({
		alpha: NoAlpha,
		color_space: Color.SpaceId.from_index(0),
		dimensions: { height: 2, width: 2 },
		format: Gray8,
		pixels: gray_pixels,
		row_stride: 2,
	}),
}

patched_profile_bytes : U64, U8 -> List(U8)
patched_profile_bytes = |offset, value| list_set(KernelSrgbProfile.bytes, offset, value)

profile_with_bytes : List(U8) -> Color.IccProfile
profile_with_bytes = |bytes| { bytes, components: Three, id: Color.ProfileId.from_index(0), tags: Semantics.Range.from_start_and_length(0, KernelSrgbProfile.tag_count), version: IccV2 }

store_with_profile : Color.IccProfile -> Color.Store
store_with_profile = |profile| { ..valid_single_profile_store, profiles: [profile] }

## Each negative twin below changes exactly one fact of a valid store and
## must fail with its own structured diagnostic before any plan or byte
## escapes.
check_negatives : U64 -> Try(U64, Gate4ColorImageEvidence.EvidenceError)
check_negatives = |context| {

	## 1: a truncated ICC payload.
	truncated_profile = {
		..profile_with_bytes(KernelSrgbProfile.bytes.sublist({ len: 100, start: 0 })),
		tags: Semantics.Range.from_start_and_length(0, 0),
	}
	expect_color_rejection(
		1,
		{ ..store_with_profile(truncated_profile), tags: [] },
		single_profile_limits,
		|error| match error {
			ProfileTooShort({ bytes: 100, profile: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 2: a declared profile size disagreeing with the payload.
	expect_color_rejection(
		2,
		store_with_profile(profile_with_bytes(patched_profile_bytes(3, 0xd1))),
		single_profile_limits,
		|error| match error {
			DeclaredSizeMismatch({ actual: 3024, declared: 3025, profile: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 3: a broken `acsp` signature.
	expect_color_rejection(
		3,
		store_with_profile(profile_with_bytes(patched_profile_bytes(36, 0))),
		single_profile_limits,
		|error| match error {
			InvalidIccSignature({ profile: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 4: a profile version disagreeing with its declared version.
	expect_color_rejection(
		4,
		store_with_profile(profile_with_bytes(patched_profile_bytes(8, 4))),
		single_profile_limits,
		|error| match error {
			UnsupportedIccVersion({ profile: 0, version: 4 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 5: a gray device space under a three-component declaration.
	gray_header = list_set(list_set(list_set(list_set(KernelSrgbProfile.bytes, 16, 0x47), 17, 0x52), 18, 0x41), 19, 0x59)
	expect_color_rejection(
		5,
		store_with_profile(profile_with_bytes(gray_header)),
		single_profile_limits,
		|error| match error {
			ComponentMismatch({ profile: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 6: a tag record disagreeing with the profile's tag table.
	first_tag = list_at(KernelSrgbProfile.tags, 0)
	shifted_tag = { ..first_tag, bytes: Semantics.Range.from_start_and_length(first_tag.bytes.start() + 1, first_tag.bytes.length()) }
	expect_color_rejection(
		6,
		{ ..valid_single_profile_store, tags: list_set(KernelSrgbProfile.tags, 0, shifted_tag) },
		single_profile_limits,
		|error| match error {
			TagRecordMismatch({ profile: 0, tag: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 7: a tag no profile owns.
	expect_color_rejection(
		7,
		{ ..valid_single_profile_store, tags: KernelSrgbProfile.tags.append(first_tag) },
		KernelColor.Limits.make({
			max_icc_bytes: KernelSrgbProfile.byte_count,
			max_profiles: 1,
			max_spaces: 2,
			max_tags: KernelSrgbProfile.tag_count + 1,
		}),
		|error| match error {
			OrphanTag({ tag: 16 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 8: the ICC byte budget.
	expect_color_rejection(
		8,
		valid_single_profile_store,
		KernelColor.Limits.make({
			max_icc_bytes: KernelSrgbProfile.byte_count - 1,
			max_profiles: 1,
			max_spaces: 2,
			max_tags: KernelSrgbProfile.tag_count,
		}),
		|error| match error {
			LimitExceeded({ attempted: _, dimension: IccBytes, limit: _ }) => Bool.True
			_ => Bool.False
		},
	)?

	## 9: an ICCBased space whose component count disagrees with its profile.
	expect_color_rejection(
		9,
		{
			..valid_single_profile_store,
			spaces: [
				{ id: Color.SpaceId.from_index(0), space: cal_gray },
				{ id: Color.SpaceId.from_index(1), space: IccBased({ components: One, profile: Color.ProfileId.from_index(0) }) },
			],
		},
		single_profile_limits,
		|error| match error {
			ComponentMismatch({ profile: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 10: a space referencing a missing profile.
	expect_color_rejection(
		10,
		{
			..valid_single_profile_store,
			spaces: [
				{ id: Color.SpaceId.from_index(0), space: cal_gray },
				{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(7)) },
			],
		},
		single_profile_limits,
		|error| match error {
			IndexOutOfRange({ available: 1, index: 7 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 11: an uncharacterized calibrated white point.
	expect_color_rejection(
		11,
		{
			..valid_single_profile_store,
			spaces: [
				{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: zero_black, white_point: { x: 950000, y: 999999, z: 1089000 } }) },
				{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(0)) },
			],
		},
		single_profile_limits,
		|error| match error {
			InvalidCalibratedGray({ space: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 12: a forbidden JPEG marker inside the stream.
	bad_marker = list_set(gray_jpeg({}), 3, 0xd8)
	expect_image_rejection(
		12,
		{ resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: bad_marker, color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] },
		negative_image_limits,
		|error| match error {
			InvalidJpegMarker({ marker: 0xd8, offset: 2, resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 13: a JPEG segment length escaping the stream.
	bad_length = list_set(gray_jpeg({}), 4, 0xff)
	expect_image_rejection(
		13,
		{ resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: bad_length, color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] },
		negative_image_limits,
		|error| match error {
			InvalidJpegSegment({ offset: 2, resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 14: an unsupported JPEG component count.
	two_components = list_set(gray_jpeg({}), 80, 2)
	expect_image_rejection(
		14,
		{ resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: two_components, color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] },
		negative_image_limits,
		|error| match error {
			UnsupportedJpegComponents({ components: 2, resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 15: a conflicting EXIF orientation that would need a pixel transform.
	rotated = with_exif_orientation(gray_jpeg({}), 6)
	expect_image_rejection(
		15,
		{ resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: rotated, color_space: Color.SpaceId.from_index(0), orientation_policy: ApplyBeforePlacement }) }] },
		negative_image_limits,
		|error| match error {
			OrientationRequiresTransform({ resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 16: a three-component JPEG declared in a gray space.
	expect_image_rejection(
		16,
		{ resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: showcase_jpeg({}), color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] },
		negative_image_limits,
		|error| match error {
			ColorComponentMismatch({ resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 17: an RGB raster declared in a gray space.
	expect_image_rejection(
		17,
		{ resources: [with_raster(|raster| { ..raster, format: Rgb8, pixels: rgb_pixels, row_stride: 6 })] },
		negative_image_limits,
		|error| match error {
			ColorComponentMismatch({ resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 18: a row stride below the packed row width.
	expect_image_rejection(
		18,
		{ resources: [with_raster(|raster| { ..raster, row_stride: 1 })] },
		negative_image_limits,
		|error| match error {
			InvalidRowStride({ minimum: 2, resource: 0, stride: 1 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 19: a pixel payload disagreeing with stride times height.
	expect_image_rejection(
		19,
		{ resources: [with_raster(|raster| { ..raster, pixels: gray_pixels.append(0) })] },
		negative_image_limits,
		|error| match error {
			DecodedLengthMismatch({ actual: 5, expected: 4, resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 20: an alpha plane disagreeing with its declared stride.
	expect_image_rejection(
		20,
		{ resources: [with_raster(|raster| { ..raster, alpha: PackedAlpha({ bytes: [255, 255, 0], row_stride: 2 }) })] },
		negative_image_limits,
		|error| match error {
			DecodedLengthMismatch({ actual: 3, expected: 4, resource: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 21: zero image dimensions.
	expect_image_rejection(
		21,
		{ resources: [with_raster(|raster| { ..raster, dimensions: { height: 2, width: 0 } })] },
		negative_image_limits,
		|error| match error {
			InvalidDimensions({ height: 2, resource: 0, width: 0 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 22: the decoded byte budget.
	expect_image_rejection(
		22,
		{ resources: [gray_raster_source] },
		KernelImage.Limits.make({ max_decoded_bytes: 3, max_encoded_bytes: 0, max_height: 2, max_markers: 0, max_resources: 1, max_width: 2 }),
		|error| match error {
			LimitExceeded({ attempted: 4, dimension: DecodedBytes, limit: 3 }) => Bool.True
			_ => Bool.False
		},
	)?

	## 23: an authored profile no color space references is unreachable.
	unreferenced = grid_with_colors(
		context,
		{
			profiles: [KernelSrgbProfile.profile(0, 0)],
			spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }],
			tags: KernelSrgbProfile.tags,
		},
		KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 1, max_tags: KernelSrgbProfile.tag_count }),
	)
	unreachable_rejected = match build_facts_for(unreferenced) {
		Err(Graph(UnreachableResource(_))) => Bool.True
		_ => Bool.False
	}
	if !unreachable_rejected {
		return Err(MissingRejection(23))
	}

	## 24: the canonical payload budget is enforced during the identity run.
	tight = KernelForm.Limits.make({
		graph: { ..graph_limits, max_payload_bytes: 8 },
		max_recipe_bytes: 4194304,
	})
	payload_rejected = match build_plan_with_limits(grid_scenario(context, Duplicated), tight) {
		Err(FormPlanFailure(Graph(PayloadByteLimitExceeded({ attempted: _, limit: 8 })))) => Bool.True
		_ => Bool.False
	}
	if !payload_rejected {
		return Err(MissingRejection(24))
	}

	Ok(context * 24)
}

with_raster : (Image.PackedRaster -> Image.PackedRaster) -> Image.SourceResource
with_raster = |transform| {
	base = {
		alpha: NoAlpha,
		color_space: Color.SpaceId.from_index(0),
		dimensions: { height: 2, width: 2 },
		format: Gray8,
		pixels: gray_pixels,
		row_stride: 2,
	}
	{ id: Image.Id.from_index(0), payload: PackedPixels(transform(base)) }
}

## Splices a minimal EXIF APP1 segment carrying one orientation entry into a
## baseline JPEG immediately after SOI.
with_exif_orientation : List(U8), U8 -> List(U8)
with_exif_orientation = |base, orientation| {
	exif = [
		0xff,
		0xe1,
		0x00,
		0x22,
		0x45,
		0x78,
		0x69,
		0x66,
		0x00,
		0x00,
		0x49,
		0x49,
		0x2a,
		0x00,
		0x08,
		0x00,
		0x00,
		0x00,
		0x01,
		0x00,
		0x12,
		0x01,
		0x03,
		0x00,
		0x01,
		0x00,
		0x00,
		0x00,
		orientation,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
	]
	[0xff, 0xd8].concat(exif).concat(base.sublist({ len: base.len() - 2, start: 2 }))
}

## A grid scenario whose color store is replaced wholesale, for the
## graph-boundary negatives.
grid_with_colors : U64, Color.Store, KernelColor.Limits -> Scenario
grid_with_colors = |scale, colors, color_limits| {
	base = grid_scenario(scale, Duplicated)
	{ ..base, color_limits, colors }
}

build_facts_for : Scenario -> Try(KernelForm.Facts, KernelForm.Error)
build_facts_for = |input| {
	resources = KernelScene.Resources.with_forms({
		color_spaces: input.colors.spaces.len(),
		forms: input.form_store.forms.len(),
		images: input.images.resources.len(),
		text_runs: 0,
	})
	form_scene = KernelScene.FormPlan.build(input.scene, input.form_store, resources, scene_limits, form_scene_limits) ? |_| ArithmeticOverflow
	colors = KernelColor.Plan.build(input.colors, input.color_limits) ? |_| ArithmeticOverflow
	images = KernelImage.Plan.build(input.images, colors, input.image_limits) ? |_| ArithmeticOverflow
	KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, form_limits)
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
	facts = KernelForm.Facts.build(form_scene, { colors, font_count: 0, images }, NoTextStore, form_limits) ? FactsFailure
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	plan = KernelForm.Plan.build(form_scene, facts, { colors, fonts: [], images }, NoText, tagged, limits) ? FormPlanFailure
	Ok(plan)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 color-image evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "Gate 4 color-image evidence update escaped"
	}
}

## The showcase deduplicates two profiles into one, four color spaces into
## two, and five images into three while both authored orders emit identical
## bytes.
expect {
	result = Gate4ColorImageEvidence.scenario("showcase", 0)?
	result.work.get(0) == Ok(2) and result.work.get(1) == Ok(1) and result.work.get(3) == Ok(4) and result.work.get(4) == Ok(2) and result.work.get(6) == Ok(5) and result.work.get(7) == Ok(3)
}

## Byte-identical authored rasters collapse to one canonical emitted image.
expect {
	result = Gate4ColorImageEvidence.scenario("dedup", 5)?
	result.work.get(7) == Ok(1) and result.work.get(8) == Ok(4) and result.work.get(28) == Ok(1)
}

## Distinct rasters stay distinct canonical images.
expect {
	result = Gate4ColorImageEvidence.scenario("distinct", 5)?
	result.work.get(7) == Ok(5) and result.work.get(8) == Ok(0) and result.work.get(28) == Ok(5)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4ColorImageEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(24) and result.work.get(1) == Ok(0)
}
