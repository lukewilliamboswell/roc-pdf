import Font
import KernelEmit
import KernelFont
import KernelShape
import KernelStructure
import KernelUnicode
import Layout
import Semantics
import Text
import "../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Gate3ShapeEvidence :: [].{
	shaping : U64 -> Try({ bytes : List(U8), work : List(U64) }, [EvidenceFailure, InvalidRuntimeGuard])
	shaping = |runtime_guard| {
		if runtime_guard != 0 {
			return Err(InvalidRuntimeGuard)
		}
		source = "Café PDF"
		analysis = KernelUnicode.analyze(
			source,
			{
				max_graphemes: 32,
				max_line_boundaries: 33,
				max_scalars: 32,
				max_script_runs: 8,
			},
		) ? |_| EvidenceFailure
		font = KernelFont.inspect(
			built_in_font_bytes,
			KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
		) ? |_| EvidenceFailure
		shape = KernelShape.shape_simple(
			font,
			source,
			analysis,
			{
				direction: LeftToRight,
				instance: Font.InstanceId.from_index(0),
				language: Language("en-AU"),
				occurrence: Semantics.OccurrenceId.from_index(0),
				script: Font.Script.from_iso15924("Latn"),
				size: Layout.Unit.from_raw(11000),
				writing_mode: Horizontal,
			},
			KernelShape.Limits.make({ max_clusters: 32, max_glyphs: 32, max_scalars: 32, max_source_bytes: 128 }),
		) ? |_| EvidenceFailure
		advanced_source = "À"
		advanced = KernelShape.validate_advanced(
			font,
			advanced_source,
			advanced_store,
			{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(1) },
			KernelShape.AdvancedLimits.make({
				max_clusters: 8,
				max_glyph_indices: 8,
				max_glyphs: 8,
				max_runs: 4,
				max_scalars: 8,
				max_source_bytes: 32,
				max_substitutions: 4,
				max_transformations: 4,
			}),
		) ? |_| EvidenceFailure
		bytes = blank_pdf(runtime_guard)?
		Ok({
			bytes,
			work: [
				font.bytes.len(),
				shape.work.utf8_bytes,
				analysis.work.scalar_visits,
				analysis.work.grapheme_visits,
				analysis.work.script_run_visits,
				shape.work.scalar_visits,
				shape.work.cluster_visits,
				shape.work.glyph_visits,
				shape.work.metric_reads,
				shape.store.runs.len(),
				shape.store.glyphs.len(),
				shape.advance.raw().to_u64_wrap(),
				shape.store.glyphs.fold(0, |sum, glyph| sum + glyph.id.raw().to_u64()),
				advanced.work.utf8_bytes,
				advanced.work.scalar_visits,
				advanced.work.run_visits,
				advanced.work.cluster_visits,
				advanced.work.glyph_visits,
				advanced.work.glyph_index_visits,
				advanced.work.auxiliary_visits,
				advanced.store.glyphs.fold(0, |sum, glyph| sum + glyph.id.raw().to_u64()),
				bytes.len(),
			],
		})
	}
}

advanced_store : Text.Store
advanced_store = {
	clusters: [
		{
			glyphs: Semantics.Range.from_start_and_length(0, 1),
			kind: Ligature,
			source: {
				scalars: Semantics.Range.from_start_and_length(0, 2),
				utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
			},
		},
	],
	glyph_indices: [0],
	glyphs: [
		{
			advance_x: Layout.Unit.from_raw(7589),
			advance_y: Layout.Unit.from_raw(0),
			id: Text.GlyphId.from_raw(5),
			offset_x: Layout.Unit.from_raw(0),
			offset_y: Layout.Unit.from_raw(0),
		},
	],
	runs: [
		{
			actual_text: FromOccurrence,
			clusters: Semantics.Range.from_start_and_length(0, 1),
			direction: LeftToRight,
			glyphs: Semantics.Range.from_start_and_length(0, 1),
			id: Text.RunId.from_index(0),
			instance: Font.InstanceId.from_index(0),
			language: Language("en-AU"),
			occurrence: Semantics.OccurrenceId.from_index(1),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(11000),
			source: {
				scalars: Semantics.Range.from_start_and_length(0, 2),
				utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
			},
			substitutions: Semantics.Range.from_start_and_length(0, 1),
			transformations: Semantics.Range.from_start_and_length(0, 0),
			writing_mode: Horizontal,
		},
	],
	substitutions: [
		{
			feature: Text.FeatureTag.from_raw(0x63636d70),
			glyphs: Semantics.Range.from_start_and_length(0, 1),
			source: {
				scalars: Semantics.Range.from_start_and_length(0, 2),
				utf8_bytes: Semantics.Range.from_start_and_length(0, 3),
			},
		},
	],
	transformations: [],
}

blank_pdf : U64 -> Try(List(U8), [EvidenceFailure, InvalidRuntimeGuard])
blank_pdf = |runtime_guard| {
	if runtime_guard != 0 {
		return Err(InvalidRuntimeGuard)
	}
	plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
	Ok(bytes)
}

expect {
	result = Gate3ShapeEvidence.shaping(0)?
	result.work.len() == 22
}

expect {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	)?
	base_cluster = list_at(advanced_store.clusters, 0)
	base_glyph = list_at(advanced_store.glyphs, 0)
	duplicate_store = {
		..advanced_store,
		clusters: [{ ..base_cluster, glyphs: Semantics.Range.from_start_and_length(0, 2), kind: ManyToMany }],
		glyph_indices: [0, 0],
	}
	notdef_store = { ..advanced_store, glyphs: [{ ..base_glyph, id: Text.GlyphId.from_raw(0) }] }
	base_run = list_at(advanced_store.runs, 0)
	bad_size_store = { ..advanced_store, runs: [{ ..base_run, size: Layout.Unit.from_raw(0) }] }
	bad_source_store = {
		..advanced_store,
		clusters: [
			{
				..base_cluster,
				source: {
					scalars: Semantics.Range.from_start_and_length(0, 2),
					utf8_bytes: Semantics.Range.from_start_and_length(0, 2),
				},
			},
		],
	}
	context = { instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(1) }
	limits = KernelShape.AdvancedLimits.make({
		max_clusters: 8,
		max_glyph_indices: 8,
		max_glyphs: 8,
		max_runs: 4,
		max_scalars: 8,
		max_source_bytes: 32,
		max_substitutions: 4,
		max_transformations: 4,
	})
	duplicate_rejected = match KernelShape.validate_advanced(font, "À", duplicate_store, context, limits) {
		Err(DuplicateGlyphReference({ glyph: 0, run: 0 })) => Bool.True
		_ => Bool.False
	}
	notdef_rejected = match KernelShape.validate_advanced(font, "À", notdef_store, context, limits) {
		Err(AdvancedGlyphInvalid({ glyph: 0, reason: GlyphId })) => Bool.True
		_ => Bool.False
	}
	source_rejected = match KernelShape.validate_advanced(font, "À", bad_source_store, context, limits) {
		Err(AdvancedClusterInvalid({ cluster: 0, reason: SourceRange })) => Bool.True
		_ => Bool.False
	}
	size_rejected = match KernelShape.validate_advanced(font, "À", bad_size_store, context, limits) {
		Err(AdvancedRunInvalid({ reason: Size, run: 0 })) => Bool.True
		_ => Bool.False
	}
	duplicate_rejected and notdef_rejected and source_rejected and size_rejected
}

## Batch shaping writes dense global ranges and glyph indices without a
## temporary Text.Store per source.
expect {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	)?
	analysis_ab = KernelUnicode.analyze("AB", { max_graphemes: 2, max_line_boundaries: 3, max_scalars: 2, max_script_runs: 1 })?
	analysis_c = KernelUnicode.analyze("C", { max_graphemes: 1, max_line_boundaries: 2, max_scalars: 1, max_script_runs: 1 })?
	analysis_bullet = KernelUnicode.analyze("•", { max_graphemes: 1, max_line_boundaries: 2, max_scalars: 1, max_script_runs: 1 })?
	batch_options = {
		direction: LeftToRight,
		instance: Font.InstanceId.from_index(0),
		language: Language("en-AU"),
		script: Font.Script.from_iso15924("Latn"),
		writing_mode: Horizontal,
	}
	sources = [
		{ analysis: analysis_ab, unicode: "AB" },
		{ analysis: analysis_c, unicode: "C" },
		{ analysis: analysis_bullet, unicode: "•" },
	]
	requests = [
		{ occurrence: Semantics.OccurrenceId.from_index(0), size: Layout.Unit.from_raw(11000), source: Semantics.TextSourceId.from_index(0) },
		{ occurrence: Semantics.OccurrenceId.from_index(1), size: Layout.Unit.from_raw(11000), source: Semantics.TextSourceId.from_index(1) },
		{ occurrence: Semantics.OccurrenceId.from_index(2), size: Layout.Unit.from_raw(11000), source: Semantics.TextSourceId.from_index(2) },
	]
	batch = KernelShape.shape_simple_batch(font, sources, batch_options, requests, KernelShape.Limits.make({ max_clusters: 4, max_glyphs: 4, max_scalars: 4, max_source_bytes: 6 }))?
	first = list_at(batch.store.runs, 0)
	second = list_at(batch.store.runs, 1)
	third = list_at(batch.store.runs, 2)
	dense = batch.store.glyph_indices == [0, 1, 2, 3] and first.id.index() == 0 and first.clusters.start() == 0 and first.clusters.length() == 2 and second.id.index() == 1 and second.clusters.start() == 2 and second.clusters.length() == 1 and third.id.index() == 2 and third.clusters.start() == 3 and third.clusters.length() == 1
	bounded = match KernelShape.shape_simple_batch(font, sources, batch_options, requests, KernelShape.Limits.make({ max_clusters: 4, max_glyphs: 4, max_scalars: 2, max_source_bytes: 6 })) {
		Err(LimitExceeded({ attempted: 3, dimension: Scalars, limit: 2 })) => True
		_ => False
	}

	dense and bounded and batch.work.scalar_visits == 4 and batch.work.glyph_visits == 4 and batch.work.metric_reads == 4 and batch.work.script_run_visits == 3 and batch.advances.len() == 3
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "Gate 3 shape evidence index escaped"
	}
	Ok(value) => value
}
