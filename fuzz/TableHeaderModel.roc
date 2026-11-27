import fuzz.Model
import pdf.Document
import pdf.KernelFacadeSemantics
import pdf.KernelFacadeSources
import pdf.KernelSemantics
import pdf.KernelTextSemantics
import pdf.Semantics

TableHeaderModel := [].{}

Row : [WideBothLeft, WideBothRight, WideColumnRight, RowAfter, RowBefore, MixedScope, FullData, NarrowData]

Sections : [BodyOnly, HeadBodyFoot]

World : { sections : [Unset, Set(Sections)], rows : List(Row) }

Action : [Arrange(Sections), Append(Row)]

machine : Model.Machine(World, Action)
machine = {
	init: { sections: Unset, rows: [] },
	actions: |world| match world.sections {
		Unset => [Arrange(BodyOnly), Arrange(HeadBodyFoot)]
		Set(_) if world.rows.len() == 3 => []
		Set(_) => {
			choices = [WideBothLeft, WideBothRight, WideColumnRight, RowAfter, RowBefore, MixedScope, FullData, NarrowData]
			# The final row supplies a header if the first two rows lack one.
			legal = if (world.rows.len() == 2 and world.rows.all(unheaded)) choices.keep_if(|row| !unheaded(row)) else choices
			legal.map(|row| Append(row))
		}
	},
	step: |world, action| match action {
		Arrange(sections) => { ..world, sections: Set(sections) }
		Append(row) => { ..world, rows: world.rows.append(row) }
	},
	rules: [
		Model.always(
			"every attached Headers list and typed edge agrees with the authored grid",
			|world| match world.sections {
				Set(sections) if world.rows.len() == 3 => agrees(world.rows, sections)
				_ => True
			},
		),
		witness("one spanning Both header contributes once across multiple columns", HeadBodyFoot, [WideBothLeft, RowAfter, FullData]),
		witness("a spanning header applies when only one of its columns overlaps", HeadBodyFoot, [WideBothLeft, RowBefore, NarrowData]),
		witness("a row header on either side of a data cell is confined to its row", BodyOnly, [RowAfter, RowBefore, FullData]),
		witness("later column headers are absent from earlier data associations", BodyOnly, [FullData, WideColumnRight, NarrowData]),
		witness("multiple earlier headers remain in authored cell order", HeadBodyFoot, [WideBothRight, WideBothLeft, FullData]),
		witness("a spanning target header keeps each preceding column header once", HeadBodyFoot, [WideBothLeft, WideColumnRight, FullData]),
		witness("a preceding row header can describe another header without a reverse edge", BodyOnly, [WideBothLeft, FullData, FullData]),
	],
}

unheaded : Row -> Bool
unheaded = |row| row == FullData or row == NarrowData

witness : Str, Sections, List(Row) -> Model.Rule(World, Action)
witness = |name, sections, rows| Model.sometimes(name, |world| world.sections == Set(sections) and world.rows == rows)

Cell : { role : [Data, Header(Document.HeaderScope)], width : U64 }

row_cells : Row -> List(Cell)
row_cells = |row| match row {
	WideBothLeft => [{ role: Header(Both), width: 2 }, { role: Header(Column), width: 1 }]
	WideBothRight => [{ role: Header(Column), width: 1 }, { role: Header(Both), width: 2 }]
	WideColumnRight => [{ role: Data, width: 1 }, { role: Header(Column), width: 2 }]
	RowAfter => [{ role: Data, width: 2 }, { role: Header(Row), width: 1 }]
	RowBefore => [{ role: Header(Row), width: 1 }, { role: Data, width: 2 }]
	MixedScope => [{ role: Header(Column), width: 1 }, { role: Data, width: 1 }, { role: Header(Both), width: 1 }]
	FullData => [{ role: Data, width: 3 }]
	NarrowData => [{ role: Data, width: 1 }, { role: Data, width: 2 }]
}

authored_row : Row -> Document.Row
authored_row = |row| Document.row(
	row_cells(row).map(
		|cell| {
			inlines = [Document.plain_text("cell")]
			authored = match cell.role {
				Data => Document.cell(inlines)
				Header(scope) => Document.header_cell(scope, inlines)
			}
			authored.spanning(cell.width.to_u16_wrap())
		},
	),
)

Rectangle : { id : U64, row : U64, left : U64, right : U64, cell : Cell }

rectangles : List(Row) -> List(Rectangle)
rectangles = |rows| {
	var $result = []
	var $row = 0
	for shape in rows {
		var $left = 0
		for cell in row_cells(shape) {
			right = $left + cell.width
			$result = $result.append({ id: $result.len(), row: $row, left: $left, right, cell })
			$left = right
		}
		$row = $row + 1
	}
	$result
}

# ISO 32000-2:2020+EC3 14.8.4.8.3 describes a search from a data or
# header cell. Rescan the authored rectangles per target, so a spanning
# header contributes at most one identity and header edges precede targets.
expected_headers : List(Rectangle), Rectangle -> List(U64)
expected_headers = |cells, target| cells.keep_if(
	|candidate|
		match candidate.cell.role {
			Header(scope) =>
				(candidate.row < target.row and (scope == Column or scope == Both) and candidate.left < target.right and target.left < candidate.right)
					or (candidate.row == target.row and (scope == Row or scope == Both) and (target.cell.role == Data or candidate.left < target.left))
			Data => False
		},
).map(|candidate| candidate.id)

identifier : U64 -> Str
identifier = |index| "c00000${(index + 1).to_str()}"

agrees : List(Row), Sections -> Bool
agrees = |rows, sections| {
	authored = rows.map(authored_row)
	partitions = if sections == HeadBodyFoot {
		{ header_rows: authored.take_first(1), body_rows: authored.sublist({ start: 1, len: 1 }), footer_rows: authored.sublist({ start: 2, len: 1 }) }
	} else {
		{ header_rows: [], body_rows: authored, footer_rows: [] }
	}
	table = Document.table({
		header_rows: partitions.header_rows,
		body_rows: partitions.body_rows,
		footer_rows: partitions.footer_rows,
		caption: NoCaption,
		columns: List.repeat({ align: Start, width: Content }, 3),
		row_split: KeepRows,
	})
	authoring = Document.normalize(Document.from_blocks({ contents: [table], language: "en-AU", title: "Table header associations" }))
	plan = match KernelFacadeSemantics.Plan.build(authoring, limits) {
		Ok(value) => value
		Err(error) => crash "table ${Str.inspect(sections)} ${Str.inspect(rows)} failed semantic planning: ${Str.inspect(error)}"
	}
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	cells = rectangles(rows)
	headers = cells.map(|cell| expected_headers(cells, cell))
	nodes = store.nodes.keep_if(|node| node.role.local_name == "TH" or node.role.local_name == "TD")
	if nodes.len() != cells.len() {
		crash "wrong number of semantic cells for ${Str.inspect(sections)} ${Str.inspect(rows)}"
	}
	for cell in cells {
		node = nodes.get(cell.id) ?? crash "missing planned cell"
		linked = headers.get(cell.id) ?? crash "missing model cell"
		attributes = store.attributes.sublist({ start: node.attributes.start(), len: node.attributes.length() })
		required = cell_attributes(cell.cell, linked)
		role = if (cell.cell.role == Data) "TD" else "TH"
		if node.role.local_name != role or node.element_identifier != HasElementIdentifier(Semantics.ElementId.from_index(cell.id)) or attributes.len() != required.len() or !required.all(|attribute| attributes.contains(attribute)) {
			crash "cell ${identifier(cell.id)} in ${Str.inspect(sections)} ${Str.inspect(rows)} expects ${Str.inspect(required)}, found ${Str.inspect(attributes)}"
		}
	}
	relations = headers.map_with_index(|linked, cell| linked.map(|header|
		HeaderFor({ cell: Semantics.ElementId.from_index(cell), header: Semantics.ElementId.from_index(header) }))).join()
	store.relationships == relations and store.element_identifiers == cells.map(|cell|
		{ id: Semantics.ElementId.from_index(cell.id), value: identifier(cell.id) })
}

cell_attributes : Cell, List(U64) -> List(Semantics.StructureAttribute)
cell_attributes = |cell, headers| {
	var $attributes = []
	if cell.width > 1 {
		$attributes = $attributes.append(table_attribute("ColSpan", Integer(cell.width.to_i64_wrap())))
	}
	if !headers.is_empty() {
		$attributes = $attributes.append(table_attribute("Headers", Names(headers.map(identifier))))
	}
	match cell.role {
		Data => {}
		Header(scope) => {
			name = match scope {
				Both => "Both"
				Row => "Row"
				Column => "Column"
			}
			$attributes = $attributes.append(table_attribute("Scope", Name(name)))
		}
	}
	$attributes
}

table_attribute : Str, Semantics.AttributeValue -> Semantics.StructureAttribute
table_attribute = |name, value| { applicability: Family(TableRoles), name: Standard(name), owner: Table, value }

limits : KernelFacadeSemantics.Limits
limits = KernelFacadeSemantics.Limits.make({
	max_container_depth: 2,
	max_inline_depth: 8,
	max_content_spine: 64,
	max_nodes: 32,
	max_occurrences: 12,
	max_properties: 4,
	max_source_inputs: 12,
	semantics: KernelSemantics.Limits.make({ max_attributes: 32, max_content_spine: 64, max_fragments: 0, max_namespaces: 1, max_nodes: 32, max_occurrences: 12, max_semantic_depth: 8 }),
	sources: KernelFacadeSources.Limits.make({
		max_hash_probes: 64,
		max_inputs: 12,
		max_source_bytes: 64,
		max_source_scalars: 64,
		max_table_slots: 32,
		max_unique_sources: 12,
		unicode: { max_graphemes: 16, max_line_boundaries: 17, max_scalars: 16, max_script_runs: 8 },
	}),
	text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 4, max_text_property_bytes: 8, max_text_source_bytes: 64, max_text_source_scalars: 64, max_text_sources: 12 }),
})

expect {
	report = Model.explore(machine, { depth: 5, key: |world| (world.sections, world.rows), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1155 and report.steps == 1154 and report.depth == 4 and report.reached.len() == 7
}

## The ordinary model above rescans scope edges. The spanning model uses a
## bounded bitmap, then compares coverage and exact ordered scopes at the
## semantic stage. Finitely many authored row recipes include illegal grids.
SpanRow : [FullHeight, Inner, Left, None, One, Two, Wide]

SpanPartition : [AllBody, HeadAndBody, HeadBodyFoot]

SpanWorld : { partition : [Partition(SpanPartition), Unset], rows : List(SpanRow) }

SpanAction : [AppendSpan(SpanRow), Partition(SpanPartition)]

SpanCell : { column_span : U64, height : U64, kind : [Data, Header(Document.HeaderScope)] }

PlacedSpan : { cell : SpanCell, column : U64, ordinal : U64, row : U64 }

span_machine : Model.Machine(SpanWorld, SpanAction)
span_machine = {
	init: { partition: Unset, rows: [] },
	actions: |world| match world.partition {
		Unset => [Partition(AllBody), Partition(HeadAndBody), Partition(HeadBodyFoot)]
		Partition(_) => if (world.rows.len() < 3) [Left, Inner, FullHeight, Wide, Two, One, None].map(|row| AppendSpan(row)) else []
	},
	step: |world, action| match action {
		Partition(partition) => { ..world, partition: Partition(partition) }
		AppendSpan(row) => { ..world, rows: world.rows.append(row) }
	},
	rules: [
		Model.always(
			"spanning cells and scopes agree with an independently filled bitmap",
			|world|
				match world.partition {
					Partition(partition) if world.rows.len() == 3 => span_agrees(world.rows, partition)
					_ => True
				},
		),
		span_witness("combined span touches a sibling without overlapping", AllBody, [Left, One, Wide]),
		span_witness("a combined span occupies a row with no authored origins", AllBody, [FullHeight, None, None]),
		span_witness("a later wide cell overlaps an earlier interior span", AllBody, [Inner, Two, Wide]),
		span_witness("a wide later cell overflows after a carried span", AllBody, [Left, Wide, Wide]),
		span_witness("a row omits an uncovered track", AllBody, [Inner, One, Wide]),
		span_witness("a rowspan crossing a section boundary rejects", HeadBodyFoot, [Left, One, Wide]),
		span_witness("a rowspan ending at a section boundary succeeds", HeadAndBody, [Left, One, Wide]),
	],
}

span_witness : Str, SpanPartition, List(SpanRow) -> Model.Rule(SpanWorld, SpanAction)
span_witness = |name, partition, rows| Model.sometimes(name, |world| world.partition == Partition(partition) and world.rows == rows)

span_cells : SpanRow -> List(SpanCell)
span_cells = |row| match row {
	Left => [{ column_span: 2, height: 2, kind: Header(Both) }, { column_span: 1, height: 1, kind: Data }]
	Inner => [{ column_span: 1, height: 1, kind: Data }, { column_span: 1, height: 2, kind: Header(Row) }, { column_span: 1, height: 1, kind: Data }]
	FullHeight => [{ column_span: 3, height: 3, kind: Header(Column) }]
	Wide => [{ column_span: 3, height: 1, kind: Header(Both) }]
	Two => [{ column_span: 2, height: 1, kind: Data }]
	One => [{ column_span: 1, height: 1, kind: Data }]
	None => []
}

span_sections : SpanPartition, U64 -> U64
span_sections = |partition, row| match partition {
	AllBody => 3
	HeadAndBody => if (row < 2) 2 else 3
	HeadBodyFoot => row + 1
}

span_bitmap : List(SpanRow), SpanPartition -> Try({ placements : List(PlacedSpan), tiles : List(List(U64)) }, [Invalid])
span_bitmap = |rows, partition| {
	var $bits = List.repeat(0, 9)
	var $placements = []
	var $row = 0
	for recipe in rows {
		for cell in span_cells(recipe) {
			var $column = 0
			while $column < 3 and ($bits.get($row * 3 + $column) ?? 0) != 0 {
				$column = $column + 1
			}
			if $column + cell.column_span > 3 or $row + cell.height > span_sections(partition, $row) {
				return Err(Invalid)
			}
			ordinal = $placements.len()
			$placements = $placements.append({ cell, column: $column, ordinal, row: $row })
			var $y = $row
			while $y < $row + cell.height {
				var $x = $column
				while $x < $column + cell.column_span {
					index = $y * 3 + $x
					if ($bits.get(index) ?? 0) != 0 {
						return Err(Invalid)
					}
					$bits = $bits.set(index, ordinal + 1) ?? crash "model bitmap coordinate escaped"
					$x = $x + 1
				}
				$y = $y + 1
			}
		}
		if $bits.sublist({ start: $row * 3, len: 3 }).contains(0) {
			return Err(Invalid)
		}
		$row = $row + 1
	}
	if !$placements.any(|entry| entry.cell.kind != Data) {
		return Err(Invalid)
	}
	tiles = [0, 1, 2].map(
		|row| {
			var $row_tiles = []
			for bit in $bits.sublist({ start: row * 3, len: 3 }) {
				if !$row_tiles.contains(bit - 1) {
					$row_tiles = $row_tiles.append(bit - 1)
				}
			}
			$row_tiles
		},
	)
	Ok({ placements: $placements, tiles })
}

span_agrees : List(SpanRow), SpanPartition -> Bool
span_agrees = |shapes, partition| {
	rows = shapes.map(
		|shape| Document.row(
			span_cells(shape).map(
				|cell| {
					text = [Document.plain_text("x")]
					authored = match cell.kind {
						Data => Document.cell(text)
						Header(scope) => Document.header_cell(scope, text)
					}
					authored.spanning(cell.column_span.to_u16_wrap()).row_spanning(cell.height.to_u16_wrap())
				},
			),
		),
	)
	subsets = match partition {
		AllBody => { head: [], body: rows, foot: [] }
		HeadAndBody => { head: rows.take_first(2), body: rows.drop_first(2), foot: [] }
		HeadBodyFoot => { head: rows.take_first(1), body: rows.sublist({ start: 1, len: 1 }), foot: rows.drop_first(2) }
	}
	table = Document.table({
		header_rows: subsets.head,
		body_rows: subsets.body,
		footer_rows: subsets.foot,
		caption: NoCaption,
		columns: List.repeat({ align: Start, width: Content }, 3),
		row_split: KeepRows,
	})
	authoring = Document.normalize(Document.from_blocks({ contents: [table], language: "en", title: "Spanning grid model" }))
	checked = KernelFacadeSemantics.Plan.build(authoring, limits)
	match (span_bitmap(shapes, partition), checked) {
		(Err(Invalid), Err(TableSpan(_))) | (Err(Invalid), Err(TableGridMismatch(_))) | (Err(Invalid), Err(TableHeaderMissing(_))) | (Err(Invalid), Err(TableEmpty(_))) => True
		(Ok(expected), Ok(plan)) => {
			verified = KernelFacadeSemantics.Plan.table_grids(plan)
			if expected.placements.any(|entry| entry.cell.height > 1) {
				grid = verified.get(0) ?? crash "verified spanning grid missing"
				actual = grid.cells.map(|cell| [cell.column, cell.column_end, cell.row, cell.row_end])
				rectangles_expected = expected.placements.map(|entry| [entry.column, entry.column + entry.cell.column_span, entry.row, entry.row + entry.cell.height])
				row_tiles = grid.rows.map(|row| grid.tiles.sublist({ start: row.tiles.start(), len: row.tiles.length() }))
				if verified.len() != 1 or actual != rectangles_expected or row_tiles != expected.tiles {
					return False
				}
			} else if !verified.is_empty() {
				return False
			}
			store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
			expected_edges = expected.placements.map(|target| span_headers(expected.placements, target).map(|header|
				HeaderFor({ cell: Semantics.ElementId.from_index(target.ordinal), header: Semantics.ElementId.from_index(header) }))).join()
			store.relationships == expected_edges
		}
		_ => {
			crash "spanning grid disagrees for ${Str.inspect(shapes)} / ${Str.inspect(partition)}: ${Str.inspect(checked)}"
		}
	}
}

span_headers : List(PlacedSpan), PlacedSpan -> List(U64)
span_headers = |cells, target| {
	columns = cells.keep_if(
		|candidate| match candidate.cell.kind {
			Data => False
			Header(scope) => scope != Row and candidate.row < target.row and candidate.column < target.column + target.cell.column_span and target.column < candidate.column + candidate.cell.column_span
		},
	)
	rows = cells.keep_if(
		|candidate| match candidate.cell.kind {
			Data => False
			Header(scope) => scope != Column and candidate.ordinal != target.ordinal and candidate.row <= target.row and candidate.row + candidate.cell.height > target.row and (target.cell.kind == Data or candidate.ordinal < target.ordinal)
		},
	)
	List.concat(columns, rows).map(|cell| cell.ordinal)
}

expect {
	report = Model.explore(span_machine, { depth: 5, key: |world| (world.partition, world.rows), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1201 and report.steps == 1200 and report.depth == 4 and report.reached.len() == 7
}
