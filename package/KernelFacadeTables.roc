import Document
import KernelFacadeShape
import KernelFacadeSources
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

		## Fixed widths plus every column's minimum exceed the available width.
		TableWidth({ available : U64, group : U64, required : U64 }),

		## A cell's widest unbreakable piece (`token`, a scalar range of the
		## cell text's `source` segment) is wider than the width its columns
		## receive.
		UnbreakableToken({ available : U64, block : U64, token : Semantics.Range, width : U64 }),
	]

	## One cell's resolved geometry: its text box starts `x` from the flow
	## edge and is `width` wide (its spanned columns less the cell padding
	## on both sides), and its lines align within it.
	CellGeometry : { align : Document.ColumnAlign, block : U64, width : U64, x : U64 }

	## One table's resolved column widths (left to right) and total width.
	TableGeometry : { columns : List(U64), group : U64, width : U64 }

	Work : {
		cell_measurements : U64,
		column_width_passes : U64,
		measurement_cache_hits : U64,
		row_visits : U64,
	}

	## `cells` is indexed by cell ordinal (the normalized `cells` arena);
	## `tables` by table index.
	Plan :: { cells : List(CellGeometry), sources : List(KernelFacadeSources.Source), tables : List(TableGeometry), work : Work }.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), U64, Theme, KernelLineLayout.Limits -> Try(Plan, Error)
		build = |authoring, shape, sources, available, theme, limits| build_plan(authoring, shape, sources, available, theme, limits)

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
CellMeasure : { max_content : U64, min_content : U64, token : Semantics.Range }

## Measurements are cached per interned source: a source's physical split
## and size are fixed for the document, so identical cell texts measure once.
CacheSlot : [Measured({ measure : CellMeasure, size : I64 }), Unmeasured]

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.Plan, List(KernelFacadeSources.Source), U64, Theme, KernelLineLayout.Limits -> Try(KernelFacadeTables.Plan, KernelFacadeTables.Error)
build_plan = |authoring, shape, sources, available, theme, limits| {
	block_runs = KernelFacadeShape.Plan.block_runs(shape)
	requests = KernelFacadeShape.Plan.requests(shape)
	store = KernelFacadeShape.Plan.shape(shape).store
	simple_sources = sources.map(|source| { analysis: source.analysis, unicode: source.unicode })
	padding = nonnegative(Theme.table_style(theme).cell_padding.raw())?
	var $cache = List.repeat(Unmeasured, sources.len())
	var $measures = List.with_capacity(authoring.cells.len())
	var $cells = List.with_capacity(authoring.cells.len())
	var $tables = List.with_capacity(authoring.tables.len())
	var $cache_hits = 0
	var $measurements = 0
	var $row_visits = 0
	var $ordinal = 0
	while $ordinal < authoring.cells.len() {
		record = list_at(authoring.cells, $ordinal)
		physical = match list_at(block_runs, record.block) {
			TextBlock({ body, label: _, level: _ }) => body.physical
		}
		var $cell = { max_content: 0, min_content: 0, token: Semantics.Range.from_start_and_length(0, 0) }
		var $segment = physical.start()
		end = physical.start() + physical.length()
		while $segment < end {
			length = segment_length(requests, $segment, end)
			source = list_at(requests, $segment).source
			size = list_at(store.runs, $segment).size.raw()
			measured = match list_at($cache, source.index()) {
				Measured(slot) => if slot.size == size {
					$cache_hits = $cache_hits + 1
					slot.measure
				} else {
					fresh = measure_segment(simple_sources, store, $segment, length, source, limits)?
					$measurements = $measurements + 1
					fresh
				}
				Unmeasured => {
					fresh = measure_segment(simple_sources, store, $segment, length, source, limits)?
					$measurements = $measurements + 1
					$cache = list_set($cache, source.index(), Measured({ measure: fresh, size }))
					fresh
				}
			}
			$cell = {
				max_content: U64.max($cell.max_content, measured.max_content),
				min_content: U64.max($cell.min_content, measured.min_content),
				token: if measured.min_content > $cell.min_content measured.token else $cell.token,
			}
			$segment = $segment + length
		}
		$measures = $measures.append($cell)
		$ordinal = $ordinal + 1
	}

	## Resolve each table's columns once, then every cell's text box.
	var $cell_cursor = 0
	var $group_index = 0
	while $group_index < authoring.groups.len() {
		group = list_at(authoring.groups, $group_index)
		match group.kind {
			Table(table_index) => {
				table = list_at(authoring.tables, table_index.to_u64())
				first_cell = $cell_cursor
				cell_end = first_cell + count_cells(authoring, group)
				columns = resolve_columns(authoring, table, group, $group_index, $measures, first_cell, cell_end, padding, available)?
				var $row = $group_index + 1
				var $ordinal_cursor = first_cell
				while $row < group.group_end {
					row_group = list_at(authoring.groups, $row)
					var $column = 0
					var $x = 0
					var $block = row_group.first_block
					while $block < row_group.block_end {
						record = list_at(authoring.cells, $ordinal_cursor)
						span = record.column_span
						cell_width = sum_range(columns, $column, span)
						if cell_width <= 2 * padding {
							return Err(UnbreakableToken({ available: 0, block: $block, token: list_at($measures, $ordinal_cursor).token, width: list_at($measures, $ordinal_cursor).min_content }))
						}
						text_width = cell_width - 2 * padding
						measure = list_at($measures, $ordinal_cursor)
						if measure.min_content > text_width {
							return Err(UnbreakableToken({ available: text_width, block: $block, token: measure.token, width: measure.min_content }))
						}
						$cells = $cells.append({ align: list_at(table.columns, $column).align, block: $block, width: text_width, x: $x + padding })
						$x = $x + cell_width
						$column = $column + span
						$ordinal_cursor = $ordinal_cursor + 1
						$block = $block + 1
					}
					$row_visits = $row_visits + 1
					$row = $row + 1
				}
				$tables = $tables.append({ columns, group: $group_index, width: sum_range(columns, 0, columns.len()) })
				$cell_cursor = cell_end
			}
			_ => {}
		}
		$group_index = $group_index + 1
	}
	Ok(
		KernelFacadeTables.Plan.{
			cells: $cells,
			sources,
			tables: $tables,
			work: {
				cell_measurements: $measurements,
				column_width_passes: $tables.len(),
				measurement_cache_hits: $cache_hits,
				row_visits: $row_visits,
			},
		},
	)
}

## Measure one explicit-line-break segment: its physical runs over one
## whole source, as a logical request.
measure_segment : List(KernelShape.SimpleSource), Text.Store, U64, U64, Semantics.TextSourceId, KernelLineLayout.Limits -> Try(CellMeasure, KernelFacadeTables.Error)
measure_segment = |sources, store, start, length, source, limits| {
	measured = KernelLineLayout.measure_logical(sources, store, { runs: Semantics.Range.from_start_and_length(start, length), source, width: Layout.Unit.from_raw(1) }, limits) ? Measure
	first = list_at(store.clusters, measured.measure.token.start())
	last = list_at(store.clusters, measured.measure.token.start() + U64.max(measured.measure.token.length(), 1) - 1)
	token_start = first.source.scalars.start()
	token_end = last.source.scalars.start() + last.source.scalars.length()
	Ok({
		max_content: nonnegative(measured.measure.max_content)?,
		min_content: nonnegative(measured.measure.min_content)?,
		token: Semantics.Range.from_start_and_length(token_start, token_end - token_start),
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
resolve_columns : Document.NormalizedAuthoring, Document.NormalizedTable, Document.NormalizedGroup, U64, List(CellMeasure), U64, U64, U64, U64 -> Try(List(U64), KernelFacadeTables.Error)
resolve_columns = |authoring, table, group, group_index, measures, first_cell, cell_end, padding, available| {
	count = table.columns.len()
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
			if record.column_span == 1 {
				measure = list_at(measures, $ordinal)
				minimum = measure.min_content + 2 * padding
				if minimum > list_at($minima, $column) {
					$minima = list_set($minima, $column, minimum)
					$widest = list_set($widest, $column, $ordinal)
				}
				$maxima = list_set($maxima, $column, U64.max(list_at($maxima, $column), measure.max_content + 2 * padding))
			}
			$column = $column + record.column_span
			$ordinal = $ordinal + 1
			$block = $block + 1
		}
		$row = $row + 1
	}
	if $ordinal != cell_end {
		return Err(InvalidCell({ block: group.first_block }))
	}

	## Exact fixed columns, and each single column's own feasibility.
	var $widths = List.repeat(0, count)
	var $fixed = 0
	var $required = 0
	var $column = 0
	while $column < count {
		minimum = list_at($minima, $column)
		limit = match list_at(table.columns, $column).width {
			Fixed(unit) => nonnegative(unit.raw())?
			_ => available
		}
		if minimum > limit {
			widest = list_at($widest, $column)
			measure = list_at(measures, widest)
			return Err(UnbreakableToken({ available: if limit > 2 * padding limit - 2 * padding else 0, block: list_at(authoring.cells, widest).block, token: measure.token, width: measure.min_content }))
		}
		match list_at(table.columns, $column).width {
			Fixed(_) => {
				$widths = list_set($widths, $column, limit)
				$fixed = $fixed + limit
				$required = $required + limit
			}
			_ => {
				$required = $required + minimum
			}
		}
		$column = $column + 1
	}
	if $required > available {
		return Err(TableWidth({ available, group: group_index, required: $required }))
	}

	## Content columns at their max-content width, reduced proportionally
	## to their slack when the minima of the share columns would not fit.
	var $content_total = 0
	var $slack_total = 0
	var $share_minima = 0
	$column = 0
	while $column < count {
		match list_at(table.columns, $column).width {
			Content => {
				$content_total = $content_total + list_at($maxima, $column)
				$slack_total = $slack_total + (list_at($maxima, $column) - list_at($minima, $column))
			}
			Share(_) => {
				$share_minima = $share_minima + list_at($minima, $column)
			}
			Fixed(_) => {}
		}
		$column = $column + 1
	}
	deficit = if $fixed + $content_total + $share_minima > available $fixed + $content_total + $share_minima - available else 0
	var $reduced = 0
	$column = 0
	while $column < count {
		match list_at(table.columns, $column).width {
			Content => {
				slack = list_at($maxima, $column) - list_at($minima, $column)
				reduction = if $slack_total == 0 0 else deficit * slack // $slack_total
				$widths = list_set($widths, $column, list_at($maxima, $column) - reduction)
				$reduced = $reduced + reduction
			}
			_ => {}
		}
		$column = $column + 1
	}
	var $remaining_deficit = deficit - $reduced
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
		if $column == count and $remaining_deficit > 0 {
			$column = 0
		}
	}

	## Share columns divide what remains; a share below its minimum is fixed
	## at the minimum and the others divide the rest again.
	var $used = sum_range($widths, 0, count)
	var $settled = List.repeat(False, count)
	var $settling = True
	while $settling {
		remaining = if available > $used available - $used else 0
		var $weights = 0
		$column = 0
		while $column < count {
			match list_at(table.columns, $column).width {
				Share(weight) => if !list_at($settled, $column) {
					$weights = $weights + weight.to_u64()
				}
				_ => {}
			}
			$column = $column + 1
		}
		$settling = False
		if $weights > 0 {
			var $below = False
			$column = 0
			while $column < count {
				match list_at(table.columns, $column).width {
					Share(weight) => if !list_at($settled, $column) and remaining * weight.to_u64() // $weights < list_at($minima, $column) {
						$widths = list_set($widths, $column, list_at($minima, $column))
						$settled = list_set($settled, $column, True)
						$used = $used + list_at($minima, $column)
						$below = True
					}
					_ => {}
				}
				$column = $column + 1
			}
			if $below {
				$settling = True
			} else {
				var $given = 0
				$column = 0
				while $column < count {
					match list_at(table.columns, $column).width {
						Share(weight) => if !list_at($settled, $column) {
							share = remaining * weight.to_u64() // $weights
							$widths = list_set($widths, $column, share)
							$given = $given + share
						}
						_ => {}
					}
					$column = $column + 1
				}
				var $remainder = remaining - $given
				$column = 0
				while $column < count and $remainder > 0 {
					match list_at(table.columns, $column).width {
						Share(weight) => if !list_at($settled, $column) and weight > 0 {
							$widths = list_set($widths, $column, list_at($widths, $column) + 1)
							$remainder = $remainder - 1
						}
						_ => {}
					}
					$column = $column + 1
					if $column == count and $remainder > 0 {
						$column = 0
					}
				}
			}
		}
	}
	Ok($widths)
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
## source: one explicit-line-break segment of a cell.
segment_length : List(KernelShape.SimpleRequest), U64, U64 -> U64
segment_length = |requests, start, end| {
	source = list_at(requests, start).source.index()
	var $index = start + 1
	while $index < end and list_at(requests, $index).source.index() == source {
		$index = $index + 1
	}
	$index - start
}

nonnegative : I64 -> Try(U64, KernelFacadeTables.Error)
nonnegative = |value| if value < 0 Err(ArithmeticOverflow) else Ok(value.to_u64_wrap())

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
