import Document
import Font
import KernelBuiltInFont
import KernelFont
import KernelSemantics
import KernelShape
import KernelTextSemantics
import KernelFacadeLines
import KernelFacadePages
import KernelFacadeReferenceLines
import KernelFacadeReferenceShape
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelLineLayout
import KernelNavigation
import KernelPageLabels
import KernelPageLayout
import Layout
import Semantics
import Text
import Theme

## One-way body references: measure fixed-width atoms, commit page geometry,
## resolve exact labels, then shape and paint against those accepted rows.
## Neither symbolic sources nor a second line-wrap pass cross this boundary.
KernelFacadeReferences :: [].{
	Error : [
		ArithmeticOverflow,
		Semantics(KernelFacadeSemantics.Error),
		Shape(KernelFacadeReferenceShape.Error),
		Lines(KernelFacadeReferenceLines.Error),
		Pages(KernelFacadePages.Error),
		Text(KernelFacadeText.Error),
		Navigation(Document.NavigationError),
		UnknownDestination({ reference : U64 }),
		MissingAnchor({ reference : U64 }),
		Format({ error : KernelPageLabels.Error, reference : U64 }),
		FieldOverflow({ reference : U64, width : Layout.Unit, required : Layout.Unit }),
		InvalidMapping({ item : U64 }),
	]
	Limits : {
		semantics : KernelFacadeSemantics.Limits,
		shape : KernelFacadeShape.Limits,
		lines : KernelFacadeLines.Limits,
		pages : KernelFacadePages.Limits,
		text : KernelFacadeText.Limits,
		navigation : KernelNavigation.Limits,
		max_reference_bytes : U64,
	}

	## The resolved target physical_page is one-based.
	Resolved : { reference : U64, physical_page : U64, value : Str }
	Work : {
		reference_atoms : U64,
		reference_lookups : U64,
		reference_format_bytes : U64,
		reference_piece_visits : U64,
		shape_metric_reads : U64,
		measurement : KernelFacadeReferenceLines.Work,
		normalization_chunks : U64,
		literal_shape_requests : U64,
		measured_items : U64,
		measured_rows : U64,
		committed_row_visits : U64,
		anchor_item_visits : U64,
		registry_lookup_steps : U64,
		resolved_labels : U64,
		resolved_label_bytes : U64,
		mapping_cluster_visits : U64,
		mapping_glyph_visits : U64,
		reference_fit_run_visits : U64,
		positioned_pieces : U64,
	}
	View : {
		semantics : KernelFacadeSemantics.Plan,
		shape : KernelFacadeShape.Plan,
		text : KernelFacadeText.Plan,
		measured : KernelFacadePages.Measured,
		paint : KernelFacadePages.MeasuredPaint,
		registry : KernelNavigation.Registry,
		labels : KernelNavigation.LabelPlan,
		resolved : List(Resolved),
		anchors : List(KernelNavigation.CommittedAnchor),
		work : Work,
	}
	Plan :: View.{
		build : Document.NormalizedAuthoring, KernelFacadeShape.FontSelection, Theme, Layout.Size, KernelFacadePages.FlowSelection, Limits -> Try(Plan, Error)
		build = |authoring, selection, theme, page_size, flow, limits| build_plan(authoring, selection, theme, page_size, flow, limits)
		view : Plan -> View
		view = |Plan.(view)| view
	}
}

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.FontSelection, Theme, Layout.Size, KernelFacadePages.FlowSelection, KernelFacadeReferences.Limits -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
build_plan = |authoring, selection, theme, page_size, flow, limits| {
	symbolic = KernelFacadeSemantics.Symbolic.build(authoring, limits.semantics) ? Semantics
	spine = KernelFacadeSemantics.Symbolic.view(symbolic)
	occurrences = checked_add(spine.literals.len(), spine.pending.len())?
	registry = KernelNavigation.Registry.build(spine.destinations, { forms: 0, nodes: spine.nodes.len(), occurrences, pages: 0, semantic_annotations: 0 }, limits.navigation) ? Navigation
	literal_shape = KernelFacadeReferenceShape.Plan.build(authoring, spine.literals, KernelFacadeSources.Plan.sources(spine.sources), selection, theme, limits.shape) ? Shape
	literal = KernelFacadeReferenceShape.Plan.view(literal_shape)
	lines = KernelFacadeReferenceLines.Plan.build(spine, literal_shape, page_size, theme, limits.lines) ? Lines
	measured_lines = KernelFacadeReferenceLines.Plan.view(lines)
	measured = KernelFacadePages.Measured.build(authoring, measured_lines.input, page_size, theme, flow, limits.pages) ? Pages
	pages = KernelPageLayout.Choice.pages(KernelFacadePages.Measured.view(measured).choice).len()
	paint = KernelFacadePages.Measured.paint(measured, authoring, measured_lines.input, measured_lines.visible_advances, page_size, theme, limits.pages) ? Pages
	labels = KernelNavigation.LabelPlan.build(authoring.page_labels, pages, limits.navigation) ? Navigation
	committed = commit_literal_anchors(occurrences, measured_lines, literal, paint.rows)?
	resolved = resolve_labels(authoring, registry, labels, committed.anchors, limits.max_reference_bytes)?
	finalized = KernelFacadeSemantics.Symbolic.finalize_with_contexts(symbolic, resolved.values) ? Semantics
	semantics = finalized.plan
	final_shape = KernelFacadeReferenceShape.Plan.build(authoring, finalized.contexts, KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics)), selection, theme, limits.shape) ? Shape
	final = KernelFacadeReferenceShape.Plan.view(final_shape)
	shape = KernelFacadeReferenceShape.Plan.final_shape(final_shape, authoring, spine.block_ownership, occurrences) ? Shape
	mapping = map_literal_clusters(literal, final)?
	positioned = position_items(authoring, spine.pending, measured_lines, literal, final, mapping.entries, paint.rows, committed.anchors)?
	text = KernelFacadeText.Plan.build_positioned({ shape: final.store, styles: final.styles, lines: positioned.lines, origins: Origins(final.origins), pages, pieces: positioned.pieces }, paint.rules, paint.flow, limits.text) ? Text
	Ok(
		KernelFacadeReferences.Plan.{
			semantics,
			shape,
			text,
			measured,
			paint,
			registry,
			labels,
			resolved: resolved.facts,
			anchors: positioned.anchors,
			work: {
				reference_atoms: spine.pending.len(),
				reference_lookups: checked_add(resolved.steps, resolved.values.len())?,
				reference_format_bytes: resolved.bytes,
				reference_piece_visits: positioned.visits,
				shape_metric_reads: checked_add(literal.work.shape.metric_reads, final.work.shape.metric_reads)?,
				measurement: measured_lines.work,
				normalization_chunks: authoring.reference_chunks.len(),
				literal_shape_requests: literal.requests.len(),
				measured_items: measured_lines.items.len(),
				measured_rows: measured_lines.rows.len(),
				committed_row_visits: paint.rows.len(),
				anchor_item_visits: committed.visits,
				registry_lookup_steps: resolved.steps,
				resolved_labels: resolved.values.len(),
				resolved_label_bytes: resolved.bytes,
				mapping_cluster_visits: mapping.clusters,
				mapping_glyph_visits: mapping.glyphs,
				reference_fit_run_visits: positioned.fit_visits,
				positioned_pieces: positioned.pieces.len(),
			},
		},
	)
}

commit_literal_anchors : U64, KernelFacadeReferenceLines.View, KernelFacadeReferenceShape.View, List(KernelFacadePages.PositionedRow) -> Try({ anchors : List(KernelNavigation.CommittedAnchor), visits : U64 }, KernelFacadeReferences.Error)
commit_literal_anchors = |occurrences, lines, shape, rows| {
	var $anchors = List.repeat(Unplaced, occurrences)
	var $visits = 0
	for row in rows {
		if !row.artifact {
			span = list_at(lines.rows, row.row).items
			var $item = span.start()
			while $item < span.start() + span.length() {
				item = list_at(lines.items, $item)
				$visits = $visits + 1
				match item.source {
					ReferenceAtom(_) => {}
					LiteralCluster(source) => {
						run = list_at(shape.store.runs, source.run)
						occurrence = occurrence_of(run)?
						match list_at($anchors, occurrence) {
							At(_) => {}
							Unplaced => {
								origin = { ..row.origin, x: add_unit(row.origin.x, list_at(lines.item_offsets, $item))? }
								rect = anchor_rect(origin, item.advance, run.size, list_at(shape.styles, source.run).leading)?
								$anchors = list_set($anchors, occurrence, At({ page: Semantics.PageId.from_index(row.page), rect }))
							}
						}
					}
				}
				$item = $item + 1
			}
		}
	}
	Ok({ anchors: $anchors, visits: $visits })
}

resolve_labels : Document.NormalizedAuthoring, KernelNavigation.Registry, KernelNavigation.LabelPlan, List(KernelNavigation.CommittedAnchor), U64 -> Try({ values : List(Str), facts : List(KernelFacadeReferences.Resolved), steps : U64, bytes : U64 }, KernelFacadeReferences.Error)
resolve_labels = |authoring, registry, labels, anchors, max_bytes| {
	destinations = KernelNavigation.Registry.destinations(registry)
	var $values = List.with_capacity(authoring.page_references.len())
	var $facts = List.with_capacity(authoring.page_references.len())
	var $steps = 0
	var $bytes = 0
	var $reference = 0
	while $reference < authoring.page_references.len() {
		record = list_at(authoring.page_references, $reference)
		found = KernelNavigation.Registry.lookup(registry, record.spec.destination)
		$steps = checked_add($steps, found.steps)?
		destination = match found.result {
			Missing => return Err(UnknownDestination({ reference: $reference }))
			Found(id) => list_at(destinations, id.index())
		}
		anchor = match list_at(anchors, destination.anchor.index()) {
			Unplaced => return Err(MissingAnchor({ reference: $reference }))
			At(located) => located
		}
		value = match record.spec.numbering {
			Physical => {
				text = checked_add(anchor.page.index(), 1)?.to_str()
				if text.count_utf8_bytes() > max_bytes {
					return Err(Format({ error: LimitExceeded({ attempted: text.count_utf8_bytes(), limit: max_bytes }), reference: $reference }))
				}
				text
			}
			PageLabel => KernelPageLabels.format(labels, anchor.page.index(), max_bytes) ? |error| Format({ error, reference: $reference })
		}
		$bytes = checked_add($bytes, value.count_utf8_bytes())?
		$values = $values.append(value)
		$facts = $facts.append({ reference: $reference, physical_page: checked_add(anchor.page.index(), 1)?, value })
		$reference = $reference + 1
	}
	Ok({ values: $values, facts: $facts, steps: $steps, bytes: $bytes })
}

MappedCluster : [Unmapped, Mapped({ cluster : U64, run : U64 })]

## Exact literal sources and styles are unchanged by reference resolution.
## Verify the final shaping facts once and retain a dense cluster map;
## accepted row traversal never searches text or re-wraps its content.
map_literal_clusters : KernelFacadeReferenceShape.View, KernelFacadeReferenceShape.View -> Try({ entries : List(MappedCluster), clusters : U64, glyphs : U64 }, KernelFacadeReferences.Error)
map_literal_clusters = |measured, final| {
	var $entries = List.repeat(Unmapped, measured.store.clusters.len())
	var $clusters = 0
	var $glyphs = 0
	for literal in measured.literal_runs {
		context = list_at(measured.literals, literal.context)
		id = context.occurrence.id.index()
		if id >= final.literal_runs.len() {
			return Err(InvalidMapping({ item: id }))
		}
		resolved = list_at(final.literal_runs, id)
		if literal.runs.length() != resolved.runs.length() {
			return Err(InvalidMapping({ item: id }))
		}
		var $physical = 0
		while $physical < literal.runs.length() {
			old_run = list_at(measured.store.runs, literal.runs.start() + $physical)
			new_run_index = resolved.runs.start() + $physical
			new_run = list_at(final.store.runs, new_run_index)
			if old_run.source != new_run.source or old_run.clusters.length() != new_run.clusters.length() or old_run.size != new_run.size {
				return Err(InvalidMapping({ item: id }))
			}
			var $cluster = 0
			while $cluster < old_run.clusters.length() {
				old_index = old_run.clusters.start() + $cluster
				new_index = new_run.clusters.start() + $cluster
				old = list_at(measured.store.clusters, old_index)
				new = list_at(final.store.clusters, new_index)
				if old.source != new.source or old.glyphs.length() != new.glyphs.length() {
					return Err(InvalidMapping({ item: old_index }))
				}
				var $glyph = 0
				while $glyph < old.glyphs.length() {
					old_glyph = list_at(measured.store.glyphs, list_at(measured.store.glyph_indices, old.glyphs.start() + $glyph))
					new_glyph = list_at(final.store.glyphs, list_at(final.store.glyph_indices, new.glyphs.start() + $glyph))
					if old_glyph != new_glyph {
						return Err(InvalidMapping({ item: old_index }))
					}
					$glyphs = $glyphs + 1
					$glyph = $glyph + 1
				}
				$entries = list_set($entries, old_index, Mapped({ cluster: new_index, run: new_run_index }))
				$clusters = $clusters + 1
				$cluster = $cluster + 1
			}
			$physical = $physical + 1
		}
	}
	if $clusters != measured.store.clusters.len() {
		return Err(InvalidMapping({ item: $clusters }))
	}
	Ok({ entries: $entries, clusters: $clusters, glyphs: $glyphs })
}

FieldFit : { runs : Semantics.Range, inset : Layout.Unit }

## Shaping already produced each physical run's exact advance. Prove the
## reserved field once per logical reference, including repeated headers;
## paint requests consume the same cached inset and run range afterward.
reference_fits : Document.NormalizedAuthoring, List(KernelFacadeSemantics.PendingContext), KernelFacadeReferenceShape.View -> Try({ fits : List(FieldFit), visits : U64 }, KernelFacadeReferences.Error)
reference_fits = |authoring, pending, final| {
	var $fits = List.with_capacity(pending.len())
	var $visits = 0
	var $reference = 0
	while $reference < pending.len() {
		context = list_at(pending, $reference)
		runs = list_at(final.literal_runs, context.occurrence.index()).runs
		var $required = 0
		var $run = runs.start()
		while $run < runs.start() + runs.length() {
			$required = checked_i64_add($required, list_at(final.advances, $run).raw())?
			$visits = $visits + 1
			$run = $run + 1
		}
		spec = list_at(authoring.page_references, $reference).spec
		if $required < 0 or $required > spec.width.raw() {
			return Err(FieldOverflow({ reference: $reference, width: spec.width, required: Layout.Unit.from_raw($required) }))
		}
		remaining = spec.width.raw() - $required
		inset = match spec.align {
			Start => 0
			Center => remaining // 2
			End => remaining
		}
		$fits = $fits.append({ runs, inset: Layout.Unit.from_raw(inset) })
		$reference = $reference + 1
	}
	Ok({ fits: $fits, visits: $visits })
}

Positioned : { lines : List(KernelLineLayout.Line), pieces : List(KernelFacadeText.PositionedPiece), anchors : List(KernelNavigation.CommittedAnchor), fit_visits : U64, visits : U64 }

position_items : Document.NormalizedAuthoring, List(KernelFacadeSemantics.PendingContext), KernelFacadeReferenceLines.View, KernelFacadeReferenceShape.View, KernelFacadeReferenceShape.View, List(MappedCluster), List(KernelFacadePages.PositionedRow), List(KernelNavigation.CommittedAnchor) -> Try(Positioned, KernelFacadeReferences.Error)
position_items = |authoring, pending, measured, literal, final, mapping, rows, anchors| {
	var $lines = []
	var $pieces = []

	## The earlier anchor arena is frozen evidence consumed by resolution.
	## Copy it once into the final owned arena before filling reference
	## anchors; never mutate a builder returned through Try.
	var $anchors = List.with_capacity(anchors.len())
	for anchor in anchors {
		$anchors = $anchors.append(anchor)
	}
	fitted = reference_fits(authoring, pending, final)?
	var $visits = 0
	for row in rows {
		span = list_at(measured.rows, row.row).items
		var $item = span.start()
		while $item < span.start() + span.length() {
			item = list_at(measured.items, $item)
			$visits = $visits + 1
			origin = { ..row.origin, x: add_unit(row.origin.x, list_at(measured.item_offsets, $item))? }
			match item.source {
				LiteralCluster(source) => {
					mapped = mapped_cluster(mapping, source.cluster)?
					first = list_at(final.store.clusters, mapped.cluster)
					var $last = first
					var $end = $item + 1
					var $advance = item.advance
					var $stop = False
					while $end < span.start() + span.length() and !$stop {
						next = list_at(measured.items, $end)
						match next.source {
							ReferenceAtom(_) => {
								$stop = True
							}
							LiteralCluster(next_source) => {
								next_mapped = mapped_cluster(mapping, next_source.cluster)?
								if next_mapped.run != mapped.run or next_mapped.cluster != mapped.cluster + ($end - $item) or list_at(measured.item_offsets, $end) != add_unit(list_at(measured.item_offsets, $item), $advance)? {
									$stop = True
								} else {
									$last = list_at(final.store.clusters, next_mapped.cluster)
									$advance = add_unit($advance, next.advance)?
									$end = $end + 1
									$visits = $visits + 1
								}
							}
						}
					}
					line = { advance: $advance, clusters: Semantics.Range.from_start_and_length(mapped.cluster, $end - $item), source: joined_source(first.source, $last.source)? }
					index = $lines.len()
					$lines = $lines.append(line)
					$pieces = $pieces.append({ artifact: row.artifact, line: index, origin, page: Semantics.PageId.from_index(row.page), source_runs: { physical: Semantics.Range.from_start_and_length(mapped.run, 1) } })
					$item = $end
				}
				ReferenceAtom(reference) => {
					if reference >= pending.len() {
						return Err(InvalidMapping({ item: $item }))
					}
					context = list_at(pending, reference)
					fit = list_at(fitted.fits, reference)
					runs = fit.runs
					var $x = add_unit(origin.x, fit.inset)?
					var $physical = runs.start()
					while $physical < runs.start() + runs.length() {
						run = list_at(final.store.runs, $physical)
						advance = list_at(final.advances, $physical)
						index = $lines.len()
						$lines = $lines.append({ advance, clusters: run.clusters, source: run.source })
						piece_origin = { ..origin, x: $x }
						$pieces = $pieces.append({ artifact: row.artifact, line: index, origin: piece_origin, page: Semantics.PageId.from_index(row.page), source_runs: { physical: Semantics.Range.from_start_and_length($physical, 1) } })
						if !row.artifact {
							match list_at($anchors, context.occurrence.index()) {
								At(_) => {}
								Unplaced => {
									rect = anchor_rect(piece_origin, advance, run.size, list_at(final.styles, $physical).leading)?
									$anchors = list_set($anchors, context.occurrence.index(), At({ page: Semantics.PageId.from_index(row.page), rect }))
								}
							}
						}
						$x = add_unit($x, advance)?
						$physical = $physical + 1
					}
					$item = $item + 1
				}
			}
		}
	}
	# The literal view is supplied explicitly so item run ids cannot be
	# accidentally reinterpreted as final physical run ids.
	if literal.store.clusters.len() != mapping.len() {
		return Err(InvalidMapping({ item: mapping.len() }))
	}
	Ok({ lines: $lines, pieces: $pieces, anchors: $anchors, fit_visits: fitted.visits, visits: $visits })
}

mapped_cluster : List(MappedCluster), U64 -> Try({ cluster : U64, run : U64 }, KernelFacadeReferences.Error)
mapped_cluster = |mapping, item| match list_at(mapping, item) {
	Mapped(value) => Ok(value)
	Unmapped => Err(InvalidMapping({ item: item }))
}

occurrence_of : Text.Run -> Try(U64, KernelFacadeReferences.Error)
occurrence_of = |run| match run.unicode {
	OccurrenceText(id) => Ok(id.index())
	_ => Err(InvalidMapping({ item: run.id.index() }))
}

anchor_rect : Layout.Point, Layout.Unit, Layout.Unit, Layout.Unit -> Try(Layout.Rect, KernelFacadeReferences.Error)
anchor_rect = |origin, width, size, leading| {
	height = if leading > size leading else size
	top = add_unit(origin.y, size)?
	bottom = checked_i64_add(top.raw(), -height.raw())?
	Ok({ origin: { x: origin.x, y: Layout.Unit.from_raw(bottom) }, size: { height, width } })
}

joined_source : Semantics.TextRange, Semantics.TextRange -> Try(Semantics.TextRange, KernelFacadeReferences.Error)
joined_source = |first, last| {
	scalar_end = checked_add(last.scalars.start(), last.scalars.length())?
	byte_end = checked_add(last.utf8_bytes.start(), last.utf8_bytes.length())?
	if scalar_end < first.scalars.start() or byte_end < first.utf8_bytes.start() {
		return Err(InvalidMapping({ item: first.scalars.start() }))
	}
	Ok({ scalars: Semantics.Range.from_start_and_length(first.scalars.start(), scalar_end - first.scalars.start()), utf8_bytes: Semantics.Range.from_start_and_length(first.utf8_bytes.start(), byte_end - first.utf8_bytes.start()) })
}

add_unit : Layout.Unit, Layout.Unit -> Try(Layout.Unit, KernelFacadeReferences.Error)
add_unit = |left, right| Ok(Layout.Unit.from_raw(checked_i64_add(left.raw(), right.raw())?))

checked_add : U64, U64 -> Try(U64, KernelFacadeReferences.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

checked_i64_add : I64, I64 -> Try(I64, KernelFacadeReferences.Error)
checked_i64_add = |left, right| match I64.plus_try(left, right) {
	Ok(value) => Ok(value)
	Err(_) => Err(ArithmeticOverflow)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "validated reference arena index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "validated reference arena update escaped"
}

test_font : {} -> Try(KernelFont.Inspection, KernelFont.Error)
test_font = |_| KernelFont.inspect(KernelBuiltInFont.bytes, KernelFont.Limits.make({ max_bytes: 200000, max_cmap_mappings: 10000, max_glyphs: 10000, max_tables: 32 }))

test_limits : KernelFacadeReferences.Limits
test_limits = {
	max_reference_bytes: 128,
	navigation: KernelNavigation.standard_limits,
	semantics: KernelFacadeSemantics.Limits.make({
		max_container_depth: 16,
		max_content_spine: 256,
		max_inline_depth: 8,
		max_nodes: 64,
		max_occurrences: 64,
		max_properties: 64,
		max_source_inputs: 64,
		semantics: KernelSemantics.Limits.make({ max_attributes: 32, max_content_spine: 256, max_fragments: 0, max_namespaces: 2, max_nodes: 64, max_occurrences: 64, max_semantic_depth: 48 }),
		sources: KernelFacadeSources.Limits.make({ max_hash_probes: 4096, max_inputs: 64, max_source_bytes: 4096, max_source_scalars: 4096, max_table_slots: 128, max_unique_sources: 64, unicode: { max_graphemes: 4096, max_line_boundaries: 4097, max_scalars: 4096, max_script_runs: 128 } }),
		text_semantics: KernelTextSemantics.Limits.make({ max_text_properties: 64, max_text_property_bytes: 4096, max_text_source_bytes: 4096, max_text_source_scalars: 4096, max_text_sources: 64 }),
	}),
	shape: KernelFacadeShape.Limits.make({ max_requests: 256, shape: KernelShape.Limits.make({ max_clusters: 4096, max_glyphs: 4096, max_scalars: 4096, max_source_bytes: 4096 }) }),
	lines: KernelFacadeLines.Limits.make({ line: KernelLineLayout.BatchLimits.make({ line: KernelLineLayout.Limits.make({ max_boundaries: 4097, max_candidates: 8192, max_clusters: 4096, max_glyph_indices: 4096, max_glyphs: 4096, max_lines: 4096 }), max_key_probes: 8192, max_lines: 4096, max_runs: 256, max_table_slots: 512, max_templates: 256 }), max_blocks: 64, max_runs: 256 }),
	pages: KernelFacadePages.Limits.make({ max_blocks: 64, max_rows: 4096, page: KernelPageLayout.Limits.make({ max_blocks: 64, max_fragments: 4096, max_lines: 4096, max_pages: 16, max_placements: 4096 }) }),
	text: KernelFacadeText.Limits.make({ max_clusters: 4096, max_glyph_indices: 4096, max_glyphs: 4096, max_pages: 16, max_placements: 4096, max_runs: 4096 }),
}

test_document : List(Document.Inline), List(Document.PageLabelRange) -> Document.NormalizedAuthoring
test_document = |inlines, labels| Document.normalize(Document.from_blocks({ contents: [Document.rich_paragraph(inlines), Document.page_break, Document.destination_paragraph("end", "Destination")], language: "en", title: "References" }).with_page_labels(labels))

# Public authoring reaches committed geometry, exact semantic Unicode and
# coalesced final text pieces with a one-way physical-page resolution.
expect {
	font = test_font({})?
	authoring = test_document([Document.plain_text("See "), Document.page_reference({ destination: "end", width: 24 }), Document.plain_text(" now")], [])
	plan = KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	store = KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(KernelFacadeSemantics.Plan.preliminary(view.semantics)))
	view.resolved == [{ reference: 0, physical_page: 2, value: "2" }]
		and store.text_sources.map(|source| source.unicode) == ["See ", " now", "Destination", "2"]
			and KernelFacadeText.Plan.pages(view.text).len() == 2
				and view.work.reference_atoms == 1
					and view.work.positioned_pieces == 4
}

# A reference-only body and configured page labels remain source-free
# until finalization. Exact Roman label Unicode is searchable final text.
expect {
	font = test_font({})?
	labels = [{ prefix: "", start_page: 0, start_number: 3, style: RomanLower }]
	authoring = test_document([Document.page_reference({ destination: "end", width: 24, numbering: PageLabel })], labels)
	plan = KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	view.resolved == [{ reference: 0, physical_page: 2, value: "iv" }]
		and view.work.reference_atoms == 1
			and view.work.literal_shape_requests == 1
				and KernelFacadeText.Plan.text(view.text).runs.len() == 2
}

# Unknown targets, an empty configured label, exact width overflow and
# formatter byte bounds all reject before a final text plan is returned.
expect {
	font = test_font({})?
	build = |authoring, limits| KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, limits)
	unknown = match build(test_document([Document.page_reference({ destination: "missing", width: 24 })], []), test_limits) {
		Err(UnknownDestination({ reference: 0 })) => True
		_ => False
	}
	empty = match build(test_document([Document.page_reference({ destination: "end", width: 24, numbering: PageLabel })], [{ prefix: "", start_page: 0, start_number: 1, style: NoNumber }]), test_limits) {
		Err(Format({ reference: 0, error: EmptyLabel })) => True
		_ => False
	}
	overflow = match build(test_document([Document.page_reference({ destination: "end", width: 0.001 })], []), test_limits) {
		Err(FieldOverflow({ reference: 0, width: _, required: _ })) => True
		_ => False
	}
	budget = match build(test_document([Document.page_reference({ destination: "end", width: 24, numbering: PageLabel })], [{ prefix: "prefix", start_page: 0, start_number: 1, style: DecimalArabic }]), { ..test_limits, max_reference_bytes: 1 }) {
		Err(Format({ reference: 0, error: LimitExceeded(_) })) => True
		_ => False
	}
	unknown and empty and overflow and budget
}

# Introducing a face used only by a resolved reference can shift the dense
# instance id of an existing literal. Literal mapping follows occurrence,
# source and glyph facts while final font instances retain their new ids.
expect {
	font = test_font({})?
	faces = [Font.FaceId.from_index(0), Font.FaceId.from_index(1), Font.FaceId.from_index(2)]
	selection = Styled({ faces, fonts: [font, font, font], roles: { code: Inherited, emphasis: Candidate(2), quote: Inherited, strong: Candidate(1) } })
	theme : Theme
	theme = { inline: { strong: { font: Face(list_at(faces, 1)) }, emphasis: { font: Face(list_at(faces, 2)) } } }
	authoring = test_document([Document.strong([Document.page_reference({ destination: "end", width: 24 })]), Document.emphasis([Document.plain_text("A")])], [])
	plan = KernelFacadeReferences.Plan.build(authoring, selection, theme, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	KernelFacadeText.Plan.text(view.text).runs.map(|run| run.instance.index()) == [1, 2, 0]
}

# Start, center and end align inside distinct reserved slots. The following
# slot's origin depends on the reserved advance, never the label's width.
expect {
	font = test_font({})?
	authoring = test_document(
		[
			Document.page_reference({ destination: "end", width: 24, align: Start }),
			Document.page_reference({ destination: "end", width: 24, align: Center }),
			Document.page_reference({ destination: "end", width: 24, align: End }),
		],
		[],
	)
	plan = KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	text = KernelFacadeText.Plan.text(view.text)
	placements = KernelFacadeText.Plan.placements(view.text)
	advance = list_at(text.glyphs, 0).advance_x.raw()
	left = Theme.default.page_margin.left.raw()
	list_at(placements, 0).origin.x.raw() == left
		and list_at(placements, 1).origin.x.raw() == left + 24000 + (24000 - advance) // 2
			and list_at(placements, 2).origin.x.raw() == left + 48000 + 24000 - advance
}
