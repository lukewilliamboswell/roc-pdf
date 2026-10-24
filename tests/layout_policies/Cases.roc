import Fixture

## The layout_policies family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Lists({ context : U64 }),
		Breaks({ context : U64 }),
		Keeps({ context : U64 }),
		Relaxations({ context : U64 }),
		Groups({ count : U64 }),
		HeadingChain({ count : U64 }),
		AtomicNegatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Lists({ context }) => Fixture.lists(context)
			Breaks({ context }) => Fixture.breaks(context)
			Keeps({ context }) => Fixture.keeps(context)
			Relaxations({ context }) => Fixture.relaxations(context)
			Groups({ count }) => Fixture.groups(count)
			HeadingChain({ count }) => Fixture.heading_chain(count)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: layout_policies fixture rejected the typed case"
		}
	}
}
