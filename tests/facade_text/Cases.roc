import Fixture

## The facade_text family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Materialize({ repetitions : U64 }),
		Prepare({ repetitions : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Materialize({ repetitions }) => Fixture.materialize(repetitions)
			Prepare({ repetitions }) => Fixture.prepare(repetitions)
		}
		match result {
			Err(_) => crash "text-layout facade text evidence failed"
			Ok(value) => value
		}
	}
}
