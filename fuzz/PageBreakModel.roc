import fuzz.Model
import pdf.KernelPageLayout
import pdf.Layout
import pdf.Semantics

PageBreakModel := [].{}

Kind : [Plain, Flexible, Guarded, Atomic, HeadingKeep, AuthorKeep, FooterCarry, Bind, Force]

Action : [PageHeight(U64), Append(Kind)]

World : { height : U64, kinds : List(Kind) }

# Unit-height measured rows isolate break policy from shaping, decoration
# and container geometry. Three blocks can combine a keep on either side
# of a split or forced break while keeping the full state space enumerable.
machine : Model.Machine(World, Action)
machine = {
	init: { height: 0, kinds: [] },
	actions: |world| {
		if world.height == 0 {
			[PageHeight(1), PageHeight(2), PageHeight(3), PageHeight(4)]
		} else if world.kinds.len() < 3 {
			[Append(Plain), Append(Flexible), Append(Guarded), Append(Atomic), Append(HeadingKeep), Append(AuthorKeep), Append(FooterCarry), Append(Bind), Append(Force)]
		} else {
			[]
		}
	},
	step: |world, action| match action {
		PageHeight(height) => { ..world, height }
		Append(kind) => { ..world, kinds: world.kinds.append(kind) }
	},
	rules: [
		Model.always("the first page matches the enumerated legal cuts", agrees),
		witness("ties between fitting cuts", 2, [Flexible]),
		witness("heading keep competes with an orphan split", 2, [HeadingKeep, Guarded]),
		witness("orphan minimum outranks widow minimum", 2, [Guarded]),
		witness("forced break leaves space on the first page", 3, [Plain, Force]),
		witness("required keep makes every fitting cut illegal", 1, [Bind, Plain]),
		witness("forced break conflicts with a required keep", 2, [Bind, Force]),
		witness("required keep at the end is rejected", 2, [Plain, Bind]),
		witness("an atomic block does not fit", 1, [Atomic]),
	],
}

witness : Str, U64, List(Kind) -> Model.Rule(World, Action)
witness = |name, height, kinds| Model.sometimes(name, |world| world.height == height and world.kinds == kinds)

Block : { rows : U64, minimum : U64, keep : KernelPageLayout.Keep, forced : Bool, atomic : Bool }

describe : Kind -> Block
describe = |kind| {
	plain = { rows: 1, minimum: 1, keep: NoKeep, forced: False, atomic: False }
	match kind {
		Plain => plain
		Flexible => { ..plain, rows: 3 }
		Guarded => { ..plain, rows: 3, minimum: 2 }
		Atomic => { ..plain, rows: 3, atomic: True }
		HeadingKeep => { ..plain, keep: Preferred(HeadingKeep) }
		AuthorKeep => { ..plain, keep: Preferred(AuthorKeep) }
		FooterCarry => { ..plain, keep: Preferred(FooterCarry) }
		Bind => { ..plain, keep: Required }
		Force => { ..plain, forced: True }
	}
}

Decision : { rows : U64, relaxed : List(KernelPageLayout.Relaxation) }

Observation : Try(Decision, KernelPageLayout.Error)

agrees : World -> Bool
agrees = |world| {
	if world.kinds.is_empty() {
		return True
	}
	blocks = world.kinds.map(describe)
	actual = observed(blocks, world.height)
	expected = reference(blocks, world.height)
	if actual != expected {
		crash "first page for ${Str.inspect(world)}: expected ${Str.inspect(expected)}, got ${Str.inspect(actual)}"
	}
	True
}

# The roomy continuation frame prevents a later fit failure from hiding
# the first page's decision. No synthetic Unicode or shaping is needed.
observed : List(Block), U64 -> Observation
observed = |blocks, height| {
	var $built = []
	var $start = 0
	for block in blocks {
		$built = $built.append({
			baseline_offset: 1,
			decoration: 0,
			lead: 0,
			leading: 1,
			lines: Semantics.IndexRange.from_start_and_length({ start: $start, length: block.rows }),
			owner: Content(Semantics.OccurrenceId.from_index($built.len())),
			policy: { break_before: block.forced, keep_together: block.atomic, keep_with_next: block.keep, minimum_first_lines: block.minimum, minimum_last_lines: block.minimum },
			space_after: 0,
			trailing: 0,
		})
		$start = $start + block.rows
	}
	limits = KernelPageLayout.Limits.make({ max_blocks: 3, max_fragments: 9, max_lines: 9, max_pages: 9, max_placements: 9 })
	geometry = { margins: { bottom: 0, left: 0, right: 0, top: 0 }, page: { height: 9, width: 1 } }
	template = { first: { height: Layout.Unit.from_raw((height * 1000).to_i64_wrap()), top: 0 }, continuation: { height: 9, top: 0 }, lead: NoLead }
	choice = KernelPageLayout.Choice.build($built, [], $start, geometry, WithTemplate(template), [], [], limits)?
	var $rows = 0
	for span in KernelPageLayout.Choice.spans(choice) {
		if span.page.index() == 0 {
			if span.rows.start() != $rows or span.rows.length() == 0 {
				crash "first-page spans do not cover a contiguous prefix"
			}
			$rows = $rows + span.rows.length()
		}
	}
	Ok({ rows: $rows, relaxed: KernelPageLayout.Choice.relaxations(choice).keep_if(|event| event.page == 0) })
}

# Enumerate prefixes from the original row counts, with rank comparisons
# independent of the production walk, score encoding and cursor state.
reference : List(Block), U64 -> Observation
reference = |blocks, height| {
	var $forced = NoCut
	var $total = 0
	var $index = blocks.len()
	while $index > 0 {
		$index = $index - 1
		block = at(blocks, $index)
		if block.keep == Required {
			if $index + 1 == blocks.len() {
				return Err(KeepConflict(RequiredKeepAtEnd({ block: $index })))
			}
			if at(blocks, $index + 1).forced {
				return Err(KeepConflict(BreakAfterRequiredKeep({ block: $index, next: $index + 1 })))
			}
		}
		$total = $total + block.rows
	}
	var $prefix = 0
	for block in blocks {
		if $prefix > 0 and block.forced {
			$forced = Cut($prefix)
			break
		}
		$prefix = $prefix + block.rows
	}
	match $forced {
		Cut(position) if position <= height => return Ok({ rows: position, relaxed: cut_relaxations(blocks, position) })
		NoCut if $total <= height => return Ok({ rows: $total, relaxed: [] })
		_ => {}
	}
	var $best = NoCandidate
	var $rows = 1
	while $rows <= height {
		placement = locate(blocks, $rows)
		block = at(blocks, placement.block)
		ends_block = placement.row == block.rows
		valid = if ends_block {
			block.keep != Required
		} else {
			!block.atomic and !(placement.block > 0 and at(blocks, placement.block - 1).keep == Required and placement.row < block.minimum)
		}
		if valid {
			candidate = { rows: $rows, relaxed: cut_relaxations(blocks, $rows) }
			if match $best {
				NoCandidate => True
				Candidate(previous) => prefers(candidate, previous)
			} {
				$best = Candidate(candidate)
			}
		}
		$rows = $rows + 1
	}
	match $best {
		Candidate(decision) => Ok(decision)
		NoCandidate => Err(no_fit(blocks, height))
	}
}

cut_relaxations : List(Block), U64 -> List(KernelPageLayout.Relaxation)
cut_relaxations = |blocks, rows| {
	end = locate(blocks, rows)
	block = at(blocks, end.block)
	if end.row == block.rows {
		return abandoned_keep(blocks, end.block)
	}
	var $events = []
	if end.row < block.minimum {
		$events = if (end.block > 0) abandoned_keep(blocks, end.block - 1) else []
		$events = $events.append({ block: end.block, page: 0, rank: Orphan })
	}
	if block.rows - end.row < block.minimum {
		$events = $events.append({ block: end.block, page: 0, rank: Widow })
	}
	$events
}

abandoned_keep : List(Block), U64 -> List(KernelPageLayout.Relaxation)
abandoned_keep = |blocks, block| match at(blocks, block).keep {
	Preferred(rank) => [{ block, page: 0, rank }]
	_ => []
}

prefers : Decision, Decision -> Bool
prefers = |left, right| {
	for rank in [HeadingKeep, AuthorKeep, FooterCarry, Orphan, Widow] {
		left_relaxed = left.relaxed.any(|event| event.rank == rank)
		right_relaxed = right.relaxed.any(|event| event.rank == rank)
		if left_relaxed != right_relaxed {
			return right_relaxed
		}
	}
	left.rows > right.rows
}

no_fit : List(Block), U64 -> KernelPageLayout.Error
no_fit = |blocks, height| {
	next = locate(blocks, height + 1)
	unit = at(blocks, next.block)
	required = next.before + (if (unit.atomic) unit.rows else 1)
	var $from = next.block
	while $from > 0 {
		$from = $from - 1
		if at(blocks, $from).keep == Required {
			return KeepConflict(ChainTooTall({ available: height * 1000, block: $from, next: $from + 1, required: required * 1000 }))
		}
	}
	Oversize({ available: height * 1000, block: next.block, required: required * 1000 })
}

locate : List(Block), U64 -> { before : U64, block : U64, row : U64 }
locate = |blocks, rows| {
	var $index = 0
	var $before = 0
	for block in blocks {
		if rows <= $before + block.rows {
			return { before: $before, block: $index, row: rows - $before }
		}
		$before = $before + block.rows
		$index = $index + 1
	}
	crash "model cut is outside the authored rows"
}

at : List(Block), U64 -> Block
at = |blocks, index| match blocks.get(index) {
	Ok(block) => block
	Err(OutOfBounds) => crash "model block index is outside the authored blocks"
}

expect {
	report = Model.explore(machine, { depth: 5, key: |world| (world.height, world.kinds), verify: EveryStep })
	report.verdict == Holds(Exhausted) and report.states == 3281 and report.steps == 3280 and report.depth == 4 and report.reached.len() == 8
}
