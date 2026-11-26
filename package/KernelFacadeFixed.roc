import Document
import KernelFacadeLines
import KernelFacadeShape
import KernelFacadeText
import KernelLineLayout
import KernelSpan
import Layout
import Semantics
import Text

KernelFacadeFixed :: [].{
	Limits : { max_pieces : U64 }

	Error : [
		InvalidPlan,
		InvalidTextStyle({ page : U64, placement : U64 }),
		LineTooWide({ page : U64, placement : U64, actual : Layout.Unit, maximum : Layout.Unit }),
		LineBoxesTooTall({ page : U64, placement : U64, actual : U64, maximum : U64 }),
		PieceLimit({ attempted : U64, limit : U64 }),
	]

	Work : { placements : U64, line_visits : U64, run_visits : U64, piece_writes : U64 }

	## Check every frame in authored order before emitting any positioned
	## pieces. Then walk pages in page order and each page's paint permutation.
	position : Document.NormalizedFixed, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Limits -> Try({ positioned : KernelFacadeText.Positioned, work : Work }, Error)
	position = |fixed, shape, line_plan, limits| {
		view = fixed.view()
		block_lines = KernelFacadeLines.Plan.blocks(line_plan)
		lines = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(line_plan))
		store = KernelFacadeShape.Plan.shape(shape).store
		styles = KernelFacadeShape.Plan.styles(shape)
		if view.frames.len() != block_lines.len() or styles.len() != store.runs.len() {
			return Err(InvalidPlan)
		}
		if lines.len() > limits.max_pieces {
			return Err(PieceLimit({ attempted: lines.len(), limit: limits.max_pieces }))
		}
		var $fits = List.with_capacity(block_lines.len())
		var $run_visits = 0
		var $line_visits = 0
		var $page_index = 0
		for page in view.pages {
			var $placement = 0
			while $placement < page.placements.length() {
				block = page.placements.start() + $placement
				result = fit_block(list_at(block_lines, block), list_at(view.frames, block), { page: $page_index, placement: $placement }, { lines, runs: store.runs, styles })?
				$fits = $fits.append(result)
				$line_visits = $line_visits + result.lines.length()
				$run_visits = $run_visits + result.runs.length()
				$placement = $placement + 1
			}
			$page_index = $page_index + 1
		}
		var $pieces = List.with_capacity(lines.len())
		$page_index = 0
		for page in view.pages {
			var $slot = 0
			while $slot < page.paint.length() {
				block = list_at(view.paint_order, page.paint.start() + $slot)
				fit = list_at($fits, block)
				frame = list_at(view.frames, block)
				run_end = fit.runs.start() + fit.runs.length()
				var $first = fit.runs.start()
				var $row = 0
				while $row < fit.lines.length() {
					line_index = fit.lines.start() + $row
					line_clusters = list_at(lines, line_index).clusters
					# The cursor advances over the block's physical shape
					# runs once. Only runs touching this line go downstream.
					while cluster_end(list_at(store.runs, $first)) <= line_clusters.start() {
						$first = $first + 1
						$run_visits = $run_visits + 1
					}
					var $end = $first + 1
					while $end < run_end and list_at(store.runs, $end).clusters.start() < line_clusters.start() + line_clusters.length() {
						$end = $end + 1
						$run_visits = $run_visits + 1
					}
					$run_visits = $run_visits + 1
					y = frame.origin.y.raw() + frame.size.height.raw() - (fit.size + $row * fit.leading).to_i64_wrap()
					$pieces = $pieces.append({
						artifact: False,
						line: line_index,
						origin: { x: frame.origin.x, y: Layout.Unit.from_raw(y) },
						page: Semantics.PageId.from_index($page_index),
						source_runs: { physical: Semantics.IndexRange.from_start_and_length({ start: $first, length: $end - $first }) },
					})
					$row = $row + 1
				}
				$slot = $slot + 1
			}
			$page_index = $page_index + 1
		}
		piece_writes = $pieces.len()
		Ok({
			positioned: { shape: store, styles, lines, origins: KernelFacadeShape.Plan.origins(shape), pages: view.pages.len(), pieces: $pieces },
			work: { placements: view.frames.len(), line_visits: $line_visits, run_visits: $run_visits, piece_writes },
		})
	}
}

Fit : { leading : U64, lines : Semantics.IndexRange, runs : Semantics.IndexRange, size : U64 }

fit_block : KernelFacadeLines.BlockLines, Layout.Rect, { page : U64, placement : U64 }, { lines : List(KernelLineLayout.Line), runs : List(Text.Run), styles : List(KernelFacadeShape.RunStyle) } -> Try(Fit, KernelFacadeFixed.Error)
fit_block = |block, frame, at, shaped| match block {
	TextBlock({ body: { lines, runs: { physical } }, label: NoLabel, .. }) => {
		line_end = KernelSpan.end_within(lines.start(), lines.length(), shaped.lines.len()) ? |_| InvalidPlan
		physical_end = KernelSpan.end_within(physical.start(), physical.length(), shaped.runs.len()) ? |_| InvalidPlan
		if lines.length() == 0 or physical.length() == 0 {
			return Err(InvalidPlan)
		}
		leading_raw = list_at(shaped.styles, physical.start()).leading.raw()
		if leading_raw <= 0 {
			return Err(InvalidPlan)
		}
		leading = leading_raw.to_u64_wrap()
		var $size = 0
		var $run = physical.start()
		while $run < physical_end {
			raw = list_at(shaped.runs, $run).size.raw()
			if raw <= 0 or list_at(shaped.styles, $run).leading.raw() != leading_raw {
				return Err(InvalidPlan)
			}
			if raw > leading_raw {
				return Err(InvalidTextStyle(at))
			}
			$size = U64.max($size, raw.to_u64_wrap())
			$run = $run + 1
		}
		maximum = frame.size.height.raw().to_u64_wrap()
		if lines.length() > maximum // leading {
			actual = if (lines.length() > U64.highest // leading) U64.highest else lines.length() * leading
			return Err(LineBoxesTooTall({ page: at.page, placement: at.placement, actual, maximum }))
		}
		first_cluster = list_at(shaped.runs, physical.start()).clusters.start()
		last_cluster = cluster_end(list_at(shaped.runs, physical_end - 1))
		var $line = lines.start()
		while $line < line_end {
			line = list_at(shaped.lines, $line)
			advance = line.advance.raw()
			if advance < 0 or line.clusters.length() == 0 or line.clusters.start() < first_cluster or !KernelSpan.end_within(line.clusters.start(), line.clusters.length(), last_cluster).is_ok() {
				return Err(InvalidPlan)
			}
			if advance > frame.size.width.raw() {
				return Err(LineTooWide({ page: at.page, placement: at.placement, actual: line.advance, maximum: frame.size.width }))
			}
			$line = $line + 1
		}
		Ok({ leading, lines, runs: physical, size: $size })
	}
	_ => Err(InvalidPlan)
}

cluster_end : Text.Run -> U64
cluster_end = |run| run.clusters.start() + run.clusters.length()

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated fixed-page index"
}
