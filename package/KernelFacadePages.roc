import Document
import KernelFacadeLines
import KernelFacadeShape
import KernelLineLayout
import KernelPageLayout
import Layout
import Semantics
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
		PageLayout(KernelPageLayout.Error),
	]
	Limits :: { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits }.{
		make : { max_blocks : U64, max_rows : U64, page : KernelPageLayout.Limits } -> Limits
		make = |limits| Limits.(limits)
	}
	Row : {
		body_line : U64,
		body_offset : Layout.Unit,
		body_run : Text.RunId,
		label : [Label({ line : U64, run : Text.RunId }), NoLabel],
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

		rows : Plan -> List(Row)
		rows = |plan| plan.rows

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, KernelFacadePages.Limits -> Try(KernelFacadePages.Plan, KernelFacadePages.Error)
build_plan = |authoring, shape, line_plan, page_size, theme, limits| {
	block_lines = KernelFacadeLines.Plan.blocks(line_plan)
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	line_batch = KernelFacadeLines.Plan.line(line_plan)
	lines = KernelLineLayout.BatchPlan.lines(line_batch)
	if authoring.blocks.len() == 0 or authoring.blocks.len() != block_lines.len() or block_lines.len() != block_runs.len() or styles.len() != shape_batch.store.runs.len() {
		return Err(InvalidBlock({ block: 0 }))
	}
	check_limit(authoring.blocks.len(), limits.max_blocks, Blocks)?
	var $row_count = 0
	var $block_index = 0
	while $block_index < block_lines.len() {
		match list_at(block_lines, $block_index) {
			TextBlock({ body, body_offset: _, label }) => {
				body_end = range_end(body)?
				if body.length() == 0 or body_end > lines.len() {
					return Err(InvalidBlock({ block: $block_index }))
				}
				match label {
					NoLabel => {}
					Label(label_lines) => if label_lines.length() != 1 or range_end(label_lines)? > lines.len() {
						return Err(InvalidBlock({ block: $block_index }))
					}
				}
				$row_count = checked_add($row_count, body.length())?
				check_limit($row_count, limits.max_rows, Rows)?
			}
		}
		$block_index = $block_index + 1
	}
	var $visual_lines = List.with_capacity($row_count)
	var $rows = List.with_capacity($row_count)
	var $page_blocks = List.with_capacity(authoring.blocks.len())
	var $label_rows = 0
	$block_index = 0
	while $block_index < block_lines.len() {
		author_block = list_at(authoring.blocks, $block_index)
		line_block = list_at(block_lines, $block_index)
		run_block = list_at(block_runs, $block_index)
		match (line_block, run_block) {
			(TextBlock({ body: body_lines, body_offset, label: label_lines }), TextBlock({ body: body_run, label: label_run })) => {
				body_index = body_run.index()
				if body_index >= shape_batch.store.runs.len() {
					return Err(InvalidRun({ block: $block_index, run: body_index }))
				}
				body_record = list_at(shape_batch.store.runs, body_index)
				body_style = list_at(styles, body_index)
				visual_start = $visual_lines.len()
				var $local = 0
				while $local < body_lines.length() {
					body_line_index = body_lines.start() + $local
					label = if $local == 0 {
						match (label_lines, label_run) {
							(NoLabel, NoLabel) => NoLabel
							(Label(label_range), Label(label_id)) => if label_id.index() >= shape_batch.store.runs.len() {
								return Err(InvalidRun({ block: $block_index, run: label_id.index() }))
							} else {
								$label_rows = checked_add($label_rows, 1)?
								Label({ line: label_range.start(), run: label_id })
							}
							_ => return Err(InvalidBlock({ block: $block_index }))
						}
					} else {
						NoLabel
					}
					if body_line_index >= lines.len() {
						return Err(InvalidLine({ block: $block_index, line: body_line_index }))
					}
					$visual_lines = $visual_lines.append(list_at(lines, body_line_index))
					$rows = $rows.append({ body_line: body_line_index, body_offset, body_run, label })
					$local = $local + 1
				}
				minimum = U64.min(2, body_lines.length())
				keep_with_next = keeps_with_next(author_block.kind) and $block_index + 1 < block_lines.len()
				space_after = if continues_list(authoring.blocks, $block_index) Layout.Unit.from_raw(0) else Theme.paragraph_spacing(theme)
				$page_blocks = $page_blocks.append({
					baseline_offset: body_record.size,
					leading: body_style.leading,
					lines: Semantics.Range.from_start_and_length(visual_start, body_lines.length()),
					occurrence: body_record.occurrence,
					policy: {
						break_before: False,
						keep_together: keeps_together(author_block.kind),
						keep_with_next,
						minimum_first_lines: minimum,
						minimum_last_lines: minimum,
					},
					space_after,
				})
			}
			_ => return Err(InvalidBlock({ block: $block_index }))
		}
		$block_index = $block_index + 1
	}
	if $visual_lines.len() != $row_count or $rows.len() != $row_count {
		return Err(InvalidBlock({ block: block_lines.len() }))
	}
	page = KernelPageLayout.Plan.build(
		$page_blocks,
		$visual_lines,
		{ margins: Theme.page_margin(theme), page: page_size },
		limits.page,
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

keeps_together : Document.NormalizedBlockKind -> Bool
keeps_together = |kind| match kind {
	Heading(_) | Title => True
	_ => False
}

keeps_with_next : Document.NormalizedBlockKind -> Bool
keeps_with_next = |kind| match kind {
	Heading(_) | Title => True
	_ => False
}

continues_list : List(Document.NormalizedBlock), U64 -> Bool
continues_list = |blocks, index| {
	if index + 1 >= blocks.len() {
		return False
	}
	match (list_at(blocks, index).kind, list_at(blocks, index + 1).kind) {
		(Bullet({ list: left, item: _ }), Bullet({ list: right, item: _ })) => left == right
		_ => False
	}
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

expect keeps_together(Title) and keeps_with_next(Heading(2)) and !keeps_together(Paragraph)

expect continues_list(
	[
		{ kind: Bullet({ item: 0, list: 0 }), text: "One" },
		{ kind: Bullet({ item: 1, list: 0 }), text: "Two" },
	],
	0,
)

expect !continues_list(
	[
		{ kind: Bullet({ item: 0, list: 0 }), text: "One" },
		{ kind: Paragraph, text: "Two" },
	],
	0,
)
