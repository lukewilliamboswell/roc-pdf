import pdf.Font
import pdf.KernelEmit
import pdf.KernelFont
import pdf.KernelGsub
import pdf.KernelLineLayout
import pdf.KernelShape
import pdf.KernelStructure
import pdf.KernelUnicode
import pdf.Layout
import pdf.Semantics
import pdf.Text
import "../../vendor/fonts/RocPdfSans-Regular.ttf" as built_in_font_bytes : List(U8)

Fixture :: [].{
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
	result = Fixture.shaping(0)?
	result.work.len() == 22
}

## A declared ligature cluster cannot enter the advanced boundary on a raw
## glyph ID alone. Its GSUB fact proves the selected `ccmp` lookup and is then
## consumed against the exact cluster, feature, and painted glyph.
expect {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	)?
	base = match KernelFont.glyph_for_scalar(font, 0x0041) {
		Some(glyph) => glyph
		None => crash "built-in GSUB fixture lost A"
	}
	grave = match KernelFont.glyph_for_scalar(font, 0x0300) {
		Some(glyph) => glyph
		None => crash "built-in GSUB fixture lost combining grave"
	}
	fact = KernelGsub.validate_ligature(
		font,
		{ feature: 0x63636d70, input: [base, grave], language: Default, output: 5, script: 0x6c61746e },
		KernelGsub.Limits.make({ max_feature_lookups: 8, max_ligature_components: 8, max_ligatures: 128, max_subtables: 16 }),
	)?.fact
	validated = KernelShape.validate_advanced_with_ligature_fact(
		font,
		"À",
		advanced_store,
		{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(1) },
		fact,
		KernelShape.AdvancedLimits.make({ max_clusters: 8, max_glyph_indices: 8, max_glyphs: 8, max_runs: 4, max_scalars: 8, max_source_bytes: 32, max_substitutions: 4, max_transformations: 4 }),
	)?
	validated.store.glyphs.len() == 1
}

## The same otherwise-valid cluster is rejected when the retained GSUB fact
## names a different painted output glyph.
expect {
	font = KernelFont.inspect(
		built_in_font_bytes,
		KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }),
	)?
	base = match KernelFont.glyph_for_scalar(font, 0x0041) {
		Some(glyph) => glyph
		None => crash "built-in GSUB fixture lost A"
	}
	grave = match KernelFont.glyph_for_scalar(font, 0x0300) {
		Some(glyph) => glyph
		None => crash "built-in GSUB fixture lost combining grave"
	}
	fact = KernelGsub.validate_ligature(
		font,
		{ feature: 0x63636d70, input: [base, grave], language: Default, output: 5, script: 0x6c61746e },
		KernelGsub.Limits.make({ max_feature_lookups: 8, max_ligature_components: 8, max_ligatures: 128, max_subtables: 16 }),
	)?.fact
	match KernelShape.validate_advanced_with_ligature_fact(
		font,
		"À",
		advanced_store,
		{ instance: Font.InstanceId.from_index(0), occurrence: Semantics.OccurrenceId.from_index(1) },
		{ ..fact, output: 6 },
		KernelShape.AdvancedLimits.make({ max_clusters: 8, max_glyph_indices: 8, max_glyphs: 8, max_runs: 4, max_scalars: 8, max_source_bytes: 32, max_substitutions: 4, max_transformations: 4 }),
	) {
		Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 })) => True
		_ => False
	}
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
		{ occurrence: Semantics.OccurrenceId.from_index(3), size: Layout.Unit.from_raw(11000), source: Semantics.TextSourceId.from_index(1) },
	]
	batch = KernelShape.shape_simple_batch(font, sources, batch_options, requests, KernelShape.Limits.make({ max_clusters: 5, max_glyphs: 5, max_scalars: 5, max_source_bytes: 7 }))?
	first = list_at(batch.store.runs, 0)
	second = list_at(batch.store.runs, 1)
	third = list_at(batch.store.runs, 2)
	fourth = list_at(batch.store.runs, 3)
	second_lines = KernelLineLayout.Plan.build_run(
		analysis_c,
		batch.store,
		Text.RunId.from_index(1),
		Layout.Unit.from_raw(20000),
		KernelLineLayout.Limits.make({ max_boundaries: 2, max_candidates: 1, max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_lines: 1 }),
	)?
	second_line = list_at(KernelLineLayout.Plan.lines(second_lines), 0)
	line_limits = KernelLineLayout.Limits.make({ max_boundaries: 3, max_candidates: 2, max_clusters: 2, max_glyph_indices: 2, max_glyphs: 2, max_lines: 1 })
	line_requests = [
		{ source: Semantics.TextSourceId.from_index(0), width: Layout.Unit.from_raw(20000) },
		{ source: Semantics.TextSourceId.from_index(1), width: Layout.Unit.from_raw(20000) },
		{ source: Semantics.TextSourceId.from_index(2), width: Layout.Unit.from_raw(20000) },
		{ source: Semantics.TextSourceId.from_index(1), width: Layout.Unit.from_raw(20000) },
	]
	line_batch = KernelLineLayout.BatchPlan.build(
		sources,
		requests,
		batch.store,
		line_requests,
		KernelLineLayout.BatchLimits.make({ line: line_limits, max_key_probes: 16, max_lines: 4, max_runs: 4, max_table_slots: 8, max_templates: 3 }),
	)?
	line_work = KernelLineLayout.BatchPlan.work(line_batch)
	line_ranges = KernelLineLayout.BatchPlan.run_lines(line_batch)
	lines = KernelLineLayout.BatchPlan.lines(line_batch)
	last_line = list_at(lines, 3)
	dense = batch.store.glyph_indices == [0, 1, 2, 3, 4] and first.id.index() == 0 and first.clusters.start() == 0 and first.clusters.length() == 2 and second.id.index() == 1 and second.clusters.start() == 2 and second.clusters.length() == 1 and third.id.index() == 2 and third.clusters.start() == 3 and third.clusters.length() == 1 and fourth.id.index() == 3 and fourth.clusters.start() == 4 and fourth.clusters.length() == 1
	bounded = match KernelShape.shape_simple_batch(font, sources, batch_options, requests, KernelShape.Limits.make({ max_clusters: 4, max_glyphs: 4, max_scalars: 2, max_source_bytes: 6 })) {
		Err(LimitExceeded({ attempted: 3, dimension: Scalars, limit: 2 })) => True
		_ => False
	}
	probe_bounded = match KernelLineLayout.BatchPlan.build(
		sources,
		requests,
		batch.store,
		line_requests,
		KernelLineLayout.BatchLimits.make({ line: line_limits, max_key_probes: 0, max_lines: 4, max_runs: 4, max_table_slots: 8, max_templates: 3 }),
	) {
		Err(LimitExceeded({ attempted: 1, dimension: KeyProbes, limit: 0 })) => True
		_ => False
	}

	dense and bounded and probe_bounded and second_line.clusters.start() == 2 and second_line.clusters.length() == 1 and second_line.source.scalars.start() == 0 and second_line.source.scalars.length() == 1 and list_at(line_ranges, 3).start() == 3 and last_line.clusters.start() == 4 and last_line.source.scalars.start() == 0 and line_work.boundary_visits == 7 and line_work.cache_hits == 1 and line_work.cluster_visits == 4 and line_work.line_writes == 4 and line_work.run_visits == 4 and line_work.table_slots == 8 and line_work.templates == 3 and batch.work.scalar_visits == 5 and batch.work.glyph_visits == 5 and batch.work.metric_reads == 4 and batch.work.script_run_visits == 3 and batch.advances.len() == 4
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "text-layout shape evidence index escaped"
	}
	Ok(value) => value
}
