import Fixture

## The color_images family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase,
		Unique,
		Shared,
		Dedup({ scale : U64 }),
		Distinct({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase => Fixture.scenario("showcase", 0)
			Unique => Fixture.scenario("unique", 0)
			Shared => Fixture.scenario("shared", 0)
			Dedup({ scale }) => Fixture.scenario("dedup", scale)
			Distinct({ scale }) => Fixture.scenario("distinct", scale)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: color_images fixture rejected the typed case"
		}
	}
}
