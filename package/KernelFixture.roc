import Color
import Image
import KernelScene
import KernelSemantics
import KernelTagged
import Layout
import Scene
import Semantics

KernelFixture :: [].{
	Error : [Semantic(KernelSemantics.Error), Scene(KernelScene.Error), Tagged(KernelTagged.Error)]

	empty_range : Semantics.Range
	empty_range = Semantics.Range.from_start_and_length(0, 0)

	unit : I64 -> Layout.Unit
	unit = |raw| Layout.Unit.from_raw(raw)

	rect : I64, I64, I64, I64 -> Layout.Rect
	rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

	semantics : Semantics.Store
	semantics = test_semantics

	scene : Scene.Store
	scene = test_scene

	tagged_plan : U64 -> Try(KernelTagged.Plan, Error)
	tagged_plan = |content_streams| build_tagged_plan(test_semantics, content_streams)

	contextual_tagged_plan : U64 -> Try(KernelTagged.Plan, Error)
	contextual_tagged_plan = |content_streams| build_tagged_plan(contextual_semantics, content_streams)
}

test_semantics : Semantics.Store
test_semantics = {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [],
	fragments: [{ content_stream: Semantics.ContentStreamId.from_index(0), continuation_index: 0, id: Semantics.FragmentId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(0), page: Semantics.PageId.from_index(0), source_range: ByteRange(KernelFixture.empty_range) }],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: [
		{ attributes: KernelFixture.empty_range, content: Semantics.Range.from_start_and_length(0, 1), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(0), language: Inherited, parent: DocumentRoot, role: { local_name: "Document", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(0), text_properties: KernelFixture.empty_range },
		{ attributes: KernelFixture.empty_range, content: Semantics.Range.from_start_and_length(1, 1), element_identifier: NoElementIdentifier, id: Semantics.NodeId.from_index(1), language: Inherited, parent: ParentNode(Semantics.NodeId.from_index(0)), role: { local_name: "P", namespace: Semantics.NamespaceId.from_index(0) }, structure_element: Semantics.StructureElementId.from_index(1), text_properties: KernelFixture.empty_range },
	],
	non_text_sources: [[]],
	occurrence_fragments: [],
	occurrences: [{ fragments: KernelFixture.empty_range, id: Semantics.OccurrenceId.from_index(0), language: Inherited, source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(KernelFixture.empty_range)), text_properties: KernelFixture.empty_range }],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [],
}

test_scene : Scene.Store
test_scene = {
	commands: [
		DrawPath({ path: Scene.PathId.from_index(0), style: { fill: SolidFill({ color: { channels: Gray(32768), space: Color.SpaceId.from_index(0) }, rule: Nonzero }), stroke: NoStroke } }),
		Transform({ children: Semantics.Range.from_start_and_length(2, 1), matrix: { a: KernelFixture.unit(1000), b: KernelFixture.unit(0), c: KernelFixture.unit(0), d: KernelFixture.unit(1000), e: KernelFixture.unit(2000), f: KernelFixture.unit(3000) } }),
		DrawImage({ image: Image.Id.from_index(0), placement: KernelFixture.rect(4000, 5000, 2000, 1000) }),
	],
	dash_lengths: [],
	groups: [
		{ commands: Semantics.Range.from_start_and_length(0, 1), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) },
		{ commands: Semantics.Range.from_start_and_length(1, 1), id: Scene.GroupId.from_index(1), owner: PageArtifact(Background) },
	],
	page_groups: [Scene.GroupId.from_index(0), Scene.GroupId.from_index(1)],
	pages: [{ boxes: { art: KernelFixture.rect(0, 0, 10000, 10000), bleed: KernelFixture.rect(0, 0, 10000, 10000), crop: KernelFixture.rect(0, 0, 10000, 10000), media: KernelFixture.rect(0, 0, 10000, 10000), trim: KernelFixture.rect(0, 0, 10000, 10000) }, id: Semantics.PageId.from_index(0), paint_order: Semantics.Range.from_start_and_length(0, 2), rotation: Rotate0 }],
	path_segments: [Rectangle(KernelFixture.rect(0, 0, 1000, 1000))],
	paths: [{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) }],
}

contextual_semantics : Semantics.Store
contextual_semantics = {
	..test_semantics,
	attributes: [{ applicability: AllRoles, name: Standard("Type"), owner: Artifact, value: Name("Pagination") }],
	content_spine: [ChildNode(Semantics.NodeId.from_index(1)), ContextualArtifact(Semantics.ContextualArtifactId.from_index(0)), ContentOccurrence(Semantics.OccurrenceId.from_index(0))],
	contextual_artifacts: [{ attributes: Semantics.Range.from_start_and_length(0, 1), id: Semantics.ContextualArtifactId.from_index(0), parent: Semantics.NodeId.from_index(1) }],
	nodes: [
		{ ..list_at(test_semantics.nodes, 0), content: Semantics.Range.from_start_and_length(0, 1) },
		{ ..list_at(test_semantics.nodes, 1), content: Semantics.Range.from_start_and_length(1, 2) },
	],
}

build_tagged_plan : Semantics.Store, U64 -> Try(KernelTagged.Plan, KernelFixture.Error)
build_tagged_plan = |semantic_store, content_streams| {
	semantics = KernelSemantics.Plan.build(semantic_store, 1, content_streams, KernelSemantics.Limits.make({ max_attributes: semantic_store.attributes.len(), max_content_spine: semantic_store.content_spine.len(), max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })) ? Semantic
	scenes = KernelScene.Plan.build(test_scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 2, max_pages: 1, max_path_segments: 1, max_paths: 1 })) ? Scene
	plan = KernelTagged.Plan.build(semantics, scenes) ? Tagged
	Ok(plan)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "tagged-visual fixture index escaped"
	}
}
