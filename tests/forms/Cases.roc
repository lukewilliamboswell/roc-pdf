import Fixture

## The forms family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase({ context : U64 }),
		Unique({ context : U64 }),
		Shared({ context : U64 }),
		Repeat({ scale : U64 }),
		Dag({ scale : U64 }),
		Deep({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase({ context }) => Fixture.scenario("showcase", context)
			Unique({ context }) => Fixture.scenario("unique", context)
			Shared({ context }) => Fixture.scenario("shared", context)
			Repeat({ scale }) => if scale > 0 {
				Fixture.scenario("repeat", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Repeat scale must be positive"
			}
			Dag({ scale }) => if scale > 0 {
				Fixture.scenario("dag", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Dag scale must be positive"
			}
			Deep({ scale }) => if scale > 0 {
				Fixture.scenario("deep", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Deep scale must be positive"
			}
			AtomicNegatives({ context }) => if context > 0 {
				Fixture.atomic_negatives(context)
			} else {
				crash "CASE_SPEC_INVALID_CONTEXT: AtomicNegatives context must be positive"
			}
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: forms fixture rejected the typed case"
		}
	}
}
