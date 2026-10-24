import Fixture

## The source_blocks family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Foregrounds({ kind : U64, lines : U64, colored : Bool }),
		ForegroundNegatives({ context : U64 }),
		HanOnly({ same_body : Bool }),
		Multiple({ context : U64 }),
		OnlyText({ context : U64 }),
		BareBlank({ context : U64 }),
		Han({ context : U64 }),
		Defaults({ context : U64 }),
		Blank({ lines : U64 }),
		Short({ context : U64 }),
		Long({ lines : U64 }),
		NearBottom({ lines : U64 }),
		Wrapping({ context : U64 }),
		Unicode({ context : U64 }),
		Negatives({ context : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Foregrounds({ kind, lines, colored }) => Fixture.foregrounds(kind, lines, colored)
			ForegroundNegatives({ context }) => Fixture.foreground_negatives(context)
			HanOnly({ same_body }) => Fixture.han_only(same_body)
			Multiple({ context }) => Fixture.multiple(context)
			OnlyText({ context }) => Fixture.only_text(context)
			BareBlank({ context }) => Fixture.bare_blank(context)
			Han({ context }) => Fixture.han(context)
			Defaults({ context }) => Fixture.defaults(context)
			Blank({ lines }) => Fixture.blank(lines)
			Short({ context }) => Fixture.short(context)
			Long({ lines }) => Fixture.long(lines)
			NearBottom({ lines }) => Fixture.near_bottom(lines)
			Wrapping({ context }) => Fixture.wrapping(context)
			Unicode({ context }) => Fixture.unicode(context)
			Negatives({ context }) => Fixture.negatives(context)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "SOURCE_BLOCK_EVIDENCE: ${Str.inspect(error)}"
		}
	}
}
