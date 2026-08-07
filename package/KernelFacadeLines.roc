import KernelFacadeShape
import KernelFacadeSources
import KernelLineLayout
import Layout
import Semantics
import Theme

KernelFacadeLines :: [].{
	Dimension : [Blocks, Runs]
	Error : [
		ArithmeticOverflow,
		ArtifactBlock({ block : U64, artifact : U64 }),
		InvalidGeometry,
		InvalidRun({ block : U64, run : U64 }),
		LineLayout(KernelLineLayout.Error),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		RunCoverage({ actual : U64, expected : U64 }),
	]
	Limits :: { line : KernelLineLayout.BatchLimits, max_blocks : U64, max_runs : U64 }.{
		make : { line : KernelLineLayout.BatchLimits, max_blocks : U64, max_runs : U64 } -> Limits
		make = |limits| Limits.(limits)
	}
	BlockLines : [TextBlock({ body : Semantics.Range, label : [Label(Semantics.Range), NoLabel] })]
	Work : {
		block_mapping_visits : U64,
		blocks : U64,
		content_width : U64,
		line : KernelLineLayout.BatchWork,
		run_writes : U64,
	}
	Plan :: { blocks : List(BlockLines), line : KernelLineLayout.BatchPlan, work : Work }.{
		build : KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Size, Theme, Limits -> Try(Plan, Error)
		build = |shape, sources, page, theme, limits| build_plan(shape, sources, page, theme, limits)

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
	body_width = content_width - indent
	default_request = { source: list_at(shape_requests, 0).source, width: Layout.Unit.from_raw(content_width.to_i64_wrap()) }
	var $line_requests = List.repeat(default_request, run_count)
	var $next_run = 0
	var $block_index = 0
	while $block_index < block_runs.len() {
		match list_at(block_runs, $block_index) {
			ArtifactBlock(artifact) => return Err(ArtifactBlock({ artifact, block: $block_index }))
			TextBlock({ body, label }) => {
				match label {
					NoLabel => {}
					Label(label_run) => {
						label_index = label_run.index()
						if label_index != $next_run or label_index >= run_count {
							return Err(InvalidRun({ block: $block_index, run: label_index }))
						}
						$line_requests = list_set($line_requests, label_index, { source: list_at(shape_requests, label_index).source, width: Layout.Unit.from_raw(indent.to_i64_wrap()) })
						$next_run = checked_add($next_run, 1)?
					}
				}
				body_index = body.index()
				if body_index != $next_run or body_index >= run_count {
					return Err(InvalidRun({ block: $block_index, run: body_index }))
				}
				width = match label {
					NoLabel => content_width
					Label(_) => body_width
				}
				$line_requests = list_set($line_requests, body_index, { source: list_at(shape_requests, body_index).source, width: Layout.Unit.from_raw(width.to_i64_wrap()) })
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
			TextBlock({ body, label }) => {
				body_lines = list_at(run_lines, body.index())
				label_lines = match label {
					NoLabel => NoLabel
					Label(label_run) => Label(list_at(run_lines, label_run.index()))
				}
				$blocks = $blocks.append(TextBlock({ body: body_lines, label: label_lines }))
			}
		}
		$block_index = $block_index + 1
	}
	Ok(
		KernelFacadeLines.Plan.{
			blocks: $blocks,
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

expect match calculate_content_width(
	{ height: Layout.Unit.from_raw(0), width: Layout.Unit.from_raw(1000) },
	{ bottom: Layout.Unit.from_raw(0), left: Layout.Unit.from_raw(0), right: Layout.Unit.from_raw(0), top: Layout.Unit.from_raw(0) },
) {
	Err(InvalidGeometry) => True
	_ => False
}
