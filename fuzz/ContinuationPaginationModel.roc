import fuzz.Model
import pdf.KernelLineLayout
import pdf.KernelPageLayout as Pagination
import pdf.Layout
import pdf.Semantics

ContinuationPaginationModel := [].{}

Profile : [PaddedSource, Paragraph]

EndFrame : [DefaultFrame, AdjacentScope]

Action : [Rows(U64), Opening(U64), Continuation(U64), End(EndFrame)]

World : { rows : U64, opening : U64, continuation : U64, ending : [Unset, Set(EndFrame)] }

# A mandatory break enters the scope and another exits it. One row-height,
# two real facade owner/policy shapes and a single scoped body isolate the
# continuation contract from keep-with-next, shaping, and container ancestry.
machine : Model.Machine(World, Action)
machine = {
	init: { rows: 0, opening: 0, continuation: 0, ending: Unset },
	actions: |world| {
		if world.rows == 0 {
			[Rows(4), Rows(5), Rows(7)]
		} else if world.opening == 0 {
			[Opening(1), Opening(2), Opening(3)]
		} else if world.continuation == 0 {
			[Continuation(1), Continuation(2), Continuation(3)]
		} else if world.ending == Unset {
			[End(DefaultFrame), End(AdjacentScope)]
		} else {
			[]
		}
	},
	step: |world, action| match action {
		Rows(rows) => { ..world, rows }
		Opening(opening) => { ..world, opening }
		Continuation(continuation) => { ..world, continuation }
		End(ending) => { ..world, ending: Set(ending) }
	},
	rules: [
		Model.always(
			"each completed document agrees with the scoped row partition",
			|world| match world.ending {
				Unset => True
				Set(ending) => agrees(world, ending, Paragraph) and agrees(world, ending, PaddedSource)
			},
		),
		Model.sometimes("padded source crosses different frames and enters an adjacent scope", |world|
			world.rows == 7 and world.opening == 1 and world.continuation == 2 and world.ending == Set(AdjacentScope)),
		Model.sometimes("paragraph relaxes widow on a resumed page", |world|
			world.rows == 4 and world.opening == 2 and world.continuation == 1 and world.ending == Set(DefaultFrame)),
		Model.sometimes("paragraph leaves space on a resumed page to avoid a widow", |world|
			world.rows == 5 and world.opening == 2 and world.continuation == 2 and world.ending == Set(DefaultFrame)),
	],
}

Owner : [Content(Semantics.OccurrenceId), SourceBlock(U64)]

Scope : [Default, Opening(U64), Continued(U64)]

Slice : { block : U64, start : U64, length : U64, inset : U64, frame : Pagination.Frame, scope : Scope }

Reference : { slices : List(Slice), relaxations : List(Pagination.Relaxation) }

# Compute the maximum rows each isolated frame admits. If it leaves an
# undersized tail, preserve two rows when possible without breaking the
# opening's head requirement. This uses only capacities and authored lengths.
partition : World, EndFrame, Profile -> Reference
partition = |world, ending, body| {
	inset = inset_of(body)
	first = { block: 0, start: 0, length: 1, inset: 0, frame: frame(1000, 1000), scope: Default }
	var $slices = [first]
	var $relaxations = []
	var $placed = 0
	while $placed < world.rows {
		opening = $placed == 0
		capacity = if (opening) world.opening else world.continuation
		remaining = world.rows - $placed
		ideal = U64.min(remaining, capacity)
		minimum = if (opening and ideal >= 2) 2 else 1
		short_tail = ideal < remaining and remaining - ideal == 1
		take = if (body == Paragraph and short_tail and ideal > minimum) ideal - 1 else ideal
		if body == Paragraph and take < remaining {
			if opening and take == 1 {
				$relaxations = $relaxations.append({ block: 1, page: $slices.len(), rank: Orphan })
			}
			if remaining - take == 1 {
				$relaxations = $relaxations.append({ block: 1, page: $slices.len(), rank: Widow })
			}
		}
		$slices = $slices.append({
			block: 1,
			start: $placed + 1,
			length: take,
			inset,
			frame: frame(capacity * 1000 + inset * 2, if (opening) 3000 else 5000),
			scope: if (opening) Opening(0) else Continued(0),
		})
		$placed = $placed + take
	}
	final_frame = if (ending == AdjacentScope) frame(2000, 7000) else frame(3000, 2000)
	final_scope = if (ending == AdjacentScope) Opening(1) else Default
	{ slices: $slices.append({ block: 2, start: world.rows + 1, length: 1, inset: 0, frame: final_frame, scope: final_scope }), relaxations: $relaxations }
}

agrees : World, EndFrame, Profile -> Bool
agrees = |world, ending, body| {
	inset = inset_of(body)
	minimum = if (body == PaddedSource) 1 else 2
	body_owner = if (body == PaddedSource) SourceBlock({ source: 0, padding: unit(inset) }) else Content(Semantics.OccurrenceId.from_index(1))
	blocks = [
		block(range(0, 1), Content(Semantics.OccurrenceId.from_index(0)), False, 1),
		block(range(1, world.rows), body_owner, True, minimum),
		block(range(world.rows + 1, 1), Content(Semantics.OccurrenceId.from_index(2)), True, 1),
	]
	template = { first: frame(1000, 1000), continuation: frame(3000, 2000), lead: NoLead }
	scope = { blocks: range(1, 1), opening: frame(world.opening * 1000 + inset * 2, 3000), continuation: frame(world.continuation * 1000 + inset * 2, 5000) }
	scopes = if ending == AdjacentScope {
		[scope, { blocks: range(2, 1), opening: frame(2000, 7000), continuation: frame(1000, 8000) }]
	} else {
		[scope]
	}
	constraints = { margins: { bottom: 1, left: 1, right: 1, top: 1 }, page: { width: 10, height: 12 } }
	limits = Pagination.Limits.make({ max_blocks: 3, max_fragments: 9, max_lines: 9, max_pages: 9, max_placements: 9 })
	rows = world.rows + 2
	lines = List.repeat(0, rows).map_with_index(|_, row| line(if (row == 0 or row == rows - 1) 0 else row - 1))
	expected = partition(world, ending, body)
	choice = match Pagination.Choice.build(blocks, [], rows, constraints, WithTemplate(template), scopes, [], limits) {
		Ok(value) => value
		Err(error) => {
			dbg "Choice build failed for ${Str.inspect(body)}: ${Str.inspect(error)}"
			return False
		}
	}
	if !choice_matches(choice, expected) {
		dbg "Choice projection differs for ${Str.inspect(body)}"
		return False
	}
	plan = match Pagination.Plan.build_with_scopes(blocks, [], lines, constraints, template, scopes, limits) {
		Ok(value) => value
		Err(error) => {
			dbg "Plan build failed for ${Str.inspect(body)}: ${Str.inspect(error)}"
			return False
		}
	}
	if !plan_matches(plan, expected, body) {
		dbg "Plan projection differs for ${Str.inspect(body)}"
		return False
	}
	True
}

expected_scopes : List(Slice) -> List(Pagination.ScopePage)
expected_scopes = |slices| slices.map_with_index(
	|slice, page| match slice.scope {
		Opening(scope) => Ok({ scope, page, opening: True })
		Continued(scope) => Ok({ scope, page, opening: False })
		Default => Err(Unscoped)
	},
).keep_oks(|entry| entry)

choice_matches : Pagination.Choice, Reference -> Bool
choice_matches = |choice, expected| {
	Pagination.Choice.page_frames(choice) == expected.slices.map(|slice| slice.frame) and
		Pagination.Choice.scope_pages(choice) == expected_scopes(expected.slices) and
			Pagination.Choice.relaxations(choice) == expected.relaxations and
				Pagination.Choice.pages(choice) == expected.slices.map_with_index(
					|_, page| {
						id: Semantics.PageId.from_index(page),
						spans: range(page, 1),
					},
				) and
					Pagination.Choice.spans(choice) == expected.slices.map_with_index(
						|slice, page| {
							block: slice.block,
							rows: range(slice.start, slice.length),
							page: Semantics.PageId.from_index(page),
							geometry: rectangle(slice),
							baseline: { x: 1, y: baseline(slice, 0) },
							leading: 1,
						},
					)
}

plan_matches : Pagination.Plan, Reference, Profile -> Bool
plan_matches = |plan, expected, body| {
	Pagination.Plan.page_frames(plan) == expected.slices.map(|slice| slice.frame) and
		Pagination.Plan.scope_pages(plan) == expected_scopes(expected.slices) and
			Pagination.Plan.relaxations(plan) == expected.relaxations and
				Pagination.Plan.pages(plan) == expected.slices.map_with_index(
					|slice, page| {
						id: Semantics.PageId.from_index(page),
						fragments: range(page, 1),
						placements: range(slice.start, slice.length),
					},
				) and
					Pagination.Plan.fragments(plan) == expected.slices.map_with_index(
						|slice, page| {
							owner: owner_of(slice.block, body),
							geometry: rectangle(slice),
							source_range: UnicodeRange(text_range(if (slice.block == 1) slice.start - 1 else 0, slice.length)),
							lines: range(slice.start, slice.length),
							page: Semantics.PageId.from_index(page),
						},
					) and
						Pagination.Plan.placements(plan) == expected.slices.map_with_index(
							|slice, page| List.repeat(0, slice.length).map_with_index(
								|_, row| {
									baseline: { x: 1, y: baseline(slice, row) },
									fragment: Semantics.FragmentId.from_index(page),
									line: slice.start + row,
								},
							),
						).join()
}

owner_of : U64, Profile -> Owner
owner_of = |index, body| if (index == 1 and body == PaddedSource) SourceBlock(0) else Content(Semantics.OccurrenceId.from_index(index))

inset_of : Profile -> U64
inset_of = |body| if (body == PaddedSource) 500 else 0

rectangle : Slice -> Layout.Rect
rectangle = |slice| { origin: { x: 1, y: baseline(slice, slice.length - 1) }, size: { width: 8, height: unit(slice.length * 1000) } }

baseline : Slice, U64 -> Layout.Unit
baseline = |slice, row| unit(11000 - slice.frame.top.raw().to_u64_wrap() - slice.inset - (row + 1) * 1000)

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

text_range : U64, U64 -> Semantics.TextRange
text_range = |start, length| { scalars: range(start, length), utf8_bytes: range(start, length) }

line : U64 -> KernelLineLayout.Line
line = |index| { advance: 1, clusters: range(index, 1), source: text_range(index, 1) }

unit : U64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw.to_i64_wrap())

frame : U64, U64 -> Pagination.Frame
frame = |height, top| { height: unit(height), top: unit(top) }

block : Semantics.IndexRange, [Content(Semantics.OccurrenceId), SourceBlock({ source : U64, padding : Layout.Unit })], Bool, U64 -> Pagination.Block
block = |lines, owner, break_before, minimum| {
	baseline_offset: 1,
	decoration: 0,
	lead: 0,
	leading: 1,
	lines,
	owner,
	policy: { break_before, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: minimum, minimum_last_lines: minimum },
	space_after: 0,
	trailing: 0,
}

expect {
	report = Model.explore(
		machine,
		{
			depth: 5,
			key: |world| (world.rows, world.opening, world.continuation, world.ending),
			verify: EveryStep,
		},
	)
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 94 and report.steps == 93 and report.depth == 4 and report.reached.len() == 3
}
