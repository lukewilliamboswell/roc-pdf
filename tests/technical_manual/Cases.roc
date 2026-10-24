import Fixture

## The technical_manual family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Manual({ chapters : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		Manual({ chapters }) = case
		match Fixture.manual(chapters) {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: ${Str.inspect(error)}"
		}
	}
}
