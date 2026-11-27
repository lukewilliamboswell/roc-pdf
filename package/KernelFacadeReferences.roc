import Document
import Font
import KernelBuiltInFont
import KernelFont
import KernelSemantics
import KernelShape
import KernelStabilization
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
		FlowCycle({ reference : U64, first : U64, repeated : U64 }),
		FlowBudget({ dimension : FlowDimension, limit : U64, reference : U64 }),
		InvalidMapping({ item : U64 }),
	]
	FlowDimension : [LayoutWork, Passes, StateUnits]
	FlowLimits : { max_layout_work : U64, max_passes : U64, max_state_units : U64 }
	default_flow_limits : FlowLimits
	default_flow_limits = { max_layout_work: 4000000, max_passes: 8, max_state_units: 500000 }

	Limits : {
		flow : FlowLimits,
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
		flow_passes : U64,
		flow_work : U64,
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
		mapping_run_visits : U64,
		reference_fit_run_visits : U64,
		positioned_pieces : U64,
		contents_rows : U64,
		leader_dots : U64,
		separator_run_visits : U64,
		separator_override_writes : U64,
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
		view = |Plan.(input_view)| input_view
	}
}

build_plan : Document.NormalizedAuthoring, KernelFacadeShape.FontSelection, Theme, Layout.Size, KernelFacadePages.FlowSelection, KernelFacadeReferences.Limits -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
build_plan = |authoring, selection, theme, page_size, flow, limits| match first_flow_reference(authoring.page_references) {
	None => build_fixed_plan(authoring, selection, theme, page_size, flow, limits)
	First(reference) => build_flow_plan(authoring, selection, theme, page_size, flow, limits, reference)
}

build_flow_plan : Document.NormalizedAuthoring, KernelFacadeShape.FontSelection, Theme, Layout.Size, KernelFacadePages.FlowSelection, KernelFacadeReferences.Limits, U64 -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
build_flow_plan = |authoring, selection, theme, page_size, flow, limits, reference| {
	symbolic = KernelFacadeSemantics.Symbolic.build(authoring, limits.semantics) ? Semantics
	spine = KernelFacadeSemantics.Symbolic.view(symbolic)
	registry = KernelNavigation.Registry.build(spine.destinations, { forms: 0, nodes: spine.nodes.len(), occurrences: KernelFacadeSemantics.Symbolic.occurrence_count(symbolic), pages: 0, semantic_annotations: 0 }, limits.navigation) ? Navigation
	literal_shape = KernelFacadeReferenceShape.Plan.build(authoring, spine.literals, KernelFacadeSources.Plan.sources(spine.sources), selection, theme, limits.shape) ? Shape
	inputs = { flow, limits, literal_shape, page_size, registry, selection, spine, symbolic, theme }
	stabilize_flow(inputs, reference)
}

## Keep the single-pass path's ownership lifetimes. A speculative Pass value
## retains its authoring arenas across the next layout and is needed only for
## flow-changing fields.
build_fixed_plan : Document.NormalizedAuthoring, KernelFacadeShape.FontSelection, Theme, Layout.Size, KernelFacadePages.FlowSelection, KernelFacadeReferences.Limits -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
build_fixed_plan = |authoring, selection, theme, page_size, flow, limits| {
	symbolic = KernelFacadeSemantics.Symbolic.build(authoring, limits.semantics) ? Semantics
	spine = KernelFacadeSemantics.Symbolic.view(symbolic)
	flow_occurrences = checked_add(spine.literals.len(), spine.pending.len())?
	registry = KernelNavigation.Registry.build(spine.destinations, { forms: 0, nodes: spine.nodes.len(), occurrences: KernelFacadeSemantics.Symbolic.occurrence_count(symbolic), pages: 0, semantic_annotations: 0 }, limits.navigation) ? Navigation
	literal_shape = KernelFacadeReferenceShape.Plan.build(authoring, spine.literals, KernelFacadeSources.Plan.sources(spine.sources), selection, theme, limits.shape) ? Shape
	literal = KernelFacadeReferenceShape.Plan.view(literal_shape)
	lines = KernelFacadeReferenceLines.Plan.build(spine, literal_shape, page_size, theme, limits.lines) ? Lines
	measured_lines = KernelFacadeReferenceLines.Plan.view(lines)
	measured = KernelFacadePages.Measured.build(authoring, measured_lines.input, page_size, theme, flow, limits.pages) ? Pages
	pages = KernelPageLayout.Choice.pages(KernelFacadePages.Measured.view(measured).choice).len()
	paint = KernelFacadePages.Measured.paint(measured, authoring, measured_lines.input, measured_lines.visible_advances, page_size, theme, limits.pages) ? Pages
	labels = KernelNavigation.LabelPlan.build(authoring.page_labels, pages, limits.navigation) ? Navigation
	committed = commit_literal_anchors(flow_occurrences, measured_lines, literal, paint.rows)?
	resolved = resolve_labels(authoring, registry, labels, committed.anchors, limits.max_reference_bytes)?
	finalized = KernelFacadeSemantics.Symbolic.finalize_with_contexts(symbolic, resolved.values, resolved.contents_targets) ? Semantics
	semantics = finalized.plan
	final_shape = KernelFacadeReferenceShape.Plan.build_resolved(literal_shape, authoring, finalized.contexts, KernelFacadeSemantics.Plan.sources(semantics), selection, theme, limits.shape) ? Shape
	final = KernelFacadeReferenceShape.Plan.view(final_shape)
	shape = KernelFacadeReferenceShape.Plan.final_shape(final_shape, authoring, spine.block_ownership, flow_occurrences) ? Shape
	literal_metric_reads = literal.work.shape.metric_reads
	literal_shape_requests = literal.requests.len()
	projections = map_literal_runs(literal, final)?
	mapping_run_visits = projections.len()
	positioned = position_items(authoring, spine.pending, measured_lines, final, projections, paint.rows, committed.anchors)?
	leaders = contents_rules(measured_lines.contents, paint.rows, theme, KernelLineLayout.BatchLimits.max_items(KernelFacadeLines.Limits.values(limits.lines).line))?
	rules = merge_contents_rules(paint.rules, leaders.rules)
	positioned_text = KernelFacadeText.Plan.build_positioned({ shape: final.store, styles: final.styles, lines: positioned.lines, origins: Origins(final.origins), pages, pieces: positioned.pieces }, rules, paint.flow, limits.text) ? Text
	separated = KernelFacadeText.Plan.with_occurrence_separators(positioned_text, finalized.separators, flow_occurrences, limits.text) ? Text
	text = separated.plan
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
				flow_passes: 0,
				reference_atoms: spine.pending.len(),
				flow_work: 0,
				reference_lookups: checked_add(resolved.steps, resolved.values.len())?,
				reference_format_bytes: resolved.bytes,
				reference_piece_visits: positioned.visits,
				shape_metric_reads: checked_add(literal_metric_reads, final.work.shape.metric_reads)?,
				measurement: measured_lines.work,
				normalization_chunks: authoring.reference_chunks.len(),
				literal_shape_requests,
				measured_items: measured_lines.items.len(),
				measured_rows: measured_lines.rows.len(),
				committed_row_visits: paint.rows.len(),
				anchor_item_visits: committed.visits,
				registry_lookup_steps: resolved.steps,
				resolved_labels: resolved.values.len(),
				resolved_label_bytes: resolved.bytes,
				mapping_run_visits,
				reference_fit_run_visits: positioned.fit_visits,
				positioned_pieces: positioned.pieces.len(),
				contents_rows: measured_lines.contents.len(),
				leader_dots: leaders.rules.len(),
				separator_run_visits: separated.work.run_visits,
				separator_override_writes: separated.work.override_writes,
			},
		},
	)
}

Inputs : {
	flow : KernelFacadePages.FlowSelection,
	limits : KernelFacadeReferences.Limits,
	literal_shape : KernelFacadeReferenceShape.Plan,
	page_size : Layout.Size,
	registry : KernelNavigation.Registry,
	selection : KernelFacadeShape.FontSelection,
	spine : KernelFacadeSemantics.SymbolicView,
	symbolic : KernelFacadeSemantics.Symbolic,
	theme : Theme,
}

Labels : { values : List(Str), facts : List(KernelFacadeReferences.Resolved), contents_targets : List(Semantics.NodeId), steps : U64, bytes : U64 }

Pass : {
	committed : { anchors : List(KernelNavigation.CommittedAnchor), visits : U64 },
	final_shape : KernelFacadeReferenceShape.Plan,
	labels : KernelNavigation.LabelPlan,
	lines : KernelFacadeReferenceLines.Plan,
	measured : KernelFacadePages.Measured,
	pages : U64,
	paint : KernelFacadePages.MeasuredPaint,
	resolved : Labels,
	semantics : KernelFacadeSemantics.Plan,
	separators : List(Text.OccurrenceSeparator),
}

layout_pass : Inputs, List(Layout.Unit) -> Try(Pass, KernelFacadeReferences.Error)
layout_pass = |{ flow, limits, literal_shape, page_size, registry, selection, spine, symbolic, theme }, widths| {
	authoring = spine.authoring
	literal = KernelFacadeReferenceShape.Plan.view(literal_shape)
	flow_occurrences = checked_add(spine.literals.len(), spine.pending.len())?
	lines = KernelFacadeReferenceLines.Plan.build_with_widths(spine, literal_shape, page_size, theme, limits.lines, widths) ? Lines
	measured_lines = KernelFacadeReferenceLines.Plan.view(lines)
	measured = KernelFacadePages.Measured.build(authoring, measured_lines.input, page_size, theme, flow, limits.pages) ? Pages
	pages = KernelPageLayout.Choice.pages(KernelFacadePages.Measured.view(measured).choice).len()
	paint = KernelFacadePages.Measured.paint(measured, authoring, measured_lines.input, measured_lines.visible_advances, page_size, theme, limits.pages) ? Pages
	labels = KernelNavigation.LabelPlan.build(authoring.page_labels, pages, limits.navigation) ? Navigation
	committed = commit_literal_anchors(flow_occurrences, measured_lines, literal, paint.rows)?
	resolved = resolve_labels(authoring, registry, labels, committed.anchors, limits.max_reference_bytes)?
	finalized = KernelFacadeSemantics.Symbolic.finalize_with_contexts(symbolic, resolved.values, resolved.contents_targets) ? Semantics
	semantics = finalized.plan
	# The symbolic literal plan is shared across passes. Reuse its glyph
	# facts while resolving and shaping this pass's exact label strings.
	final_shape = KernelFacadeReferenceShape.Plan.build_resolved(literal_shape, authoring, finalized.contexts, KernelFacadeSemantics.Plan.sources(semantics), selection, theme, limits.shape) ? Shape
	Ok({ committed, final_shape, labels, lines, measured, pages, paint, resolved, semantics, separators: finalized.separators })
}

render_pass : Inputs, Pass, U64, U64 -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
render_pass = |{ limits, literal_shape, registry, spine, theme, .. }, { committed, final_shape, labels, lines, measured, pages, paint, resolved, semantics, separators }, flow_passes, flow_work| {
	authoring = spine.authoring
	flow_occurrences = checked_add(spine.literals.len(), spine.pending.len())?
	literal = KernelFacadeReferenceShape.Plan.view(literal_shape)
	measured_lines = KernelFacadeReferenceLines.Plan.view(lines)
	final = KernelFacadeReferenceShape.Plan.view(final_shape)
	shape = KernelFacadeReferenceShape.Plan.final_shape(final_shape, authoring, spine.block_ownership, flow_occurrences) ? Shape
	literal_metric_reads = literal.work.shape.metric_reads
	literal_shape_requests = literal.requests.len()
	projections = map_literal_runs(literal, final)?
	mapping_run_visits = projections.len()
	positioned = position_items(authoring, spine.pending, measured_lines, final, projections, paint.rows, committed.anchors)?
	leaders = contents_rules(measured_lines.contents, paint.rows, theme, KernelLineLayout.BatchLimits.max_items(KernelFacadeLines.Limits.values(limits.lines).line))?
	rules = merge_contents_rules(paint.rules, leaders.rules)
	positioned_text = KernelFacadeText.Plan.build_positioned({ shape: final.store, styles: final.styles, lines: positioned.lines, origins: Origins(final.origins), pages, pieces: positioned.pieces }, rules, paint.flow, limits.text) ? Text
	separated = KernelFacadeText.Plan.with_occurrence_separators(positioned_text, separators, flow_occurrences, limits.text) ? Text
	text = separated.plan
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
				flow_passes,
				flow_work,
				reference_atoms: spine.pending.len(),
				reference_lookups: checked_add(resolved.steps, resolved.values.len())?,
				reference_format_bytes: resolved.bytes,
				reference_piece_visits: positioned.visits,
				shape_metric_reads: checked_add(literal_metric_reads, final.work.shape.metric_reads)?,
				measurement: measured_lines.work,
				normalization_chunks: authoring.reference_chunks.len(),
				literal_shape_requests,
				measured_items: measured_lines.items.len(),
				measured_rows: measured_lines.rows.len(),
				committed_row_visits: paint.rows.len(),
				anchor_item_visits: committed.visits,
				registry_lookup_steps: resolved.steps,
				resolved_labels: resolved.values.len(),
				resolved_label_bytes: resolved.bytes,
				mapping_run_visits,
				reference_fit_run_visits: positioned.fit_visits,
				positioned_pieces: positioned.pieces.len(),
				contents_rows: measured_lines.contents.len(),
				leader_dots: leaders.rules.len(),
				separator_run_visits: separated.work.run_visits,
				separator_override_writes: separated.work.override_writes,
			},
		},
	)
}

first_flow_reference : List(Document.NormalizedPageReference) -> [None, First(U64)]
first_flow_reference = |references| {
	var $index = 0
	for reference in references {
		if reference.flow {
			return First($index)
		}
		$index = $index + 1
	}
	None
}

stabilize_flow : Inputs, U64 -> Try(KernelFacadeReferences.Plan, KernelFacadeReferences.Error)
stabilize_flow = |inputs, reference| {
	limits = inputs.limits.flow
	work_exhausted = FlowBudget({ dimension: LayoutWork, limit: limits.max_layout_work, reference })
	stepped = KernelStabilization.stabilize(
		KernelStabilization.initial,
		limits.max_passes,
		|state, previous, _pass| {
			references = inputs.spine.authoring.page_references
			var $widths = List.with_capacity(references.len())
			var $index = 0
			for record in references {
				width = if state.pages == 0 {
					record.spec.width
				} else {
					Layout.Unit.from_raw(list_at(state.values, $index).to_i64_wrap())
				}
				$widths = $widths.append(width)
				$index = $index + 1
			}
			work_before = match previous {
				NoCandidate => 0
				Candidate(value) => value.work
			}
			if work_before >= limits.max_layout_work {
				return Err(work_exhausted)
			}
			current = layout_pass(inputs, $widths)?
			key = flow_state(inputs, current, reference)?
			if key.work > limits.max_layout_work - work_before {
				return Err(work_exhausted)
			}
			Ok({ candidate: { current, work: work_before + key.work }, state: key.state })
		},
	)?
	match stepped.outcome {
		Stable({ passes, work, .. }) => match stepped.candidate {
			Candidate(result) => render_pass(inputs, result.current, passes, checked_add(work, result.work)?)
			NoCandidate => Err(InvalidMapping({ item: reference }))
		}
		Cycle({ first_seen_pass, repeated_at_pass, .. }) => Err(FlowCycle({ reference, first: first_seen_pass, repeated: repeated_at_pass }))
		BudgetExhausted(_) => Err(FlowBudget({ dimension: Passes, limit: limits.max_passes, reference }))
	}
}

## The fixed authored inputs and literal shaping are shared by every pass.
## Key each variable fact in its original dense order. Length prefixes
## keep labels and variable arenas distinct. An item's identity is its
## index in the unchanged symbolic/literal stream, even if its row moves.
flow_state : Inputs, Pass, U64 -> Try({ state : KernelStabilization.State, work : U64 }, KernelFacadeReferences.Error)
flow_state = |inputs, pass, reference| {
	lines = KernelFacadeReferenceLines.Plan.view(pass.lines)
	final = KernelFacadeReferenceShape.Plan.view(pass.final_shape)
	choice = KernelFacadePages.Measured.view(pass.measured).choice
	refs = inputs.spine.authoring.page_references
	spans = KernelPageLayout.Choice.spans(choice)
	containers = KernelPageLayout.Choice.container_fragments(choice)
	# A state buffer stores U64 words behind a reference count. Check
	# its byte capacity even when the caller requests a wider budget.
	limit = U64.min(inputs.limits.flow.max_state_units, (U64.highest - 8) // 8)
	exhausted = FlowBudget({ dimension: StateUnits, limit, reference })
	remaining = reserve_state_units(limit, 7, 1) ? |_| exhausted
	after_refs = reserve_state_units(remaining, refs.len(), 3) ? |_| exhausted
	after_anchors = reserve_state_units(after_refs, pass.committed.anchors.len(), 6) ? |_| exhausted
	after_items = reserve_state_units(after_anchors, lines.items.len(), 2) ? |_| exhausted
	after_rows = reserve_state_units(after_items, pass.paint.rows.len(), 8) ? |_| exhausted
	after_spans = reserve_state_units(after_rows, spans.len(), 11) ? |_| exhausted
	after_containers = reserve_state_units(after_spans, containers.len(), 7) ? |_| exhausted
	after_labels = reserve_state_units(after_containers, pass.resolved.bytes, 1) ? |_| exhausted
	capacity = limit - after_labels
	var $key = List.with_capacity(capacity)
	var $index = 0
	var $fit_visits = 0
	for record in refs {
		width = if record.flow {
			context = list_at(inputs.spine.pending, $index)
			runs = list_at(final.literal_runs, context.occurrence.index()).runs
			var $required = 0
			var $run = runs.start()
			while $run < runs.start() + runs.length() {
				$required = checked_i64_add($required, list_at(final.advances, $run).raw())?
				$fit_visits = $fit_visits + 1
				$run = $run + 1
			}
			if $required <= 0 {
				return Err(FieldOverflow({ reference: $index, width: record.spec.width, required: Layout.Unit.from_raw($required) }))
			}
			Layout.Unit.from_raw($required)
		} else {
			record.spec.width
		}
		$key = $key.append(width.raw().to_u64_wrap())
		$index = $index + 1
	}
	$key = $key.append(pass.resolved.facts.len())
	for resolved in pass.resolved.facts {
		$key = $key.append(resolved.physical_page)
		bytes = resolved.value.to_utf8()
		$key = $key.append(bytes.len())
		for byte in bytes {
			$key = $key.append(byte.to_u64())
		}
	}
	$key = $key.append(pass.committed.anchors.len())
	for anchor in pass.committed.anchors {
		match anchor {
			Unplaced => {
				$key = $key.append(0)
			}
			At({ page, rect }) => {
				$key = $key.append(1).append(page.index())
				$key = append_rect($key, rect)
			}
		}
	}
	$key = $key.append(pass.paint.rows.len())
	for row in pass.paint.rows {
		items = list_at(lines.rows, row.row).items
		artifact = if (row.artifact) 1 else 0
		$key = $key.append(row.page).append(row.block).append(row.row).append(artifact)
		$key = $key.append(row.origin.x.raw().to_u64_wrap()).append(row.origin.y.raw().to_u64_wrap())
		$key = $key.append(items.start()).append(items.length())
	}
	$key = $key.append(lines.items.len())
	$index = 0
	for item in lines.items {
		$key = $key.append(item.advance.raw().to_u64_wrap()).append(list_at(lines.item_offsets, $index).raw().to_u64_wrap())
		$index = $index + 1
	}
	$key = $key.append(spans.len())
	for span in spans {
		$key = $key.append(span.block).append(span.rows.start()).append(span.rows.length()).append(span.page.index())
		$key = append_rect($key, span.geometry)
		$key = $key.append(span.baseline.x.raw().to_u64_wrap()).append(span.baseline.y.raw().to_u64_wrap()).append(span.leading.raw().to_u64_wrap())
	}
	$key = $key.append(containers.len())
	for fragment in containers {
		part = match fragment.part {
			Whole => 0
			First => 1
			Middle => 2
			Last => 3
		}
		$key = $key.append(fragment.container).append(fragment.page).append(part)
		$key = append_rect($key, fragment.rect)
	}
	paging = KernelPageLayout.Choice.work(choice)
	measure = lines.work
	work_exhausted = FlowBudget({ dimension: LayoutWork, limit: inputs.limits.flow.max_layout_work, reference })
	with_fits = checked_add($key.len(), $fit_visits) ? |_| work_exhausted
	with_measured = checked_add(with_fits, measure.measured_items) ? |_| work_exhausted
	with_wrapped = checked_add(with_measured, measure.wrapped_items) ? |_| work_exhausted
	with_alignment = checked_add(with_wrapped, measure.alignment_items) ? |_| work_exhausted
	with_candidates = checked_add(with_alignment, paging.candidate_visits) ? |_| work_exhausted
	with_pages = checked_add(with_candidates, paging.line_visits) ? |_| work_exhausted
	with_anchors = checked_add(with_pages, pass.committed.visits) ? |_| work_exhausted
	with_resolved = checked_add(with_anchors, pass.resolved.steps) ? |_| work_exhausted
	work = checked_add(with_resolved, final.work.shape.metric_reads) ? |_| work_exhausted
	Ok({ state: { pages: pass.pages, values: $key }, work })
}

reserve_state_units : U64, U64, U64 -> Try(U64, [TooManyStateUnits])
reserve_state_units = |remaining, count, width| {
	if count > remaining // width {
		return Err(TooManyStateUnits)
	}
	Ok(remaining - count * width)
}

append_rect : List(U64), Layout.Rect -> List(U64)
append_rect = |values, { origin, size }| values.append(origin.x.raw().to_u64_wrap()).append(origin.y.raw().to_u64_wrap()).append(size.width.raw().to_u64_wrap()).append(size.height.raw().to_u64_wrap())

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

resolve_labels : Document.NormalizedAuthoring, KernelNavigation.Registry, KernelNavigation.LabelPlan, List(KernelNavigation.CommittedAnchor), U64 -> Try(Labels, KernelFacadeReferences.Error)
resolve_labels = |authoring, registry, labels, anchors, max_bytes| {
	destinations = KernelNavigation.Registry.destinations(registry)
	var $contents_targets = []
	var $index_targets = []
	has_index = authoring.groups.any(
		|group| match group.kind {
			IndexList => True
			_ => False
		},
	)
	var $contents_index = 0
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
		if $contents_index < authoring.contents_entries.len() and list_at(authoring.contents_entries, $contents_index).reference == $reference {
			$contents_targets = $contents_targets.append(destination.target)
			$contents_index = $contents_index + 1
		}
		if has_index {
			match Document.index_location(authoring, $reference) {
				IndexLocation(_) => {
					$index_targets = $index_targets.append(destination.target)
				}
				NoIndexLocation => {}
			}
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
	structure_targets = if ($index_targets.is_empty()) $contents_targets else $contents_targets.concat($index_targets)
	Ok({ values: $values, facts: $facts, contents_targets: structure_targets, steps: $steps, bytes: $bytes })
}

## The final title row is explicit measurement evidence. Paint bounded small
## dots as Decoration rectangles; neither dots nor alignment gaps enter the
## semantic text sources, glyph arena, or link ownership.
contents_rules : List(KernelFacadeReferenceLines.ContentsTerminal), List(KernelFacadePages.PositionedRow), Theme, U64 -> Try({ rules : List(KernelFacadePages.Rule) }, KernelFacadeReferences.Error)
contents_rules = |terminals, rows, theme, max_dots| {
	if terminals.is_empty() {
		return Ok({ rules: [] })
	}
	var $rules = []
	var $terminal = 0
	for row in rows {
		if $terminal < terminals.len() and list_at(terminals, $terminal).row == row.row {
			terminal = list_at(terminals, $terminal)
			$terminal = $terminal + 1
			if terminal.leader == Dots {
				var $x = add_unit(row.origin.x, terminal.title_advance)?
				$x = add_unit($x, 3)?
				end = add_unit(row.origin.x, terminal.field_offset)?
				while $x.raw() + 3600 <= end.raw() {
					if $rules.len() >= max_dots {
						return Err(ArithmeticOverflow)
					}
					$rules = $rules.append({ color: Theme.body_style(theme).color, layer: Front, page: row.page, rect: { origin: { x: $x, y: add_unit(row.origin.y, 0.6)? }, size: { width: 0.6, height: 0.6 } } })
					$x = add_unit($x, 3)?
				}
			}
		}
	}
	if $terminal != terminals.len() {
		return Err(InvalidMapping({ item: $terminal }))
	}
	Ok({ rules: $rules })
}

## Both arenas are already in page order. Existing Behind rules precede
## ordinary Front rules, then contents decorations, on each physical page.
merge_contents_rules : List(KernelFacadePages.Rule), List(KernelFacadePages.Rule) -> List(KernelFacadePages.Rule)
merge_contents_rules = |ordinary, contents| {
	if contents.is_empty() {
		return ordinary
	}
	var $rules = List.with_capacity(ordinary.len() + contents.len())
	var $ordinary = 0
	var $contents = 0
	while $ordinary < ordinary.len() or $contents < contents.len() {
		if $ordinary < ordinary.len() and ($contents >= contents.len() or list_at(ordinary, $ordinary).page <= list_at(contents, $contents).page) {
			$rules = $rules.append(list_at(ordinary, $ordinary))
			$ordinary = $ordinary + 1
		} else {
			$rules = $rules.append(list_at(contents, $contents))
			$contents = $contents + 1
		}
	}
	$rules
}

RunProjection : { measured : Semantics.IndexRange, final_start : U64, run : U64 }

## Resolved reference shaping copied the nominal literal clusters in order
## with their glyphs unchanged. Project the old dense cluster position within
## each checked physical run onto its new range instead of walking glyphs.
map_literal_runs : KernelFacadeReferenceShape.View, KernelFacadeReferenceShape.View -> Try(List(RunProjection), KernelFacadeReferences.Error)
map_literal_runs = |measured, final| {
	var $entries = List.with_capacity(measured.store.runs.len())
	var $cluster = 0
	for literal in measured.literal_runs {
		context = measured.literals.get(literal.context) ? |_| InvalidMapping({ item: literal.context })
		id = context.occurrence.id.index()
		resolved = final.literal_runs.get(id) ? |_| InvalidMapping({ item: id })
		if literal.runs.length() != resolved.runs.length() or literal.runs.start() != $entries.len() {
			return Err(InvalidMapping({ item: id }))
		}
		var $physical = 0
		while $physical < literal.runs.length() {
			old = measured.store.runs.get(literal.runs.start() + $physical) ? |_| InvalidMapping({ item: id })
			new_index = resolved.runs.start() + $physical
			new = final.store.runs.get(new_index) ? |_| InvalidMapping({ item: id })
			length = old.clusters.length()
			if old.unicode != OccurrenceText(context.occurrence.id) or new.unicode != old.unicode or old.source != new.source or old.size != new.size {
				return Err(InvalidMapping({ item: id }))
			}
			final_start = new.clusters.start()
			if old.clusters.start() != $cluster or length != new.clusters.length() or length > measured.store.clusters.len() - $cluster or final_start > final.store.clusters.len() or length > final.store.clusters.len() - final_start {
				return Err(InvalidMapping({ item: $cluster }))
			}
			$entries = $entries.append({ measured: old.clusters, final_start, run: new_index })
			$cluster = $cluster + length
			$physical = $physical + 1
		}
	}
	if $entries.len() != measured.store.runs.len() or $cluster != measured.store.clusters.len() {
		return Err(InvalidMapping({ item: $cluster }))
	}
	Ok($entries)
}

FieldFit : { runs : Semantics.IndexRange, inset : Layout.Unit }

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
		record = list_at(authoring.page_references, $reference)
		width = if (record.flow) Layout.Unit.from_raw($required) else record.spec.width
		if $required < 0 or $required > width.raw() {
			return Err(FieldOverflow({ reference: $reference, width, required: Layout.Unit.from_raw($required) }))
		}
		remaining = width.raw() - $required
		inset = match record.spec.align {
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

position_items : Document.NormalizedAuthoring, List(KernelFacadeSemantics.PendingContext), KernelFacadeReferenceLines.View, KernelFacadeReferenceShape.View, List(RunProjection), List(KernelFacadePages.PositionedRow), List(KernelNavigation.CommittedAnchor) -> Try(Positioned, KernelFacadeReferences.Error)
position_items = |authoring, pending, measured, final, mapping, rows, anchors| {
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
					mapped = mapped_cluster(mapping, source)?
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
								next_mapped = mapped_cluster(mapping, next_source)?
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
					line = { advance: $advance, clusters: Semantics.IndexRange.from_start_and_length({ start: mapped.cluster, length: $end - $item }), source: joined_source(first.source, $last.source)? }
					index = $lines.len()
					$lines = $lines.append(line)
					$pieces = $pieces.append({ artifact: row.artifact, line: index, origin, page: Semantics.PageId.from_index(row.page), source_runs: { physical: Semantics.IndexRange.from_start_and_length({ start: mapped.run, length: 1 }) } })
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
						$pieces = $pieces.append({ artifact: row.artifact, line: index, origin: piece_origin, page: Semantics.PageId.from_index(row.page), source_runs: { physical: Semantics.IndexRange.from_start_and_length({ start: $physical, length: 1 }) } })
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
	Ok({ lines: $lines, pieces: $pieces, anchors: $anchors, fit_visits: fitted.visits, visits: $visits })
}

mapped_cluster : List(RunProjection), { cluster : U64, run : U64 } -> Try({ cluster : U64, run : U64 }, KernelFacadeReferences.Error)
mapped_cluster = |entries, source| {
	projection = entries.get(source.run) ? |_| InvalidMapping({ item: source.cluster })
	start = projection.measured.start()
	if source.cluster < start or source.cluster - start >= projection.measured.length() {
		return Err(InvalidMapping({ item: source.cluster }))
	}
	Ok({ cluster: projection.final_start + (source.cluster - start), run: projection.run })
}

occurrence_of : Text.Run -> Try(U64, KernelFacadeReferences.Error)
occurrence_of = |run| match run.unicode {
	OccurrenceText(id) => Ok(id.index())
	_ => Err(InvalidMapping({ item: run.id.index() }))
}

anchor_rect : Layout.Point, Layout.Unit, Layout.Unit, Layout.Unit -> Try(Layout.Rect, KernelFacadeReferences.Error)
anchor_rect = |origin, width, size, leading| {
	height = if (leading > size) leading else size
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
	Ok({ scalars: Semantics.IndexRange.from_start_and_length({ start: first.scalars.start(), length: scalar_end - first.scalars.start() }), utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: first.utf8_bytes.start(), length: byte_end - first.utf8_bytes.start() }) })
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
	flow: KernelFacadeReferences.default_flow_limits,
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
test_document = |inlines, labels| Document.normalize(Document.from_blocks({ contents: [Document.rich_paragraph(inlines), Document.page_break, Document.destination_paragraph({ name: "end", text: "Destination" })], language: "en", title: "References" }).with_page_labels(labels))

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
	selection = Styled({ faces, fonts: [font, font, font], inline_faces: [], face_indexes: [], roles: { code: Inherited, emphasis: Candidate(2), quote: Inherited, strong: Candidate(1) } })
	theme : Theme
	theme = { inline: { strong: { font: Face(list_at(faces, 1)) }, emphasis: { font: Face(list_at(faces, 2)) } } }
	authoring = test_document([Document.strong([Document.page_reference({ destination: "end", width: 24 })]), Document.emphasis([Document.plain_text("A")])], [])
	plan = KernelFacadeReferences.Plan.build(authoring, selection, theme, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	KernelFacadeText.Plan.text(view.text).runs.map(|run| run.instance.index()) == [1, 2, 0]
}

# The fixed final store has the same dense indexes and glyphs as a fresh
# final shape. The label uses the same canonical Unicode source as a
# literal, but introduces an earlier face through the strong role.
expect {
	font = test_font({})?
	faces = [Font.FaceId.from_index(0), Font.FaceId.from_index(1), Font.FaceId.from_index(2)]
	selection = Styled({ faces, fonts: [font, font, font], inline_faces: [], face_indexes: [], roles: { code: Inherited, emphasis: Candidate(2), quote: Inherited, strong: Candidate(1) } })
	theme : Theme
	theme = { inline: { strong: { font: Face(list_at(faces, 1)) }, emphasis: { font: Face(list_at(faces, 2)) } } }
	authoring = test_document([Document.strong([Document.page_reference({ destination: "end", width: 24 })]), Document.emphasis([Document.plain_text("2")])], [])
	symbolic = KernelFacadeSemantics.Symbolic.build(authoring, test_limits.semantics)?
	spine = KernelFacadeSemantics.Symbolic.view(symbolic)
	measured = KernelFacadeReferenceShape.Plan.build(authoring, spine.literals, KernelFacadeSources.Plan.sources(spine.sources), selection, theme, test_limits.shape)?
	finalized = KernelFacadeSemantics.Symbolic.finalize_with_contexts(symbolic, ["2"], [])?
	final_sources = KernelFacadeSemantics.Plan.sources(finalized.plan)
	check = |limits| {
		fresh = KernelFacadeReferenceShape.Plan.build(authoring, finalized.contexts, KernelFacadeSources.Plan.sources(final_sources), selection, theme, limits)
		reused = KernelFacadeReferenceShape.Plan.build_resolved(measured, authoring, finalized.contexts, final_sources, selection, theme, limits)
		match (fresh, reused) {
			(Ok(full), Ok(cached)) => {
				a = KernelFacadeReferenceShape.Plan.view(full)
				b = KernelFacadeReferenceShape.Plan.view(cached)
				projection_moves_past_label(KernelFacadeReferenceShape.Plan.view(measured), b) == Ok(True)
					and a.store == b.store and a.advances == b.advances and a.styles == b.styles and a.origins == b.origins and a.requests == b.requests and a.literal_runs == b.literal_runs
					and b.store.runs.map(|run| run.instance.index()) == [1, 2, 0]
					and list_at(b.requests, 0).source == list_at(b.requests, 1).source
					and b.work == { ..a.work, shape: { ..a.work.shape, metric_reads: 1 } }
			}
			_ => False
		}
	}
	exact = KernelFacadeShape.Limits.make({ max_requests: 3, shape: KernelShape.Limits.make({ max_clusters: 13, max_glyphs: 13, max_scalars: 13, max_source_bytes: 13 }) })
	over = KernelFacadeShape.Limits.make({ max_requests: 3, shape: KernelShape.Limits.make({ max_clusters: 13, max_glyphs: 12, max_scalars: 13, max_source_bytes: 13 }) })
	budget = match (
		KernelFacadeReferenceShape.Plan.build(authoring, finalized.contexts, KernelFacadeSources.Plan.sources(final_sources), selection, theme, over),
		KernelFacadeReferenceShape.Plan.build_resolved(measured, authoring, finalized.contexts, final_sources, selection, theme, over),
	) {
		(Err(Shape(LimitExceeded({ attempted: 13, dimension: Glyphs, limit: 12 }))), Err(Shape(LimitExceeded({ attempted: 13, dimension: Glyphs, limit: 12 })))) => True
		_ => False
	}
	check(exact) and budget
}

# The fresh label occupies run and cluster zero. Every old literal
# keeps its relative position and moves by exactly one in each arena.
projection_moves_past_label : KernelFacadeReferenceShape.View, KernelFacadeReferenceShape.View -> Try(Bool, KernelFacadeReferences.Error)
projection_moves_past_label = |measured, final| {
	runs = map_literal_runs(measured, final)?
	for run in measured.store.runs {
		var $cluster = run.clusters.start()
		while $cluster < run.clusters.start() + run.clusters.length() {
			source = { cluster: $cluster, run: run.id.index() }
			if mapped_cluster(runs, source)? != { cluster: $cluster + 1, run: run.id.index() + 1 } {
				return Ok(False)
			}
			$cluster = $cluster + 1
		}
	}
	in_range = list_at(measured.store.runs, 0).clusters.start()
	invalid_run = mapped_cluster(runs, { cluster: in_range, run: runs.len() })
	invalid_cluster = mapped_cluster(runs, { cluster: measured.store.clusters.len(), run: 0 })
	Ok(invalid_run == Err(InvalidMapping({ item: in_range })) and invalid_cluster == Err(InvalidMapping({ item: measured.store.clusters.len() })))
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

# An authored break after a reference reaches the emitted-run handoff as
# explicit owned replacement evidence, without changing exact label source.
expect {
	font = test_font({})?
	authoring = test_document([Document.page_reference({ destination: "end", width: 24 }), Document.line_break, Document.page_reference({ destination: "end", width: 24 })], [])
	plan = KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, test_limits)?
	view = KernelFacadeReferences.Plan.view(plan)
	runs = KernelFacadeText.Plan.text(view.text).runs
	override = match list_at(runs, 0).actual_text {
		SemanticOverrideSlice(boxed) => {
			fact = Text.ActualTextSlice.value(boxed)
			fact.property.index() == 0 and fact.utf8_bytes.start() == 0 and fact.utf8_bytes.length() == 2
		}
		_ => False
	}
	override and list_at(runs, 0).source.utf8_bytes.length() == 1 and list_at(runs, 1).actual_text == FromOccurrence
		and view.work.separator_run_visits == runs.len() and view.work.separator_override_writes == 1
}

# The final accepted pass and its work can use the last permitted unit.
# A lower limit produces a located failure for the exhausted dimension.
expect {
	font = test_font({})?
	authoring = test_document([Document.plain_text("The destination is on page "), Document.flow_page_reference({ destination: "end" })], [])
	build = |flow| KernelFacadeReferences.Plan.build(authoring, Single(font), Theme.default, { width: 595, height: 842 }, NoFlowTemplate, { ..test_limits, flow })
	defaults = KernelFacadeReferences.default_flow_limits
	accepted = build(defaults)?
	work = KernelFacadeReferences.Plan.view(accepted).work
	passes = work.flow_passes
	comparisons = ((passes - 1) * passes) // 2 + 1
	layout_work = work.flow_work - comparisons
	exact = build({ ..defaults, max_passes: passes, max_layout_work: layout_work })?
	pass_rejected = match build({ ..defaults, max_passes: passes - 1 }) {
		Err(FlowBudget({ dimension: Passes, limit, reference: 0 })) => limit == passes - 1
		_ => False
	}
	work_rejected = match build({ ..defaults, max_layout_work: layout_work - 1 }) {
		Err(FlowBudget({ dimension: LayoutWork, limit, reference: 0 })) => limit == layout_work - 1
		_ => False
	}
	view = KernelFacadeReferences.Plan.view(exact)
	pass_rejected and work_rejected and view.work == work
		and work.mapping_run_visits == 2
		and work.shape_metric_reads == "The destination is on page ".count_utf8_bytes() + "Destination".count_utf8_bytes() + work.resolved_label_bytes
}

expect {
	reserve_state_units(8, 2, 4) == Ok(0)
		and reserve_state_units(7, 2, 4) == Err(TooManyStateUnits)
		and reserve_state_units(U64.highest, U64.highest, 8) == Err(TooManyStateUnits)
}
