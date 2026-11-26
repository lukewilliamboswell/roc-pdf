import fuzz.Model
import pdf.Font
import pdf.KernelInternationalSelection
import pdf.KernelInternationalText
import pdf.KernelUnicode
import pdf.Semantics
import "../examples/bilingual-invoice/fonts/IBMPlexSansHebrew-Regular.ttf" as hebrew : List(U8)
import "../examples/hindi-statement/fonts/IBMPlexSansDevanagari-Regular.ttf" as devanagari : List(U8)

InternationalCoverageModel := [].{}

Content : [Latin, Hebrew, Hindi]

Candidate : [Inter, ScriptFont]

State : [Begin, Source(Content), Policy({ content : Content, order : List(Candidate) })]

Action : [ChooseSource(Content), ChooseOrder(List(Candidate))]

machine : Model.Machine(State, Action)
machine = {
	init: Begin,
	actions: |state| match state {
		Begin => [ChooseSource(Latin), ChooseSource(Hebrew), ChooseSource(Hindi)]
		Source(_) => [ChooseOrder([Inter]), ChooseOrder([ScriptFont]), ChooseOrder([Inter, ScriptFont]), ChooseOrder([ScriptFont, Inter])]
		Policy(_) => []
	},
	step: |state, action| match (state, action) {
		(Begin, ChooseSource(content)) => Source(content)
		(Source(content), ChooseOrder(order)) => Policy({ content, order })
		_ => state
	},
	rules: [
		Model.always(
			"only a complete grapheme acquires an allowed face in policy order",
			|state| match state {
				Policy({ content, order }) => matches(content, order) == Ok(True)
				_ => True
			},
		),
		Model.sometimes("a Hindi grapheme with two scalar contributors selects one face", |state| state == Policy({ content: Hindi, order: [Inter, ScriptFont] })),
		Model.sometimes("a shared Latin glyph consumes the first approved face", |state| state == Policy({ content: Latin, order: [ScriptFont, Inter] })),
	],
}

expect {
	report = Model.explore(machine, { depth: 3, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 16 and report.steps == 15 and report.depth == 2 and report.reached.len() == 2
}

matches : Content, List(Candidate) -> Try(Bool, [Setup])
matches = |content, order| {
	(text, language, script, mode, bytes, scalar_count, cluster_count, required) = match content {
		Latin => ("A", Language("en"), "Hebr", UnpointedHebrewLatin, hebrew, 1, 1, [Inter, ScriptFont])
		Hebrew => ("אב", Language("he"), "Hebr", UnpointedHebrewLatin, hebrew, 2, 2, [ScriptFont])
		Hindi => ("वि", Language("hi"), "Deva", ModernHindiLatin, devanagari, 2, 1, [ScriptFont])
	}
	latin = Font.Registry.register_built_in(Font.Registry.empty, Font.ValidationLimits.default) ? |_| Setup
	other = latin.registry.register({ bytes, registration: { provision: BuiltIn, scripts: [Font.Script.from_iso15924("Latn"), Font.Script.from_iso15924(script)] }, limits: Font.ValidationLimits.default }) ? |_| Setup
	selection = other.registry.with_policy(
		order.map(|face| if (face == Inter) latin.face else other.face),
	) ? |_| Setup
	policy = KernelInternationalSelection.for_repertoire(selection.registry, selection.policy, mode) ? |_| Setup
	analysis = KernelUnicode.analyze(text, KernelUnicode.default_limits) ? |_| Setup
	range = { scalars: span(scalar_count), utf8_bytes: span(text.count_utf8_bytes()) }
	plan = KernelInternationalText.plan(text, analysis, Auto, [{ id: Semantics.OccurrenceId.from_index(0), language, source: range }], mode, { max_clusters: 2, max_items: 2, max_scalars: 2 }) ? |_| Setup
	expected = first_covered(order, required)
	actual = KernelInternationalSelection.select(policy, Semantics.TextSourceId.from_index(0), language, plan)
	Ok(
		match (expected, actual) {
			(Some(face), Ok({ selected: [entry], work })) => entry.face == face and entry.item.source == range and work.graphemes == cluster_count
			(None, Err(NoCoverage({ scalar_index: 0, .. }))) => True
			_ => False
		},
	)
}

first_covered : List(Candidate), List(Candidate) -> [None, Some(U64)]
first_covered = |candidates, required| {
	var $index = 0
	for face in candidates {
		if required.contains(face) {
			return Some($index)
		}
		$index = $index + 1
	}
	None
}

span : U64 -> Semantics.IndexRange
span = |length| Semantics.IndexRange.from_start_and_length({ start: 0, length })
