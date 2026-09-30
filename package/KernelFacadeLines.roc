import Document
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeTables
import KernelLineLayout
import KernelShape
import Layout
import Semantics
import Text
import Theme

KernelFacadeLines :: [].{
	Dimension : [Blocks, Runs]
	Error : [
		ArithmeticOverflow,

		## A custom block's measured box is wider than the flow region
		## around it.
		CustomWidth({ available : U64, custom : U64, width : U64 }),
		InvalidGeometry,
		InvalidRun({ block : U64, run : U64 }),
		LabelTooWide({ available : U64, block : U64, width : U64 }),
		LineLayout(KernelLineLayout.Error),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		RunCoverage({ actual : U64, expected : U64 }),
		Tables(KernelFacadeTables.Error),
	]
	Limits :: { line : KernelLineLayout.BatchLimits, max_blocks : U64, max_runs : U64 }.{
		make : { line : KernelLineLayout.BatchLimits, max_blocks : U64, max_runs : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Preserve the logical-to-physical shaped-run relation alongside the line
	## ranges. The present line breaker accepts one physical run per logical
	## request; that restriction is checked below rather than encoded as an
	## accidental equality of dense IDs.
	##
	## A list block is indented by the label columns of its enclosing
	## lists; its generated label paints start-aligned in its own list's
	## column before its body, at `offset`. A list's column is the theme's
	## list indent, widened for the whole list when its widest label (plus
	## half the label's size as a gap) does not fit.
	## A body that spans several explicit-line-break segments has one line
	## request per segment, and its `lines` range covers them in order.
	##
	## `ContentlessCell` is a table cell with no content: it has no line.
	BlockLines : [ContentlessCell, TextBlock({ body : { lines : Semantics.Range, runs : KernelFacadeShape.LogicalRun }, body_offset : Layout.Unit, label : [Label({ lines : Semantics.Range, offset : Layout.Unit, runs : KernelFacadeShape.LogicalRun }), NoLabel] })]
	Work : {
		block_mapping_visits : U64,
		blocks : U64,
		content_width : U64,
		line : KernelLineLayout.BatchWork,
		run_writes : U64,
	}

	## `geometry` holds the resolved table geometry when the document has
	## tables; each cell's lines are laid out at its column text width.
	Plan :: { blocks : List(BlockLines), geometry : [NoTables, WithTables(KernelFacadeTables.Plan)], line : KernelLineLayout.BatchPlan, work : Work }.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |authoring, shape, sources, page, theme, limits| build_plan(authoring, shape, sources, page, theme, limits)

		## The authoring-aware entry: a document with tables resolves its
		## column widths once from measured cell widths, then lays every
		## cell out at its text width through the logical batch; any other
		## document takes `build` exactly.
		build_authoring : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_authoring = |authoring, shape, sources, page, theme, limits| if authoring.tables.is_empty() build_plan(authoring, shape, sources, page, theme, limits) else build_table_plan(authoring, shape, sources, page, theme, limits)

		geometry : Plan -> [NoTables, WithTables(KernelFacadeTables.Plan)]
		geometry = |plan| plan.geometry

		## The logical path: one line-layout request per logical run,
		## measured across its adjacent physical face or occurrence runs.
		build_ordered : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_ordered = |authoring, shape, sources, page, theme, limits| build_ordered_plan(authoring, shape, sources, page, theme, limits, [])

		build_ordered_authoring : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_ordered_authoring = |authoring, shape, sources, page, theme, limits| if authoring.tables.is_empty() build_ordered_plan(authoring, shape, sources, page, theme, limits, []) else build_table_plan(authoring, shape, sources, page, theme, limits)

		blocks : Plan -> List(BlockLines)
		blocks = |plan| plan.blocks

		line : Plan -> KernelLineLayout.BatchPlan
		line = |plan| plan.line

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, KernelFacadeLines.Limits -> Try(KernelFacadeLines.Plan, KernelFacadeLines.Error)
build_plan = |authoring, shape, sources, page, theme, limits| {
	block_runs = KernelFacadeShape.Plan.block_runs(shape)

	## A rich paragraph's logical run spans several physical runs; the
	## logical batch measures such ranges. Documents whose runs are all
	## single keep the exact one-run batch, unless a code span holds its
	## words together, which only the logical batch applies.
	if has_multi_run(block_runs) or has_code_holds(authoring, shape, sources) {
		return build_ordered_plan(authoring, shape, sources, page, theme, limits, [])
	}
	shape_requests = KernelFacadeShape.Plan.requests(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	run_count = shape_requests.len()
	check_limit(block_runs.len(), limits.max_blocks, Blocks)?
	check_limit(run_count, limits.max_runs, Runs)?
	if run_count == 0 or run_count != shape_batch.store.runs.len() {
		return Err(RunCoverage({ actual: shape_batch.store.runs.len(), expected: run_count }))
	}
	content_width = calculate_content_width(page, Theme.page_margin(theme))?
	indent = positive_raw(Theme.bullet_indent(theme))?
	if indent >= content_width {
		return Err(InvalidGeometry)
	}
	geometries = list_geometries(authoring, block_runs, shape_batch.store, indent, content_width)?
	default_request = { source: list_at(shape_requests, 0).source, width: Layout.Unit.from_raw(content_width.to_i64_wrap()) }
	var $line_requests = List.repeat(default_request, run_count)
	var $next_run = 0
	var $block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			TextBlock({ body, label, level: _ }) => {
				geometry = list_at(geometries, $block_index)
				match label {
					NoLabel => {}
					Label(label_run) => {
						label_index = single_run_index(label_run, $block_index)?
						if label_index != $next_run or label_index >= run_count {
							return Err(InvalidRun({ block: $block_index, run: label_index }))
						}
						$line_requests = list_set($line_requests, label_index, { source: list_at(shape_requests, label_index).source, width: Layout.Unit.from_raw(geometry.column.to_i64_wrap()) })
						$next_run = checked_add($next_run, 1)?
					}
				}
				body_index = single_run_index(body, $block_index)?
				if body_index != $next_run or body_index >= run_count {
					return Err(InvalidRun({ block: $block_index, run: body_index }))
				}
				$line_requests = list_set($line_requests, body_index, { source: list_at(shape_requests, body_index).source, width: Layout.Unit.from_raw(geometry.body_width.to_i64_wrap()) })
				$next_run = checked_add($next_run, 1)?
			}
			ContentlessCell => {}
		}
		$block_index = $block_index + 1
	}
	if $next_run != run_count {
		return Err(RunCoverage({ actual: $next_run, expected: run_count }))
	}
	line = KernelLineLayout.BatchPlan.build(sources, shape_requests, shape_batch.store, $line_requests, limits.line) ? LineLayout
	run_lines = KernelLineLayout.BatchPlan.run_lines(line)
	var $blocks = List.with_capacity(block_runs.len())
	$block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			TextBlock({ body, label, level: _ }) => {
				geometry = list_at(geometries, $block_index)
				body_index = single_run_index(body, $block_index)?
				body_lines = list_at(run_lines, body_index)
				label_lines = match label {
					NoLabel => NoLabel
					Label(label_run) => {
						label_index = single_run_index(label_run, $block_index)?
						Label({ lines: list_at(run_lines, label_index), offset: Layout.Unit.from_raw(geometry.label_offset.to_i64_wrap()), runs: label_run })
					}
				}
				$blocks = $blocks.append(TextBlock({ body: { lines: body_lines, runs: body }, body_offset: Layout.Unit.from_raw(geometry.body_offset.to_i64_wrap()), label: label_lines }))
			}
			ContentlessCell => {
				$blocks = $blocks.append(ContentlessCell)
			}
		}
		$block_index = $block_index + 1
	}
	Ok(
		KernelFacadeLines.Plan.{
			blocks: $blocks,
			geometry: NoTables,
			line,
			work: {
				block_mapping_visits: block_runs.len(),
				blocks: block_runs.len(),
				content_width,
				line: KernelLineLayout.BatchPlan.work(line),
				run_writes: run_count,
			},
		},
	)
}

## Tables resolve their geometry before any line is broken; each cell's
## text width then replaces the flow width of its block.
build_table_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, KernelFacadeLines.Limits -> Try(KernelFacadeLines.Plan, KernelFacadeLines.Error)
build_table_plan = |authoring, shape, sources, page, theme, limits| {
	content_width = calculate_content_width(page, Theme.page_margin(theme))?
	tables = KernelFacadeTables.Plan.build(authoring, shape, sources, content_width, theme, KernelLineLayout.BatchLimits.line(limits.line)) ? Tables
	var $widths = List.repeat(0, authoring.blocks.len())
	for cell in KernelFacadeTables.Plan.cells(tables) {
		$widths = list_set($widths, cell.block, cell.width)
	}
	plan = build_ordered_plan(authoring, shape, sources, page, theme, limits, $widths)?
	Ok({ ..plan, geometry: WithTables(tables) })
}

## `widths` is empty, or holds one text width per block where a nonzero
## entry (a table cell's) replaces the block's flow width.
build_ordered_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, KernelFacadeLines.Limits, List(U64) -> Try(KernelFacadeLines.Plan, KernelFacadeLines.Error)
build_ordered_plan = |authoring, shape, sources, page, theme, limits, widths| {
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	shape_requests = KernelFacadeShape.Plan.requests(shape)
	shape_batch = KernelFacadeShape.Plan.shape(shape)
	run_count = shape_requests.len()
	check_limit(block_runs.len(), limits.max_blocks, Blocks)?
	check_limit(run_count, limits.max_runs, Runs)?
	if run_count == 0 or run_count != shape_batch.store.runs.len() {
		return Err(RunCoverage({ actual: shape_batch.store.runs.len(), expected: run_count }))
	}
	content_width = calculate_content_width(page, Theme.page_margin(theme))?
	indent = positive_raw(Theme.bullet_indent(theme))?
	if indent >= content_width {
		return Err(InvalidGeometry)
	}
	geometries = list_geometries(authoring, block_runs, shape_batch.store, indent, content_width)?
	var $line_requests = []
	var $holds = []
	var $logical_index_of_body = List.repeat(0, block_runs.len())
	var $logical_index_of_label = List.repeat(0, block_runs.len())
	var $next_physical = 0
	var $block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			TextBlock({ body, label, level: _ }) => {
				geometry = list_at(geometries, $block_index)
				label_request = match label {
					NoLabel => NoLabel
					Label(label_run) => {
						start = logical_run_bounds(label_run, $block_index, $next_physical, run_count)?
						$logical_index_of_label = list_set($logical_index_of_label, $block_index, $line_requests.len())
						$next_physical = checked_add(start, label_run.physical.length())?
						Label({
							runs: label_run.physical,
							source: list_at(shape_requests, start).source,
							width: Layout.Unit.from_raw(geometry.column.to_i64_wrap()),
						})
					}
				}
				body_start = logical_run_bounds(body, $block_index, $next_physical, run_count)?
				override = if widths.is_empty() 0 else list_at(widths, $block_index)
				width = if override == 0 geometry.body_width else override
				$logical_index_of_body = list_set(
					$logical_index_of_body,
					$block_index,
					$line_requests.len() + (match label_request {
						NoLabel => 0
						Label(_) => 1
					}),
				)
				$next_physical = checked_add(body_start, body.physical.length())?
				first_body_request = $line_requests.len() + (match label_request {
					NoLabel => 0
					Label(_) => 1
				})
				$holds = append_holds($holds, KernelFacadeShape.Plan.code_holds(shape, authoring, $block_index, sources), shape_requests, first_body_request, body_start, body_start + body.physical.length())
				$line_requests = append_logical_requests(
					$line_requests,
					label_request,
					{
						runs: Semantics.Range.from_start_and_length(body_start, segment_length(shape_requests, body_start, body_start + body.physical.length())),
						source: list_at(shape_requests, body_start).source,
						width: Layout.Unit.from_raw(width.to_i64_wrap()),
					},
				)

				## Each further explicit-line-break segment of the body is its
				## own source and its own line request.
				var $segment_start = body_start + segment_length(shape_requests, body_start, body_start + body.physical.length())
				while $segment_start < body_start + body.physical.length() {
					length = segment_length(shape_requests, $segment_start, body_start + body.physical.length())
					$line_requests = $line_requests.append({
						runs: Semantics.Range.from_start_and_length($segment_start, length),
						source: list_at(shape_requests, $segment_start).source,
						width: Layout.Unit.from_raw(width.to_i64_wrap()),
					})
					$segment_start = $segment_start + length
				}
			}
			ContentlessCell => {}
		}
		$block_index = $block_index + 1
	}
	if $next_physical != run_count {
		return Err(RunCoverage({ actual: $next_physical, expected: run_count }))
	}
	line = (if $holds.is_empty() KernelLineLayout.BatchPlan.build_logical(sources, shape_batch.store, $line_requests, limits.line) else KernelLineLayout.BatchPlan.build_logical_held(sources, shape_batch.store, $line_requests, $holds, limits.line)) ? LineLayout
	run_lines = KernelLineLayout.BatchPlan.run_lines(line)
	var $blocks = List.with_capacity(block_runs.len())
	$block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			TextBlock({ body, label, level: _ }) => {
				geometry = list_at(geometries, $block_index)
				first_request = list_at($logical_index_of_body, $block_index)
				segments = segment_count(shape_requests, body.physical.start(), body.physical.start() + body.physical.length())
				first_lines = list_at(run_lines, first_request)
				last_lines = list_at(run_lines, first_request + segments - 1)
				body_lines = if segments == 1 first_lines else Semantics.Range.from_start_and_length(first_lines.start(), last_lines.start() + last_lines.length() - first_lines.start())
				label_lines = match label {
					NoLabel => NoLabel
					Label(label_run) => Label({ lines: list_at(run_lines, list_at($logical_index_of_label, $block_index)), offset: Layout.Unit.from_raw(geometry.label_offset.to_i64_wrap()), runs: label_run })
				}
				$blocks = $blocks.append(TextBlock({ body: { lines: body_lines, runs: body }, body_offset: Layout.Unit.from_raw(geometry.body_offset.to_i64_wrap()), label: label_lines }))
			}
			ContentlessCell => {
				$blocks = $blocks.append(ContentlessCell)
			}
		}
		$block_index = $block_index + 1
	}
	Ok(
		KernelFacadeLines.Plan.{
			blocks: $blocks,
			geometry: NoTables,
			line,
			work: {
				block_mapping_visits: block_runs.len(),
				blocks: block_runs.len(),
				content_width,
				line: KernelLineLayout.BatchPlan.work(line),
				run_writes: $line_requests.len(),
			},
		},
	)
}

## Whether any block's code span holds a word together. It scans each
## block's inline records once and allocates only for a code leaf that
## has an interior break opportunity.
has_code_holds : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source) -> Bool
has_code_holds = |authoring, shape, sources| {
	var $block = 0
	var $found = False
	while !$found and $block < authoring.blocks.len() {
		$found = !KernelFacadeShape.Plan.code_holds(shape, authoring, $block, sources).is_empty()
		$block = $block + 1
	}
	$found
}

## A block's code holds as line-layout holds: each goes to the line
## request of the explicit-line-break segment holding its run. The body's
## segments are its line requests from `first_request` on, in run order.
append_holds : List(KernelLineLayout.Hold), List(KernelFacadeShape.CodeHold), List(KernelShape.SimpleRequest), U64, U64, U64 -> List(KernelLineLayout.Hold)
append_holds = |holds, code, requests, first_request, body_start, body_end| {
	if code.is_empty() {
		return holds
	}
	var $holds = holds
	var $request = first_request
	var $segment_start = body_start
	var $segment_end = body_start + segment_length(requests, body_start, body_end)
	for hold in code {
		while hold.run >= $segment_end and $segment_end < body_end {
			$segment_start = $segment_end
			$segment_end = $segment_start + segment_length(requests, $segment_start, body_end)
			$request = $request + 1
		}
		$holds = $holds.append({ request: $request, scalars: hold.scalars })
	}
	$holds
}

## An ordered logical run names a non-empty adjacent physical range starting
## exactly where the previous logical run ended.
logical_run_bounds : KernelFacadeShape.LogicalRun, U64, U64, U64 -> Try(U64, KernelFacadeLines.Error)
logical_run_bounds = |logical, block, expected_start, run_count| {
	physical = logical.physical
	start = physical.start()
	length = physical.length()
	if length == 0 or start != expected_start or start >= run_count or length > run_count - start {
		Err(InvalidRun({ block, run: start }))
	} else {
		Ok(start)
	}
}

## The existing LTR facade path is deliberately narrow, but it now states
## that boundary in terms of the logical range it receives. A later physical
## multi-run line-breaker can consume a longer range without rewriting block
## ownership or recovering a relationship from run IDs.
single_run_index : KernelFacadeShape.LogicalRun, U64 -> Try(U64, KernelFacadeLines.Error)
single_run_index = |logical, block| {
	physical = logical.physical
	if physical.length() != 1 {
		Err(InvalidRun({ block, run: physical.start() }))
	} else {
		Ok(physical.start())
	}
}

has_multi_run : List(KernelFacadeShape.BlockRuns) -> Bool
has_multi_run = |block_runs| {
	var $index = 0
	var $found = False
	while !$found and $index < block_runs.len() {
		$found = match list_at(block_runs, $index) {
			TextBlock({ body, label: _, level: _ }) => body.physical.length() != 1
			ContentlessCell => False
		}
		$index = $index + 1
	}
	$found
}

## Every block's horizontal geometry, in O(blocks + groups). A list's
## label column is the theme indent, or, when the list's widest generated
## label does not fit it, that label's width plus half its size as the gap
## to the body; all the list's items share the column, so their bodies
## stay aligned. A body is indented by the columns of its enclosing lists
## (a legacy bullet list is one level deep); a label paints at the start
## of its own list's column. A column that leaves its body no width is
## `LabelTooWide`: a label is never shrunk or allowed to overlap its body.
list_geometries : Document.NormalizedAuthoring, List(KernelFacadeShape.BlockRuns), Text.Store, U64, U64 -> Try(List(BlockGeometry), KernelFacadeLines.Error)
list_geometries = |authoring, block_runs, store, indent, content_width| {
	groups = authoring.groups
	blocks = authoring.blocks
	var $group_columns = List.repeat(indent, groups.len())
	var $legacy_columns = []
	var $block = 0
	while $block < block_runs.len() {
		match list_at(block_runs, $block) {
			TextBlock({ body: _, label: Label(label_run), level: _ }) => {
				measured = label_width(store, label_run)?
				column = if measured.width <= indent indent else checked_add(measured.width, measured.size // 2)?
				match list_key(blocks, groups, $block) {
					LegacyList(list) => {
						while $legacy_columns.len() <= list {
							$legacy_columns = $legacy_columns.append(indent)
						}
						$legacy_columns = list_set($legacy_columns, list, U64.max(list_at($legacy_columns, list), column))
					}
					ListGroup(group) => {
						$group_columns = list_set($group_columns, group, U64.max(list_at($group_columns, group), column))
					}
					NoList => return Err(InvalidGeometry)
				}
			}
			TextBlock(_) | ContentlessCell => {}
		}
		$block = $block + 1
	}

	## Groups are in preorder, so a parent's offset is known first. A
	## custom block insets its content on both sides inside its measured
	## width, so a document with custom blocks also tracks each group's end
	## edge (only then, so other documents allocate nothing for it).
	customs = authoring.customs
	var $offsets = List.with_capacity(groups.len())
	var $ends = if customs.is_empty() [] else List.with_capacity(groups.len())
	for group in groups {
		outer = if group.parent == 0 0 else list_at($offsets, group.parent - 1)
		own = match group.kind {
			ItemList(_) => list_at($group_columns, $offsets.len())
			Custom(_) => positive_raw(list_at(customs, custom_index(group.kind)).inset)?
			_ => 0
		}
		if !customs.is_empty() {
			outer_end = if group.parent == 0 content_width else list_at($ends, group.parent - 1)
			end = match group.kind {
				Custom(index) => {
					custom = list_at(customs, index.to_u64())
					width = positive_raw(custom.width)?
					available = if outer_end > outer outer_end - outer else 0
					if width > available {
						return Err(CustomWidth({ available, custom: index.to_u64(), width }))
					}
					outer + width - positive_raw(custom.inset)?
				}
				_ => outer_end
			}
			$ends = $ends.append(end)
		}
		$offsets = $offsets.append(checked_add(outer, own)?)
	}
	var $geometries = List.with_capacity(block_runs.len())
	$block = 0
	while $block < block_runs.len() {
		record = list_at(blocks, $block)
		outer = if record.parent == 0 0 else list_at($offsets, record.parent - 1)
		geometry = match list_at(block_runs, $block) {
			TextBlock({ body: _, label: Label(_), level: _ }) => {
				placed = match list_key(blocks, groups, $block) {
					LegacyList(list) => {
						column = list_at($legacy_columns, list)
						{ body_offset: checked_add(outer, column)?, column }
					}
					ListGroup(group) => { body_offset: outer, column: list_at($group_columns, group) }
					NoList => return Err(InvalidGeometry)
				}
				label_offset = placed.body_offset - placed.column
				if placed.body_offset >= content_width {
					return Err(LabelTooWide({ available: content_width - label_offset, block: $block, width: placed.column }))
				}
				{ body_offset: placed.body_offset, body_width: content_width - placed.body_offset, column: placed.column, label_offset }
			}
			TextBlock(_) | ContentlessCell => {
				end = if $ends.is_empty() or record.parent == 0 content_width else list_at($ends, record.parent - 1)
				if outer >= end {
					return Err(InvalidGeometry)
				}
				{ body_offset: outer, body_width: end - outer, column: indent, label_offset: 0 }
			}
		}
		$geometries = $geometries.append(geometry)
		$block = $block + 1
	}
	Ok($geometries)
}

BlockGeometry : { body_offset : U64, body_width : U64, column : U64, label_offset : U64 }

## The list whose label a labelled block paints: a legacy bullet list, or
## the `ItemList` group around the block's `ListItem` group.
list_key : List(Document.NormalizedBlock), List(Document.NormalizedGroup), U64 -> [LegacyList(U64), ListGroup(U64), NoList]
list_key = |blocks, groups, block| {
	record = list_at(blocks, block)
	match record.kind {
		Bullet({ item: _, list }) => LegacyList(list)
		_ => if record.parent == 0 {
			NoList
		} else {
			item = list_at(groups, record.parent - 1)
			if item.parent == 0 NoList else ListGroup(item.parent - 1)
		}
	}
}

## A generated label's advance and size: it has no break opportunity, so
## its whole advance must fit its column.
label_width : Text.Store, KernelFacadeShape.LogicalRun -> Try({ size : U64, width : U64 }, KernelFacadeLines.Error)
label_width = |store, label| {
	var $width = 0
	var $size = 0
	var $run = label.physical.start()
	while $run < label.physical.start() + label.physical.length() {
		record = list_at(store.runs, $run)
		raw_size = record.size.raw()
		$size = if raw_size > 0 U64.max($size, raw_size.to_u64_wrap()) else $size
		var $glyph = record.glyphs.start()
		while $glyph < record.glyphs.start() + record.glyphs.length() {
			advance = list_at(store.glyphs, $glyph).advance_x.raw()
			$width = if advance > 0 checked_add($width, advance.to_u64_wrap())? else $width
			$glyph = $glyph + 1
		}
		$run = $run + 1
	}
	Ok({ size: $size, width: $width })
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

segment_count : List(KernelShape.SimpleRequest), U64, U64 -> U64
segment_count = |requests, start, end| {
	var $count = 0
	var $index = start
	while $index < end {
		$index = $index + segment_length(requests, $index, end)
		$count = $count + 1
	}
	$count
}

checked_mul : U64, U64 -> Try(U64, KernelFacadeLines.Error)
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

calculate_content_width : Layout.Size, Theme.PageMargin -> Try(U64, KernelFacadeLines.Error)
calculate_content_width = |page, margins| {
	_height = positive_raw(page.height)?
	width = positive_raw(page.width)?
	left = nonnegative_raw(margins.left)?
	right = nonnegative_raw(margins.right)?
	horizontal = checked_add(left, right)?
	if horizontal >= width Err(InvalidGeometry) else Ok(width - horizontal)
}

positive_raw : Layout.Unit -> Try(U64, KernelFacadeLines.Error)
positive_raw = |unit| {
	raw = unit.raw()
	if raw <= 0 Err(InvalidGeometry) else Ok(raw.to_u64_wrap())
}

nonnegative_raw : Layout.Unit -> Try(U64, KernelFacadeLines.Error)
nonnegative_raw = |unit| {
	raw = unit.raw()
	if raw < 0 Err(InvalidGeometry) else Ok(raw.to_u64_wrap())
}

check_limit : U64, U64, KernelFacadeLines.Dimension -> Try({}, KernelFacadeLines.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeLines.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade line index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade line write escaped"
	}
	Ok(updated) => updated
}

expect match calculate_content_width(
	{ height: Layout.Unit.from_raw(1000), width: Layout.Unit.from_raw(1000) },
	{ bottom: Layout.Unit.from_raw(0), left: Layout.Unit.from_raw(500), right: Layout.Unit.from_raw(500), top: Layout.Unit.from_raw(0) },
) {
	Err(InvalidGeometry) => True
	_ => False
}

expect match single_run_index({ physical: Semantics.Range.from_start_and_length(4, 2) }, 7) {
	Err(InvalidRun({ block: 7, run: 4 })) => True
	_ => False
}

expect match calculate_content_width(
	{ height: Layout.Unit.from_raw(0), width: Layout.Unit.from_raw(1000) },
	{ bottom: Layout.Unit.from_raw(0), left: Layout.Unit.from_raw(0), right: Layout.Unit.from_raw(0), top: Layout.Unit.from_raw(0) },
) {
	Err(InvalidGeometry) => True
	_ => False
}

# Consume the growing store once per block, after fallible validation. The
# optional label precedes its body without retaining an earlier list version.
append_logical_requests : List(KernelLineLayout.LogicalRunRequest), [NoLabel, Label(KernelLineLayout.LogicalRunRequest)], KernelLineLayout.LogicalRunRequest -> List(KernelLineLayout.LogicalRunRequest)
append_logical_requests = |requests, label, body| match label {
	NoLabel => requests.append(body)
	Label(request) => requests.append(request).append(body)
}

custom_index : Document.NormalizedGroupKind -> U64
custom_index = |kind| match kind {
	Custom(index) => index.to_u64()
	_ => 0
}
