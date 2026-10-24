import Fixture

## The page_templates family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : [
		Chapters({ chapters : U64, mode : U64 }),
		ChapterNegatives({ context : U64 }),
		Letter({ paragraphs : U64 }),
		Report({ sections : U64 }),
		Ordered({ sections : U64 }),
		Numbering({ context : U64 }),
		Images({ context : U64 }),
		AtomicNegatives({ context : U64 }),
		PageSizes({ context : U64 }),
		Backdrops({ pages : U64 }),
		SlotInset({ context : U64 }),
		Typography({ pages : U64 }),
		FurnitureGroups({ context : U64 }),
		PageLabels({ pages : U64 }),
	]

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		result = match case {
			Chapters({ chapters, mode }) => Fixture.chapters(chapters, mode)
			ChapterNegatives({ context }) => Fixture.chapter_negatives(context)
			Letter({ paragraphs }) => Fixture.letter(paragraphs)
			Report({ sections }) => Fixture.report(sections)
			Ordered({ sections }) => Fixture.ordered(sections)
			Numbering({ context }) => Fixture.numbering(context)
			Images({ context }) => Fixture.images(context)
			AtomicNegatives({ context }) => Fixture.atomic_negatives(context)
			PageSizes({ context }) => Fixture.page_sizes(context)
			Backdrops({ pages }) => Fixture.backdrops(pages)
			SlotInset({ context }) => Fixture.slot_inset(context)
			Typography({ pages }) => Fixture.typography(pages)
			FurnitureGroups({ context }) => Fixture.furniture_groups(context)
			PageLabels({ pages }) => Fixture.page_labels(pages)
		}
		match result {
			Ok(value) => value
			Err(_) => crash "CASE_EXECUTION_FAILED: page_templates fixture rejected the typed case"
		}
	}
}
