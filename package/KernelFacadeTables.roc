import Document
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeTableGrid
import KernelLineLayout
import KernelShape
import Layout
import Semantics
import Text
import Theme

## Table geometry for the facade: per-cell width facts measured once from
## the shaped store, then the declared column-width algorithm, resolved once
## per table before line layout. Its outputs are exact millipoint facts that
## later stages consume; nothing downstream remeasures a cell or infers a
## column from positioned text.
KernelFacadeTables :: [].{
	Error : [
		ArithmeticOverflow,
		InvalidCell({ block : U64 }),
		Measure(KernelLineLayout.Error),

		## An authored fixed column width is zero or negative.
		TableFixedWidth({ column : U64, group : U64 }),

		## Fixed widths plus every column's minimum exceed the available width.
		TableWidth({ available : U64, group : U64, required : U128 }),

		## A cell's widest unbreakable piece (`token`, a scalar range of the
		## cell text's `source` segment) is wider than the width its columns
		## receive.
		UnbreakableToken({ available : U64, block : U64, token : Semantics.IndexRange, width : U64 }),
		UnbreakableItems({ available : U64, block : U64, items : Semantics.IndexRange, width : U64 }),
	]

	WidthToken : [Scalars(Semantics.IndexRange), Items(Semantics.IndexRange)]
	MeasuredWidth : { max_content : U64, min_content : U64, token : WidthToken }

	## One cell's resolved geometry: its text box starts `x` from the flow
	## edge and is `width` wide (its spanned columns less the cell padding
	## on both sides), and its lines align within it.
	CellGeometry : { offset : U64, align : Document.ColumnAlign, block : U64, width : U64, x : U64 }

	## One table's resolved column widths (left to right) and total width.
	TableGeometry : { offset : U64, columns : List(U64), group : U64, width : U64 }

	Work : {
		cell_measurements : U64,
		column_width_passes : U64,
		measurement_cache_hits : U64,
		row_visits : U64,
	}

	## `cells` is indexed by cell ordinal (the normalized `cells` arena);
	## `tables` by table index.
	Plan :: { cells : List(CellGeometry), table_grids : List(KernelFacadeTableGrid.Grid), sources : List(KernelFacadeSources.Source), tables : List(TableGeometry), work : Work }.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), U64, Theme, KernelLineLayout.Limits -> Try(Plan, Error)
		build = |authoring, shape, input_sources, available, theme, limits| build_plan(authoring, shape, input_sources, available, [], theme, limits, [])

		build_framed : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), U64, List({ offset : U64, width : U64 }), Theme, KernelLineLayout.Limits, List(KernelFacadeTableGrid.Grid) -> Try(Plan, Error)
		build_framed = |authoring, shape, input_sources, available, frames, theme, limits, verified_grids| build_plan(authoring, shape, input_sources, available, frames, theme, limits, verified_grids)

		## Resolve the same column algorithm from source-free intrinsic
		## widths. Item-token diagnostics retain their explicit domain.
		build_measured : Document.NormalizedAuthoring, List(KernelFacadeSources.Source), List(MeasuredWidth), U64, List({ offset : U64, width : U64 }), Theme, List(KernelFacadeTableGrid.Grid) -> Try(Plan, Error)
		build_measured = |authoring, input_sources, measures, available, frames, theme, verified_grids| {
			if measures.len() != authoring.cells.len() {
				return Err(InvalidCell({ block: 0 }))
			}
			resolve_geometry(authoring, input_sources, measures, available, frames, theme, measures.len(), 0, verified_grids)
		}

		grids : Plan -> List(KernelFacadeTableGrid.Grid)
		grids = |plan| plan.table_grids

		cells : Plan -> List(CellGeometry)
		cells = |plan| plan.cells

		tables : Plan -> List(TableGeometry)
		tables = |plan| plan.tables

		## The interned sources the cells were measured from, for aligning
		## lines by their visible advance.
		sources : Plan -> List(KernelFacadeSources.Source)
		sources = |plan| plan.sources

		work : Plan -> Work
		work = |plan| plan.work
	}
}

## A cell's width facts: its widest line and widest unbreakable piece
## (with that piece's source-relative scalar range), over every explicit
## line-break segment of its text.
CellMeasure : KernelFacadeTables.MeasuredWidth

## Measurements are cached per interned source: a source's physical split
## and size are fixed for the document, so identical cell texts measure once.
CacheSlot : [Measured({ measure : CellMeasure, size : I64 }), Unmeasured]

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), U64, List({ offset : U64, width : U64 }), Theme, KernelLineLayout.Limits, List(KernelFacadeTableGrid.Grid) -> Try(KernelFacadeTables.Plan, KernelFacadeTables.Error)
build_plan = |authoring, shape, sources, available, frames, theme, limits, grids| {
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	styles = KernelFacadeShape.Plan.styles(shape)
	requests = KernelFacadeShape.Plan.requests(shape)
	store = KernelFacadeShape.Plan.shape(shape).store
	simple_sources = sources.map(|source| { analysis: source.analysis, unicode: source.unicode })
	var $cache = List.repeat(Unmeasured, sources.len())
	var $measures = List.with_capacity(authoring.cells.len())
	var $cache_hits = 0
	var $measurements = 0
	var $ordinal = 0
	while $ordinal < authoring.cells.len() {
		record = list_at(authoring.cells, $ordinal)

		## A contentless cell has no run, so its widths are zero and it
		## never widens a column.
		physical = match list_at(block_runs, record.block) {
			TextBlock({ body, label: _, level: _ }) => body.physical
			EmptySourceLine(_) => return Err(InvalidCell({ block: record.block }))
			ContentlessCell => Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 })
		}
		var $cell = { max_content: 0, min_content: 0, token: Scalars(Semantics.IndexRange.from_start_and_length({ start: 0, length: 0 })) }
		code = KernelFacadeShape.Plan.code_holds(shape, authoring, record.block, sources)
		var $segment = physical.start()
		end = physical.start() + physical.length()
		while $segment < end {
			length = segment_length(styles, $segment, end)
			source = list_at(requests, $segment).source
			size = list_at(store.runs, $segment).size.raw()
			held = segment_holds(code, $segment, $segment + length)

			## A segment whose code span holds words together measures on
			## its own: the per-source cache holds untailored widths.
			measured = if !held.is_empty() {
				fresh = measure_segment(simple_sources, store, $segment, length, source, held, limits)?
				$measurements = $measurements + 1
				fresh
			} else match list_at($cache, source.index()) {
				Measured(slot) => if slot.size == size {
					$cache_hits = $cache_hits + 1
					slot.measure
				} else {
					fresh = measure_segment(simple_sources, store, $segment, length, source, [], limits)?
					$measurements = $measurements + 1
					fresh
				}
				Unmeasured => {
					fresh = measure_segment(simple_sources, store, $segment, length, source, [], limits)?
					$measurements = $measurements + 1
					$cache = list_set($cache, source.index(), Measured({ measure: fresh, size }))
					fresh
				}
			}
			$cell = {
				max_content: U64.max($cell.max_content, measured.max_content),
				min_content: U64.max($cell.min_content, measured.min_content),
				token: if (measured.min_content > $cell.min_content) measured.token else $cell.token,
			}
			$segment = $segment + length
		}
		$measures = $measures.append($cell)
		$ordinal = $ordinal + 1
	}

	resolve_geometry(authoring, sources, $measures, available, frames, theme, $measurements, $cache_hits, grids)
}

resolve_geometry : Document.NormalizedAuthoring, List(KernelFacadeSources.Source), List(CellMeasure), U64, List({ offset : U64, width : U64 }), Theme, U64, U64, List(KernelFacadeTableGrid.Grid) -> Try(KernelFacadeTables.Plan, KernelFacadeTables.Error)
resolve_geometry = |authoring, sources, measures, available, frames, theme, measurements, cache_hits, grids| {
	padding = nonnegative(theme.table.cell_padding.raw())?
	var $cells = List.with_capacity(authoring.cells.len())
	var $tables = List.with_capacity(authoring.tables.len())
	var $row_visits = 0
	# Resolve each table's columns once, then every cell's text box.
	var $cell_cursor = 0
	var $group_index = 0
	while $group_index < authoring.groups.len() {
		group = list_at(authoring.groups, $group_index)
		match group.kind {
			Table(table_index) => {
				table = list_at(authoring.tables, table_index.to_u64())
				frame = if (frames.is_empty()) { offset: 0, width: available } else list_at(frames, table_index.to_u64())
				first_cell = $cell_cursor
				cell_end = first_cell + count_cells(authoring, group)
				grid = KernelFacadeTableGrid.for_group(grids, $group_index)
				columns = resolve_columns(authoring, table, group, $group_index, measures, first_cell, cell_end, padding, frame.width, grid)?
				edges = match grid {
					Ordinary => []
					Spanning(_) => column_edges(columns)
				}
				var $row = $group_index + 1
				var $ordinal_cursor = first_cell
				while $row < group.group_end {
					row_group = list_at(authoring.groups, $row)
					var $column = 0
					var $x = 0
					var $block = row_group.first_block
					while $block < row_group.block_end {
						record = list_at(authoring.cells, $ordinal_cursor)
						$column = grid_column(grid, $ordinal_cursor, $column)
						if !edges.is_empty() {
							$x = list_at(edges, $column)
						}
						span = record.column_span.to_u64()
						cell_width = sum_range(columns, $column, span)
						contentless = match list_at(authoring.blocks, $block).kind {
							EmptyCell => True
							_ => False
						}
						if cell_width <= 2 * padding and !contentless {
							return Err(token_error(0, $block, list_at(measures, $ordinal_cursor)))
						}
						text_width = if (cell_width <= 2 * padding) 0 else cell_width - 2 * padding
						measure = list_at(measures, $ordinal_cursor)
						if measure.min_content > text_width {
							return Err(token_error(text_width, $block, measure))
						}
						align = match record.align {
							Aligned(value) => value
							FirstColumn => list_at(table.columns, $column).align
						}
						$cells = $cells.append({ offset: frame.offset, align, block: $block, width: text_width, x: $x + padding })
						$x = $x + cell_width
						$column = $column + span
						$ordinal_cursor = $ordinal_cursor + 1
						$block = $block + 1
					}
					$row_visits = $row_visits + 1
					$row = $row + 1
				}
				$tables = $tables.append({ offset: frame.offset, columns, group: $group_index, width: sum_range(columns, 0, columns.len()) })
				$cell_cursor = cell_end
			}
			_ => {}
		}
		$group_index = $group_index + 1
	}
	Ok(
		KernelFacadeTables.Plan.{
			cells: $cells,
			table_grids: grids,
			sources,
			tables: $tables,
			work: {
				cell_measurements: measurements,
				column_width_passes: $tables.len(),
				measurement_cache_hits: cache_hits,
				row_visits: $row_visits,
			},
		},
	)
}

grid_column : KernelFacadeTableGrid.Selection, U64, U64 -> U64
grid_column = |grid, ordinal, ordinary| match grid {
	Ordinary => ordinary
	Spanning(verified) => list_at(verified.cells, ordinal - verified.first_cell).column
}

column_edges : List(U64) -> List(U64)
column_edges = |columns| {
	var $edges = List.with_capacity(columns.len() + 1).append(0)
	var $edge = 0
	for width in columns {
		$edge = $edge + width
		$edges = $edges.append($edge)
	}
	$edges
}

## The code holds whose run lies in one segment's runs, as line-layout
## holds (their request field is unused by measurement).
segment_holds : List(KernelFacadeShape.CodeHold), U64, U64 -> List(KernelLineLayout.Hold)
segment_holds = |code, start, end| {
	if code.is_empty() {
		return []
	}
	var $held = []
	for hold in code {
		if hold.run >= start and hold.run < end {
			$held = $held.append({ request: 0, scalars: hold.scalars })
		}
	}
	$held
}

## Measure one explicit-line-break segment: its physical runs over one
## whole source, as a logical request.
measure_segment : List(KernelShape.SimpleSource), Text.Store, U64, U64, Semantics.TextSourceId, List(KernelLineLayout.Hold), KernelLineLayout.Limits -> Try(CellMeasure, KernelFacadeTables.Error)
measure_segment = |sources, store, start, length, source, holds, limits| {
	request = { runs: Semantics.IndexRange.from_start_and_length({ start: start, length: length }), source, width: Layout.Unit.from_raw(1) }
	measured = (if (holds.is_empty()) KernelLineLayout.measure_logical(sources, store, request, limits) else KernelLineLayout.measure_logical_held(sources, store, request, holds, limits)) ? Measure
	first = list_at(store.clusters, measured.measure.token.start())
	last = list_at(store.clusters, measured.measure.token.start() + U64.max(measured.measure.token.length(), 1) - 1)
	token_start = first.source.scalars.start()
	token_end = last.source.scalars.start() + last.source.scalars.length()
	Ok({
		max_content: nonnegative(measured.measure.max_content)?,
		min_content: nonnegative(measured.measure.min_content)?,
		token: Scalars(Semantics.IndexRange.from_start_and_length({ start: token_start, length: token_end - token_start })),
	})
}

## The column-width algorithm of `reference-documents`: `Fixed` columns are
## exact; `Content` columns take their max-content width, reduced toward
## their min-content width only as needed, in proportion to each column's
## slack; the remaining width divides among `Share` columns in proportion
## to their weights, a share below its column's minimum being fixed at that
## minimum and the rest redistributed. Millipoint remainders go to columns
## left to right. A column's minimum and maximum are those of its
## single-column cells plus the cell padding on both sides; spanning cells
## are checked against their resolved spans afterwards. A single column
## whose minimum exceeds its fixed width or the available width is
## `UnbreakableToken`; minima that fit alone but not together are
## `TableWidth`.
resolve_columns : Document.NormalizedAuthoring, Document.NormalizedTable, Document.NormalizedGroup, U64, List(CellMeasure), U64, U64, U64, U64, KernelFacadeTableGrid.Selection -> Try(List(U64), KernelFacadeTables.Error)
resolve_columns = |authoring, table, group, group_index, measures, first_cell, cell_end, padding, available, grid| {
	count = table.columns.len()
	padding_width = 2 * padding
	var $minima = List.repeat(0, count)
	var $maxima = List.repeat(0, count)
	var $widest = List.repeat(first_cell, count)
	var $row = group_index + 1
	var $ordinal = first_cell
	while $row < group.group_end {
		row_group = list_at(authoring.groups, $row)
		var $column = 0
		var $block = row_group.first_block
		while $block < row_group.block_end {
			record = list_at(authoring.cells, $ordinal)
			$column = grid_column(grid, $ordinal, $column)
			if record.column_span == 1 {
				measure = list_at(measures, $ordinal)
				minimum = match U64.plus_try(measure.min_content, padding_width) {
					Ok(value) => value
					Err(_) => {
						limit = match list_at(table.columns, $column).width {
							Fixed(unit) => fixed_width(unit, group_index, $column)?
							_ => available
						}
						return Err(token_error(limit.minus_saturated(padding_width), $block, measure))
					}
				}
				if minimum > list_at($minima, $column) {
					$minima = list_set($minima, $column, minimum)
					$widest = list_set($widest, $column, $ordinal)
				}
				$maxima = list_set($maxima, $column, U64.max(list_at($maxima, $column), measure.max_content))
			}
			$column = $column + record.column_span.to_u64()
			$ordinal = $ordinal + 1
			$block = $block + 1
		}
		$row = $row + 1
	}
	if $ordinal != cell_end {
		return Err(InvalidCell({ block: group.first_block }))
	}

	# Exact fixed columns, and each single column's own feasibility.
	var $widths = List.repeat(0, count)
	var $required = 0.U128
	var $column = 0
	while $column < count {
		minimum = list_at($minima, $column)
		limit = match list_at(table.columns, $column).width {
			Fixed(unit) => fixed_width(unit, group_index, $column)?
			_ => available
		}
		if minimum > limit {
			widest = list_at($widest, $column)
			measure = list_at(measures, widest)
			return Err(token_error(limit.minus_saturated(padding_width), list_at(authoring.cells, widest).block, measure))
		}
		match list_at(table.columns, $column).width {
			Fixed(_) => {
				$widths = list_set($widths, $column, limit)
				$required = $required + limit.to_u128()
			}
			_ => {
				$required = $required + minimum.to_u128()
			}
		}
		$column = $column + 1
	}
	if $required > available.to_u128() {
		return Err(TableWidth({ available, group: group_index, required: $required }))
	}

	## Each term is at most U64.highest and the table has at most that many
	## columns, so the wide sums cannot overflow. Padding cancels in slack.
	var $slack_total = 0.U128
	var $share_weight = 0
	$column = 0
	while $column < count {
		match list_at(table.columns, $column).width {
			Content => {
				slack = column_slack($maxima, $minima, $column, padding_width)
				$slack_total = $slack_total + slack.to_u128()
			}
			Share(weight) => {
				$share_weight = U64.plus_try($share_weight, weight.to_u64()) ? |_| ArithmeticOverflow
			}
			Fixed(_) => {}
		}
		$column = $column + 1
	}

	## Compute retained slack directly. Subtracting a floored proportional
	## reduction is equivalent to keeping a ceiling of the available slack.
	## The headroom is at most U64.highest even if the reduction is wider.
	headroom = available.to_u128() - $required
	shrink = $slack_total > headroom
	var $kept = 0.U128
	$column = 0
	while $column < count {
		match list_at(table.columns, $column).width {
			Content => {
				slack = column_slack($maxima, $minima, $column, padding_width)
				retained = if shrink {
					product = headroom * slack.to_u128()
					product // $slack_total + (if (product % $slack_total == 0) 0 else 1)
				} else {
					slack.to_u128()
				}
				$widths = list_set($widths, $column, list_at($minima, $column) + retained.to_u64_wrap())
				$kept = $kept + retained
			}
			_ => {}
		}
		$column = $column + 1
	}
	# Each positive retained term rounds up by less than one, so each
	# column can give back at most one rounding unit in this pass.
	var $remaining_deficit = $kept.minus_saturated(headroom)
	$column = 0
	while $column < count and $remaining_deficit > 0 {
		match list_at(table.columns, $column).width {
			Content => if list_at($widths, $column) > list_at($minima, $column) {
				$widths = list_set($widths, $column, list_at($widths, $column) - 1)
				$remaining_deficit = $remaining_deficit - 1
			}
			_ => {}
		}
		$column = $column + 1
	}

	Ok(resolve_shares(table.columns, $widths, $minima, available, $share_weight))
}

# Measured widths can be much larger than the available frame. Applying
# the exact retained slack still applies the rounding correction left to right.
expect {
	cell = Document.cell([Document.plain_text("Value")])
	column = { align: Start, width: Content }
	block = Document.table({ body_rows: [Document.row([cell, cell])], caption: NoCaption, columns: [column, column], footer_rows: [], header_rows: [], row_split: KeepRows })
	authoring = Document.normalize(Document.from_blocks({ contents: [block], language: "en", title: "Wide intrinsic measurements" }))
	table = list_at(authoring.tables, 0)
	group = list_at(authoring.groups, 0)
	token = Scalars(Semantics.IndexRange.from_start_and_length({ start: 0, length: 1 }))
	measure = |max_content| { max_content, min_content: 1, token }
	products = resolve_columns(authoring, table, group, 0, [measure(8000000001), measure(4000000001)], 0, 2, 0, 9, Ordinary)?
	wide_sum = resolve_columns(authoring, table, group, 0, [measure(U64.highest), measure(U64.highest)], 0, 2, 0, 9, Ordinary)?
	products == [5, 4] and wide_sum == [4, 5]
}

column_slack : List(U64), List(U64), U64, U64 -> U64
column_slack = |maxima, minima, column, padding| list_at(maxima, column) - list_at(minima, column).minus_saturated(padding)

ShareMinimum : { column : U64, minimum : U64, weight : U64 }

## Share columns divide the width left by fixed and content columns.
## Clamp initially undersized columns in authored order, then deal with
## a cascade only when a further minimum exceeds the new share. The
## previous feasibility checks guarantee room for every minimum.
resolve_shares : List(Document.TableColumn), List(U64), List(U64), U64, U64 -> List(U64)
resolve_shares = |columns, widths, minima, available, share_weight| {
	count = columns.len()
	used = sum_range(widths, 0, count)
	initial_remaining = if (available > used) available - used else 0
	var $widths = widths
	var $settled = List.repeat(False, count)
	var $remaining = initial_remaining
	var $weight_left = share_weight
	if share_weight > 0 {
		var $column = 0
		while $column < count {
			match list_at(columns, $column).width {
				Share(share) => {
					weight = share.to_u64()
					minimum = list_at(minima, $column)
					if initial_remaining * weight // share_weight < minimum {
						$widths = list_set($widths, $column, minimum)
						$settled = list_set($settled, $column, True)
						$remaining = $remaining - minimum
						$weight_left = $weight_left - weight
					}
				}
				_ => {}
			}
			$column = $column + 1
		}
	}
	if $remaining < initial_remaining and $weight_left > 0 and needs_redistribution(columns, minima, $settled, $remaining, $weight_left) {
		ranked = rank_share_minima(columns, minima, $settled)
		var $index = 0
		# Removing a column whose minimum exceeds its exact proportional
		# share can only lower the width per weight. The old wave's
		# qualifying columns still qualify one at a time in ratio order.
		while $index < ranked.len() and $weight_left > 0 {
			share = list_at(ranked, $index)
			if $remaining * share.weight // $weight_left >= share.minimum {
				break
			}
			$widths = list_set($widths, share.column, share.minimum)
			$settled = list_set($settled, share.column, True)
			$remaining = $remaining - share.minimum
			$weight_left = $weight_left - share.weight
			$index = $index + 1
		}
	}
	if $weight_left == 0 {
		return $widths
	}

	var $given = 0
	var $column = 0
	while $column < count {
		match list_at(columns, $column).width {
			Share(weight) => if !list_at($settled, $column) {
				share = $remaining * weight.to_u64() // $weight_left
				$widths = list_set($widths, $column, share)
				$given = $given + share
			}
			_ => {}
		}
		$column = $column + 1
	}

	# Rounding leaves fewer millipoints than the number of positive
	# unsettled weights. Give them to those columns from left to right.
	var $remainder = $remaining - $given
	$column = 0
	while $column < count and $remainder > 0 {
		match list_at(columns, $column).width {
			Share(weight) => if !list_at($settled, $column) and weight > 0 {
				$widths = list_set($widths, $column, list_at($widths, $column) + 1)
				$remainder = $remainder - 1
			}
			_ => {}
		}
		$column = $column + 1
	}
	$widths
}

needs_redistribution : List(Document.TableColumn), List(U64), List(Bool), U64, U64 -> Bool
needs_redistribution = |columns, minima, settled, remaining, total| {
	var $column = 0
	while $column < columns.len() {
		match list_at(columns, $column).width {
			Share(weight) if !list_at(settled, $column) and remaining * weight.to_u64() // total < list_at(minima, $column) => return True
			_ => {}
		}
		$column = $column + 1
	}
	False
}

rank_share_minima : List(Document.TableColumn), List(U64), List(Bool) -> List(ShareMinimum)
rank_share_minima = |columns, minima, settled| {
	var $shares = []
	var $column = 0
	while $column < columns.len() {
		minimum = list_at(minima, $column)
		match list_at(columns, $column).width {
			Share(weight) if weight > 0 and minimum > 0 and !list_at(settled, $column) => {
				$shares = $shares.append({ column: $column, minimum, weight: weight.to_u64() })
			}
			_ => {}
		}
		$column = $column + 1
	}
	$shares.sort_with(
		|left, right| {
			left_product = left.minimum.to_u128() * right.weight.to_u128()
			right_product = right.minimum.to_u128() * left.weight.to_u128()
			if left_product > right_product {
				Before
			} else if left_product < right_product {
				After
			} else {
				Same
			}
		},
	)
}

count_cells : Document.NormalizedAuthoring, Document.NormalizedGroup -> U64
count_cells = |authoring, group| {
	var $count = group.block_end - group.first_block
	table = match group.kind {
		Table(index) => list_at(authoring.tables, index.to_u64())
		_ => crash "table geometry escaped its table group"
	}
	if table.caption {
		$count = $count - 1
	}
	$count
}

sum_range : List(U64), U64, U64 -> U64
sum_range = |values, start, length| {
	var $total = 0
	var $index = start
	while $index < start + length {
		$total = $total + list_at(values, $index)
		$index = $index + 1
	}
	$total
}

## The number of physical runs from `start` (before `end`) sharing its
## explicit segment occurrence, independently of interned source identity.
segment_length : List(KernelFacadeShape.RunStyle), U64, U64 -> U64
segment_length = |requests, start, end| {
	segment = list_at(requests, start).segment
	var $index = start + 1
	while $index < end and list_at(requests, $index).segment == segment {
		$index = $index + 1
	}
	$index - start
}

fixed_width : Layout.Unit, U64, U64 -> Try(U64, KernelFacadeTables.Error)
fixed_width = |width, group, column| {
	if width <= 0 {
		Err(TableFixedWidth({ column, group }))
	} else {
		Ok(width.raw().to_u64_wrap())
	}
}

nonnegative : I64 -> Try(U64, KernelFacadeTables.Error)
nonnegative = |value| if (value < 0) Err(ArithmeticOverflow) else Ok(value.to_u64_wrap())

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated table geometry index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated table geometry write escaped"
	}
	Ok(updated) => updated
}

## The token domain is carried from measurement, never guessed by a
## diagnostic consumer from coincidentally similar numeric ranges.
token_error : U64, U64, CellMeasure -> KernelFacadeTables.Error
token_error = |available, block, measure| match measure.token {
	Scalars(token) => UnbreakableToken({ available, block, token, width: measure.min_content })
	Items(items) => UnbreakableItems({ available, block, items, width: measure.min_content })
}

# Independent small-world oracle. Enumerate bounded clamp sets and accept
# the one that satisfies all exact ratios at its own final water level.
TestShare : { minimum : U64, weight : U16 }

expected_shares : List(TestShare), U64 -> List(U64)
expected_shares = |tracks, available| {
	total_weight = tracks.fold(0, |sum, share| sum + share.weight.to_u64())
	if total_weight == 0 {
		return List.repeat(0, tracks.len())
	}
	var $mask = 0
	while $mask < (1.U64).shl_wrap(tracks.len().to_u8_wrap()) {
		var $remaining = available
		var $weight_left = total_weight
		var $column = 0
		while $column < tracks.len() {
			share = list_at(tracks, $column)
			if includes_share($mask, $column) {
				$remaining = $remaining - share.minimum
				$weight_left = $weight_left - share.weight.to_u64()
			}
			$column = $column + 1
		}
		var $agrees = $weight_left != 0
		$column = 0
		while $column < tracks.len() and $agrees {
			share = list_at(tracks, $column)
			$agrees = includes_share($mask, $column) == (share.minimum * $weight_left > $remaining * share.weight.to_u64())
			$column = $column + 1
		}
		if $agrees {
			return expected_rounded(tracks, $mask, $remaining, $weight_left)
		}
		$mask = $mask + 1
	}
	crash "a feasible share assignment had no stable clamp set"
}

includes_share : U64, U64 -> Bool
includes_share = |mask, index| mask.bitwise_and((1.U64).shl_wrap(index.to_u8_wrap())) != 0

expected_rounded : List(TestShare), U64, U64, U64 -> List(U64)
expected_rounded = |tracks, mask, available, total_weight| {
	var $total = 0
	var $column = 0
	var $values = []
	while $column < tracks.len() {
		share = list_at(tracks, $column)
		if includes_share(mask, $column) {
			$values = $values.append(share.minimum)
		} else {
			floor = available * share.weight.to_u64() // total_weight
			$values = $values.append(floor)
			$total = $total + floor
		}
		$column = $column + 1
	}
	var $awards_left = available - $total
	$column = 0
	while $column < tracks.len() and $awards_left > 0 {
		if !includes_share(mask, $column) and list_at(tracks, $column).weight > 0 {
			$values = list_set($values, $column, list_at($values, $column) + 1)
			$awards_left = $awards_left - 1
		}
		$column = $column + 1
	}
	$values
}

test_share : U64 -> TestShare
test_share = |encoding| { minimum: encoding % 3, weight: ((encoding // 3) % 3).to_u16_wrap() }

actual_shares : List(TestShare), U64 -> List(U64)
actual_shares = |tracks, available| {
	columns = tracks.map(|share| { align: Start, width: Share(share.weight) })
	minima = tracks.map(|share| share.minimum)
	total_weight = tracks.fold(0, |sum, share| sum + share.weight.to_u64())
	resolve_shares(columns, List.repeat(0, tracks.len()), minima, available, total_weight)
}

expect {
	var $encoding = 0
	while $encoding < 729 {
		tracks = [test_share($encoding), test_share($encoding // 9), test_share($encoding // 81)]
		minimum = tracks.fold(0, |sum, track| sum + track.minimum)
		var $available = minimum
		while $available <= minimum + 3 {
			actual = actual_shares(tracks, $available)
			expected = expected_shares(tracks, $available)
			if actual != expected {
				crash "Share mismatch for ${Str.inspect(tracks)} and ${$available.to_str()}: ${Str.inspect(actual)}"
			}
			$available = $available + 1
		}
		$encoding = $encoding + 1
	}
	True
}

expect {
	cascade = [{ minimum: 18, weight: 7 }, { minimum: 8, weight: 4 }, { minimum: 3, weight: 2 }, { minimum: 0, weight: 1 }]
	tie = [{ minimum: 3, weight: 2 }, { minimum: 1, weight: 1 }]
	actual_shares(cascade, 30) == expected_shares(cascade, 30) and
		actual_shares(cascade, 30) == [18, 8, 3, 1] and
			actual_shares(tie, 5) == [4, 1]
}
