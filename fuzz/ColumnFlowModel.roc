import fuzz.Model
import pdf.Document
import pdf.Layout
import pdf.Pdf

ColumnFlowModel := [].{}

State : { tokens : U64, capacity : U64, keep : Bool, chosen : Bool }

Action : [Choose({ tokens : U64, capacity : U64, keep : Bool })]

machine : Model.Machine(State, Action)
machine = {
	init: { tokens: 0, capacity: 0, keep: False, chosen: False },
	actions: |state| {
		var $actions = []
		if !state.chosen {
			for tokens in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
				for capacity in [1, 2, 3] {
					$actions = $actions.append(Choose({ tokens, capacity, keep: False }))
					$actions = $actions.append(Choose({ tokens, capacity, keep: True }))
				}
			}
		}
		$actions
	},
	step: |_, Choose({ tokens, capacity, keep })| { tokens, capacity, keep, chosen: True },
	rules: [
		Model.always("accepted column cuts keep the independently counted source and pages", |state| !state.chosen or agrees(state)),
		Model.sometimes("flows from left to right and across a physical page", |state| state.chosen and !state.keep and state.tokens == 10 and state.capacity == 3),
		Model.sometimes("retains a whole paragraph in a wider second column", |state| state.chosen and state.keep and state.tokens == 3 and state.capacity == 2),
		Model.sometimes("the minimum widow moves the last line forward", |state| state.chosen and !state.keep and state.tokens == 5 and state.capacity == 3),
		Model.sometimes("neither column can fit a mandatory keep", |state| state.chosen and state.keep and state.tokens == 7 and state.capacity == 3),
	],
}

## At 10 pt on the declared font, both "a" and space are 6 pt, so a
## line holds one word in 14 pt or two in 26 pt. Its trailing space
## comes with it except on the final line. Numerical word partitions
## give an independent expected result without measuring glyphs.
expected : State -> [Fit({ lines : U64, pages : U64 }), Impossible]
expected = |state| {
	if state.keep {
		if state.tokens <= state.capacity {
			return Fit({ lines: state.tokens, pages: 1 })
		}
		if state.tokens <= state.capacity * 2 {
			return Fit({ lines: (state.tokens + 1) // 2, pages: 1 })
		}
		return Impossible
	}
	var $remaining = state.tokens
	var $line_count = 0
	var $frame = 0
	while $remaining > 0 {
		rate = 1 + $frame % 2
		next_rate = 3 - rate
		full = state.capacity * rate
		if $remaining <= full {
			$line_count = $line_count + ($remaining + rate - 1) // rate
			return Fit({ lines: $line_count, pages: $frame // 2 + 1 })
		}
		minimum = if ($frame == 0) 2 else 1
		tail = $remaining - full
		short_end = tail <= next_rate and tail + rate > next_rate
		cut = state.capacity - if (state.capacity > minimum and short_end) 1 else 0
		$line_count = $line_count + cut
		$remaining = $remaining - cut * rate
		$frame = $frame + 1
	}
	Impossible
}

agrees : State -> Bool
agrees = |state| {
	content = Pdf.paragraph(Str.join_with(List.repeat("a", state.tokens), " "))
	block = if (state.keep) Pdf.keep_together([content]) else content
	document = article(block, 14)
	height = Layout.Unit.points(32 + (state.capacity * 16).to_i64_wrap())
	options : Pdf.Options
	options = {
		page_size: Custom({ width: 75, height }),
		theme: {
			body: { size: 10, leading: 16 },
			family: BuiltIn(Mono),
			page_margin: { left: 16, right: 16, top: 16, bottom: 16 },
		},
	}
	props = Pdf.ReportProps.{ options: options }
	match (Pdf.prepare_with_report(document, props), expected(state)) {
		(Ok({ report, .. }), Fit({ pages, lines })) => match report.facts.blocks {
			[actual] => actual.role == "P" and actual.first_page == 1 and actual.last_page == pages and actual.fragments == lines and report.facts.pages.len() == pages
			_ => False
		}
		(Err(InvalidDocument({ diagnostics: [{ feature: Feature("layout.columns.keep_conflict"), .. }], .. })), Impossible) => True
		_ => False
	}
}

article : Document.Block, Layout.Unit -> Document
article = |block, first| Pdf.document({
	contents: [Pdf.multi_column({ first, second: 26, gutter: 3, contents: [block] })],
	title: "Column cut model",
	language: "en",
})

expect {
	report = Model.explore(machine, { depth: 2, key: |state| state, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)}"
	}
	report.states == 73 and report.steps == 72 and report.reached.len() == 4
}
