import Fixture

## The facade_output family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Visible,
		AtomicNegative,
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Visible => Fixture.visible(0)
			AtomicNegative => Fixture.negative(0)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: facade_output fixture rejected the typed case"
		}
	}
}
