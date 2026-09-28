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
		ArtifactBlock({ block : U64, artifact : U64 }),
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
	## A block at list level `L` is indented by `L` theme list indents; its
	## generated label paints in the indent before its body, at `offset`.
	## A body that spans several explicit-line-break segments has one line
	## request per segment, and its `lines` range covers them in order.
	BlockLines : [TextBlock({ body : { lines : Semantics.Range, runs : KernelFacadeShape.LogicalRun }, body_offset : Layout.Unit, label : [Label({ lines : Semantics.Range, offset : Layout.Unit, runs : KernelFacadeShape.LogicalRun }), NoLabel] })]
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
		build : KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |shape, sources, page, theme, limits| build_plan(shape, sources, page, theme, limits)

		## The authoring-aware entry: a document with tables resolves its
		## column widths once from measured cell widths, then lays every
		## cell out at its text width through the logical batch; any other
		## document takes `build` exactly.
		build_authoring : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_authoring = |authoring, shape, sources, page, theme, limits| if authoring.tables.is_empty() build_plan(shape, sources, page, theme, limits) else build_table_plan(authoring, shape, sources, page, theme, limits)

		geometry : Plan -> [NoTables, WithTables(KernelFacadeTables.Plan)]
		geometry = |plan| plan.geometry

		## The logical path: one line-layout request per logical run,
		## measured across its adjacent physical face or occurrence runs.
		build_ordered : KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_ordered = |shape, sources, page, theme, limits| build_ordered_plan(shape, sources, page, theme, limits, [])

		build_ordered_authoring : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build_ordered_authoring = |authoring, shape, sources, page, theme, limits| if authoring.tables.is_empty() build_ordered_plan(shape, sources, page, theme, limits, []) else build_table_plan(authoring, shape, sources, page, theme, limits)

		blocks : Plan -> List(BlockLines)
		blocks = |plan| plan.blocks

		line : Plan -> KernelLineLayout.BatchPlan
		line = |plan| plan.line

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, KernelFacadeLines.Limits -> Try(KernelFacadeLines.Plan, KernelFacadeLines.Error)
build_plan = |shape, sources, page, theme, limits| {
	block_runs = KernelFacadeShape.Plan.block_runs(shape)

	## A rich paragraph's logical run spans several physical runs; the
	## logical batch measures such ranges. Documents whose runs are all
	## single keep the exact one-run batch.
	if has_multi_run(block_runs) {
		return build_ordered_plan(shape, sources, page, theme, limits, [])
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
	default_request = { source: list_at(shape_requests, 0).source, width: Layout.Unit.from_raw(content_width.to_i64_wrap()) }
	var $line_requests = List.repeat(default_request, run_count)
	var $next_run = 0
	var $block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			ArtifactBlock(artifact) => return Err(ArtifactBlock({ artifact, block: $block_index }))
			TextBlock({ body, label, level }) => {
				geometry = block_geometry(level, label, indent, content_width)?
				match label {
					NoLabel => {}
					Label(label_run) => {
						label_index = single_run_index(label_run, $block_index)?
						if label_index != $next_run or label_index >= run_count {
							return Err(InvalidRun({ block: $block_index, run: label_index }))
						}
						check_label_width(shape_batch.store, label_run, indent, $block_index)?
						$line_requests = list_set($line_requests, label_index, { source: list_at(shape_requests, label_index).source, width: Layout.Unit.from_raw(indent.to_i64_wrap()) })
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
			ArtifactBlock(artifact) => return Err(ArtifactBlock({ artifact, block: $block_index }))
			TextBlock({ body, label, level }) => {
				geometry = block_geometry(level, label, indent, content_width)?
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
	plan = build_ordered_plan(shape, sources, page, theme, limits, $widths)?
	Ok({ ..plan, geometry: WithTables(tables) })
}

## `widths` is empty, or holds one text width per block where a nonzero
## entry (a table cell's) replaces the block's flow width.
build_ordered_plan : KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, KernelFacadeLines.Limits, List(U64) -> Try(KernelFacadeLines.Plan, KernelFacadeLines.Error)
build_ordered_plan = |shape, sources, page, theme, limits, widths| {
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
	var $line_requests = []
	var $logical_index_of_body = List.repeat(0, block_runs.len())
	var $logical_index_of_label = List.repeat(0, block_runs.len())
	var $next_physical = 0
	var $block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			ArtifactBlock(artifact) => return Err(ArtifactBlock({ artifact, block: $block_index }))
			TextBlock({ body, label, level }) => {
				geometry = block_geometry(level, label, indent, content_width)?
				label_request = match label {
					NoLabel => NoLabel
					Label(label_run) => {
						start = logical_run_bounds(label_run, $block_index, $next_physical, run_count)?
						check_label_width(shape_batch.store, label_run, indent, $block_index)?
						$logical_index_of_label = list_set($logical_index_of_label, $block_index, $line_requests.len())
						$next_physical = checked_add(start, label_run.physical.length())?
						Label({
							runs: label_run.physical,
							source: list_at(shape_requests, start).source,
							width: Layout.Unit.from_raw(indent.to_i64_wrap()),
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
		}
		$block_index = $block_index + 1
	}
	if $next_physical != run_count {
		return Err(RunCoverage({ actual: $next_physical, expected: run_count }))
	}
	line = KernelLineLayout.BatchPlan.build_logical(sources, shape_batch.store, $line_requests, limits.line) ? LineLayout
	run_lines = KernelLineLayout.BatchPlan.run_lines(line)
	var $blocks = List.with_capacity(block_runs.len())
	$block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			ArtifactBlock(artifact) => return Err(ArtifactBlock({ artifact, block: $block_index }))
			TextBlock({ body, label, level }) => {
				geometry = block_geometry(level, label, indent, content_width)?
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
			ArtifactBlock(_) => False
		}
		$index = $index + 1
	}
	$found
}

## A block's horizontal geometry: level `L` indents the body by `L` list
## indents and paints a label in the indent before it. A body left with no
## width is invalid geometry.
block_geometry : U64, [Label(KernelFacadeShape.LogicalRun), NoLabel], U64, U64 -> Try({ body_offset : U64, body_width : U64, label_offset : U64 }, KernelFacadeLines.Error)
block_geometry = |level, label, indent, content_width| {
	body_offset = checked_mul(level, indent)?
	if body_offset >= content_width {
		return Err(InvalidGeometry)
	}
	match label {
		Label(_) => if level == 0 Err(InvalidGeometry) else Ok({ body_offset, body_width: content_width - body_offset, label_offset: body_offset - indent })
		NoLabel => Ok({ body_offset, body_width: content_width - body_offset, label_offset: 0 })
	}
}

## A generated label must fit its indent: it has no break opportunity, and
## it is never shrunk or allowed to overlap the body.
check_label_width : Text.Store, KernelFacadeShape.LogicalRun, U64, U64 -> Try({}, KernelFacadeLines.Error)
check_label_width = |store, label, indent, block| {
	var $width = 0
	var $run = label.physical.start()
	while $run < label.physical.start() + label.physical.length() {
		record = list_at(store.runs, $run)
		var $glyph = record.glyphs.start()
		while $glyph < record.glyphs.start() + record.glyphs.length() {
			advance = list_at(store.glyphs, $glyph).advance_x.raw()
			$width = if advance > 0 checked_add($width, advance.to_u64_wrap())? else $width
			$glyph = $glyph + 1
		}
		$run = $run + 1
	}
	if $width > indent Err(LabelTooWide({ available: indent, block, width: $width })) else Ok({})
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
