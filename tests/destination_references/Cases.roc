import Fixture

## The destination_references family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Contents({ entries : U64 }),
		ContentsNegatives({ context : U64 }),
		References({ sections : U64 }),
		Styled({ context : U64 }),
		Ordered({ context : U64 }),
		Geometry({ context : U64 }),
		Negatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Contents({ entries }) => Fixture.contents(entries)
			ContentsNegatives({ context }) => Fixture.contents_negatives(context)
			References({ sections }) => Fixture.references(sections)
			Styled({ context }) => Fixture.styled(context)
			Ordered({ context }) => Fixture.ordered(context)
			Geometry({ context }) => Fixture.geometry(context)
			Negatives({ context }) => Fixture.negatives(context)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: destination_references ${Str.inspect(error)}"
		}
	}
}
