import fuzz.Model
import pdf.Color
import pdf.Layout
import pdf.Pdf
import pdf.Scene

AnchoredFigureModel := [].{

	## Exercise the same independent fit oracle with a forced break or PDF output.
	check : { capacity : U64, drawing : U64, lines : U64, spacer : U64, force_break : Bool, emit : Bool } -> Bool
	check = |{ capacity, drawing, lines, spacer, force_break, emit }|
		agrees({ capacity, drawing, lines, lead: Lead(spacer) }, spacer, { force_break, emit })
}

State : { capacity : U64, drawing : U64, lines : U64, lead : [Pending, Lead(U64)] }

Action : [Capacity(U64), Drawing(U64), Lines(U64), Before(U64)]

machine : Model.Machine(State, Action)
machine = {
	init: { capacity: 0, drawing: 0, lines: 0, lead: Pending },
	actions: |state| {
		if state.capacity == 0 {
			[Capacity(82000), Capacity(96000), Capacity(113999), Capacity(114000)]
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
				Lead(spacer) => agrees(state, spacer, { force_break: False, emit: False })
			},
		),
		witness("the pair fits after preceding context", 114000, 30, 1, 0),
		witness("deferral makes an exact empty-frame fit", 114000, 64, 2, 55),
		witness("one unit less than the empty-frame fit rejects", 113999, 64, 2, 55),
	],
}

witness : Str, U64, U64, U64, U64 -> Model.Rule(State, Action)
witness = |name, capacity, drawing, lines, spacer| Model.sometimes(name, |state| state == { capacity, drawing, lines, lead: Lead(spacer) })

agrees : State, U64, { force_break : Bool, emit : Bool } -> Bool
agrees = |state, spacer, { force_break, emit }| {
	tint : Color.SourceValue
	tint = "#145B68"
	drawing = Scene.Drawing.empty.rectangle({ bounds: Layout.rect({ x: 0, y: 0, width: 80, height: state.drawing.to_i64_wrap() }), color: tint })
	var $paragraph = [Pdf.text("Introducing the figure.")]
	var $line = 1
	while $line < state.lines {
		$paragraph = $paragraph.append(Pdf.line_break).append(Pdf.text("A new anchor line."))
		$line = $line + 1
	}
	context = Pdf.paragraph("Preceding context.")
	anchor = Pdf.anchored_figure($paragraph, { drawing, alt: "A teal patch", caption: "Diagram caption" })
	contents = if force_break {
		[context, Pdf.page_break, anchor]
	} else {
		[context, Pdf.spacer(Layout.Unit.points(spacer.to_i64_wrap())), anchor]
	}
	document = Pdf.document({ title: "Anchor placement model", language: "en-AU", contents })
	# Page sides use whole points. The bottom margin can reserve a millipoint.
	frame_points = (state.capacity + 999) / 1000
	bottom = 20000 + frame_points * 1000 - state.capacity
	options : Pdf.Options
	options = {
		page_size: Custom({ width: 310, height: Layout.Unit.points((frame_points + 40).to_i64_wrap()) }),
		theme: { page_margin: { top: 20, bottom: Layout.Unit.millipoints(bottom.to_i64_wrap()), left: 20, right: 20 }, paragraph_spacing: 4, body: { size: 10, leading: 14 } },
	}
	# Body lines and the caption each occupy one leading per line.
	# Two paragraph gaps separate the anchor, drawing and caption.
	required = (state.lines * 14 + state.drawing + 22) * 1000
	total = required + (18 + spacer) * 1000
	expected_page = if (force_break or total > state.capacity) 2 else 1
	match Pdf.prepare_with_report(document, { options: options }) {
		Ok({ report, prepared, .. }) => {
			if emit {
				match Pdf.to_bytes_prepared(prepared) {
					Ok(bytes) if bytes.take_first(8) == "%PDF-2.0".to_utf8() => {}
					_ => return False
				}
			}
			required <= state.capacity and report.facts.pages.len() == expected_page and
				report.facts.blocks.map(|block| (block.path, block.role, block.first_page, block.last_page)) ==
					[
						("contents[0]", "P", 1, 1),
						("contents[2].anchor", "P", expected_page, expected_page),
						("contents[2].figure", "Figure", expected_page, expected_page),
						("contents[2].figure.caption", "Caption", expected_page, expected_page),
					]
		}
		Err(error) => {
			if !located_rejection(error) {
				crash "anchor model ${Str.inspect(state)} hit ${Pdf.Error.to_inspect(error)}"
			}
			required > state.capacity and (!emit or (rejects(Pdf.to_bytes_with(document, options)) and rejects(Pdf.to_chunks_with(document, options))))
		}
	}
}

located_rejection : Pdf.Error -> Bool
located_rejection = |error| match error {
	InvalidDocument({ diagnostics: [{ feature: Feature("layout.anchored_figure_fit"), details: ["contents[2].anchor", "contents[2].figure"], .. }], truncation: Complete, .. }) => True
	_ => False
}

rejects : Try(a, Pdf.Error) -> Bool
rejects = |result| match result {
	Err(error) => located_rejection(error)
	_ => False
}

expect {
	report = Model.explore(machine, { depth: 5, key: |state| (state.capacity, state.drawing, state.lines, state.lead), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 161 and report.steps == 160 and report.depth == 4 and report.reached.len() == 3
}

expect AnchoredFigureModel.check({ capacity: 114000, drawing: 64, lines: 2, spacer: 0, force_break: True, emit: True })

expect AnchoredFigureModel.check({ capacity: 113999, drawing: 64, lines: 2, spacer: 0, force_break: True, emit: True })
