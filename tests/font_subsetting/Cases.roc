import Fixture

## The font_subsetting family's typed cases and their dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Program({ context : U64 }),
		Subset({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Program({ context }) =>
				match Fixture.font_program(context) {
					Err(_) => crash "text-layout font-program evidence failed"
					Ok(result) => result
				}

			Subset({ context }) =>
				match Fixture.font_subset(context) {
					Err(_) => crash "text-layout font-subset evidence failed"
					Ok(result) => result
				}
		}
	}
}
