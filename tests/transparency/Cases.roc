import Fixture

## The transparency family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase,
		Unique,
		Shared,
		Share({ scale : U64 }),
		States({ scale : U64 }),
		Nest({ scale : U64 }),
		Forms({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase => Fixture.scenario("showcase", 0)
			Unique => Fixture.scenario("unique", 0)
			Shared => Fixture.scenario("shared", 0)
			Share({ scale }) => Fixture.scenario("share", scale)
			States({ scale }) => Fixture.scenario("states", scale)
			Nest({ scale }) => Fixture.scenario("nest", scale)
			Forms({ scale }) => Fixture.scenario("forms", scale)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: transparency fixture rejected the typed case"
		}
	}
}
