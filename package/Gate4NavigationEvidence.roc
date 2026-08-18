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
import KernelNavigation
import KernelObject
import KernelPdfFont
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelStructure
import KernelTagged
import Layout
import Pdf
import Scene
import Semantics

## Gate 4 navigation and link-annotation evidence.
##
## Every positive scenario authors typed navigation facts (named internal
## destinations pairing a semantic structure target with an explicit layout
## anchor occurrence, URI and internal GoTo link annotations with explicit
## rectangles and quadrilaterals, outline entries in authored preorder, and
## page-label ranges), runs the whole canonical Gate 4 pipeline with
## navigation, and emits real PDF bytes plus the deterministic work vector.
##
## - `showcase`  : two pages, two named destinations, a URI link, a
##                 two-quad fragmented internal link, an internal link with a
##                 normal appearance form, a nested outline with mixed open
##                 state, and two page-label ranges; destination authoring
##                 order reversed must produce identical bytes.
## - `annots xN` : N one-quad URI links on one page with the keyboard order
##                 authored fully reversed, isolating per-annotation work.
## - `quads xN`  : one link fragmented into N quadrilaterals.
## - `share xN`  : N internal links sharing one named destination.
## - `appearance xN` : N links sharing one canonical appearance form without
##                 sharing occurrences or ownership.
## - `outline_deep xN` / `outline_wide xN` : an N-deep chain and an N-wide
##                 sibling list with alternating open state.
## - `names xN`  : N named destinations authored in reverse byte order.
## - `labels xN` : N page-label ranges over N pages.
## - `unique`/`retained` : the one-shot ownership path versus the same
##                 retained authored input planned twice.
Gate4NavigationEvidence :: [].{
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

gray_value : U16 -> Color.Value
gray_value = |level| { channels: Gray(level), space: Color.SpaceId.from_index(0) }

fill_with : Color.Value -> Scene.PathStyle
fill_with = |color| { fill: SolidFill({ color, rule: Nonzero }), stroke: NoStroke }

graph_limits : KernelForm.Limits
graph_limits = KernelForm.Limits.make({
	graph: {
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
		max_roots: 16,
		max_topological_work: 1048576,
	},
	max_mask_depth: 4,
	max_opacity_depth: 64,
	max_recipe_bytes: 4194304,
})

scene_limits : KernelScene.Limits
scene_limits = KernelScene.Limits.make({
	max_commands: 65536,
	max_dash_lengths: 0,
	max_graphics_depth: 512,
	max_groups: 4096,
	max_pages: 128,
	max_path_segments: 4096,
	max_paths: 1024,
})

form_scene_limits : KernelScene.FormLimits
form_scene_limits = KernelScene.FormLimits.make({ max_form_commands: 65536, max_forms: 64 })

paint_limits : KernelScene.PaintLimits
paint_limits = KernelScene.PaintLimits.make({ max_pattern_commands: 0, max_patterns: 0, max_shading_stops: 0, max_shadings: 0 })

content_limits : KernelContent.Limits
content_limits = KernelContent.Limits.make({ max_content_bytes: 1048576, max_content_streams: 128 })

object_limits : KernelObject.Limits
object_limits = {
	max_array_items: 65536,
	max_byte_string_bytes: 65536,
	max_byte_strings: 4096,
	max_dictionary_entries: 65536,
	max_direct_depth: 8,
	max_name_bytes: 65536,
	max_names: 8192,
	max_objects: 8192,
	max_payload_bytes: 2097152,
	max_payloads: 4096,
	max_streams: 4096,
	max_text_string_bytes: 65536,
	max_text_strings: 4096,
	max_values: 262144,
}

structure_limits : KernelGate4FormStructure.Limits
structure_limits = KernelGate4FormStructure.Limits.make({
	font_limits: KernelPdfFont.Limits.make({ max_to_unicode_bytes: 0, max_unicode_mappings: 0, max_unicode_scalars: 0 }),
	object_limits,
})

navigation_limits : U64 -> KernelNavigation.Limits
navigation_limits = |guard| KernelNavigation.Limits.make({
	max_annotations: 512 + guard,
	max_description_bytes: 256,
	max_destinations: 256,
	max_label_prefix_bytes: 32,
	max_label_ranges: 128,
	max_name_bytes: 64,
	max_outline_depth: 32,
	max_outline_entries: 256,
	max_outline_title_bytes: 256,
	max_quads: 4096,
	max_uri_bytes: 512,
})

semantic_limits : Semantics.Store -> KernelSemantics.Limits
semantic_limits = |store| KernelSemantics.Limits.make({
	max_attributes: 0,
	max_content_spine: store.content_spine.len(),
	max_fragments: store.fragments.len(),
	max_namespaces: 1,
	max_nodes: store.nodes.len(),
	max_occurrences: store.occurrences.len(),
	max_semantic_depth: 4,
})

## One semantic/scene block: a plain paragraph or a link (a P wrapper
## containing a Link node), painted as one rectangle fragment per listed
## page.
BlockSpec := [
	LinkBlock({ annotations : U64, pages : List(U64) }),
	Paragraph({ pages : List(U64) }),
]

spec_pages : BlockSpec -> List(U64)
spec_pages = |spec| match spec {
	LinkBlock({ annotations: _, pages }) => pages
	Paragraph({ pages }) => pages
}

## Deterministic fragment geometry: fragment `slot` on its page paints the
## rectangle at row `slot % 6`, and the anchor rectangle is the painted
## rectangle.
fragment_rect : U64 -> Layout.Rect
fragment_rect = |slot| {
	row = U64.mod_by(slot, 6)
	rect(10000, 80000 - (row * 12000).to_i64_wrap(), 60000, 10000)
}

NavStore := {
	anchor_rects : List(KernelNavigation.AnchorRect),
	block_occurrences : List(Semantics.OccurrenceId),
	block_nodes : List(Semantics.NodeId),
	scene : Scene.Store,
	semantics : Semantics.Store,
}

## Build the semantic store, scene store, and per-fragment anchor rectangles
## for a list of block specs over `page_count` pages. Fragments are appended
## per block in page order; every fragment paints exactly one rectangle.
build_stores : U64, List(BlockSpec) -> NavStore
build_stores = |page_count, specs| {
	var $nodes = []
	var $spine = []
	var $occurrences = []
	var $fragments = []
	var $annotations = []
	var $block_nodes = []
	var $block_occurrences = []
	var $commands = []
	var $groups = []
	var $segments = []
	var $paths = []
	var $anchor_rects = []
	var $page_group_lists = List.repeat([], page_count)
	var $next_node = 1
	var $next_occurrence = 0
	var $next_fragment = 0
	var $next_annotation = 0
	var $logical = 0
	var $root_children = []
	var $spec_index = 0

	## Root span placeholder: the root's children are appended first so the
	## root's content range is (0, specs).
	while $spec_index < specs.len() {
		top_node = match list_at(specs, $spec_index) {
			Paragraph(_) => $next_node + top_offset(specs, $spec_index)
			LinkBlock(_) => $next_node + top_offset(specs, $spec_index)
		}
		_ = top_node
		$spec_index = $spec_index + 1
	}

	## First pass: compute each spec's top node index so the root span can be
	## written before the block spans.
	var $top_nodes = []
	var $node_cursor = 1
	$spec_index = 0
	while $spec_index < specs.len() {
		$top_nodes = $top_nodes.append($node_cursor)
		$node_cursor = $node_cursor + match list_at(specs, $spec_index) {
			Paragraph(_) => 1
			LinkBlock(_) => 2
		}
		$spec_index = $spec_index + 1
	}
	$spec_index = 0
	while $spec_index < specs.len() {
		$root_children = $root_children.append(ChildNode(Semantics.NodeId.from_index(list_at($top_nodes, $spec_index))))
		$spec_index = $spec_index + 1
	}
	$spine = $root_children

	$spec_index = 0
	while $spec_index < specs.len() {
		spec = list_at(specs, $spec_index)
		pages = spec_pages(spec)
		occurrence = $next_occurrence
		$next_occurrence = $next_occurrence + 1
		$block_occurrences = $block_occurrences.append(Semantics.OccurrenceId.from_index(occurrence))

		## Fragments and painted groups, one per listed page.
		var $page_edge = 0
		while $page_edge < pages.len() {
			page = list_at(pages, $page_edge)
			slot = $next_fragment
			geometry = fragment_rect(slot)
			$segments = $segments.append(Rectangle(geometry))
			$paths = $paths.append({ id: Scene.PathId.from_index(slot), segments: Semantics.Range.from_start_and_length(slot, 1) })
			$commands = $commands.append(DrawPath({ path: Scene.PathId.from_index(slot), style: fill_with(gray_value(24672)) }))
			$groups = $groups.append({ commands: Semantics.Range.from_start_and_length(slot, 1), id: Scene.GroupId.from_index(slot), owner: Fragment(Semantics.FragmentId.from_index(slot)) })
			$page_group_lists = list_set($page_group_lists, page, list_at($page_group_lists, page).append(Scene.GroupId.from_index(slot)))
			$fragments = $fragments.append({
				content_stream: Semantics.ContentStreamId.from_index(page),
				continuation_index: $page_edge,
				id: Semantics.FragmentId.from_index(slot),
				occurrence: Semantics.OccurrenceId.from_index(occurrence),
				page: Semantics.PageId.from_index(page),
				source_range: ByteRange(empty_range),
			})
			$anchor_rects = $anchor_rects.append(AnchorAt(geometry))
			$next_fragment = $next_fragment + 1
			$page_edge = $page_edge + 1
		}
		$occurrences = $occurrences.append({
			fragments: empty_range,
			id: Semantics.OccurrenceId.from_index(occurrence),
			language: Inherited,
			source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(empty_range)),
			text_properties: empty_range,
		})

		match spec {
			Paragraph(_) => {
				node = $next_node
				start = $spine.len()
				$spine = $spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index(occurrence)))
				$nodes = $nodes.append(make_node(node, ParentNode(Semantics.NodeId.from_index(0)), "P", Semantics.Range.from_start_and_length(start, 1)))
				$block_nodes = $block_nodes.append(Semantics.NodeId.from_index(node))
				$next_node = $next_node + 1
			}
			LinkBlock({ annotations, pages: _ }) => {
				wrapper = $next_node
				link_node = wrapper + 1
				wrapper_start = $spine.len()
				$spine = $spine.append(ChildNode(Semantics.NodeId.from_index(link_node)))
				link_start = $spine.len()
				$spine = $spine.append(ContentOccurrence(Semantics.OccurrenceId.from_index(occurrence)))
				var $slot = 0
				while $slot < annotations {
					$spine = $spine.append(AnnotationOccurrence(Semantics.AnnotationId.from_index($next_annotation)))
					$annotations = $annotations.append({
						id: Semantics.AnnotationId.from_index($next_annotation),
						logical_order: $logical,
						owner: Semantics.NodeId.from_index(link_node),
					})
					$next_annotation = $next_annotation + 1
					$logical = $logical + 1
					$slot = $slot + 1
				}
				$nodes = $nodes.append(make_node(wrapper, ParentNode(Semantics.NodeId.from_index(0)), "P", Semantics.Range.from_start_and_length(wrapper_start, 1)))
				$nodes = $nodes.append(make_node(link_node, ParentNode(Semantics.NodeId.from_index(wrapper)), "Link", Semantics.Range.from_start_and_length(link_start, 1 + annotations)))
				$block_nodes = $block_nodes.append(Semantics.NodeId.from_index(link_node))
				$next_node = $next_node + 2
			}
		}
		$spec_index = $spec_index + 1
	}

	## Scene pages: paint order concatenates each page's group list.
	var $page_groups = []
	var $pages = []
	var $page_index = 0
	while $page_index < page_count {
		start = $page_groups.len()
		$page_groups = $page_groups.concat(list_at($page_group_lists, $page_index))
		$pages = $pages.append({
			boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box },
			id: Semantics.PageId.from_index($page_index),
			paint_order: Semantics.Range.from_start_and_length(start, $page_groups.len() - start),
			rotation: Rotate0,
		})
		$page_index = $page_index + 1
	}

	root = make_node(0, DocumentRoot, "Document", Semantics.Range.from_start_and_length(0, specs.len()))
	all_nodes = [root].concat($nodes)
	{
		anchor_rects: $anchor_rects,
		block_nodes: $block_nodes,
		block_occurrences: $block_occurrences,
		scene: {
			commands: $commands,
			dash_lengths: [],
			groups: $groups,
			page_groups: $page_groups,
			pages: $pages,
			path_segments: $segments,
			paths: $paths,
		},
		semantics: {
			annotations: $annotations,
			assertions: [],
			attribute_roles: [],
			attributes: [],
			content_spine: $spine,
			contextual_artifacts: [],
			document_root: Semantics.NodeId.from_index(0),
			element_identifiers: [],
			fragments: $fragments,
			mathml_subtrees: [],
			namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
			nodes: all_nodes,
			non_text_sources: [[]],
			occurrence_fragments: [],
			occurrences: $occurrences,
			relationships: [],
			role_mappings: [],
			text_properties: [],
			text_sources: [],
		},
	}
}

top_offset : List(BlockSpec), U64 -> U64
top_offset = |_specs, _index| 0

make_node : U64, Semantics.NodeParent, Str, Semantics.Range -> Semantics.Node
make_node = |index, parent, role, content| {
	attributes: empty_range,
	content,
	element_identifier: NoElementIdentifier,
	id: Semantics.NodeId.from_index(index),
	language: Inherited,
	parent,
	role: { local_name: role, namespace: Semantics.NamespaceId.from_index(0) },
	structure_element: Semantics.StructureElementId.from_index(index),
	text_properties: empty_range,
}

## One quad per fragment of the annotation's page, in run order: the quads
## are the exact painted fragment rectangles.
quad_of : Layout.Rect -> KernelNavigation.Quad
quad_of = |geometry| {
	x_left: geometry.origin.x,
	x_right: unit(geometry.origin.x.raw() + geometry.size.width.raw()),
	y_bottom: geometry.origin.y,
	y_top: unit(geometry.origin.y.raw() + geometry.size.height.raw()),
}

union_of : List(KernelNavigation.Quad) -> Layout.Rect
union_of = |quads| {
	first = list_at(quads, 0)
	var $x_left = first.x_left.raw()
	var $x_right = first.x_right.raw()
	var $y_bottom = first.y_bottom.raw()
	var $y_top = first.y_top.raw()
	var $index = 1
	while $index < quads.len() {
		quad = list_at(quads, $index)
		$x_left = I64.min($x_left, quad.x_left.raw())
		$x_right = I64.max($x_right, quad.x_right.raw())
		$y_bottom = I64.min($y_bottom, quad.y_bottom.raw())
		$y_top = I64.max($y_top, quad.y_top.raw())
		$index = $index + 1
	}
	rect($x_left, $y_bottom, $x_right - $x_left, $y_top - $y_bottom)
}

Scenario := {
	forms : Scene.FormStore,
	navigation : KernelNavigation.Input,
	stores : NavStore,
}

Built := {
	bytes : List(U8),
	form_plan : KernelForm.Plan,
	navigation_work : KernelNavigation.Work,
	store : KernelNavigation.Store,
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
	NavigationFailure(Document.NavigationError),
	ObjectFailure(KernelGate2Objects.Error),
	ResourceUseFailure(KernelResourceUse.Error),
	SemanticFailure(KernelSemantics.Error),
	StructureFailure(KernelGate4FormStructure.Error),
	TaggedFailure(KernelTagged.Error),
]

evidence_colors : Color.Store
evidence_colors = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: cal_gray }],
	tags: [],
}

no_images : KernelColor.Plan -> Try(KernelImage.Plan, BuildFailure)
no_images = |colors| {
	plan = KernelImage.Plan.build(
		{ resources: [] },
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ? ImageFailure
	Ok(plan)
}

## The canonical Gate 4 pipeline with navigation: the navigation store
## validates once before planning, appearance references join both resource
## graph runs as closure uses, and the structure builder resolves the paired
## destination targets and lowers every navigation object.
run_pipeline : Scenario, U64 -> Try(Built, BuildFailure)
run_pipeline = |input, guard| {
	stores = input.stores
	semantic = KernelSemantics.Plan.build_navigation(
		stores.semantics,
		stores.scene.pages.len(),
		stores.scene.pages.len(),
		semantic_limits(stores.semantics),
	) ? SemanticFailure
	navigation = KernelNavigation.validate(
		input.navigation,
		{
			forms: input.forms.forms.len(),
			nodes: stores.semantics.nodes.len(),
			occurrences: stores.semantics.occurrences.len(),
			pages: stores.scene.pages.len(),
			semantic_annotations: stores.semantics.annotations.len(),
		},
		navigation_limits(guard),
	) ? NavigationFailure
	var $appearances = []
	var $appearance_scan = 0
	while $appearance_scan < navigation.store.annotations.len() {
		annotation = list_at(navigation.store.annotations, $appearance_scan)
		match annotation.appearance {
			NoAppearance => {}
			NormalAppearance(form) => {
				$appearances = $appearances.append({ form: form.index(), page: annotation.page.index() })
			}
		}
		$appearance_scan = $appearance_scan + 1
	}
	resources = KernelScene.Resources.with_forms({
		color_spaces: 1,
		forms: input.forms.forms.len(),
		images: 0,
		text_runs: 0,
	})
	paint_scene = KernelScene.PaintPlan.build(stores.scene, input.forms, Scene.no_shadings, Scene.no_patterns, resources, scene_limits, form_scene_limits, paint_limits) ? FormSceneFailure
	colors = KernelColor.Plan.build(evidence_colors, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? ColorFailure
	images = no_images(colors)?
	facts = KernelForm.Facts.build_with_navigation(paint_scene, { colors, font_count: 0, images }, NoTextStore, $appearances, graph_limits) ? FactsFailure
	form_scene = KernelScene.PaintPlan.forms(paint_scene)
	tagged = KernelTagged.Plan.build(semantic, KernelScene.FormPlan.page(form_scene)) ? TaggedFailure
	form_plan = KernelForm.Plan.build_with_paints(paint_scene, facts, { colors, fonts: [], images }, NoText, tagged, graph_limits) ? FormPlanFailure
	content = KernelContent.Plan.build_with_forms(tagged, form_context(form_plan, input.forms), content_limits) ? ContentFailure
	resource_use = KernelResourceUse.TextPlan.build_with_forms(form_scene, colors, images) ? ResourceUseFailure
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(form_plan)
	base = KernelGate2Objects.Plan.build_canonical(
		tagged,
		colors,
		images,
		resource_use,
		content,
		{ color_spaces: leaf_counts.color_spaces, image_alpha: KernelForm.Plan.canonical_image_alpha(form_plan), profiles: leaf_counts.profiles },
		KernelGate2Objects.Limits.make({ max_objects: 8192, max_pages: 128 }),
	) ? ObjectFailure
	objects = KernelGate4FormObjects.Plan.build_with_states(base, KernelForm.Plan.canonical_form_count(form_plan), KernelForm.Plan.canonical_state_count(form_plan), 0, 8192) ? FormObjectFailure
	structure = KernelGate4FormStructure.Plan.build_with_navigation(
		tagged,
		colors,
		images,
		content,
		form_plan,
		objects,
		NoTextObjects,
		Scene.no_shadings,
		NoDocumentFacts,
		WithNavigation({ anchor_rects: stores.anchor_rects, max_outline_depth: 32, store: navigation.store }),
		structure_limits,
	) ? StructureFailure
	bytes = KernelEmit.to_bytes(KernelGate4FormStructure.Plan.structure(structure)) ? |_| EmitFailure
	Ok({ bytes, form_plan, navigation_work: navigation.work, store: navigation.store, structure })
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
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	[
		built.navigation_work.destinations_checked,
		built.navigation_work.annotations_checked,
		built.navigation_work.quads_checked,
		built.navigation_work.name_bytes_checked,
		built.navigation_work.name_ordering_steps,
		built.navigation_work.outline_entries_checked,
		built.navigation_work.label_ranges_checked,
		structure_work.destinations_resolved,
		structure_work.annotation_objects,
		structure_work.name_node_objects,
		structure_work.outline_objects,
		structure_work.label_node_objects,
		structure_work.quad_numbers,
		structure_work.tagged_objects.annotation_entries,
		structure_work.objects,
		built.bytes.len(),
	]
}

## The showcase: two pages, five blocks. Block 0 is the `intro` destination
## target, block 3 is the `results` destination target on page two; block 1
## is a URI link, block 2 an internal link fragmented into two quads, and
## block 4 an internal link back to `intro` carrying the normal appearance
## form. Keyboard order on page one is authored adversarially (the later
## spine annotation tabs first). `Reversed` authors the destination registry
## in the opposite order, which must not change one emitted byte.
showcase_scenario : [Forward, Reversed] -> Scenario
showcase_scenario = |direction| {
	base_stores = build_stores(
		2,
		[
			Paragraph({ pages: [0] }),
			LinkBlock({ annotations: 1, pages: [0] }),
			LinkBlock({ annotations: 1, pages: [0, 0] }),
			Paragraph({ pages: [1] }),
			LinkBlock({ annotations: 1, pages: [1] }),
		],
	)
	appearance = with_appearance_path(base_stores, fragment_rect(4))
	stores = appearance.stores
	intro = { anchor: list_at(stores.block_occurrences, 0), name: "intro", target: list_at(stores.block_nodes, 0) }
	results = { anchor: list_at(stores.block_occurrences, 3), name: "results", target: list_at(stores.block_nodes, 3) }
	destinations = match direction {
		Forward => [intro, results]
		Reversed => [results, intro]
	}
	uri_quads = [quad_of(fragment_rect(1))]
	internal_quads = [quad_of(fragment_rect(2)), quad_of(fragment_rect(3))]
	back_quads = [quad_of(fragment_rect(4))]
	{
		forms: appearance_form_store(appearance.path, fragment_rect(4)),
		navigation: {
			annotations: [
				{
					action: Uri("https://example.org/reference?section=1&lang=en"),
					appearance: NoAppearance,
					description: WithDescription("Example reference"),
					keyboard_order: 1,
					page: Semantics.PageId.from_index(0),
					print: True,
					quads: uri_quads,
					rect: union_of(uri_quads),
				},
				{
					action: GoToName(
						match direction {
							Forward => "results"
							Reversed => "results"
						},
					),
					appearance: NoAppearance,
					description: NoDescription,
					keyboard_order: 0,
					page: Semantics.PageId.from_index(0),
					print: True,
					quads: internal_quads,
					rect: union_of(internal_quads),
				},
				{
					action: GoToName("intro"),
					appearance: NormalAppearance(Scene.FormId.from_index(0)),
					description: NoDescription,
					keyboard_order: 0,
					page: Semantics.PageId.from_index(1),
					print: False,
					quads: back_quads,
					rect: union_of(back_quads),
				},
			],
			destinations,
			outline: [
				{ depth: 0, destination: "intro", open: True, title: "Introduction" },
				{ depth: 1, destination: "results", open: False, title: "Results detail" },
				{ depth: 0, destination: "results", open: True, title: "Findings" },
			],
			page_labels: [
				{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
				{ prefix: "A-", start_number: 5, start_page: 1, style: DecimalArabic },
			],
		},
		stores,
	}
}

## The appearance form paints one darker inset rectangle in its own
## appearance space; its bounding box is exactly `[0 0 w h]` with the target
## annotation rectangle's extents. The painted path lives in the shared page
## path store, so the scenario appends it beside the fragment paths.
with_appearance_path : NavStore, Layout.Rect -> { path : Scene.PathId, stores : NavStore }
with_appearance_path = |stores, target| {
	scene = stores.scene
	segment_index = scene.path_segments.len()
	path_index = scene.paths.len()
	inset = rect(2000, 2000, target.size.width.raw() - 4000, target.size.height.raw() - 4000)
	{
		path: Scene.PathId.from_index(path_index),
		stores: NavStore.{
			anchor_rects: stores.anchor_rects,
			block_nodes: stores.block_nodes,
			block_occurrences: stores.block_occurrences,
			scene: {
				..scene,
				path_segments: scene.path_segments.append(Rectangle(inset)),
				paths: scene.paths.append({ id: Scene.PathId.from_index(path_index), segments: Semantics.Range.from_start_and_length(segment_index, 1) }),
			},
			semantics: stores.semantics,
		},
	}
}

appearance_form_store : Scene.PathId, Layout.Rect -> Scene.FormStore
appearance_form_store = |path, target| {
	commands: [DrawPath({ path, style: fill_with(gray_value(8224)) })],
	forms: [
		{
			bbox: rect(0, 0, target.size.width.raw(), target.size.height.raw()),
			commands: Semantics.Range.from_start_and_length(0, 1),
			group: NoGroup,
			id: Scene.FormId.from_index(0),
		},
	],
}

## N one-quad URI links on one page; keyboard order is authored fully
## reversed so the /Annots array must invert the authored order.
annots_scenario : U64 -> Scenario
annots_scenario = |scale| {
	var $specs = []
	var $index = 0
	while $index < scale {
		$specs = $specs.append(LinkBlock({ annotations: 1, pages: [0] }))
		$index = $index + 1
	}
	stores = build_stores(1, $specs)
	var $annotations = []
	$index = 0
	while $index < scale {
		quads = [quad_of(fragment_rect($index))]
		$annotations = $annotations.append({
			action: Uri("https://example.org/item"),
			appearance: NoAppearance,
			description: NoDescription,
			keyboard_order: scale - 1 - $index,
			page: Semantics.PageId.from_index(0),
			print: True,
			quads,
			rect: union_of(quads),
		})
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: { annotations: $annotations, destinations: [], outline: [], page_labels: [] },
		stores,
	}
}

## One link fragmented into N quadrilaterals.
quads_scenario : U64 -> Scenario
quads_scenario = |scale| {
	var $pages = []
	var $index = 0
	while $index < scale {
		$pages = $pages.append(0)
		$index = $index + 1
	}
	stores = build_stores(1, [LinkBlock({ annotations: 1, pages: $pages })])
	var $quads = []
	$index = 0
	while $index < scale {
		$quads = $quads.append(quad_of(fragment_rect($index)))
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: {
			annotations: [
				{
					action: Uri("https://example.org/fragmented"),
					appearance: NoAppearance,
					description: NoDescription,
					keyboard_order: 0,
					page: Semantics.PageId.from_index(0),
					print: True,
					quads: $quads,
					rect: union_of($quads),
				},
			],
			destinations: [],
			outline: [],
			page_labels: [],
		},
		stores,
	}
}

## N internal links sharing one named destination.
share_scenario : U64 -> Scenario
share_scenario = |scale| {
	var $specs = [Paragraph({ pages: [0] })]
	var $index = 0
	while $index < scale {
		$specs = $specs.append(LinkBlock({ annotations: 1, pages: [0] }))
		$index = $index + 1
	}
	stores = build_stores(1, $specs)
	var $annotations = []
	$index = 0
	while $index < scale {
		quads = [quad_of(fragment_rect($index + 1))]
		$annotations = $annotations.append({
			action: GoToName("shared-target"),
			appearance: NoAppearance,
			description: NoDescription,
			keyboard_order: $index,
			page: Semantics.PageId.from_index(0),
			print: True,
			quads,
			rect: union_of(quads),
		})
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: {
			annotations: $annotations,
			destinations: [{ anchor: list_at(stores.block_occurrences, 0), name: "shared-target", target: list_at(stores.block_nodes, 0) }],
			outline: [],
			page_labels: [],
		},
		stores,
	}
}

## N links sharing one canonical appearance form without sharing occurrences
## or ownership: all rectangles have identical extents, so one form serves
## every annotation.
appearance_scenario : U64 -> Scenario
appearance_scenario = |scale| {
	var $specs = []
	var $index = 0
	while $index < scale {
		$specs = $specs.append(LinkBlock({ annotations: 1, pages: [0] }))
		$index = $index + 1
	}
	base_stores = build_stores(1, $specs)
	appearance = with_appearance_path(base_stores, fragment_rect(0))
	stores = appearance.stores
	var $annotations = []
	$index = 0
	while $index < scale {
		quads = [quad_of(fragment_rect($index))]
		$annotations = $annotations.append({
			action: Uri("https://example.org/appearance"),
			appearance: NormalAppearance(Scene.FormId.from_index(0)),
			description: NoDescription,
			keyboard_order: $index,
			page: Semantics.PageId.from_index(0),
			print: True,
			quads,
			rect: union_of(quads),
		})
		$index = $index + 1
	}
	{
		forms: appearance_form_store(appearance.path, fragment_rect(0)),
		navigation: { annotations: $annotations, destinations: [], outline: [], page_labels: [] },
		stores,
	}
}

## An N-deep outline chain (every entry open) or an N-wide sibling list with
## alternating open state, over one destination.
outline_scenario : [Deep, Wide], U64 -> Scenario
outline_scenario = |shape, scale| {
	stores = build_stores(1, [Paragraph({ pages: [0] })])
	var $outline = []
	var $index = 0
	while $index < scale {
		entry = match shape {
			Deep => { depth: $index, destination: "chapter", open: True, title: "Depth entry" }
			Wide => { depth: 0, destination: "chapter", open: U64.mod_by($index, 2) == 0, title: "Wide entry" }
		}
		$outline = $outline.append(entry)
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: {
			annotations: [],
			destinations: [{ anchor: list_at(stores.block_occurrences, 0), name: "chapter", target: list_at(stores.block_nodes, 0) }],
			outline: $outline,
			page_labels: [],
		},
		stores,
	}
}

## N named destinations authored in reverse byte order; the registry must
## canonicalize to ascending order and the tree splits into multiple nodes
## past the fixed fanout.
names_scenario : U64 -> Scenario
names_scenario = |scale| {
	var $specs = []
	var $index = 0
	while $index < scale {
		$specs = $specs.append(Paragraph({ pages: [0] }))
		$index = $index + 1
	}
	stores = build_stores(1, $specs)
	var $destinations = []
	$index = 0
	while $index < scale {
		authored = scale - 1 - $index
		$destinations = $destinations.append({
			anchor: list_at(stores.block_occurrences, authored),
			name: "target-${pad_two(authored)}",
			target: list_at(stores.block_nodes, authored),
		})
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: { annotations: [], destinations: $destinations, outline: [], page_labels: [] },
		stores,
	}
}

pad_two : U64 -> Str
pad_two = |value| if value < 10 "0${value.to_str()}" else value.to_str()

## N page-label ranges over N pages with alternating styles and prefixes.
labels_scenario : U64 -> Scenario
labels_scenario = |scale| {
	var $specs = []
	var $index = 0
	while $index < scale {
		$specs = $specs.append(Paragraph({ pages: [$index] }))
		$index = $index + 1
	}
	stores = build_stores(scale, $specs)
	var $labels = []
	$index = 0
	while $index < scale {
		label = if U64.mod_by($index, 3) == 0 {
			{ prefix: "", start_number: $index + 1, start_page: $index, style: DecimalArabic }
		} else if U64.mod_by($index, 3) == 1 {
			{ prefix: "S-", start_number: 1, start_page: $index, style: RomanUpper }
		} else {
			{ prefix: "Annex ", start_number: 1, start_page: $index, style: NoNumber }
		}
		$labels = $labels.append(label)
		$index = $index + 1
	}
	{
		forms: Scene.no_forms,
		navigation: { annotations: [], destinations: [], outline: [], page_labels: $labels },
		stores,
	}
}

run_scenario : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4NavigationEvidence.EvidenceError)
run_scenario = |mode, scale| {

	## Always zero at runtime, but derived from a runtime argument, so the
	## measured pipelines cannot be evaluated at compile time.
	guard = U64.mod_by(scale, 1)
	if mode == "showcase" {
		forward = run_pipeline(showcase_scenario(Forward), guard) ? |_| EvidenceFailure
		reversed = run_pipeline(showcase_scenario(Reversed), guard) ? |_| EvidenceFailure
		if forward.bytes != reversed.bytes {
			return Err(AdversarialOrderDiverged)
		}
		check_invariants(forward)?
		Ok({ bytes: forward.bytes, work: work_vector(forward) })
	} else if mode == "annots" {
		if scale < 1 or scale > 128 {
			return Err(InvalidScale)
		}
		built = run_pipeline(annots_scenario(scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "quads" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(quads_scenario(scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "share" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(share_scenario(scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "appearance" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(appearance_scenario(scale), guard) ? |_| EvidenceFailure
		if KernelForm.Plan.work(built.form_plan).canonical_forms != 1 {
			return Err(SharingDiverged)
		}
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "outline_deep" {
		if scale < 1 or scale > 32 {
			return Err(InvalidScale)
		}
		built = run_pipeline(outline_scenario(Deep, scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "outline_wide" {
		if scale < 1 or scale > 256 {
			return Err(InvalidScale)
		}
		built = run_pipeline(outline_scenario(Wide, scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "names" {
		if scale < 1 or scale > 99 {
			return Err(InvalidScale)
		}
		built = run_pipeline(names_scenario(scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "labels" {
		if scale < 1 or scale > 64 {
			return Err(InvalidScale)
		}
		built = run_pipeline(labels_scenario(scale), guard) ? |_| EvidenceFailure
		check_invariants(built)?
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "unique" {
		built = run_pipeline(showcase_scenario(Forward), guard) ? |_| EvidenceFailure
		Ok({ bytes: built.bytes, work: work_vector(built) })
	} else if mode == "retained" {
		scenario_input = showcase_scenario(Forward)
		first = run_pipeline(scenario_input, guard) ? |_| EvidenceFailure
		second = run_pipeline(scenario_input, guard) ? |_| EvidenceFailure
		if first.bytes != second.bytes {
			return Err(SharedInputDiverged)
		}
		Ok({ bytes: first.bytes, work: work_vector(first) })
	} else {
		Err(InvalidScale)
	}
}

## Structural invariants every positive scenario must satisfy: the xref sits
## one past the stored objects, and every annotation lowered exactly one
## object with its ParentTree row.
check_invariants : Built -> Try({}, Gate4NavigationEvidence.EvidenceError)
check_invariants = |built| {
	structure_work = KernelGate4FormStructure.Plan.work(built.structure)
	plan = KernelGate4FormStructure.Plan.structure(built.structure)
	if KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)) != structure_work.objects + 1 {
		return Err(SharingDiverged)
	}
	if structure_work.annotation_objects != built.store.annotations.len() {
		return Err(SharingDiverged)
	}
	if structure_work.tagged_objects.annotation_entries != built.store.annotations.len() {
		return Err(SharingDiverged)
	}
	if structure_work.destinations_resolved != built.store.destinations.len() {
		return Err(SharingDiverged)
	}
	Ok({})
}

## Numbered atomic rejections. Every attempt differs from a valid request in
## exactly one fact; each must fail with its distinct typed error.
run_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, Gate4NavigationEvidence.EvidenceError)
run_negatives = |runtime_context| {
	if runtime_context != 1 {
		return Err(InvalidScale)
	}

	## Always zero at runtime, but derived from the runtime argument, so the
	## exercised rejections cannot be evaluated at compile time.
	guard = U64.mod_by(runtime_context, 2) - 1
	base = showcase_scenario(Forward)
	valid = base.navigation
	context = {
		forms: base.forms.forms.len(),
		nodes: base.stores.semantics.nodes.len(),
		occurrences: base.stores.semantics.occurrences.len(),
		pages: base.stores.scene.pages.len(),
		semantic_annotations: base.stores.semantics.annotations.len(),
	}
	limits = navigation_limits(guard)
	first_annotation = list_at(valid.annotations, 0)
	first_destination = list_at(valid.destinations, 0)

	## 1-6: destination name and identity rejections.
	expect_rejection(1, { ..valid, destinations: [{ ..first_destination, name: "" }, list_at(valid.destinations, 1)] }, context, limits, |error| error == DestinationNameEmpty({ destination: 0 }))?
	expect_rejection(2, { ..valid, destinations: [{ ..first_destination, name: "bad name" }, list_at(valid.destinations, 1)] }, context, limits, |error| error == DestinationNameInvalidByte({ destination: 0, offset: 3 }))?
	expect_rejection(3, { ..valid, destinations: [{ ..first_destination, name: "a-name-far-beyond-the-configured-sixty-four-byte-registry-limit-for-names" }, list_at(valid.destinations, 1)] }, context, limits, |error| error == DestinationNameTooLong({ attempted: 73, destination: 0, limit: 64 }))?
	expect_rejection(4, { ..valid, destinations: [first_destination, first_destination] }, context, limits, |error| error == DuplicateDestinationName({ first: 0, second: 1 }))?
	expect_rejection(5, { ..valid, destinations: [{ ..first_destination, target: Semantics.NodeId.from_index(99) }, list_at(valid.destinations, 1)] }, context, limits, |error| error == DestinationTargetOutOfRange({ attempted: 99, destination: 0, nodes: context.nodes }))?
	expect_rejection(6, { ..valid, destinations: [{ ..first_destination, anchor: Semantics.OccurrenceId.from_index(99) }, list_at(valid.destinations, 1)] }, context, limits, |error| error == DestinationAnchorOutOfRange({ attempted: 99, destination: 0, occurrences: context.occurrences }))?

	## 7-10: URI rejections.
	expect_rejection(7, replace_action(valid, Uri("")), context, limits, |error| error == UriEmpty({ annotation: 0 }))?
	expect_rejection(8, replace_action(valid, Uri("example.org/no-scheme")), context, limits, |error| error == UriMissingScheme({ annotation: 0 }))?
	expect_rejection(9, replace_action(valid, Uri("https://example.org/a b")), context, limits, |error| error == UriInvalidByte({ annotation: 0, offset: 21 }))?
	expect_rejection(10, replace_action(valid, Uri("https://example.org/%zz")), context, limits, |error| error == UriInvalidPercentEncoding({ annotation: 0, offset: 20 }))?

	## 11: an unknown destination name on a link.
	expect_rejection(11, replace_action(valid, GoToName("missing")), context, limits, |error| error == UnknownDestinationName({ annotation: 0 }))?

	## 12-15: geometry rejections.
	degenerate = { ..first_annotation, rect: rect(10000, 10000, 0, 5000) }
	expect_rejection(12, replace_annotation(valid, degenerate), context, limits, |error| error == InvalidAnnotationRect({ annotation: 0 }))?
	inverted_quad = { ..first_annotation, quads: [{ x_left: unit(20000), x_right: unit(10000), y_bottom: unit(10000), y_top: unit(20000) }], rect: rect(0, 0, 100000, 100000) }
	expect_rejection(13, replace_annotation(valid, inverted_quad), context, limits, |error| error == InvalidQuad({ annotation: 0, quad: 0 }))?
	escaped_quad = { ..first_annotation, quads: [{ x_left: unit(0), x_right: unit(90000), y_bottom: unit(0), y_top: unit(20000) }], rect: rect(0, 0, 50000, 50000) }
	expect_rejection(14, replace_annotation(valid, escaped_quad), context, limits, |error| error == QuadOutsideRect({ annotation: 0, quad: 0 }))?
	expect_rejection(15, replace_annotation(valid, { ..first_annotation, quads: [] }), context, limits, |error| error == QuadsEmpty({ annotation: 0 }))?

	## 16-18: page association, keyboard order, and identity rejections.
	expect_rejection(16, replace_annotation(valid, { ..first_annotation, page: Semantics.PageId.from_index(9) }), context, limits, |error| error == AnnotationPageOutOfRange({ annotation: 0, attempted: 9, pages: 2 }))?
	expect_rejection(17, replace_annotation(valid, { ..first_annotation, keyboard_order: 7 }), context, limits, |error| error == KeyboardOrderOutOfRange({ annotation: 0, attempted: 7, page_annotations: 2 }))?
	expect_rejection(18, { ..valid, annotations: valid.annotations.append(first_annotation) }, context, limits, |error| error == AnnotationCountMismatch({ navigation: 4, semantics: 3 }))?

	## 19-21: outline rejections.
	expect_rejection(19, { ..valid, outline: [{ depth: 1, destination: "intro", open: True, title: "Broken" }] }, context, limits, |error| error == OutlineFirstDepthNonzero({ depth: 1 }))?
	expect_rejection(
		20,
		{
			..valid,
			outline: [
				{ depth: 0, destination: "intro", open: True, title: "One" },
				{ depth: 2, destination: "intro", open: True, title: "Two" },
			],
		},
		context,
		limits,
		|error| error == OutlineDepthJump({ actual: 2, entry: 1, previous: 0 }),
	)?
	expect_rejection(21, { ..valid, outline: [{ depth: 0, destination: "nowhere", open: True, title: "Lost" }] }, context, limits, |error| error == OutlineDestinationUnknown({ entry: 0 }))?

	## 22-24: page-label rejections.
	expect_rejection(22, { ..valid, page_labels: [{ prefix: "", start_number: 1, start_page: 1, style: DecimalArabic }] }, context, limits, |error| error == LabelStartPageNotZero({ start: 1 }))?
	expect_rejection(
		23,
		{
			..valid,
			page_labels: [
				{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic },
				{ prefix: "", start_number: 1, start_page: 0, style: RomanLower },
			],
		},
		context,
		limits,
		|error| error == LabelRangeNotAscending({ range: 1 }),
	)?
	expect_rejection(24, { ..valid, page_labels: [{ prefix: "", start_number: 0, start_page: 0, style: DecimalArabic }] }, context, limits, |error| error == LabelStartNumberZero({ range: 0 }))?

	## 25: an appearance reference outside the form store.
	expect_rejection(25, replace_annotation(valid, { ..first_annotation, appearance: NormalAppearance(Scene.FormId.from_index(9)) }), context, limits, |error| error == AppearanceFormOutOfRange({ annotation: 0, attempted: 9, forms: 1 }))?

	## 26: a destination whose anchor occurrence belongs to a different node
	## than its semantic target is rejected at resolution — the paired /SD
	## and /D facts cannot disagree.
	mismatched = {
		..base.navigation,
		destinations: [
			{ ..first_destination, target: list_at(base.stores.block_nodes, 3) },
			list_at(valid.destinations, 1),
		],
	}
	match run_pipeline(Scenario.{ forms: base.forms, navigation: mismatched, stores: base.stores }, guard + 1 - 1) {
		Err(StructureFailure(Navigation(DestinationTargetMismatch({ anchor_owner: 1, destination: 0, target: 6 })))) => {}
		_ => return Err(MissingRejection(26))
	}

	## 27: a destination without a painted anchor fragment cannot resolve —
	## an /SD-only internal link is unrepresentable, so the document is
	## rejected instead.
	no_anchor = Scenario.{
		forms: base.forms,
		navigation: base.navigation,
		stores: { ..base.stores, anchor_rects: List.repeat(NoAnchor, base.stores.anchor_rects.len()) },
	}
	match run_pipeline(no_anchor, guard + 1 - 1) {
		Err(StructureFailure(Navigation(UnresolvedDestinationAnchor({ destination: 0 })))) => {}
		_ => return Err(MissingRejection(27))
	}

	## 28: an appearance form whose bounding box disagrees with the
	## annotation rectangle.
	wrong_box = Scenario.{
		forms: {
			commands: base.forms.commands,
			forms: [
				{
					bbox: rect(0, 0, 12345, 10000),
					commands: Semantics.Range.from_start_and_length(0, 1),
					group: NoGroup,
					id: Scene.FormId.from_index(0),
				},
			],
		},
		navigation: base.navigation,
		stores: base.stores,
	}
	match run_pipeline(wrong_box, guard + 1 - 1) {
		Err(StructureFailure(Navigation(AppearanceGeometryMismatch({ annotation: 2, form: 0 })))) => {}
		_ => return Err(MissingRejection(28))
	}

	## 29: a semantic annotation whose spine occurrence sits in a node other
	## than its declared owner.
	bad_owner_semantics = {
		..base.stores.semantics,
		annotations: [
			{ id: Semantics.AnnotationId.from_index(0), logical_order: 0, owner: Semantics.NodeId.from_index(1) },
			list_at(base.stores.semantics.annotations, 1),
			list_at(base.stores.semantics.annotations, 2),
		],
	}
	match KernelSemantics.Plan.build_navigation(bad_owner_semantics, 2 + guard, 2, semantic_limits(bad_owner_semantics)) {
		Err(AnnotationOwnerMismatch({ annotation: 0, occurrence_owner: 3, owner: 1 })) => {}
		_ => return Err(MissingRejection(29))
	}

	## 30: a logical order disagreeing with the spine rank.
	bad_order_semantics = {
		..base.stores.semantics,
		annotations: [
			{ id: Semantics.AnnotationId.from_index(0), logical_order: 2, owner: Semantics.NodeId.from_index(3) },
			list_at(base.stores.semantics.annotations, 1),
			list_at(base.stores.semantics.annotations, 2),
		],
	}
	match KernelSemantics.Plan.build_navigation(bad_order_semantics, 2 + guard, 2, semantic_limits(bad_order_semantics)) {
		Err(AnnotationLogicalOrderInvalid({ actual: 2, annotation: 0, expected: 0 })) => {}
		_ => return Err(MissingRejection(30))
	}

	## 31: the resource/entry budgets reject transactionally.
	tight = KernelNavigation.Limits.make({
		max_annotations: 1 + guard,
		max_description_bytes: 256,
		max_destinations: 256,
		max_label_prefix_bytes: 32,
		max_label_ranges: 128,
		max_name_bytes: 64,
		max_outline_depth: 32,
		max_outline_entries: 256,
		max_outline_title_bytes: 256,
		max_quads: 4096,
		max_uri_bytes: 512,
	})
	match KernelNavigation.validate(valid, context, tight) {
		Err(AnnotationLimitExceeded({ attempted: 3, limit: 1 })) => {}
		_ => return Err(MissingRejection(31))
	}

	## 32: the facade rejects an unknown internal destination atomically with
	## the exact typed error and no bytes.
	facade_title = if guard == 0 "Navigation negative" else "guarded"
	facade_document = Pdf.document({ contents: [Pdf.internal_link("Broken", "missing")], language: "en-AU", title: facade_title })
	match Pdf.to_bytes(facade_document) {
		Err(InvalidNavigation(UnknownDestinationName({ annotation: 0 }))) => {}
		_ => return Err(MissingRejection(32))
	}

	carrier = run_pipeline(showcase_scenario(Forward), guard + 1 - 1) ? |_| EvidenceFailure
	Ok({ bytes: carrier.bytes, work: [32, 0, carrier.bytes.len()] })
}

replace_action : KernelNavigation.Input, KernelNavigation.AuthoredAction -> KernelNavigation.Input
replace_action = |input, action| {
	first = list_at(input.annotations, 0)
	replace_annotation(input, { ..first, action })
}

replace_annotation : KernelNavigation.Input, KernelNavigation.AnnotationInput -> KernelNavigation.Input
replace_annotation = |input, annotation| {
	..input,
	annotations: [annotation, list_at(input.annotations, 1), list_at(input.annotations, 2)],
}

expect_rejection : U64, KernelNavigation.Input, KernelNavigation.Context, KernelNavigation.Limits, (Document.NavigationError -> Bool) -> Try({}, Gate4NavigationEvidence.EvidenceError)
expect_rejection = |index, input, context, limits, matches| match KernelNavigation.validate(input, context, limits) {
	Err(error) => if matches(error) Ok({}) else Err(MissingRejection(index))
	Ok(_) => Err(MissingRejection(index))
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "navigation evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "navigation evidence update escaped"
	}
}

## The adversarial showcase, sharing checks, and atomic negatives hold under
## `roc test`; the harness re-runs them as compiled scenarios with exact
## allocation and work baselines.
expect match Gate4NavigationEvidence.scenario("showcase", 0) {
	Ok(result) => result.bytes.len() > 0 and list_at(result.work, 0) == 2 and list_at(result.work, 1) == 3 and list_at(result.work, 8) == 3
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("annots", 4) {
	Ok(result) => list_at(result.work, 1) == 4 and list_at(result.work, 8) == 4
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("quads", 6) {
	Ok(result) => list_at(result.work, 2) == 6 and list_at(result.work, 12) == 48
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("share", 3) {
	Ok(result) => list_at(result.work, 0) == 1 and list_at(result.work, 1) == 3
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("appearance", 3) {
	Ok(result) => list_at(result.work, 8) == 3
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("names", 33) {
	Ok(result) => list_at(result.work, 9) == 3
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("outline_deep", 4) {
	Ok(result) => list_at(result.work, 10) == 5
	Err(_) => False
}

expect match Gate4NavigationEvidence.scenario("labels", 4) {
	Ok(result) => list_at(result.work, 6) == 4 and list_at(result.work, 11) == 1
	Err(_) => False
}

expect match Gate4NavigationEvidence.atomic_negatives(1) {
	Ok(result) => list_at(result.work, 0) == 32
	Err(_) => False
}
