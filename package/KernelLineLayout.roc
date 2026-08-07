import KernelShape
import KernelUnicode
import Layout
import Semantics
import Text

KernelLineLayout :: [].{
	Dimension : [Boundaries, Candidates, Clusters, GlyphIndices, Glyphs, Lines]
	Error : [
		ArithmeticOverflow,
		InvalidAnalysis,
		InvalidCluster({ cluster : U64 }),
		InvalidGlyphAdvance({ glyph : U64 }),
		InvalidWidth(I64),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		Unbreakable({ cluster_end : U64, cluster_start : U64 }),
	]

	Limits :: {
		max_boundaries : U64,
		max_candidates : U64,
		max_clusters : U64,
		max_glyph_indices : U64,
		max_glyphs : U64,
		max_lines : U64,
	}.{
		make : {
			max_boundaries : U64,
			max_candidates : U64,
			max_clusters : U64,
			max_glyph_indices : U64,
			max_glyphs : U64,
			max_lines : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	Line : {
		advance : Layout.Unit,
		clusters : Semantics.Range,
		source : Semantics.TextRange,
	}

	Work : {
		boundary_visits : U64,
		candidate_visits : U64,
		cluster_visits : U64,
		glyph_index_visits : U64,
		glyph_visits : U64,
		line_writes : U64,
	}

	Plan :: { lines : List(Line), work : Work }.{

		## Both entry points require the shaped-stage wrapper. The line planner
		## consumes its cluster/source facts; it never reconstructs clusters from
		## Unicode text or assumes one glyph per scalar.
		build_simple : KernelUnicode.UnicodeAnalysis, KernelShape.Shape, Layout.Unit, Limits -> Try(Plan, Error)
		build_simple = |analysis, shaped, width, limits| build_plan(analysis, shaped.store, width, limits)

		build_advanced : KernelUnicode.UnicodeAnalysis, KernelShape.Validated, Layout.Unit, Limits -> Try(Plan, Error)
		build_advanced = |analysis, shaped, width, limits| build_plan(analysis, shaped.store, width, limits)

		lines : Plan -> List(Line)
		lines = |plan| plan.lines

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelUnicode.UnicodeAnalysis, Text.Store, Layout.Unit, KernelLineLayout.Limits -> Try(KernelLineLayout.Plan, KernelLineLayout.Error)
build_plan = |analysis, store, width, limits| {
	max_width = width.raw()
	if max_width <= 0 {
		return Err(InvalidWidth(max_width))
	}
	scalars = analysis.work.scalar_visits
	if scalars == 0 or analysis.line_boundaries.len() != scalars + 1 or store.clusters.len() == 0 {
		return Err(InvalidAnalysis)
	}
	check_limit(analysis.line_boundaries.len(), limits.max_boundaries, Boundaries)?
	check_limit(store.clusters.len(), limits.max_clusters, Clusters)?
	check_limit(store.glyph_indices.len(), limits.max_glyph_indices, GlyphIndices)?
	check_limit(store.glyphs.len(), limits.max_glyphs, Glyphs)?
	boundary_work = validate_boundaries(analysis.line_boundaries, store.clusters, scalars)?
	measure = measure_clusters(store.clusters, store.glyph_indices, store.glyphs, scalars)?
	if measure.glyph_index_visits != store.glyphs.len() {
		return Err(InvalidAnalysis)
	}
	var $lines = []
	var $line_start = 0
	var $candidate = 1
	var $last_break = 0
	var $candidate_visits = 0
	while $line_start < store.clusters.len() {
		if $candidate > store.clusters.len() {
			return Err(InvalidAnalysis)
		}
		$candidate_visits = checked_add($candidate_visits, 1)?
		check_limit($candidate_visits, limits.max_candidates, Candidates)?
		cluster = list_at(store.clusters, $candidate - 1)
		boundary_index = range_end(cluster.source.scalars)?
		boundary = list_at(analysis.line_boundaries, boundary_index)
		line_width = list_at(measure.prefix, $candidate) - list_at(measure.prefix, $line_start)
		if line_width > max_width {
			if $last_break == $line_start {
				return Err(Unbreakable({ cluster_end: $candidate, cluster_start: $line_start }))
			}
			$lines = append_line($lines, store.clusters, measure.prefix, $line_start, $last_break, limits.max_lines)?
			$line_start = $last_break
			$candidate = $line_start + 1
			$last_break = $line_start
		} else {
			match boundary.decision {
				Allowed => {
					$last_break = $candidate
					$candidate = $candidate + 1
				}
				Mandatory => {
					$lines = append_line($lines, store.clusters, measure.prefix, $line_start, $candidate, limits.max_lines)?
					$line_start = $candidate
					$candidate = $line_start + 1
					$last_break = $line_start
				}
				Prohibited => {
					$candidate = $candidate + 1
				}
			}
		}
	}
	Ok(
		KernelLineLayout.Plan.{
			lines: $lines,
			work: {
				boundary_visits: boundary_work.visits,
				candidate_visits: $candidate_visits,
				cluster_visits: measure.cluster_visits,
				glyph_index_visits: measure.glyph_index_visits,
				glyph_visits: measure.glyph_index_visits,
				line_writes: $lines.len(),
			},
		},
	)
}

validate_boundaries : List(KernelUnicode.LineBoundary), List(Text.Cluster), U64 -> Try({ visits : U64 }, KernelLineLayout.Error)
validate_boundaries = |boundaries, clusters, scalars| {
	var $index = 0
	var $previous_byte = 0
	var $cluster_index = 0
	while $index < boundaries.len() {
		boundary = list_at(boundaries, $index)
		if boundary.scalar_offset != $index or boundary.byte_offset < $previous_byte {
			return Err(InvalidAnalysis)
		}
		if $index == 0 and boundary.byte_offset != 0 {
			return Err(InvalidAnalysis)
		}
		if $index < scalars and boundary.decision == Mandatory {
			return Err(InvalidAnalysis)
		}
		while $cluster_index < clusters.len() and range_end(list_at(clusters, $cluster_index).source.scalars)? < $index {
			$cluster_index = $cluster_index + 1
		}
		if boundary.decision != Prohibited {
			if $cluster_index >= clusters.len() {
				return Err(InvalidAnalysis)
			}
			cluster = list_at(clusters, $cluster_index)
			if range_end(cluster.source.scalars)? != $index or range_end(cluster.source.utf8_bytes)? != boundary.byte_offset {
				return Err(InvalidAnalysis)
			}
		}
		$previous_byte = boundary.byte_offset
		$index = $index + 1
	}
	if list_at(boundaries, scalars).decision != Mandatory {
		Err(InvalidAnalysis)
	} else {
		Ok({ visits: boundaries.len() })
	}
}

measure_clusters : List(Text.Cluster), List(U64), List(Text.Glyph), U64 -> Try({ cluster_visits : U64, glyph_index_visits : U64, prefix : List(I64) }, KernelLineLayout.Error)
measure_clusters = |clusters, glyph_indices, glyphs, scalars| {
	var $prefix = [0]
	var $total = 0
	var $scalar_cursor = 0
	var $byte_cursor = 0
	var $cluster_index = 0
	var $glyph_index_visits = 0
	while $cluster_index < clusters.len() {
		cluster = list_at(clusters, $cluster_index)
		if cluster.source.scalars.start() != $scalar_cursor or cluster.source.utf8_bytes.start() != $byte_cursor or cluster.source.scalars.length() == 0 or cluster.glyphs.length() == 0 {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		$scalar_cursor = range_end(cluster.source.scalars)?
		$byte_cursor = range_end(cluster.source.utf8_bytes)?
		glyph_end = range_end(cluster.glyphs)?
		if glyph_end > glyph_indices.len() {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		var $reference = cluster.glyphs.start()
		while $reference < glyph_end {
			glyph_index = list_at(glyph_indices, $reference)
			if glyph_index >= glyphs.len() {
				return Err(InvalidCluster({ cluster: $cluster_index }))
			}
			advance = list_at(glyphs, glyph_index).advance_x.raw()
			if advance < 0 {
				return Err(InvalidGlyphAdvance({ glyph: glyph_index }))
			}
			$total = match I64.plus_try($total, advance) {
				Err(_) => return Err(ArithmeticOverflow)
				Ok(value) => value
			}
			$glyph_index_visits = checked_add($glyph_index_visits, 1)?
			$reference = $reference + 1
		}
		$prefix = $prefix.append($total)
		$cluster_index = $cluster_index + 1
	}
	if $scalar_cursor != scalars {
		Err(InvalidAnalysis)
	} else {
		Ok({ cluster_visits: clusters.len(), glyph_index_visits: $glyph_index_visits, prefix: $prefix })
	}
}

append_line : List(KernelLineLayout.Line), List(Text.Cluster), List(I64), U64, U64, U64 -> Try(List(KernelLineLayout.Line), KernelLineLayout.Error)
append_line = |lines, clusters, prefix, start, end, limit| {
	if end <= start {
		return Err(InvalidAnalysis)
	}
	required = checked_add(lines.len(), 1)?
	check_limit(required, limit, Lines)?
	first = list_at(clusters, start)
	last = list_at(clusters, end - 1)
	scalar_end = range_end(last.source.scalars)?
	byte_end = range_end(last.source.utf8_bytes)?
	Ok(
		lines.append({
			advance: Layout.Unit.from_raw(list_at(prefix, end) - list_at(prefix, start)),
			clusters: Semantics.Range.from_start_and_length(start, end - start),
			source: {
				scalars: Semantics.Range.from_start_and_length(first.source.scalars.start(), scalar_end - first.source.scalars.start()),
				utf8_bytes: Semantics.Range.from_start_and_length(first.source.utf8_bytes.start(), byte_end - first.source.utf8_bytes.start()),
			},
		}),
	)
}

range_end : Semantics.Range -> Try(U64, KernelLineLayout.Error)
range_end = |range| checked_add(range.start(), range.length())

check_limit : U64, U64, KernelLineLayout.Dimension -> Try({}, KernelLineLayout.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelLineLayout.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated line layout index escaped"
	}
	Ok(value) => value
}

test_analysis : KernelUnicode.UnicodeAnalysis
test_analysis = {
	graphemes: [],
	line_boundaries: [
		{ authority: Tailorable, byte_offset: 0, decision: Prohibited, scalar_offset: 0 },
		{ authority: Tailorable, byte_offset: 1, decision: Prohibited, scalar_offset: 1 },
		{ authority: Tailorable, byte_offset: 2, decision: Allowed, scalar_offset: 2 },
		{ authority: Tailorable, byte_offset: 3, decision: Prohibited, scalar_offset: 3 },
		{ authority: Tailorable, byte_offset: 4, decision: Allowed, scalar_offset: 4 },
		{ authority: Tailorable, byte_offset: 5, decision: Prohibited, scalar_offset: 5 },
		{ authority: NonTailorable, byte_offset: 6, decision: Mandatory, scalar_offset: 6 },
	],
	script_runs: [],
	work: { grapheme_visits: 0, line_boundary_visits: 7, scalar_visits: 6, script_run_visits: 0 },
}

test_store : Text.Store
test_store = {
	clusters: List.map(
		[0, 1, 2, 3, 4, 5],
		|index| {
			glyphs: Semantics.Range.from_start_and_length(index, 1),
			kind: OneToOne,
			source: {
				scalars: Semantics.Range.from_start_and_length(index, 1),
				utf8_bytes: Semantics.Range.from_start_and_length(index, 1),
			},
		},
	),
	glyph_indices: [0, 1, 2, 3, 4, 5],
	glyphs: List.map(
		[1, 2, 3, 4, 5, 6],
		|id| {
			advance_x: Layout.Unit.from_raw(1000),
			advance_y: Layout.Unit.from_raw(0),
			id: Text.GlyphId.from_raw(id),
			offset_x: Layout.Unit.from_raw(0),
			offset_y: Layout.Unit.from_raw(0),
		},
	),
	runs: [],
	substitutions: [],
	transformations: [],
}

test_limits : KernelLineLayout.Limits
test_limits = KernelLineLayout.Limits.make({ max_boundaries: 7, max_candidates: 10, max_clusters: 6, max_glyph_indices: 6, max_glyphs: 6, max_lines: 3 })

expect {
	plan = build_plan(test_analysis, test_store, Layout.Unit.from_raw(3000), test_limits)?
	lines = KernelLineLayout.Plan.lines(plan)
	work = KernelLineLayout.Plan.work(plan)
	lines.len() == 3 and
		list_at(lines, 0).source.scalars.length() == 2 and
			list_at(lines, 1).clusters.start() == 2 and
				list_at(lines, 2).source.utf8_bytes.start() == 4 and
					work.boundary_visits == 7 and
						work.candidate_visits == 10 and
							work.cluster_visits == 6 and
								work.glyph_index_visits == 6 and
									work.glyph_visits == 6 and
										work.line_writes == 3
}

expect {
	boundaries = List.map(test_analysis.line_boundaries, |boundary| if boundary.scalar_offset == 6 { ..boundary, decision: Mandatory } else { ..boundary, decision: Prohibited })
	analysis = { ..test_analysis, line_boundaries: boundaries }
	match build_plan(analysis, test_store, Layout.Unit.from_raw(3000), test_limits) {
		Err(Unbreakable({ cluster_end: 4, cluster_start: 0 })) => True
		_ => False
	}
}

## An allowed scalar boundary inside one multi-scalar cluster is not silently
## treated as a legal cluster break.
expect {
	cluster = {
		glyphs: Semantics.Range.from_start_and_length(0, 1),
		kind: Ligature,
		source: {
			scalars: Semantics.Range.from_start_and_length(0, 2),
			utf8_bytes: Semantics.Range.from_start_and_length(0, 2),
		},
	}
	store = { ..test_store, clusters: [cluster], glyph_indices: [0], glyphs: [list_at(test_store.glyphs, 0)] }
	boundaries = [
		{ authority: Tailorable, byte_offset: 0, decision: Prohibited, scalar_offset: 0 },
		{ authority: Tailorable, byte_offset: 1, decision: Allowed, scalar_offset: 1 },
		{ authority: NonTailorable, byte_offset: 2, decision: Mandatory, scalar_offset: 2 },
	]
	analysis = { ..test_analysis, line_boundaries: boundaries, work: { ..test_analysis.work, line_boundary_visits: 3, scalar_visits: 2 } }
	limits = KernelLineLayout.Limits.make({ max_boundaries: 3, max_candidates: 1, max_clusters: 1, max_glyph_indices: 1, max_glyphs: 1, max_lines: 1 })
	match build_plan(analysis, store, Layout.Unit.from_raw(3000), limits) {
		Err(InvalidAnalysis) => True
		_ => False
	}
}
