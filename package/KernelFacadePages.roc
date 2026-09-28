import Document
import KernelFacadeLines
import KernelFacadeShape
import KernelLineLayout
import KernelPageLayout
import Layout
import Semantics
import KernelShape
import Text
import Theme

KernelFacadePages :: [].{
	Dimension : [Blocks, Rows]
	Error : [
		ArithmeticOverflow,
		InvalidBlock({ block : U64 }),
		InvalidLine({ block : U64, line : U64 }),
		InvalidRun({ block : U64, run : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		PageBreakPosition({ page_break : U64 }),
		PageLayout(KernelPageLayout.Error),
	]
	Limits :: { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits }.{
		make : { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## One painted row: a body line at `body_offset` from the flow edge, the
	## logical run it belongs to (its explicit-line-break segment when the
	## body has several), and an optional generated label at `offset`.
	Row : {
		body_line : U64,
		body_offset : Layout.Unit,
		body_runs : KernelFacadeShape.LogicalRun,
		label : [Label({ line : U64, offset : Layout.Unit, runs : KernelFacadeShape.LogicalRun }), NoLabel],
	}
	Work : {
		block_planning_visits : U64,
		block_writes : U64,
		label_rows : U64,
		page : KernelPageLayout.Work,
		row_writes : U64,
	}
	Plan :: { page : KernelPageLayout.Plan, rows : List(Row), work : Work }.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |authoring, shape, lines, page, theme, limits| build_plan(authoring, shape, lines, page, theme, limits)

		page : Plan -> KernelPageLayout.Plan
		page = |plan| plan.page

		## The preferences the accepted pagination relaxed, with the
		## declaring block and page, for the preparation report.
		relaxations : Plan -> List(KernelPageLayout.Relaxation)
		relaxations = |plan| KernelPageLayout.Plan.relaxations(plan.page)

		rows : Plan -> List(Row)
		rows = |plan| plan.rows

		work : Plan -> Work
		work = |plan| plan.work
	}
}

## Layout policy per block, from the authored flow: headings and titles keep
## with the next block (R1, theme) and are unsplittable with figures;
## `keep_with_next` groups bind their last leaf (`Required`, else R2 unless
## the theme's R1 already applies); a page break sets the next leaf's
## mandatory `break_before`; spacers add to the preceding leaf's spacing;
## `keep_together` groups become required atomic groups. Documents without
## these constructs allocate nothing for them.
build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, KernelFacadePages.Limits -> Try(KernelFacadePages.Plan, KernelFacadePages.Error)
build_plan = |authoring, shape, line_plan, page_size, theme, limits| {
	block_lines = KernelFacadeLines.Plan.blocks(line_plan)
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	shape_requests = KernelFacadeShape.Plan.requests(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	line_batch = KernelFacadeLines.Plan.line(line_plan)
	lines = KernelLineLayout.BatchPlan.lines(line_batch)
	if authoring.blocks.len() == 0 or authoring.blocks.len() != block_lines.len() or block_lines.len() != block_runs.len() or styles.len() != shape_batch.store.runs.len() {
		return Err(InvalidBlock({ block: 0 }))
	}
	check_limit(authoring.blocks.len(), limits.max_blocks, Blocks)?
	check_page_breaks(authoring.page_breaks, authoring.blocks.len())?
	author_keeps = authored_keeps(authoring.groups, authoring.blocks.len())
	var $row_count = 0
	var $block_index = 0
	while $block_index < block_lines.len() {
		match list_at(block_lines, $block_index) {
			TextBlock({ body, body_offset: _, label }) => {
				body_end = range_end(body.lines)?
				if body.lines.length() == 0 or body_end > lines.len() {
					return Err(InvalidBlock({ block: $block_index }))
				}
				match label {
					NoLabel => {}
					Label(label_lines) => if label_lines.lines.length() != 1 or range_end(label_lines.lines)? > lines.len() {
						return Err(InvalidBlock({ block: $block_index }))
					}
				}
				$row_count = checked_add($row_count, body.lines.length())?
				check_limit($row_count, limits.max_rows, Rows)?
			}
		}
		$block_index = $block_index + 1
	}
	var $visual_lines = List.with_capacity($row_count)
	var $rows = List.with_capacity($row_count)
	var $page_blocks = List.with_capacity(authoring.blocks.len())
	var $label_rows = 0
	var $break_cursor = 0
	var $spacer_cursor = 0
	$block_index = 0
	while $block_index < block_lines.len() {
		author_block = list_at(authoring.blocks, $block_index)
		line_block = list_at(block_lines, $block_index)
		run_block = list_at(block_runs, $block_index)
		match (line_block, run_block) {
			(TextBlock({ body: body_lines, body_offset, label: label_lines }), TextBlock({ body: body_run, label: label_run, level })) => {
				body_index = logical_run_first(body_run, $block_index, shape_batch.store.runs.len())?
				assert_logical_identity(shape_batch.store.runs, styles, body_run, $block_index)?
				body_record = list_at(shape_batch.store.runs, body_index)
				body_style = list_at(styles, body_index)
				segmented = list_at(shape_requests, body_index).source.index() != list_at(shape_requests, body_index + body_run.physical.length() - 1).source.index()
				visual_start = $visual_lines.len()
				var $segment_start = body_index
				var $segment_length = if segmented segment_length(shape_requests, body_index, body_index + body_run.physical.length()) else body_run.physical.length()
				var $local = 0
				while $local < body_lines.lines.length() {
					body_line_index = body_lines.lines.start() + $local
					label = if $local == 0 {
						match (label_lines, label_run) {
							(NoLabel, NoLabel) => NoLabel
							(Label(label_range), Label(label_id)) => {
								_label_index = logical_run_first(label_id, $block_index, shape_batch.store.runs.len())?
								assert_logical_identity(shape_batch.store.runs, styles, label_id, $block_index)?
								$label_rows = checked_add($label_rows, 1)?
								Label({ line: label_range.lines.start(), offset: label_range.offset, runs: label_id })
							}
							_ => return Err(InvalidBlock({ block: $block_index }))
						}
					} else {
						NoLabel
					}
					if body_line_index >= lines.len() {
						return Err(InvalidLine({ block: $block_index, line: body_line_index }))
					}
					line = list_at(lines, body_line_index)

					## A line belongs to the explicit-line-break segment whose
					## physical runs hold its first cluster.
					if segmented {
						while $segment_start + $segment_length < body_index + body_run.physical.length() and line.clusters.start() >= segment_cluster_end(shape_batch.store.runs, $segment_start, $segment_length)? {
							$segment_start = $segment_start + $segment_length
							$segment_length = segment_length(shape_requests, $segment_start, body_index + body_run.physical.length())
						}
					}
					runs = if segmented { physical: Semantics.Range.from_start_and_length($segment_start, $segment_length) } else body_run
					$visual_lines = $visual_lines.append(line)
					$rows = $rows.append({ body_line: body_line_index, body_offset, body_runs: runs, label })
					$local = $local + 1
				}
				minimum = U64.min(2, body_lines.lines.length())
				theme_keep = keeps_with_next(author_block.kind) and $block_index + 1 < block_lines.len()
				authored = if author_keeps.is_empty() NoKeep else list_at(author_keeps, $block_index)
				keep_with_next = match authored {
					Required => Required
					_ => if theme_keep Preferred(HeadingKeep) else authored
				}
				spacing = if continues_list(authoring, block_runs, $block_index, level) 0 else nonnegative_raw(Theme.paragraph_spacing(theme))?
				spaced = spacer_total(authoring.spacers, $spacer_cursor, $block_index + 1)
				$spacer_cursor = spaced.cursor
				break_before = $break_cursor < authoring.page_breaks.len() and list_at(authoring.page_breaks, $break_cursor).block == $block_index
				if break_before {
					$break_cursor = $break_cursor + 1
				}
				$page_blocks = $page_blocks.append({
					baseline_offset: body_record.size,
					leading: body_style.leading,
					lines: Semantics.Range.from_start_and_length(visual_start, body_lines.lines.length()),
					occurrence: body_record.occurrence,
					policy: {
						break_before,
						keep_together: keeps_together(author_block.kind),
						keep_with_next,
						minimum_first_lines: minimum,
						minimum_last_lines: minimum,
					},
					space_after: Layout.Unit.from_raw(checked_add(spacing, spaced.amount)?.to_i64_wrap()),
				})
			}
			_ => return Err(InvalidBlock({ block: $block_index }))
		}
		$block_index = $block_index + 1
	}
	if $visual_lines.len() != $row_count or $rows.len() != $row_count {
		return Err(InvalidBlock({ block: block_lines.len() }))
	}
	keep_groups = together_groups(authoring.groups)
	constraints = { margins: Theme.page_margin(theme), page: page_size }
	page = (
		if keep_groups.is_empty() {
			KernelPageLayout.Plan.build($page_blocks, $visual_lines, constraints, limits.page)
		} else {
			KernelPageLayout.Plan.build_with_groups($page_blocks, keep_groups, $visual_lines, constraints, limits.page)
		}
	) ? PageLayout
	Ok(
		KernelFacadePages.Plan.{
			page,
			rows: $rows,
			work: {
				block_planning_visits: block_lines.len(),
				block_writes: $page_blocks.len(),
				label_rows: $label_rows,
				page: KernelPageLayout.Plan.work(page),
				row_writes: $rows.len(),
			},
		},
	)
}

## An explicit page break separates two flow blocks: one before the first
## leaf, after the last, or directly after another break would ask for an
## empty page, which is rejected rather than collapsed.
check_page_breaks : List(Document.NormalizedPageBreak), U64 -> Try({}, KernelFacadePages.Error)
check_page_breaks = |page_breaks, block_count| {
	var $index = 0
	while $index < page_breaks.len() {
		block = list_at(page_breaks, $index).block
		repeated = $index > 0 and list_at(page_breaks, $index - 1).block == block
		if block == 0 or block >= block_count or repeated {
			return Err(PageBreakPosition({ page_break: $index }))
		}
		$index = $index + 1
	}
	Ok({})
}

## The authored keep-with-next of each leaf: a `keep_with_next` group binds
## its last leaf; `Required` outranks `Preferred` when groups share it. Empty
## (and unallocated) when the document has no such group.
authored_keeps : List(Document.NormalizedGroup), U64 -> List(KernelPageLayout.Keep)
authored_keeps = |groups, block_count| {
	var $keeps = []
	for group in groups {
		match group.kind {
			KeepWithNext(keep) => {
				if $keeps.is_empty() {
					$keeps = List.repeat(NoKeep, block_count)
				}
				last = group.block_end - 1
				current = list_at($keeps, last)
				updated = match (keep, current) {
					(Required, _) => Required
					(Preferred, Required) => Required
					(Preferred, _) => Preferred(AuthorKeep)
				}
				$keeps = list_set($keeps, last, updated)
			}
			_ => {}
		}
	}
	$keeps
}

## Required keep-together groups in preorder, for page layout.
together_groups : List(Document.NormalizedGroup) -> List(KernelPageLayout.KeepGroup)
together_groups = |groups| {
	var $together = []
	for group in groups {
		match group.kind {
			KeepTogether => {
				$together = $together.append({ blocks: Semantics.Range.from_start_and_length(group.first_block, group.block_end - group.first_block) })
			}
			_ => {}
		}
	}
	$together
}

## The authored spacing after leaf `next - 1`: every spacer recorded before
## leaf `next`, from a forward cursor over the block-ordered spacers.
## Spacers before the first leaf fall at the top of the first page and are
## suppressed.
spacer_total : List(Document.NormalizedSpacer), U64, U64 -> { amount : U64, cursor : U64 }
spacer_total = |spacers, cursor, next| {
	var $cursor = cursor
	var $amount = 0
	while $cursor < spacers.len() and list_at(spacers, $cursor).block <= next {
		spacer = list_at(spacers, $cursor)
		raw = spacer.amount.raw()
		if spacer.block == next and raw > 0 {
			$amount = $amount + raw.to_u64_wrap()
		}
		$cursor = $cursor + 1
	}
	{ amount: $amount, cursor: $cursor }
}

## The number of physical runs from `start` (before `end`) sharing its
## source: one explicit-line-break segment of a body.
segment_length : List(KernelShape.SimpleRequest), U64, U64 -> U64
segment_length = |requests, start, end| {
	source = list_at(requests, start).source.index()
	var $index = start + 1
	while $index < end and list_at(requests, $index).source.index() == source {
		$index = $index + 1
	}
	$index - start
}

segment_cluster_end : List(Text.Run), U64, U64 -> Try(U64, KernelFacadePages.Error)
segment_cluster_end = |runs, start, length| range_end(list_at(runs, start + length - 1).clusters)

nonnegative_raw : Layout.Unit -> Try(U64, KernelFacadePages.Error)
nonnegative_raw = |value| {
	raw = value.raw()
	if raw < 0 Err(InvalidBlock({ block: 0 })) else Ok(raw.to_u64_wrap())
}

## A logical run's physical range must be non-empty and inside the shaped
## store; pagination consumes only its first run's identity facts after the
## whole range is proven identical.
logical_run_first : KernelFacadeShape.LogicalRun, U64, U64 -> Try(U64, KernelFacadePages.Error)
logical_run_first = |logical, block, run_count| {
	physical = logical.physical
	start = physical.start()
	length = physical.length()
	if length == 0 or start >= run_count or length > run_count - start {
		Err(InvalidRun({ block, run: start }))
	} else {
		Ok(start)
	}
}

## Every physical run of one logical run must carry the identical size and
## leading: pagination treats the logical run as one row source regardless
## of its face or occurrence split. Fill colors may differ between the
## occurrences of a rich paragraph; they are paint facts, not row geometry.
assert_logical_identity : List(Text.Run), List(KernelFacadeShape.RunStyle), KernelFacadeShape.LogicalRun, U64 -> Try({}, KernelFacadePages.Error)
assert_logical_identity = |runs, styles, logical, block| {
	start = logical.physical.start()
	length = logical.physical.length()
	if start >= runs.len() or length > runs.len() - start or start >= styles.len() or length > styles.len() - start {
		return Err(InvalidRun({ block, run: start }))
	}
	first = list_at(runs, start)
	first_style = list_at(styles, start)
	var $index = start + 1
	while $index < start + length {
		run = list_at(runs, $index)
		if run.size.raw() != first.size.raw() or list_at(styles, $index).leading.raw() != first_style.leading.raw() {
			return Err(InvalidRun({ block, run: $index }))
		}
		$index = $index + 1
	}
	Ok({})
}

keeps_together : Document.NormalizedBlockKind -> Bool
keeps_together = |kind| match kind {
	Figure(_) | Heading(_) | Title => True
	_ => False
}

keeps_with_next : Document.NormalizedBlockKind -> Bool
keeps_with_next = |kind| match kind {
	Heading(_) | Title => True
	_ => False
}

## Consecutive blocks of one list, at any nesting depth, stack without
## paragraph spacing: the legacy flat bullets, or two leaves inside the same
## outermost list.
continues_list : Document.NormalizedAuthoring, List(KernelFacadeShape.BlockRuns), U64, U64 -> Bool
continues_list = |authoring, block_runs, index, level| {
	blocks = authoring.blocks
	if index + 1 >= blocks.len() {
		return False
	}
	match (list_at(blocks, index).kind, list_at(blocks, index + 1).kind) {
		(Bullet({ list: left, item: _ }), Bullet({ list: right, item: _ })) => left == right
		_ => {
			next_level = match list_at(block_runs, index + 1) {
				TextBlock({ body: _, label: _, level: value }) => value
				ArtifactBlock(_) => 0
			}
			if level == 0 or next_level == 0 {
				False
			} else {
				list = outermost_list(authoring.groups, list_at(blocks, index).parent)
				list != 0 and list == outermost_list(authoring.groups, list_at(blocks, index + 1).parent)
			}
		}
	}
}

## The outermost list group above group code `code`.
outermost_list : List(Document.NormalizedGroup), U64 -> U64
outermost_list = |groups, code| {
	var $code = code
	var $found = 0
	while $code != 0 {
		group = list_at(groups, $code - 1)
		match group.kind {
			ItemList(_) => {
				$found = $code
			}
			_ => {}
		}
		$code = group.parent
	}
	$found
}

range_end : Semantics.Range -> Try(U64, KernelFacadePages.Error)
range_end = |range| checked_add(range.start(), range.length())

check_limit : U64, U64, KernelFacadePages.Dimension -> Try({}, KernelFacadePages.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadePages.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade page index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade page write escaped"
	}
	Ok(updated) => updated
}

expect keeps_together(Title) and keeps_with_next(Heading(2)) and !keeps_together(Paragraph)

expect {
	authoring = Document.normalize(Document.from_blocks({ contents: [Document.bullets(["One", "Two"]), Document.paragraph("Three")], language: "en-AU", title: "Lists" }))
	runs = List.repeat(TextBlock({ body: { physical: Semantics.Range.from_start_and_length(0, 1) }, label: NoLabel, level: 1 }), 3)
	continues_list(authoring, runs, 0, 1) and !continues_list(authoring, runs, 1, 1)
}

## Leaves of one nested list stack without spacing; the paragraph after the
## outermost list does not.
expect {
	item = |text| Document.list_item([Document.paragraph(text)])
	nested = Document.bullet_list([Document.list_item([Document.paragraph("One"), Document.bullet_list([item("Two")])]), item("Three")])
	authoring = Document.normalize(Document.from_blocks({ contents: [nested, Document.paragraph("After")], language: "en-AU", title: "Lists" }))
	runs = [1, 2, 1, 0].map(|level| TextBlock({ body: { physical: Semantics.Range.from_start_and_length(0, 1) }, label: NoLabel, level }))
	continues_list(authoring, runs, 0, 1) and continues_list(authoring, runs, 1, 2) and !continues_list(authoring, runs, 2, 1)
}
