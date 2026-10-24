import Fixture

## The form-text family's typed case and its dispatch, run by a fixture group app.
##
## `guard` is the runtime zero the fixture takes so that the compiler cannot
## evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Text({ guard : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Text({ guard }) =>
				match Fixture.text_form(guard) {
					Ok(value) => value
					Err(_) => crash "production-visual form text evidence failed"
				}
		}
	}
}
