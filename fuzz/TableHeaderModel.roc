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

# ISO 32000-2:2020+EC3 14.8.4.8.3 and Table 371 allow implicit lookup
# when a cell omits Headers. Explicit Table attributes are in 14.8.5.7,
# Table 384. The order and applicability here are the facade's contract
# in development/performance/tables.md. Rescan authored rectangles once
# per data cell, so a spanning header contributes at most one identity.
expected_headers : List(Rectangle), Rectangle -> List(U64)
expected_headers = |cells, target| match target.cell.role {
	Header(_) => []
	Data => cells.keep_if(
		|candidate|
			match candidate.cell.role {
				Header(scope) =>
					(candidate.row < target.row and (scope == Column or scope == Both) and candidate.left < target.right and target.left < candidate.right)
						or (candidate.row == target.row and (scope == Row or scope == Both))
				Data => False
			},
	).map(|candidate| candidate.id)
}

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
		Err(error) => {
			dbg "authored table failed semantic planning: ${Str.inspect(error)}"
			return False
		}
	}
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(plan)))
	cells = rectangles(rows)
	headers = cells.map(|cell| expected_headers(cells, cell))
	nodes = store.nodes.keep_if(|node| node.role.local_name == "TH" or node.role.local_name == "TD")
	if nodes.len() != cells.len() {
		dbg "wrong number of semantic cells"
		return False
	}
	for cell in cells {
		node = nodes.get(cell.id) ?? crash "missing planned cell"
		linked = headers.get(cell.id) ?? crash "missing model cell"
		attributes = store.attributes.sublist({ start: node.attributes.start(), len: node.attributes.length() })
		required = cell_attributes(cell.cell, linked)
		role = if (cell.cell.role == Data) "TD" else "TH"
		if node.role.local_name != role or node.element_identifier != HasElementIdentifier(Semantics.ElementId.from_index(cell.id)) or attributes.len() != required.len() or !required.all(|attribute| attributes.contains(attribute)) {
			dbg "cell ${identifier(cell.id)} expects ${Str.inspect(required)}, found ${Str.inspect(attributes)}"
			return False
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
	report.states == 1155 and report.steps == 1154 and report.depth == 4 and report.reached.len() == 5
}
