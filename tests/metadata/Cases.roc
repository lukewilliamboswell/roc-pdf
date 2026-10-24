import Fixture

## The metadata family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase,
		Minimal,
		Unique,
		Shared,
		Share({ scale : U64 }),
		Title({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase => Fixture.scenario("showcase", 0)
			Minimal => Fixture.scenario("minimal", 0)
			Unique => Fixture.scenario("unique", 0)
			Shared => Fixture.scenario("shared", 0)
			Share({ scale }) => Fixture.scenario("share", scale)
			Title({ scale }) => Fixture.scenario("title", scale)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: metadata fixture rejected the typed case"
		}
	}
}
