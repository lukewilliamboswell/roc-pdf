import fuzz.Model
import pdf.KernelSemantics
import pdf.Semantics

GroupingContainmentModel := [].{}

Role : [Division, Document, Paragraph, Part, Section, Span, Title]

Action : [Enter(Role), End(Role)]

World : { path : List(Role), done : Bool }

# ISO 32000-2 Table 365 and Annex L.2. This small set distinguishes the
# effective ancestor's row from the rows for the two grouping types.
machine : Model.Machine(World, Action)
machine = {
	init: { path: [Document], done: False },
	actions: |world| {
		if world.done {
			return []
		}
		endings = [End(Paragraph), End(Span)]
		if (world.path.len() == 5) endings else endings.concat([Enter(Division), Enter(Part), Enter(Section), Enter(Title)])
	},
	step: |world, action| match action {
		Enter(group) => { ..world, path: world.path.append(group) }
		End(leaf) => { path: world.path.append(leaf), done: True }
	},
	rules: [
		Model.always("typed edges agree with the authored ancestor path", agrees),
		Model.sometimes("two Parts retain the Document restriction on Span", |world| world.path == [Document, Part, Part, Span]),
		Model.sometimes("two Divs retain the Document restriction on Span", |world| world.path == [Document, Division, Division, Span]),
		Model.sometimes("a nearer Title permits Span through Div", |world| world.path == [Document, Part, Title, Division, Span]),
		Model.sometimes("Div inherits the Part restriction on Span within Title", |world| world.path == [Document, Title, Part, Division, Span]),
	],
}

role_name : Role -> Str
role_name = |role| match role {
	Division => "Div"
	Document => "Document"
	Paragraph => "P"
	Part => "Part"
	Section => "Sect"
	Span => "Span"
	Title => "Title"
}

# Scan outwards for each edge. The planner carries context downwards.
first_illegal_edge : List(Role) -> [Legal, Illegal({ child : U64, parent : U64 })]
first_illegal_edge = |roles| {
	var $child_index = 1
	while $child_index < roles.len() {
		child = roles.get($child_index) ?? crash "checked role path escaped"
		var $ancestor_index = $child_index - 1
		var $part = False
		while !([Document, Section, Title].contains(roles.get($ancestor_index) ?? crash "checked ancestor escaped")) {
			$part = $part or roles.get($ancestor_index) == Ok(Part)
			$ancestor_index = $ancestor_index - 1
		}
		ancestor = roles.get($ancestor_index) ?? crash "checked ancestor escaped"
		allowed = match ancestor {
			Document | Section => child != Span
			Title => child != Section and child != Title
			_ => crash "role path has no non-grouping ancestor"
		}
		if !allowed or ($part and child == Span) {
			return Illegal({ child: $child_index, parent: $child_index - 1 })
		}
		$child_index = $child_index + 1
	}
	Legal
}

agrees : World -> Bool
agrees = |world| {
	if !world.done {
		return True
	}
	store = store_for_roles(world.path.map(role_name))
	match (first_illegal_edge(world.path), KernelSemantics.Plan.build_text_validated(store, [], 1, 1, limits)) {
		(Legal, Ok(plan)) => {
			work = KernelSemantics.Plan.work(plan)
			KernelSemantics.Plan.store(plan).nodes == store.nodes and
				work.containment_edges == world.path.len() - 1 and work.node_visits == world.path.len()
		}
		(Illegal(expected), Err(IllegalContainment(actual))) => expected == actual
		_ => False
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
	report = Model.explore(machine, { depth: 6, key: |world| (world.path, world.done), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1023 and report.steps == 1022 and report.depth == 5 and report.reached.len() == 4
}
