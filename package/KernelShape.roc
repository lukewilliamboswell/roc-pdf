import Font
import KernelFont
import KernelGsub
import KernelUnicode
import Layout
import Semantics
import Text
import unicode.ByteRange
import unicode.Scalar

KernelShape :: [].{
	Dimension : [Clusters, GlyphIndices, Glyphs, Runs, Scalars, SourceBytes, Substitutions, Transformations]
	Error : [
		AnalysisMismatch([GraphemeFacts, ScalarFacts, ScriptFacts]),
		ArithmeticOverflow,
		EmptySource,
		InvalidSource({ request : U64, source : U64 }),
		InvalidSize(I64),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MetricFailure(U32),
		MissingGlyph({ scalar : U32, scalar_index : U64 }),
		NotdefGlyph({ scalar : U32, scalar_index : U64 }),
		AdvancedClusterInvalid({ cluster : U64, reason : [Cardinality, GlyphIndexRange, SourceRange] }),
		AdvancedGlyphInvalid({ glyph : U64, reason : [Advance, GlyphId] }),
		AdvancedRunInvalid({ reason : [AuxiliaryRange, ClusterRange, GlyphRange, RunId, Size, SourceRange], run : U64 }),
		DuplicateGlyphReference({ glyph : U64, run : U64 }),
		GlyphOutsideRun({ glyph : U64, run : U64 }),
		InstanceMismatch({ actual : Font.InstanceId, expected : Font.InstanceId, run : U64 }),
		OccurrenceMismatch({ actual : Semantics.OccurrenceId, expected : Semantics.OccurrenceId, run : U64 }),
		UnreferencedGlyph({ glyph : U64, run : U64 }),
		UnsupportedCluster({ grapheme : U64, scalars : U64 }),
		UnsupportedDirection(Text.Direction),
		UnsupportedScript({ actual : Str, expected : Str, run : U64 }),
		UnsupportedWritingMode(Text.WritingMode),
	]

	Limits :: { max_clusters : U64, max_glyphs : U64, max_scalars : U64, max_source_bytes : U64 }.{
		make : { max_clusters : U64, max_glyphs : U64, max_scalars : U64, max_source_bytes : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	AdvancedLimits :: { max_clusters : U64, max_glyph_indices : U64, max_glyphs : U64, max_runs : U64, max_scalars : U64, max_source_bytes : U64, max_substitutions : U64, max_transformations : U64 }.{
		make : { max_clusters : U64, max_glyph_indices : U64, max_glyphs : U64, max_runs : U64, max_scalars : U64, max_source_bytes : U64, max_substitutions : U64, max_transformations : U64 } -> AdvancedLimits
		make = |limits| AdvancedLimits.(limits)
	}

	AdvancedContext : {
		instance : Font.InstanceId,
		occurrence : Semantics.OccurrenceId,
	}

	ValidationWork : {
		auxiliary_visits : U64,
		cluster_visits : U64,
		glyph_index_visits : U64,
		glyph_visits : U64,
		run_visits : U64,
		scalar_visits : U64,
		utf8_bytes : U64,
	}

	Validated : {
		store : Text.Store,
		work : ValidationWork,
	}

	Options : {
		direction : Text.Direction,
		instance : Font.InstanceId,
		language : Semantics.Language,
		occurrence : Semantics.OccurrenceId,
		script : Font.Script,
		size : Layout.Unit,
		writing_mode : Text.WritingMode,
	}

	Work : {
		cluster_visits : U64,
		glyph_visits : U64,
		metric_reads : U64,
		scalar_visits : U64,
		script_run_visits : U64,
		utf8_bytes : U64,
	}

	Shape : {
		advance : Layout.Unit,
		store : Text.Store,
		work : Work,
	}

	SimpleSource : { analysis : KernelUnicode.UnicodeAnalysis, unicode : Str }

	BatchOptions : {
		direction : Text.Direction,
		instance : Font.InstanceId,
		language : Semantics.Language,
		script : Font.Script,
		writing_mode : Text.WritingMode,
	}

	SimpleRequest : { occurrence : Semantics.OccurrenceId, size : Layout.Unit, source : Semantics.TextSourceId }

	Batch : {
		advances : List(Layout.Unit),
		store : Text.Store,
		work : Work,
	}

	## The built-in convenience path is intentionally narrow. It consumes the
	## earlier Unicode analysis, supports horizontal LTR Latin with one scalar
	## per grapheme, and rejects every unsupported relationship explicitly.
	shape_simple : KernelFont.Inspection, Str, KernelUnicode.UnicodeAnalysis, Options, Limits -> Try(Shape, Error)
	shape_simple = |font, source, analysis, options, limits| shape_simple_latin(font, source, analysis, options, limits)

	## Facade shaping writes all run, cluster, glyph-index, and glyph records
	## directly into one dense store rather than materializing one store per
	## authored block.
	shape_simple_batch : KernelFont.Inspection, List(SimpleSource), BatchOptions, List(SimpleRequest), Limits -> Try(Batch, Error)
	shape_simple_batch = |font, sources, options, requests, limits| shape_simple_batch_latin(font, sources, options, requests, limits)

	## Advanced callers supply positioned glyphs, but validation still proves
	## dense IDs, complete source/glyph partitions, cluster cardinalities, exact
	## instance/occurrence ownership, glyph legality, and horizontal advances.
	validate_advanced : KernelFont.Inspection, Str, Text.Store, AdvancedContext, AdvancedLimits -> Try(Validated, Error)
	validate_advanced = |font, source, store, context, limits| validate_advanced_store(font, source, store, context, limits)

	## A GSUB fact is consumed alongside an advanced run when that run claims a
	## ligature. The fact is already font-validated; this boundary proves that it
	## names the run's exact ligature cluster, feature, and painted output glyph.
	validate_advanced_with_ligature_fact : KernelFont.Inspection, Str, Text.Store, AdvancedContext, KernelGsub.Fact, AdvancedLimits -> Try(Validated, Error)
	validate_advanced_with_ligature_fact = |font, source, store, context, fact, limits| {
		validated = validate_advanced_store(font, source, store, context, limits)?
		validate_ligature_fact(validated.store, fact)?
		Ok(validated)
	}
}

shape_simple_latin : KernelFont.Inspection, Str, KernelUnicode.UnicodeAnalysis, KernelShape.Options, KernelShape.Limits -> Try(KernelShape.Shape, KernelShape.Error)
shape_simple_latin = |font, source, analysis, options, limits| {
	if options.direction != LeftToRight {
		return Err(UnsupportedDirection(options.direction))
	}
	if options.writing_mode != Horizontal {
		return Err(UnsupportedWritingMode(options.writing_mode))
	}
	expected_script = options.script.as_str()
	if expected_script != latin_script {
		return Err(UnsupportedScript({ actual: expected_script, expected: latin_script, run: 0 }))
	}
	size = options.size.raw()
	if size <= 0 {
		return Err(InvalidSize(size))
	}

	source_bytes = source.count_utf8_bytes()
	scalar_count = analysis.work.scalar_visits
	cluster_count = analysis.graphemes.len()
	if source_bytes == 0 or scalar_count == 0 or cluster_count == 0 {
		return Err(EmptySource)
	}
	check_limit(source_bytes, limits.max_source_bytes, SourceBytes)?
	check_limit(scalar_count, limits.max_scalars, Scalars)?
	check_limit(scalar_count, limits.max_glyphs, Glyphs)?
	check_limit(cluster_count, limits.max_clusters, Clusters)?
	if cluster_count != scalar_count {
		return Err(AnalysisMismatch(GraphemeFacts))
	}
	validate_scripts(analysis.script_runs, source_bytes, scalar_count, expected_script)?

	var $glyphs = List.with_capacity(scalar_count)
	var $clusters = List.with_capacity(cluster_count)
	var $glyph_indices = List.with_capacity(scalar_count)
	var $total_advance = 0
	var $visited = 0
	for located in Scalar.iter(source) {
		if $visited >= scalar_count {
			return Err(AnalysisMismatch(ScalarFacts))
		}
		grapheme = list_at(analysis.graphemes, $visited)
		grapheme_scalars = if grapheme.scalar_end >= grapheme.scalar_start grapheme.scalar_end - grapheme.scalar_start else 0
		if grapheme_scalars != 1 {
			return Err(UnsupportedCluster({ grapheme: $visited, scalars: grapheme_scalars }))
		}
		byte_start = ByteRange.start(located.byte_range)
		byte_end = ByteRange.end(located.byte_range)
		if grapheme.scalar_start != located.scalar_index or grapheme.scalar_end != located.scalar_index + 1 or grapheme.byte_start != byte_start or grapheme.byte_end != byte_end {
			return Err(AnalysisMismatch(GraphemeFacts))
		}
		scalar = Scalar.to_u32(located.scalar)
		glyph = match KernelFont.glyph_for_scalar(font, scalar) {
			None => return Err(MissingGlyph({ scalar, scalar_index: located.scalar_index }))
			Some(0) => return Err(NotdefGlyph({ scalar, scalar_index: located.scalar_index }))
			Some(value) => value
		}
		width = KernelFont.advance_width(font, glyph) ? |_| MetricFailure(glyph)
		advance = scale_advance(width, size, font.metrics.units_per_em)?
		$total_advance = checked_add($total_advance, advance)?
		$glyphs = $glyphs.append({
			advance_x: Layout.Unit.from_raw(advance.to_i64_wrap()),
			advance_y: zero_unit,
			id: Text.GlyphId.from_raw(glyph),
			offset_x: zero_unit,
			offset_y: zero_unit,
		})
		$clusters = $clusters.append({
			glyphs: Semantics.Range.from_start_and_length($glyph_indices.len(), 1),
			kind: OneToOne,
			source: {
				scalars: Semantics.Range.from_start_and_length(located.scalar_index, 1),
				utf8_bytes: Semantics.Range.from_start_and_length(byte_start, byte_end - byte_start),
			},
		})
		$glyph_indices = $glyph_indices.append($visited)
		$visited = $visited + 1
	}
	if $visited != scalar_count {
		return Err(AnalysisMismatch(ScalarFacts))
	}

	run = {
		actual_text: FromOccurrence,
		clusters: Semantics.Range.from_start_and_length(0, $clusters.len()),
		direction: options.direction,
		glyphs: Semantics.Range.from_start_and_length(0, $glyphs.len()),
		id: Text.RunId.from_index(0),
		instance: options.instance,
		language: options.language,
		occurrence: options.occurrence,
		script: options.script,
		size: Layout.Unit.from_raw(size),
		source: {
			scalars: Semantics.Range.from_start_and_length(0, scalar_count),
			utf8_bytes: Semantics.Range.from_start_and_length(0, source_bytes),
		},
		substitutions: Semantics.Range.from_start_and_length(0, 0),
		transformations: Semantics.Range.from_start_and_length(0, 0),
		writing_mode: options.writing_mode,
	}
	Ok({
		advance: Layout.Unit.from_raw($total_advance.to_i64_wrap()),
		store: {
			clusters: $clusters,
			glyph_indices: $glyph_indices,
			glyphs: $glyphs,
			runs: [run],
			substitutions: [],
			transformations: [],
		},
		work: {
			cluster_visits: $visited,
			glyph_visits: $visited,
			metric_reads: $visited,
			scalar_visits: $visited,
			script_run_visits: analysis.script_runs.len(),
			utf8_bytes: source_bytes,
		},
	})
}

SimpleGlyphTemplate : { byte_end : U64, byte_start : U64, glyph : U32, scalar_index : U64, width : U32 }

SourceTemplate : { glyphs : Semantics.Range }

shape_simple_batch_latin : KernelFont.Inspection, List(KernelShape.SimpleSource), KernelShape.BatchOptions, List(KernelShape.SimpleRequest), KernelShape.Limits -> Try(KernelShape.Batch, KernelShape.Error)
shape_simple_batch_latin = |font, sources, options, requests, limits| {
	if options.direction != LeftToRight {
		return Err(UnsupportedDirection(options.direction))
	}
	if options.writing_mode != Horizontal {
		return Err(UnsupportedWritingMode(options.writing_mode))
	}
	expected_script = options.script.as_str()
	if expected_script != latin_script {
		return Err(UnsupportedScript({ actual: expected_script, expected: latin_script, run: 0 }))
	}
	var $planned_clusters = 0
	var $planned_scalars = 0
	var $planned_source_bytes = 0
	var $planning_index = 0
	while $planning_index < requests.len() {
		request = list_at(requests, $planning_index)
		source_index = request.source.index()
		if source_index >= sources.len() {
			return Err(InvalidSource({ request: $planning_index, source: source_index }))
		}
		source = list_at(sources, source_index)
		if request.size.raw() <= 0 {
			return Err(InvalidSize(request.size.raw()))
		}
		source_bytes = source.unicode.count_utf8_bytes()
		scalar_count = source.analysis.work.scalar_visits
		cluster_count = source.analysis.graphemes.len()
		if source_bytes == 0 or scalar_count == 0 or cluster_count == 0 {
			return Err(EmptySource)
		}
		if cluster_count != scalar_count {
			return Err(AnalysisMismatch(GraphemeFacts))
		}
		$planned_source_bytes = checked_add($planned_source_bytes, source_bytes)?
		$planned_scalars = checked_add($planned_scalars, scalar_count)?
		$planned_clusters = checked_add($planned_clusters, cluster_count)?
		check_limit($planned_source_bytes, limits.max_source_bytes, SourceBytes)?
		check_limit($planned_scalars, limits.max_scalars, Scalars)?
		check_limit($planned_scalars, limits.max_glyphs, Glyphs)?
		check_limit($planned_clusters, limits.max_clusters, Clusters)?
		$planning_index = $planning_index + 1
	}
	var $source_templates = List.with_capacity(sources.len())
	var $template_glyphs = []
	var $metric_reads = 0
	var $script_run_visits = 0
	var $source_index = 0
	while $source_index < sources.len() {
		source_record = list_at(sources, $source_index)
		source = source_record.unicode
		analysis = source_record.analysis
		source_bytes = source.count_utf8_bytes()
		scalar_count = analysis.work.scalar_visits
		cluster_count = analysis.graphemes.len()
		if source_bytes == 0 or scalar_count == 0 or cluster_count == 0 {
			return Err(EmptySource)
		}
		if cluster_count != scalar_count {
			return Err(AnalysisMismatch(GraphemeFacts))
		}
		validate_scripts(analysis.script_runs, source_bytes, scalar_count, latin_script)?
		$script_run_visits = checked_add($script_run_visits, analysis.script_runs.len())?
		template_start = $template_glyphs.len()
		var $visited = 0
		for located in Scalar.iter(source) {
			if $visited >= scalar_count {
				return Err(AnalysisMismatch(ScalarFacts))
			}
			grapheme = list_at(analysis.graphemes, $visited)
			grapheme_scalars = if grapheme.scalar_end >= grapheme.scalar_start grapheme.scalar_end - grapheme.scalar_start else 0
			if grapheme_scalars != 1 {
				return Err(UnsupportedCluster({ grapheme: $visited, scalars: grapheme_scalars }))
			}
			byte_start = ByteRange.start(located.byte_range)
			byte_end = ByteRange.end(located.byte_range)
			if grapheme.scalar_start != located.scalar_index or grapheme.scalar_end != located.scalar_index + 1 or grapheme.byte_start != byte_start or grapheme.byte_end != byte_end {
				return Err(AnalysisMismatch(GraphemeFacts))
			}
			scalar = Scalar.to_u32(located.scalar)
			glyph = match KernelFont.glyph_for_scalar(font, scalar) {
				None => return Err(MissingGlyph({ scalar, scalar_index: located.scalar_index }))
				Some(0) => return Err(NotdefGlyph({ scalar, scalar_index: located.scalar_index }))
				Some(value) => value
			}
			width = KernelFont.advance_width(font, glyph) ? |_| MetricFailure(glyph)
			$template_glyphs = $template_glyphs.append({ byte_end, byte_start, glyph, scalar_index: located.scalar_index, width })
			$metric_reads = checked_add($metric_reads, 1)?
			$visited = $visited + 1
		}
		if $visited != scalar_count {
			return Err(AnalysisMismatch(ScalarFacts))
		}
		$source_templates = $source_templates.append({ glyphs: Semantics.Range.from_start_and_length(template_start, $visited) })
		$source_index = $source_index + 1
	}
	var $advances = List.with_capacity(requests.len())
	var $clusters = List.with_capacity($planned_clusters)
	var $glyph_indices = List.with_capacity($planned_scalars)
	var $glyphs = List.with_capacity($planned_scalars)
	var $runs = List.with_capacity(requests.len())
	var $cluster_visits = 0
	var $glyph_visits = 0
	var $scalar_visits = 0
	var $utf8_bytes = 0
	var $request_index = 0
	while $request_index < requests.len() {
		request = list_at(requests, $request_index)
		source_record = list_at(sources, request.source.index())
		source = source_record.unicode
		analysis = source_record.analysis
		size = request.size.raw()

		source_bytes = source.count_utf8_bytes()
		scalar_count = analysis.work.scalar_visits
		cluster_count = analysis.graphemes.len()

		cluster_start = $clusters.len()
		glyph_start = $glyphs.len()
		template = list_at($source_templates, request.source.index())
		var $advance_total = 0
		var $visited = 0
		while $visited < template.glyphs.length() {
			template_glyph = list_at($template_glyphs, template.glyphs.start() + $visited)
			advance = scale_advance(template_glyph.width, size, font.metrics.units_per_em)?
			$advance_total = checked_add($advance_total, advance)?
			glyph_index = $glyphs.len()
			$glyphs = $glyphs.append({
				advance_x: Layout.Unit.from_raw(advance.to_i64_wrap()),
				advance_y: zero_unit,
				id: Text.GlyphId.from_raw(template_glyph.glyph),
				offset_x: zero_unit,
				offset_y: zero_unit,
			})
			$clusters = $clusters.append({
				glyphs: Semantics.Range.from_start_and_length($glyph_indices.len(), 1),
				kind: OneToOne,
				source: {
					scalars: Semantics.Range.from_start_and_length(template_glyph.scalar_index, 1),
					utf8_bytes: Semantics.Range.from_start_and_length(template_glyph.byte_start, template_glyph.byte_end - template_glyph.byte_start),
				},
			})
			$glyph_indices = $glyph_indices.append(glyph_index)
			$visited = $visited + 1
		}
		if $visited != scalar_count {
			return Err(AnalysisMismatch(ScalarFacts))
		}

		$runs = $runs.append({
			actual_text: FromOccurrence,
			clusters: Semantics.Range.from_start_and_length(cluster_start, cluster_count),
			direction: options.direction,
			glyphs: Semantics.Range.from_start_and_length(glyph_start, scalar_count),
			id: Text.RunId.from_index($request_index),
			instance: options.instance,
			language: options.language,
			occurrence: request.occurrence,
			script: options.script,
			size: request.size,
			source: {
				scalars: Semantics.Range.from_start_and_length(0, scalar_count),
				utf8_bytes: Semantics.Range.from_start_and_length(0, source_bytes),
			},
			substitutions: Semantics.Range.from_start_and_length(0, 0),
			transformations: Semantics.Range.from_start_and_length(0, 0),
			writing_mode: options.writing_mode,
		})
		$advances = $advances.append(Layout.Unit.from_raw($advance_total.to_i64_wrap()))
		$cluster_visits = checked_add($cluster_visits, $visited)?
		$glyph_visits = checked_add($glyph_visits, $visited)?
		$scalar_visits = checked_add($scalar_visits, $visited)?
		$utf8_bytes = checked_add($utf8_bytes, source_bytes)?
		$request_index = $request_index + 1
	}
	Ok({
		advances: $advances,
		store: {
			clusters: $clusters,
			glyph_indices: $glyph_indices,
			glyphs: $glyphs,
			runs: $runs,
			substitutions: [],
			transformations: [],
		},
		work: { cluster_visits: $cluster_visits, glyph_visits: $glyph_visits, metric_reads: $metric_reads, scalar_visits: $scalar_visits, script_run_visits: $script_run_visits, utf8_bytes: $utf8_bytes },
	})
}

validate_scripts : List(KernelUnicode.ScriptRun), U64, U64, Str -> Try({}, KernelShape.Error)
validate_scripts = |runs, source_bytes, scalar_count, expected| {
	if runs.len() == 0 {
		return Err(AnalysisMismatch(ScriptFacts))
	}
	var $byte_cursor = 0
	var $scalar_cursor = 0
	var $index = 0
	while $index < runs.len() {
		run = list_at(runs, $index)
		if run.range.byte_start != $byte_cursor or run.range.scalar_start != $scalar_cursor or run.range.byte_end < run.range.byte_start or run.range.scalar_end < run.range.scalar_start {
			return Err(AnalysisMismatch(ScriptFacts))
		}
		if !script_compatible(run.script, expected) {
			return Err(UnsupportedScript({ actual: run.script, expected, run: $index }))
		}
		$byte_cursor = run.range.byte_end
		$scalar_cursor = run.range.scalar_end
		$index = $index + 1
	}
	if $byte_cursor != source_bytes or $scalar_cursor != scalar_count {
		return Err(AnalysisMismatch(ScriptFacts))
	}
	Ok({})
}

script_compatible : Str, Str -> Bool
script_compatible = |actual, expected| actual == expected or (expected == latin_script and (actual == common_script or actual == inherited_script))

validate_advanced_store : KernelFont.Inspection, Str, Text.Store, KernelShape.AdvancedContext, KernelShape.AdvancedLimits -> Try(KernelShape.Validated, KernelShape.Error)
validate_advanced_store = |font, source, store, context, limits| {
	source_bytes = source.count_utf8_bytes()
	if source_bytes == 0 or store.runs.len() == 0 {
		return Err(EmptySource)
	}
	check_limit(source_bytes, limits.max_source_bytes, SourceBytes)?
	check_limit(store.runs.len(), limits.max_runs, Runs)?
	check_limit(store.glyphs.len(), limits.max_glyphs, Glyphs)?
	check_limit(store.clusters.len(), limits.max_clusters, Clusters)?
	check_limit(store.glyph_indices.len(), limits.max_glyph_indices, GlyphIndices)?
	check_limit(store.substitutions.len(), limits.max_substitutions, Substitutions)?
	check_limit(store.transformations.len(), limits.max_transformations, Transformations)?
	boundaries = scalar_boundaries(source, limits.max_scalars)?
	scalar_count = boundaries.len() - 1

	var $referenced = List.with_capacity(store.glyphs.len())
	var $glyph_index = 0
	while $glyph_index < store.glyphs.len() {
		$referenced = $referenced.append(zero_marker)
		$glyph_index = $glyph_index + 1
	}

	var $source_scalar_cursor = 0
	var $source_byte_cursor = 0
	var $glyph_cursor = 0
	var $cluster_cursor = 0
	var $glyph_reference_cursor = 0
	var $substitution_cursor = 0
	var $transformation_cursor = 0
	var $cluster_visits = 0
	var $glyph_visits = 0
	var $glyph_reference_visits = 0
	var $auxiliary_visits = 0
	var $run_index = 0
	while $run_index < store.runs.len() {
		run = list_at(store.runs, $run_index)
		if run.id.index() != $run_index {
			return Err(AdvancedRunInvalid({ reason: RunId, run: $run_index }))
		}
		if run.instance.index() != context.instance.index() {
			return Err(InstanceMismatch({ actual: run.instance, expected: context.instance, run: $run_index }))
		}
		if run.occurrence.index() != context.occurrence.index() {
			return Err(OccurrenceMismatch({ actual: run.occurrence, expected: context.occurrence, run: $run_index }))
		}
		if run.writing_mode != Horizontal {
			return Err(UnsupportedWritingMode(run.writing_mode))
		}
		if run.size.raw() <= 0 {
			return Err(AdvancedRunInvalid({ reason: Size, run: $run_index }))
		}
		if !valid_text_range(run.source, boundaries, source_bytes, scalar_count) or run.source.scalars.start() != $source_scalar_cursor or run.source.utf8_bytes.start() != $source_byte_cursor {
			return Err(AdvancedRunInvalid({ reason: SourceRange, run: $run_index }))
		}
		run_scalar_end = range_end(run.source.scalars, scalar_count) ? |_| AdvancedRunInvalid({ reason: SourceRange, run: $run_index })
		run_byte_end = range_end(run.source.utf8_bytes, source_bytes) ? |_| AdvancedRunInvalid({ reason: SourceRange, run: $run_index })
		if !range_starts_and_fits(run.glyphs, $glyph_cursor, store.glyphs.len()) or run.glyphs.length() == 0 {
			return Err(AdvancedRunInvalid({ reason: GlyphRange, run: $run_index }))
		}
		if !range_starts_and_fits(run.clusters, $cluster_cursor, store.clusters.len()) or run.clusters.length() == 0 {
			return Err(AdvancedRunInvalid({ reason: ClusterRange, run: $run_index }))
		}
		if !range_starts_and_fits(run.substitutions, $substitution_cursor, store.substitutions.len()) or !range_starts_and_fits(run.transformations, $transformation_cursor, store.transformations.len()) {
			return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: $run_index }))
		}
		run_glyph_end = range_end(run.glyphs, store.glyphs.len()) ? |_| AdvancedRunInvalid({ reason: GlyphRange, run: $run_index })
		run_cluster_end = range_end(run.clusters, store.clusters.len()) ? |_| AdvancedRunInvalid({ reason: ClusterRange, run: $run_index })

		$glyph_index = $glyph_cursor
		while $glyph_index < run_glyph_end {
			glyph = list_at(store.glyphs, $glyph_index)
			glyph_id = glyph.id.raw()
			if glyph_id == 0 or glyph_id.to_u64() >= font.metrics.glyph_count {
				return Err(AdvancedGlyphInvalid({ glyph: $glyph_index, reason: GlyphId }))
			}
			if glyph.advance_x.raw() < 0 or glyph.advance_y.raw() != 0 {
				return Err(AdvancedGlyphInvalid({ glyph: $glyph_index, reason: Advance }))
			}
			$glyph_visits = $glyph_visits + 1
			$glyph_index = $glyph_index + 1
		}

		var $cluster_source_scalar = $source_scalar_cursor
		var $cluster_source_byte = $source_byte_cursor
		var $current_cluster = $cluster_cursor
		while $current_cluster < run_cluster_end {
			cluster = list_at(store.clusters, $current_cluster)
			if !valid_text_range(cluster.source, boundaries, source_bytes, scalar_count) or cluster.source.scalars.start() != $cluster_source_scalar or cluster.source.utf8_bytes.start() != $cluster_source_byte {
				return Err(AdvancedClusterInvalid({ cluster: $current_cluster, reason: SourceRange }))
			}
			cluster_scalar_end = range_end(cluster.source.scalars, scalar_count) ? |_| AdvancedClusterInvalid({ cluster: $current_cluster, reason: SourceRange })
			cluster_byte_end = range_end(cluster.source.utf8_bytes, source_bytes) ? |_| AdvancedClusterInvalid({ cluster: $current_cluster, reason: SourceRange })
			if cluster_scalar_end > run_scalar_end or cluster_byte_end > run_byte_end or !range_starts_and_fits(cluster.glyphs, $glyph_reference_cursor, store.glyph_indices.len()) or cluster.glyphs.length() == 0 {
				return Err(AdvancedClusterInvalid({ cluster: $current_cluster, reason: GlyphIndexRange }))
			}
			if !valid_cluster_cardinality(cluster.kind, cluster.source.scalars.length(), cluster.glyphs.length()) {
				return Err(AdvancedClusterInvalid({ cluster: $current_cluster, reason: Cardinality }))
			}
			cluster_reference_end = range_end(cluster.glyphs, store.glyph_indices.len()) ? |_| AdvancedClusterInvalid({ cluster: $current_cluster, reason: GlyphIndexRange })
			while $glyph_reference_cursor < cluster_reference_end {
				referenced_glyph = list_at(store.glyph_indices, $glyph_reference_cursor)
				if referenced_glyph < $glyph_cursor or referenced_glyph >= run_glyph_end {
					return Err(GlyphOutsideRun({ glyph: referenced_glyph, run: $run_index }))
				}
				if list_at($referenced, referenced_glyph) != zero_marker {
					return Err(DuplicateGlyphReference({ glyph: referenced_glyph, run: $run_index }))
				}
				$referenced = list_set($referenced, referenced_glyph, referenced_marker)
				$glyph_reference_visits = $glyph_reference_visits + 1
				$glyph_reference_cursor = $glyph_reference_cursor + 1
			}
			$cluster_source_scalar = cluster_scalar_end
			$cluster_source_byte = cluster_byte_end
			$cluster_visits = $cluster_visits + 1
			$current_cluster = $current_cluster + 1
		}
		if $cluster_source_scalar != run_scalar_end or $cluster_source_byte != run_byte_end {
			return Err(AdvancedRunInvalid({ reason: SourceRange, run: $run_index }))
		}
		$glyph_index = $glyph_cursor
		while $glyph_index < run_glyph_end {
			if list_at($referenced, $glyph_index) == zero_marker {
				return Err(UnreferencedGlyph({ glyph: $glyph_index, run: $run_index }))
			}
			$glyph_index = $glyph_index + 1
		}

		substitution_end = range_end(run.substitutions, store.substitutions.len()) ? |_| AdvancedRunInvalid({ reason: AuxiliaryRange, run: $run_index })
		while $substitution_cursor < substitution_end {
			substitution = list_at(store.substitutions, $substitution_cursor)
			if !range_within(substitution.glyphs, run.glyphs) or substitution.glyphs.length() == 0 or substitution.source.scalars.length() == 0 or !valid_text_range(substitution.source, boundaries, source_bytes, scalar_count) or !text_range_within(substitution.source, run.source) {
				return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: $run_index }))
			}
			$auxiliary_visits = $auxiliary_visits + 1
			$substitution_cursor = $substitution_cursor + 1
		}
		transformation_end = range_end(run.transformations, store.transformations.len()) ? |_| AdvancedRunInvalid({ reason: AuxiliaryRange, run: $run_index })
		while $transformation_cursor < transformation_end {
			transformation = list_at(store.transformations, $transformation_cursor)
			if !range_within(transformation.glyphs, run.glyphs) or transformation.glyphs.length() == 0 or transformation.source.scalars.length() == 0 or !valid_text_range(transformation.source, boundaries, source_bytes, scalar_count) or !text_range_within(transformation.source, run.source) {
				return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: $run_index }))
			}
			$auxiliary_visits = $auxiliary_visits + 1
			$transformation_cursor = $transformation_cursor + 1
		}

		$source_scalar_cursor = run_scalar_end
		$source_byte_cursor = run_byte_end
		$glyph_cursor = run_glyph_end
		$cluster_cursor = run_cluster_end
		$run_index = $run_index + 1
	}
	if $source_scalar_cursor != scalar_count or $source_byte_cursor != source_bytes or $glyph_cursor != store.glyphs.len() or $cluster_cursor != store.clusters.len() or $glyph_reference_cursor != store.glyph_indices.len() or $substitution_cursor != store.substitutions.len() or $transformation_cursor != store.transformations.len() {
		return Err(AdvancedRunInvalid({ reason: SourceRange, run: store.runs.len() }))
	}
	Ok({
		store,
		work: {
			auxiliary_visits: $auxiliary_visits,
			cluster_visits: $cluster_visits,
			glyph_index_visits: $glyph_reference_visits,
			glyph_visits: $glyph_visits,
			run_visits: store.runs.len(),
			scalar_visits: scalar_count,
			utf8_bytes: source_bytes,
		},
	})
}

validate_ligature_fact : Text.Store, KernelGsub.Fact -> Try({}, KernelShape.Error)
validate_ligature_fact = |store, fact| {
	var $cluster_index = 0
	while $cluster_index < store.clusters.len() {
		cluster = list_at(store.clusters, $cluster_index)
		if cluster.kind == Ligature and cluster.source.scalars.length() == fact.input.len() {
			var $substitution_index = 0
			while $substitution_index < store.substitutions.len() {
				substitution = list_at(store.substitutions, $substitution_index)
				same_source = substitution.source.scalars.start() == cluster.source.scalars.start() and substitution.source.scalars.length() == cluster.source.scalars.length() and substitution.source.utf8_bytes.start() == cluster.source.utf8_bytes.start() and substitution.source.utf8_bytes.length() == cluster.source.utf8_bytes.length()
				if substitution.feature.raw() == fact.feature and same_source {
					if substitution.glyphs.length() != 1 {
						return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 }))
					}
					glyph = list_at(store.glyphs, substitution.glyphs.start())
					if glyph.id.raw() == fact.output {
						return Ok({})
					} else {
						return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 }))
					}
				}
				$substitution_index = $substitution_index + 1
			}
			return Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 }))
		}
		$cluster_index = $cluster_index + 1
	}
	Err(AdvancedRunInvalid({ reason: AuxiliaryRange, run: 0 }))
}

scalar_boundaries : Str, U64 -> Try(List(U64), KernelShape.Error)
scalar_boundaries = |source, limit| {
	var $boundaries = [0]
	var $count = 0
	for located in Scalar.iter(source) {
		required = $count + 1
		check_limit(required, limit, Scalars)?
		$boundaries = $boundaries.append(ByteRange.end(located.byte_range))
		$count = required
	}
	Ok($boundaries)
}

valid_text_range : Semantics.TextRange, List(U64), U64, U64 -> Bool
valid_text_range = |range, boundaries, source_bytes, scalar_count| {
	scalar_start = range.scalars.start()
	byte_start = range.utf8_bytes.start()
	if scalar_start > scalar_count or range.scalars.length() > scalar_count - scalar_start or byte_start > source_bytes or range.utf8_bytes.length() > source_bytes - byte_start {
		return False
	}
	scalar_end = scalar_start + range.scalars.length()
	byte_end = byte_start + range.utf8_bytes.length()
	list_at(boundaries, scalar_start) == byte_start and list_at(boundaries, scalar_end) == byte_end
}

text_range_within : Semantics.TextRange, Semantics.TextRange -> Bool
text_range_within = |inner, outer| range_within(inner.scalars, outer.scalars) and range_within(inner.utf8_bytes, outer.utf8_bytes)

range_starts_and_fits : Semantics.Range, U64, U64 -> Bool
range_starts_and_fits = |range, expected_start, available| range.start() == expected_start and range.start() <= available and range.length() <= available - range.start()

range_within : Semantics.Range, Semantics.Range -> Bool
range_within = |inner, outer| {
	inner_start = inner.start()
	outer_start = outer.start()
	if inner_start < outer_start or outer_start > U64.highest - outer.length() or inner_start > U64.highest - inner.length() {
		False
	} else {
		inner_start + inner.length() <= outer_start + outer.length()
	}
}

range_end : Semantics.Range, U64 -> Try(U64, [OutOfRange])
range_end = |range, available| if range.start() > available or range.length() > available - range.start() Err(OutOfRange) else Ok(range.start() + range.length())

valid_cluster_cardinality : Text.ClusterKind, U64, U64 -> Bool
valid_cluster_cardinality = |kind, scalars, glyphs| match kind {
	OneToOne => scalars == 1 and glyphs == 1
	OneToMany => scalars == 1 and glyphs > 1
	ManyToOne => scalars > 1 and glyphs == 1
	Ligature => scalars > 1 and glyphs == 1
	ManyToMany => scalars > 1 and glyphs > 1
	Reordered => scalars > 0 and glyphs > 0
	Contextual => scalars > 0 and glyphs > 0
}

scale_advance : U16, I64, U16 -> Try(U64, KernelShape.Error)
scale_advance = |width, size, units_per_em| {
	if size <= 0 or units_per_em == 0 {
		return Err(InvalidSize(size))
	}
	product = checked_times(width.to_u64(), size.to_u64_wrap())?
	rounded = checked_add(product, units_per_em.to_u64() / 2)?
	result = U64.div_by(rounded, units_per_em.to_u64())
	if result > I64.highest.to_u64_wrap() {
		Err(ArithmeticOverflow)
	} else {
		Ok(result)
	}
}

check_limit : U64, U64, KernelShape.Dimension -> Try({}, KernelShape.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelShape.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelShape.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated shaping index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated shaping update escaped"
	}
	Ok(updated) => updated
}

latin_script : Str
latin_script = "Latn"

common_script : Str
common_script = "Zyyy"

inherited_script : Str
inherited_script = "Zinh"

zero_unit : Layout.Unit
zero_unit = Layout.Unit.from_raw(0)

zero_marker : U8
zero_marker = 0

referenced_marker : U8
referenced_marker = 1

expect scale_advance(1413, 11000, 2048)? == 7589

expect match scale_advance(2, I64.highest, 1) {
	Err(ArithmeticOverflow) => Bool.True
	_ => Bool.False
}
