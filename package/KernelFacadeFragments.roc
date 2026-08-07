import KernelFacadeText
import KernelSemantics
import KernelTextSemantics
import Semantics
import Text

KernelFacadeFragments :: [].{
	Dimension : [Fragments, Occurrences, Pages]
	Error : [
		ArithmeticOverflow,
		InvalidOccurrence({ available : U64, run : U64 }),
		InvalidPage({ page : U64 }),
		InvalidPlacement({ placement : U64 }),
		InvalidPreliminaryFragments({ fragments : U64, reverse_entries : U64 }),
		InvalidRun({ run : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		SourceRangeMismatch({ run : U64 }),
		TextSemantics(KernelTextSemantics.Error),
	]
	Limits :: {
		max_fragments : U64,
		max_occurrences : U64,
		max_pages : U64,
	}.{
		make : { max_fragments : U64, max_occurrences : U64, max_pages : U64 } -> Limits
		make = |limits| Limits.(limits)
	}
	Work : {
		continuation_reads : U64,
		continuation_writes : U64,
		fragment_writes : U64,
		page_visits : U64,
		placement_visits : U64,
	}
	Prepared : {
		pages : List(KernelFacadeText.Page),
		placements : List(KernelFacadeText.Placement),
		text : Text.Store,
	}
	Arena :: { fragments : List(Semantics.LayoutFragment), work : Work }.{

		## Focused phase evidence stops at the flat fragment arena. The production
		## `Plan.build` additionally rebuilds the validated semantic reverse index.
		build : KernelTextSemantics.Plan, KernelFacadeText.Plan, Limits -> Try(Arena, Error)
		build = |preliminary, text, limits| build_arena(preliminary, prepare_text(text), limits)

		build_prepared : KernelTextSemantics.Plan, Prepared, Limits -> Try(Arena, Error)
		build_prepared = |preliminary, prepared, limits| build_arena(preliminary, prepared, limits)

		fragments : Arena -> List(Semantics.LayoutFragment)
		fragments = |arena| arena.fragments

		work : Arena -> Work
		work = |arena| arena.work
	}
	Plan :: { arena : Arena, semantics : KernelTextSemantics.Plan, text : KernelFacadeText.Plan }.{
		build : KernelTextSemantics.Plan, KernelFacadeText.Plan, Limits, KernelSemantics.Limits -> Try(Plan, Error)
		build = |preliminary, text, limits, semantic_limits| build_plan(preliminary, text, limits, semantic_limits)

		fragments : Plan -> List(Semantics.LayoutFragment)
		fragments = |plan| plan.arena.fragments

		semantics : Plan -> KernelTextSemantics.Plan
		semantics = |plan| plan.semantics

		text : Plan -> KernelFacadeText.Plan
		text = |plan| plan.text

		work : Plan -> Work
		work = |plan| plan.arena.work
	}
}

build_plan : KernelTextSemantics.Plan, KernelFacadeText.Plan, KernelFacadeFragments.Limits, KernelSemantics.Limits -> Try(KernelFacadeFragments.Plan, KernelFacadeFragments.Error)
build_plan = |preliminary, text, limits, semantic_limits| {
	arena = build_arena(preliminary, prepare_text(text), limits)?
	page_count = KernelFacadeText.Plan.pages(text).len()
	semantics = KernelTextSemantics.Plan.attach_fragments(preliminary, arena.fragments, page_count, page_count, semantic_limits) ? TextSemantics
	Ok(KernelFacadeFragments.Plan.{ arena, semantics, text })
}

prepare_text : KernelFacadeText.Plan -> KernelFacadeFragments.Prepared
prepare_text = |text_plan| {
	pages: KernelFacadeText.Plan.pages(text_plan),
	placements: KernelFacadeText.Plan.placements(text_plan),
	text: KernelFacadeText.Plan.text(text_plan),
}

build_arena : KernelTextSemantics.Plan, KernelFacadeFragments.Prepared, KernelFacadeFragments.Limits -> Try(KernelFacadeFragments.Arena, KernelFacadeFragments.Error)
build_arena = |preliminary, prepared, limits| {
	semantic_store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary))
	text = prepared.text
	placements = prepared.placements
	pages = prepared.pages
	if semantic_store.fragments.len() != 0 or semantic_store.occurrence_fragments.len() != 0 {
		return Err(InvalidPreliminaryFragments({ fragments: semantic_store.fragments.len(), reverse_entries: semantic_store.occurrence_fragments.len() }))
	}
	check_limit(text.runs.len(), limits.max_fragments, Fragments)?
	check_limit(semantic_store.occurrences.len(), limits.max_occurrences, Occurrences)?
	check_limit(pages.len(), limits.max_pages, Pages)?
	if placements.len() != text.runs.len() {
		return Err(InvalidPlacement({ placement: placements.len() }))
	}
	var $occurrence_index = 0
	while $occurrence_index < semantic_store.occurrences.len() {
		if list_at(semantic_store.occurrences, $occurrence_index).fragments.length() != 0 {
			return Err(InvalidPreliminaryFragments({ fragments: semantic_store.fragments.len(), reverse_entries: semantic_store.occurrence_fragments.len() }))
		}
		$occurrence_index = $occurrence_index + 1
	}
	var $placement_cursor = 0
	var $page_index = 0
	while $page_index < pages.len() {
		page = list_at(pages, $page_index)
		if page.id.index() != $page_index or page.runs.start() != $placement_cursor or !range_fits(page.runs, placements.len()) {
			return Err(InvalidPage({ page: $page_index }))
		}
		page_end = checked_add(page.runs.start(), page.runs.length())?
		while $placement_cursor < page_end {
			placement = list_at(placements, $placement_cursor)
			if placement.page.index() != $page_index or placement.run.index() != $placement_cursor {
				return Err(InvalidPlacement({ placement: $placement_cursor }))
			}
			$placement_cursor = $placement_cursor + 1
		}
		$page_index = $page_index + 1
	}
	if $placement_cursor != placements.len() {
		return Err(InvalidPlacement({ placement: $placement_cursor }))
	}
	var $continuations = List.repeat(0, semantic_store.occurrences.len())
	var $fragments = List.with_capacity(text.runs.len())
	var $run_index = 0
	while $run_index < text.runs.len() {
		run = list_at(text.runs, $run_index)
		placement = list_at(placements, $run_index)
		if run.id.index() != $run_index or placement.run.index() != $run_index {
			return Err(InvalidRun({ run: $run_index }))
		}
		occurrence_index = run.occurrence.index()
		if occurrence_index >= semantic_store.occurrences.len() {
			return Err(InvalidOccurrence({ available: semantic_store.occurrences.len(), run: $run_index }))
		}
		occurrence = list_at(semantic_store.occurrences, occurrence_index)
		occurrence_range = match occurrence.source {
			Text(_, UnicodeRange(range)) => range
			_ => return Err(SourceRangeMismatch({ run: $run_index }))
		}
		if !relative_range_fits(run.source, occurrence_range) {
			return Err(SourceRangeMismatch({ run: $run_index }))
		}
		fragment_range = {
			scalars: Semantics.Range.from_start_and_length(checked_add(occurrence_range.scalars.start(), run.source.scalars.start())?, run.source.scalars.length()),
			utf8_bytes: Semantics.Range.from_start_and_length(checked_add(occurrence_range.utf8_bytes.start(), run.source.utf8_bytes.start())?, run.source.utf8_bytes.length()),
		}
		continuation = list_at($continuations, occurrence_index)
		$continuations = list_set($continuations, occurrence_index, checked_add(continuation, 1)?)
		$fragments = $fragments.append({
			content_stream: Semantics.ContentStreamId.from_index(placement.page.index()),
			continuation_index: continuation,
			id: Semantics.FragmentId.from_index($run_index),
			occurrence: run.occurrence,
			page: placement.page,
			source_range: UnicodeRange(fragment_range),
		})
		$run_index = $run_index + 1
	}
	Ok(
		KernelFacadeFragments.Arena.{
			fragments: $fragments,
			work: {
				continuation_reads: text.runs.len(),
				continuation_writes: text.runs.len(),
				fragment_writes: text.runs.len(),
				page_visits: pages.len(),
				placement_visits: placements.len(),
			},
		},
	)
}

relative_range_fits : Semantics.TextRange, Semantics.TextRange -> Bool
relative_range_fits = |relative, occurrence| range_fits(relative.scalars, occurrence.scalars.length()) and range_fits(relative.utf8_bytes, occurrence.utf8_bytes.length())

range_fits : Semantics.Range, U64 -> Bool
range_fits = |range, available| range.start() <= available and range.length() <= available - range.start()

check_limit : U64, U64, KernelFacadeFragments.Dimension -> Try({}, KernelFacadeFragments.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeFragments.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated facade-fragment index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated facade-fragment update escaped"
	}
}
