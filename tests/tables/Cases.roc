import Fixture

## The tables family's typed cases and their dispatch, for a group fixture app.
Cases :: [].{
	Case : [
		Invoice({ rows : U64 }),
		Spans({ context : U64 }),
		SplitRows({ context : U64 }),
		FooterCarry({ context : U64 }),
		Ordered({ context : U64 }),
		AtomicNegatives({ context : U64 }),
		KeptWhole({ context : U64 }),
		Styled({ rows : U64 }),
		EmptyCells({ rows : U64 }),
		Ruled({ rows : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Invoice({ rows }) => Fixture.invoice(rows)
			Spans({ context }) => Fixture.spans(context)
			SplitRows({ context }) => Fixture.split_rows(context)
			FooterCarry({ context }) => Fixture.footer_carry(context)
			Ordered({ context }) => Fixture.ordered(context)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			KeptWhole({ context }) => Fixture.kept_whole(context)
			Styled({ rows }) => Fixture.styled(rows)
			EmptyCells({ rows }) => Fixture.empty_cells(rows)
			Ruled({ rows }) => Fixture.ruled(rows)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: tables fixture rejected the typed case"
		}
	}
}
