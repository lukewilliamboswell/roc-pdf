import Fixture

## The custom_block family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Report({ context : U64 }),
		Defaults({ context : U64 }),
		Callouts({ callouts : U64 }),
		AtomicNegatives({ context : U64 }),
		RichCallouts({ callouts : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Report({ context }) => Fixture.report(context)
			Defaults({ context }) => Fixture.defaults(context)
			Callouts({ callouts }) => Fixture.callouts(callouts)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			RichCallouts({ callouts }) => Fixture.rich_callouts(callouts)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: custom_block fixture rejected the typed case: ${Str.inspect(error)}"
		}
	}
}
