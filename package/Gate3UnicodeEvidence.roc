import KernelEmit
import KernelStructure
import KernelUnicode

Gate3UnicodeEvidence :: [].{
	unicode_analysis : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRepetitions])
	unicode_analysis = |repetitions| {
		if repetitions == 0 or repetitions > 100000 {
			return Err(InvalidRepetitions)
		}

		pattern = Str.to_utf8("a é漢 ")
		var $source_bytes = List.with_capacity(pattern.len() * repetitions)
		var $repetition = 0
		while $repetition < repetitions {
			var $byte_index = 0
			while $byte_index < pattern.len() {
				match pattern.get($byte_index) {
					Err(OutOfBounds) => return Err(EvidenceFailure)
					Ok(byte) => {
						$source_bytes = $source_bytes.append(byte)
					}
				}
				$byte_index = $byte_index + 1
			}
			$repetition = $repetition + 1
		}

		source = Str.from_utf8($source_bytes) ? |_| EvidenceFailure
		analysis = KernelUnicode.analyze(
			source,
			{
				max_graphemes: repetitions * 5,
				max_line_boundaries: repetitions * 6 + 1,
				max_scalars: repetitions * 6,
				max_script_runs: repetitions * 4,
			},
		) ? |_| EvidenceFailure
		plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure

		Ok({
			bytes,
			work: [
				repetitions,
				source.count_utf8_bytes(),
				analysis.work.scalar_visits,
				analysis.work.grapheme_visits,
				analysis.work.line_boundary_visits,
				analysis.work.script_run_visits,
			],
		})
	}
}

expect {
	result = Gate3UnicodeEvidence.unicode_analysis(2)?
	result.work == [2, 18, 12, 10, 13, 5]
}
