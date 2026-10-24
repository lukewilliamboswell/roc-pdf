import Fixture
import Lowering

## The containers family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Nested,
		Sections({ count : U64 }),
		AtomicNegatives({ context : U64 }),
		Lowering,
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Nested => Fixture.nested({})
			Sections({ count }) => Fixture.sections(count)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			Lowering => Lowering.lowering({})
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: containers fixture rejected the typed case"
		}
	}
}
