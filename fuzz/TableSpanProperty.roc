import fuzz.Fuzz
import pdf.Layout
import pdf.Document
import pdf.Pdf

TableSpanProperty :: [].{
	target = Fuzz.target({
		name: "roc-pdf-table-spans",
		examples: [
			Fuzz.example({ name: "variable-cell-heights", revision: "1", make: || Input.{ mode: 0, rows: [1, 9, 17, 37, 50, 68, 91, 255] } }),
			Fuzz.example({ name: "overlap-with-carried-column", revision: "1", make: || Input.{ mode: 1, rows: [99, 14, 8] } }),
			Fuzz.example({ name: "unknown-explicit-header", revision: "1", make: || Input.{ mode: 2, rows: [0, 7, 8] } }),
			Fuzz.example({ name: "explicit-reference-to-data", revision: "1", make: || Input.{ mode: 3, rows: [14, 15] } }),
			Fuzz.example({ name: "row-extent-near-u16-limit", revision: "1", make: || Input.{ mode: 4, rows: [0] } }),
			Fuzz.example({ name: "column-extent-near-u16-limit", revision: "1", make: || Input.{ mode: 5, rows: [0] } }),
		],
		test,
		show: |input| Str.inspect(input),
	})
}

Input := { mode : U8, rows : List(U8) }.{
	parser_for : _
	encoder_for : _
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { mode: Fuzz.u8, rows: Fuzz.list(Fuzz.u8, 40) }.Fuzz
}

render : Input -> Document
render = |input| {
	mode = input.mode % 6
	rows = if (input.rows.is_empty()) [0] else input.rows
	column = { width: Fixed(90), align: Start }
	head = Pdf.row([
		Pdf.header_cell(Column, [Pdf.text("Item")]),
		Pdf.header_cell_with([Pdf.text("Group")], { scope: Column, layout: { key: Named("group") } }),
		Pdf.header_cell(Column, [Pdf.text("Details")]),
	])
	var $body = List.with_capacity(rows.len() * 2)
	var $index = 0
	for byte in rows {
		key = "region-${$index.to_str()}"
		data_key = "item-${$index.to_str()}"
		bad = $index == 0
		row_span = if (mode == 4 and bad) 65535 else 2
		column_span = if (mode == 5 and bad) 65535 else 1
		region = Pdf.header_cell_with([Pdf.text("District ${$index.to_str()}")], { scope: Row, layout: { row_span, column_span, key: Named(key) } })
		item = Pdf.cell_with([Pdf.text("Orders")], { key: Named(data_key) })
		header_keys = if bad and mode == 2 {
			["unknown"]
		} else if bad and mode == 3 {
			[data_key]
		} else {
			["group", key]
		}
		fanout = byte % 5
		var $details = [Pdf.text("Received")]
		var $line = 0
		while $line < fanout {
			$details = $details.append(Pdf.line_break).append(Pdf.text("Scheduled"))
			$line = $line + 1
		}
		$body = $body.append(Pdf.row([item, region, Pdf.cell_with($details, { headers: Explicit(header_keys) })]))
		following = if (bad and mode == 1) [Pdf.cell([Pdf.text("Overlap")]).spanning(2)] else [Pdf.cell([Pdf.text("Stock")]), Pdf.cell([Pdf.text("Available")])]
		$body = $body.append(Pdf.row(following))
		$index = $index + 1
	}
	table = Pdf.table({ columns: [column, column, column], header_rows: [head], body_rows: $body, caption: Pdf.no_caption, row_split: SplitSpans })
	Pdf.document({ contents: [table], title: "District schedule", language: "en" })
}

test : Input -> Fuzz.Outcome
test = |input| {
	document = render(input)
	options = Pdf.Options.{ page_size: Custom({ height: Layout.Unit.points(300), width: Layout.Unit.points(500) }) }
	match (Pdf.to_bytes_with(document, options), Pdf.to_chunks_with(document, options), input.mode % 6) {
		(Ok(bytes), Ok(chunks), 0) if matches_chunks(chunks, bytes) => Fuzz.keep
		(Err(InvalidDocument({ diagnostics: [{ feature: Feature(left), .. }], .. })), Err(InvalidDocument({ diagnostics: [{ feature: Feature(right), .. }], .. })), mode) => {
			expected = if (mode == 2 or mode == 3) "table.header_targets" else "table.span_extent"
			if mode != 0 and left == expected and right == expected {
				return Fuzz.keep
			}
			crash "span rejection returned the wrong diagnostic: ${left} / ${right}"
		}
		_ => crash "grid accepted an invalid span or lost bytes in the sink path"
	}
}

matches_chunks : Pdf.Encode, List(U8) -> Bool
matches_chunks = |initial, expected| {
	var $encoder = initial
	var $offset = 0
	while True {
		match Pdf.next_chunk($encoder) {
			Done => return $offset == expected.len()
			Emit(chunk, next) => {
				if chunk != expected.sublist({ start: $offset, len: chunk.len() }) {
					return False
				}
				$offset = $offset + chunk.len()
				$encoder = next
			}
		}
	}
}
