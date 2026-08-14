import KernelShape
import KernelUnicode
import Layout
import Semantics
import Text

KernelLineLayout :: [].{
	Dimension : [Boundaries, Candidates, Clusters, GlyphIndices, Glyphs, KeyProbes, Lines, Runs, TableSlots, Templates]
	Error : [
		ArithmeticOverflow,
		InvalidAnalysis,
		InvalidCluster({ cluster : U64 }),
		InvalidGlyphAdvance({ glyph : U64 }),
		InvalidRun({ run : U64 }),
		InvalidWidth(I64),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		TableExhausted,
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
	RunRequest : { source : Semantics.TextSourceId, width : Layout.Unit }
	BatchLimits :: { line : Limits, max_key_probes : U64, max_lines : U64, max_runs : U64, max_table_slots : U64, max_templates : U64 }.{
		make : { line : Limits, max_key_probes : U64, max_lines : U64, max_runs : U64, max_table_slots : U64, max_templates : U64 } -> BatchLimits
		make = |limits| BatchLimits.(limits)
	}
	BatchWork : {
		boundary_visits : U64,
		cache_hits : U64,
		candidate_visits : U64,
		cluster_visits : U64,
		glyph_index_visits : U64,
		glyph_visits : U64,
		key_probes : U64,
		line_writes : U64,
		run_visits : U64,
		table_slots : U64,
		templates : U64,
	}

	## One logical layout request may span several adjacent physical shaped
	## runs produced by ordered multi-face selection. Line selection measures
	## the merged contiguous cluster range, so a line may legally cross the
	## face boundary; the later text materializer splits paint runs again.
	LogicalRunRequest : { runs : Semantics.Range, source : Semantics.TextSourceId, width : Layout.Unit }

	BatchPlan :: { lines : List(Line), run_lines : List(Semantics.Range), work : BatchWork }.{
		build : List(KernelShape.SimpleSource), List(KernelShape.SimpleRequest), Text.Store, List(RunRequest), BatchLimits -> Try(BatchPlan, Error)
		build = |sources, shape_requests, store, requests, limits| build_batch(sources, shape_requests, store, requests, limits)

		## The ordered multi-face batch. The template cache stays keyed by the
		## existing `BatchKey`: one policy per build makes the physical split
		## of a source deterministic, so source, first-instance, size, and
		## width remain a complete cache identity.
		build_logical : List(KernelShape.SimpleSource), Text.Store, List(LogicalRunRequest), BatchLimits -> Try(BatchPlan, Error)
		build_logical = |sources, store, requests, limits| build_logical_batch(sources, store, requests, limits)

		lines : BatchPlan -> List(Line)
		lines = |plan| plan.lines

		run_lines : BatchPlan -> List(Semantics.Range)
		run_lines = |plan| plan.run_lines

		work : BatchPlan -> BatchWork
		work = |plan| plan.work
	}

	Plan :: { lines : List(Line), work : Work }.{

		## Both entry points require the shaped-stage wrapper. The line planner
		## consumes its cluster/source facts; it never reconstructs clusters from
		## Unicode text or assumes one glyph per scalar.
		build_simple : KernelUnicode.UnicodeAnalysis, KernelShape.Shape, Layout.Unit, Limits -> Try(Plan, Error)
		build_simple = |analysis, shaped, width, limits| build_plan(analysis, shaped.store, width, limits)

		build_advanced : KernelUnicode.UnicodeAnalysis, KernelShape.Validated, Layout.Unit, Limits -> Try(Plan, Error)
		build_advanced = |analysis, shaped, width, limits| build_plan(analysis, shaped.store, width, limits)

		## Batch facade layout selects one already-validated global run range.
		## Returned line cluster ranges remain global store ranges; source ranges
		## remain relative to the run's immutable Unicode source.
		build_run : KernelUnicode.UnicodeAnalysis, Text.Store, Text.RunId, Layout.Unit, Limits -> Try(Plan, Error)
		build_run = |analysis, store, run, width, limits| build_run_plan(analysis, store, run, width, limits)

		lines : Plan -> List(Line)
		lines = |plan| plan.lines

		work : Plan -> Work
		work = |plan| plan.work
	}
}

BatchKey := { instance : U64, size : I64, source : U64, width : I64 }

Template := { cluster_length : U64, cluster_start : U64, lines : Semantics.Range }

## Keep a selected run's dense-store bounds together across the internal
## layout boundary. The planner validates this range before consuming it.
RangeBounds := { cluster_end : U64, cluster_start : U64, glyph_end : U64, glyph_start : U64 }

empty_slot : U64
empty_slot = U64.highest

build_batch : List(KernelShape.SimpleSource), List(KernelShape.SimpleRequest), Text.Store, List(KernelLineLayout.RunRequest), KernelLineLayout.BatchLimits -> Try(KernelLineLayout.BatchPlan, KernelLineLayout.Error)
build_batch = |sources, shape_requests, store, requests, limits| {
	if requests.len() == 0 or requests.len() != store.runs.len() or shape_requests.len() != requests.len() {
		return Err(InvalidAnalysis)
	}
	check_limit(requests.len(), limits.max_runs, Runs)?
	capacity = table_capacity(requests.len(), limits.max_table_slots)?
	var $assignments = List.repeat(empty_slot, requests.len())
	var $slots = List.repeat(empty_slot, capacity)
	var $keys = []
	var $templates = []
	var $template_lines = []
	var $total_lines = 0
	var $boundary_visits = 0
	var $cache_hits = 0
	var $candidate_visits = 0
	var $template_cluster_visits = 0
	var $glyph_index_visits = 0
	var $glyph_visits = 0
	var $key_probes = 0
	var $previous_template = empty_slot
	var $run_index = 0
	while $run_index < requests.len() {
		request = list_at(requests, $run_index)
		shape_request = list_at(shape_requests, $run_index)
		run = list_at(store.runs, $run_index)
		source_index = request.source.index()
		if source_index >= sources.len() or shape_request.source.index() != source_index or shape_request.occurrence.index() != run.occurrence.index() or shape_request.size.raw() != run.size.raw() or request.width.raw() <= 0 {
			return Err(InvalidRun({ run: $run_index }))
		}
		key = { instance: run.instance.index(), size: run.size.raw(), source: source_index, width: request.width.raw() }
		var $template_index = empty_slot
		var $insertion_slot = empty_slot
		if $previous_template != empty_slot {
			$key_probes = checked_add($key_probes, 1)?
			check_limit($key_probes, limits.max_key_probes, KeyProbes)?
			if key_equal(key, list_at($keys, $previous_template)) {
				$template_index = $previous_template
				$cache_hits = checked_add($cache_hits, 1)?
			}
		}
		if $template_index == empty_slot {
			hashed = hash_key(key)
			var $probe = 0
			while $probe < capacity and $template_index == empty_slot and $insertion_slot == empty_slot {
				$key_probes = checked_add($key_probes, 1)?
				check_limit($key_probes, limits.max_key_probes, KeyProbes)?
				slot_index = (hashed + $probe) % capacity
				candidate = list_at($slots, slot_index)
				if candidate == empty_slot {
					$insertion_slot = slot_index
				} else if key_equal(key, list_at($keys, candidate)) {
					$template_index = candidate
					$cache_hits = checked_add($cache_hits, 1)?
				}
				$probe = $probe + 1
			}
			if $template_index == empty_slot and $insertion_slot == empty_slot {
				return Err(TableExhausted)
			}
		}
		if $template_index == empty_slot {
			template_count = checked_add($templates.len(), 1)?
			check_limit(template_count, limits.max_templates, Templates)?
			source = list_at(sources, source_index)
			selected = build_run_plan(source.analysis, store, Text.RunId.from_index($run_index), request.width, limits.line)?
			line_start = $template_lines.len()
			var $line_index = 0
			while $line_index < selected.lines.len() {
				$template_lines = $template_lines.append(list_at(selected.lines, $line_index))
				$line_index = $line_index + 1
			}
			$template_index = $templates.len()
			$keys = $keys.append(key)
			$slots = list_set($slots, $insertion_slot, $template_index)
			$templates = $templates.append({
				cluster_length: run.clusters.length(),
				cluster_start: run.clusters.start(),
				lines: Semantics.Range.from_start_and_length(line_start, selected.lines.len()),
			})
			$boundary_visits = checked_add($boundary_visits, selected.work.boundary_visits)?
			$candidate_visits = checked_add($candidate_visits, selected.work.candidate_visits)?

			## The batch accepts the simple shaped store, whose representative run
			## owns this exact cluster range. build_run_plan has already measured
			## and validated every cluster in it.
			$template_cluster_visits = checked_add($template_cluster_visits, run.clusters.length())?
			$glyph_index_visits = checked_add($glyph_index_visits, selected.work.glyph_index_visits)?
			$glyph_visits = checked_add($glyph_visits, selected.work.glyph_visits)?
		}
		line_count = list_at($templates, $template_index).lines.length()
		$total_lines = checked_add($total_lines, line_count)?
		check_limit($total_lines, limits.max_lines, Lines)?
		$assignments = match $assignments.set($run_index, $template_index) {
			Err(OutOfBounds) => return Err(InvalidRun({ run: $run_index }))
			Ok(updated) => updated
		}
		$previous_template = $template_index
		$run_index = $run_index + 1
	}
	var $lines = List.with_capacity($total_lines)
	var $run_lines = List.repeat(Semantics.Range.from_start_and_length(0, 0), requests.len())
	$run_index = 0
	while $run_index < requests.len() {
		run = list_at(store.runs, $run_index)
		template = list_at($templates, list_at($assignments, $run_index))
		if run.clusters.length() != template.cluster_length or run.clusters.start() < template.cluster_start {
			return Err(InvalidRun({ run: $run_index }))
		}
		cluster_delta = run.clusters.start() - template.cluster_start
		run_cluster_end = range_end(run.clusters)?
		line_start = $lines.len()
		line_end = checked_add(template.lines.start(), template.lines.length())?
		var $template_line = template.lines.start()
		while $template_line < line_end {
			line = list_at($template_lines, $template_line)
			shifted_start = checked_add(line.clusters.start(), cluster_delta)?
			shifted_end = checked_add(shifted_start, line.clusters.length())?
			if shifted_end > run_cluster_end {
				return Err(InvalidRun({ run: $run_index }))
			}
			$lines = $lines.append({
				advance: line.advance,
				clusters: Semantics.Range.from_start_and_length(shifted_start, line.clusters.length()),
				source: line.source,
			})
			$template_line = $template_line + 1
		}
		$run_lines = match $run_lines.set($run_index, Semantics.Range.from_start_and_length(line_start, template.lines.length())) {
			Err(OutOfBounds) => return Err(InvalidRun({ run: $run_index }))
			Ok(updated) => updated
		}
		$run_index = $run_index + 1
	}
	Ok(
		KernelLineLayout.BatchPlan.{
			lines: $lines,
			run_lines: $run_lines,
			work: {
				boundary_visits: $boundary_visits,
				cache_hits: $cache_hits,
				candidate_visits: $candidate_visits,
				cluster_visits: $template_cluster_visits,
				glyph_index_visits: $glyph_index_visits,
				glyph_visits: $glyph_visits,
				key_probes: $key_probes,
				line_writes: $lines.len(),
				run_visits: requests.len(),
				table_slots: capacity,
				templates: $templates.len(),
			},
		},
	)
}

## The merged dense-store bounds and identity facts of one logical request's
## adjacent physical runs, proven contiguous before any measurement.
LogicalBounds := { bounds : RangeBounds, glyph_length : U64, instance : U64, size : I64 }

build_logical_batch : List(KernelShape.SimpleSource), Text.Store, List(KernelLineLayout.LogicalRunRequest), KernelLineLayout.BatchLimits -> Try(KernelLineLayout.BatchPlan, KernelLineLayout.Error)
build_logical_batch = |sources, store, requests, limits| {
	if requests.len() == 0 or store.runs.len() == 0 {
		return Err(InvalidAnalysis)
	}
	check_limit(requests.len(), limits.max_runs, Runs)?
	capacity = table_capacity(requests.len(), limits.max_table_slots)?
	var $assignments = List.repeat(empty_slot, requests.len())
	var $slots = List.repeat(empty_slot, capacity)
	var $keys = []
	var $templates = []
	var $template_lines = []
	var $total_lines = 0
	var $boundary_visits = 0
	var $cache_hits = 0
	var $candidate_visits = 0
	var $template_cluster_visits = 0
	var $glyph_index_visits = 0
	var $glyph_visits = 0
	var $key_probes = 0
	var $run_cursor = 0
	var $previous_template = empty_slot
	var $request_index = 0
	while $request_index < requests.len() {
		request = list_at(requests, $request_index)
		source_index = request.source.index()
		if source_index >= sources.len() or request.width.raw() <= 0 {
			return Err(InvalidRun({ run: $request_index }))
		}
		logical = logical_bounds(store, request.runs, $run_cursor)?
		$run_cursor = range_end(request.runs)?
		key = { instance: logical.instance, size: logical.size, source: source_index, width: request.width.raw() }
		var $template_index = empty_slot
		var $insertion_slot = empty_slot
		if $previous_template != empty_slot {
			$key_probes = checked_add($key_probes, 1)?
			check_limit($key_probes, limits.max_key_probes, KeyProbes)?
			if key_equal(key, list_at($keys, $previous_template)) {
				$template_index = $previous_template
				$cache_hits = checked_add($cache_hits, 1)?
			}
		}
		if $template_index == empty_slot {
			hashed = hash_key(key)
			var $probe = 0
			while $probe < capacity and $template_index == empty_slot and $insertion_slot == empty_slot {
				$key_probes = checked_add($key_probes, 1)?
				check_limit($key_probes, limits.max_key_probes, KeyProbes)?
				slot_index = (hashed + $probe) % capacity
				candidate = list_at($slots, slot_index)
				if candidate == empty_slot {
					$insertion_slot = slot_index
				} else if key_equal(key, list_at($keys, candidate)) {
					$template_index = candidate
					$cache_hits = checked_add($cache_hits, 1)?
				}
				$probe = $probe + 1
			}
			if $template_index == empty_slot and $insertion_slot == empty_slot {
				return Err(TableExhausted)
			}
		}
		if $template_index == empty_slot {
			template_count = checked_add($templates.len(), 1)?
			check_limit(template_count, limits.max_templates, Templates)?
			source = list_at(sources, source_index)
			bounds = logical.bounds
			selected = build_range(source.analysis, store, bounds, request.width, limits.line)?
			if selected.work.glyph_index_visits != logical.glyph_length {
				return Err(InvalidRun({ run: $request_index }))
			}
			line_start = $template_lines.len()
			var $line_index = 0
			while $line_index < selected.lines.len() {
				$template_lines = $template_lines.append(list_at(selected.lines, $line_index))
				$line_index = $line_index + 1
			}
			$template_index = $templates.len()
			$keys = $keys.append(key)
			$slots = list_set($slots, $insertion_slot, $template_index)
			$templates = $templates.append({
				cluster_length: bounds.cluster_end - bounds.cluster_start,
				cluster_start: bounds.cluster_start,
				lines: Semantics.Range.from_start_and_length(line_start, selected.lines.len()),
			})
			$boundary_visits = checked_add($boundary_visits, selected.work.boundary_visits)?
			$candidate_visits = checked_add($candidate_visits, selected.work.candidate_visits)?
			$template_cluster_visits = checked_add($template_cluster_visits, bounds.cluster_end - bounds.cluster_start)?
			$glyph_index_visits = checked_add($glyph_index_visits, selected.work.glyph_index_visits)?
			$glyph_visits = checked_add($glyph_visits, selected.work.glyph_visits)?
		}
		line_count = list_at($templates, $template_index).lines.length()
		$total_lines = checked_add($total_lines, line_count)?
		check_limit($total_lines, limits.max_lines, Lines)?
		$assignments = match $assignments.set($request_index, $template_index) {
			Err(OutOfBounds) => return Err(InvalidRun({ run: $request_index }))
			Ok(updated) => updated
		}
		$previous_template = $template_index
		$request_index = $request_index + 1
	}
	if $run_cursor != store.runs.len() {
		return Err(InvalidAnalysis)
	}
	var $lines = List.with_capacity($total_lines)
	var $run_lines = List.repeat(Semantics.Range.from_start_and_length(0, 0), requests.len())
	$request_index = 0
	$run_cursor = 0
	while $request_index < requests.len() {
		request = list_at(requests, $request_index)
		logical = logical_bounds(store, request.runs, $run_cursor)?
		$run_cursor = range_end(request.runs)?
		bounds = logical.bounds
		template = list_at($templates, list_at($assignments, $request_index))
		merged_length = bounds.cluster_end - bounds.cluster_start
		if merged_length != template.cluster_length or bounds.cluster_start < template.cluster_start {
			return Err(InvalidRun({ run: $request_index }))
		}
		cluster_delta = bounds.cluster_start - template.cluster_start
		line_start = $lines.len()
		line_end = checked_add(template.lines.start(), template.lines.length())?
		var $template_line = template.lines.start()
		while $template_line < line_end {
			line = list_at($template_lines, $template_line)
			shifted_start = checked_add(line.clusters.start(), cluster_delta)?
			shifted_end = checked_add(shifted_start, line.clusters.length())?
			if shifted_end > bounds.cluster_end {
				return Err(InvalidRun({ run: $request_index }))
			}
			$lines = $lines.append({
				advance: line.advance,
				clusters: Semantics.Range.from_start_and_length(shifted_start, line.clusters.length()),
				source: line.source,
			})
			$template_line = $template_line + 1
		}
		$run_lines = match $run_lines.set($request_index, Semantics.Range.from_start_and_length(line_start, template.lines.length())) {
			Err(OutOfBounds) => return Err(InvalidRun({ run: $request_index }))
			Ok(updated) => updated
		}
		$request_index = $request_index + 1
	}
	Ok(
		KernelLineLayout.BatchPlan.{
			lines: $lines,
			run_lines: $run_lines,
			work: {
				boundary_visits: $boundary_visits,
				cache_hits: $cache_hits,
				candidate_visits: $candidate_visits,
				cluster_visits: $template_cluster_visits,
				glyph_index_visits: $glyph_index_visits,
				glyph_visits: $glyph_visits,
				key_probes: $key_probes,
				line_writes: $lines.len(),
				run_visits: requests.len(),
				table_slots: capacity,
				templates: $templates.len(),
			},
		},
	)
}

## Validates one logical request's physical runs: dense IDs, adjacency of
## cluster and glyph ranges, and one occurrence, size, and source span. The
## returned merged bounds cover the whole logical range.
logical_bounds : Text.Store, Semantics.Range, U64 -> Try(LogicalBounds, KernelLineLayout.Error)
logical_bounds = |store, run_range, expected_start| {
	run_start = run_range.start()
	run_count = run_range.length()
	run_end = range_end(run_range)?
	if run_count == 0 or run_start != expected_start or run_end > store.runs.len() {
		return Err(InvalidRun({ run: run_start }))
	}
	first = list_at(store.runs, run_start)
	first_cluster_end = range_end(first.clusters)?
	first_glyph_end = range_end(first.glyphs)?
	if first.id.index() != run_start or first.clusters.length() == 0 or first.glyphs.length() == 0 or first_cluster_end > store.clusters.len() or first_glyph_end > store.glyphs.len() {
		return Err(InvalidRun({ run: run_start }))
	}
	var $cluster_end = first_cluster_end
	var $glyph_end = first_glyph_end
	var $glyph_length = first.glyphs.length()
	var $index = run_start + 1
	while $index < run_end {
		run = list_at(store.runs, $index)
		cluster_end = range_end(run.clusters)?
		glyph_end = range_end(run.glyphs)?
		if run.id.index() != $index or run.clusters.length() == 0 or run.glyphs.length() == 0 or run.clusters.start() != $cluster_end or run.glyphs.start() != $glyph_end or cluster_end > store.clusters.len() or glyph_end > store.glyphs.len() or run.occurrence.index() != first.occurrence.index() or run.size.raw() != first.size.raw() {
			return Err(InvalidRun({ run: $index }))
		}
		$cluster_end = cluster_end
		$glyph_end = glyph_end
		$glyph_length = checked_add($glyph_length, run.glyphs.length())?
		$index = $index + 1
	}
	Ok({
		bounds: { cluster_end: $cluster_end, cluster_start: first.clusters.start(), glyph_end: $glyph_end, glyph_start: first.glyphs.start() },
		glyph_length: $glyph_length,
		instance: first.instance.index(),
		size: first.size.raw(),
	})
}

key_equal : BatchKey, BatchKey -> Bool
key_equal = |left, right| left.instance == right.instance and left.size == right.size and left.source == right.source and left.width == right.width

hash_key : BatchKey -> U64
hash_key = |key| {
	first = mix_hash(14695981039346656037, key.source)
	second = mix_hash(first, key.instance)
	third = mix_hash(second, key.size.to_u64_wrap())
	mix_hash(third, key.width.to_u64_wrap())
}

mix_hash : U64, U64 -> U64
mix_hash = |hash, value| {
	mixed = hash.bitwise_xor(value)
	left = mixed.bitwise_xor(mixed.shl_wrap(13))
	right = left.bitwise_xor(left.shr_wrap(7))
	right.bitwise_xor(right.shl_wrap(17))
}

table_capacity : U64, U64 -> Try(U64, KernelLineLayout.Error)
table_capacity = |requests, limit| {
	required = checked_mul(requests, 2)?
	var $capacity = 8
	while $capacity < required {
		$capacity = checked_mul($capacity, 2)?
	}
	check_limit($capacity, limit, TableSlots)?
	Ok($capacity)
}

build_plan : KernelUnicode.UnicodeAnalysis, Text.Store, Layout.Unit, KernelLineLayout.Limits -> Try(KernelLineLayout.Plan, KernelLineLayout.Error)
build_plan = |analysis, store, width, limits| build_range(analysis, store, { cluster_end: store.clusters.len(), cluster_start: 0, glyph_end: store.glyphs.len(), glyph_start: 0 }, width, limits)

build_run_plan : KernelUnicode.UnicodeAnalysis, Text.Store, Text.RunId, Layout.Unit, KernelLineLayout.Limits -> Try(KernelLineLayout.Plan, KernelLineLayout.Error)
build_run_plan = |analysis, store, run_id, width, limits| {
	run_index = run_id.index()
	if run_index >= store.runs.len() {
		return Err(InvalidRun({ run: run_index }))
	}
	run = list_at(store.runs, run_index)
	cluster_end = range_end(run.clusters)?
	glyph_end = range_end(run.glyphs)?
	if run.id.index() != run_index or run.clusters.length() == 0 or run.glyphs.length() == 0 or cluster_end > store.clusters.len() or glyph_end > store.glyphs.len() {
		return Err(InvalidRun({ run: run_index }))
	}
	plan = build_range(analysis, store, { cluster_end, cluster_start: run.clusters.start(), glyph_end, glyph_start: run.glyphs.start() }, width, limits)?
	if plan.work.glyph_index_visits != run.glyphs.length() {
		Err(InvalidRun({ run: run_index }))
	} else {
		Ok(plan)
	}
}

build_range : KernelUnicode.UnicodeAnalysis, Text.Store, RangeBounds, Layout.Unit, KernelLineLayout.Limits -> Try(KernelLineLayout.Plan, KernelLineLayout.Error)
build_range = |analysis, store, bounds, width, limits| {
	cluster_start = bounds.cluster_start
	cluster_end = bounds.cluster_end
	glyph_start = bounds.glyph_start
	glyph_end = bounds.glyph_end
	max_width = width.raw()
	if max_width <= 0 {
		return Err(InvalidWidth(max_width))
	}
	scalars = analysis.work.scalar_visits
	cluster_count = if cluster_end >= cluster_start cluster_end - cluster_start else 0
	glyph_count = if glyph_end >= glyph_start glyph_end - glyph_start else 0
	if scalars == 0 or analysis.line_boundaries.len() != scalars + 1 or cluster_count == 0 or glyph_count == 0 or cluster_end > store.clusters.len() or glyph_end > store.glyphs.len() {
		return Err(InvalidAnalysis)
	}
	check_limit(analysis.line_boundaries.len(), limits.max_boundaries, Boundaries)?
	check_limit(cluster_count, limits.max_clusters, Clusters)?
	check_limit(glyph_count, limits.max_glyph_indices, GlyphIndices)?
	check_limit(glyph_count, limits.max_glyphs, Glyphs)?
	boundary_work = validate_boundaries(analysis.line_boundaries, store.clusters, cluster_start, cluster_end, scalars)?
	measure = measure_clusters(store.clusters, store.glyph_indices, store.glyphs, cluster_start, cluster_end, glyph_start, glyph_end, scalars)?
	if measure.glyph_index_visits != glyph_count {
		return Err(InvalidAnalysis)
	}
	var $lines = []
	var $line_start = cluster_start
	var $candidate = cluster_start + 1
	var $last_break = cluster_start
	var $candidate_visits = 0
	while $line_start < cluster_end {
		if $candidate > cluster_end {
			return Err(InvalidAnalysis)
		}
		$candidate_visits = checked_add($candidate_visits, 1)?
		check_limit($candidate_visits, limits.max_candidates, Candidates)?
		cluster = list_at(store.clusters, $candidate - 1)
		boundary_index = range_end(cluster.source.scalars)?
		boundary = list_at(analysis.line_boundaries, boundary_index)
		line_width = list_at(measure.prefix, $candidate - cluster_start) - list_at(measure.prefix, $line_start - cluster_start)
		if line_width > max_width {
			if $last_break == $line_start {
				return Err(Unbreakable({ cluster_end: $candidate, cluster_start: $line_start }))
			}
			$lines = append_line($lines, store.clusters, measure.prefix, cluster_start, $line_start, $last_break, limits.max_lines)?
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
					$lines = append_line($lines, store.clusters, measure.prefix, cluster_start, $line_start, $candidate, limits.max_lines)?
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
				cluster_visits: cluster_count,
				glyph_index_visits: measure.glyph_index_visits,
				glyph_visits: measure.glyph_index_visits,
				line_writes: $lines.len(),
			},
		},
	)
}

validate_boundaries : List(KernelUnicode.LineBoundary), List(Text.Cluster), U64, U64, U64 -> Try({ visits : U64 }, KernelLineLayout.Error)
validate_boundaries = |boundaries, clusters, cluster_start, cluster_end, scalars| {
	var $index = 0
	var $previous_byte = 0
	var $cluster_index = cluster_start
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
		while $cluster_index < cluster_end and range_end(list_at(clusters, $cluster_index).source.scalars)? < $index {
			$cluster_index = $cluster_index + 1
		}
		if boundary.decision != Prohibited {
			if $cluster_index >= cluster_end {
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

measure_clusters : List(Text.Cluster), List(U64), List(Text.Glyph), U64, U64, U64, U64, U64 -> Try({ cluster_visits : U64, glyph_index_visits : U64, prefix : List(I64) }, KernelLineLayout.Error)
measure_clusters = |clusters, glyph_indices, glyphs, cluster_start, cluster_end, glyph_start, glyph_end, scalars| {
	var $prefix = [0]
	var $total = 0
	var $scalar_cursor = 0
	var $byte_cursor = 0
	var $cluster_index = cluster_start
	var $glyph_index_visits = 0
	while $cluster_index < cluster_end {
		cluster = list_at(clusters, $cluster_index)
		if cluster.source.scalars.start() != $scalar_cursor or cluster.source.utf8_bytes.start() != $byte_cursor or cluster.source.scalars.length() == 0 or cluster.glyphs.length() == 0 {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		$scalar_cursor = range_end(cluster.source.scalars)?
		$byte_cursor = range_end(cluster.source.utf8_bytes)?
		cluster_glyph_end = range_end(cluster.glyphs)?
		if cluster_glyph_end > glyph_indices.len() {
			return Err(InvalidCluster({ cluster: $cluster_index }))
		}
		var $reference = cluster.glyphs.start()
		while $reference < cluster_glyph_end {
			glyph_index = list_at(glyph_indices, $reference)
			if glyph_index < glyph_start or glyph_index >= glyph_end {
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
		Ok({ cluster_visits: cluster_end - cluster_start, glyph_index_visits: $glyph_index_visits, prefix: $prefix })
	}
}

append_line : List(KernelLineLayout.Line), List(Text.Cluster), List(I64), U64, U64, U64, U64 -> Try(List(KernelLineLayout.Line), KernelLineLayout.Error)
append_line = |lines, clusters, prefix, prefix_start, start, end, limit| {
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
			advance: Layout.Unit.from_raw(list_at(prefix, end - prefix_start) - list_at(prefix, start - prefix_start)),
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

checked_mul : U64, U64 -> Try(U64, KernelLineLayout.Error)
checked_mul = |left, right| {
	if left == 0 or right == 0 {
		return Ok(0)
	}
	if left > U64.highest / right {
		Err(ArithmeticOverflow)
	} else {
		Ok(left * right)
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated line layout index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated line layout table index escaped"
	}
	Ok(updated) => updated
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
