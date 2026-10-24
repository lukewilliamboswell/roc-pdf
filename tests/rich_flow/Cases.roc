import Fixture

## The rich_flow family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Lists({ count : U64 }),
		Callouts({ count : U64 }),
		Paragraphs({ count : U64 }),
		Negatives({ context : U64 }),
		Ownership({ count : U64, shared : Bool }),
		ZeroPadding({ context : U64 }),
		ScopedTables({ count : U64, mode : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Lists({ count }) => Fixture.lists(count)
			Callouts({ count }) => Fixture.callouts(count)
			Paragraphs({ count }) => Fixture.paragraphs(count)
			Negatives({ context }) => Fixture.negatives(context)
			Ownership({ count, shared }) => Fixture.ownership(count, shared)
			ZeroPadding({ context }) => Fixture.zero_padding(context)
			ScopedTables({ count, mode }) => Fixture.scoped_tables(count, mode)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: ${Str.inspect(error)}"
		}
	}
}
