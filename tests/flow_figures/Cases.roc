import Fixture

## The flow_figures family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Report({ context : U64 }),
		Sections({ sections : U64 }),
		Labels({ count : U64 }),
		LabelFaces({ count : U64 }),
		AtomicNegatives({ context : U64 }),
		SpacedDecorations({ sections : U64 }),
		BoundDiagnostics({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Report({ context }) => Fixture.report(context)
			Sections({ sections }) => Fixture.sections(sections)
			Labels({ count }) => Fixture.labels(count)
			LabelFaces({ count }) => Fixture.label_faces(count)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			SpacedDecorations({ sections }) => Fixture.spaced_decorations(sections)
			BoundDiagnostics({ context }) => Fixture.bound_diagnostics(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: flow_figures fixture rejected the typed case"
		}
	}
}
