import pdf.KernelEmit
import pdf.KernelSourceText
import pdf.KernelStructure

## The source_text family's typed cases and their dispatch, run by a fixture group app.
Cases :: [].{
	Case : { repetitions : U64 }

	run : Case -> { bytes : List(U8), work : List(U64) }
	run = |case| {
		if case.repetitions == 0 or case.repetitions > 1000 {
			crash "CASE_SPEC_INVALID: source_text"
		}
		# One append-only source buffer and one dense line arena; construction is
		# included in the measurement, with no list of copied line strings.
		var $input = []
		var $repeat = 0
		while $repeat < case.repetitions {
			for byte in "\tα\r\n\n  x  \n".to_utf8() {
				$input = $input.append(byte)
			}
			$repeat = $repeat + 1
		}
		input = match Str.from_utf8($input) {
			Ok(value) => value
			Err(_) => crash "SOURCE_ENCODING"
		}
		limits = { max_input_bytes: 100000, max_lines: 10000, max_output_bytes: 200000 }
		prepared = match KernelSourceText.prepare(input, ExpandTo(4), limits) {
			Ok(value) => value
			Err(_) => crash "SOURCE_PREPARATION"
		}
		if prepared.lines.len() != 3 * case.repetitions + 1 or prepared.work.tab_spaces != 4 * case.repetitions {
			crash "SOURCE_LINES_OR_TABS"
		}
		var $index = 0
		var $byte_cursor = 0
		var $scalar_cursor = 0
		while $index < prepared.lines.len() {
			line = match prepared.lines.get($index) {
				Ok(value) => value
				Err(_) => crash "SOURCE_LINE_RANGE"
			}
			expected_scalars = if ($index == prepared.lines.len() - 1) 0 else match $index % 3 {
				0 => 5
				1 => 0
				_ => 5
			}
			expected_bytes = expected_scalars + (if ($index % 3 == 0 and $index < prepared.lines.len() - 1) 1 else 0)
			if line.scalars.start() != $scalar_cursor or line.utf8_bytes.start() != $byte_cursor or line.scalars.length() != expected_scalars or line.utf8_bytes.length() != expected_bytes {
				crash "SOURCE_EXACT_RANGES"
			}
			$byte_cursor = $byte_cursor + expected_bytes + 1
			$scalar_cursor = $scalar_cursor + expected_scalars + 1
			$index = $index + 1
		}
		if prepared.text.count_utf8_bytes() != $byte_cursor - 1 {
			crash "SOURCE_EXACT_BYTES"
		}
		# Atomic errors are part of each case; no partial Prepared can escape.
		rejections = [
			KernelSourceText.prepare("a\rb", ExpandTo(4), limits).is_err(),
			KernelSourceText.prepare("a\t", RejectTabs, limits).is_err(),
			KernelSourceText.prepare("", ExpandTo(0), limits).is_err(),
			KernelSourceText.prepare("\t", ExpandTo(4), { ..limits, max_output_bytes: 3 }).is_err(),
			KernelSourceText.prepare("a\n", ExpandTo(4), { ..limits, max_lines: 1 }).is_err(),
			KernelSourceText.prepare("aa", ExpandTo(4), { ..limits, max_input_bytes: 1 }).is_err(),
		]
		for rejected in rejections {
			if !rejected {
				crash "SOURCE_ATOMIC_REJECTION"
			}
		}
		plan = match KernelStructure.build_blank(U64.min(case.repetitions, 1), A4) {
			Ok(value) => value
			Err(_) => crash "SOURCE_EVIDENCE_PLAN"
		}
		bytes = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => crash "SOURCE_EVIDENCE_BYTES"
		}
		{ bytes, work: [prepared.work.input_bytes, prepared.work.output_bytes, prepared.work.line_writes, prepared.work.tab_spaces, $index, rejections.len()] }
	}
}
