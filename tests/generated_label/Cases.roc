import Fixture

## The generated-label family's typed case and its dispatch, run by a fixture group app.
##
## `runtime_guard` is the runtime zero the fixture takes so that the compiler
## cannot evaluate the evidence at compile time.
Cases :: [].{
	Case : [
		Negative({ runtime_guard : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		match case {
			Negative({ runtime_guard }) =>
				Fixture.negative(runtime_guard) ?? crash "text-layout generated-label negative evidence failed"
		}
	}
}
