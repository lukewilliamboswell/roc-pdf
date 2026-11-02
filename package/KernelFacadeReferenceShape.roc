import Document
import Font
import KernelFacadeShape
import KernelFacadeSemantics
import KernelFacadeSources
import KernelFont
import KernelShape
import KernelUnicode
import Layout
import Semantics
import Text
import Theme
import unicode.Scalar

## Shapes only exact authored literals. Pending page-reference occurrences
## remain absent from this store and keep their global semantic identities.
KernelFacadeReferenceShape :: [].{
	LiteralContext : { occurrence : Semantics.ContentOccurrence, block : U64, inline : [AtInline(U64), NoInline], segment : U64, role : [Body, GeneratedLabel] }
	Error : [
		InvalidLiteral({ occurrence : U64 }),
		InvalidSelection,
		LimitExceeded({ attempted : U64, limit : U64 }),
		Shape(KernelShape.Error),
		Style(KernelFacadeShape.Error),
	]
	LiteralRuns : { context : U64, runs : Semantics.IndexRange }
	Work : { literal_visits : U64, range_probes : U64, selected_runs : U64, source_selections : U64, shape : KernelShape.Work }
	View : {
		literals : List(LiteralContext),
		literal_runs : List(LiteralRuns),
		requests : List(KernelShape.SimpleRequest),
		styles : List(KernelFacadeShape.RunStyle),
		origins : List(KernelFacadeShape.Origin),
		store : Text.Store,
		advances : List(Layout.Unit),
		selection : KernelFacadeShape.Selection,
		fonts : List(KernelFont.Inspection),
		work : Work,
	}
	Plan :: View.{
		build : Document.NormalizedAuthoring, List(LiteralContext), List(KernelFacadeSources.Source), KernelFacadeShape.FontSelection, Theme, KernelFacadeShape.Limits -> Try(Plan, Error)
		build = |authoring, literals, sources, selection, theme, limits| build_plan(authoring, literals, sources, selection, theme, limits)
		final_shape : Plan, Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), U64 -> Try(KernelFacadeShape.Plan, Error)
		final_shape = |plan, authoring, owners, count| finalize_shape(plan, authoring, owners, count)
		view : Plan -> View
		view = |Plan.(value)| value
	}
}

Selected : { clusters : Semantics.IndexRange, face : Font.FaceId, script : Font.Script }

SelectedSources : [FixedFace(List(U64)), PolicyFaces({ segments : List(List(Selected)), indexes : List(U64) })]

build_plan : Document.NormalizedAuthoring, List(KernelFacadeReferenceShape.LiteralContext), List(KernelFacadeSources.Source), KernelFacadeShape.FontSelection, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeReferenceShape.Plan, KernelFacadeReferenceShape.Error)
build_plan = |authoring, literals, sources, selection, theme, limits| {
	if literals.len() > KernelFacadeShape.Limits.max_requests(limits) {
		return Err(LimitExceeded({ attempted: literals.len(), limit: KernelFacadeShape.Limits.max_requests(limits) }))
	}
	selected = prepare_selection(authoring, literals, sources, selection, theme)?
	var $requests = []
	var $styles = []
	var $origins = []
	var $selected = []
	var $literal_runs = List.with_capacity(literals.len())
	var $range_probes = 0
	var $previous_occurrence = NoOccurrence
	var $literal = 0
	while $literal < literals.len() {
		context = list_at(literals, $literal)
		occurrence = context.occurrence
		index = occurrence.id.index()
		match $previous_occurrence {
			Occurrence(previous) if index <= previous => return Err(InvalidLiteral({ occurrence: index }))
			_ => {}
		}
		$previous_occurrence = Occurrence(index)
		if context.block >= authoring.blocks.len() {
			return Err(InvalidLiteral({ occurrence: index }))
		}
		located = match occurrence.source {
			Text(source, UnicodeRange(range)) if source.index() < sources.len() => { source, range }
			_ => return Err(InvalidLiteral({ occurrence: index }))
		}
		source = list_at(sources, located.source.index())
		bounds = cluster_bounds(source.analysis, located.range, index)?
		$range_probes = $range_probes + bounds.probes
		style = KernelFacadeShape.leaf_style(authoring, context.block, context.inline, context.role, theme)
		candidate = match selection {
			Single(_) => {
				if style.font != Theme.body_font(theme) {
					return Err(Style(UnsupportedThemeFace({ block: context.block, face: style.font.index() })))
				}
				0
			}
			Styled(styled) => KernelFacadeShape.leaf_candidate(authoring, context.block, context.inline, context.role, styled, theme)
			Ordered(_) => 0
		}
		start = $requests.len()
		segments = literal_segments(source.analysis, bounds.range, context, authoring, selected.sources, located.source.index(), candidate)?
		$range_probes = $range_probes + segments.probes
		for segment in segments.segments {
			attempted = $requests.len() + 1
			if attempted > KernelFacadeShape.Limits.max_requests(limits) {
				return Err(LimitExceeded({ attempted, limit: KernelFacadeShape.Limits.max_requests(limits) }))
			}
			$requests = $requests.append({ occurrence: occurrence.id, size: style.size, source: located.source })
			$styles = $styles.append({ color: style.color, leading: style.leading, segment: context.segment })
			$origins = $origins.append({ byte: located.range.utf8_bytes.start(), scalar: located.range.scalars.start() })
			$selected = $selected.append({ clusters: segment.clusters, instance: Font.InstanceId.from_index(segment.font), language: occurrence.language, occurrence: occurrence.id, script: segment.script, size: style.size, source: located.source })
		}
		$literal_runs = $literal_runs.append({ context: $literal, runs: Semantics.IndexRange.from_start_and_length({ start: start, length: $requests.len() - start }) })
		$literal = $literal + 1
	}

	## Empty literal stores are intentional, including an atom-only document.
	## They do not manufacture an empty source or a shaping request.
	batch = if $selected.is_empty() {
		{ store: empty_store, advances: [], work: empty_work }
	} else {
		match KernelShape.shape_ranged_selected_batch(selected.fonts, sources, { direction: LeftToRight, language: Language(authoring.language), writing_mode: Horizontal }, $selected, KernelFacadeShape.Limits.shape(limits)) {
			Ok(value) => value
			Err(error) => return Err(locate_failure(literals, $literal_runs, sources, selected.fonts, $selected, error))
		}
	}
	Ok(KernelFacadeReferenceShape.Plan.{ literals, literal_runs: $literal_runs, requests: $requests, styles: $styles, origins: $origins, store: batch.store, advances: batch.advances, selection: selected.selection, fonts: selected.fonts, work: { literal_visits: literals.len(), range_probes: $range_probes, selected_runs: $requests.len(), source_selections: selected.selections, shape: batch.work } })
}

## The ordered policy chooses once per unique real source. Dense font
## indexes are assigned in policy order, independently of occurrence order.
prepare_selection : Document.NormalizedAuthoring, List(KernelFacadeReferenceShape.LiteralContext), List(KernelFacadeSources.Source), KernelFacadeShape.FontSelection, Theme -> Try({ fonts : List(KernelFont.Inspection), sources : SelectedSources, selections : U64, selection : KernelFacadeShape.Selection }, KernelFacadeReferenceShape.Error)
prepare_selection = |authoring, literals, sources, selection, theme| match selection {
	Single(font) => Ok({ fonts: [font], sources: FixedFace([0]), selections: 0, selection: SingleFace })
	Styled(styled) => {
		var $used = List.repeat(False, styled.fonts.len())
		if authoring.sources.is_empty() {
			$used = list_set($used, 0, True)
		}
		for literal in literals {
			candidate = KernelFacadeShape.leaf_candidate(authoring, literal.block, literal.inline, literal.role, styled, theme)
			if candidate >= $used.len() {
				return Err(InvalidSelection)
			}
			$used = list_set($used, candidate, True)
		}
		for candidate in KernelFacadeShape.drawing_candidates(authoring, styled) {
			if candidate >= $used.len() {
				return Err(InvalidSelection)
			}
			$used = list_set($used, candidate, True)
		}
		var $indexes = List.repeat(U64.highest, styled.fonts.len())
		var $fonts = []
		var $faces = []
		var $candidate = 0
		while $candidate < styled.fonts.len() {
			if list_at($used, $candidate) {
				$indexes = list_set($indexes, $candidate, $fonts.len())
				$fonts = $fonts.append(list_at(styled.fonts, $candidate))
				$faces = $faces.append(list_at(styled.faces, $candidate))
			}
			$candidate = $candidate + 1
		}
		Ok({ fonts: $fonts, sources: FixedFace($indexes), selections: 0, selection: OrderedFaces({ faces: $faces, fonts: $fonts, work: zero_selection_work }) })
	}
	Ordered(ordered) => {
		policy = ordered.registry.policy_faces(ordered.policy) ? |error| Style(PolicyInvalid(error))
		count = ordered.registry.store().faces.len()
		var $used = List.repeat(False, count)
		var $segments = List.with_capacity(sources.len())
		var $source = 0
		var $selection_work = zero_selection_work
		while $source < sources.len() {
			result = KernelFacadeShape.select_source_reporting(ordered.registry, ordered.policy, list_at(sources, $source), $source, Language(authoring.language)) ? |error| locate_policy_failure(literals, list_at(sources, $source), $source, error)
			segments = result.segments
			$selection_work = { coverage_span_visits: $selection_work.coverage_span_visits + result.work.coverage_span_visits, face_visits: $selection_work.face_visits + result.work.face_visits, grapheme_visits: $selection_work.grapheme_visits + result.work.grapheme_visits, planned_sources: $selection_work.planned_sources + result.work.planned_sources, selection_ranges: $selection_work.selection_ranges + result.work.selection_ranges }
			for segment in segments {
				if segment.face.index() >= count {
					return Err(InvalidSelection)
				}
				$used = list_set($used, segment.face.index(), True)
			}
			$segments = $segments.append(segments)
			$source = $source + 1
		}
		var $indexes = List.repeat(U64.highest, count)
		var $fonts = []
		var $faces = []
		for face in policy {
			if face.index() >= count {
				return Err(InvalidSelection)
			}
			if list_at($used, face.index()) {
				font = ordered.registry.prepared_face(face) ? |_| InvalidSelection
				$indexes = list_set($indexes, face.index(), $fonts.len())
				$fonts = $fonts.append(font)
				$faces = $faces.append(face)
			}
		}
		Ok({ fonts: $fonts, sources: PolicyFaces({ segments: $segments, indexes: $indexes }), selections: sources.len(), selection: OrderedFaces({ faces: $faces, fonts: $fonts, work: $selection_work }) })
	}
}

zero_selection_work : KernelFacadeShape.SelectionWork
zero_selection_work = { coverage_span_visits: 0, face_visits: 0, grapheme_visits: 0, planned_sources: 0, selection_ranges: 0 }

PhysicalSegment : { clusters : Semantics.IndexRange, font : U64, script : Font.Script }

literal_segments : KernelUnicode.UnicodeAnalysis, Semantics.IndexRange, KernelFacadeReferenceShape.LiteralContext, Document.NormalizedAuthoring, SelectedSources, U64, U64 -> Try({ segments : List(PhysicalSegment), probes : U64 }, KernelFacadeReferenceShape.Error)
literal_segments = |analysis, range, context, authoring, selection, source, candidate| {
	end = range.start() + range.length()
	var $segments = []
	var $probes = 0
	match selection {
		PolicyFaces(policy) => {
			if source >= policy.segments.len() {
				return Err(InvalidSelection)
			}
			segments = list_at(policy.segments, source)
			var $low = 0
			var $high = segments.len()
			while $low < $high {
				middle = $low + ($high - $low) // 2
				$probes = $probes + 1
				segment = list_at(segments, middle)
				if segment.clusters.start() + segment.clusters.length() <= range.start() {
					$low = middle + 1
				} else {
					$high = middle
				}
			}
			var $cursor = range.start()
			while $low < segments.len() and $cursor < end {
				segment = list_at(segments, $low)
				stop = U64.min(end, segment.clusters.start() + segment.clusters.length())
				if segment.face.index() >= policy.indexes.len() or list_at(policy.indexes, segment.face.index()) == U64.highest or segment.clusters.start() > $cursor or stop <= $cursor {
					return Err(InvalidSelection)
				}
				$segments = $segments.append({ clusters: Semantics.IndexRange.from_start_and_length({ start: $cursor, length: stop - $cursor }), font: list_at(policy.indexes, segment.face.index()), script: segment.script })
				$cursor = stop
				$low = $low + 1
			}
			if $cursor != end {
				return Err(InvalidSelection)
			}
		}
		FixedFace(indexes) => {
			if candidate >= indexes.len() or list_at(indexes, candidate) == U64.highest {
				return Err(InvalidSelection)
			}
			font_index = list_at(indexes, candidate)
			is_source = match list_at(authoring.blocks, context.block).kind {
				SourceLine(_) => True
				_ => False
			}
			var $cursor = range.start()
			var $script = 0
			var $high = analysis.script_runs.len()
			first_scalar = list_at(analysis.graphemes, $cursor).scalar_start
			while $script < $high {
				middle = $script + ($high - $script) // 2
				$probes = $probes + 1
				if list_at(analysis.script_runs, middle).range.scalar_end <= first_scalar {
					$script = middle + 1
				} else {
					$high = middle
				}
			}
			while $cursor < end {
				first = list_at(analysis.graphemes, $cursor)
				while $script < analysis.script_runs.len() and list_at(analysis.script_runs, $script).range.scalar_end <= first.scalar_start {
					$script = $script + 1
				}
				if $script >= analysis.script_runs.len() {
					return Err(InvalidLiteral({ occurrence: context.occurrence.id.index() }))
				}
				script = list_at(analysis.script_runs, $script)
				if !declared_script(script.script) {
					return Err(Style(UnsupportedText({ block: context.block, inline: context.inline, reason: Script(script.script), scalars: Semantics.IndexRange.from_start_and_length({ start: first.scalar_start - literal_start(context), length: first.scalar_end - first.scalar_start }) })))
				}
				var $stop = $cursor + 1
				while $stop < end and list_at(analysis.graphemes, $stop).scalar_start < script.range.scalar_end {
					$stop = $stop + 1
				}
				$segments = $segments.append({ clusters: Semantics.IndexRange.from_start_and_length({ start: $cursor, length: $stop - $cursor }), font: font_index, script: Font.Script.from_iso15924(if (is_source and script.script != "Zyyy" and script.script != "Zinh") script.script else "Latn") })
				$cursor = $stop
			}
		}
	}
	Ok({ segments: $segments, probes: $probes })
}

declared_script : Str -> Bool
declared_script = |value| value == "Latn" or value == "Hani" or value == "Zyyy" or value == "Zinh"

literal_start : KernelFacadeReferenceShape.LiteralContext -> U64
literal_start = |context| match context.occurrence.source {
	Text(_, UnicodeRange(range)) => range.scalars.start()
	_ => 0
}

cluster_bounds : KernelUnicode.UnicodeAnalysis, Semantics.TextRange, U64 -> Try({ range : Semantics.IndexRange, probes : U64 }, KernelFacadeReferenceShape.Error)
cluster_bounds = |analysis, range, occurrence| {
	start = cluster_boundary(analysis.graphemes, range.scalars.start(), occurrence)?
	end = cluster_boundary(analysis.graphemes, range.scalars.start() + range.scalars.length(), occurrence)?
	if end.index <= start.index {
		return Err(InvalidLiteral({ occurrence: occurrence }))
	}
	first = list_at(analysis.graphemes, start.index)
	last = list_at(analysis.graphemes, end.index - 1)
	if first.byte_start != range.utf8_bytes.start() or last.byte_end != range.utf8_bytes.start() + range.utf8_bytes.length() {
		return Err(InvalidLiteral({ occurrence: occurrence }))
	}
	Ok({ range: Semantics.IndexRange.from_start_and_length({ start: start.index, length: end.index - start.index }), probes: start.probes + end.probes })
}

cluster_boundary : List(KernelUnicode.UnicodeRange), U64, U64 -> Try({ index : U64, probes : U64 }, KernelFacadeReferenceShape.Error)
cluster_boundary = |graphemes, scalar, occurrence| {
	var $low = 0
	var $high = graphemes.len()
	var $probes = 0
	while $low < $high {
		middle = $low + ($high - $low) // 2
		$probes = $probes + 1
		if list_at(graphemes, middle).scalar_start < scalar {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	if $low < graphemes.len() {
		if list_at(graphemes, $low).scalar_start != scalar {
			return Err(InvalidLiteral({ occurrence: occurrence }))
		}
	} else if graphemes.is_empty() or list_at(graphemes, graphemes.len() - 1).scalar_end != scalar {
		return Err(InvalidLiteral({ occurrence: occurrence }))
	}
	Ok({ index: $low, probes: $probes })
}

empty_store : Text.Store
empty_store = { clusters: [], glyph_indices: [], glyphs: [], runs: [], substitutions: [], transformations: [] }

empty_work : KernelShape.Work
empty_work = { cluster_visits: 0, glyph_visits: 0, metric_reads: 0, scalar_visits: 0, script_run_visits: 0, utf8_bytes: 0 }

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(_) => crash "validated reference-shape index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(updated) => updated
	Err(_) => crash "validated reference-shape write escaped"
}

## Only dense, fully resolved contexts may freeze to the ordinary Shape
## plan consumed by text, scenes and PDF font planning.
finalize_shape : KernelFacadeReferenceShape.Plan, Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), U64 -> Try(KernelFacadeShape.Plan, KernelFacadeReferenceShape.Error)
finalize_shape = |plan, authoring, owners, count| {
	view = KernelFacadeReferenceShape.Plan.view(plan)
	if view.literals.len() != count or owners.len() != authoring.blocks.len() {
		return Err(InvalidSelection)
	}
	var $index = 0
	while $index < count {
		if list_at(view.literals, $index).occurrence.id.index() != $index or list_at(view.literal_runs, $index).context != $index {
			return Err(InvalidLiteral({ occurrence: $index }))
		}
		$index = $index + 1
	}
	var $blocks = List.with_capacity(owners.len())
	$index = 0
	while $index < owners.len() {
		block = match list_at(owners, $index) {
			ContentlessCell => ContentlessCell
			EmptySourceLine => match list_at(authoring.blocks, $index).kind {
				EmptySourceLine(value) => EmptySourceLine(value)
				_ => return Err(InvalidSelection)
			}
			TextBlock({ body, label, level }) => {
				if body.index() >= count {
					return Err(InvalidSelection)
				}
				{ body: { physical: list_at(view.literal_runs, body.index()).runs }, label: resolved_label(view.literal_runs, label), level } |> TextBlock
			}
			RichTextBlock({ occurrences, label, level }) => {
				if occurrences.length() == 0 or occurrences.start() + occurrences.length() > count {
					return Err(InvalidSelection)
				}
				first = list_at(view.literal_runs, occurrences.start()).runs
				last = list_at(view.literal_runs, occurrences.start() + occurrences.length() - 1).runs
				TextBlock({ body: { physical: Semantics.IndexRange.from_start_and_length({ start: first.start(), length: last.start() + last.length() - first.start() }) }, label: resolved_label(view.literal_runs, label), level })
			}
		}
		$blocks = $blocks.append(block)
		$index = $index + 1
	}
	var $font_bytes = 0
	var $font_tables = 0
	for font in view.fonts {
		$font_bytes = $font_bytes + font.bytes.len()
		$font_tables = $font_tables + font.work.directory_entries
	}
	work = view.work.shape
	final = KernelFacadeShape.Plan.from_contexts({ block_runs: $blocks, origins: Origins(view.origins), requests: view.requests, selection: view.selection, shape: { store: view.store, advances: view.advances, work }, styles: view.styles, work: { font_bytes: $font_bytes, font_tables: $font_tables, glyphs: work.glyph_visits, metric_reads: work.metric_reads, requests: view.work.selected_runs, scalars: work.scalar_visits, script_run_visits: work.script_run_visits, source_bytes: work.utf8_bytes } }, count) ? Style
	Ok(final)
}

resolved_label : List(KernelFacadeReferenceShape.LiteralRuns), [NoLabel, Label(Semantics.OccurrenceId)] -> [NoLabel, Label(KernelFacadeShape.LogicalRun)]
resolved_label = |runs, label| match label {
	NoLabel => NoLabel
	Label(id) => Label({ physical: list_at(runs, id.index()).runs })
}

expect {
	analysis = KernelUnicode.analyze("pré", KernelUnicode.default_limits)?
	bounds = cluster_bounds(analysis, { scalars: Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 }), utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: 0, length: 4 }) }, 9)?
	bounds.range.start() == 0 and bounds.range.length() == 3 and bounds.probes <= 6
}

expect {
	analysis = KernelUnicode.analyze("pré", KernelUnicode.default_limits)?
	match cluster_bounds(analysis, { scalars: Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 }), utf8_bytes: Semantics.IndexRange.from_start_and_length({ start: 0, length: 3 }) }, 9) {
		Err(InvalidLiteral({ occurrence: 9 })) => True
		_ => False
	}
}

## Audit only an unsuccessful shape, using exact selected source slices.
## This locates coverage, cluster and script failures without rescanning a
## preceding source prefix for each styled leaf or retaining source bytes
## inside the public diagnostic.
locate_failure : List(KernelFacadeReferenceShape.LiteralContext), List(KernelFacadeReferenceShape.LiteralRuns), List(KernelFacadeSources.Source), List(KernelFont.Inspection), List(KernelShape.SelectedBatchRequest), KernelShape.Error -> KernelFacadeReferenceShape.Error
locate_failure = |contexts, spans, sources, fonts, requests, error| {
	var $context = 0
	var $request = 0
	while $request < requests.len() {
		while $context < spans.len() and list_at(spans, $context).runs.start() + list_at(spans, $context).runs.length() <= $request {
			$context = $context + 1
		}
		if $context >= contexts.len() {
			return Shape(error)
		}
		context = list_at(contexts, $context)
		request = list_at(requests, $request)
		if request.source.index() >= sources.len() or request.instance.index() >= fonts.len() {
			return Shape(error)
		}
		source = list_at(sources, request.source.index())
		font = list_at(fonts, request.instance.index())
		if request.clusters.length() == 0 {
			return Shape(error)
		}
		first = list_at(source.analysis.graphemes, request.clusters.start())
		last = list_at(source.analysis.graphemes, request.clusters.start() + request.clusters.length() - 1)
		chunk = match Str.from_utf8(source.unicode.to_utf8().sublist({ start: first.byte_start, len: last.byte_end - first.byte_start })) {
			Ok(value) => value
			Err(_) => return Shape(error)
		}
		var $cluster = request.clusters.start()
		var $script = 0
		var $high = source.analysis.script_runs.len()
		while $script < $high {
			middle = $script + ($high - $script) // 2
			if list_at(source.analysis.script_runs, middle).range.scalar_end <= first.scalar_start {
				$script = middle + 1
			} else {
				$high = middle
			}
		}
		for located in Scalar.iter(chunk) {
			scalar = first.scalar_start + located.scalar_index
			while $cluster < request.clusters.start() + request.clusters.length() and list_at(source.analysis.graphemes, $cluster).scalar_end <= scalar {
				$cluster = $cluster + 1
			}
			while $script < source.analysis.script_runs.len() and list_at(source.analysis.script_runs, $script).range.scalar_end <= scalar {
				$script = $script + 1
			}
			if $cluster >= source.analysis.graphemes.len() or $script >= source.analysis.script_runs.len() {
				return Shape(error)
			}
			grapheme = list_at(source.analysis.graphemes, $cluster)
			actual_script = list_at(source.analysis.script_runs, $script).script
			value = Scalar.to_u32(located.scalar)
			covered = match KernelFont.glyph_for_scalar(font, value) {
				Some(glyph) => glyph != 0
				None => False
			}
			reason = if (grapheme.scalar_end - grapheme.scalar_start != 1) Failed(Cluster) else if (!covered) Failed(Coverage(value)) else if (actual_script != "Zyyy" and actual_script != "Zinh" and actual_script != request.script.to_str()) Failed(Script(actual_script)) else Passed
			match reason {
				Failed(found) => return Style(UnsupportedText({ block: context.block, inline: context.inline, reason: found, scalars: Semantics.IndexRange.from_start_and_length({ start: grapheme.scalar_start - literal_start(context), length: grapheme.scalar_end - grapheme.scalar_start }) }))
				Passed => {}
			}
		}
		$request = $request + 1
	}
	Shape(error)
}

## Preserve a rejected policy's explicit source/cluster identity in the
## authored location. Only an error visits contexts or decodes this exact
## grapheme slice; successful policy selection retains its existing work.
locate_policy_failure : List(KernelFacadeReferenceShape.LiteralContext), KernelFacadeSources.Source, U64, KernelFacadeShape.Error -> KernelFacadeReferenceShape.Error
locate_policy_failure = |contexts, source, source_id, error| {
	failure = match error {
		FontSelectionRejected(errors) => match errors.get(0) {
			Ok(MissingCoverage({ cluster, source: range })) if cluster < source.analysis.graphemes.len() => {
				grapheme = list_at(source.analysis.graphemes, cluster)
				if range.scalars.start() != grapheme.scalar_start or range.scalars.length() != grapheme.scalar_end - grapheme.scalar_start {
					return Style(error)
				}
				CoverageCluster(cluster)
			}
			_ => return Style(error)
		}
		UndeclaredScript({ script, source: rejected }) if rejected == source_id => {
			var $first = U64.highest
			for run in source.analysis.script_runs {
				if run.script == script {
					$first = run.range.scalar_start
					break
				}
			}
			var $cluster = 0
			while $cluster < source.analysis.graphemes.len() and list_at(source.analysis.graphemes, $cluster).scalar_end <= $first {
				$cluster = $cluster + 1
			}
			if $cluster >= source.analysis.graphemes.len() {
				return Style(error)
			}
			ScriptCluster({ cluster: $cluster, script })
		}
		_ => return Style(error)
	}
	cluster = match failure {
		CoverageCluster(index) => index
		ScriptCluster({ cluster: index, .. }) => index
	}
	grapheme = list_at(source.analysis.graphemes, cluster)
	for context in contexts {
		match context.occurrence.source {
			Text(id, UnicodeRange(range)) if id.index() == source_id and range.scalars.start() <= grapheme.scalar_start and range.scalars.start() + range.scalars.length() >= grapheme.scalar_end => {
				reason = match failure {
					ScriptCluster({ script, .. }) => Script(script)
					CoverageCluster(_) if grapheme.scalar_end - grapheme.scalar_start != 1 => Cluster
					CoverageCluster(_) => {
						chunk = match Str.from_utf8(source.unicode.to_utf8().sublist({ start: grapheme.byte_start, len: grapheme.byte_end - grapheme.byte_start })) {
							Ok(value) => value
							Err(_) => return Style(error)
						}
						var $scalar = NoScalar
						for located in Scalar.iter(chunk) {
							$scalar = HasScalar(Scalar.to_u32(located.scalar))
							break
						}
						match $scalar {
							HasScalar(value) => Coverage(value)
							NoScalar => return Style(error)
						}
					}
				}
				return Style(UnsupportedText({ block: context.block, inline: context.inline, reason, scalars: Semantics.IndexRange.from_start_and_length({ start: grapheme.scalar_start - range.scalars.start(), length: grapheme.scalar_end - grapheme.scalar_start }) }))
			}
			_ => {}
		}
	}
	Style(error)
}
