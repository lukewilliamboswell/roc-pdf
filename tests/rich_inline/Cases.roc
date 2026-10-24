import Fixture

## The rich_inline family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		RepeatedSegments({ count : U64 }),
		RepeatedSegmentsOrdered({ count : U64 }),
		Mixed({ context : U64 }),
		Paragraphs({ count : U64 }),
		Ordered({ context : U64 }),
		CodeFace({ context : U64 }),
		SharedSource({ count : U64 }),
		HeadingFaces({ count : U64 }),
		ScaledCode({ count : U64 }),
		LinkStyle({ count : U64 }),
		ScopedColors({ count : U64 }),
		ScopedText({ count : U64 }),
		AtomicNegatives({ context : U64 }),
		CodeHolds({ count : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			RepeatedSegments({ count }) => Fixture.repeated_segments(count)
			RepeatedSegmentsOrdered({ count }) => Fixture.repeated_segments_ordered(count)
			Mixed({ context }) => Fixture.mixed(context)
			Paragraphs({ count }) => Fixture.paragraphs(count)
			Ordered({ context }) => Fixture.ordered(context)
			CodeFace({ context }) => Fixture.code_face(context)
			SharedSource({ count }) => Fixture.shared_source(count)
			HeadingFaces({ count }) => Fixture.heading_faces(count)
			ScaledCode({ count }) => Fixture.scaled_code(count)
			LinkStyle({ count }) => Fixture.link_style(count)
			ScopedColors({ count }) => Fixture.scoped_colors(count)
			ScopedText({ count }) => Fixture.scoped_text(count)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			CodeHolds({ count }) => Fixture.code_holds(count)
		}
		match result {
			Ok(value) => value
			Err(error) => crash "CASE_EXECUTION_FAILED: rich_inline fixture rejected the typed case: ${Str.inspect(error)}"
		}
	}
}
