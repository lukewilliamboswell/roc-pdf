import Fixture

## The font_leaves family's typed cases and their dispatch, run by a fixture group app.
##
## Each case names a fixture scenario; `scale` is the scenario's size, and the
## runtime zero for scenarios that have none.
Cases :: [].{
	Case : [
		Showcase({ scale : U64 }),
		Facts({ scale : U64 }),
		Unique({ scale : U64 }),
		Shared({ scale : U64 }),
		Share({ scale : U64 }),
		Dedupe({ scale : U64 }),
		Distinct({ scale : U64 }),
		Collide({ scale : U64 }),
		Negative({ scale : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase({ scale }) => Fixture.scenario("showcase", scale)
			Facts({ scale }) => Fixture.scenario("facts", scale)
			Unique({ scale }) => Fixture.scenario("unique", scale)
			Shared({ scale }) => Fixture.scenario("shared", scale)
			Share({ scale }) => Fixture.scenario("share", scale)
			Dedupe({ scale }) => Fixture.scenario("dedupe", scale)
			Distinct({ scale }) => Fixture.scenario("distinct", scale)
			Collide({ scale }) => Fixture.scenario("collide", scale)
			Negative({ scale }) => Fixture.scenario("negative", scale)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "production-visual font-leaf evidence failed"
		}
	}
}
