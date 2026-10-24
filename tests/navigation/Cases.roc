import Fixture

## The navigation family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Showcase,
		Annotations({ scale : U64 }),
		Quads({ scale : U64 }),
		Share({ scale : U64 }),
		Appearance({ scale : U64 }),
		OutlineDeep({ scale : U64 }),
		OutlineWide({ scale : U64 }),
		Names({ scale : U64 }),
		Labels({ scale : U64 }),
		Unique,
		Retained,
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Showcase => Fixture.scenario("showcase", 0)
			Annotations({ scale }) => Fixture.scenario("annots", scale)
			Quads({ scale }) => Fixture.scenario("quads", scale)
			Share({ scale }) => Fixture.scenario("share", scale)
			Appearance({ scale }) => Fixture.scenario("appearance", scale)
			OutlineDeep({ scale }) => Fixture.scenario("outline_deep", scale)
			OutlineWide({ scale }) => Fixture.scenario("outline_wide", scale)
			Names({ scale }) => Fixture.scenario("names", scale)
			Labels({ scale }) => Fixture.scenario("labels", scale)
			Unique => Fixture.scenario("unique", 0)
			Retained => Fixture.scenario("retained", 0)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: navigation fixture rejected the typed case"
		}
	}
}
