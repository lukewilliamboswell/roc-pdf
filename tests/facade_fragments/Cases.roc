import Fixture

## The facade_fragments family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Arena({ repetitions : U64 }),
		Negative({ repetitions : U64 }),
		Output({ repetitions : U64 }),
		Prepare({ repetitions : U64 }),
		Scene({ repetitions : U64 }),
		Validate({ repetitions : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Arena({ repetitions }) => Fixture.arena(repetitions)
			Negative({ repetitions }) => Fixture.negative(repetitions)
			Output({ repetitions }) => Fixture.output_validate(repetitions)
			Prepare({ repetitions }) => Fixture.prepare(repetitions)
			Scene({ repetitions }) => Fixture.scene_validate(repetitions)
			Validate({ repetitions }) => Fixture.validate(repetitions)
		}
		match result {
			Err(_) => crash "text-layout facade fragment evidence failed"
			Ok(value) => value
		}
	}
}
