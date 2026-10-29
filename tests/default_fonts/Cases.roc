import Fixture

## Public font-family and exact-style acceptance, with a resolver scale pair.
Cases :: [].{
	Case : [Sans({ context : U64 }), Serif({ context : U64 }), Mono({ context : U64 }), Override({ context : U64 }), Scale({ count : U64 }), Negatives({ context : U64 })]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Sans({ context }) => Fixture.family(Sans, context)
			Serif({ context }) => Fixture.family(Serif, context)
			Mono({ context }) => Fixture.family(Mono, context)
			Override({ context }) => Fixture.exact_override(context)
			Scale({ count }) => Fixture.scale(count)
			Negatives({ context }) => Fixture.negatives(context)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "DEFAULT_FONT_EVIDENCE: ${Str.inspect(error)}"
		}
	}
}
