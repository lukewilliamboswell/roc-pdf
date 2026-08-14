import KernelUnicode
import Semantics
import Text
import unicode.Bidi
import unicode.ByteRange
import unicode.Scalar
import unicode.ScalarRange
import unicode.TextRange

## The project-side UAX #9 boundary over the pinned Unicode package's
## revision-51 bidirectional algorithm.
##
## This module owns no bidi rules. It consumes one immutable source once,
## projects the dependency's per-scalar resolution into flat project-typed
## facts, and resolves a selected logical line into a dense visual
## cluster-ID sequence with explicit mirror decisions. Reading order stays
## separate from paint order: the logical source and cluster ranges are
## preserved beside the visual sequence, never replaced by it. Later stages
## consume these facts; no stage infers direction from glyph order or paint
## positions. The retained upstream analysis holds scalar coordinates and
## properties only — the dependency documents that it never retains the
## source `Str`.
KernelBidiBoundary :: [].{
	Dimension : [Clusters, Scalars, VisualOrder]
	Direction : [LeftToRight, RightToLeft]

	## `Auto` requests the UAX #9 P2/P3 first-strong heuristic. The explicit
	## directions are the higher-level protocol override P3 permits; the
	## caller never asserts a resolved level.
	BaseDirection : [Auto, LeftToRight, RightToLeft]
	ResolvedLevel : [Level(U8), RemovedByX9]

	## Upstream failures are projected onto a stable project discriminant so
	## no dependency error payload leaks into later stages.
	BidiFailure : [ByteLimit, InvalidParagraph, LineOutOfBounds, MultipleParagraphs, ScalarLimit]

	Limits :: { max_clusters : U64, max_scalars : U64, max_visual_order : U64 }.{
		make : { max_clusters : U64, max_scalars : U64, max_visual_order : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Counters cover this project's own walks only. The dependency exposes no
	## work counters, so its internal traversal is deliberately not claimed.
	Work : { cluster_visits : U64, mirror_visits : U64, scalar_visits : U64, visual_writes : U64 }

	ScalarFact : {
		level : ResolvedLevel,
		matched_bracket : [Some(U64), None],
		mirroring_glyph : [Some(U32), None],
		needs_mirrored_glyph : Bool,
		non_rendering : Bool,
	}

	MirrorInfo : { glyph : [Some(U32), None], needs_glyph : Bool }

	## The coordinate facts of one already-selected logical line. Taking the
	## selection rather than the line breaker's record keeps this boundary
	## independent of layout: it consumes ranges, not a layout decision.
	LineSelection : { clusters : Semantics.Range, source : Semantics.TextRange }

	VisualRunFact : { direction : Direction, level : U8, logical_scalars : Semantics.Range }

	Paragraph : {
		analysis : Bidi.Analysis,
		base_level : U8,
		entries : List(ScalarFact),
		logical_source : Semantics.TextRange,
		work : Work,
	}

	## `visual_clusters` is the dense paint sequence. It omits exactly the
	## clusters whose scalars UAX #9 X9 removes (explicit embedding and
	## override controls); `removed_clusters` counts them, so a consumer can
	## check total coverage without inferring it from a length difference.
	## Isolate initiators and PDI are not removed: they stay in the sequence
	## and remain flagged non-rendering in the paragraph facts.
	LineOrder : {
		logical_clusters : Semantics.Range,
		logical_source : Semantics.TextRange,
		mirrors : List(MirrorInfo),
		paragraph_level : U8,
		removed_clusters : U64,
		visual_clusters : List(U64),
		visual_runs : List(VisualRunFact),
		work : Work,
	}

	Error : [
		AnalysisMismatch,
		ClusterSplitByReorder({ cluster : U64 }),
		InvalidCluster({ cluster : U64 }),
		InvalidLineRange,
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MirrorOnMultiScalarCluster({ cluster : U64 }),
		ParagraphFactsMismatch,
		UnicodeBidi(BidiFailure),
		UnpaintedCluster({ cluster : U64 }),
	]

	## UAX #9 P2/P3 paragraph direction discovery and X/W/N/I resolution.
	analyze_paragraph : Str, KernelUnicode.UnicodeAnalysis, BaseDirection, Limits -> Try(Paragraph, Error)
	analyze_paragraph = |source, analysis, base, limits| analyze(source, analysis, base, limits)

	## Validates a stored paragraph fact against the immutable source. Normal
	## staged consumers do not need this extra analysis; it exists for
	## boundary validation and atomic malformed-fact tests.
	validate_paragraph : Str, KernelUnicode.UnicodeAnalysis, BaseDirection, Paragraph, Limits -> Try({}, Error)
	validate_paragraph = |source, analysis, base, paragraph, limits| {
		expected = analyze(source, analysis, base, limits)?
		if paragraph_equal(expected, paragraph) Ok({}) else Err(ParagraphFactsMismatch)
	}

	## UAX #9 L1/L2 for one selected logical line, projected onto grapheme
	## clusters. A cluster is indivisible: if reordering would split one, the
	## line is rejected rather than painted in a fabricated order.
	resolve_line : Paragraph, LineSelection, List(Text.Cluster), Limits -> Try(LineOrder, Error)
	resolve_line = |paragraph, line, clusters, limits| resolve(paragraph, line, clusters, limits)
}

analyze : Str, KernelUnicode.UnicodeAnalysis, KernelBidiBoundary.BaseDirection, KernelBidiBoundary.Limits -> Try(KernelBidiBoundary.Paragraph, KernelBidiBoundary.Error)
analyze = |source, analysis, base, limits| {
	if analysis.work.scalar_visits > limits.max_scalars {
		return Err(LimitExceeded({ attempted: analysis.work.scalar_visits, dimension: Scalars, limit: limits.max_scalars }))
	}
	source_bytes = source.count_utf8_bytes()
	requested = match base {
		Auto => Auto
		LeftToRight => LeftToRight
		RightToLeft => RightToLeft
	}
	resolved = Bidi.analyze_paragraph(source, requested, { max_bytes: source_bytes, max_scalars: limits.max_scalars }) ? map_bidi_error
	entries = Bidi.entries(resolved)
	if entries.len() != analysis.work.scalar_visits {
		return Err(AnalysisMismatch)
	}
	var $facts = List.with_capacity(entries.len())
	var $scalar_visits = 0
	var $mirror_visits = 0
	var $last_byte_end = 0
	var $index = 0
	while $index < entries.len() {
		entry = list_at(entries, $index)
		scalars = TextRange.scalar_range(entry.range)
		bytes = ByteRange.end(TextRange.byte_range(entry.range))
		if ScalarRange.start(scalars) != $index {
			return Err(AnalysisMismatch)
		}
		$facts = $facts.append({
			level: match entry.level {
				Some(value) => Level(value)
				None => RemovedByX9
			},
			matched_bracket: entry.matched_bracket,
			mirroring_glyph: match entry.mirroring_glyph {
				Some(glyph) => Some(Scalar.to_u32(glyph))
				None => None
			},
			needs_mirrored_glyph: entry.needs_mirrored_glyph,
			non_rendering: entry.non_rendering,
		})
		if entry.needs_mirrored_glyph {
			$mirror_visits = $mirror_visits + 1
		}
		$last_byte_end = bytes
		$scalar_visits = $scalar_visits + 1
		$index = $index + 1
	}
	if $scalar_visits != analysis.work.scalar_visits or $last_byte_end != source_bytes {
		return Err(AnalysisMismatch)
	}
	Ok({
		analysis: resolved,
		base_level: Bidi.paragraph_level(resolved),
		entries: $facts,
		logical_source: {
			scalars: Semantics.Range.from_start_and_length(0, $scalar_visits),
			utf8_bytes: Semantics.Range.from_start_and_length(0, $last_byte_end),
		},
		work: { cluster_visits: 0, mirror_visits: $mirror_visits, scalar_visits: $scalar_visits, visual_writes: 0 },
	})
}

resolve : KernelBidiBoundary.Paragraph, KernelBidiBoundary.LineSelection, List(Text.Cluster), KernelBidiBoundary.Limits -> Try(KernelBidiBoundary.LineOrder, KernelBidiBoundary.Error)
resolve = |paragraph, line, clusters, limits| {
	scalar_start = line.source.scalars.start()
	scalar_end = range_end(line.source.scalars)?
	byte_start = line.source.utf8_bytes.start()
	byte_end = range_end(line.source.utf8_bytes)?
	paragraph_scalar_end = range_end(paragraph.logical_source.scalars)?
	paragraph_byte_end = range_end(paragraph.logical_source.utf8_bytes)?
	cluster_start = line.clusters.start()
	cluster_end = range_end(line.clusters)?
	if line.source.scalars.length() == 0 or scalar_start > paragraph_scalar_end or scalar_end > paragraph_scalar_end or byte_start > paragraph_byte_end or byte_end > paragraph_byte_end or cluster_end > clusters.len() or paragraph.entries.len() != paragraph.logical_source.scalars.length() {
		return Err(InvalidLineRange)
	}
	line_scalars = line.source.scalars.length()
	if line.clusters.length() > limits.max_clusters {
		return Err(LimitExceeded({ attempted: line.clusters.length(), dimension: Clusters, limit: limits.max_clusters }))
	}
	if line_scalars > limits.max_scalars {
		return Err(LimitExceeded({ attempted: line_scalars, dimension: Scalars, limit: limits.max_scalars }))
	}
	if line.clusters.length() > limits.max_visual_order {
		return Err(LimitExceeded({ attempted: line.clusters.length(), dimension: VisualOrder, limit: limits.max_visual_order }))
	}

	## The line's clusters must exactly partition its source range. The dense
	## scalar-to-cluster table is the only extra buffer this resolution needs.
	var $scalar_clusters = List.repeat(clusters.len(), line_scalars)
	var $cluster_scalars = List.repeat(0, line.clusters.length())
	var $cluster_visits = 0
	var $scalar_cursor = scalar_start
	var $byte_cursor = byte_start
	var $cluster_index = cluster_start
	while $cluster_index < cluster_end {
		cluster = list_at(clusters, $cluster_index)
		cluster_scalar_end = range_end(cluster.source.scalars)?
		cluster_byte_end = range_end(cluster.source.utf8_bytes)?
		if cluster.source.scalars.start() != $scalar_cursor or cluster.source.utf8_bytes.start() != $byte_cursor or cluster.source.scalars.length() == 0 or cluster_scalar_end > scalar_end or cluster_byte_end > byte_end {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		var $scalar = $scalar_cursor
		while $scalar < cluster_scalar_end {
			$scalar_clusters = list_set($scalar_clusters, $scalar - scalar_start, $cluster_index)
			$scalar = $scalar + 1
		}
		$cluster_scalars = list_set($cluster_scalars, $cluster_index - cluster_start, cluster.source.scalars.length())
		$scalar_cursor = cluster_scalar_end
		$byte_cursor = cluster_byte_end
		$cluster_visits = $cluster_visits + 1
		$cluster_index = $cluster_index + 1
	}
	if $scalar_cursor != scalar_end or $byte_cursor != byte_end {
		return Err(InvalidLineRange)
	}

	line_range = ScalarRange.from_bounds(scalar_start, scalar_end) ? |_| InvalidLineRange
	order = Bidi.reorder_line(paragraph.analysis, line_range) ? map_bidi_error
	visual = Bidi.visual_to_logical(order)
	mirroring = Bidi.line_mirroring(order)

	## Walk the dependency's visual scalar sequence once. A cluster is emitted
	## at its first visual scalar and must own the immediately following
	## visual entries for its remaining scalars; any other arrangement would
	## split the cluster, which is a typed rejection rather than a reordering
	## this project invents.
	var $visual_clusters = List.with_capacity(line.clusters.length())
	var $mirrors = List.with_capacity(line.clusters.length())
	var $emitted = List.repeat(Bool.False, line.clusters.length())
	var $mirror_visits = 0
	var $scalar_visits = 0
	var $visual_index = 0
	while $visual_index < visual.len() {
		logical_scalar = list_at(visual, $visual_index)
		if logical_scalar < scalar_start or logical_scalar >= scalar_end {
			return Err(InvalidLineRange)
		}
		$scalar_visits = $scalar_visits + 1
		owning_cluster = list_at($scalar_clusters, logical_scalar - scalar_start)
		if owning_cluster >= clusters.len() {
			return Err(InvalidLineRange)
		}
		local_cluster = owning_cluster - cluster_start
		if list_at($emitted, local_cluster) {
			$visual_index = $visual_index + 1
		} else {
			cluster_length = list_at($cluster_scalars, local_cluster)
			var $offset = 1
			while $offset < cluster_length {
				following = $visual_index + $offset
				if following >= visual.len() {
					return Err(ClusterSplitByReorder({ cluster: owning_cluster }))
				}
				next_scalar = list_at(visual, following)
				if next_scalar < scalar_start or next_scalar >= scalar_end or list_at($scalar_clusters, next_scalar - scalar_start) != owning_cluster {
					return Err(ClusterSplitByReorder({ cluster: owning_cluster }))
				}
				$offset = $offset + 1
			}
			mirror = mirror_for_cluster(mirroring, logical_scalar - scalar_start, cluster_length, owning_cluster)?
			$mirror_visits = $mirror_visits + cluster_length
			$mirrors = $mirrors.append(mirror)
			$visual_clusters = $visual_clusters.append(owning_cluster)
			$emitted = list_set($emitted, local_cluster, Bool.True)
			$visual_index = $visual_index + 1
		}
	}

	## Every cluster absent from the paint sequence must consist solely of
	## scalars X9 removed. Any other unpainted cluster would mean text
	## silently vanished, so it is a typed rejection.
	var $removed_clusters = 0
	var $unpainted = 0
	while $unpainted < line.clusters.length() {
		if !list_at($emitted, $unpainted) {
			cluster = list_at(clusters, cluster_start + $unpainted)
			cluster_scalar_end = range_end(cluster.source.scalars)?
			var $scalar = cluster.source.scalars.start()
			while $scalar < cluster_scalar_end {
				if scalar_is_painted(paragraph.entries, $scalar) {
					return Err(UnpaintedCluster({ cluster: cluster_start + $unpainted }))
				}
				$scalar = $scalar + 1
			}
			$removed_clusters = $removed_clusters + 1
		}
		$unpainted = $unpainted + 1
	}
	if $visual_clusters.len() + $removed_clusters != line.clusters.length() {
		return Err(InvalidLineRange)
	}

	var $visual_runs = List.with_capacity(Bidi.visual_runs(order).len())
	upstream_runs = Bidi.visual_runs(order)
	var $run_index = 0
	while $run_index < upstream_runs.len() {
		run = list_at(upstream_runs, $run_index)
		run_start = ScalarRange.start(run.logical_range)
		run_length = ScalarRange.len(run.logical_range)
		$visual_runs = $visual_runs.append({
			direction: match run.direction {
				LeftToRight => LeftToRight
				RightToLeft => RightToLeft
			},
			level: run.level,
			logical_scalars: Semantics.Range.from_start_and_length(run_start, run_length),
		})
		$run_index = $run_index + 1
	}

	Ok({
		logical_clusters: line.clusters,
		logical_source: line.source,
		mirrors: $mirrors,
		paragraph_level: paragraph.base_level,
		removed_clusters: $removed_clusters,
		visual_clusters: $visual_clusters,
		visual_runs: $visual_runs,
		work: { cluster_visits: $cluster_visits, mirror_visits: $mirror_visits, scalar_visits: $scalar_visits, visual_writes: $visual_clusters.len() },
	})
}

## Mirroring is a per-scalar UAX #9 decision. A multi-scalar cluster whose
## members request a mirrored glyph has no single presentation this boundary
## can honestly claim, so it is rejected rather than silently unmirrored.
mirror_for_cluster : List(Bidi.MirrorInfo), U64, U64, U64 -> Try(KernelBidiBoundary.MirrorInfo, KernelBidiBoundary.Error)
mirror_for_cluster = |mirroring, local_scalar, cluster_length, cluster| {
	if local_scalar >= mirroring.len() {
		return Err(InvalidLineRange)
	}
	first = list_at(mirroring, local_scalar)
	if cluster_length > 1 {
		var $offset = 0
		while $offset < cluster_length {
			index = local_scalar + $offset
			if index >= mirroring.len() {
				return Err(InvalidLineRange)
			}
			if list_at(mirroring, index).needs_glyph {
				return Err(MirrorOnMultiScalarCluster({ cluster: cluster }))
			}
			$offset = $offset + 1
		}
		return Ok({ glyph: None, needs_glyph: Bool.False })
	}
	Ok({
		glyph: match first.glyph {
			Some(scalar) => Some(Scalar.to_u32(scalar))
			None => None
		},
		needs_glyph: first.needs_glyph,
	})
}

map_bidi_error : Bidi.Error -> KernelBidiBoundary.Error
map_bidi_error = |error| match error {
	ScalarLimitExceeded(_) => UnicodeBidi(ScalarLimit)
	ByteLimitExceeded(_) => UnicodeBidi(ByteLimit)
	MultipleParagraphs => UnicodeBidi(MultipleParagraphs)
	InvalidParagraphRange(_) => UnicodeBidi(InvalidParagraph)
	LineOutOfBounds(_) => UnicodeBidi(LineOutOfBounds)
}

range_end : Semantics.Range -> Try(U64, KernelBidiBoundary.Error)
range_end = |range| {
	match U64.plus_try(range.start(), range.length()) {
		Err(_) => Err(InvalidLineRange)
		Ok(end) => Ok(end)
	}
}

range_equal : Semantics.Range, Semantics.Range -> Bool
range_equal = |left, right| left.start() == right.start() and left.length() == right.length()

text_range_equal : Semantics.TextRange, Semantics.TextRange -> Bool
text_range_equal = |left, right| range_equal(left.scalars, right.scalars) and range_equal(left.utf8_bytes, right.utf8_bytes)

work_equal : KernelBidiBoundary.Work, KernelBidiBoundary.Work -> Bool
work_equal = |left, right| left.cluster_visits == right.cluster_visits and left.mirror_visits == right.mirror_visits and left.scalar_visits == right.scalar_visits and left.visual_writes == right.visual_writes

facts_equal : KernelBidiBoundary.ScalarFact, KernelBidiBoundary.ScalarFact -> Bool
facts_equal = |left, right| {
	levels = match (left.level, right.level) {
		(Level(first), Level(second)) => first == second
		(RemovedByX9, RemovedByX9) => Bool.True
		_ => Bool.False
	}
	brackets = match (left.matched_bracket, right.matched_bracket) {
		(Some(first), Some(second)) => first == second
		(None, None) => Bool.True
		_ => Bool.False
	}
	glyphs = match (left.mirroring_glyph, right.mirroring_glyph) {
		(Some(first), Some(second)) => first == second
		(None, None) => Bool.True
		_ => Bool.False
	}
	levels and brackets and glyphs and left.needs_mirrored_glyph == right.needs_mirrored_glyph and left.non_rendering == right.non_rendering
}

paragraph_equal : KernelBidiBoundary.Paragraph, KernelBidiBoundary.Paragraph -> Bool
paragraph_equal = |left, right| {
	if left.base_level != right.base_level or left.entries.len() != right.entries.len() or !text_range_equal(left.logical_source, right.logical_source) or !work_equal(left.work, right.work) {
		return Bool.False
	}
	var $index = 0
	while $index < left.entries.len() {
		if !facts_equal(list_at(left.entries, $index), list_at(right.entries, $index)) {
			return Bool.False
		}
		$index = $index + 1
	}
	Bool.True
}

## X9 removes explicit embedding and override controls from the display
## sequence; every other scalar keeps a resolved level and is painted.
scalar_is_painted : List(KernelBidiBoundary.ScalarFact), U64 -> Bool
scalar_is_painted = |entries, scalar| match list_at(entries, scalar).level {
	Level(_) => Bool.True
	RemovedByX9 => Bool.False
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "KernelBidiBoundary validated list index"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "KernelBidiBoundary validated list write"
}
