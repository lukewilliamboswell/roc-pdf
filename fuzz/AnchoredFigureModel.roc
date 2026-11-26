import fuzz.Model
import pdf.Color
import pdf.Layout
import pdf.Pdf
import pdf.Scene

AnchoredFigureModel := [].{}

State : { capacity : U64, drawing : U64, lines : U64, lead : [Pending, Lead(U64)] }

Action : [Capacity(U64), Drawing(U64), Lines(U64), Before(U64)]

machine : Model.Machine(State, Action)
machine = {
	init: { capacity: 0, drawing: 0, lines: 0, lead: Pending },
	actions: |state| {
		if state.capacity == 0 {
			[Capacity(82), Capacity(96), Capacity(113), Capacity(114)]
		} else if state.drawing == 0 {
			[Drawing(30), Drawing(48), Drawing(64)]
		} else if state.lines == 0 {
			[Lines(1), Lines(2), Lines(3)]
		} else if state.lead == Pending {
			[Before(0), Before(20), Before(55)]
		} else {
			[]
		}
	},
	step: |state, action| match action {
		Capacity(capacity) => { ..state, capacity }
		Drawing(drawing) => { ..state, drawing }
		Lines(lines) => { ..state, lines }
		Before(lead) => { ..state, lead: Lead(lead) }
	},
	rules: [
		Model.always(
			"the whole pair stays, defers once, or rejects at both authored parts",
			|state| match state.lead {
				Pending => True
				Lead(spacer) => agrees(state, spacer)
			},
		),
		witness("the pair fits after preceding context", 114, 30, 1, 0),
		witness("deferral makes an exact empty-frame fit", 114, 64, 2, 55),
		witness("one unit less than the empty-frame fit rejects", 113, 64, 2, 55),
	],
}

witness : Str, U64, U64, U64, U64 -> Model.Rule(State, Action)
witness = |name, capacity, drawing, lines, spacer| Model.sometimes(name, |state| state == { capacity, drawing, lines, lead: Lead(spacer) })

agrees : State, U64 -> Bool
agrees = |state, spacer| {
	tint : Color.SourceValue
	tint = "#145B68"
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 80, height: state.drawing.to_i64_wrap() }), color: tint })
	var $paragraph = [Pdf.text("Introducing the figure.")]
	var $line = 1
	while $line < state.lines {
		$paragraph = $paragraph.append(Pdf.line_break).append(Pdf.text("A new anchor line."))
		$line = $line + 1
	}
	document = Pdf.document({
		title: "Anchor placement model",
		language: "en-AU",
		contents: [
			Pdf.paragraph("Preceding context."),
			Pdf.spacer(Layout.Unit.points(spacer.to_i64_wrap())),
			Pdf.anchored_figure($paragraph, { drawing, alt: "A teal patch", caption: "Diagram caption" }),
		],
	})
	options : Pdf.Options
	options = {
		page_size: Custom({ width: 310, height: Layout.Unit.points((state.capacity + 40).to_i64_wrap()) }),
		theme: { page_margin: { top: 20, bottom: 20, left: 20, right: 20 }, paragraph_spacing: 4, body: { size: 10, leading: 14 } },
	}
	# Body lines and the caption each occupy one leading per line.
	# Two paragraph gaps separate the anchor, drawing and caption.
	required = state.lines * 14 + state.drawing + 22
	total = required + 18 + spacer
	expected_page = if (total <= state.capacity) 1 else 2
	match Pdf.prepare_with_report(document, { options: options }) {
		Ok({ report, .. }) => {
			required <= state.capacity and report.facts.pages.len() == expected_page and
				report.facts.blocks.map(|block| (block.role, block.first_page, block.last_page)) ==
					[("P", 1, 1), ("P", expected_page, expected_page), ("Figure", expected_page, expected_page), ("Caption", expected_page, expected_page)]
		}
		Err(InvalidDocument({ diagnostics: [{ feature: Feature("layout.anchored_figure_fit"), details: ["contents[2].anchor", "contents[2].figure"], .. }], .. })) => required > state.capacity
		Err(error) => crash "anchor model ${Str.inspect(state)} hit ${Pdf.Error.to_inspect(error)}"
	}
}

expect {
	report = Model.explore(machine, { depth: 5, key: |state| (state.capacity, state.drawing, state.lines, state.lead), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 161 and report.steps == 160 and report.depth == 4 and report.reached.len() == 3
}
