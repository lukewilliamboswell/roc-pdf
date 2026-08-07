import KernelLineLayout
import Layout
import Semantics

KernelPageLayout :: [].{
	Dimension : [Blocks, Fragments, Lines, Pages, Placements]
	Error : [
		ArithmeticOverflow,
		InvalidBlock({ block : U64 }),
		InvalidConstraints,
		InvalidLine({ line : U64 }),
		InvalidPolicy({ block : U64 }),
		KeepImpossible({ block : U64, required : U64, available : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
	]

	Margins : { bottom : Layout.Unit, left : Layout.Unit, right : Layout.Unit, top : Layout.Unit }
	Constraints : { margins : Margins, page : Layout.Size }
	Policy : {
		break_before : Bool,
		keep_together : Bool,
		keep_with_next : Bool,
		minimum_first_lines : U64,
		minimum_last_lines : U64,
	}
	Block : {
		baseline_offset : Layout.Unit,
		leading : Layout.Unit,
		lines : Semantics.Range,
		occurrence : Semantics.OccurrenceId,
		policy : Policy,
		space_after : Layout.Unit,
	}
	Limits :: { max_blocks : U64, max_fragments : U64, max_lines : U64, max_pages : U64, max_placements : U64 }.{
		make : { max_blocks : U64, max_fragments : U64, max_lines : U64, max_pages : U64, max_placements : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Fragment : {
		layout : Layout.Fragment,
		lines : Semantics.Range,
		page : Semantics.PageId,
	}
	PlacedLine : {
		baseline : Layout.Point,
		fragment : Semantics.FragmentId,
		line : U64,
	}
	Page : {
		fragments : Semantics.Range,
		id : Semantics.PageId,
		placements : Semantics.Range,
	}
	Work : {
		block_visits : U64,
		fragment_writes : U64,
		keep_policy_visits : U64,
		line_visits : U64,
		page_writes : U64,
		placement_writes : U64,
	}
	Plan :: { fragments : List(Fragment), pages : List(Page), placements : List(PlacedLine), work : Work }.{
		build : List(Block), List(KernelLineLayout.Line), Constraints, Limits -> Try(Plan, Error)
		build = |blocks, lines, constraints, limits| build_plan(blocks, lines, constraints, limits)

		fragments : Plan -> List(Fragment)
		fragments = |plan| plan.fragments

		pages : Plan -> List(Page)
		pages = |plan| plan.pages

		placements : Plan -> List(PlacedLine)
		placements = |plan| plan.placements

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Geometry := {
	content_height : U64,
	content_width : U64,
	margin_left : U64,
	margin_top : U64,
	page_height : U64,
}

Validation := { keep_requirements : List(U64), line_visits : U64 }

build_plan : List(KernelPageLayout.Block), List(KernelLineLayout.Line), KernelPageLayout.Constraints, KernelPageLayout.Limits -> Try(KernelPageLayout.Plan, KernelPageLayout.Error)
build_plan = |blocks, lines, constraints, limits| {
	if blocks.len() == 0 or lines.len() == 0 {
		return Err(InvalidConstraints)
	}
	check_limit(blocks.len(), limits.max_blocks, Blocks)?
	check_limit(lines.len(), limits.max_lines, Lines)?
	geometry = validate_geometry(constraints)?
	validation = validate_input(blocks, lines, geometry.content_height)?
	var $pages = []
	var $fragments = []
	var $placements = []
	var $page_fragment_start = 0
	var $page_placement_start = 0
	var $used = 0
	var $block_index = 0
	while $block_index < blocks.len() {
		block = list_at(blocks, $block_index)
		line_end = range_end(block.lines)?
		var $line_cursor = block.lines.start()
		page_has_content = $placements.len() > $page_placement_start
		if block.policy.break_before and page_has_content {
			$pages = append_page($pages, $page_fragment_start, $fragments.len(), $page_placement_start, $placements.len(), limits.max_pages)?
			$page_fragment_start = $fragments.len()
			$page_placement_start = $placements.len()
			$used = 0
		}
		keep_required = list_at(validation.keep_requirements, $block_index)
		if keep_required > geometry.content_height {
			return Err(KeepImpossible({ available: geometry.content_height, block: $block_index, required: keep_required }))
		}
		remaining_page = geometry.content_height - $used
		if keep_required > remaining_page and $placements.len() > $page_placement_start {
			$pages = append_page($pages, $page_fragment_start, $fragments.len(), $page_placement_start, $placements.len(), limits.max_pages)?
			$page_fragment_start = $fragments.len()
			$page_placement_start = $placements.len()
			$used = 0
		}
		while $line_cursor < line_end {
			leading = positive_raw(block.leading)?
			remaining_lines = line_end - $line_cursor
			available_lines = (geometry.content_height - $used) / leading
			must_restart = available_lines == 0 or (remaining_lines > available_lines and available_lines < block.policy.minimum_first_lines)
			if must_restart {
				if $placements.len() == $page_placement_start {
					return Err(InvalidPolicy({ block: $block_index }))
				}
				$pages = append_page($pages, $page_fragment_start, $fragments.len(), $page_placement_start, $placements.len(), limits.max_pages)?
				$page_fragment_start = $fragments.len()
				$page_placement_start = $placements.len()
				$used = 0
			} else {
				take = select_fragment_lines(block, $block_index, remaining_lines, available_lines)?
				fragment_height = checked_mul(take, leading)?
				fragment_id = Semantics.FragmentId.from_index($fragments.len())
				fragment = make_fragment(block, lines, $line_cursor, take, fragment_height, $used, geometry, $pages.len())?
				check_limit(checked_add($fragments.len(), 1)?, limits.max_fragments, Fragments)?
				$fragments = $fragments.append(fragment)
				var $local = 0
				while $local < take {
					check_limit(checked_add($placements.len(), 1)?, limits.max_placements, Placements)?
					baseline_descent = checked_add($used, checked_add(positive_raw(block.baseline_offset)?, checked_mul($local, leading)?)?)?
					baseline_y = geometry.page_height - geometry.margin_top - baseline_descent
					$placements = $placements.append({
						baseline: { x: Layout.Unit.from_raw(geometry.margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(baseline_y.to_i64_wrap()) },
						fragment: fragment_id,
						line: $line_cursor + $local,
					})
					$local = $local + 1
				}
				$used = checked_add($used, fragment_height)?
				$line_cursor = $line_cursor + take
				if $line_cursor < line_end {
					$pages = append_page($pages, $page_fragment_start, $fragments.len(), $page_placement_start, $placements.len(), limits.max_pages)?
					$page_fragment_start = $fragments.len()
					$page_placement_start = $placements.len()
					$used = 0
				}
			}
		}
		space = nonnegative_raw(block.space_after)?
		spaced = checked_add($used, space)?
		$used = if spaced > geometry.content_height geometry.content_height else spaced
		$block_index = $block_index + 1
	}
	if $placements.len() > $page_placement_start {
		$pages = append_page($pages, $page_fragment_start, $fragments.len(), $page_placement_start, $placements.len(), limits.max_pages)?
	}
	Ok(
		KernelPageLayout.Plan.{
			fragments: $fragments,
			pages: $pages,
			placements: $placements,
			work: {
				block_visits: blocks.len(),
				fragment_writes: $fragments.len(),
				keep_policy_visits: blocks.len(),
				line_visits: validation.line_visits,
				page_writes: $pages.len(),
				placement_writes: $placements.len(),
			},
		},
	)
}

validate_geometry : KernelPageLayout.Constraints -> Try(Geometry, KernelPageLayout.Error)
validate_geometry = |constraints| {
	page_width = positive_raw(constraints.page.width)?
	page_height = positive_raw(constraints.page.height)?
	left = nonnegative_raw(constraints.margins.left)?
	right = nonnegative_raw(constraints.margins.right)?
	top = nonnegative_raw(constraints.margins.top)?
	bottom = nonnegative_raw(constraints.margins.bottom)?
	horizontal = checked_add(left, right)?
	vertical = checked_add(top, bottom)?
	if horizontal >= page_width or vertical >= page_height {
		Err(InvalidConstraints)
	} else {
		Ok({
			content_height: page_height - vertical,
			content_width: page_width - horizontal,
			margin_left: left,
			margin_top: top,
			page_height,
		})
	}
}

validate_input : List(KernelPageLayout.Block), List(KernelLineLayout.Line), U64 -> Try(Validation, KernelPageLayout.Error)
validate_input = |blocks, lines, content_height| {
	var $heights = List.with_capacity(blocks.len())
	var $line_cursor = 0
	var $line_visits = 0
	var $block_index = 0
	while $block_index < blocks.len() {
		block = list_at(blocks, $block_index)
		line_count = block.lines.length()
		if block.lines.start() != $line_cursor or line_count == 0 or block.policy.minimum_first_lines == 0 or block.policy.minimum_last_lines == 0 or block.policy.minimum_first_lines > line_count or block.policy.minimum_last_lines > line_count {
			return Err(InvalidBlock({ block: $block_index }))
		}
		if block.policy.keep_with_next and !block.policy.keep_together {
			return Err(InvalidPolicy({ block: $block_index }))
		}
		leading = positive_raw(block.leading) ? |_| InvalidBlock({ block: $block_index })
		baseline = positive_raw(block.baseline_offset) ? |_| InvalidBlock({ block: $block_index })
		if baseline > leading {
			return Err(InvalidBlock({ block: $block_index }))
		}
		_ = nonnegative_raw(block.space_after) ? |_| InvalidBlock({ block: $block_index })
		height = checked_mul(line_count, leading)?
		if block.policy.keep_together and height > content_height {
			return Err(KeepImpossible({ available: content_height, block: $block_index, required: height }))
		}
		var $local = 0
		var $scalar_cursor = 0
		var $byte_cursor = 0
		while $local < line_count {
			line_index = $line_cursor + $local
			if line_index >= lines.len() {
				return Err(InvalidBlock({ block: $block_index }))
			}
			line = list_at(lines, line_index)
			if $local > 0 and (line.source.scalars.start() != $scalar_cursor or line.source.utf8_bytes.start() != $byte_cursor) {
				return Err(InvalidLine({ line: line_index }))
			}
			$scalar_cursor = range_end(line.source.scalars)?
			$byte_cursor = range_end(line.source.utf8_bytes)?
			$line_visits = checked_add($line_visits, 1)?
			$local = $local + 1
		}
		$line_cursor = checked_add($line_cursor, line_count)?
		$heights = $heights.append(height)
		$block_index = $block_index + 1
	}
	if $line_cursor != lines.len() {
		return Err(InvalidBlock({ block: blocks.len() }))
	}
	var $requirements = List.repeat(0, blocks.len())
	var $reverse = blocks.len()
	while $reverse > 0 {
		$reverse = $reverse - 1
		block = list_at(blocks, $reverse)
		required = if block.policy.keep_with_next {
			if $reverse + 1 >= blocks.len() {
				return Err(InvalidPolicy({ block: $reverse }))
			}
			next = list_at(blocks, $reverse + 1)
			if next.policy.break_before {
				return Err(InvalidPolicy({ block: $reverse }))
			}
			next_required = if next.policy.keep_with_next {
				list_at($requirements, $reverse + 1)
			} else {
				checked_mul(next.policy.minimum_first_lines, positive_raw(next.leading)?)?
			}
			checked_add(list_at($heights, $reverse), checked_add(nonnegative_raw(block.space_after)?, next_required)?)?
		} else if block.policy.keep_together {
			list_at($heights, $reverse)
		} else {
			0
		}
		$requirements = list_set($requirements, $reverse, required)
	}
	Ok({ keep_requirements: $requirements, line_visits: $line_visits })
}

select_fragment_lines : KernelPageLayout.Block, U64, U64, U64 -> Try(U64, KernelPageLayout.Error)
select_fragment_lines = |block, block_index, remaining, available| {
	if remaining <= available {
		return Ok(remaining)
	}
	if block.policy.keep_together {
		return Err(InvalidPolicy({ block: block_index }))
	}
	if available < block.policy.minimum_first_lines {
		return Err(InvalidPolicy({ block: block_index }))
	}
	max_before_last = remaining - block.policy.minimum_last_lines
	take = if available < max_before_last available else max_before_last
	if take < block.policy.minimum_first_lines {
		Err(InvalidPolicy({ block: block_index }))
	} else {
		Ok(take)
	}
}

make_fragment : KernelPageLayout.Block, List(KernelLineLayout.Line), U64, U64, U64, U64, Geometry, U64 -> Try(KernelPageLayout.Fragment, KernelPageLayout.Error)
make_fragment = |block, lines, start, length, height, used, geometry, page_index| {
	first = list_at(lines, start)
	last = list_at(lines, start + length - 1)
	scalar_end = range_end(last.source.scalars)?
	byte_end = range_end(last.source.utf8_bytes)?
	origin_y = geometry.page_height - geometry.margin_top - used - height
	Ok({
		layout: {
			geometry: {
				origin: { x: Layout.Unit.from_raw(geometry.margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(origin_y.to_i64_wrap()) },
				size: { height: Layout.Unit.from_raw(height.to_i64_wrap()), width: Layout.Unit.from_raw(geometry.content_width.to_i64_wrap()) },
			},
			occurrence: block.occurrence,
			source_range: UnicodeRange({
				scalars: Semantics.Range.from_start_and_length(first.source.scalars.start(), scalar_end - first.source.scalars.start()),
				utf8_bytes: Semantics.Range.from_start_and_length(first.source.utf8_bytes.start(), byte_end - first.source.utf8_bytes.start()),
			}),
		},
		lines: Semantics.Range.from_start_and_length(start, length),
		page: Semantics.PageId.from_index(page_index),
	})
}

append_page : List(KernelPageLayout.Page), U64, U64, U64, U64, U64 -> Try(List(KernelPageLayout.Page), KernelPageLayout.Error)
append_page = |pages, fragment_start, fragment_end, placement_start, placement_end, limit| {
	if placement_end <= placement_start or fragment_end <= fragment_start {
		return Err(InvalidConstraints)
	}
	check_limit(checked_add(pages.len(), 1)?, limit, Pages)?
	Ok(
		pages.append({
			fragments: Semantics.Range.from_start_and_length(fragment_start, fragment_end - fragment_start),
			id: Semantics.PageId.from_index(pages.len()),
			placements: Semantics.Range.from_start_and_length(placement_start, placement_end - placement_start),
		}),
	)
}

positive_raw : Layout.Unit -> Try(U64, KernelPageLayout.Error)
positive_raw = |value| {
	raw = value.raw()
	if raw <= 0 {
		Err(InvalidConstraints)
	} else {
		Ok(raw.to_u64_wrap())
	}
}

nonnegative_raw : Layout.Unit -> Try(U64, KernelPageLayout.Error)
nonnegative_raw = |value| {
	raw = value.raw()
	if raw < 0 {
		Err(InvalidConstraints)
	} else {
		Ok(raw.to_u64_wrap())
	}
}

range_end : Semantics.Range -> Try(U64, KernelPageLayout.Error)
range_end = |range| checked_add(range.start(), range.length())

checked_add : U64, U64 -> Try(U64, KernelPageLayout.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_mul : U64, U64 -> Try(U64, KernelPageLayout.Error)
checked_mul = |left, right| {
	if left == 0 or right == 0 {
		return Ok(0)
	}
	product = left * right
	if product / right != left {
		Err(ArithmeticOverflow)
	} else {
		Ok(product)
	}
}

check_limit : U64, U64, KernelPageLayout.Dimension -> Try({}, KernelPageLayout.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated page layout index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated page layout rewrite escaped"
	}
	Ok(updated) => updated
}

test_lines : List(KernelLineLayout.Line)
test_lines = List.map(
	[0, 1, 2, 3, 4, 5, 6, 7],
	|index| {
		advance: Layout.Unit.from_raw(1000),
		clusters: Semantics.Range.from_start_and_length(index, 1),
		source: {
			scalars: Semantics.Range.from_start_and_length(index, 1),
			utf8_bytes: Semantics.Range.from_start_and_length(index, 1),
		},
	},
)

test_policy : KernelPageLayout.Policy
test_policy = { break_before: False, keep_together: False, keep_with_next: False, minimum_first_lines: 2, minimum_last_lines: 2 }

test_constraints : KernelPageLayout.Constraints
test_constraints = {
	margins: { bottom: Layout.Unit.from_raw(1000), left: Layout.Unit.from_raw(1000), right: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(1000) },
	page: { height: Layout.Unit.from_raw(5000), width: Layout.Unit.from_raw(10000) },
}

test_limits : KernelPageLayout.Limits
test_limits = KernelPageLayout.Limits.make({ max_blocks: 8, max_fragments: 8, max_lines: 8, max_pages: 8, max_placements: 8 })

## Five lines split three/two without violating widow/orphan minima.
expect {
	block = {
		baseline_offset: Layout.Unit.from_raw(800),
		leading: Layout.Unit.from_raw(1000),
		lines: Semantics.Range.from_start_and_length(0, 5),
		occurrence: Semantics.OccurrenceId.from_index(0),
		policy: test_policy,
		space_after: Layout.Unit.from_raw(0),
	}
	plan = KernelPageLayout.Plan.build([block], test_lines.take_first(5), test_constraints, test_limits)?
	fragments = KernelPageLayout.Plan.fragments(plan)
	pages = KernelPageLayout.Plan.pages(plan)
	placements = KernelPageLayout.Plan.placements(plan)
	fragments.len() == 2 and pages.len() == 2 and placements.len() == 5 and list_at(fragments, 0).lines.length() == 3 and list_at(fragments, 1).lines.length() == 2 and list_at(placements, 0).baseline.y.raw() == 3200
}

## A kept heading chain moves as one unit so the following paragraph retains
## its minimum first fragment.
expect {
	leading = Layout.Unit.from_raw(1000)
	base = {
		baseline_offset: Layout.Unit.from_raw(800),
		leading,
		lines: Semantics.Range.from_start_and_length(0, 1),
		occurrence: Semantics.OccurrenceId.from_index(0),
		policy: test_policy,
		space_after: Layout.Unit.from_raw(0),
	}
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2), policy: { ..test_policy, keep_together: True } },
		{ ..base, lines: Semantics.Range.from_start_and_length(2, 1), policy: { ..test_policy, keep_together: True, keep_with_next: True, minimum_first_lines: 1, minimum_last_lines: 1 } },
		{ ..base, lines: Semantics.Range.from_start_and_length(3, 5), policy: test_policy },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines, test_constraints, test_limits)?
	pages = KernelPageLayout.Plan.pages(plan)
	fragments = KernelPageLayout.Plan.fragments(plan)
	pages.len() == 3 and list_at(fragments, 1).page.index() == 1 and list_at(fragments, 2).page.index() == 1
}

## Break-before starts the next block on a new page even when space remains.
expect {
	base = {
		baseline_offset: Layout.Unit.from_raw(800),
		leading: Layout.Unit.from_raw(1000),
		lines: Semantics.Range.from_start_and_length(0, 1),
		occurrence: Semantics.OccurrenceId.from_index(0),
		policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 },
		space_after: Layout.Unit.from_raw(0),
	}
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 1) },
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 1), policy: { ..base.policy, break_before: True } },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(2), test_constraints, test_limits)?
	KernelPageLayout.Plan.pages(plan).len() == 2
}

## A keep-together block larger than the content box fails instead of
## overflowing the page or silently dropping the policy.
expect {
	block = {
		baseline_offset: Layout.Unit.from_raw(800),
		leading: Layout.Unit.from_raw(1000),
		lines: Semantics.Range.from_start_and_length(0, 5),
		occurrence: Semantics.OccurrenceId.from_index(0),
		policy: { ..test_policy, keep_together: True },
		space_after: Layout.Unit.from_raw(0),
	}
	match KernelPageLayout.Plan.build([block], test_lines.take_first(5), test_constraints, test_limits) {
		Err(KeepImpossible({ available: 3000, block: 0, required: 5000 })) => True
		_ => False
	}
}

## Keep-with-next and an explicit break on the next block are contradictory.
expect {
	base = {
		baseline_offset: Layout.Unit.from_raw(800),
		leading: Layout.Unit.from_raw(1000),
		lines: Semantics.Range.from_start_and_length(0, 1),
		occurrence: Semantics.OccurrenceId.from_index(0),
		policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 },
		space_after: Layout.Unit.from_raw(0),
	}
	blocks = [
		{ ..base, policy: { ..base.policy, keep_together: True, keep_with_next: True } },
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 1), policy: { ..base.policy, break_before: True } },
	]
	match KernelPageLayout.Plan.build(blocks, test_lines.take_first(2), test_constraints, test_limits) {
		Err(InvalidPolicy({ block: 0 })) => True
		_ => False
	}
}
