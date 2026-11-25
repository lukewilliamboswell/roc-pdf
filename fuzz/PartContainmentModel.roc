import fuzz.Model
import pdf.KernelSemantics
import pdf.Semantics

PartContainmentModel := [].{}

Grouping : [Division, Part, Section]

Leaf : [Paragraph, Span]

Action : [Enter(Grouping), End(Leaf)]

World : { path : List(Grouping), leaf : [NoLeaf, Leaf(Leaf)] }

# Table 365 resolves Part containment against the first non-Part ancestor.
# The grouping paths below have legal grouping edges in Annex L and TS 32005.
# Their final P and Span edges distinguish the supported containment rows.
machine : Model.Machine(World, Action)
machine = {
	init: { path: [], leaf: NoLeaf },
	actions: |world| match world.leaf {
		Leaf(_) => []
		NoLeaf => {
			endings = [End(Paragraph), End(Span)]
			if (world.path.len() == 4) endings else endings.concat([Enter(Division), Enter(Part), Enter(Section)])
		}
	},
	step: |world, action| match action {
		Enter(group) => { ..world, path: world.path.append(group) }
		End(leaf) => { ..world, leaf: Leaf(leaf) }
	},
	rules: [
		Model.always("a typed leaf edge agrees with the nearest non-Part ancestor", agrees),
		Model.sometimes("two Parts retain the Document restriction on Span", |world| world.path == [Part, Part] and world.leaf == Leaf(Span)),
		Model.sometimes("a nearer Div permits Span after the earlier Sect", |world| world.path == [Section, Part, Division, Part] and world.leaf == Leaf(Span)),
	],
}

group_name : Grouping -> Str
group_name = |role| match role {
	Division => "Div"
	Part => "Part"
	Section => "Sect"
}

agrees : World -> Bool
agrees = |world| match world.leaf {
	NoLeaf => True
	Leaf(leaf) => {
		allowed = leaf == Paragraph or world.path.keep_if(|group| group != Part).last() == Ok(Division)
		leaf_role = if (leaf == Paragraph) "P" else "Span"
		roles = ["Document"].concat(world.path.map(group_name)).append(leaf_role)
		child = roles.len() - 1
		match KernelSemantics.Plan.build_text_validated(store_for_roles(roles), [], 1, 1, limits) {
			Ok(plan) => {
				work = KernelSemantics.Plan.work(plan)
				allowed and work.containment_edges == child and work.node_visits == roles.len()
			}
			Err(IllegalContainment(details)) => !allowed and details == { child, parent: child - 1 }
			Err(_) => False
		}
	}
}

limits : KernelSemantics.Limits
limits = KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 6, max_fragments: 0, max_namespaces: 1, max_nodes: 6, max_occurrences: 1, max_semantic_depth: 6 })

empty_range : Semantics.IndexRange
empty_range = Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 })

store_for_roles : List(Str) -> Semantics.Store
store_for_roles = |roles| {
	annotations: [],
	assertions: [],
	attribute_roles: [],
	attributes: [],
	content_spine: roles.map_with_index(|_, index| if (index + 1 == roles.len()) ContentOccurrence(Semantics.OccurrenceId.from_index(0)) else ChildNode(Semantics.NodeId.from_index(index + 1))),
	contextual_artifacts: [],
	document_root: Semantics.NodeId.from_index(0),
	element_identifiers: [],
	fragments: [],
	mathml_subtrees: [],
	namespaces: [{ id: Semantics.NamespaceId.from_index(0), kind: Pdf20, uri: "http://iso.org/pdf2/ssn" }],
	nodes: roles.map_with_index(
		|local_name, index| {
			attributes: empty_range,
			content: Semantics.IndexRange.from_start_and_length({ start: index, length: 1 }),
			element_identifier: NoElementIdentifier,
			id: Semantics.NodeId.from_index(index),
			language: Inherited,
			parent: if (index == 0) DocumentRoot else ParentNode(Semantics.NodeId.from_index(index - 1)),
			role: { local_name, namespace: Semantics.NamespaceId.from_index(0) },
			structure_element: Semantics.StructureElementId.from_index(index),
			text_properties: empty_range,
		},
	),
	non_text_sources: [[]],
	occurrence_fragments: [],
	occurrences: [
		{
			fragments: empty_range,
			id: Semantics.OccurrenceId.from_index(0),
			language: Inherited,
			source: NonText(Semantics.NonTextSourceId.from_index(0), ByteRange(empty_range)),
			text_properties: empty_range,
		},
	],
	relationships: [],
	role_mappings: [],
	text_properties: [],
	text_sources: [],
}

expect {
	report = Model.explore(machine, { depth: 6, key: |world| (world.path, world.leaf), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 363 and report.steps == 362 and report.depth == 5 and report.reached.len() == 2
}
