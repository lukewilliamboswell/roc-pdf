import fuzz.Model
import pdf.Document
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeSources
import pdf.KernelSemantics
import pdf.KernelTextSemantics
import pdf.Pdf

BibliographyModel := [].{}

Label : [Checklist, Policy, Missing]

History : [Begin, Authored({ reversed : Bool, citations : List(Label) })]

Action : [Order(Bool), Cite(Label)]

machine : Model.Machine(History, Action)
machine = {
	init: Begin,
	actions: |state| match state {
		Begin => [Order(False), Order(True)]
		Authored({ citations, .. }) if citations.len() < 3 => [Cite(Checklist), Cite(Policy), Cite(Missing)]
		Authored(_) => []
	},
	step: |state, action| match (state, action) {
		(Begin, Order(reversed)) => Authored({ reversed, citations: [] })
		(Authored(authoring), Cite(label)) => Authored({ ..authoring, citations: authoring.citations.append(label) })
		_ => state
	},
	rules: [
		Model.always(
			"citation lookup follows the exact authored identity and preserves entry order",
			|state| match state {
				Authored(history) => agrees(history.reversed, history.citations)
				Begin => True
			},
		),
		Model.sometimes("a reordered appendix has two citations to one entry", |state| state == Authored({ reversed: True, citations: [Policy, Checklist, Policy] })),
		Model.sometimes("a missing target aborts at its first citing block", |state| state == Authored({ reversed: False, citations: [Checklist, Missing, Missing] })),
	],
}

expect {
	report = Model.explore(machine, { depth: 5, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 81 and report.steps == 80 and report.depth == 4 and report.reached.len() == 2
}

agrees : Bool, List(Label) -> Bool
agrees = |reversed, citations| {
	entries = if reversed {
		[{ target: "policy", text: "Policy" }, { target: "checklist", text: "Checklist" }]
	} else {
		[{ target: "checklist", text: "Checklist" }, { target: "policy", text: "Policy" }]
	}
	paragraphs = citations.map(|label| Pdf.rich_paragraph([Pdf.citation({ text: name(label), target: name(label) })]))
	document = Pdf.document({ title: "Citation model", language: "en", contents: paragraphs.append(Pdf.bibliography(entries)) })
	normalized = Document.normalize(document)
	expected = first_missing(citations)
	match (KernelFacadeSemantics.Plan.build(normalized, limits), expected) {
		(Err(BibliographyCitation({ block, .. })), Some(first)) => block == first
		(Ok(plan), None) => {
			store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
			declared = KernelFacadeSemantics.Plan.destinations(plan)
			links = KernelFacadeSemantics.Plan.links(plan)
			if declared.map(|target| target.name) != entries.map(|entry| entry.target) or links.len() != citations.len() or store.relationships.len() != citations.len() {
				return False
			}
			var $index = 0
			for label in citations {
				link = at(links, $index).node
				first = if (name(label) == at(entries, 0).target) 0 else 1
				entry = at(declared, first).target
				if at(store.relationships, $index) != BibliographyReference({ entry, citation: link }) {
					return False
				}
				$index = $index + 1
			}
			True
		}
		_ => False
	}
}

first_missing : List(Label) -> [None, Some(U64)]
first_missing = |citations| {
	var $index = 0
	for label in citations {
		if label == Missing {
			return Some($index)
		}
		$index = $index + 1
	}
	None
}

name : Label -> Str
name = |label| match label {
	Checklist => "checklist"
	Policy => "policy"
	Missing => "undeclared"
}

at : List(a), U64 -> a
at = |items, index| items.get(index) ?? crash "citation model index escaped"

limits : KernelFacadeSemantics.Limits
limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 4,
	max_inline_depth: 4,
	max_content_spine: 32,
	max_nodes: 16,
	max_occurrences: 12,
	max_properties: 4,
	max_source_inputs: 12,
	semantics: KernelSemantics.Limits.make({
		max_attributes: 8,
		max_content_spine: 32,
		max_fragments: 0,
		max_namespaces: 2,
		max_nodes: 16,
		max_occurrences: 12,
		max_semantic_depth: 8,
	}),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 64,
		max_inputs: 12,
		max_source_bytes: 128,
		max_source_scalars: 128,
		max_table_slots: 32,
		max_unique_sources: 12,
		unicode: { max_graphemes: 16, max_line_boundaries: 17, max_scalars: 16, max_script_runs: 8 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({
		max_text_properties: 4,
		max_text_property_bytes: 8,
		max_text_source_bytes: 128,
		max_text_source_scalars: 128,
		max_text_sources: 12,
	}),
})
