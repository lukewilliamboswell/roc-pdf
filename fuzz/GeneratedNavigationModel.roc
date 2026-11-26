import fuzz.Model
import pdf.Document
import pdf.KernelContentsSelection
import pdf.KernelStabilization
import pdf.Pdf

GeneratedNavigationModel := [].{}

Outcome : [StableAt(U64), CycleAt({ first : U64, repeat : U64 }), ExhaustedAt(U64), Invalid]

# Every state has the same page count. Only the committed anchor coordinate
# changes, so testing counts alone would falsely accept a first pass.
projection : U64 -> KernelStabilization.State
projection = |anchor| { pages: 2, values: [anchor] }

actual : List(U64), U64 -> Outcome
actual = |transitions, budget| {
	result = KernelStabilization.stabilize(
		projection(0),
		budget,
		|state, _, _| {
			anchor = transitions.get(state.values.get(0) ?? crash "missing anchor") ?? crash "missing transition"
			Ok({ candidate: anchor, state: projection(anchor) })
		},
	)
	match result {
		Ok({ candidate: Candidate(anchor), outcome: Stable({ passes, state, .. }) }) if state == projection(anchor) => StableAt(passes)
		Ok({ candidate: Candidate(anchor), outcome: Cycle({ first_seen_pass, repeated, repeated_at_pass }) }) if repeated == projection(anchor) => CycleAt({ first: first_seen_pass, repeat: repeated_at_pass })
		Ok({ candidate: Candidate(anchor), outcome: BudgetExhausted({ attempted, passes, .. }) }) if attempted == projection(anchor) => ExhaustedAt(passes)
		_ => Invalid
	}
}

## Produce the finite orbit first. Then find the earliest pair of positions
## that identify the same state.
expected : List(U64), U64 -> Outcome
expected = |transitions, budget| {
	var $orbit = [0]
	var $at = 0
	while $at < budget {
		key = $orbit.get($at) ?? crash "orbit position missing"
		$orbit = $orbit.append(transitions.get(key) ?? crash "expected transition missing")
		$at = $at + 1
	}
	var $later = 1
	while $later <= budget {
		var $earlier = 0
		while $earlier < $later {
			if $orbit.get($earlier) == $orbit.get($later) {
				return if ($earlier + 1 == $later) StableAt($later) else CycleAt({ first: $earlier, repeat: $later })
			}
			$earlier = $earlier + 1
		}
		$later = $later + 1
	}
	ExhaustedAt(budget)
}

transitions : Model.Machine(List(U64), U64)
transitions = {
	init: [],
	actions: |state| if (state.len() < 4) [0, 1, 2, 3] else [],
	step: |state, next| state.append(next),
	rules: [
		Model.always("complete states follow the exact finite orbit", |table| table.len() < 4 or [1, 2, 3, 4].all(|budget| actual(table, budget) == expected(table, budget))),
		Model.sometimes("same page count but changed anchor", |table| table == [1, 1, 2, 3] and actual(table, 1) == ExhaustedAt(1)),
		Model.sometimes("exact budget-edge success", |table| table == [1, 1, 2, 3] and actual(table, 2) == StableAt(2)),
		Model.sometimes("a four-state cycle", |table| table == [1, 2, 3, 0] and actual(table, 4) == CycleAt({ first: 0, repeat: 4 })),
	],
}

expect {
	report = Model.explore(transitions, { depth: 5, key: |table| table, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 341 and report.steps == 340 and report.reached.len() == 3
}

Heading : [First, Deeper, Anonymous, End]

heading_value : Heading -> KernelContentsSelection.Heading
heading_value = |kind| match kind {
	First => { level: 2, target: Named("first"), title: "Recovery" }
	Deeper => { level: 3, target: Named("deeper"), title: "Recovery" }
	Anonymous => { level: 2, target: NoTarget, title: "Theme" }
	End => { level: 1, target: Named("end"), title: "Appendix" }
}

headings_match : List(Heading), U8 -> Bool
headings_match = |headings, depth| {
	input = [{ level: 1, target: Named("root"), title: "Root" }].concat(headings.map(heading_value))
	result = KernelContentsSelection.select(input, { depth, overrides: [], scope: Under("root") })
	var $projected = []
	for heading in headings {
		if heading == End {
			break
		}
		if heading == First {
			$projected = $projected.append({ depth: 1, target: "first", title: "Recovery" })
		} else if heading == Deeper and depth == 2 {
			$projected = $projected.append({ depth: 2, target: "deeper", title: "Recovery" })
		}
	}
	match result {
		Ok(plan) => !$projected.is_empty() and plan.entries == $projected
		Err(EmptySelection) => $projected.is_empty()
		_ => False
	}
}

headings : Model.Machine(List(Heading), Heading)
headings = {
	init: [],
	actions: |state| [First, Deeper, Anonymous, End].keep_if(|choice| !state.contains(choice)),
	step: |state, choice| state.append(choice),
	rules: [
		Model.always("scope and relative depth preserve authored heading order", |state| headings_match(state, 1) and headings_match(state, 2)),
		Model.sometimes("identical titles retain distinct keys", |state| state == [First, Deeper]),
		Model.sometimes("an appendix stops collection", |state| state == [End, First]),
	],
}

expect {
	report = Model.explore(headings, { depth: 5, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 65 and report.steps == 64 and report.reached.len() == 2
}

term : U64 -> Str
term = |ordinal| match ordinal {
	0 => "A"
	1 => "a"
	2 => "aa"
	_ => "É"
}

index_matches : List(U64) -> Bool
index_matches = |terms| {
	entries = terms.map(|ordinal| { term: term(ordinal), destinations: ["shared"] })
	input = Pdf.document({ title: "Index", language: "en", contents: [Pdf.index({ entries: entries })] })
	ordered = [0, 1, 2, 3].keep_if(|ordinal| terms.contains(ordinal))
	match Document.resolve_generated_contents(input) {
		Err(InvalidIndex({ error: Empty, .. })) => terms.is_empty()
		Err(InvalidIndex({ error: DuplicateTerm(_), .. })) => terms.len() != ordered.len()
		Err(_) => False
		Ok(resolved) => {
			normalized = Document.normalize(resolved)
			positions = normalized.rich_paragraphs.map(|paragraph| paragraph.position)
			positions.map(|position| terms.get(position)) == ordered.map(|ordinal| Ok(ordinal))
		}
	}
}

index_terms : Model.Machine(List(U64), U64)
index_terms = {
	init: [],
	actions: |state| if (state.len() < 3) [0, 1, 2, 3] else [],
	step: |state, ordinal| state.append(ordinal),
	rules: [
		Model.always("index order depends on term bytes and preserves authored positions", index_matches),
		Model.sometimes("exact duplicate is rejected", |state| state == [2, 2]),
		Model.sometimes("distinct terms may share one destination", |state| state == [3, 2, 0]),
	],
}

expect {
	report = Model.explore(index_terms, { depth: 4, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 85 and report.steps == 84 and report.reached.len() == 2
}
