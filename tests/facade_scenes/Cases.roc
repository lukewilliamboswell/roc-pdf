import Fixture

## The facade_scenes family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Arena({ repetitions : U64 }),
		Negative({ repetitions : U64 }),
		Prepare({ repetitions : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Arena({ repetitions }) => Fixture.arena(repetitions)
			Negative({ repetitions }) => Fixture.negative(repetitions)
			Prepare({ repetitions }) => Fixture.prepare(repetitions)
		}
		match result {
			Err(_) => crash "text-layout facade scene evidence failed"
			Ok(value) => value
		}
	}
}
