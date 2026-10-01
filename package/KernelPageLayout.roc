import KernelLineLayout
import Layout
import Semantics

KernelPageLayout :: [].{
	Dimension : [Blocks, Fragments, Groups, Lines, Pages, Placements]

	## The ranked preferences of `reference-documents-v4`, highest first:
	## R1 a heading keeps with its next block's first placement unit, R2 an
	## author's preferred keep-with-next, R3 a table footer group carries a
	## body row (reserved for the table slice), R4 the orphan minimum, and R5
	## the widow minimum. A higher rank is never sacrificed for a lower one.
	Rank : [AuthorKeep, FooterCarry, HeadingKeep, Orphan, Widow]

	## Keep-with-next strength. `Required` is a mandatory constraint that is
	## never relaxed; `Preferred` is a ranked preference.
	Keep : [NoKeep, Preferred(Rank), Required]

	## Conflicting mandatory constraints, each naming its participating
	## sources by dense block and keep-group index.
	Conflict : [
		BreakAfterRequiredKeep({ block : U64, next : U64 }),
		BreakInsideGroup({ block : U64, group : U64 }),
		ChainTooTall({ available : U64, block : U64, next : U64, required : U64 }),
		GroupTooTall({ available : U64, group : U64, required : U64 }),
		RequiredKeepAtEnd({ block : U64 }),
	]
	Error : [
		ArithmeticOverflow,
		InvalidBlock({ block : U64 }),
		InvalidConstraints,
		InvalidGroup({ group : U64 }),
		InvalidLine({ line : U64 }),
		KeepConflict(Conflict),

		## The lead region's blocks need `required` height but the region
		## reserves `available`.
		LeadOverflow({ available : U64, required : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		Oversize({ available : U64, block : U64, required : U64 }),
	]

	Margins : { bottom : Layout.Unit, left : Layout.Unit, right : Layout.Unit, top : Layout.Unit }
	Constraints : { margins : Margins, page : Layout.Size }

	## A page template's flow region on one kind of page: `top` is its offset
	## below the top of the body frame (the page less its margins) and
	## `height` its height. Template regions are fixed before flow, so these
	## frames never depend on painted furniture.
	Frame : { height : Layout.Unit, top : Layout.Unit }

	## Page-template geometry: the first page's and every later page's flow
	## region, and optionally the first page's lead region, which receives
	## the first `blocks` blocks as one unit before the body flow begins.
	Template : { continuation : Frame, first : Frame, lead : [Lead({ blocks : U64, frame : Frame }), NoLead] }

	## Typed per-block policy. `break_before` is a mandatory explicit page
	## break and `keep_together` a mandatory unsplittable block;
	## `keep_with_next` binds the block's end to the next block's first
	## placement unit (the whole next block when it is unsplittable, else
	## its first `minimum_first_lines` lines). The line minimums are the R4
	## and R5 preferences.
	Policy : {
		break_before : Bool,
		keep_together : Bool,
		keep_with_next : Keep,
		minimum_first_lines : U64,
		minimum_last_lines : U64,
	}

	## `lead` is height reserved at the top of every page on which this
	## block starts or continues: a continued table repaints its header rows
	## there. It is zero for every other block, and every fit check of a unit
	## starting a page subtracts its first block's lead from the page body.
	## `decoration` is the height of in-flow decorations placed immediately
	## above the block's first line: it is part of the block's first
	## placement unit, so it is always on the page where the block starts.
	## `trailing` is height reserved below the block's last line and before
	## its spacing (a custom block's bottom inset and unused measured
	## height). Only an unsplittable block may reserve it, so it is always
	## on the page where the block ends and counts toward every fit check.
	Block : {
		baseline_offset : Layout.Unit,
		decoration : Layout.Unit,
		lead : Layout.Unit,
		leading : Layout.Unit,
		lines : Semantics.Range,
		occurrence : Semantics.OccurrenceId,
		policy : Policy,
		space_after : Layout.Unit,
		trailing : Layout.Unit,
	}

	## A required keep-together group over a contiguous block range. Groups
	## are listed in preorder: a group either nests inside an earlier one or
	## starts after it ends.
	KeepGroup : { blocks : Semantics.Range }

	## One preference the chosen break left unsatisfied: its rank, the block
	## whose policy declared it, and the page the break closed.
	Relaxation : { block : U64, page : U64, rank : Rank }

	## Where a block's decoration band was placed: its page and the absolute
	## y coordinate of the band's top edge, which the block's first line
	## follows after the band's height.
	Band : { block : U64, page : U64, top : U64 }
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

	## `candidate_visits` counts every break position scored by the page
	## scans, including positions rescanned after an earlier break was
	## chosen; it is bounded by the placed lines plus one page of look-back
	## per page, so it grows linearly with the document.
	Work : {
		block_visits : U64,
		candidate_visits : U64,
		fragment_writes : U64,
		keep_policy_visits : U64,
		line_visits : U64,
		page_writes : U64,
		placement_writes : U64,
	}
	Plan :: { bands : List(Band), fragments : List(Fragment), pages : List(Page), placements : List(PlacedLine), relaxations : List(Relaxation), work : Work }.{
		build : List(Block), List(KernelLineLayout.Line), Constraints, Limits -> Try(Plan, Error)
		build = |blocks, lines, constraints, limits| build_plan(blocks, [], lines, constraints, NoTemplate, limits)

		## Pagination with required keep-together groups.
		build_with_groups : List(Block), List(KeepGroup), List(KernelLineLayout.Line), Constraints, Limits -> Try(Plan, Error)
		build_with_groups = |blocks, groups, lines, constraints, limits| build_plan(blocks, groups, lines, constraints, NoTemplate, limits)

		## Pagination under page templates: the first page flows in the
		## first frame and every later page in the continuation frame, after
		## the lead region (when present) receives its blocks on the first
		## page. Every fit check uses its page's own flow height.
		build_with_template : List(Block), List(KeepGroup), List(KernelLineLayout.Line), Constraints, Template, Limits -> Try(Plan, Error)
		build_with_template = |blocks, groups, lines, constraints, template, limits| build_plan(blocks, groups, lines, constraints, WithTemplate(template), limits)

		fragments : Plan -> List(Fragment)
		fragments = |plan| plan.fragments

		## The placed decoration band of every block with a decoration, in
		## block order.
		bands : Plan -> List(Band)
		bands = |plan| plan.bands

		pages : Plan -> List(Page)
		pages = |plan| plan.pages

		placements : Plan -> List(PlacedLine)
		placements = |plan| plan.placements

		relaxations : Plan -> List(Relaxation)
		relaxations = |plan| plan.relaxations

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

## `heights[b]` is block b's line height with its decoration band;
## `atomic_ends[b]` is the exclusive end of the outermost keep-together
## group starting at b, or zero (empty when no group exists).
Validation := { atomic_ends : List(U64), heights : List(U64), line_visits : U64 }

## A page scan either reaches the end of the document or chooses a break at
## `line` lines into `block` (line zero is the boundary before the block).
Scan := { candidates : U64, end : [AllFits, Break({ block : U64, line : U64 })] }

## Preference bits of a break's score vector, R1 highest.
heading_bit : U64
heading_bit = 16

author_bit : U64
author_bit = 8

orphan_bit : U64
orphan_bit = 2

widow_bit : U64
widow_bit = 1

all_satisfied : U64
all_satisfied = 31

no_candidate : U64
no_candidate = U64.highest

## Validated per-page flow geometry: every page's scalar frame, and the
## first page's lead region with the number of blocks it receives.
Frames := {
	continuation_height : U64,
	continuation_top : U64,
	first_height : U64,
	first_top : U64,
	lead : [Lead({ blocks : U64, height : U64, top : U64 }), NoLead],
	largest : U64,
}

build_plan : List(KernelPageLayout.Block), List(KernelPageLayout.KeepGroup), List(KernelLineLayout.Line), KernelPageLayout.Constraints, [NoTemplate, WithTemplate(KernelPageLayout.Template)], KernelPageLayout.Limits -> Try(KernelPageLayout.Plan, KernelPageLayout.Error)
build_plan = |blocks, groups, lines, constraints, template, limits| {
	if blocks.len() == 0 or lines.len() == 0 {
		return Err(InvalidConstraints)
	}
	check_limit(blocks.len(), limits.max_blocks, Blocks)?
	check_limit(lines.len(), limits.max_lines, Lines)?
	check_limit(groups.len(), limits.max_blocks, Groups)?
	geometry = validate_geometry(constraints)?
	frames = validate_frames(template, geometry, blocks.len())?
	validation = validate_input(blocks, groups, lines, frames.largest)?
	var $pages = []
	var $fragments = []
	var $placements = []
	var $relaxations = []
	var $bands = []
	var $candidate_visits = 0
	var $block = 0
	var $line = 0

	## The lead region receives its blocks on the first page, stacked from
	## its top with their spacing between them, as one unit.
	match frames.lead {
		NoLead => {}
		Lead({ blocks: lead_blocks, height: lead_height, top: lead_top }) => {
			lead_geometry = { ..geometry, content_height: lead_height, margin_top: checked_add(geometry.margin_top, lead_top)? }
			var $used = 0
			while $block < lead_blocks {
				block = list_at(blocks, $block)
				take = block.lines.length()
				leading = positive_raw(block.leading)?
				fragment_height = checked_mul(take, leading)?
				decoration = nonnegative_raw(block.decoration)?
				if checked_add(checked_add($used, decoration)?, fragment_height)? > lead_height {
					return Err(LeadOverflow({ available: lead_height, required: lead_total(blocks, lead_blocks)? }))
				}
				if decoration > 0 {
					$bands = $bands.append({ block: $block, page: 0, top: lead_geometry.page_height - lead_geometry.margin_top - $used })
					$used = $used + decoration
				}
				fragment_id = Semantics.FragmentId.from_index($fragments.len())
				fragment = make_fragment(block, lines, block.lines.start(), take, fragment_height, $used, lead_geometry, 0)?
				check_limit(checked_add($fragments.len(), 1)?, limits.max_fragments, Fragments)?
				$fragments = $fragments.append(fragment)
				var $local = 0
				while $local < take {
					check_limit(checked_add($placements.len(), 1)?, limits.max_placements, Placements)?
					baseline_descent = checked_add($used, checked_add(positive_raw(block.baseline_offset)?, checked_mul($local, leading)?)?)?
					baseline_y = lead_geometry.page_height - lead_geometry.margin_top - baseline_descent
					$placements = $placements.append({
						baseline: { x: Layout.Unit.from_raw(geometry.margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(baseline_y.to_i64_wrap()) },
						fragment: fragment_id,
						line: block.lines.start() + $local,
					})
					$local = $local + 1
				}
				$used = checked_add(checked_add($used, fragment_height)?, nonnegative_raw(block.trailing)?)?
				if $block + 1 < lead_blocks {
					$used = checked_add($used, nonnegative_raw(block.space_after)?)?
				}
				$block = $block + 1
			}
		}
	}
	var $page_fragment_start = 0
	var $page_placement_start = 0
	while $block < blocks.len() {
		page_index = $pages.len()
		flow_height = if page_index == 0 frames.first_height else frames.continuation_height
		flow_top = if page_index == 0 frames.first_top else frames.continuation_top
		page_geometry = { ..geometry, content_height: flow_height, margin_top: checked_add(geometry.margin_top, flow_top)? }
		scan = scan_page(blocks, validation, flow_height, $block, $line)?
		$candidate_visits = checked_add($candidate_visits, scan.candidates)?
		end = match scan.end {
			AllFits => { block: blocks.len(), line: 0 }
			Break(position) => position
		}
		fragment_start = $page_fragment_start
		placement_start = $page_placement_start

		# Materialize the accepted page once, from the page start to the
		# chosen break, exactly as the scan measured it.
		var $used = nonnegative_raw(list_at(blocks, $block).lead)?
		var $cursor_block = $block
		var $cursor_line = $line
		while $cursor_block < end.block or ($cursor_block == end.block and $cursor_line < end.line) {
			block = list_at(blocks, $cursor_block)
			line_count = block.lines.length()
			stop = if $cursor_block == end.block end.line else line_count
			take = stop - $cursor_line
			leading = positive_raw(block.leading)?
			fragment_height = checked_mul(take, leading)?
			decoration = if $cursor_line == 0 nonnegative_raw(block.decoration)? else 0
			if decoration > 0 {
				$bands = $bands.append({ block: $cursor_block, page: page_index, top: page_geometry.page_height - page_geometry.margin_top - $used })
				$used = checked_add($used, decoration)?
			}
			fragment_id = Semantics.FragmentId.from_index($fragments.len())
			line_start = block.lines.start() + $cursor_line
			fragment = make_fragment(block, lines, line_start, take, fragment_height, $used, page_geometry, page_index)?
			check_limit(checked_add($fragments.len(), 1)?, limits.max_fragments, Fragments)?
			$fragments = $fragments.append(fragment)
			var $local = 0
			while $local < take {
				check_limit(checked_add($placements.len(), 1)?, limits.max_placements, Placements)?
				baseline_descent = checked_add($used, checked_add(positive_raw(block.baseline_offset)?, checked_mul($local, leading)?)?)?
				baseline_y = page_geometry.page_height - page_geometry.margin_top - baseline_descent
				$placements = $placements.append({
					baseline: { x: Layout.Unit.from_raw(geometry.margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(baseline_y.to_i64_wrap()) },
					fragment: fragment_id,
					line: line_start + $local,
				})
				$local = $local + 1
			}
			$used = checked_add($used, fragment_height)?
			if stop == line_count {
				$used = checked_add($used, nonnegative_raw(block.trailing)?)?
				spaced = checked_add($used, nonnegative_raw(block.space_after)?)?
				$used = if spaced > page_geometry.content_height page_geometry.content_height else spaced
				$cursor_block = $cursor_block + 1
				$cursor_line = 0
			} else {
				$cursor_line = stop
			}
		}
		$pages = append_page($pages, fragment_start, $fragments.len(), placement_start, $placements.len(), limits.max_pages)?
		$page_fragment_start = $fragments.len()
		$page_placement_start = $placements.len()
		match scan.end {
			AllFits => {}
			Break(position) => {
				$relaxations = record_relaxations($relaxations, blocks, position, $block, $line, page_index)
			}
		}
		$block = end.block
		$line = end.line
	}
	Ok(
		KernelPageLayout.Plan.{
			bands: $bands,
			fragments: $fragments,
			pages: $pages,
			placements: $placements,
			relaxations: $relaxations,
			work: {
				block_visits: blocks.len(),
				candidate_visits: $candidate_visits,
				fragment_writes: $fragments.len(),
				keep_policy_visits: blocks.len(),
				line_visits: validation.line_visits,
				page_writes: $pages.len(),
				placement_writes: $placements.len(),
			},
		},
	)
}

## Scan one fresh page from `start_block`/`start_line`: collect every legal
## break position up to the last one whose content still fits, score each by
## its (R1, ..., R5) vector, and keep the lexicographically greatest, the
## latest on ties. Required keeps make a position illegal; keep-together
## groups and unsplittable blocks are atomic units. A reachable explicit
## break ends the page there. The scan keeps scalar state only.
scan_page : List(KernelPageLayout.Block), Validation, U64, U64, U64 -> Try(Scan, KernelPageLayout.Error)
scan_page = |blocks, validation, height, start_block, start_line| {
	var $used = nonnegative_raw(list_at(blocks, start_block).lead)?
	var $best_block = 0
	var $best_line = 0
	var $best_score = no_candidate
	var $visits = 0
	var $blocked = no_candidate
	var $index = start_block
	var $first_line = start_line
	while $index < blocks.len() {
		block = list_at(blocks, $index)
		if $index > start_block {
			$visits = $visits + 1
			if block.policy.break_before {
				return Ok({ candidates: $visits, end: Break({ block: $index, line: 0 }) })
			}
			match list_at(blocks, $index - 1).policy.keep_with_next {
				Required => {
					$blocked = $index - 1
				}
				keep => {
					score = all_satisfied - keep_bit(keep)
					if $best_score == no_candidate or score >= $best_score {
						$best_score = score
						$best_block = $index
						$best_line = 0
					}
				}
			}
		}
		atomic_end = if validation.atomic_ends.is_empty() or $first_line != 0 0 else list_at(validation.atomic_ends, $index)
		if atomic_end != 0 {
			unit = group_height(blocks, validation.heights, $index, atomic_end)?
			if checked_add($used, unit)? > height {
				return finish_scan($best_score, $best_block, $best_line, $visits, { blocked: $blocked, height, start: start_block, stop: $index, unit, used: $used }, blocks)
			}
			spaced = checked_add(checked_add($used, unit)?, nonnegative_raw(list_at(blocks, atomic_end - 1).space_after)?)?
			$used = if spaced > height height else spaced
			$index = atomic_end
			$first_line = 0
		} else if block.policy.keep_together and $first_line == 0 {
			unit = list_at(validation.heights, $index)
			if checked_add($used, unit)? > height {
				return finish_scan($best_score, $best_block, $best_line, $visits, { blocked: $blocked, height, start: start_block, stop: $index, unit, used: $used }, blocks)
			}
			spaced = checked_add(checked_add($used, unit)?, nonnegative_raw(block.space_after)?)?
			$used = if spaced > height height else spaced
			$index = $index + 1
		} else {
			leading = positive_raw(block.leading)?
			line_count = block.lines.length()
			remaining = line_count - $first_line

			## A block starting here places its decoration band first.
			decoration = if $first_line == 0 nonnegative_raw(block.decoration)? else 0
			$used = checked_add($used, decoration)?
			fit = if $used >= height 0 else (height - $used) / leading
			take_max = if fit < remaining fit else remaining
			starts_here = $first_line == 0
			previous_keep = if starts_here and $index > start_block list_at(blocks, $index - 1).policy.keep_with_next else NoKeep
			var $taken = $first_line + 1
			while $taken <= $first_line + take_max and $taken < line_count {
				$visits = $visits + 1
				var $score = all_satisfied
				var $legal = True
				if starts_here and $taken < block.policy.minimum_first_lines {
					$score = $score - orphan_bit
					match previous_keep {
						Required => {
							$legal = False
							$blocked = $index - 1
						}
						keep => {
							$score = $score - keep_bit(keep)
						}
					}
				}
				if line_count - $taken < block.policy.minimum_last_lines {
					$score = $score - widow_bit
				}
				if $legal and ($best_score == no_candidate or $score >= $best_score) {
					$best_score = $score
					$best_block = $index
					$best_line = $taken
				}
				$taken = $taken + 1
			}
			if remaining > fit {
				return finish_scan($best_score, $best_block, $best_line, $visits, { blocked: $blocked, height, start: start_block, stop: $index, unit: leading, used: $used }, blocks)
			}
			spaced = checked_add(checked_add($used, checked_mul(remaining, leading)?)?, nonnegative_raw(block.space_after)?)?
			$used = if spaced > height height else spaced
			$index = $index + 1
			$first_line = 0
		}
	}
	Ok({ candidates: $visits, end: AllFits })
}

## The scan stopped at a unit that does not fit. The best legal candidate
## ends the page; with none, the page start cannot be placed at all, and the
## result is the error for that unit, never an empty page.
finish_scan : U64, U64, U64, U64, { blocked : U64, height : U64, start : U64, stop : U64, unit : U64, used : U64 }, List(KernelPageLayout.Block) -> Try(Scan, KernelPageLayout.Error)
finish_scan = |best_score, best_block, best_line, visits, stop, blocks| {
	if best_score != no_candidate {
		return Ok({ candidates: visits, end: Break({ block: best_block, line: best_line }) })
	}
	required = checked_add(stop.used, stop.unit)?
	if stop.blocked != no_candidate {
		Err(KeepConflict(ChainTooTall({ available: stop.height, block: stop.blocked, next: stop.blocked + 1, required })))
	} else if stop.stop < blocks.len() {
		Err(Oversize({ available: stop.height, block: stop.stop, required }))
	} else {
		Err(InvalidBlock({ block: stop.start }))
	}
}

keep_bit : KernelPageLayout.Keep -> U64
keep_bit = |keep| match keep {
	NoKeep | Required => 0
	Preferred(rank) => rank_bit(rank)
}

rank_bit : KernelPageLayout.Rank -> U64
rank_bit = |rank| match rank {
	HeadingKeep => heading_bit
	AuthorKeep => author_bit
	FooterCarry => 4
	Orphan => orphan_bit
	Widow => widow_bit
}

## Record each preference the chosen break leaves unsatisfied, with the
## block whose policy declared it. The list stays empty (and unallocated)
## for a document whose every break satisfies every preference.
record_relaxations : List(KernelPageLayout.Relaxation), List(KernelPageLayout.Block), { block : U64, line : U64 }, U64, U64, U64 -> List(KernelPageLayout.Relaxation)
record_relaxations = |relaxations, blocks, position, start_block, start_line, page| {
	block = list_at(blocks, position.block)
	if position.line == 0 {
		if position.block == 0 {
			return relaxations
		}
		return match list_at(blocks, position.block - 1).policy.keep_with_next {
			Preferred(rank) => relaxations.append({ block: position.block - 1, page, rank })
			_ => relaxations
		}
	}
	starts_here = position.block > start_block or start_line == 0
	var $relaxations = relaxations
	if starts_here and position.line < block.policy.minimum_first_lines {
		if position.block > start_block {
			match list_at(blocks, position.block - 1).policy.keep_with_next {
				Preferred(rank) => {
					$relaxations = $relaxations.append({ block: position.block - 1, page, rank })
				}
				_ => {}
			}
		}
		$relaxations = $relaxations.append({ block: position.block, page, rank: Orphan })
	}
	if block.lines.length() - position.line < block.policy.minimum_last_lines {
		$relaxations = $relaxations.append({ block: position.block, page, rank: Widow })
	}
	$relaxations
}

## The height of an atomic keep-together group: its members' lines plus the
## spacing between members (not after the last).
group_height : List(KernelPageLayout.Block), List(U64), U64, U64 -> Try(U64, KernelPageLayout.Error)
group_height = |blocks, heights, start, end| {
	var $total = 0
	var $index = start
	while $index < end {
		$total = checked_add($total, list_at(heights, $index))?
		if $index + 1 < end {
			$total = checked_add($total, nonnegative_raw(list_at(blocks, $index).space_after)?)?
		}
		$index = $index + 1
	}
	Ok($total)
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

## Page-template frames lie inside the body frame, have positive heights,
## and a lead region precedes the first page's flow and receives at least
## one block but not every block. Without a template every page's frame is
## the whole body frame.
validate_frames : [NoTemplate, WithTemplate(KernelPageLayout.Template)], Geometry, U64 -> Try(Frames, KernelPageLayout.Error)
validate_frames = |template, geometry, block_count| match template {
	NoTemplate => Ok({ continuation_height: geometry.content_height, continuation_top: 0, first_height: geometry.content_height, first_top: 0, largest: geometry.content_height, lead: NoLead })
	WithTemplate({ continuation, first, lead }) => {
		first_frame = frame_scalars(first, geometry.content_height)?
		continuation_frame = frame_scalars(continuation, geometry.content_height)?
		lead_frame = match lead {
			NoLead => NoLead
			Lead({ blocks, frame }) => {
				scalars = frame_scalars(frame, geometry.content_height)?
				if blocks == 0 or blocks >= block_count or checked_add(scalars.top, scalars.height)? > first_frame.top {
					return Err(InvalidConstraints)
				}
				Lead({ blocks, height: scalars.height, top: scalars.top })
			}
		}
		Ok({
			continuation_height: continuation_frame.height,
			continuation_top: continuation_frame.top,
			first_height: first_frame.height,
			first_top: first_frame.top,
			largest: U64.max(first_frame.height, continuation_frame.height),
			lead: lead_frame,
		})
	}
}

frame_scalars : KernelPageLayout.Frame, U64 -> Try({ height : U64, top : U64 }, KernelPageLayout.Error)
frame_scalars = |frame, content_height| {
	height = positive_raw(frame.height)?
	top = nonnegative_raw(frame.top)?
	if checked_add(top, height)? > content_height {
		Err(InvalidConstraints)
	} else {
		Ok({ height, top })
	}
}

## The lead region's content height: its blocks' lines and the spacing
## between them.
lead_total : List(KernelPageLayout.Block), U64 -> Try(U64, KernelPageLayout.Error)
lead_total = |blocks, count| {
	var $total = 0
	var $index = 0
	while $index < count {
		block = list_at(blocks, $index)
		$total = checked_add($total, checked_add(checked_add(nonnegative_raw(block.decoration)?, nonnegative_raw(block.trailing)?)?, checked_mul(block.lines.length(), positive_raw(block.leading)?)?)?)?
		if $index + 1 < count {
			$total = checked_add($total, nonnegative_raw(block.space_after)?)?
		}
		$index = $index + 1
	}
	Ok($total)
}

## Static validation before any page is scanned: block and line shape,
## unsplittable blocks that exceed a fresh page, keep-group nesting, explicit
## breaks strictly inside a group, and required keep chains. The backward
## pass computes each required chain's minimum height: the block's tail
## (the whole block when unsplittable, else one line), its spacing, and the
## next block's first placement unit or, when that block keeps too, its own
## chain. A chain taller than a fresh page is a conflict naming the keep and
## the block it binds.
validate_input : List(KernelPageLayout.Block), List(KernelPageLayout.KeepGroup), List(KernelLineLayout.Line), U64 -> Try(Validation, KernelPageLayout.Error)
validate_input = |blocks, groups, lines, content_height| {
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
		leading = positive_raw(block.leading) ? |_| InvalidBlock({ block: $block_index })
		baseline = positive_raw(block.baseline_offset) ? |_| InvalidBlock({ block: $block_index })
		if baseline > leading {
			return Err(InvalidBlock({ block: $block_index }))
		}
		_ = nonnegative_raw(block.space_after) ? |_| InvalidBlock({ block: $block_index })
		decoration = nonnegative_raw(block.decoration) ? |_| InvalidBlock({ block: $block_index })
		trailing = nonnegative_raw(block.trailing) ? |_| InvalidBlock({ block: $block_index })
		if trailing > 0 and !block.policy.keep_together {
			return Err(InvalidBlock({ block: $block_index }))
		}
		height = checked_add(checked_add(checked_mul(line_count, leading)?, decoration)?, trailing)?
		lead = nonnegative_raw(block.lead) ? |_| InvalidBlock({ block: $block_index })
		if block.policy.keep_together and checked_add(height, lead)? > content_height {
			return Err(Oversize({ available: content_height, block: $block_index, required: checked_add(height, lead)? }))
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

			## Lines of one block continue one source, or begin the next
			## explicit-line-break segment at its own source origin.
			continues = line.source.scalars.start() == $scalar_cursor and line.source.utf8_bytes.start() == $byte_cursor
			restarts = line.source.scalars.start() == 0 and line.source.utf8_bytes.start() == 0
			if $local > 0 and !continues and !restarts {
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
	atomic_ends = validate_groups(blocks, groups, $heights, content_height)?
	var $requirements = List.repeat(0, blocks.len())
	var $reverse = blocks.len()
	while $reverse > 0 {
		$reverse = $reverse - 1
		block = list_at(blocks, $reverse)
		match block.policy.keep_with_next {
			Required => {
				if $reverse + 1 >= blocks.len() {
					return Err(KeepConflict(RequiredKeepAtEnd({ block: $reverse })))
				}
				next = list_at(blocks, $reverse + 1)
				if next.policy.break_before {
					return Err(KeepConflict(BreakAfterRequiredKeep({ block: $reverse, next: $reverse + 1 })))
				}
				tail = if block.policy.keep_together or block.lines.length() == 1 list_at($heights, $reverse) else positive_raw(block.leading)?
				next_unit = match next.policy.keep_with_next {
					Required => list_at($requirements, $reverse + 1)
					_ => first_unit(next, list_at($heights, $reverse + 1), atomic_ends, $reverse + 1, blocks, $heights)?
				}
				required = checked_add(nonnegative_raw(block.lead)?, checked_add(tail, checked_add(nonnegative_raw(block.space_after)?, next_unit)?)?)?
				if required > content_height {
					return Err(KeepConflict(ChainTooTall({ available: content_height, block: $reverse, next: $reverse + 1, required })))
				}
				$requirements = list_set($requirements, $reverse, required)
			}
			_ => {}
		}
	}
	Ok({ atomic_ends, heights: $heights, line_visits: $line_visits })
}

## A block's first placement unit: its keep-together group, the whole block
## when unsplittable, or its orphan-minimum lines.
first_unit : KernelPageLayout.Block, U64, List(U64), U64, List(KernelPageLayout.Block), List(U64) -> Try(U64, KernelPageLayout.Error)
first_unit = |block, height, atomic_ends, index, blocks, heights| {
	atomic_end = if atomic_ends.is_empty() 0 else list_at(atomic_ends, index)
	if atomic_end != 0 {
		group_height(blocks, heights, index, atomic_end)
	} else if block.policy.keep_together {
		Ok(height)
	} else {
		checked_add(checked_mul(block.policy.minimum_first_lines, positive_raw(block.leading)?)?, nonnegative_raw(block.decoration)?)
	}
}

## Groups arrive in preorder. Each group either starts at or after the end
## of the current outermost group (a new outermost group) or nests entirely
## inside it. Only outermost groups become atomic units; each is checked
## once against a fresh page and for explicit breaks strictly inside it.
validate_groups : List(KernelPageLayout.Block), List(KernelPageLayout.KeepGroup), List(U64), U64 -> Try(List(U64), KernelPageLayout.Error)
validate_groups = |blocks, groups, heights, content_height| {
	if groups.is_empty() {
		return Ok([])
	}
	var $ends = List.repeat(0, blocks.len())
	var $outer_start = 0
	var $outer_end = 0
	var $group_index = 0
	while $group_index < groups.len() {
		group = list_at(groups, $group_index).blocks
		start = group.start()
		end = range_end(group)?
		if group.length() == 0 or end > blocks.len() or start < $outer_start {
			return Err(InvalidGroup({ group: $group_index }))
		}
		if start < $outer_end {
			if end > $outer_end {
				return Err(InvalidGroup({ group: $group_index }))
			}
		} else {
			var $member = start + 1
			while $member < end {
				if list_at(blocks, $member).policy.break_before {
					return Err(KeepConflict(BreakInsideGroup({ block: $member, group: $group_index })))
				}
				$member = $member + 1
			}
			required = checked_add(nonnegative_raw(list_at(blocks, start).lead)?, group_height(blocks, heights, start, end)?)?
			if required > content_height {
				return Err(KeepConflict(GroupTooTall({ available: content_height, group: $group_index, required })))
			}
			$ends = list_set($ends, start, end)
			$outer_start = start
			$outer_end = end
		}
		$group_index = $group_index + 1
	}
	Ok($ends)
}

make_fragment : KernelPageLayout.Block, List(KernelLineLayout.Line), U64, U64, U64, U64, Geometry, U64 -> Try(KernelPageLayout.Fragment, KernelPageLayout.Error)
make_fragment = |block, lines, start, length, height, used, geometry, page_index| {
	first = list_at(lines, start)
	last = list_at(lines, start + length - 1)
	scalar_end = range_end(last.source.scalars)?
	byte_end = range_end(last.source.utf8_bytes)?
	scalar_start = if scalar_end < first.source.scalars.start() 0 else first.source.scalars.start()
	byte_start = if byte_end < first.source.utf8_bytes.start() 0 else first.source.utf8_bytes.start()
	origin_y = geometry.page_height - geometry.margin_top - used - height
	Ok({
		layout: {
			geometry: {
				origin: { x: Layout.Unit.from_raw(geometry.margin_left.to_i64_wrap()), y: Layout.Unit.from_raw(origin_y.to_i64_wrap()) },
				size: { height: Layout.Unit.from_raw(height.to_i64_wrap()), width: Layout.Unit.from_raw(geometry.content_width.to_i64_wrap()) },
			},
			occurrence: block.occurrence,
			source_range: UnicodeRange({
				scalars: Semantics.Range.from_start_and_length(scalar_start, scalar_end - scalar_start),
				utf8_bytes: Semantics.Range.from_start_and_length(byte_start, byte_end - byte_start),
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
	if left > U64.highest / right {
		Err(ArithmeticOverflow)
	} else {
		Ok(left * right)
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
test_policy = { break_before: False, keep_together: False, keep_with_next: NoKeep, minimum_first_lines: 2, minimum_last_lines: 2 }

test_constraints : KernelPageLayout.Constraints
test_constraints = {
	margins: { bottom: Layout.Unit.from_raw(1000), left: Layout.Unit.from_raw(1000), right: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(1000) },
	page: { height: Layout.Unit.from_raw(5000), width: Layout.Unit.from_raw(10000) },
}

test_limits : KernelPageLayout.Limits
test_limits = KernelPageLayout.Limits.make({ max_blocks: 8, max_fragments: 8, max_lines: 8, max_pages: 8, max_placements: 8 })

test_block : KernelPageLayout.Block
test_block = {
	baseline_offset: Layout.Unit.from_raw(800),
	decoration: Layout.Unit.from_raw(0),
	lead: Layout.Unit.from_raw(0),
	leading: Layout.Unit.from_raw(1000),
	lines: Semantics.Range.from_start_and_length(0, 1),
	occurrence: Semantics.OccurrenceId.from_index(0),
	policy: test_policy,
	space_after: Layout.Unit.from_raw(0),
	trailing: Layout.Unit.from_raw(0),
}

# Five lines split three/two without violating widow/orphan minima.
expect {
	block = { ..test_block, lines: Semantics.Range.from_start_and_length(0, 5) }
	plan = KernelPageLayout.Plan.build([block], test_lines.take_first(5), test_constraints, test_limits)?
	fragments = KernelPageLayout.Plan.fragments(plan)
	pages = KernelPageLayout.Plan.pages(plan)
	placements = KernelPageLayout.Plan.placements(plan)
	fragments.len() == 2 and pages.len() == 2 and placements.len() == 5 and list_at(fragments, 0).lines.length() == 3 and list_at(fragments, 1).lines.length() == 2 and list_at(placements, 0).baseline.y.raw() == 3200 and KernelPageLayout.Plan.relaxations(plan).is_empty()
}

# A preferred heading keep moves the heading to the next page with its
# following paragraph's first two lines; nothing is relaxed.
expect {
	blocks = [
		{ ..test_block, lines: Semantics.Range.from_start_and_length(0, 2), policy: { ..test_policy, keep_together: True } },
		{ ..test_block, lines: Semantics.Range.from_start_and_length(2, 1), policy: { ..test_policy, keep_together: True, keep_with_next: Preferred(HeadingKeep), minimum_first_lines: 1, minimum_last_lines: 1 } },
		{ ..test_block, lines: Semantics.Range.from_start_and_length(3, 5), policy: test_policy },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines, test_constraints, test_limits)?
	pages = KernelPageLayout.Plan.pages(plan)
	fragments = KernelPageLayout.Plan.fragments(plan)
	pages.len() == 3 and list_at(fragments, 1).page.index() == 1 and list_at(fragments, 2).page.index() == 1 and KernelPageLayout.Plan.relaxations(plan).is_empty()
}

# A decoration band is part of its block's first placement unit: a block
# whose band and first line do not fit below the previous block moves to
# the next page with its band, which is recorded at that page's top.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2) },
		{ ..base, decoration: Layout.Unit.from_raw(1500), lines: Semantics.Range.from_start_and_length(2, 1) },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(3), test_constraints, test_limits)?
	placements = KernelPageLayout.Plan.placements(plan)
	KernelPageLayout.Plan.pages(plan).len() == 2 and KernelPageLayout.Plan.bands(plan) == [{ block: 1, page: 1, top: 4000 }] and list_at(placements, 2).baseline.y.raw() == 1700
}

# Trailing height reserved below an unsplittable block's last line (a
# custom block's bottom inset) counts toward its fit: with it the block
# no longer fits below the first block and moves whole, and the next
# block starts below the reservation. Only an unsplittable block may
# reserve it.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2) },
		{ ..base, lines: Semantics.Range.from_start_and_length(2, 1), policy: { ..base.policy, keep_together: True }, trailing: Layout.Unit.from_raw(1000) },
		{ ..base, lines: Semantics.Range.from_start_and_length(3, 1) },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(4), test_constraints, test_limits)?
	placements = KernelPageLayout.Plan.placements(plan)
	splittable = [{ ..base, lines: Semantics.Range.from_start_and_length(0, 1), trailing: Layout.Unit.from_raw(1) }]
	rejected = match KernelPageLayout.Plan.build(splittable, test_lines.take_first(1), test_constraints, test_limits) {
		Err(InvalidBlock({ block: 0 })) => True
		_ => False
	}
	KernelPageLayout.Plan.pages(plan).len() == 2 and list_at(placements, 2).baseline.y.raw() == 3200 and list_at(placements, 3).baseline.y.raw() == 1200 and rejected
}

# A band that does not fit even on a fresh page with its line is an
# oversize unit, never clipped.
expect {
	block = { ..test_block, decoration: Layout.Unit.from_raw(2500), policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	match KernelPageLayout.Plan.build([block], test_lines.take_first(1), test_constraints, test_limits) {
		Err(InvalidBlock(_)) | Err(Oversize(_)) => True
		_ => False
	}
}

# Break-before starts the next block on a new page even when space remains.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 1) },
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 1), policy: { ..base.policy, break_before: True } },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(2), test_constraints, test_limits)?
	KernelPageLayout.Plan.pages(plan).len() == 2
}

# An unsplittable block larger than the content box fails instead of
# overflowing the page or silently dropping the policy.
expect {
	block = { ..test_block, lines: Semantics.Range.from_start_and_length(0, 5), policy: { ..test_policy, keep_together: True } }
	match KernelPageLayout.Plan.build([block], test_lines.take_first(5), test_constraints, test_limits) {
		Err(Oversize({ available: 3000, block: 0, required: 5000 })) => True
		_ => False
	}
}

# A required keep followed by an explicit break is a conflict naming both.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, policy: { ..base.policy, keep_together: True, keep_with_next: Required } },
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 1), policy: { ..base.policy, break_before: True } },
	]
	match KernelPageLayout.Plan.build(blocks, test_lines.take_first(2), test_constraints, test_limits) {
		Err(KeepConflict(BreakAfterRequiredKeep({ block: 0, next: 1 }))) => True
		_ => False
	}
}

# A three-line paragraph with two lines left on the page moves whole: the
# break before it satisfies every preference.
expect {
	blocks = [
		{ ..test_block, lines: Semantics.Range.from_start_and_length(0, 1), policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } },
		{ ..test_block, lines: Semantics.Range.from_start_and_length(1, 3) },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(4), test_constraints, test_limits)?
	fragments = KernelPageLayout.Plan.fragments(plan)
	fragments.len() == 2 and list_at(fragments, 1).page.index() == 1 and list_at(fragments, 1).lines.length() == 3 and KernelPageLayout.Plan.relaxations(plan).is_empty()
}

# When no break satisfies every preference, the lexicographically best one
# is chosen: a three-line paragraph on a two-line page keeps its orphan
# minimum (R4) and relaxes the widow minimum (R5), which is recorded.
expect {
	small = { ..test_constraints, page: { height: Layout.Unit.from_raw(4000), width: Layout.Unit.from_raw(10000) } }
	block = { ..test_block, lines: Semantics.Range.from_start_and_length(0, 3) }
	plan = KernelPageLayout.Plan.build([block], test_lines.take_first(3), small, test_limits)?
	fragments = KernelPageLayout.Plan.fragments(plan)
	relaxations = KernelPageLayout.Plan.relaxations(plan)
	fragments.len() == 2 and list_at(fragments, 0).lines.length() == 2 and relaxations == [{ block: 0, page: 0, rank: Widow }]
}

# A preferred heading keep that cannot hold (the heading and the next
# unsplittable block never share a page) is relaxed and reported rather
# than rejected.
expect {
	blocks = [
		{ ..test_block, policy: { ..test_policy, keep_together: True, keep_with_next: Preferred(HeadingKeep), minimum_first_lines: 1, minimum_last_lines: 1 } },
		{ ..test_block, lines: Semantics.Range.from_start_and_length(1, 3), policy: { ..test_policy, keep_together: True, minimum_first_lines: 1, minimum_last_lines: 1 } },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(4), test_constraints, test_limits)?
	KernelPageLayout.Plan.pages(plan).len() == 2 and KernelPageLayout.Plan.relaxations(plan) == [{ block: 0, page: 0, rank: HeadingKeep }]
}

# A keep-together group moves whole to the next page, and a group taller
# than a fresh page is a conflict naming the group.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2) },
		{ ..base, lines: Semantics.Range.from_start_and_length(2, 1) },
		{ ..base, lines: Semantics.Range.from_start_and_length(3, 1) },
	]
	plan = KernelPageLayout.Plan.build_with_groups(blocks, [{ blocks: Semantics.Range.from_start_and_length(1, 2) }], test_lines.take_first(4), test_constraints, test_limits)?
	fragments = KernelPageLayout.Plan.fragments(plan)
	tall = KernelPageLayout.Plan.build_with_groups(blocks, [{ blocks: Semantics.Range.from_start_and_length(0, 3) }], test_lines.take_first(4), test_constraints, test_limits)
	moved = list_at(fragments, 1).page.index() == 1 and list_at(fragments, 2).page.index() == 1
	moved and match tall {
		Err(KeepConflict(GroupTooTall({ available: 3000, group: 0, required: 4000 }))) => True
		_ => False
	}
}

# An explicit break strictly inside a keep-together group conflicts.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		base,
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 1), policy: { ..base.policy, break_before: True } },
	]
	match KernelPageLayout.Plan.build_with_groups(blocks, [{ blocks: Semantics.Range.from_start_and_length(0, 2) }], test_lines.take_first(2), test_constraints, test_limits) {
		Err(KeepConflict(BreakInsideGroup({ block: 1, group: 0 }))) => True
		_ => False
	}
}

# A required keep chain taller than a fresh page conflicts statically.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2), policy: { ..base.policy, keep_together: True, keep_with_next: Required } },
		{ ..base, lines: Semantics.Range.from_start_and_length(2, 2), policy: { ..base.policy, keep_together: True } },
	]
	match KernelPageLayout.Plan.build(blocks, test_lines.take_first(4), test_constraints, test_limits) {
		Err(KeepConflict(ChainTooTall({ available: 3000, block: 0, next: 1, required: 4000 }))) => True
		_ => False
	}
}

# A block's lead is reserved at the top of every page it starts or
# continues on: the kept second block moves to page two below its lead,
# and a kept block that cannot fit a fresh page with its lead is oversize.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2) },
		{ ..base, lead: Layout.Unit.from_raw(1000), lines: Semantics.Range.from_start_and_length(2, 2), policy: { ..base.policy, keep_together: True } },
	]
	plan = KernelPageLayout.Plan.build(blocks, test_lines.take_first(4), test_constraints, test_limits)?
	placements = KernelPageLayout.Plan.placements(plan)
	moved = KernelPageLayout.Plan.pages(plan).len() == 2 and list_at(placements, 2).baseline.y.raw() == 2200 and list_at(placements, 3).baseline.y.raw() == 1200
	oversize = match KernelPageLayout.Plan.build([{ ..base, lead: Layout.Unit.from_raw(1000), lines: Semantics.Range.from_start_and_length(0, 3), policy: { ..base.policy, keep_together: True } }], test_lines.take_first(3), test_constraints, test_limits) {
		Err(Oversize({ available: 3000, block: 0, required: 4000 })) => True
		_ => False
	}
	moved and oversize
}

# Page templates: the lead region receives its block on the first page at
# its own top, the first page flows in its own frame below it, and later
# pages flow in the continuation frame.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		base,
		{ ..base, lines: Semantics.Range.from_start_and_length(1, 2) },
		{ ..base, lines: Semantics.Range.from_start_and_length(3, 2) },
	]
	template = {
		continuation: { height: Layout.Unit.from_raw(2000), top: Layout.Unit.from_raw(1000) },
		first: { height: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(2000) },
		lead: Lead({ blocks: 1, frame: { height: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(500) } }),
	}
	plan = KernelPageLayout.Plan.build_with_template(blocks, [], test_lines.take_first(5), test_constraints, template, test_limits)?
	pages = KernelPageLayout.Plan.pages(plan)
	placements = KernelPageLayout.Plan.placements(plan)
	fragments = KernelPageLayout.Plan.fragments(plan)

	## Frame top 4000; the lead line's baseline is 500 + 800 below it, the
	## first page's body line 2000 + 800 below it, and a continuation page's
	## first line 1000 + 800 below it.
	pages.len() == 3 and list_at(placements, 0).baseline.y.raw() == 2700 and list_at(placements, 1).baseline.y.raw() == 1200 and list_at(placements, 2).baseline.y.raw() == 2200 and list_at(fragments, 0).page.index() == 0 and list_at(fragments, 1).page.index() == 0 and list_at(fragments, 2).page.index() == 1
}

# Lead content taller than its region fails with both heights; it is
# never split into the body flow.
expect {
	base = { ..test_block, policy: { ..test_policy, minimum_first_lines: 1, minimum_last_lines: 1 } }
	blocks = [
		{ ..base, lines: Semantics.Range.from_start_and_length(0, 2) },
		{ ..base, lines: Semantics.Range.from_start_and_length(2, 1) },
	]
	template = {
		continuation: { height: Layout.Unit.from_raw(3000), top: Layout.Unit.from_raw(0) },
		first: { height: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(2000) },
		lead: Lead({ blocks: 1, frame: { height: Layout.Unit.from_raw(1000), top: Layout.Unit.from_raw(0) } }),
	}
	match KernelPageLayout.Plan.build_with_template(blocks, [], test_lines.take_first(3), test_constraints, template, test_limits) {
		Err(LeadOverflow({ available: 1000, required: 2000 })) => True
		_ => False
	}
}
