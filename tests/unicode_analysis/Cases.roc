import Fixture

## The Unicode analysis family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Analysis({ repetitions : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Analysis({ repetitions }) =>
				match Fixture.unicode_analysis(repetitions) {
					Ok(result) => result
					Err(_) => crash "text-layout Unicode evidence failed"
				}
		}
	}
}
