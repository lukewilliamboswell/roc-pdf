import Color
import Font
import KernelFacadeLines
import KernelFacadePages
import KernelFacadeShape
import KernelLineLayout
import KernelPageLayout
import Layout
import Semantics
import Text

KernelFacadeText :: [].{
	Dimension : [Clusters, GlyphIndices, Glyphs, Pages, Placements, Runs]
	Error : [
		ArithmeticOverflow,
		InvalidCluster({ cluster : U64, line : U64 }),
		InvalidGlyph({ glyph : U64, line : U64 }),
		InvalidLine({ line : U64, run : U64 }),
		InvalidPage({ page : U64 }),
		InvalidPlacement({ placement : U64 }),
		InvalidRun({ run : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		UnsupportedRunEvidence({ run : U64 }),
	]
	Limits :: {
		max_clusters : U64,
		max_glyph_indices : U64,
		max_glyphs : U64,
		max_pages : U64,
		max_placements : U64,
		max_runs : U64,
	}.{
		make : {
			max_clusters : U64,
			max_glyph_indices : U64,
			max_glyphs : U64,
			max_pages : U64,
			max_placements : U64,
			max_runs : U64,
		} -> Limits
		make = |limits| Limits.(limits)
	}
	Page : { id : Semantics.PageId, runs : Semantics.Range }
	Placement : { origin : Layout.Point, page : Semantics.PageId, run : Text.RunId }
	Prepared : {
		fragment_count : U64,
		label_rows : U64,
		lines : List(KernelLineLayout.Line),
		page_placements : List(KernelPageLayout.PlacedLine),
		pages : List(KernelPageLayout.Page),
		rows : List(KernelFacadePages.Row),
		shape : Text.Store,
		styles : List(KernelFacadeShape.RunStyle),
	}
	Work : {
		cluster_visits : U64,
		glyph_index_visits : U64,
		glyph_writes : U64,
		page_visits : U64,
		placement_visits : U64,
		run_writes : U64,
	}
	Plan :: {
		pages : List(Page),
		placements : List(Placement),
		styles : List(KernelFacadeShape.RunStyle),
		text : Text.Store,
		work : Work,
	}.{
		build : KernelFacadeShape.Plan, KernelFacadeLines.Plan, KernelFacadePages.Plan, Limits -> Try(Plan, Error)
		build = |shape, lines, pages, limits| build_plan(shape, lines, pages, limits)

		## Focused phase evidence may supply the same flat typed boundary directly.
		## The production facade uses `build`, which extracts it from validated
		## preceding plans without exposing this internal module publicly.
		build_prepared : Prepared, Limits -> Try(Plan, Error)
		build_prepared = |prepared, limits| build_prepared_plan(prepared, limits)

		pages : Plan -> List(Page)
		pages = |plan| plan.pages

		placements : Plan -> List(Placement)
		placements = |plan| plan.placements

		styles : Plan -> List(KernelFacadeShape.RunStyle)
		styles = |plan| plan.styles

		text : Plan -> Text.Store
		text = |plan| plan.text

		work : Plan -> Work
		work = |plan| plan.work
	}
}

## The request remains attached to the logical run range selected before line
## breaking. The current materializer rejects a range wider than one physical
## run explicitly; it no longer relies on a bare run ID to hide that boundary.
PaintRequest := { line : U64, origin : Layout.Point, page : Semantics.PageId, source_runs : KernelFacadeShape.LogicalRun }

build_plan : KernelFacadeShape.Plan, KernelFacadeLines.Plan, KernelFacadePages.Plan, KernelFacadeText.Limits -> Try(KernelFacadeText.Plan, KernelFacadeText.Error)
build_plan = |shape_plan, line_plan, page_plan, limits| {
	pagination = KernelFacadePages.Plan.page(page_plan)
	build_prepared_plan(
		{
			fragment_count: KernelPageLayout.Plan.fragments(pagination).len(),
			label_rows: KernelFacadePages.Plan.work(page_plan).label_rows,
			lines: KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(line_plan)),
			page_placements: KernelPageLayout.Plan.placements(pagination),
			pages: KernelPageLayout.Plan.pages(pagination),
			rows: KernelFacadePages.Plan.rows(page_plan),
			shape: KernelFacadeShape.Plan.shape(shape_plan).store,
			styles: KernelFacadeShape.Plan.styles(shape_plan),
		},
		limits,
	)
}

build_prepared_plan : KernelFacadeText.Prepared, KernelFacadeText.Limits -> Try(KernelFacadeText.Plan, KernelFacadeText.Error)
build_prepared_plan = |prepared, limits| {
	shape = prepared.shape
	styles = prepared.styles
	lines = prepared.lines
	rows = prepared.rows
	pages = prepared.pages
	page_placements = prepared.page_placements
	if styles.len() != shape.runs.len() {
		return Err(InvalidRun({ run: shape.runs.len() }))
	}
	if shape.substitutions.len() != 0 or shape.transformations.len() != 0 {
		return Err(UnsupportedRunEvidence({ run: 0 }))
	}
	if rows.len() != page_placements.len() {
		return Err(InvalidPlacement({ placement: page_placements.len() }))
	}
	run_count = checked_add(rows.len(), prepared.label_rows)?
	check_limit(shape.clusters.len(), limits.max_clusters, Clusters)?
	check_limit(shape.glyph_indices.len(), limits.max_glyph_indices, GlyphIndices)?
	check_limit(shape.glyphs.len(), limits.max_glyphs, Glyphs)?
	check_limit(pages.len(), limits.max_pages, Pages)?
	check_limit(run_count, limits.max_placements, Placements)?
	check_limit(run_count, limits.max_runs, Runs)?
	var $requests = List.with_capacity(run_count)
	var $placement_cursor = 0
	var $page_index = 0
	while $page_index < pages.len() {
		page = list_at(pages, $page_index)
		if page.id.index() != $page_index or page.placements.start() != $placement_cursor or !range_fits(page.placements, page_placements.len()) {
			return Err(InvalidPage({ page: $page_index }))
		}
		page_placement_end = range_end(page.placements)?
		while $placement_cursor < page_placement_end {
			placement = list_at(page_placements, $placement_cursor)
			if placement.line != $placement_cursor or placement.line >= rows.len() or placement.fragment.index() >= prepared.fragment_count {
				return Err(InvalidPlacement({ placement: $placement_cursor }))
			}
			row = list_at(rows, placement.line)
			match row.label {
				NoLabel => {}
				Label(label) => {
					$requests = $requests.append({ line: label.line, origin: placement.baseline, page: page.id, source_runs: label.runs })
				}
			}
			if row.body_offset.raw() < 0 {
				return Err(InvalidPlacement({ placement: $placement_cursor }))
			}
			body_x = checked_i64_add(placement.baseline.x.raw(), row.body_offset.raw())?
			body_origin = { x: Layout.Unit.from_raw(body_x), y: placement.baseline.y }
			$requests = $requests.append({ line: row.body_line, origin: body_origin, page: page.id, source_runs: row.body_runs })
			$placement_cursor = $placement_cursor + 1
		}
		$page_index = $page_index + 1
	}
	if $placement_cursor != rows.len() or $requests.len() != run_count {
		return Err(InvalidPlacement({ placement: $placement_cursor }))
	}
	var $clusters = List.with_capacity(shape.clusters.len())
	var $glyph_indices = List.with_capacity(shape.glyph_indices.len())
	var $glyphs = List.with_capacity(shape.glyphs.len())
	var $placements = List.with_capacity(run_count)
	var $runs = List.with_capacity(run_count)
	var $final_styles = List.with_capacity(run_count)

	## Page run ranges are counted over the final materialized runs, because
	## one paint request may split into several physical face runs.
	var $page_records = List.with_capacity(pages.len())
	var $page_cursor = 0
	var $page_run_start = 0
	var $request_index = 0
	while $request_index < $requests.len() {
		request = list_at($requests, $request_index)
		while $page_cursor < request.page.index() {
			$page_records = $page_records.append({
				id: Semantics.PageId.from_index($page_cursor),
				runs: Semantics.Range.from_start_and_length($page_run_start, $runs.len() - $page_run_start),
			})
			$page_cursor = $page_cursor + 1
			$page_run_start = $runs.len()
		}
		if request.source_runs.physical.length() != 1 {
			split = paint_split_logical(
				{
					clusters: $clusters,
					glyph_indices: $glyph_indices,
					glyphs: $glyphs,
					placements: $placements,
					runs: $runs,
					styles: $final_styles,
				},
				shape,
				styles,
				lines,
				request,
				limits,
			)?
			$clusters = split.clusters
			$glyph_indices = split.glyph_indices
			$glyphs = split.glyphs
			$placements = split.placements
			$runs = split.runs
			$final_styles = split.styles
			$request_index = $request_index + 1
		} else {
			source_run_index = single_run_index(request.source_runs)?
			if source_run_index >= shape.runs.len() or request.line >= lines.len() {
				return Err(InvalidLine({ line: request.line, run: source_run_index }))
			}
			run = list_at(shape.runs, source_run_index)
			line = list_at(lines, request.line)
			if run.id.index() != source_run_index or !range_fits(run.clusters, shape.clusters.len()) or !range_fits(run.glyphs, shape.glyphs.len()) or run.clusters.length() == 0 or run.glyphs.length() == 0 {
				return Err(InvalidRun({ run: source_run_index }))
			}
			if run.substitutions.length() != 0 or run.transformations.length() != 0 {
				return Err(UnsupportedRunEvidence({ run: source_run_index }))
			}
			if line.clusters.length() == 0 or !range_within(line.clusters, run.clusters) or !text_range_within(line.source, run.source) {
				return Err(InvalidLine({ line: request.line, run: source_run_index }))
			}
			cluster_start = $clusters.len()
			glyph_start = $glyphs.len()
			var $source_scalar = line.source.scalars.start()
			var $source_byte = line.source.utf8_bytes.start()
			var $cluster_index = line.clusters.start()
			cluster_end = range_end(line.clusters)?
			while $cluster_index < cluster_end {
				cluster = list_at(shape.clusters, $cluster_index)
				if cluster.source.scalars.start() != $source_scalar or cluster.source.utf8_bytes.start() != $source_byte or !range_fits(cluster.glyphs, shape.glyph_indices.len()) or cluster.glyphs.length() == 0 {
					return Err(InvalidCluster({ cluster: $cluster_index, line: request.line }))
				}
				$source_scalar = range_end(cluster.source.scalars)?
				$source_byte = range_end(cluster.source.utf8_bytes)?
				if $source_scalar > range_end(line.source.scalars)? or $source_byte > range_end(line.source.utf8_bytes)? {
					return Err(InvalidCluster({ cluster: $cluster_index, line: request.line }))
				}
				new_references = $glyph_indices.len()
				var $reference = cluster.glyphs.start()
				reference_end = range_end(cluster.glyphs)?
				while $reference < reference_end {
					glyph_index = list_at(shape.glyph_indices, $reference)
					if glyph_index < run.glyphs.start() or glyph_index >= range_end(run.glyphs)? {
						return Err(InvalidGlyph({ glyph: glyph_index, line: request.line }))
					}
					check_limit(checked_add($glyphs.len(), 1)?, limits.max_glyphs, Glyphs)?
					check_limit(checked_add($glyph_indices.len(), 1)?, limits.max_glyph_indices, GlyphIndices)?
					$glyph_indices = $glyph_indices.append($glyphs.len())
					$glyphs = $glyphs.append(list_at(shape.glyphs, glyph_index))
					$reference = $reference + 1
				}
				check_limit(checked_add($clusters.len(), 1)?, limits.max_clusters, Clusters)?
				$clusters = $clusters.append({
					..cluster,
					glyphs: Semantics.Range.from_start_and_length(new_references, $glyph_indices.len() - new_references),
				})
				$cluster_index = $cluster_index + 1
			}
			if $source_scalar != range_end(line.source.scalars)? or $source_byte != range_end(line.source.utf8_bytes)? {
				return Err(InvalidLine({ line: request.line, run: source_run_index }))
			}
			new_run_id = Text.RunId.from_index($runs.len())
			$runs = $runs.append({
				..run,
				clusters: Semantics.Range.from_start_and_length(cluster_start, $clusters.len() - cluster_start),
				glyphs: Semantics.Range.from_start_and_length(glyph_start, $glyphs.len() - glyph_start),
				id: new_run_id,
				source: line.source,
				substitutions: Semantics.Range.from_start_and_length(0, 0),
				transformations: Semantics.Range.from_start_and_length(0, 0),
			})
			$placements = $placements.append({ origin: request.origin, page: request.page, run: new_run_id })
			$final_styles = $final_styles.append(list_at(styles, source_run_index))
			$request_index = $request_index + 1
		}
	}
	while $page_cursor < pages.len() {
		$page_records = $page_records.append({
			id: Semantics.PageId.from_index($page_cursor),
			runs: Semantics.Range.from_start_and_length($page_run_start, $runs.len() - $page_run_start),
		})
		$page_cursor = $page_cursor + 1
		$page_run_start = $runs.len()
	}
	if $clusters.len() != shape.clusters.len() or $glyph_indices.len() != shape.glyph_indices.len() or $glyphs.len() != shape.glyphs.len() {
		return Err(InvalidRun({ run: $runs.len() }))
	}
	text = {
		clusters: $clusters,
		glyph_indices: $glyph_indices,
		glyphs: $glyphs,
		runs: $runs,
		substitutions: [],
		transformations: [],
	}
	Ok(
		KernelFacadeText.Plan.{
			pages: $page_records,
			placements: $placements,
			styles: $final_styles,
			text,
			work: {
				cluster_visits: text.clusters.len(),
				glyph_index_visits: text.glyph_indices.len(),
				glyph_writes: text.glyphs.len(),
				page_visits: pages.len(),
				placement_visits: page_placements.len(),
				run_writes: text.runs.len(),
			},
		},
	)
}

## The lists a paint request appends to, moved through the split helper so
## every buffer keeps its unique in-place ownership.
PaintAccumulator : {
	clusters : List(Text.Cluster),
	glyph_indices : List(U64),
	glyphs : List(Text.Glyph),
	placements : List(KernelFacadeText.Placement),
	runs : List(Text.Run),
	styles : List(KernelFacadeShape.RunStyle),
}

## Materialize one line of a logical run that spans several physical face
## runs: one final run and placement per overlapped physical segment, with
## origins advanced by the accumulated widths of the preceding segments.
paint_split_logical : PaintAccumulator, Text.Store, List(KernelFacadeShape.RunStyle), List(KernelLineLayout.Line), PaintRequest, KernelFacadeText.Limits -> Try(PaintAccumulator, KernelFacadeText.Error)
paint_split_logical = |accumulator, shape, styles, lines, request, limits| {
	var $clusters = accumulator.clusters
	var $glyph_indices = accumulator.glyph_indices
	var $glyphs = accumulator.glyphs
	var $placements = accumulator.placements
	var $runs = accumulator.runs
	var $final_styles = accumulator.styles
	physical_start = request.source_runs.physical.start()
	physical_end = range_end(request.source_runs.physical)?
	if physical_end > shape.runs.len() or physical_end <= physical_start or request.line >= lines.len() or physical_end > styles.len() {
		return Err(InvalidLine({ line: request.line, run: physical_start }))
	}
	line = list_at(lines, request.line)
	first = list_at(shape.runs, physical_start)
	last = list_at(shape.runs, physical_end - 1)
	last_cluster_end = range_end(last.clusters)?
	last_scalar_end = range_end(last.source.scalars)?
	last_byte_end = range_end(last.source.utf8_bytes)?
	if last_cluster_end < first.clusters.start() or last_scalar_end < first.source.scalars.start() or last_byte_end < first.source.utf8_bytes.start() {
		return Err(InvalidRun({ run: physical_start }))
	}
	merged_clusters = Semantics.Range.from_start_and_length(first.clusters.start(), last_cluster_end - first.clusters.start())
	merged_source = {
		scalars: Semantics.Range.from_start_and_length(first.source.scalars.start(), last_scalar_end - first.source.scalars.start()),
		utf8_bytes: Semantics.Range.from_start_and_length(first.source.utf8_bytes.start(), last_byte_end - first.source.utf8_bytes.start()),
	}
	if line.clusters.length() == 0 or !range_within(line.clusters, merged_clusters) or !text_range_within(line.source, merged_source) {
		return Err(InvalidLine({ line: request.line, run: physical_start }))
	}
	line_cluster_end = range_end(line.clusters)?
	line_scalar_end = range_end(line.source.scalars)?
	line_byte_end = range_end(line.source.utf8_bytes)?
	var $advance_offset = 0
	var $source_scalar = line.source.scalars.start()
	var $source_byte = line.source.utf8_bytes.start()
	var $physical = physical_start
	while $physical < physical_end {
		run = list_at(shape.runs, $physical)
		if run.id.index() != $physical or !range_fits(run.clusters, shape.clusters.len()) or !range_fits(run.glyphs, shape.glyphs.len()) or run.clusters.length() == 0 or run.glyphs.length() == 0 {
			return Err(InvalidRun({ run: $physical }))
		}
		if run.substitutions.length() != 0 or run.transformations.length() != 0 {
			return Err(UnsupportedRunEvidence({ run: $physical }))
		}
		run_cluster_end = range_end(run.clusters)?
		segment_start = if line.clusters.start() > run.clusters.start() line.clusters.start() else run.clusters.start()
		segment_end = if line_cluster_end < run_cluster_end line_cluster_end else run_cluster_end
		if segment_end > segment_start {
			cluster_start_new = $clusters.len()
			glyph_start_new = $glyphs.len()
			segment_first = list_at(shape.clusters, segment_start)
			segment_scalar_start = segment_first.source.scalars.start()
			segment_byte_start = segment_first.source.utf8_bytes.start()
			var $segment_advance = 0
			var $cluster_index = segment_start
			while $cluster_index < segment_end {
				cluster = list_at(shape.clusters, $cluster_index)
				if cluster.source.scalars.start() != $source_scalar or cluster.source.utf8_bytes.start() != $source_byte or !range_fits(cluster.glyphs, shape.glyph_indices.len()) or cluster.glyphs.length() == 0 {
					return Err(InvalidCluster({ cluster: $cluster_index, line: request.line }))
				}
				$source_scalar = range_end(cluster.source.scalars)?
				$source_byte = range_end(cluster.source.utf8_bytes)?
				if $source_scalar > line_scalar_end or $source_byte > line_byte_end {
					return Err(InvalidCluster({ cluster: $cluster_index, line: request.line }))
				}
				new_references = $glyph_indices.len()
				var $reference = cluster.glyphs.start()
				reference_end = range_end(cluster.glyphs)?
				while $reference < reference_end {
					glyph_index = list_at(shape.glyph_indices, $reference)
					if glyph_index < run.glyphs.start() or glyph_index >= range_end(run.glyphs)? {
						return Err(InvalidGlyph({ glyph: glyph_index, line: request.line }))
					}
					check_limit(checked_add($glyphs.len(), 1)?, limits.max_glyphs, Glyphs)?
					check_limit(checked_add($glyph_indices.len(), 1)?, limits.max_glyph_indices, GlyphIndices)?
					glyph = list_at(shape.glyphs, glyph_index)
					$segment_advance = checked_i64_add($segment_advance, glyph.advance_x.raw())?
					$glyph_indices = $glyph_indices.append($glyphs.len())
					$glyphs = $glyphs.append(glyph)
					$reference = $reference + 1
				}
				check_limit(checked_add($clusters.len(), 1)?, limits.max_clusters, Clusters)?
				$clusters = $clusters.append({
					..cluster,
					glyphs: Semantics.Range.from_start_and_length(new_references, $glyph_indices.len() - new_references),
				})
				$cluster_index = $cluster_index + 1
			}
			check_limit(checked_add($runs.len(), 1)?, limits.max_runs, Runs)?
			check_limit(checked_add($placements.len(), 1)?, limits.max_placements, Placements)?
			new_run_id = Text.RunId.from_index($runs.len())
			origin_x = checked_i64_add(request.origin.x.raw(), $advance_offset)?
			$runs = $runs.append({
				..run,
				clusters: Semantics.Range.from_start_and_length(cluster_start_new, $clusters.len() - cluster_start_new),
				glyphs: Semantics.Range.from_start_and_length(glyph_start_new, $glyphs.len() - glyph_start_new),
				id: new_run_id,
				source: {
					scalars: Semantics.Range.from_start_and_length(segment_scalar_start, $source_scalar - segment_scalar_start),
					utf8_bytes: Semantics.Range.from_start_and_length(segment_byte_start, $source_byte - segment_byte_start),
				},
				substitutions: Semantics.Range.from_start_and_length(0, 0),
				transformations: Semantics.Range.from_start_and_length(0, 0),
			})
			$placements = $placements.append({ origin: { x: Layout.Unit.from_raw(origin_x), y: request.origin.y }, page: request.page, run: new_run_id })
			$final_styles = $final_styles.append(list_at(styles, $physical))
			$advance_offset = checked_i64_add($advance_offset, $segment_advance)?
		}
		$physical = $physical + 1
	}
	if $source_scalar != line_scalar_end or $source_byte != line_byte_end {
		return Err(InvalidLine({ line: request.line, run: physical_start }))
	}
	Ok({
		clusters: $clusters,
		glyph_indices: $glyph_indices,
		glyphs: $glyphs,
		placements: $placements,
		runs: $runs,
		styles: $final_styles,
	})
}

single_run_index : KernelFacadeShape.LogicalRun -> Try(U64, KernelFacadeText.Error)
single_run_index = |logical| {
	physical = logical.physical
	if physical.length() != 1 {
		Err(InvalidRun({ run: physical.start() }))
	} else {
		Ok(physical.start())
	}
}

text_range_within : Semantics.TextRange, Semantics.TextRange -> Bool
text_range_within = |inner, outer| range_within(inner.scalars, outer.scalars) and range_within(inner.utf8_bytes, outer.utf8_bytes)

range_within : Semantics.Range, Semantics.Range -> Bool
range_within = |inner, outer| {
	if inner.start() < outer.start() {
		False
	} else {
		offset = inner.start() - outer.start()
		offset <= outer.length() and inner.length() <= outer.length() - offset
	}
}

range_fits : Semantics.Range, U64 -> Bool
range_fits = |range, available| range.start() <= available and range.length() <= available - range.start()

range_end : Semantics.Range -> Try(U64, KernelFacadeText.Error)
range_end = |range| checked_add(range.start(), range.length())

check_limit : U64, U64, KernelFacadeText.Dimension -> Try({}, KernelFacadeText.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

checked_add : U64, U64 -> Try(U64, KernelFacadeText.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_i64_add : I64, I64 -> Try(I64, KernelFacadeText.Error)
checked_i64_add = |left, right| match I64.plus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade text index escaped"
	}
	Ok(value) => value
}

test_text : Text.Store
test_text = {
	clusters: [
		{
			glyphs: Semantics.Range.from_start_and_length(0, 1),
			kind: OneToOne,
			source: { scalars: Semantics.Range.from_start_and_length(0, 1), utf8_bytes: Semantics.Range.from_start_and_length(0, 1) },
		},
		{
			glyphs: Semantics.Range.from_start_and_length(1, 1),
			kind: OneToOne,
			source: { scalars: Semantics.Range.from_start_and_length(1, 1), utf8_bytes: Semantics.Range.from_start_and_length(1, 1) },
		},
	],
	glyph_indices: [0, 1],
	glyphs: [
		{ advance_x: Layout.Unit.from_raw(500), advance_y: Layout.Unit.from_raw(0), id: Text.GlyphId.from_raw(1), offset_x: Layout.Unit.from_raw(0), offset_y: Layout.Unit.from_raw(0) },
		{ advance_x: Layout.Unit.from_raw(500), advance_y: Layout.Unit.from_raw(0), id: Text.GlyphId.from_raw(2), offset_x: Layout.Unit.from_raw(0), offset_y: Layout.Unit.from_raw(0) },
	],
	runs: [
		{
			actual_text: FromOccurrence,
			clusters: Semantics.Range.from_start_and_length(0, 2),
			direction: LeftToRight,
			glyphs: Semantics.Range.from_start_and_length(0, 2),
			id: Text.RunId.from_index(0),
			instance: Font.InstanceId.from_index(0),
			language: Language("en"),
			occurrence: Semantics.OccurrenceId.from_index(0),
			script: Font.Script.from_iso15924("Latn"),
			size: Layout.Unit.from_raw(1000),
			source: { scalars: Semantics.Range.from_start_and_length(0, 2), utf8_bytes: Semantics.Range.from_start_and_length(0, 2) },
			substitutions: Semantics.Range.from_start_and_length(0, 0),
			transformations: Semantics.Range.from_start_and_length(0, 0),
			writing_mode: Horizontal,
		},
	],
	substitutions: [],
	transformations: [],
}

test_lines : List(KernelLineLayout.Line)
test_lines = [
	{
		advance: Layout.Unit.from_raw(500),
		clusters: Semantics.Range.from_start_and_length(0, 1),
		source: { scalars: Semantics.Range.from_start_and_length(0, 1), utf8_bytes: Semantics.Range.from_start_and_length(0, 1) },
	},
	{
		advance: Layout.Unit.from_raw(500),
		clusters: Semantics.Range.from_start_and_length(1, 1),
		source: { scalars: Semantics.Range.from_start_and_length(1, 1), utf8_bytes: Semantics.Range.from_start_and_length(1, 1) },
	},
]

test_style : KernelFacadeShape.RunStyle
test_style = { color: Srgb(Rgb({ blue: 0, green: 0, red: 0 })), leading: Layout.Unit.from_raw(1200) }

test_limits : KernelFacadeText.Limits
test_limits = KernelFacadeText.Limits.make({ max_clusters: 2, max_glyph_indices: 2, max_glyphs: 2, max_pages: 1, max_placements: 2, max_runs: 2 })

test_prepared : Text.Store -> KernelFacadeText.Prepared
test_prepared = |shape| {
	fragment_count: 1,
	label_rows: 1,
	lines: test_lines,
	page_placements: [{ baseline: { x: Layout.Unit.from_raw(10), y: Layout.Unit.from_raw(20) }, fragment: Semantics.FragmentId.from_index(0), line: 0 }],
	pages: [{ fragments: Semantics.Range.from_start_and_length(0, 1), id: Semantics.PageId.from_index(0), placements: Semantics.Range.from_start_and_length(0, 1) }],
	rows: [
		{
			body_line: 1,
			body_offset: Layout.Unit.from_raw(5),
			body_runs: { physical: Semantics.Range.from_start_and_length(0, 1) },
			label: Label({ line: 0, runs: { physical: Semantics.Range.from_start_and_length(0, 1) } }),
		},
	],
	shape,
	styles: [test_style],
}

## A label and indented body sharing one visual row become dense, independently
## owned final runs without duplicating their cluster or glyph payload.
expect {
	plan = KernelFacadeText.Plan.build_prepared(test_prepared(test_text), test_limits)?
	text = KernelFacadeText.Plan.text(plan)
	placements = KernelFacadeText.Plan.placements(plan)
	first_run = list_at(text.runs, 0)
	second_run = list_at(text.runs, 1)
	text.runs.len() == 2 and text.clusters.len() == 2 and text.glyph_indices == [0, 1] and text.glyphs.len() == 2 and first_run.source.scalars.start() == 0 and second_run.source.scalars.start() == 1 and list_at(placements, 1).run.index() == 1 and list_at(placements, 1).origin.x.raw() == 15
}

## The constrained facade never drops advanced substitution evidence while
## splitting a run.
expect {
	run = list_at(test_text.runs, 0)
	bad = { ..test_text, runs: [{ ..run, substitutions: Semantics.Range.from_start_and_length(0, 1) }] }
	match KernelFacadeText.Plan.build_prepared(test_prepared(bad), test_limits) {
		Err(UnsupportedRunEvidence({ run: 0 })) => True
		_ => False
	}
}

## A cluster cannot smuggle a glyph from outside its source run.
expect {
	bad = { ..test_text, glyph_indices: [9, 1] }
	match KernelFacadeText.Plan.build_prepared(test_prepared(bad), test_limits) {
		Err(InvalidGlyph({ glyph: 9, line: 0 })) => True
		_ => False
	}
}

## The multi-face materializer accepts a widened logical range only when its
## physical runs actually exist; a range past the shaped store is rejected
## before it can emit a partial visual run.
expect {
	prepared = test_prepared(test_text)
	row = list_at(prepared.rows, 0)
	bad = {
		..prepared,
		rows: [{ ..row, body_runs: { physical: Semantics.Range.from_start_and_length(0, 2) } }],
	}
	match KernelFacadeText.Plan.build_prepared(bad, test_limits) {
		Err(InvalidLine({ line: 1, run: 0 })) => True
		_ => False
	}
}
