import fuzz.Model
import pdf.KernelSemantics
import pdf.Semantics

HeadingFamilyModel := [].{}

Heading : [Generic, LevelOne, LevelTwo]

World : List(Heading)

# Heading slots in reading order:
# Document / H, Fragment A / H, A / inner Fragment / H, A / Sect / H,
# sibling Fragment B / H, Document / Sect / Sect / H.
# The last Document heading is visited after earlier fragment headings.
slots : List({ node : U64, scope : U64 })
slots = [{ node: 1, scope: 0 }, { node: 3, scope: 2 }, { node: 5, scope: 4 }, { node: 7, scope: 2 }, { node: 9, scope: 8 }, { node: 12, scope: 0 }]

machine : Model.Machine(World, Heading)
machine = {
	init: [],
	actions: |world| if (world.len() == slots.len()) [] else [Generic, LevelOne, LevelTwo],
	step: |world, heading| world.append(heading),
	rules: [
		Model.always("each document and fragment has one heading family", agrees),
		Model.sometimes("separate fragment families and numbered levels coexist", |world| world == [LevelOne, Generic, LevelTwo, Generic, LevelOne, LevelTwo]),
		Model.sometimes("a fragment mixes families even though its document is consistent", |world| world == [LevelOne, Generic, LevelTwo, LevelOne, LevelOne, LevelTwo]),
		Model.sometimes("a fragment does not separate two incompatible Document headings", |world| world == [Generic, LevelOne, LevelTwo, LevelTwo, Generic, LevelTwo]),
	],
}

heading_name : Heading -> Str
heading_name = |heading| match heading {
	Generic => "H"
	LevelOne => "H1"
	LevelTwo => "H2"
}

agrees : World -> Bool
agrees = |headings| {
	if headings.len() != slots.len() {
		return True
	}
	authored = slots.map_with_index(|slot, index| { node: slot.node, scope: slot.scope, generic: headings.get(index) == Ok(Generic) })
	# Compare pairs in the authored scopes instead of following validator frames
	# or recording an encountered family. The first conflicting node is free
	# to depend on traversal order.
	conflicts = |heading| authored.any(|other| other.scope == heading.scope and other.generic != heading.generic)
	store = store_for_headings(headings.map(heading_name))
	match KernelSemantics.Plan.build_text_validated(store, [], 1, 1, limits) {
		Ok(plan) => {
			work = KernelSemantics.Plan.work(plan)
			!authored.any(conflicts) and work.node_visits == 13 and work.containment_edges == 12 and work.max_semantic_depth == 4
		}
		Err(MixedHeadingFamilies({ node, scope })) => authored.any(|heading| heading.node == node and heading.scope == scope and conflicts(heading))
		_ => False
	}
}

limits : KernelSemantics.Limits
limits = limits_with_depth(4)

limits_with_depth : U64 -> KernelSemantics.Limits
limits_with_depth = |max_semantic_depth| KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 12, max_fragments: 0, max_namespaces: 1, max_nodes: 13, max_occurrences: 0, max_semantic_depth })

empty_range : Semantics.IndexRange
empty_range = Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 })

store_for_headings : List(Str) -> Semantics.Store
store_for_headings = |names| {
	roles = [
		"Document",
		name_at(names, 0),
		"DocumentFragment",
		name_at(names, 1),
		"DocumentFragment",
		name_at(names, 2),
		"Sect",
		name_at(names, 3),
		"DocumentFragment",
		name_at(names, 4),
		"Sect",
		"Sect",
		name_at(names, 5),
	]
	parents : List(U64)
	parents = [U64.highest, 0, 0, 2, 2, 4, 2, 6, 0, 8, 0, 10, 11]
	indexed_parents = parents.map_with_index(|parent, child| (child, parent))
	var $nodes = []
	var $spine = []
	for local_name in roles {
		index = $nodes.len()
		start = $spine.len()
		for (child, parent) in indexed_parents {
			if parent == index {
				$spine = $spine.append(ChildNode(Semantics.NodeId.from_index(child)))
			}
		}
		parent = if (index == 0) DocumentRoot else ParentNode(Semantics.NodeId.from_index(parents.get(index) ?? crash "missing parent"))
		$nodes = $nodes.append({
			attributes: empty_range,
			content: Semantics.IndexRange.from_start_and_length({ start, length: $spine.len() - start }),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(index),
			language: Inherited,
			parent,
			role: { local_name, namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(index),
			text_properties: empty_range,
		})
	}
	{
		annotations: [],
		assertions: [],
		attribute_roles: [],
		attributes: [],
		content_spine: $spine,
		contextual_artifacts: [],
		document_root: Semantics.NodeId.from_index(0),
		element_identifiers: [],
		fragments: [],
		mathml_subtrees: [],
		namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
		nodes: $nodes,
		non_text_sources: [],
		occurrence_fragments: [],
		occurrences: [],
		relationships: [],
		role_mappings: [],
		text_properties: [],
		text_sources: [],
	}
}

name_at : List(Str), U64 -> Str
name_at = |names, index| names.get(index) ?? crash "missing heading"

expect {
	report = Model.explore(machine, { depth: 7, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1093 and report.steps == 1092 and report.depth == 6 and report.reached.len() == 3
}

expect {
	store = store_for_headings(["H", "H", "H1", "H", "H1", "H1"])
	match KernelSemantics.Plan.build_text_validated(store, [], 1, 1, limits_with_depth(3)) {
		Err(LimitExceeded({ attempted: 4, dimension: SemanticDepth, limit: 3 })) => True
		_ => False
	}
}
