import Color
import Document
import Font
import KernelFacadeSemantics
import KernelFacadeSources
import KernelFont
import KernelUnicode
import KernelShape
import Layout
import Semantics
import Text
import Theme
import unicode.Scalar

KernelFacadeShape :: [].{
	Dimension : [Requests]
	Error : [
		ArtifactTextPending({ artifacts : U64 }),
		FontSelectionRejected(List(Font.PlanError)),
		GeneratedLabelEvidenceInvalid({ block : U64, occurrence : U64 }),
		InvalidOccurrence({ block : U64, occurrence : U64 }),
		LanguageMismatch({ occurrence : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		OccurrenceCoverage({ actual : U64, expected : U64 }),
		PolicyInvalid(Font.PolicyError),
		ShapeFailure,
		StyleArithmeticOverflow(U64),
		UndeclaredScript({ script : Str, source : U64 }),
		UnsupportedThemeFace({ block : U64, face : U64 }),
	]

	## The facade's resolved font selection. `Single` is the existing exact
	## one-face path; `Ordered` carries the caller registry and the
	## Theme-selected finite policy for per-cluster coverage selection.
	FontSelection : [Ordered({ policy : Font.PolicyId, registry : Font.Registry }), Single(KernelFont.Inspection)]
	Limits :: { max_requests : U64, shape : KernelShape.Limits }.{
		make : { max_requests : U64, shape : KernelShape.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	## A logical authoring occurrence may become more than one physical shaped
	## run when an earlier font plan selects different faces by grapheme
	## cluster. Keep that relationship explicit here, before line breaking has
	## an opportunity to split or place it. The current built-in Latin path
	## creates exactly one physical run; later multi-face materialization will
	## be allowed to widen this range without changing block ownership.
	LogicalRun : { physical : Semantics.Range }
	BlockRuns : [ArtifactBlock(U64), TextBlock({ body : LogicalRun, label : [Label(LogicalRun), NoLabel] })]
	RunStyle : { color : Color.SourceValue, leading : Layout.Unit }
	Work : {
		font_bytes : U64,
		font_tables : U64,
		glyphs : U64,
		metric_reads : U64,
		requests : U64,
		scalars : U64,
		script_run_visits : U64,
		source_bytes : U64,
	}

	SelectionWork : {
		coverage_span_visits : U64,
		face_visits : U64,
		grapheme_visits : U64,
		planned_sources : U64,
		selection_ranges : U64,
	}

	## `SingleFace` marks the exact one-face path and adds no retained state.
	## `OrderedFaces` retains the dense used-font identities in policy order:
	## index k is the run-level `InstanceId` k and the k-th font plan, subset,
	## and `F1_k` resource of PDF lowering.
	Selection : [
		OrderedFaces({ faces : List(Font.FaceId), fonts : List(KernelFont.Inspection), work : SelectionWork }),
		SingleFace,
	]
	Preparation :: { block_runs : List(BlockRuns), options : KernelShape.BatchOptions, requests : List(KernelShape.SimpleRequest), styles : List(RunStyle) }.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, U64, U64, U64, Theme -> Try(Preparation, Error)
		build = |authoring, owners, store, source_count, artifact_count, max_requests, theme| prepare_plan(authoring, owners, store, source_count, artifact_count, max_requests, theme, RequireBuiltInFace)

		block_runs : Preparation -> List(BlockRuns)
		block_runs = |preparation| preparation.block_runs

		options : Preparation -> KernelShape.BatchOptions
		options = |preparation| preparation.options

		requests : Preparation -> List(KernelShape.SimpleRequest)
		requests = |preparation| preparation.requests

		styles : Preparation -> List(RunStyle)
		styles = |preparation| preparation.styles
	}
	Plan :: {
		block_runs : List(BlockRuns),
		requests : List(KernelShape.SimpleRequest),
		selection : Selection,
		shape : KernelShape.Batch,
		styles : List(RunStyle),
		work : Work,
	}.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, KernelFont.Inspection, Theme, Limits -> Try(Plan, Error)
		build = |authoring, owners, store, sources, artifact_count, font, theme, limits| build_plan(authoring, owners, store, sources, artifact_count, font, theme, limits)

		## The ordered multi-face arm: policy resolution, once-per-unique-source
		## coverage planning, physical-run splitting, and selected shaping. The
		## single-face `build` path above is untouched by this entry point.
		build_ordered : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Limits -> Try(Plan, Error)
		build_ordered = |authoring, owners, store, sources, artifact_count, ordered, theme, limits| build_ordered_plan(authoring, owners, store, sources, artifact_count, ordered, theme, limits)

		block_runs : Plan -> List(BlockRuns)
		block_runs = |plan| plan.block_runs

		requests : Plan -> List(KernelShape.SimpleRequest)
		requests = |plan| plan.requests

		selection : Plan -> Selection
		selection = |plan| plan.selection

		## Dense used-font inspections in policy order; the single-face path
		## reports none because its one inspection travels beside the plan.
		fonts : Plan -> List(KernelFont.Inspection)
		fonts = |plan| match plan.selection {
			OrderedFaces(ordered) => ordered.fonts
			SingleFace => []
		}

		selected_faces : Plan -> List(Font.FaceId)
		selected_faces = |plan| match plan.selection {
			OrderedFaces(ordered) => ordered.faces
			SingleFace => []
		}

		shape : Plan -> KernelShape.Batch
		shape = |plan| plan.shape

		styles : Plan -> List(RunStyle)
		styles = |plan| plan.styles

		work : Plan -> Work
		work = |plan| plan.work
	}
}

logical_run_single : Text.RunId -> KernelFacadeShape.LogicalRun
logical_run_single = |run| { physical: Semantics.Range.from_start_and_length(run.index(), 1) }

build_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, KernelFont.Inspection, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_plan = |authoring, owners, store, source_store, artifact_count, font, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store.len(), artifact_count, limits.max_requests, theme, RequireBuiltInFace)?
	shape = match KernelShape.shape_simple_batch(font, source_store, preparation.options, preparation.requests, limits.shape) {
		Err(_) => return Err(ShapeFailure)
		Ok(value) => value
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: preparation.block_runs,
			requests: preparation.requests,
			selection: SingleFace,
			shape,
			styles: preparation.styles,
			work: {
				font_bytes: font.bytes.len(),
				font_tables: font.work.directory_entries,
				glyphs: shape.work.glyph_visits,
				metric_reads: shape.work.metric_reads,
				requests: preparation.requests.len(),
				scalars: shape.work.scalar_visits,
				script_run_visits: shape.work.script_run_visits,
				source_bytes: shape.work.utf8_bytes,
			},
		},
	)
}

## The single-face path requires every style to reference the exact resolved
## face; the ordered-policy path resolves fonts per cluster instead, so style
## face identities are deliberately not consulted there.
FaceCheck : [RequireBuiltInFace, PolicySelectsFaces]

prepare_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, U64, U64, U64, Theme, FaceCheck -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_plan = |authoring, owners, store, source_count, artifact_count, max_requests, theme, face_check| {
	if artifact_count != 0 {
		return Err(ArtifactTextPending({ artifacts: artifact_count }))
	}
	batch_language = Language(authoring.language)
	batch_options = {
		direction: LeftToRight,
		instance: Font.InstanceId.from_index(0),
		language: batch_language,
		script: Font.Script.from_iso15924("Latn"),
		writing_mode: Horizontal,
	}
	occurrence_count = store.occurrences.len()
	if occurrence_count > max_requests {
		return Err(LimitExceeded({ attempted: occurrence_count, dimension: Requests, limit: max_requests }))
	}
	default_style = Theme.body_style(theme)
	var $requests = List.repeat({ occurrence: Semantics.OccurrenceId.from_index(0), size: default_style.size, source: Semantics.TextSourceId.from_index(0) }, occurrence_count)
	var $styles = List.repeat({ color: default_style.color, leading: default_style.leading }, occurrence_count)
	var $block_runs = List.repeat(ArtifactBlock(0), authoring.blocks.len())
	var $request_index = 0
	var $block_index = 0
	while $block_index < authoring.blocks.len() {
		block = list_at(authoring.blocks, $block_index)
		owner = list_at(owners, $block_index)
		match owner {
			ArtifactBlock(artifact) => {
				$block_runs = match $block_runs.set($block_index, ArtifactBlock(artifact)) {
					Err(OutOfBounds) => {
						crash "validated facade shaping artifact write escaped"
					}
					Ok(updated) => updated
				}
			}
			TextBlock({ body, label }) => {
				body_style = match block.kind {
					Figure(index) => figure_style(list_at(authoring.figures, index), theme, $block_index)?
					_ => style_for(block.kind, theme)
				}
				if face_check == RequireBuiltInFace and body_style.font.index() != 0 {
					return Err(UnsupportedThemeFace({ block: $block_index, face: body_style.font.index() }))
				}
				label_run = match label {
					NoLabel => NoLabel
					Label(occurrence_id) => {
						label_style = Theme.body_style(theme)
						if face_check == RequireBuiltInFace and label_style.font.index() != 0 {
							return Err(UnsupportedThemeFace({ block: $block_index, face: label_style.font.index() }))
						}
						if $request_index >= occurrence_count {
							return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
						}
						occurrence_index = occurrence_id.index()
						if occurrence_index >= store.occurrences.len() {
							return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
						}
						occurrence = list_at(store.occurrences, occurrence_index)
						if !generated_label_evidence_valid(occurrence, store.text_properties) {
							return Err(GeneratedLabelEvidenceInvalid({ block: $block_index, occurrence: occurrence_index }))
						}
						if occurrence.language != batch_language {
							return Err(LanguageMismatch({ occurrence: occurrence_index }))
						}
						source_id = match occurrence.source {
							Text(id, UnicodeRange(_)) => id
							_ => return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
						}
						if source_id.index() >= source_count {
							return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
						}
						run = logical_run_single(Text.RunId.from_index($request_index))
						$requests = match $requests.set(
							$request_index,
							{
								occurrence: occurrence_id,
								size: label_style.size,
								source: source_id,
							},
						) {
							Err(OutOfBounds) => return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
							Ok(updated) => updated
						}
						$styles = match $styles.set($request_index, { color: label_style.color, leading: label_style.leading }) {
							Err(OutOfBounds) => return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
							Ok(updated) => updated
						}
						$request_index = $request_index + 1
						Label(run)
					}
				}
				if $request_index >= occurrence_count {
					return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
				}
				occurrence_index = body.index()
				if occurrence_index >= store.occurrences.len() {
					return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
				}
				occurrence = list_at(store.occurrences, occurrence_index)
				if occurrence.language != batch_language {
					return Err(LanguageMismatch({ occurrence: occurrence_index }))
				}
				source_id = match occurrence.source {
					Text(id, UnicodeRange(_)) => id
					_ => return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
				}
				if source_id.index() >= source_count {
					return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrence_index }))
				}
				body_run = logical_run_single(Text.RunId.from_index($request_index))
				$requests = match $requests.set(
					$request_index,
					{
						occurrence: body,
						size: body_style.size,
						source: source_id,
					},
				) {
					Err(OutOfBounds) => return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
					Ok(updated) => updated
				}
				$styles = match $styles.set($request_index, { color: body_style.color, leading: body_style.leading }) {
					Err(OutOfBounds) => return Err(OccurrenceCoverage({ actual: $request_index + 1, expected: occurrence_count }))
					Ok(updated) => updated
				}
				$request_index = $request_index + 1
				$block_runs = match $block_runs.set($block_index, TextBlock({ body: body_run, label: label_run })) {
					Err(OutOfBounds) => {
						crash "validated facade shaping text write escaped"
					}
					Ok(updated) => updated
				}
			}
		}
		$block_index = $block_index + 1
	}
	if $request_index != occurrence_count {
		return Err(OccurrenceCoverage({ actual: $request_index, expected: occurrence_count }))
	}
	Ok(KernelFacadeShape.Preparation.{ block_runs: $block_runs, options: batch_options, requests: $requests, styles: $styles })
}

## One selected physical segment of a source: a contiguous grapheme-cluster
## range owned by one dense output font and one itemized script.
SelectedSegment : { clusters : Semantics.Range, font : U64, script : Font.Script }

build_ordered_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, { policy : Font.PolicyId, registry : Font.Registry }, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_ordered_plan = |authoring, owners, store, source_store, artifact_count, ordered, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store.len(), artifact_count, limits.max_requests, theme, PolicySelectsFaces)?
	policy_faces = ordered.registry.policy_faces(ordered.policy) ? PolicyInvalid
	batch_language = preparation.options.language

	## Coverage selection runs once per unique interned source; every later
	## occurrence of that source reuses the completed plan. This is the
	## selection-plan cache realized through source identity.
	var $ranges_per_source = List.with_capacity(source_store.len())
	var $selection_work = { coverage_span_visits: 0, face_visits: 0, grapheme_visits: 0, planned_sources: 0, selection_ranges: 0 }
	var $source_index = 0
	while $source_index < source_store.len() {
		source = list_at(source_store, $source_index)
		clusters = ordered_source_clusters(source, $source_index)?
		selection = match ordered.registry.plan({ clusters, language: batch_language, policy: ordered.policy, source: Semantics.TextSourceId.from_index($source_index) }) {
			Complete(value) => value
			Rejected(errors) => return Err(FontSelectionRejected(errors))
		}
		$selection_work = {
			coverage_span_visits: $selection_work.coverage_span_visits + selection.work.coverage_span_visits,
			face_visits: $selection_work.face_visits + selection.work.face_visits,
			grapheme_visits: $selection_work.grapheme_visits + selection.work.grapheme_visits,
			planned_sources: $selection_work.planned_sources + 1,
			selection_ranges: $selection_work.selection_ranges + selection.face_ranges.len(),
		}
		$ranges_per_source = $ranges_per_source.append(selection.face_ranges)
		$source_index = $source_index + 1
	}

	## The dense used-font list follows policy order, so output font identity
	## `k` deterministically names the k-th selected face's plan and subset.
	var $used_faces = []
	var $fonts = []
	registry_store = ordered.registry.store()
	var $policy_position = 0
	while $policy_position < policy_faces.len() {
		face = list_at(policy_faces, $policy_position)
		if face_selected_anywhere($ranges_per_source, face) {

			## The face's registered shaping provision is a capability fact:
			## the built-in convenience shaper only drives faces declared for
			## it, never a face registered for advanced caller runs only.
			if face.index() >= registry_store.faces.len() {
				return Err(PolicyInvalid(UnknownPolicyFace(face)))
			}
			face_record = list_at(registry_store.faces, face.index())
			if face_record.provision != BuiltIn {
				script_index = face_record.scripts.start()
				script = if script_index < registry_store.scripts.len() list_at(registry_store.scripts, script_index) else Font.Script.from_iso15924("Zzzz")
				return Err(FontSelectionRejected([UnsupportedBuiltInShaping({ cluster: 0, script })]))
			}
			inspection = ordered.registry.prepared_face(face) ? |_| PolicyInvalid(UnknownPolicyFace(face))
			$used_faces = $used_faces.append(face)
			$fonts = $fonts.append(inspection)
		}
		$policy_position = $policy_position + 1
	}

	## Refine each source's selected face ranges at itemized script-run
	## boundaries so every physical run carries one exact script fact.
	var $segments_per_source = List.with_capacity(source_store.len())
	$source_index = 0
	while $source_index < source_store.len() {
		source = list_at(source_store, $source_index)
		segments = ordered_segments(list_at($ranges_per_source, $source_index), source.analysis.script_runs, $used_faces, $source_index)?
		$segments_per_source = $segments_per_source.append(segments)
		$source_index = $source_index + 1
	}

	## Expand each logical occurrence request into its physical selected runs
	## in the exact order the preparation assigned occurrence requests.
	var $selected_requests = []
	var $physical_requests = []
	var $physical_styles = []
	var $block_runs = List.repeat(ArtifactBlock(0), preparation.block_runs.len())
	var $block_index = 0
	while $block_index < preparation.block_runs.len() {
		match list_at(preparation.block_runs, $block_index) {
			ArtifactBlock(artifact) => {
				$block_runs = list_set($block_runs, $block_index, ArtifactBlock(artifact))
			}
			TextBlock({ body, label }) => {
				expanded_label = match label {
					NoLabel => NoLabel
					Label(logical) => {
						expanded = expand_logical(logical, preparation, $segments_per_source, $selected_requests, $physical_requests, $physical_styles, limits.max_requests)?
						$selected_requests = expanded.selected
						$physical_requests = expanded.requests
						$physical_styles = expanded.styles
						Label(expanded.run)
					}
				}
				expanded_body = expand_logical(body, preparation, $segments_per_source, $selected_requests, $physical_requests, $physical_styles, limits.max_requests)?
				$selected_requests = expanded_body.selected
				$physical_requests = expanded_body.requests
				$physical_styles = expanded_body.styles
				$block_runs = list_set($block_runs, $block_index, TextBlock({ body: expanded_body.run, label: expanded_label }))
			}
		}
		$block_index = $block_index + 1
	}

	shape = match KernelShape.shape_selected_batch($fonts, source_store, { direction: LeftToRight, language: batch_language, writing_mode: Horizontal }, $selected_requests, limits.shape) {
		Err(_) => return Err(ShapeFailure)
		Ok(value) => value
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: $block_runs,
			requests: $physical_requests,
			selection: OrderedFaces({ faces: $used_faces, fonts: $fonts, work: $selection_work }),
			shape,
			styles: $physical_styles,
			work: {
				font_bytes: total_font_bytes($fonts),
				font_tables: total_font_tables($fonts),
				glyphs: shape.work.glyph_visits,
				metric_reads: shape.work.metric_reads,
				requests: $physical_requests.len(),
				scalars: shape.work.scalar_visits,
				script_run_visits: shape.work.script_run_visits,
				source_bytes: shape.work.utf8_bytes,
			},
		},
	)
}

## Segmented grapheme-cluster facts for coverage planning: one cluster per
## grapheme with its exact scalar values and itemized script. Scripts outside
## the declared convenience set are typed rejections here, before any
## coverage probe or shaping work.
ordered_source_clusters : KernelFacadeSources.Source, U64 -> Try(List(Font.SourceCluster), KernelFacadeShape.Error)
ordered_source_clusters = |source, source_index| {
	analysis = source.analysis
	var $clusters = List.with_capacity(analysis.graphemes.len())
	var $run_cursor = 0
	var $grapheme_index = 0
	var $scalars = []
	for located in Scalar.iter(source.unicode) {
		if $grapheme_index >= analysis.graphemes.len() {
			return Err(InvalidOccurrence({ block: 0, occurrence: source_index }))
		}
		grapheme = list_at(analysis.graphemes, $grapheme_index)
		$scalars = $scalars.append(Scalar.to_u32(located.scalar))
		if located.scalar_index + 1 == grapheme.scalar_end {
			script = ordered_script_at(analysis.script_runs, grapheme.scalar_start, $run_cursor, source_index)?
			$run_cursor = script.cursor
			$clusters = $clusters.append({
				scalars: $scalars,
				script: script.script,
				source: {
					scalars: Semantics.Range.from_start_and_length(grapheme.scalar_start, grapheme.scalar_end - grapheme.scalar_start),
					utf8_bytes: Semantics.Range.from_start_and_length(grapheme.byte_start, grapheme.byte_end - grapheme.byte_start),
				},
			})
			$scalars = []
			$grapheme_index = $grapheme_index + 1
		}
	}
	if $grapheme_index != analysis.graphemes.len() {
		Err(InvalidOccurrence({ block: 0, occurrence: source_index }))
	} else {
		Ok($clusters)
	}
}

## The convenience path's declared script set. Everything else, including an
## unresolved Common itemization run, is an explicit typed rejection rather
## than an implicit fallback face search.
declared_script : Str -> Bool
declared_script = |alias| alias == "Latn" or alias == "Hani"

ordered_script_at : List(KernelUnicode.ScriptRun), U64, U64, U64 -> Try({ cursor : U64, script : Font.Script }, KernelFacadeShape.Error)
ordered_script_at = |runs, scalar_index, cursor, source_index| {
	var $cursor = cursor
	while $cursor < runs.len() and list_at(runs, $cursor).range.scalar_end <= scalar_index {
		$cursor = $cursor + 1
	}
	if $cursor >= runs.len() {
		return Err(UndeclaredScript({ script: "", source: source_index }))
	}
	run = list_at(runs, $cursor)
	if !declared_script(run.script) {
		return Err(UndeclaredScript({ script: run.script, source: source_index }))
	}
	Ok({ cursor: $cursor, script: Font.Script.from_iso15924(run.script) })
}

face_selected_anywhere : List(List(Font.FaceRange)), Font.FaceId -> Bool
face_selected_anywhere = |ranges_per_source, face| {
	var $source_index = 0
	while $source_index < ranges_per_source.len() {
		ranges = list_at(ranges_per_source, $source_index)
		var $range_index = 0
		while $range_index < ranges.len() {

			## Registered static instances share their face's dense index.
			if list_at(ranges, $range_index).instance.index() == face.index() {
				return Bool.True
			}
			$range_index = $range_index + 1
		}
		$source_index = $source_index + 1
	}
	Bool.False
}

ordered_segments : List(Font.FaceRange), List(KernelUnicode.ScriptRun), List(Font.FaceId), U64 -> Try(List(SelectedSegment), KernelFacadeShape.Error)
ordered_segments = |face_ranges, script_runs, used_faces, source_index| {
	var $segments = []
	var $range_index = 0
	while $range_index < face_ranges.len() {
		range = list_at(face_ranges, $range_index)
		font = dense_font_index(used_faces, range.instance, source_index)?
		range_start = range.clusters.start()
		range_length = range.clusters.length()
		range_end = range_start + range_length
		var $cursor = range_start
		while $cursor < range_end {
			run = script_run_covering(script_runs, $cursor, source_index)?
			segment_end = if run.range.scalar_end < range_end run.range.scalar_end else range_end
			if segment_end <= $cursor {
				return Err(UndeclaredScript({ script: run.script, source: source_index }))
			}
			if !declared_script(run.script) {
				return Err(UndeclaredScript({ script: run.script, source: source_index }))
			}
			$segments = $segments.append({
				clusters: Semantics.Range.from_start_and_length($cursor, segment_end - $cursor),
				font,
				script: Font.Script.from_iso15924(run.script),
			})
			$cursor = segment_end
		}
		$range_index = $range_index + 1
	}
	Ok($segments)
}

script_run_covering : List(KernelUnicode.ScriptRun), U64, U64 -> Try(KernelUnicode.ScriptRun, KernelFacadeShape.Error)
script_run_covering = |runs, scalar_index, source_index| {
	var $index = 0
	while $index < runs.len() {
		run = list_at(runs, $index)
		if run.range.scalar_start <= scalar_index and scalar_index < run.range.scalar_end {
			return Ok(run)
		}
		$index = $index + 1
	}
	Err(UndeclaredScript({ script: "", source: source_index }))
}

dense_font_index : List(Font.FaceId), Font.InstanceId, U64 -> Try(U64, KernelFacadeShape.Error)
dense_font_index = |used_faces, instance, source_index| {
	var $index = 0
	while $index < used_faces.len() {
		if list_at(used_faces, $index).index() == instance.index() {
			return Ok($index)
		}
		$index = $index + 1
	}
	Err(InvalidOccurrence({ block: 0, occurrence: source_index }))
}

Expanded : { requests : List(KernelShape.SimpleRequest), run : KernelFacadeShape.LogicalRun, selected : List(KernelShape.SelectedBatchRequest), styles : List(KernelFacadeShape.RunStyle) }

## Split one logical occurrence request into its per-segment physical runs.
## Every logical run keeps a physical range of at least one; the segment
## split is the per-source selection fact, never recomputed per occurrence.
expand_logical : KernelFacadeShape.LogicalRun, KernelFacadeShape.Preparation, List(List(SelectedSegment)), List(KernelShape.SelectedBatchRequest), List(KernelShape.SimpleRequest), List(KernelFacadeShape.RunStyle), U64 -> Try(Expanded, KernelFacadeShape.Error)
expand_logical = |logical, preparation, segments_per_source, selected, physical_requests, styles, max_requests| {
	if logical.physical.length() != 1 {
		return Err(OccurrenceCoverage({ actual: logical.physical.length(), expected: 1 }))
	}
	request_index = logical.physical.start()
	if request_index >= preparation.requests.len() {
		return Err(OccurrenceCoverage({ actual: request_index, expected: preparation.requests.len() }))
	}
	request = list_at(preparation.requests, request_index)
	style = list_at(preparation.styles, request_index)
	source_index = request.source.index()
	if source_index >= segments_per_source.len() {
		return Err(InvalidOccurrence({ block: 0, occurrence: request_index }))
	}
	segments = list_at(segments_per_source, source_index)
	if segments.is_empty() {
		return Err(OccurrenceCoverage({ actual: 0, expected: 1 }))
	}
	physical_start = physical_requests.len()
	attempted = physical_start + segments.len()
	if attempted > max_requests {
		return Err(LimitExceeded({ attempted, dimension: Requests, limit: max_requests }))
	}
	var $selected = selected
	var $requests = physical_requests
	var $styles = styles
	var $segment_index = 0
	while $segment_index < segments.len() {
		segment = list_at(segments, $segment_index)
		$selected = $selected.append({
			clusters: segment.clusters,
			instance: Font.InstanceId.from_index(segment.font),
			occurrence: request.occurrence,
			script: segment.script,
			size: request.size,
			source: request.source,
		})
		$requests = $requests.append(request)
		$styles = $styles.append(style)
		$segment_index = $segment_index + 1
	}
	Ok({
		requests: $requests,
		run: { physical: Semantics.Range.from_start_and_length(physical_start, segments.len()) },
		selected: $selected,
		styles: $styles,
	})
}

total_font_bytes : List(KernelFont.Inspection) -> U64
total_font_bytes = |fonts| {
	var $total = 0
	var $index = 0
	while $index < fonts.len() {
		$total = $total + list_at(fonts, $index).bytes.len()
		$index = $index + 1
	}
	$total
}

total_font_tables : List(KernelFont.Inspection) -> U64
total_font_tables = |fonts| {
	var $total = 0
	var $index = 0
	while $index < fonts.len() {
		$total = $total + list_at(fonts, $index).work.directory_entries
		$index = $index + 1
	}
	$total
}

## Labels are generated presentation, not punctuation inferred from a layout
## position. The source occurrence and its sole generated-text property remain
## coupled before shaping so later text lowering receives an explicit fact.
generated_label_evidence_valid : Semantics.ContentOccurrence, List(Semantics.TextProperty) -> Bool
generated_label_evidence_valid = |occurrence, properties| {
	match occurrence.source {
		Text(_, UnicodeRange(source_range)) => {
			property_range = occurrence.text_properties
			if property_range.length() != 1 or property_range.start() >= properties.len() {
				False
			} else {
				match list_at(properties, property_range.start()) {
					SourceToPresentation({ kind: GeneratedText, presentation, source }) => presentation == "•" and text_ranges_equal(source, source_range)
					_ => False
				}
			}
		}
		_ => False
	}
}

text_ranges_equal : Semantics.TextRange, Semantics.TextRange -> Bool
text_ranges_equal = |left, right| {
	scalars_equal = ranges_equal(left.scalars, right.scalars)
	bytes_equal = ranges_equal(left.utf8_bytes, right.utf8_bytes)
	scalars_equal and bytes_equal
}

ranges_equal : Semantics.Range, Semantics.Range -> Bool
ranges_equal = |left, right| {
	left_start = left.start()
	right_start = right.start()
	left_length = left.length()
	right_length = right.length()
	left_start == right_start and left_length == right_length
}

style_for : Document.NormalizedBlockKind, Theme -> Theme.TextStyle
style_for = |kind, theme| match kind {
	Title => Theme.title_style(theme)
	Heading(_) | DestinationHeading(_) => Theme.heading_style(theme)
	Bullet(_) | Paragraph | DestinationParagraph(_) | Link(_) | InternalLink(_) | Figure(_) | PageArtifact(_) => Theme.body_style(theme)
}

figure_style : Document.NormalizedFigure, Theme, U64 -> Try(Theme.TextStyle, KernelFacadeShape.Error)
figure_style = |figure, theme, block| {
	body = Theme.body_style(theme)
	leading = I64.plus_try(body.leading.raw(), figure.placement.size.height.raw()) ? |_| StyleArithmeticOverflow(block)
	Ok({ ..body, leading: Layout.Unit.from_raw(leading) })
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade shaping index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade shaping write escaped"
	}
	Ok(updated) => updated
}
