import fuzz.Model
import pdf.KernelBidiBoundary
import pdf.KernelInternationalText
import pdf.KernelUnicode
import pdf.Semantics
import pdf.Text

InternationalLineModel := [].{}

Sample : [Latin, LatinBrackets, Hebrew, HebrewBrackets]

Authored : { base : U8, levels : List(U8), source : Str, stops : List(U64) }

authored : Sample -> Authored
authored = |sample| match sample {
	Latin => { base: 0, source: "A אב 12", levels: [0, 0, 1, 1, 1, 2, 2], stops: [2, 5, 7] }
	LatinBrackets => { base: 0, source: "A (אב) 12", levels: [0, 0, 0, 1, 1, 0, 0, 2, 2], stops: [2, 7, 9] }
	Hebrew => { base: 1, source: "אב A 12", levels: [1, 1, 1, 2, 2, 2, 2], stops: [3, 5, 7] }
	HebrewBrackets => { base: 1, source: "אב (A) 12", levels: [1, 1, 1, 1, 2, 1, 1, 2, 2], stops: [3, 7, 9] }
}

State : [Start, Paragraph(Sample), Styled({ sample : Sample, split : Bool }), Line({ sample : Sample, split : Bool, stop : U64 })]

Action : [Choose(Sample), Split(Bool), Wrap(U64)]

machine : Model.Machine(State, Action)
machine = {
	init: Start,
	actions: |state| match state {
		Start => [Choose(Latin), Choose(LatinBrackets), Choose(Hebrew), Choose(HebrewBrackets)]
		Paragraph(_) => [Split(False), Split(True)]
		Styled({ sample, .. }) => authored(sample).stops.map(|stop| Wrap(stop))
		Line(_) => []
	},
	step: |state, action| match (state, action) {
		(Start, Choose(sample)) => Paragraph(sample)
		(Paragraph(sample), Split(split)) => Styled({ sample, split })
		(Styled({ sample, split }), Wrap(stop)) => Line({ sample, split, stop })
		_ => state
	},
	rules: [
		Model.always(
			"authored levels survive ownership splits and each committed line reorders independently",
			|state| match state {
				Line({ sample, split, stop }) => line_matches(sample, split, stop) == Ok(True)
				_ => True
			},
		),
		Model.sometimes("trailing space reorders when a styled RTL-containing line wraps", |state| state == Line({ sample: Latin, split: True, stop: 5 })),
		Model.sometimes("bracketed Latin and RTL base have an earlier legal line cut", |state| state == Line({ sample: HebrewBrackets, split: True, stop: 7 })),
	],
}

expect {
	report = Model.explore(machine, { depth: 4, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 37 and report.steps == 36 and report.depth == 3 and report.reached.len() == 2
}

line_matches : Sample, Bool, U64 -> Try(Bool, [Failed])
line_matches = |sample, split, stop| {
	spec = authored(sample)
	analysis = KernelUnicode.analyze(spec.source, KernelUnicode.default_limits) ? |_| Failed
	end_byte = spec.source.count_utf8_bytes()
	graphemes = analysis.graphemes
	count = graphemes.len()
	first_end = list_at(graphemes, 0).byte_end
	owners = if split {
		[owner(0, 0, 1, 0, first_end), owner(1, 1, count - 1, first_end, end_byte - first_end)]
	} else {
		[owner(0, 0, count, 0, end_byte)]
	}
	planned = KernelInternationalText.plan(spec.source, analysis, Auto, owners, UnpointedHebrewLatin, { max_clusters: 9, max_items: 9, max_scalars: 9 }) ? |_| Failed
	if planned.bidi.base_level != spec.base or planned.bidi.entries.map(|entry| entry.level) != spec.levels.map(|level| Level(level)) {
		return Ok(False)
	}
	clusters : List(Text.Cluster)
	clusters = graphemes.map_with_index(
		|grapheme, index| {
			source: { scalars: span(index, 1), utf8_bytes: span(grapheme.byte_start, grapheme.byte_end - grapheme.byte_start) },
			glyphs: span(index, 1),
			kind: OneToOne,
		},
	)
	byte_stop = list_at(graphemes, stop - 1).byte_end
	line = { clusters: span(0, stop), source: { scalars: span(0, stop), utf8_bytes: span(0, byte_stop) } }
	resolved = KernelBidiBoundary.resolve_line(planned.bidi, line, clusters, KernelBidiBoundary.Limits.make({ max_clusters: 9, max_scalars: 9, max_visual_order: 9 })) ? |_| Failed
	# Interior committed stops in this finite alphabet follow exactly one
	# ASCII space. There are no separators, embedding controls or isolates.
	var $levels = spec.levels.sublist({ start: 0, len: stop })
	if stop != count {
		$levels = set_at($levels, stop - 1, spec.base)
	}
	expected_levels = $levels
	visual = l2(expected_levels)
	if resolved.logical_source != line.source or resolved.logical_clusters != line.clusters or resolved.visual_clusters != visual {
		return Ok(False)
	}
	var $visual_start = 0
	for run in resolved.visual_runs {
		var $at = 0
		while $at < run.logical_scalars.length() {
			if $visual_start >= stop or list_at(expected_levels, list_at(visual, $visual_start)) != run.level {
				return Ok(False)
			}
			$at = $at + 1
			$visual_start = $visual_start + 1
		}
	}
	Ok($visual_start == stop)
}

## Independent L2 for the model's finite level alphabet {0,1,2}. Each
## threshold builds a new sequence by reversing its maximal matching spans.
l2 : List(U8) -> List(U64)
l2 = |levels| {
	indices = levels.map_with_index(|_, index| index)
	if levels.contains(1) {
		reverse_spans(reverse_spans(indices, levels, 2), levels, 1)
	} else {
		indices
	}
}

reverse_spans : List(U64), List(U8), U8 -> List(U64)
reverse_spans = |indices, levels, threshold| {
	var $result = List.with_capacity(indices.len())
	var $start = 0
	while $start < indices.len() {
		index = list_at(indices, $start)
		if list_at(levels, index) < threshold {
			$result = $result.append(index)
			$start = $start + 1
		} else {
			var $stop = $start + 1
			while $stop < indices.len() and list_at(levels, list_at(indices, $stop)) >= threshold {
				$stop = $stop + 1
			}
			var $next = $stop
			while $next > $start {
				$next = $next - 1
				$result = $result.append(list_at(indices, $next))
			}
			$start = $stop
		}
	}
	$result
}

owner : U64, U64, U64, U64, U64 -> KernelInternationalText.Occurrence
owner = |id, start, len, byte, byte_len| { id: Semantics.OccurrenceId.from_index(id), language: Language("he"), source: { scalars: span(start, len), utf8_bytes: span(byte, byte_len) } }

span : U64, U64 -> Semantics.IndexRange
span = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

list_at : List(a), U64 -> a
list_at = |items, index| items.get(index) ?? crash "bounded mixed-direction model lost an index"

set_at : List(a), U64, a -> List(a)
set_at = |items, index, value| items.set(index, value) ?? crash "bounded mixed-direction model escaped its finite state"
