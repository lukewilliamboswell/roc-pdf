import KernelLineLayout
import KernelUnicode
import Semantics
import Text
import unicode.BidiClass
import unicode.ByteRange
import unicode.Scalar

## This is an internal UAX #9 prerequisite, not the bidirectional algorithm.
##
## The pinned Unicode package supplies scalar Bidi_Class facts but no paragraph
## resolution. This module makes the later boundary explicit without inventing
## mixed-direction, isolate, neutral, bracket, mirror, or shaping facts. It
## supports only a single resolved level whose scalars are all strong L or all
## strong R/AL. Every other line is rejected for a future complete UAX #9
## resolver. Nothing in this module is consumed by PDF lowering.
KernelBidiBoundary :: [].{
	Level : [Even, Odd]
	ScalarClass : [Other, StrongLeft, StrongRight]
	Dimension : [Clusters, Scalars, VisualOrder]
	Limits :: { max_clusters : U64, max_scalars : U64, max_visual_order : U64 }.{
		make : { max_clusters : U64, max_scalars : U64, max_visual_order : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : { cluster_visits : U64, scalar_visits : U64, strong_class_visits : U64, visual_writes : U64 }
	Paragraph : {
		base_level : Level,
		classes : List(ScalarClass),
		logical_source : Semantics.TextRange,
		work : Work,
	}
	LineOrder : {
		logical_clusters : Semantics.Range,
		logical_source : Semantics.TextRange,
		resolved_level : Level,
		visual_clusters : List(U64),
		work : Work,
	}
	Error : [
		AnalysisMismatch,
		InvalidCluster({ cluster : U64 }),
		InvalidLineRange,
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		ParagraphFactsMismatch,
		UnsupportedSingleLevelClass({ class : ScalarClass, scalar : U64 }),
	]

	## UAX #9 P2/P3 paragraph direction discovery. `classes` is a compact
	## source-relative scalar buffer, so the later line resolver never infers
	## direction from glyph order or paint positions and does not rescan source.
	analyze_paragraph : Str, KernelUnicode.UnicodeAnalysis, Limits -> Try(Paragraph, Error)
	analyze_paragraph = |source, analysis, limits| analyze(source, analysis, limits)

	## Validates a stored paragraph fact against the immutable source. Normal
	## staged consumers do not need this extra source walk; it exists for
	## boundary validation and atomic malformed-fact tests.
	validate_paragraph : Str, KernelUnicode.UnicodeAnalysis, Paragraph, Limits -> Try({}, Error)
	validate_paragraph = |source, analysis, paragraph, limits| {
		expected = analyze(source, analysis, limits)?
		if paragraph_equal(expected, paragraph) Ok({}) else Err(ParagraphFactsMismatch)
	}

	## Resolve only a line already proven to contain one strong level. The
	## returned visual IDs are independent from the line's logical cluster range.
	## Odd-level reversal is UAX #9 L2 over a single resolved level; it is not
	## PDF output and carries no mirroring or shaping claim.
	resolve_single_level_line : Paragraph, KernelLineLayout.Line, List(Text.Cluster), Limits -> Try(LineOrder, Error)
	resolve_single_level_line = |paragraph, line, clusters, limits| resolve_line(paragraph, line, clusters, limits)
}

analyze : Str, KernelUnicode.UnicodeAnalysis, KernelBidiBoundary.Limits -> Try(KernelBidiBoundary.Paragraph, KernelBidiBoundary.Error)
analyze = |source, analysis, limits| {
	if analysis.work.scalar_visits > limits.max_scalars {
		return Err(LimitExceeded({ attempted: analysis.work.scalar_visits, dimension: Scalars, limit: limits.max_scalars }))
	}
	var $classes = List.with_capacity(analysis.work.scalar_visits)
	var $scalar_visits = 0
	var $strong_class_visits = 0
	var $found_strong = Bool.False
	var $base_level = Even
	var $last_byte_end = 0
	for located in Scalar.iter(source) {
		required = $scalar_visits + 1
		if required > limits.max_scalars {
			return Err(LimitExceeded({ attempted: required, dimension: Scalars, limit: limits.max_scalars }))
		}
		class = scalar_class(BidiClass.short(BidiClass.of_scalar(located.scalar)))
		$classes = $classes.append(class)
		if class != Other {
			$strong_class_visits = $strong_class_visits + 1
			if !$found_strong {
				$base_level = match class {
					StrongLeft => Even
					StrongRight => Odd
					Other => Even
				}
				$found_strong = Bool.True
			}
		}
		$scalar_visits = required
		$last_byte_end = ByteRange.end(located.byte_range)
	}
	if $scalar_visits != analysis.work.scalar_visits or $last_byte_end != source.count_utf8_bytes() {
		return Err(AnalysisMismatch)
	}
	Ok({
		base_level: $base_level,
		classes: $classes,
		logical_source: {
			scalars: Semantics.Range.from_start_and_length(0, $scalar_visits),
			utf8_bytes: Semantics.Range.from_start_and_length(0, $last_byte_end),
		},
		work: { cluster_visits: 0, scalar_visits: $scalar_visits, strong_class_visits: $strong_class_visits, visual_writes: 0 },
	})
}

scalar_class : Str -> KernelBidiBoundary.ScalarClass
scalar_class = |class| {
	if class == "L" StrongLeft
	else if class == "R" or class == "AL" StrongRight
	else Other
}

resolve_line : KernelBidiBoundary.Paragraph, KernelLineLayout.Line, List(Text.Cluster), KernelBidiBoundary.Limits -> Try(KernelBidiBoundary.LineOrder, KernelBidiBoundary.Error)
resolve_line = |paragraph, line, clusters, limits| {
	scalar_end = range_end(line.source.scalars)?
	byte_end = range_end(line.source.utf8_bytes)?
	paragraph_scalar_end = range_end(paragraph.logical_source.scalars)?
	paragraph_byte_end = range_end(paragraph.logical_source.utf8_bytes)?
	cluster_end = range_end(line.clusters)?
	if line.source.scalars.length() == 0 or line.source.scalars.start() > paragraph_scalar_end or scalar_end > paragraph_scalar_end or line.source.utf8_bytes.start() > paragraph_byte_end or byte_end > paragraph_byte_end or cluster_end > clusters.len() or paragraph.classes.len() != paragraph.logical_source.scalars.length() {
		return Err(InvalidLineRange)
	}
	if line.clusters.length() > limits.max_clusters {
		return Err(LimitExceeded({ attempted: line.clusters.length(), dimension: Clusters, limit: limits.max_clusters }))
	}
	if line.clusters.length() > limits.max_visual_order {
		return Err(LimitExceeded({ attempted: line.clusters.length(), dimension: VisualOrder, limit: limits.max_visual_order }))
	}
	var $cluster_visits = 0
	var $scalar_cursor = line.source.scalars.start()
	var $byte_cursor = line.source.utf8_bytes.start()
	var $cluster_index = line.clusters.start()
	while $cluster_index < cluster_end {
		cluster = list_at(clusters, $cluster_index)
		cluster_scalar_end = range_end(cluster.source.scalars)?
		cluster_byte_end = range_end(cluster.source.utf8_bytes)?
		if cluster.source.scalars.start() != $scalar_cursor or cluster.source.utf8_bytes.start() != $byte_cursor or cluster.source.scalars.length() == 0 or cluster_scalar_end > scalar_end or cluster_byte_end > byte_end {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		$scalar_cursor = cluster_scalar_end
		$byte_cursor = cluster_byte_end
		$cluster_visits = $cluster_visits + 1
		$cluster_index = $cluster_index + 1
	}
	if $scalar_cursor != scalar_end or $byte_cursor != byte_end {
		return Err(InvalidLineRange)
	}
	var $scalar = line.source.scalars.start()
	while $scalar < scalar_end {
		class = list_at(paragraph.classes, $scalar)
		allowed = match paragraph.base_level {
			Even => class == StrongLeft
			Odd => class == StrongRight
		}
		if !allowed {
			return Err(UnsupportedSingleLevelClass({ class, scalar: $scalar }))
		}
		$scalar = $scalar + 1
	}
	var $visual_clusters = List.with_capacity(line.clusters.length())
	match paragraph.base_level {
		Even => {
			var $cluster = line.clusters.start()
			while $cluster < cluster_end {
				$visual_clusters = $visual_clusters.append($cluster)
				$cluster = $cluster + 1
			}
		}
		Odd => {
			var $cluster = cluster_end
			while $cluster > line.clusters.start() {
				$cluster = $cluster - 1
				$visual_clusters = $visual_clusters.append($cluster)
			}
		}
	}
	Ok({
		logical_clusters: line.clusters,
		logical_source: line.source,
		resolved_level: paragraph.base_level,
		visual_clusters: $visual_clusters,
		work: { cluster_visits: $cluster_visits, scalar_visits: line.source.scalars.length(), strong_class_visits: line.source.scalars.length(), visual_writes: $visual_clusters.len() },
	})
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
work_equal = |left, right| left.cluster_visits == right.cluster_visits and left.scalar_visits == right.scalar_visits and left.strong_class_visits == right.strong_class_visits and left.visual_writes == right.visual_writes

paragraph_equal : KernelBidiBoundary.Paragraph, KernelBidiBoundary.Paragraph -> Bool
paragraph_equal = |left, right| left.base_level == right.base_level and left.classes == right.classes and text_range_equal(left.logical_source, right.logical_source) and work_equal(left.work, right.work)

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "KernelBidiBoundary validated list index"
}
