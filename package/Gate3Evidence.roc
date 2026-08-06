import KernelEmit
import KernelFont
import KernelStructure
import KernelUnicode
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3Evidence :: [].{
	font_inspection : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	font_inspection = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({
				max_bytes: 200000,
				max_cmap_mappings: 10000,
				max_glyphs: 10000,
				max_tables: 32,
			}),
		) ? |_| EvidenceFailure
		glyph_a = match KernelFont.glyph_for_scalar(font, 0x41) {
			None => return Err(EvidenceFailure)
			Some(glyph) => glyph
		}
		width_a = KernelFont.advance_width(font, glyph_a) ? |_| EvidenceFailure
		plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
		bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
		Ok({
			bytes,
			work: [
				font.bytes.len(),
				font.tables.len(),
				font.metrics.glyph_count,
				font.coverage.len(),
				font.work.checksum_bytes,
				font.work.cmap_mapping_visits,
				font.work.loca_entries,
				font.work.overlap_comparisons,
				font.work.glyph_visits,
				font.work.component_edge_visits,
				glyph_a.to_u64(),
				width_a.to_u64(),
			],
		})
	}

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
	result = Gate3Evidence.unicode_analysis(2)?
	result.work == [2, 18, 12, 10, 13, 5]
}

expect {
	result = Gate3Evidence.font_inspection(0)?
	result.work.len() == 12
}
