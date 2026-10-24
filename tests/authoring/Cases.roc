import Fixture

## The authoring family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Builder({ repetitions : U64 }),
		Ordered({ repetitions : U64 }),
		Layout({ repetitions : U64 }),
		Lines({ repetitions : U64 }),
		Pages({ repetitions : U64 }),
		Paginate({ repetitions : U64 }),
		Semantics({ repetitions : U64 }),
		Shape({ repetitions : U64 }),
		Simple({ repetitions : U64 }),
		SourceShared({ repetitions : U64 }),
		SourceUnique({ repetitions : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Builder({ repetitions }) => Fixture.normalize_builder(repetitions)
			Ordered({ repetitions }) => Fixture.ordered_facade(repetitions)
			Layout({ repetitions }) => Fixture.line_layout(repetitions)
			Lines({ repetitions }) => Fixture.line_facade(repetitions)
			Pages({ repetitions }) => Fixture.page_layout(repetitions)
			Paginate({ repetitions }) => Fixture.page_facade(repetitions)
			Semantics({ repetitions }) => Fixture.semantic_facade(repetitions)
			Shape({ repetitions }) => Fixture.shape_facade(repetitions)
			Simple({ repetitions }) => Fixture.normalize_simple(repetitions)
			SourceShared({ repetitions }) => Fixture.source_cache_shared(repetitions)
			SourceUnique({ repetitions }) => Fixture.source_cache_unique(repetitions)
		}
		match result {
			Err(_) => crash "text-layout facade authoring evidence failed"
			Ok(value) => value
		}
	}
}
