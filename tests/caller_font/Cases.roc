import Fixture

## The caller_font family's typed cases and their dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		VisibleText({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			VisibleText({ context }) =>
				match Fixture.visible_text(context) {
					Err(_) => crash "text-layout caller-font text evidence failed"
					Ok(result) => result
				}
		}
	}
}
