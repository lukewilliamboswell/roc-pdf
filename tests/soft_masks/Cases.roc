import Fixture

## The soft_masks family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase({ context : U64 }),
		Unique({ context : U64 }),
		Shared({ context : U64 }),
		Reuse({ scale : U64 }),
		Masks({ scale : U64 }),
		Chain({ scale : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase({ context }) => Fixture.scenario("showcase", context)
			Unique({ context }) => Fixture.scenario("unique", context)
			Shared({ context }) => Fixture.scenario("shared", context)
			Reuse({ scale }) => if scale > 0 {
				Fixture.scenario("reuse", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Reuse scale must be positive"
			}
			Masks({ scale }) => if scale > 0 {
				Fixture.scenario("masks", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Masks scale must be positive"
			}
			Chain({ scale }) => if scale > 0 {
				Fixture.scenario("chain", scale)
			} else {
				crash "CASE_SPEC_INVALID_SCALE: Chain scale must be positive"
			}
			AtomicNegatives({ context }) => if context > 0 {
				Fixture.atomic_negatives(context)
			} else {
				crash "CASE_SPEC_INVALID_CONTEXT: AtomicNegatives context must be positive"
			}
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: soft_masks fixture rejected the typed case"
		}
	}
}
