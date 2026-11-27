import KernelBidiBoundary
import Layout
import Semantics
import Text

## Preserve the committed line's logical source and assign text-run
## positions from the independent UAX #9 L1/L2 cluster order. PDF tagging
## consumes the pieces in logical order. Their x offsets express paint
## placement and never act as ownership or reading-order evidence.
KernelInternationalLine :: [].{
	Error : [
		AdvanceMismatch({ measured : I64, positioned : I64 }),
		ArithmeticOverflow,
		Bidi(KernelBidiBoundary.Error),
		InvalidCluster(U64),
		InvalidRun(U64),
		InvalidStore,
		RunBoundaryRequiresReshaping(U64),
	]

	Line : { advance : Layout.Unit, clusters : Semantics.IndexRange, source : Semantics.TextRange }

	Piece : { clusters : Semantics.IndexRange, origin : Layout.Unit, run : Text.RunId }
	Work : { boundaries : KernelBidiBoundary.Work, glyphs : U64, physical_runs : U64 }
	Positioned : { pieces : List(Piece), work : Work }

	## Build the cluster-to-run index once per selected shaped store, before
	## visiting the accepted lines. It uses one dense run ID per shaped
	## cluster and never stores another glyph or source range.
	cluster_owners : Text.Store -> Try(List(U64), Error)
	cluster_owners = |store| {
		var $owners = List.with_capacity(store.clusters.len())
		var $run = 0
		for run in store.runs {
			if run.id.index() != $run or run.clusters.start() != $owners.len() or run.clusters.length() == 0 or !fits(run.clusters, store.clusters.len()) {
				return Err(InvalidRun($run))
			}
			var $index = 0
			while $index < run.clusters.length() {
				$owners = $owners.append($run)
				$index = $index + 1
			}
			$run = $run + 1
		}
		if $owners.len() != store.clusters.len() {
			Err(InvalidStore)
		} else {
			Ok($owners)
		}
	}

	position : KernelBidiBoundary.Paragraph, Text.Store, List(U64), Line, KernelBidiBoundary.Limits -> Try(Positioned, Error)
	position = |paragraph, store, owners, line, limits| {
		if line.clusters.length() == 0 or owners.len() != store.clusters.len() or !fits(line.clusters, owners.len()) {
			return Err(InvalidStore)
		}
		order = KernelBidiBoundary.resolve_line(paragraph, { clusters: line.clusters, source: line.source }, store.clusters, limits) ? Bidi
		if order.removed_clusters != 0 or order.visual_clusters.len() != line.clusters.length() {
			return Err(InvalidStore)
		}
		first_run = list_at(owners, line.clusters.start())
		last_run = list_at(owners, line.clusters.start() + line.clusters.length() - 1)
		if last_run < first_run or last_run >= store.runs.len() {
			return Err(InvalidStore)
		}

		var $positions = List.repeat(Unseen, last_run - first_run + 1)
		var $x = 0
		var $piece_count = 0
		var $glyph_count = 0
		var $active = store.runs.len()
		var $previous_cluster = 0
		for index in order.visual_clusters {
			if index < line.clusters.start() or index - line.clusters.start() >= line.clusters.length() {
				return Err(InvalidCluster(index))
			}
			run_index = list_at(owners, index)
			if run_index < first_run or run_index > last_run {
				return Err(InvalidRun(run_index))
			}
			run = list_at(store.runs, run_index)
			if run_index == $active {
				expected_next = if (run.direction == RightToLeft) index + 1 == $previous_cluster else index == $previous_cluster + 1
				if !expected_next {
					return Err(RunBoundaryRequiresReshaping(run_index))
				}
			} else {
				match list_at($positions, run_index - first_run) {
					Unseen => {
						$positions = set_at($positions, run_index - first_run, At($x))
					}
					At(_) => return Err(RunBoundaryRequiresReshaping(run_index))
				}
				$piece_count = $piece_count + 1
				$active = run_index
			}
			cluster = list_at(store.clusters, index)
			if cluster.glyphs.length() == 0 or !fits(cluster.glyphs, store.glyph_indices.len()) {
				return Err(InvalidCluster(index))
			}
			var $offset = 0
			while $offset < cluster.glyphs.length() {
				glyph = list_at(store.glyph_indices, cluster.glyphs.start() + $offset)
				if glyph < run.glyphs.start() or glyph - run.glyphs.start() >= run.glyphs.length() or glyph >= store.glyphs.len() {
					return Err(InvalidCluster(index))
				}
				advance = list_at(store.glyphs, glyph).advance_x.raw()
				if advance < 0 {
					return Err(InvalidCluster(index))
				}
				$x = checked_add($x, advance)?
				$glyph_count = $glyph_count + 1
				$offset = $offset + 1
			}
			$previous_cluster = index
		}
		if $x != line.advance.raw() {
			return Err(AdvanceMismatch({ measured: line.advance.raw(), positioned: $x }))
		}
		var $pieces = List.with_capacity($piece_count)
		var $run_index = first_run
		while $run_index <= last_run {
			offset = match list_at($positions, $run_index - first_run) {
				At(x) => x
				Unseen => return Err(InvalidRun($run_index))
			}
			run = list_at(store.runs, $run_index)
			first = U64.max(line.clusters.start(), run.clusters.start())
			last = U64.min(line.clusters.start() + line.clusters.length(), run.clusters.start() + run.clusters.length())
			if last <= first {
				return Err(InvalidRun($run_index))
			}
			$pieces = $pieces.append({
				clusters: Semantics.IndexRange.from_start_and_length({ start: first, length: last - first }),
				origin: Layout.Unit.from_raw(offset),
				run: run.id,
			})
			$run_index = $run_index + 1
		}
		Ok({ pieces: $pieces, work: { boundaries: order.work, glyphs: $glyph_count, physical_runs: $piece_count } })
	}
}

fits : Semantics.IndexRange, U64 -> Bool
fits = |range, limit| range.start() <= limit and range.length() <= limit - range.start()

checked_add : I64, I64 -> Try(I64, KernelInternationalLine.Error)
checked_add = |a, b| match I64.plus_try(a, b) {
	Ok(value) => Ok(value)
	Err(Overflow) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "international line index escaped its committed range"
}

set_at : List(a), U64, a -> List(a)
set_at = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "international line placement escaped its validated range"
}
