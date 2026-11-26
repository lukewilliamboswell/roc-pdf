import Document
import Semantics

## Verified logical coordinates for tables with row spans. Ordinary tables
## use their dense cell order and allocate no grid arena. The tiles of a
## logical row stay in column order; a spanning cell appears once per row
## it covers, using its original authored cell identity.
KernelFacadeTableGrid :: [].{
	Cell : { column : U64, column_end : U64, row : U64, row_end : U64 }
	Row : { crosses_after : Bool, tiles : Semantics.IndexRange }
	Grid : { cells : List(Cell), first_cell : U64, group : U64, rows : List(Row), tiles : List(U64), work : U64 }
	Selection : [Ordinary, Spanning(Grid)]
	Error : [
		CellExtent({ block : U64, reason : [ColumnEnd, ColumnOccupied, RowGroupEnd, ZeroColumns, ZeroRows] }),
		RowGap({ column : U64, group : U64 }),
		TrackBudget({ group : U64, limit : U64 }),
	]

	build : Document.NormalizedAuthoring, U64, U64, U64, Document.NormalizedTable -> Try(Selection, Error)
	build = |authoring, group, first, end, table| check_grid(authoring, group, first, end, table)

	## Look up the sparse accepted grid by its normalized table group.
	for_group : List(Grid), U64 -> Selection
	for_group = |grids, group| {
		var $lo = 0
		var $hi = grids.len()
		while $lo < $hi {
			mid = $lo + U64.div_by($hi - $lo, 2)
			grid = list_at(grids, mid)
			if grid.group == group {
				return Spanning(grid)
			}
			if grid.group < group {
				$lo = mid + 1
			} else {
				$hi = mid
			}
		}
		Ordinary
	}
}

Track : { cell : U64, column_end : U64, row_end : U64 }

track_limit : U64
track_limit = 1000000

## ISO 32000-2:2020+EC3 §14.8.4.8.3 and Table 371, §14.8.5.7 and Table
## 384. PDF/UA-2 and WTPDF §8.2.5.26 require a regular logical grid. Each
## authored cell starts in the first unoccupied column and occupies its
## whole rectangle within its own THead, TBody or TFoot. Every track is
## occupied exactly once in every row. Grid work is bounded before arena
## writes; only a span's starting row writes slots to the active track list.
check_grid : Document.NormalizedAuthoring, U64, U64, U64, Document.NormalizedTable -> Try(KernelFacadeTableGrid.Selection, KernelFacadeTableGrid.Error)
check_grid = |authoring, group, first, end, table| {
	var $index = first
	while $index < end {
		record = list_at(authoring.cells, $index)
		if record.row_span > 1 {
			return check_rectangles(authoring, group, first, end, table)
		}
		$index = $index + 1
	}
	Ok(Ordinary)
}

check_rectangles : Document.NormalizedAuthoring, U64, U64, U64, Document.NormalizedTable -> Try(KernelFacadeTableGrid.Selection, KernelFacadeTableGrid.Error)
check_rectangles = |authoring, group, first, end, table| {
	width = table.columns.len()
	header_end = table.header_rows
	body_end = header_end + table.body_rows
	footer_end = body_end + table.footer_rows
	if width > track_limit or end - first > track_limit or footer_end > track_limit {
		return Err(TrackBudget({ group, limit: track_limit }))
	}
	var $active = List.repeat({ cell: 0, column_end: 0, row_end: 0 }, width)
	var $cells = List.with_capacity(end - first)
	var $rows = List.with_capacity(footer_end)
	var $tiles = []
	var $work = 0
	var $row = 0
	var $cell = first
	while $row < footer_end {
		row_group = group + 1 + $row
		row = list_at(authoring.groups, row_group)
		group_end = if ($row < header_end) header_end else if ($row < body_end) body_end else footer_end
		row_end = $cell + row.block_end - row.first_block
		tile_start = $tiles.len()
		var $crosses_after = False
		var $column = 0
		while $column < width {
			if $work == track_limit {
				return Err(TrackBudget({ group, limit: track_limit }))
			}
			$work = $work + 1
			active = list_at($active, $column)
			if active.row_end > $row {
				$tiles = $tiles.append(active.cell)
				$crosses_after = $crosses_after or active.row_end > $row + 1
				$column = active.column_end
			} else {
				if $cell >= row_end {
					return Err(RowGap({ column: $column, group: row_group }))
				}
				record = list_at(authoring.cells, $cell)
				height = record.row_span.to_u64()
				span = record.column_span.to_u64()
				if height == 0 {
					return Err(CellExtent({ block: record.block, reason: ZeroRows }))
				}
				if height > group_end - $row {
					return Err(CellExtent({ block: record.block, reason: RowGroupEnd }))
				}
				if span == 0 {
					return Err(CellExtent({ block: record.block, reason: ZeroColumns }))
				}
				if span > width - $column {
					return Err(CellExtent({ block: record.block, reason: ColumnEnd }))
				}
				cell_end = $column + span
				area = span * height
				if area > track_limit - $work {
					return Err(TrackBudget({ group, limit: track_limit }))
				}
				$work = $work + area
				var $track = $column
				while $track < cell_end {
					if list_at($active, $track).row_end > $row {
						return Err(CellExtent({ block: record.block, reason: ColumnOccupied }))
					}
					$active = list_set($active, $track, { cell: $cell, column_end: cell_end, row_end: $row + height })
					$track = $track + 1
				}
				$cells = $cells.append({ column: $column, column_end: cell_end, row: $row, row_end: $row + height })
				$tiles = $tiles.append($cell)
				$crosses_after = $crosses_after or height > 1
				$cell = $cell + 1
				$column = cell_end
			}
		}
		if $cell < row_end {
			return Err(CellExtent({ block: list_at(authoring.cells, $cell).block, reason: ColumnEnd }))
		}
		$rows = $rows.append({ crosses_after: $crosses_after, tiles: Semantics.IndexRange.from_start_and_length({ start: tile_start, length: $tiles.len() - tile_start }) })
		$row = $row + 1
	}
	Ok(Spanning({ cells: $cells, first_cell: first, group, rows: $rows, tiles: $tiles, work: $work }))
}

list_at : List(a), U64 -> a
list_at = |items, index| items.get(index) ?? crash "verified table grid index escaped"

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| items.set(index, value) ?? crash "verified table grid index escaped"
