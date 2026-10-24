import Fixture

## The shaping family's typed case and its dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Shape({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Shape({ context }) =>
				match Fixture.shaping(context) {
					Err(_) => crash "text-layout shaping evidence failed"
					Ok(result) => result
				}
		}
	}
}
