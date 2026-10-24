import Fixture

## The visible-text family's typed case and its dispatch, run by a fixture group app.
##
## Each `context` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Visible({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Visible({ context }) =>
				match Fixture.visible_text(context) {
					Err(_) => crash "text-layout visible text evidence failed"
					Ok(result) => result
				}
		}
	}
}
