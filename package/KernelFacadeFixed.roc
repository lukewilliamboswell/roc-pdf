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
		FigureTooLarge({ page : U64, placement : U64, height : U64, width : U64, frame_height : U64, frame_width : U64 }),
		PieceLimit({ attempted : U64, limit : U64 }),
	]

	Work : { placements : U64, line_visits : U64, run_visits : U64, piece_writes : U64 }

	## The drawing's synthetic space identifies its semantic occurrence.
	## Its nominal advance does not consume the authored drawing width.
	line_frames : Document.NormalizedFixed -> List(Layout.Rect)
	line_frames = |fixed| {
		view = fixed.view()
		if view.authoring.figures.is_empty() {
			return view.frames
		}
		view.frames.map_with_index(
			|frame, block| match list_at(view.authoring.blocks, block).kind {
				Figure(_) => anchor_frame(frame)
				_ => frame
			},
		)
	}

	## Check every frame in authored order before emitting any positioned
	## pieces. Then walk pages in page order and each page's paint permutation.
	position : Document.NormalizedFixed, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Unit, Limits -> Try({ positioned : KernelFacadeText.Positioned, work : Work }, Error)
	position = |fixed, shape, line_plan, gap, limits| {
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
				ordinal = page.placements.start() + $placement
				blocks = Document.NormalizedFixed.blocks_for(view.placement_blocks, ordinal)
				block = blocks.start()
				at = { page: $page_index, placement: $placement }
				shaped = { lines, runs: store.runs, styles }
				line_block = list_at(block_lines, block)
				frame = list_at(view.frames, block)
				match list_at(view.authoring.blocks, block).kind {
					Figure(index) => {
						figure = list_at(view.authoring.figures, index)
						caption = if (blocks.length() == 2) Caption(list_at(block_lines, block + 1)) else NoCaption
						fit = fit_figure(line_block, figure.drawing, caption, frame, gap, at, shaped)?
						$fits = $fits.append(fit.anchor)
						$line_visits = $line_visits + fit.anchor.lines.length()
						$run_visits = $run_visits + fit.anchor.runs.length()
						match fit.caption {
							Caption(placed) => {
								$fits = $fits.append(placed)
								$line_visits = $line_visits + placed.lines.length()
								$run_visits = $run_visits + placed.runs.length()
							}
							NoCaption => {}
						}
					}
					_ => {
						result = fit_block(line_block, frame, at, shaped)?
						$fits = $fits.append(result)
						$line_visits = $line_visits + result.lines.length()
						$run_visits = $run_visits + result.runs.length()
					}
				}
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
			work: { placements: if (view.placement_blocks.is_empty()) view.frames.len() else view.placement_blocks.len(), line_visits: $line_visits, run_visits: $run_visits, piece_writes },
		})
	}
}

Fit : { leading : U64, lines : Semantics.IndexRange, runs : Semantics.IndexRange, size : U64 }

Shaped : { lines : List(KernelLineLayout.Line), runs : List(Text.Run), styles : List(KernelFacadeShape.RunStyle) }

anchor_frame : Layout.Rect -> Layout.Rect
anchor_frame = |frame| { ..frame, size: { width: 14400, height: 14400 } }

## Paint a figure at full scale, top-aligned in its frame. Its drawing
## anchor's baseline is the drawing bottom. The caption gets the
## remainder of the same frame, after the theme's paragraph gap.
fit_figure : KernelFacadeLines.BlockLines, Document.ValidatedDrawing, [Caption(KernelFacadeLines.BlockLines), NoCaption], Layout.Rect, Layout.Unit, { page : U64, placement : U64 }, Shaped -> Try({ anchor : Fit, caption : [Caption(Fit), NoCaption] }, KernelFacadeFixed.Error)
fit_figure = |anchor, validated, caption, frame, gap, at, shaped| {
	drawing = match validated {
		ValidDrawing(value) => value
		DrawingDepthLimit(_) | InvalidDrawing(_) | InvalidDrawingPath(_) | InvalidImageStride(_) => return Err(InvalidPlan)
	}
	frame_width = frame.size.width.raw().to_u64_wrap()
	frame_height = frame.size.height.raw().to_u64_wrap()
	if gap.raw() < 0 {
		return Err(InvalidPlan)
	}
	oversize = |height| FigureTooLarge({ page: at.page, placement: at.placement, height, width: drawing.width, frame_height, frame_width })
	if drawing.width > frame_width or drawing.height > frame_height {
		return Err(oversize(drawing.height))
	}
	fit = fit_block(anchor, anchor_frame(frame), at, shaped)?
	if fit.lines.length() != 1 {
		return Err(InvalidPlan)
	}
	placed_anchor = { ..fit, size: drawing.height }
	match caption {
		NoCaption => Ok({ anchor: placed_anchor, caption: NoCaption })
		Caption(block) => {
			above = drawing.height + gap.raw().to_u64_wrap()
			if above >= frame_height {
				return Err(oversize(above))
			}
			caption_frame = { ..frame, size: { ..frame.size, height: Layout.Unit.from_raw((frame_height - above).to_i64_wrap()) } }
			placed = match fit_block(block, caption_frame, at, shaped) {
				Ok(value) => value
				Err(LineBoxesTooTall({ actual, .. })) => return Err(oversize(if (actual > U64.highest - above) U64.highest else above + actual))
				Err(error) => return Err(error)
			}
			Ok({ anchor: placed_anchor, caption: Caption({ ..placed, size: above + placed.size }) })
		}
	}
}

fit_block : KernelFacadeLines.BlockLines, Layout.Rect, { page : U64, placement : U64 }, Shaped -> Try(Fit, KernelFacadeFixed.Error)
fit_block = |block, frame, at, shaped| match block {
	TextBlock({ body: { lines, runs: { physical } }, label: NoLabel, .. }) => {
		line_end = KernelSpan.end_within(lines.start(), lines.length(), shaped.lines.len()) ? |_| InvalidPlan
		physical_end = KernelSpan.end_within(physical.start(), physical.length(), shaped.runs.len()) ? |_| InvalidPlan
		if lines.length() == 0 or physical.length() == 0 {
			return Err(InvalidPlan)
		}
		leading_raw = list_at(shaped.styles, physical.start()).leading.raw()
		if leading_raw <= 0 {
			return Err(InvalidTextStyle(at))
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
