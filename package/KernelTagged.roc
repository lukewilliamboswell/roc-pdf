import KernelScene
import KernelSemantics
import Image
import Layout
import Scene
import Semantics

KernelTagged :: [].{
	IndexKind : [ContentStreamIndex, FragmentIndex, OccurrenceIndex]
	Error : [
		ArithmeticOverflow,
		DuplicateFragmentOwnership({ fragment : U64 }),
		FragmentPageMismatch({ actual : U64, expected : U64, fragment : U64 }),
		IndexOutOfRange({ available : U64, index : U64, kind : IndexKind }),
		OccurrenceHasNoFragments({ occurrence : U64 }),
		OrphanFragment({ fragment : U64 }),
		PageCountMismatch({ scenes : U64, semantics : U64 }),
	]

	MarkedContentReference : {
		content_stream : Semantics.ContentStreamId,
		fragment : Semantics.FragmentId,
		mcid : U64,
		page : Semantics.PageId,
		structure_element : Semantics.StructureElementId,
	}

	## `AnnotationChild` is an annotation occurrence in its owner's spine; it
	## lowers to an OBJR object reference rather than a marked-content item and
	## never consumes an MCID.
	KItem : [
		AnnotationChild(Semantics.AnnotationId),
		ChildStructure(Semantics.StructureElementId),
		ContextualArtifactChild(Semantics.ContextualArtifactId),
		MarkedContent(MarkedContentReference),
	]

	NodeK : { items : Semantics.Range, node : Semantics.NodeId }
	ParentTreeRow : { content_stream : Semantics.ContentStreamId, entries : Semantics.Range }

	Work : {
		annotation_items : U64,
		artifact_groups : U64,
		fragment_groups : U64,
		k_items : U64,
		node_k_ranges : U64,
		occurrence_owner_edges : U64,
		paint_edges : U64,
		parent_prefix_steps : U64,
		parent_writes : U64,
	}

	Plan :: {
		annotation_owners : List(Semantics.StructureElementId),
		occurrence_owners : List(Semantics.NodeId),
		k_items : List(KItem),
		marked_fragments : List(MarkedContentReference),
		node_k : List(NodeK),
		parent_entries : List(MarkedContentReference),
		parent_rows : List(ParentTreeRow),
		scenes : Scene.Store,
		semantics : Semantics.Store,
		work : Work,
	}.{
		build : KernelSemantics.Plan, KernelScene.Plan -> Try(Plan, Error)
		build = |semantics, scenes| build_plan(semantics, scenes)

		## Each annotation's owning structure element, dense by annotation
		## identity. ParentTree lowering reads `/StructParent` values through
		## this list without re-deriving ownership.
		annotation_owners : Plan -> List(Semantics.StructureElementId)
		annotation_owners = |plan| plan.annotation_owners

		## Each content occurrence's owning semantic node, dense by occurrence
		## identity. Destination resolution validates its paired semantic and
		## geometric targets through this map without re-walking the spine.
		occurrence_owners : Plan -> List(Semantics.NodeId)
		occurrence_owners = |plan| plan.occurrence_owners

		k_items : Plan -> List(KItem)
		k_items = |plan| plan.k_items

		marked_fragments : Plan -> List(MarkedContentReference)
		marked_fragments = |plan| plan.marked_fragments

		node_k : Plan -> List(NodeK)
		node_k = |plan| plan.node_k

		parent_entries : Plan -> List(MarkedContentReference)
		parent_entries = |plan| plan.parent_entries

		parent_rows : Plan -> List(ParentTreeRow)
		parent_rows = |plan| plan.parent_rows

		scenes : Plan -> Scene.Store
		scenes = |plan| plan.scenes

		semantics : Plan -> Semantics.Store
		semantics = |plan| plan.semantics

		work : Plan -> Work
		work = |plan| plan.work
	}
}

PaintWork := { artifact_groups : U64, fragment_groups : U64, fragment_order : List(Semantics.FragmentId), paint_edges : U64 }

ParentWork := {
	marked : List(KernelTagged.MarkedContentReference),
	parent_entries : List(KernelTagged.MarkedContentReference),
	parent_rows : List(KernelTagged.ParentTreeRow),
	prefix_steps : U64,
	writes : U64,
}

KWork := { annotation_items : U64, items : List(KernelTagged.KItem), node_k : List(KernelTagged.NodeK) }

TaggedProbeError := [SemanticFailure(KernelSemantics.Error), SceneFailure(KernelScene.Error), TaggedFailure(KernelTagged.Error)]

build_plan : KernelSemantics.Plan, KernelScene.Plan -> Try(KernelTagged.Plan, KernelTagged.Error)
build_plan = |semantic_plan, scene_plan| {
	semantics = KernelSemantics.Plan.store(semantic_plan)
	scenes = KernelScene.Plan.scenes(scene_plan)
	semantic_pages = KernelSemantics.Plan.page_count(semantic_plan)
	if scenes.pages.len() != semantic_pages {
		Err(PageCountMismatch({ scenes: scenes.pages.len(), semantics: semantic_pages }))
	} else {
		occurrence_nodes = build_occurrence_nodes(semantics)?
		paint = collect_paint_order(semantics, scenes)?
		ensure_occurrences_painted(semantics.occurrences)?
		parents = build_parent_tree(semantics, paint.fragment_order, occurrence_nodes, KernelSemantics.Plan.content_stream_count(semantic_plan))?
		k = build_k_order(semantics, parents.marked)?
		annotation_owners = build_annotation_owners(semantics)

		Ok(
			KernelTagged.Plan.{
				annotation_owners,
				occurrence_owners: occurrence_nodes,
				k_items: k.items,
				marked_fragments: parents.marked,
				node_k: k.node_k,
				parent_entries: parents.parent_entries,
				parent_rows: parents.parent_rows,
				scenes,
				semantics,
				work: {
					annotation_items: k.annotation_items,
					artifact_groups: paint.artifact_groups,
					fragment_groups: paint.fragment_groups,
					k_items: k.items.len(),
					node_k_ranges: k.node_k.len(),
					occurrence_owner_edges: semantics.occurrences.len(),
					paint_edges: paint.paint_edges,
					parent_prefix_steps: parents.prefix_steps,
					parent_writes: parents.writes,
				},
			},
		)
	}
}

build_occurrence_nodes : Semantics.Store -> Try(List(Semantics.NodeId), KernelTagged.Error)
build_occurrence_nodes = |store| {
	var $owners = List.repeat(0, store.occurrences.len())
	var $nodes = List.repeat(store.document_root, store.occurrences.len())
	var $node_index = 0
	var $error = NoError
	while $node_index < store.nodes.len() and $error == NoError {
		node = list_at(store.nodes, $node_index)
		start = node.content.start()
		end = start + node.content.length()
		var $content_index = start
		while $content_index < end and $error == NoError {
			match list_at(store.content_spine, $content_index) {
				ContentOccurrence(occurrence) => {
					index = occurrence.index()
					if index >= $owners.len() {
						$error = Invalid(IndexOutOfRange({ available: $owners.len(), index, kind: OccurrenceIndex }))
					} else if list_at($owners, index) != 0 {
						$error = Invalid(DuplicateFragmentOwnership({ fragment: index }))
					} else {
						$owners = list_set($owners, index, 1)
						$nodes = list_set($nodes, index, node.id)
					}
				}
				_ => {}
			}
			$content_index = $content_index + 1
		}
		$node_index = $node_index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($nodes)
	}
}

collect_paint_order : Semantics.Store, Scene.Store -> Try(PaintWork, KernelTagged.Error)
collect_paint_order = |semantics, scenes| {
	var $owners = List.repeat(0, semantics.fragments.len())
	var $fragment_order = []
	var $page_index = 0
	var $paint_edges = 0
	var $fragment_groups = 0
	var $artifact_groups = 0
	var $error = NoError
	while $page_index < scenes.pages.len() and $error == NoError {
		page = list_at(scenes.pages, $page_index)
		start = page.paint_order.start()
		end = start + page.paint_order.length()
		var $edge = start
		while $edge < end and $error == NoError {
			group_index = list_at(scenes.page_groups, $edge).index()
			group = list_at(scenes.groups, group_index)
			match group.owner {
				PageArtifact(_) => {
					$artifact_groups = $artifact_groups + 1
				}
				Fragment(fragment) => {
					fragment_index = fragment.index()
					if fragment_index >= semantics.fragments.len() {
						$error = Invalid(IndexOutOfRange({ available: semantics.fragments.len(), index: fragment_index, kind: FragmentIndex }))
					} else if list_at($owners, fragment_index) != 0 {
						$error = Invalid(DuplicateFragmentOwnership({ fragment: fragment_index }))
					} else {
						semantic_fragment = list_at(semantics.fragments, fragment_index)
						expected_page = semantic_fragment.page.index()
						if expected_page != $page_index {
							$error = Invalid(FragmentPageMismatch({ actual: $page_index, expected: expected_page, fragment: fragment_index }))
						} else {
							$owners = list_set($owners, fragment_index, 1)
							$fragment_order = $fragment_order.append(fragment)
							$fragment_groups = $fragment_groups + 1
						}
					}
				}
			}
			$edge = $edge + 1
			$paint_edges = $paint_edges + 1
		}
		$page_index = $page_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => match first_unowned($owners) {
			AllOwned => Ok({ artifact_groups: $artifact_groups, fragment_groups: $fragment_groups, fragment_order: $fragment_order, paint_edges: $paint_edges })
			Unowned(fragment) => Err(
				OrphanFragment({
					fragment: fragment,
				}),
			)
		}
	}
}

ensure_occurrences_painted : List(Semantics.ContentOccurrence) -> Try({}, KernelTagged.Error)
ensure_occurrences_painted = |occurrences| {
	var $index = 0
	var $missing = NoMissing
	while $index < occurrences.len() and $missing == NoMissing {
		if list_at(occurrences, $index).fragments.length() == 0 {
			$missing = Missing($index)
		}
		$index = $index + 1
	}
	match $missing {
		Missing(occurrence) => Err(
			OccurrenceHasNoFragments({
				occurrence: occurrence,
			}),
		)
		NoMissing => Ok({})
	}
}

build_parent_tree : Semantics.Store, List(Semantics.FragmentId), List(Semantics.NodeId), U64 -> Try(ParentWork, KernelTagged.Error)
build_parent_tree = |store, fragment_order, occurrence_nodes, stream_count| {
	var $counts = List.repeat(0, stream_count)
	var $index = 0
	while $index < fragment_order.len() {
		fragment = list_at(store.fragments, list_at(fragment_order, $index).index())
		stream = fragment.content_stream.index()
		count = list_at($counts, stream)
		$counts = list_set($counts, stream, U64.plus_try(count, 1) ? |_| ArithmeticOverflow)
		$index = $index + 1
	}

	var $starts = List.repeat(0, stream_count)
	var $rows = []
	var $total = 0
	var $stream = 0
	while $stream < stream_count {
		$starts = list_set($starts, $stream, $total)
		count = list_at($counts, $stream)
		$rows = $rows.append({ content_stream: Semantics.ContentStreamId.from_index($stream), entries: Semantics.Range.from_start_and_length($total, count) })
		$total = U64.plus_try($total, count) ? |_| ArithmeticOverflow
		$stream = $stream + 1
	}

	empty_reference = {
		content_stream: Semantics.ContentStreamId.from_index(0),
		fragment: Semantics.FragmentId.from_index(0),
		mcid: 0,
		page: Semantics.PageId.from_index(0),
		structure_element: Semantics.StructureElementId.from_index(0),
	}
	var $marked = List.repeat(empty_reference, store.fragments.len())
	var $entries = List.repeat(empty_reference, fragment_order.len())
	var $cursors = $starts
	$index = 0
	while $index < fragment_order.len() {
		fragment_id = list_at(fragment_order, $index)
		fragment = list_at(store.fragments, fragment_id.index())
		stream_index = fragment.content_stream.index()
		write_index = list_at($cursors, stream_index)
		mcid = write_index - list_at($starts, stream_index)
		owner_node = list_at(occurrence_nodes, fragment.occurrence.index())
		node = list_at(store.nodes, owner_node.index())
		reference = {
			content_stream: fragment.content_stream,
			fragment: fragment_id,
			mcid,
			page: fragment.page,
			structure_element: node.structure_element,
		}
		$marked = list_set($marked, fragment_id.index(), reference)
		$entries = list_set($entries, write_index, reference)
		$cursors = list_set($cursors, stream_index, write_index + 1)
		$index = $index + 1
	}

	Ok({ marked: $marked, parent_entries: $entries, parent_rows: $rows, prefix_steps: stream_count, writes: fragment_order.len() })
}

build_k_order : Semantics.Store, List(KernelTagged.MarkedContentReference) -> Try(KWork, KernelTagged.Error)
build_k_order = |store, marked| {
	var $items = []
	var $ranges = []
	var $annotation_items = 0
	var $node_index = 0
	while $node_index < store.nodes.len() {
		node = list_at(store.nodes, $node_index)
		start = $items.len()
		content_start = node.content.start()
		content_end = content_start + node.content.length()
		var $content_index = content_start
		while $content_index < content_end {
			match list_at(store.content_spine, $content_index) {
				AnnotationOccurrence(annotation) => {
					$items = $items.append(AnnotationChild(annotation))
					$annotation_items = $annotation_items + 1
				}
				ChildNode(child) => {
					child_node = list_at(store.nodes, child.index())
					$items = $items.append(ChildStructure(child_node.structure_element))
				}
				ContextualArtifact(artifact) => {
					$items = $items.append(ContextualArtifactChild(artifact))
				}
				ContentOccurrence(occurrence) => {
					occurrence_record = list_at(store.occurrences, occurrence.index())
					fragment_start = occurrence_record.fragments.start()
					fragment_end = fragment_start + occurrence_record.fragments.length()
					var $fragment_edge = fragment_start
					while $fragment_edge < fragment_end {
						fragment_id = list_at(store.occurrence_fragments, $fragment_edge)
						$items = $items.append(MarkedContent(list_at(marked, fragment_id.index())))
						$fragment_edge = $fragment_edge + 1
					}
				}
			}
			$content_index = $content_index + 1
		}
		$ranges = $ranges.append({ items: Semantics.Range.from_start_and_length(start, $items.len() - start), node: node.id })
		$node_index = $node_index + 1
	}
	Ok({ annotation_items: $annotation_items, items: $items, node_k: $ranges })
}

## Each annotation's owner node was validated by the semantic stage; this maps
## it to the owner's emitted structure element once, dense by annotation id.
build_annotation_owners : Semantics.Store -> List(Semantics.StructureElementId)
build_annotation_owners = |store| {
	var $owners = List.with_capacity(store.annotations.len())
	var $index = 0
	while $index < store.annotations.len() {
		annotation = list_at(store.annotations, $index)
		node = list_at(store.nodes, annotation.owner.index())
		$owners = $owners.append(node.structure_element)
		$index = $index + 1
	}
	$owners
}

first_unowned : List(U8) -> [AllOwned, Unowned(U64)]
first_unowned = |owners| {
	var $index = 0
	var $result = AllOwned
	while $index < owners.len() and $result == AllOwned {
		if list_at(owners, $index) == 0 {
			$result = Unowned($index)
		}
		$index = $index + 1
	}
	$result
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated tagged index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated tagged update escaped"
	}
}

empty_range : Semantics.Range
empty_range = Semantics.Range.from_start_and_length(0, 0)

tagged_semantics : Semantics.Store
tagged_semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [{ applicability: AllRoles, name: Standard("Type"), owner: Artifact, value: Name("Pagination") }],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [{ attributes: Semantics.Range.from_start_and_length(0, 1), id: Semantics.ContextualArtifactId.from_index(0), parent: Semantics.NodeId.from_index(0) }],
	document_root: Semantics.NodeId.from_index(0),
	fragments: [{ content_stream: Semantics.ContentStreamId.from_index(0), continuation_index: 0, id: Semantics.FragmentId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0), page: Semantics.PageId.from_index(0), source_range: ByteRange(empty_range) }],
	element_identifiers: [],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(0, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: empty_range },
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(2, 1), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(1), language: Inherited, parent: ParentNode(Semantics.NodeId.from_index(0)), role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(1), text_properties: empty_range },
	],
	non_text_sources: [[]],
	occurrence_fragments: [],
	occurrences: [{ fragments: empty_range, id: Semantics.OccurrenceId.from_index(0), language: Inherited, source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(empty_range)), text_properties: empty_range }],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [],
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

tagged_scene : Scene.Store
tagged_scene = {
	commands: [
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(1000, 1000, 1000, 1000) }),
	],
	dash_lengths: [],
	groups: [
		{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
		{ commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
	],
	page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
	pages: [{ boxes: { art: rect(0, 0, 10000, 10000), bleed: rect(0, 0, 10000, 10000), crop: rect(0, 0, 10000, 10000), media: rect(0, 0, 10000, 10000), trim: rect(0, 0, 10000, 10000) }, id: Semantics.PageId.from_index(0), paint_order: Semantics.Range.from_start_and_length(0, 2), rotation: Rotate0 }],
	path_segments: [],
	paths: [],
}

semantic_limits : KernelSemantics.Limits
semantic_limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 3, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })

scene_limits : KernelScene.Limits
scene_limits = KernelScene.Limits.make({ max_commands: 2, max_dash_lengths: 0, max_graphics_depth: 1, max_groups: 2, max_pages: 1, max_path_segments: 0, max_paths: 0 })

tagged_plan : {} -> Try(KernelTagged.Plan, TaggedProbeError)
tagged_plan = |_| {
	semantics = KernelSemantics.Plan.build(tagged_semantics, 1, 1, semantic_limits) ? SemanticFailure
	scene = KernelScene.Plan.build(tagged_scene, KernelScene.Resources.make({ color_spaces: 0, images: 1 }), scene_limits) ? SceneFailure
	plan = KernelTagged.Plan.build(semantics, scene) ? TaggedFailure
	Ok(plan)
}

## MCIDs and ParentTree rows are assigned from content-stream paint order.
expect {
	plan = tagged_plan({})?
	marked = list_at(KernelTagged.Plan.marked_fragments(plan), 0)
	row = list_at(KernelTagged.Plan.parent_rows(plan), 0)
	parent = list_at(KernelTagged.Plan.parent_entries(plan), 0)

	marked.mcid == 0 and marked.fragment.index() == 0 and marked.structure_element.index() == 1 and row.content_stream.index() == 0 and row.entries.start() == 0 and row.entries.length() == 1 and parent.fragment.index() == 0
}

## Mixed structure order comes from each node's semantic content spine.
expect {
	plan = tagged_plan({})?
	items = KernelTagged.Plan.k_items(plan)
	ranges = KernelTagged.Plan.node_k(plan)

	items.len() == 3 and
		match list_at(items, 0) {
			ChildStructure(structure) => structure.index() == 1
			_ => False
		} and match list_at(items, 1) {
			ContextualArtifactChild(artifact) => artifact.index() == 0
			_ => False
		} and match list_at(items, 2) {
			MarkedContent(reference) => reference.fragment.index() == 0 and reference.mcid == 0
			_ => False
		} and list_at(ranges, 0).items.length() == 2 and list_at(ranges, 1).items.start() == 2
}

## Page artifacts never acquire MCIDs or semantic ownership.
expect {
	plan = tagged_plan({})?
	work = KernelTagged.Plan.work(plan)

	work.fragment_groups == 1 and work.artifact_groups == 1 and work.paint_edges == 2 and work.parent_writes == 1 and work.k_items == 3
}

## One semantic fragment cannot own multiple painted scene groups.
expect {
	second = list_at(tagged_scene.groups, 1)
	groups = list_set(tagged_scene.groups, 1, { ..second, owner: Fragment(Semantics.FragmentId.from_index(0)) })
	scene_store = { ..tagged_scene, groups }
	semantics = KernelSemantics.Plan.build(tagged_semantics, 1, 1, semantic_limits)?
	scene = KernelScene.Plan.build(scene_store, KernelScene.Resources.make({ color_spaces: 0, images: 1 }), scene_limits)?

	match KernelTagged.Plan.build(semantics, scene) {
		Err(DuplicateFragmentOwnership({ fragment: 0 })) => True
		_ => False
	}
}

## Meaningful semantic fragments cannot disappear into page-artifact paint.
expect {
	first = list_at(tagged_scene.groups, 0)
	groups = list_set(tagged_scene.groups, 0, { ..first, owner: PageArtifact(Decoration) })
	scene_store = { ..tagged_scene, groups }
	semantics = KernelSemantics.Plan.build(tagged_semantics, 1, 1, semantic_limits)?
	scene = KernelScene.Plan.build(scene_store, KernelScene.Resources.make({ color_spaces: 0, images: 1 }), scene_limits)?

	match KernelTagged.Plan.build(semantics, scene) {
		Err(OrphanFragment({ fragment: 0 })) => True
		_ => False
	}
}

## Logical content cannot be accepted without at least one painted fragment.
expect {
	empty_semantics = { ..tagged_semantics, fragments: [] }
	empty_limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 3, max_fragments: 0, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })
	first = list_at(tagged_scene.groups, 0)
	groups = list_set(tagged_scene.groups, 0, { ..first, owner: PageArtifact(Decoration) })
	scene_store = { ..tagged_scene, groups }
	semantics = KernelSemantics.Plan.build(empty_semantics, 1, 1, empty_limits)?
	scene = KernelScene.Plan.build(scene_store, KernelScene.Resources.make({ color_spaces: 0, images: 1 }), scene_limits)?

	match KernelTagged.Plan.build(semantics, scene) {
		Err(OccurrenceHasNoFragments({ occurrence: 0 })) => True
		_ => False
	}
}

navigation_tagged_semantics : Semantics.Store
navigation_tagged_semantics = {
	..tagged_semantics,
	annotations: [{ id: Semantics.AnnotationId.from_index(0), logical_order: 0, owner: Semantics.NodeId.from_index(1) }],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0)), AnnotationOccurrence(Semantics.AnnotationId.from_index(0))],
	nodes: [
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(0, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: empty_range },
		{ attributes: empty_range, content: Semantics.Range.from_start_and_length(2, 2), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(1), language: Inherited, parent: ParentNode(Semantics.NodeId.from_index(0)), role: { local_name: "Link", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(1), text_properties: empty_range },
	],
}

## Annotation spine occurrences become AnnotationChild K items in spine order
## with dense owner structure elements; they never consume an MCID.
expect {
	limits = KernelSemantics.Limits.make({ max_attributes: 1, max_content_spine: 4, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })
	semantics = KernelSemantics.Plan.build_navigation(navigation_tagged_semantics, 1, 1, limits) ? |_| TestFailure
	scene = KernelScene.Plan.build(tagged_scene, KernelScene.Resources.make({ color_spaces: 0, images: 1 }), scene_limits) ? |_| TestFailure
	plan = KernelTagged.Plan.build(semantics, scene) ? |_| TestFailure
	items = KernelTagged.Plan.k_items(plan)
	owners = KernelTagged.Plan.annotation_owners(plan)
	work = KernelTagged.Plan.work(plan)
	marked = list_at(KernelTagged.Plan.marked_fragments(plan), 0)

	items.len() == 4 and
		match list_at(items, 3) {
			AnnotationChild(annotation) => annotation.index() == 0
			_ => False
		} and owners.len() == 1 and
			list_at(owners, 0).index() == 1 and
				work.annotation_items == 1 and
					work.k_items == 4 and
						marked.mcid == 0
}
