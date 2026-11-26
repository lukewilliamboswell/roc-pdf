import KernelColumnLayout
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelLineLayout
import Layout
import Semantics
import Text

KernelFacadeColumns :: [].{
	Block : { keep : [KeepTogether, Split], runs : Semantics.IndexRange, source : Semantics.TextSourceId }

	Limits : { candidates : U64, page_count : U64, pieces : U64, line : KernelLineLayout.Limits }

	Work : { blocks : U64, candidate_visits : U64, frame_advances : U64, lines : U64, run_visits : U64 }

	Error : [
		Column(KernelColumnLayout.Error),
		ColumnAt({ block : U64, error : KernelColumnLayout.Error }),
		KeepTooTall({ block : U64 }),
		InvalidBlock({ block : U64 }),
		LineAt({ block : U64, error : KernelLineLayout.Error }),
		PieceLimit({ limit : U64 }),
		WorkLimit({ limit : U64 }),
	]

	## The columns consume source-relative logical runs and final shape data.
	## Measurement, source cuts, and physical origins are explicit before the
	## ordinary text and semantic fragment builders consume the positions.
	position : List(Block), KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Rect, KernelColumnLayout.Widths, Layout.Unit, Limits -> Try({ positioned : KernelFacadeText.Positioned, work : Work }, Error)
	position = |blocks, shape, sources, body, widths, gap, limits| position_columns(blocks, shape, sources, body, widths, gap, limits)
}

position_columns : List(KernelFacadeColumns.Block), KernelFacadeShape.Plan, List(KernelFacadeSources.Source), Layout.Rect, KernelColumnLayout.Widths, Layout.Unit, KernelFacadeColumns.Limits -> Try({ positioned : KernelFacadeText.Positioned, work : KernelFacadeColumns.Work }, KernelFacadeColumns.Error)
position_columns = |blocks, shape, sources, body, widths, gap, limits| {
	store = KernelFacadeShape.Plan.shape(shape).store
	styles = KernelFacadeShape.Plan.styles(shape)
	start = KernelColumnLayout.Cursor.start(body, widths, limits.page_count) ? Column
	var $frame = start
	var $lines = []
	var $pieces = []
	var $candidate_visits = 0
	var $frame_advances = 0
	var $run_visits = 0
	var $block_index = 0
	for block in blocks {
		physical_end = block.runs.start() + block.runs.length()
		if block.runs.length() == 0 or physical_end > store.runs.len() or physical_end > styles.len() or block.source.index() >= sources.len() {
			return Err(InvalidBlock({ block: $block_index }))
		}
		first = list_at(store.runs, block.runs.start())
		leading = list_at(styles, block.runs.start()).leading
		if first.size.raw() <= 0 or leading.raw() < first.size.raw() {
			return Err(InvalidBlock({ block: $block_index }))
		}
		if leading.raw() > body.size.height.raw() {
			return Err(ColumnAt({ block: $block_index, error: LineTooTall({ available: body.size.height.raw(), required: leading.raw() }) }))
		}
		source = list_at(sources, block.source.index())
		line_error = |error| LineAt({ block: $block_index, error })
		column_error = |error| ColumnAt({ block: $block_index, error })
		var $text = KernelLineLayout.LineCursor.start(source.analysis, store, block.runs, limits.line) ? line_error
		var $run = block.runs.start()
		var $whole_advances = 0
		while !$text.is_complete() {
			box = $frame.frame()
			capacity = (box.available.raw() // leading.raw()).to_u64_wrap()
			choice = choose_fragment($text, $frame, capacity, leading, body.size.height, block.keep, $block_index)?
			$candidate_visits = charge($candidate_visits, choice.visits, limits.candidates)?
			if choice.lines == 0 {
				$whole_advances = $whole_advances + 1
				# There are only two distinct full frames. A third refusal
				# revisits the size of one already tested on this page or next.
				if block.keep == KeepTogether and $whole_advances >= 3 {
					return Err(KeepTooTall({ block: $block_index }))
				}
				$frame = $frame.advance_frame() ? column_error
				$frame_advances = $frame_advances + 1
			} else {
				var $emitted = 0
				while $emitted < choice.lines {
					if $lines.len() >= limits.pieces {
						return Err(PieceLimit({ limit: limits.pieces }))
					}
					step = select_line($text, box.width) ? line_error
					$candidate_visits = charge($candidate_visits, step.remaining.work().candidate_visits - $text.work().candidate_visits, limits.candidates)?
					$text = step.remaining
					placed = $frame.place_line({ baseline: first.size, leading }) ? column_error
					$frame = placed.next
					line = step.line
					while cluster_end(list_at(store.runs, $run)) <= line.clusters.start() {
						$run = $run + 1
						$run_visits = $run_visits + 1
					}
					var $end = $run + 1
					while $end < physical_end and list_at(store.runs, $end).clusters.start() < line.clusters.start() + line.clusters.length() {
						$end = $end + 1
					}
					$run_visits = $run_visits + $end - $run
					$pieces = $pieces.append({
						artifact: False,
						line: $lines.len(),
						origin: placed.baseline,
						page: box.page,
						source_runs: { physical: Semantics.IndexRange.from_start_and_length({ start: $run, length: $end - $run }) },
					})
					$lines = $lines.append(line)
					$emitted = $emitted + 1
				}
				if !$text.is_complete() {
					$frame = $frame.advance_frame() ? column_error
					$frame_advances = $frame_advances + 1
				}
			}
		}
		$frame = $frame.space_after(gap) ? column_error
		$block_index = $block_index + 1
	}
	pages = $frame.frame().page.index() + 1
	count = $pieces.len()
	Ok({
		positioned: { shape: store, styles, lines: $lines, origins: KernelFacadeShape.Plan.origins(shape), pages, pieces: $pieces },
		work: { blocks: blocks.len(), candidate_visits: $candidate_visits, frame_advances: $frame_advances, lines: count, run_visits: $run_visits },
	})
}

Choice : { lines : U64, visits : U64 }

Scan : { after : KernelLineLayout.LineCursor, before_last : KernelLineLayout.LineCursor, lines : U64, visits : U64 }

## Latest legal cut. When a two-line beginning would fit a fresh column,
## prefer it to one line in a partially occupied column. A lone final line
## is avoided by moving one line forward when that leaves a legal earlier
## fragment and two lines at the actual next column width.
choose_fragment : KernelLineLayout.LineCursor, KernelColumnLayout.Cursor, U64, Layout.Unit, Layout.Unit, [KeepTogether, Split], U64 -> Try(Choice, KernelFacadeColumns.Error)
choose_fragment = |text, frame, capacity, leading, full_height, keep, block| {
	if capacity == 0 {
		return Ok({ lines: 0, visits: 0 })
	}
	box = frame.frame()
	line_error = |error| LineAt({ block, error })
	cut = scan_lines(text, box.width, capacity) ? line_error
	if cut.after.is_complete() {
		return Ok({ lines: cut.lines, visits: cut.visits })
	}
	if keep == KeepTogether {
		return Ok({ lines: 0, visits: cut.visits })
	}
	if cut.lines == 1 and box.available.raw() < full_height.raw() and full_height.raw() // leading.raw() >= 2 and text.work().line_writes == 0 {
		return Ok({ lines: 0, visits: cut.visits })
	}
	minimum = if (text.work().line_writes == 0) 2 else 1
	if cut.lines <= minimum {
		return Ok({ lines: cut.lines, visits: cut.visits })
	}
	next = frame.advance_frame() ? |error| ColumnAt({ block, error })
	next_width = next.frame().width
	last = scan_lines(cut.after, next_width, 1) ? line_error
	if !last.after.is_complete() {
		return Ok({ lines: cut.lines, visits: cut.visits + last.visits })
	}
	moved = scan_lines(cut.before_last, next_width, 1) ? line_error
	Ok({
		lines: if (moved.after.is_complete()) cut.lines else cut.lines - 1,
		visits: cut.visits + last.visits + moved.visits,
	})
}

scan_lines : KernelLineLayout.LineCursor, Layout.Unit, U64 -> Try(Scan, KernelLineLayout.Error)
scan_lines = |text, width, capacity| {
	var $before_last = text
	var $after = text
	var $lines = 0
	while $lines < capacity and !$after.is_complete() {
		$before_last = $after
		step = select_line($after, width)?
		$after = step.remaining
		$lines = $lines + 1
	}
	Ok({ after: $after, before_last: $before_last, lines: $lines, visits: $after.work().candidate_visits - text.work().candidate_visits })
}

select_line : KernelLineLayout.LineCursor, Layout.Unit -> Try({ line : KernelLineLayout.Line, remaining : KernelLineLayout.LineCursor }, KernelLineLayout.Error)
select_line = |text, width| match text.next(width)? {
	Line(step) => Ok(step)
	Complete => Err(InvalidAnalysis)
}

charge : U64, U64, U64 -> Try(U64, KernelFacadeColumns.Error)
charge = |used, extra, maximum| {
	if extra > maximum - used {
		Err(WorkLimit({ limit: maximum }))
	} else {
		Ok(used + extra)
	}
}

cluster_end : Text.Run -> U64
cluster_end = |run| run.clusters.start() + run.clusters.length()

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated column layout index"
}
