import Fixture

## The shading_patterns family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase({ context : U64 }),
		Unique({ context : U64 }),
		Shared({ context : U64 }),
		Share({ scale : U64 }),
		Distinct({ scale : U64 }),
		Stops({ scale : U64 }),
		PatternShare({ scale : U64 }),
		PatternDistinct({ scale : U64 }),
		PatternCells({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase({ context }) => Fixture.scenario("showcase", context)
			Unique({ context }) => Fixture.scenario("unique", context)
			Shared({ context }) => Fixture.scenario("shared", context)
			Share({ scale }) => Fixture.scenario("share", scale)
			Distinct({ scale }) => Fixture.scenario("distinct", scale)
			Stops({ scale }) => Fixture.scenario("stops", scale)
			PatternShare({ scale }) => Fixture.scenario("pshare", scale)
			PatternDistinct({ scale }) => Fixture.scenario("pdistinct", scale)
			PatternCells({ scale }) => Fixture.scenario("pcells", scale)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: shading_patterns fixture rejected the typed case"
		}
	}
}
