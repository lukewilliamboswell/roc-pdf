import Fixture

## The structural_kernel family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Pages({ count : U64 }),
		Indexes({ count : U64 }),
		Outlines({ count : U64 }),
		Resources({ count : U64 }),
		Lexical({ count : U64 }),
		Deflate({ input_bytes : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Pages({ count }) => Ok(Fixture.generate_blank(count))
			Indexes({ count }) => Ok(Fixture.generate_blank_with_indexes(count))
			Outlines({ count }) => Ok(Fixture.generate_blank_with_outline(count))
			Resources({ count }) => Ok(Fixture.generate_blank_with_resource_names(count))
			Lexical({ count }) => Ok(Fixture.generate_blank_with_lexical_values(count))
			Deflate({ input_bytes }) => Ok(Fixture.generate_deflate_stream(input_bytes))
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: structural_kernel fixture rejected the typed case"
		}
	}
}
