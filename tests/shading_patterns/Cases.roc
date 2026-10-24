import Fixture

## The shading_patterns family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase,
		Unique,
		Shared,
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
			Showcase => Fixture.scenario("showcase", 0)
			Unique => Fixture.scenario("unique", 0)
			Shared => Fixture.scenario("shared", 0)
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
