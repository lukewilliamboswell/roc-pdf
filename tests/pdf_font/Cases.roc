import Fixture

## The PDF font family's typed case and its dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Objects({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Objects({ context }) =>
				match Fixture.font_objects(context) {
					Err(_) => crash "text-layout PDF font object evidence failed"
					Ok(result) => result
				}
		}
	}
}
