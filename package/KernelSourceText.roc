import Semantics

## Preformatted source preparation. The canonical source retains LF line
## separators, indentation, trailing spaces and empty lines. CRLF becomes LF;
## a bare CR is rejected. Tabs either reject or expand to explicit spaces at
## scalar-column tab stops. No width, glyph or page facts are inferred here.
## The output owns one UTF-8 buffer and a dense line-range buffer. Later
## stages consume these ranges rather than splitting or rescanning the text.
KernelSourceText :: [].{
	Tabs : [ExpandTo(U16), RejectTabs]
	Dimension : [InputBytes, Lines, OutputBytes]
	Error : [
		BareCarriageReturn({ byte : U64 }),
		InvalidTabWidth,
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		TabRejected({ byte : U64 }),
	]
	Limits : { max_input_bytes : U64, max_lines : U64, max_output_bytes : U64 }
	Line : { scalars : Semantics.Range, utf8_bytes : Semantics.Range }
	Work : { input_bytes : U64, line_writes : U64, output_bytes : U64, tab_spaces : U64 }
	Prepared : { lines : List(Line), text : Str, work : Work }

	prepare : Str, Tabs, Limits -> Try(Prepared, Error)
	prepare = |text, tabs, limits| prepare_source(text, tabs, limits)
}

prepare_source : Str, KernelSourceText.Tabs, KernelSourceText.Limits -> Try(KernelSourceText.Prepared, KernelSourceText.Error)
prepare_source = |text, tabs, limits| {
	input = text.to_utf8()
	check_limit(input.len(), limits.max_input_bytes, InputBytes)?
	width = match tabs {
		ExpandTo(0) => return Err(InvalidTabWidth)
		ExpandTo(value) => value.to_u64()
		RejectTabs => 1
	}
	check_limit(1, limits.max_lines, Lines)?
	var $bytes = List.with_capacity(U64.min(input.len(), limits.max_output_bytes))
	var $lines = []
	var $cursor = 0
	var $line_byte = 0
	var $line_scalar = 0
	var $scalars = 0
	var $column = 0
	var $tab_spaces = 0
	while $cursor < input.len() {
		byte = list_at(input, $cursor)
		if byte == 13 or byte == 10 {
			if byte == 13 {
				if $cursor + 1 >= input.len() or list_at(input, $cursor + 1) != 10 {
					return Err(BareCarriageReturn({ byte: $cursor }))
				}
				$cursor = $cursor + 1
			}
			check_limit($lines.len() + 2, limits.max_lines, Lines)?
			check_limit($bytes.len() + 1, limits.max_output_bytes, OutputBytes)?
			line = {
				scalars: Semantics.Range.from_start_and_length($line_scalar, $scalars - $line_scalar),
				utf8_bytes: Semantics.Range.from_start_and_length($line_byte, $bytes.len() - $line_byte),
			}
			$lines = $lines.append(line)
			$bytes = $bytes.append(10)
			$scalars = $scalars + 1
			$line_byte = $bytes.len()
			$line_scalar = $scalars
			$column = 0
		} else if byte == 9 {
			match tabs {
				RejectTabs => return Err(TabRejected({ byte: $cursor }))
				ExpandTo(_) => {}
			}
			spaces = width - $column % width
			if $bytes.len() > limits.max_output_bytes or spaces > limits.max_output_bytes - $bytes.len() {
				return Err(LimitExceeded({ attempted: $bytes.len() + spaces, dimension: OutputBytes, limit: limits.max_output_bytes }))
			}
			var $remaining = spaces
			while $remaining > 0 {
				$bytes = $bytes.append(32)
				$remaining = $remaining - 1
			}
			$scalars = $scalars + spaces
			$column = $column + spaces
			$tab_spaces = $tab_spaces + spaces
		} else {
			check_limit($bytes.len() + 1, limits.max_output_bytes, OutputBytes)?
			$bytes = $bytes.append(byte)
			# UTF-8 continuation bytes do not advance a scalar column.
			if byte < 128 or byte >= 192 {
				$scalars = $scalars + 1
				$column = $column + 1
			}
		}
		$cursor = $cursor + 1
	}
	$lines = $lines.append({
		scalars: Semantics.Range.from_start_and_length($line_scalar, $scalars - $line_scalar),
		utf8_bytes: Semantics.Range.from_start_and_length($line_byte, $bytes.len() - $line_byte),
	})
	output_bytes = $bytes.len()
	canonical = match Str.from_utf8($bytes) {
		Ok(value) => value
		Err(_) => crash "source preparation corrupted validated UTF-8"
	}
	Ok({ lines: $lines, text: canonical, work: { input_bytes: input.len(), line_writes: $lines.len(), output_bytes, tab_spaces: $tab_spaces } })
}

check_limit : U64, U64, KernelSourceText.Dimension -> Try({}, KernelSourceText.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "validated source byte index escaped"
}

test_limits : KernelSourceText.Limits
test_limits = { max_input_bytes: 4096, max_lines: 100, max_output_bytes: 8192 }

expect match KernelSourceText.prepare("\tα\r\n\n  x  \n", ExpandTo(4), test_limits) {
	Ok(prepared) => prepared.text == "    α\n\n  x  \n" and prepared.lines.len() == 4 and list_at(prepared.lines, 1).scalars.length() == 0 and list_at(prepared.lines, 2).scalars.length() == 5 and prepared.work.tab_spaces == 4
	Err(_) => False
}

expect match KernelSourceText.prepare("", ExpandTo(4), test_limits) {
	Ok(prepared) => prepared.text.is_empty() and prepared.lines.len() == 1 and list_at(prepared.lines, 0).utf8_bytes.length() == 0
	Err(_) => False
}

expect match KernelSourceText.prepare("a\rb", ExpandTo(4), test_limits) {
	Err(BareCarriageReturn({ byte: 1 })) => True
	_ => False
}

expect match KernelSourceText.prepare("a\t", RejectTabs, test_limits) {
	Err(TabRejected({ byte: 1 })) => True
	_ => False
}

expect match KernelSourceText.prepare("\t", ExpandTo(0), test_limits) {
	Err(InvalidTabWidth) => True
	_ => False
}

expect match KernelSourceText.prepare("\t", ExpandTo(4), { ..test_limits, max_output_bytes: 3 }) {
	Err(LimitExceeded({ attempted: 4, dimension: OutputBytes, limit: 3 })) => True
	_ => False
}

expect match KernelSourceText.prepare("a\n", ExpandTo(4), { ..test_limits, max_lines: 1 }) {
	Err(LimitExceeded({ attempted: 2, dimension: Lines, limit: 1 })) => True
	_ => False
}
