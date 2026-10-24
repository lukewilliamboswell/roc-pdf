import Fixture

## The bidi family's typed cases and their dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Uax9Vectors({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Uax9Vectors({ context }) =>
				match Fixture.uax9_vectors(context) {
					Err(_) => crash "text-layout UAX #9 vector evidence failed"
					Ok(result) => result
				}
		}
	}
}
