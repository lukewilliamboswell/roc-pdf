import fuzz.Model
import fuzz.Solve
import pdf.KernelPageLayout
import pdf.KernelSpan
import pdf.Layout
import pdf.Semantics

FootnotePaginationModel := [].{}

World : { rows : List(U8), height : U64 }

Action : [Add(U8), Finalize(U64)]

machine : Model.Machine(World, Action)
machine = {
	init: { rows: [], height: 0 },
	actions: |world| if world.height > 0 {
		[]
	} else if world.rows.len() < 3 {
		[Add(0), Add(1), Add(2), Add(3), Add(4), Finalize(8000), Finalize(9000), Finalize(16000)]
	} else {
		[Finalize(8000), Finalize(9000), Finalize(16000)]
	},
	step: |world, action| match action {
		Add(row) => { ..world, rows: world.rows.append(row) }
		Finalize(height) => { ..world, height }
	},
	rules: [
		Model.always("each committed cut fits once per earliest citation, or rejects only without a legal cut", |world| world.height == 0 or agrees(world)),
		Model.sometimes("repeat has no reserve", |world| world.height == 8000 and world.rows == [1, 1]),
		Model.sometimes("exact note fit", |world| world.height == 9000 and world.rows == [2]),
		Model.sometimes("no legal cut", |world| world.height == 8000 and world.rows == [2]),
		Model.sometimes("two notes enter one citation line", |world| world.height == 16000 and world.rows == [3]),
		Model.sometimes("explicit break before repeated work", |world| world.height == 16000 and world.rows == [1, 4, 1]),
	],
}

first : List(U8), U8 -> U64
first = |rows, wanted| {
	var $index = 0
	for code in rows {
		if code == wanted or code == 3 {
			return $index
		}
		$index = $index + 1
	}
	rows.len()
}

oracle : World, U64, U64 -> [Impossible, Ends(List(U64))]
oracle = |world, first_a, first_b| {
	var $ends = []
	var $start = 0
	while $start < world.rows.len() {
		var $end = $start + 1
		var $best = $start
		while $end <= world.rows.len() {
			row = $end - 1
			if row > $start and (world.rows.get(row) ?? 0) == 4 {
				break
			}
			a = if (first_a >= $start and first_a < $end) 7000 else 0
			b = if (first_b >= $start and first_b < $end) 8000 else 0
			if ($end - $start) * 1000 + a + b <= world.height {
				$best = $end
			}
			$end = $end + 1
		}
		if $best == $start {
			return Impossible
		}
		$ends = $ends.append($best)
		$start = $best
	}
	Ends($ends)
}

agrees : World -> Bool
agrees = |world| {
	body = world.rows.len()
	a = first(world.rows, 1)
	b = first(world.rows, 2)
	if a == body and b == body {
		return True
	}
	var $blocks = []
	var $index = 0
	for row in world.rows {
		$blocks = $blocks.append(block($index, 1000, row == 4))
		$index = $index + 1
	}
	var $anchors = []
	if a < body {
		$anchors = $anchors.append({ line: a, block: $blocks.len() })
		$blocks = $blocks.append(block($blocks.len(), 1000, False))
	}
	if b < body {
		$anchors = $anchors.append({ line: b, block: $blocks.len() })
		$blocks = $blocks.append(block($blocks.len(), 2000, False))
	}
	anchors = $anchors.sort_with(|left, right| if (left.line < right.line) Before else if (left.line > right.line) After else Same)
	lines = List.repeat(
		{
			advance: 1,
			clusters: Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }),
			source: {
				utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }),
				scalars: Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }),
			},
		},
		$blocks.len(),
	)
	limits = KernelPageLayout.Limits.make({ max_blocks: 8, max_fragments: 8, max_lines: 8, max_pages: 8, max_placements: 8 })
	constraints = {
		page: { width: 72, height: Layout.Unit.millipoints((world.height + 2000).to_i64_wrap()) },
		margins: { top: 1, right: 1, bottom: 1, left: 1 },
	}
	actual = KernelPageLayout.Plan.build_with_footnotes($blocks, [], lines, constraints, { anchors, body_blocks: body }, limits)
	match (oracle(world, a, b), actual) {
		(Impossible, Err(NoteTooTall(_))) => True
		(Ends(ends), Ok(result)) => {
			if KernelPageLayout.Plan.pages(result).len() != ends.len() {
				return False
			}
			for fragment in KernelPageLayout.Plan.fragments(result) {
				source = fragment.lines.start()
				anchor = if source < body {
					source
				} else if source == body and a < body {
					a
				} else {
					b
				}
				page = fragment.page.index()
				past = ends.get(page) ?? 0
				start = if (page == 0) 0 else ends.get(page - 1) ?? 0
				if anchor < start or anchor >= past {
					return False
				}
			}
			True
		}
		_ => False
	}
}

block : U64, U64, Bool -> KernelPageLayout.Block
block = |index, leading, break_before| {
	baseline_offset: 1,
	decoration: 0,
	lead: 0,
	leading: Layout.Unit.millipoints(leading.to_i64_wrap()),
	lines: Semantics.IndexRange.from_start_and_length({ start: index, length: 1 }),
	owner: Content(Semantics.OccurrenceId.from_index(index)),
	policy: { break_before, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: 1, minimum_last_lines: 1 },
	space_after: 0,
	trailing: 0,
}

expect {
	report = Model.explore(machine, { depth: 5, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash Model.explain(report)
	}
	report.states == 624 and report.steps == 623 and report.depth == 4 and report.reached.len() == 5
}

expect Solve.prove_within(
	{ body: Solve.u64_in(0, 14400000), note: Solve.u64_in(0, 14400000), height: Solve.u64_in(0, 14400000) }.Solve,
	|{ body, note, height }| {
		end = KernelSpan.Arithmetic.wrapped_end(body, note)
		fits = KernelSpan.Arithmetic.fits(body, end, height, |left, right| left.lte(right), |a, b| Solve.all([a, b]))
		fits.implies(Solve.all([body.lte(height), note.lte(height - body)]))
	},
	5000,
) == Ok(Proved)
