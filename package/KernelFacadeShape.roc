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
		InlineClusterBoundary({ block : U64, inline : U64 }),
		InvalidOccurrence({ block : U64, occurrence : U64 }),
		LanguageMismatch({ occurrence : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		OccurrenceCoverage({ actual : U64, expected : U64 }),
		PolicyInvalid(Font.PolicyError),
		ShapeFailure,
		StyleArithmeticOverflow(U64),
		UndeclaredScript({ script : Str, source : U64 }),
		UnsupportedInlineScript({ block : U64, inline : U64, script : Str }),
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
	##
	## A rich paragraph is one logical run over its one interned source: its
	## physical runs are the per-occurrence (and, on the ordered path, per
	## face) segments in logical order, all at the paragraph's size and
	## leading, so line breaking measures the whole paragraph at once.
	LogicalRun : { physical : Semantics.Range }
	BlockRuns : [ArtifactBlock(U64), TextBlock({ body : LogicalRun, label : [Label(LogicalRun), NoLabel], level : U64 })]
	RunStyle : { color : Color.SourceValue, leading : Layout.Unit }

	## Where each physical run's occurrence begins inside its interned source.
	## Shaped and line-layout ranges are source coordinates; the final text
	## store is occurrence-relative. `WholeSources` states the construction
	## fact that every occurrence covers its entire source (no rich paragraph
	## exists), so no rebasing is needed; `Origins` has one entry per
	## physical run.
	Origin : { byte : U64, scalar : U64 }
	Origins : [Origins(List(Origin)), WholeSources]

	## One request's exact cluster range of its source, the natural language
	## of its occurrence, and where that occurrence begins in the source.
	RequestRange : { clusters : Semantics.Range, language : Semantics.Language, origin : Origin }
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

	## `ranges` is empty unless the document has a rich paragraph; then it
	## holds one entry per request, in request order.
	Preparation :: { block_runs : List(BlockRuns), options : KernelShape.BatchOptions, ranges : List(RequestRange), requests : List(KernelShape.SimpleRequest), styles : List(RunStyle) }.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, U64, Theme -> Try(Preparation, Error)
		build = |authoring, owners, store, sources, artifact_count, max_requests, theme| prepare_plan(authoring, owners, store, sources, artifact_count, max_requests, theme, RequireBuiltInFace)

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
		origins : Origins,
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

		origins : Plan -> Origins
		origins = |plan| plan.origins

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
	preparation = prepare_plan(authoring, owners, store, source_store, artifact_count, limits.max_requests, theme, RequireBuiltInFace)?

	## Without a rich paragraph every occurrence covers its whole source and
	## the exact whole-source batch shaper applies. A rich paragraph's
	## occurrences cover sub-ranges of one source, which the range-exact
	## selected shaper consumes with the one resolved face.
	shaped = if preparation.ranges.is_empty() {
		KernelShape.shape_simple_batch(font, source_store, preparation.options, preparation.requests, limits.shape)
	} else {
		KernelShape.shape_selected_batch([font], source_store, { direction: LeftToRight, language: preparation.options.language, writing_mode: Horizontal }, single_face_requests(preparation), limits.shape)
	}
	shape = match shaped {
		Err(_) => return Err(ShapeFailure)
		Ok(value) => value
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: preparation.block_runs,
			origins: request_origins(preparation.ranges),
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

## Range-exact requests over the one resolved face (dense font 0), in
## preparation order: each request shapes exactly its occurrence's clusters.
single_face_requests : KernelFacadeShape.Preparation -> List(KernelShape.SelectedBatchRequest)
single_face_requests = |preparation| {
	latin = Font.Script.from_iso15924("Latn")
	var $selected = List.with_capacity(preparation.requests.len())
	var $index = 0
	while $index < preparation.requests.len() {
		request = list_at(preparation.requests, $index)
		range = list_at(preparation.ranges, $index)
		$selected = $selected.append({ clusters: range.clusters, instance: Font.InstanceId.from_index(0), language: range.language, occurrence: request.occurrence, script: latin, size: request.size, source: request.source })
		$index = $index + 1
	}
	$selected
}

request_origins : List(KernelFacadeShape.RequestRange) -> KernelFacadeShape.Origins
request_origins = |ranges| if ranges.is_empty() WholeSources else Origins(ranges.map(|range| range.origin))

## The single-face path requires every style to reference the exact resolved
## face; the ordered-policy path resolves fonts per cluster instead, so style
## face identities are deliberately not consulted there.
FaceCheck : [RequireBuiltInFace, PolicySelectsFaces]

## Request ranges exist only when a rich paragraph does. A document without
## one keeps the exact whole-source preparation and its buffers; a document
## with one prepares every request with its exact cluster range, language,
## and occurrence origin.
prepare_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, U64, Theme, FaceCheck -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_plan = |authoring, owners, store, sources, artifact_count, max_requests, theme, face_check| {
	if artifact_count != 0 {
		return Err(ArtifactTextPending({ artifacts: artifact_count }))
	}
	occurrence_count = store.occurrences.len()
	if occurrence_count > max_requests {
		return Err(LimitExceeded({ attempted: occurrence_count, dimension: Requests, limit: max_requests }))
	}
	if has_rich_block(owners) {
		prepare_ranged_plan(authoring, owners, store, sources, theme, face_check)
	} else {
		prepare_whole_plan(authoring, owners, store, sources, theme, face_check)
	}
}

batch_options_for : Document.NormalizedAuthoring -> KernelShape.BatchOptions
batch_options_for = |authoring| {
	direction: LeftToRight,
	instance: Font.InstanceId.from_index(0),
	language: Language(authoring.language),
	script: Font.Script.from_iso15924("Latn"),
	writing_mode: Horizontal,
}

prepare_whole_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), Theme, FaceCheck -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_whole_plan = |authoring, owners, store, sources, theme, face_check| {
	source_count = sources.len()
	batch_language = Language(authoring.language)
	batch_options = {
		direction: LeftToRight,
		instance: Font.InstanceId.from_index(0),
		language: batch_language,
		script: Font.Script.from_iso15924("Latn"),
		writing_mode: Horizontal,
	}
	occurrence_count = store.occurrences.len()
	var $requests = List.with_capacity(occurrence_count)
	var $styles = List.with_capacity(occurrence_count)
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
			RichTextBlock({ label: _, level: _, occurrences }) => return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrences.start() }))
			TextBlock({ body, label, level }) => {
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
						if !generated_label_evidence_valid(occurrence, store.text_properties, sources) {
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
						$requests = $requests.append({ occurrence: occurrence_id, size: label_style.size, source: source_id })
						$styles = $styles.append({ color: label_style.color, leading: label_style.leading })
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
				$requests = $requests.append({ occurrence: body, size: body_style.size, source: source_id })
				$styles = $styles.append({ color: body_style.color, leading: body_style.leading })
				$request_index = $request_index + 1
				$block_runs = match $block_runs.set($block_index, TextBlock({ body: body_run, label: label_run, level })) {
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
	Ok(KernelFacadeShape.Preparation.{ block_runs: $block_runs, options: batch_options, ranges: [], requests: $requests, styles: $styles })
}

## The ranged preparation of a document with rich paragraphs: one request
## per occurrence in block order, each with its exact cluster range of its
## source, its natural language, and its occurrence origin. Plain blocks
## keep whole-source ranges in the document language. Buffers move through
## the per-block helpers as separate arguments so they stay uniquely owned.
prepare_ranged_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), Theme, FaceCheck -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_ranged_plan = |authoring, owners, store, sources, theme, face_check| {
	batch_options = batch_options_for(authoring)
	occurrence_count = store.occurrences.len()
	var $requests = List.with_capacity(occurrence_count)
	var $styles = List.with_capacity(occurrence_count)
	var $ranges = List.with_capacity(occurrence_count)
	var $block_runs = List.repeat(ArtifactBlock(0), authoring.blocks.len())
	var $block_index = 0
	while $block_index < authoring.blocks.len() {
		block = list_at(authoring.blocks, $block_index)
		first_request = $requests.len()
		at = { authoring, block: $block_index, face_check, language: batch_options.language, sources, store, theme }
		match list_at(owners, $block_index) {
			ArtifactBlock(artifact) => {
				$block_runs = list_set($block_runs, $block_index, ArtifactBlock(artifact))
			}
			RichTextBlock({ label, level, occurrences }) => {
				rich = match block.kind {
					RichParagraph(paragraph) => list_at(authoring.rich_paragraphs, paragraph)
					_ => return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrences.start() }))
				}
				body_start = match label {
					NoLabel => first_request
					Label(_) => first_request + 1
				}
				if occurrences.length() != rich.leaves or body_start + rich.leaves > occurrence_count {
					return Err(OccurrenceCoverage({ actual: body_start + rich.leaves, expected: occurrence_count }))
				}
				label_run = match label {
					NoLabel => NoLabel
					Label(_) => Label(logical_run_single(Text.RunId.from_index(first_request)))
				}
				$block_runs = list_set($block_runs, $block_index, TextBlock({ body: { physical: Semantics.Range.from_start_and_length(body_start, rich.leaves) }, label: label_run, level }))
				match label {
					NoLabel => {}
					Label(_) => {
						labelled = append_label_request($ranges, $requests, $styles, at, label)?
						$ranges = labelled.ranges
						$requests = labelled.requests
						$styles = labelled.styles
					}
				}
				appended = append_rich_requests($ranges, $requests, $styles, at, occurrences, rich)?
				$ranges = appended.ranges
				$requests = appended.requests
				$styles = appended.styles
			}
			TextBlock({ body, label, level }) => {
				body_start = match label {
					NoLabel => first_request
					Label(_) => first_request + 1
				}
				label_run = match label {
					NoLabel => NoLabel
					Label(_) => Label(logical_run_single(Text.RunId.from_index(first_request)))
				}
				$block_runs = list_set($block_runs, $block_index, TextBlock({ body: logical_run_single(Text.RunId.from_index(body_start)), label: label_run, level }))
				appended = append_plain_requests($ranges, $requests, $styles, at, body, label)?
				$ranges = appended.ranges
				$requests = appended.requests
				$styles = appended.styles
			}
		}
		$block_index = $block_index + 1
	}
	if $requests.len() != occurrence_count {
		return Err(OccurrenceCoverage({ actual: $requests.len(), expected: occurrence_count }))
	}
	Ok(KernelFacadeShape.Preparation.{ block_runs: $block_runs, options: batch_options, ranges: $ranges, requests: $requests, styles: $styles })
}

RequestBuffers : { ranges : List(KernelFacadeShape.RequestRange), requests : List(KernelShape.SimpleRequest), styles : List(KernelFacadeShape.RunStyle) }

RangedContext : { authoring : Document.NormalizedAuthoring, block : U64, face_check : FaceCheck, language : Semantics.Language, sources : List(KernelFacadeSources.Source), store : Semantics.Store, theme : Theme }

## A plain block in a ranged document: its optional generated label and its
## body, each covering its whole source in the document language.
append_plain_requests : List(KernelFacadeShape.RequestRange), List(KernelShape.SimpleRequest), List(KernelFacadeShape.RunStyle), RangedContext, Semantics.OccurrenceId, [Label(Semantics.OccurrenceId), NoLabel] -> Try(RequestBuffers, KernelFacadeShape.Error)
append_plain_requests = |ranges, requests, styles, at, body, label| {
	block = list_at(at.authoring.blocks, at.block)
	body_style = match block.kind {
		Figure(index) => figure_style(list_at(at.authoring.figures, index), at.theme, at.block)?
		_ => style_for(block.kind, at.theme)
	}
	if at.face_check == RequireBuiltInFace and body_style.font.index() != 0 {
		return Err(UnsupportedThemeFace({ block: at.block, face: body_style.font.index() }))
	}
	var $ranges = ranges
	var $requests = requests
	var $styles = styles
	match label {
		NoLabel => {}
		Label(occurrence_id) => {
			label_style = Theme.body_style(at.theme)
			if at.face_check == RequireBuiltInFace and label_style.font.index() != 0 {
				return Err(UnsupportedThemeFace({ block: at.block, face: label_style.font.index() }))
			}
			occurrence = whole_occurrence(at, occurrence_id)?
			if !generated_label_evidence_valid(occurrence.value, at.store.text_properties, at.sources) {
				return Err(GeneratedLabelEvidenceInvalid({ block: at.block, occurrence: occurrence_id.index() }))
			}
			$requests = $requests.append({ occurrence: occurrence_id, size: label_style.size, source: occurrence.source })
			$styles = $styles.append({ color: label_style.color, leading: label_style.leading })
			$ranges = $ranges.append(whole_source_range(at.sources, occurrence.source, at.language))
		}
	}
	occurrence = whole_occurrence(at, body)?
	$requests = $requests.append({ occurrence: body, size: body_style.size, source: occurrence.source })
	$styles = $styles.append({ color: body_style.color, leading: body_style.leading })
	$ranges = $ranges.append(whole_source_range(at.sources, occurrence.source, at.language))
	Ok({ ranges: $ranges, requests: $requests, styles: $styles })
}

## The generated label request of a rich list-item paragraph, covering its
## whole label source in the document language, exactly as a plain block's.
append_label_request : List(KernelFacadeShape.RequestRange), List(KernelShape.SimpleRequest), List(KernelFacadeShape.RunStyle), RangedContext, [Label(Semantics.OccurrenceId), NoLabel] -> Try(RequestBuffers, KernelFacadeShape.Error)
append_label_request = |ranges, requests, styles, at, label| match label {
	NoLabel => Ok({ ranges, requests, styles })
	Label(occurrence_id) => {
		label_style = Theme.body_style(at.theme)
		if at.face_check == RequireBuiltInFace and label_style.font.index() != 0 {
			return Err(UnsupportedThemeFace({ block: at.block, face: label_style.font.index() }))
		}
		occurrence = whole_occurrence(at, occurrence_id)?
		if !generated_label_evidence_valid(occurrence.value, at.store.text_properties, at.sources) {
			return Err(GeneratedLabelEvidenceInvalid({ block: at.block, occurrence: occurrence_id.index() }))
		}
		Ok({
			ranges: ranges.append(whole_source_range(at.sources, occurrence.source, at.language)),
			requests: requests.append({ occurrence: occurrence_id, size: label_style.size, source: occurrence.source }),
			styles: styles.append({ color: label_style.color, leading: label_style.leading }),
		})
	}
}

## A whole-source occurrence of a plain block, in the document language.
whole_occurrence : RangedContext, Semantics.OccurrenceId -> Try({ source : Semantics.TextSourceId, value : Semantics.ContentOccurrence }, KernelFacadeShape.Error)
whole_occurrence = |at, occurrence_id| {
	occurrence_index = occurrence_id.index()
	if occurrence_index >= at.store.occurrences.len() {
		return Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
	}
	occurrence = list_at(at.store.occurrences, occurrence_index)
	if occurrence.language != at.language {
		return Err(LanguageMismatch({ occurrence: occurrence_index }))
	}
	match occurrence.source {
		Text(id, UnicodeRange(_)) => if id.index() < at.sources.len() Ok({ source: id, value: occurrence }) else Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
		_ => Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
	}
}

## One request per text leaf of a rich paragraph, in logical order: its
## occurrence's exact cluster range of the shared source, its language, its
## origin, and the paragraph style with the innermost themed inline color.
## The buffers move through this helper so they keep their unique in-place
## ownership in the caller's block loop. Every inline paints in the
## paragraph's face, size, and leading.
append_rich_requests : List(KernelFacadeShape.RequestRange), List(KernelShape.SimpleRequest), List(KernelFacadeShape.RunStyle), RangedContext, Semantics.Range, Document.NormalizedRich -> Try(RequestBuffers, KernelFacadeShape.Error)
append_rich_requests = |ranges, requests, styles, at, occurrences, rich| {
	body = Theme.body_style(at.theme)
	if at.face_check == RequireBuiltInFace and body.font.index() != 0 {
		return Err(UnsupportedThemeFace({ block: at.block, face: body.font.index() }))
	}
	paragraph_color = header_cell_color(at.authoring, at.block, at.theme, body.color)
	var $ranges = ranges
	var $requests = requests
	var $styles = styles
	var $cluster = 0
	var $script_run = 0
	var $source = U64.highest
	var $inline = rich.inlines
	while $inline < rich.inlines + rich.length {
		record = list_at(at.authoring.inlines, $inline)
		match record.kind {
			Text(_) => {
				occurrence_index = occurrences.start() + record.first_leaf
				if occurrence_index >= at.store.occurrences.len() {
					return Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
				}
				occurrence = list_at(at.store.occurrences, occurrence_index)
				located = match occurrence.source {
					Text(id, UnicodeRange(range)) => if id.index() < at.sources.len() {
						{ id, range }
					} else {
						return Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
					}
					_ => return Err(InvalidOccurrence({ block: at.block, occurrence: occurrence_index }))
				}
				analysis = list_at(at.sources, located.id.index()).analysis

				## Each explicit-line-break segment is its own source; the
				## forward cursors restart at its origin.
				if located.id.index() != $source {
					$source = located.id.index()
					$cluster = 0
					$script_run = 0
				}
				scalar_start = located.range.scalars.start()
				scalar_end = scalar_start + located.range.scalars.length()

				## The convenience path accepts only the declared scripts; a
				## span in another script rejects here, naming the authored
				## inline, before any shaping.
				$script_run = inline_script(analysis.script_runs, $script_run, scalar_start, scalar_end, at.face_check, at.block, $inline)?
				cluster_start = cluster_at(analysis.graphemes, $cluster, scalar_start, at.block, $inline)?
				cluster_end = cluster_at(analysis.graphemes, cluster_start, scalar_end, at.block, $inline)?
				$cluster = cluster_end
				$requests = $requests.append({ occurrence: Semantics.OccurrenceId.from_index(occurrence_index), size: body.size, source: located.id })
				$styles = $styles.append({ color: inline_color(at.authoring.inlines, record.parent, at.theme, paragraph_color), leading: body.leading })
				$ranges = $ranges.append({
					clusters: Semantics.Range.from_start_and_length(cluster_start, cluster_end - cluster_start),
					language: occurrence.language,
					origin: { byte: located.range.utf8_bytes.start(), scalar: scalar_start },
				})
			}
			_ => {}
		}
		$inline = $inline + 1
	}
	Ok({ ranges: $ranges, requests: $requests, styles: $styles })
}

## Header-cell text paints in the theme's table header color when one is
## set; every other rich block paints in its paragraph color.
header_cell_color : Document.NormalizedAuthoring, U64, Theme, Color.SourceValue -> Color.SourceValue
header_cell_color = |authoring, block, theme, paragraph_color| {
	parent = list_at(authoring.blocks, block).parent
	in_row = parent != 0 and (match list_at(authoring.groups, parent - 1).kind {
		TableRow(_) => True
		_ => False
	})
	if !in_row {
		return paragraph_color
	}
	match Theme.table_style(theme).header_color {
		Inherited => paragraph_color
		Themed(color) => {
			var $low = 0
			var $high = authoring.cells.len()
			while $low < $high {
				middle = $low + ($high - $low) // 2
				if list_at(authoring.cells, middle).block < block {
					$low = middle + 1
				} else {
					$high = middle
				}
			}
			match list_at(authoring.cells, $low).kind {
				HeaderCell(_) => color
				DataCell => paragraph_color
			}
		}
	}
}

has_rich_block : List(KernelFacadeSemantics.BlockOwnership) -> Bool
has_rich_block = |owners| {
	var $index = 0
	var $found = False
	while !$found and $index < owners.len() {
		$found = match list_at(owners, $index) {
			RichTextBlock(_) => True
			_ => False
		}
		$index = $index + 1
	}
	$found
}

whole_source_range : List(KernelFacadeSources.Source), Semantics.TextSourceId, Semantics.Language -> KernelFacadeShape.RequestRange
whole_source_range = |sources, source, language| {
	clusters: Semantics.Range.from_start_and_length(0, list_at(sources, source.index()).analysis.graphemes.len()),
	language,
	origin: { byte: 0, scalar: 0 },
}

## The grapheme-cluster index that starts at scalar `scalar`, searching
## forward from `from` (or the cluster count at the source end). A leaf
## boundary inside a multi-scalar cluster cannot be shaped as two runs.
cluster_at : List(KernelUnicode.UnicodeRange), U64, U64, U64, U64 -> Try(U64, KernelFacadeShape.Error)
cluster_at = |graphemes, from, scalar, block, inline| {
	var $cursor = from
	while $cursor < graphemes.len() and list_at(graphemes, $cursor).scalar_start < scalar {
		$cursor = $cursor + 1
	}
	if $cursor < graphemes.len() {
		if list_at(graphemes, $cursor).scalar_start == scalar Ok($cursor) else Err(InlineClusterBoundary({ block, inline }))
	} else if $cursor > 0 and list_at(graphemes, $cursor - 1).scalar_end == scalar {
		Ok($cursor)
	} else {
		Err(InlineClusterBoundary({ block, inline }))
	}
}

## Every itemized script run a leaf overlaps must be one the path shapes:
## Latin (with Common and Inherited) on the single-face path, and Latin or
## Han on the ordered path, whose Common-run rule applies later. Returns
## the advanced run cursor; leaves arrive in scalar order.
inline_script : List(KernelUnicode.ScriptRun), U64, U64, U64, FaceCheck, U64, U64 -> Try(U64, KernelFacadeShape.Error)
inline_script = |runs, from, scalar_start, scalar_end, face_check, block, inline| {
	var $cursor = from
	while $cursor < runs.len() and list_at(runs, $cursor).range.scalar_end <= scalar_start {
		$cursor = $cursor + 1
	}
	var $probe = $cursor
	while $probe < runs.len() and list_at(runs, $probe).range.scalar_start < scalar_end {
		script = list_at(runs, $probe).script
		accepted = script == "Latn" or script == "Zyyy" or script == "Zinh" or (face_check == PolicySelectsFaces and script == "Hani")
		if !accepted {
			return Err(UnsupportedInlineScript({ block, inline, script }))
		}
		$probe = $probe + 1
	}
	Ok($cursor)
}

## The innermost themed inline role around a leaf decides its color; with
## no themed role the leaf paints like its paragraph.
inline_color : List(Document.NormalizedInline), U64, Theme, Color.SourceValue -> Color.SourceValue
inline_color = |inlines, parent, theme, paragraph_color| {
	var $cursor = parent
	var $color = Unresolved
	while $cursor != 0 and $color == Unresolved {
		record = list_at(inlines, $cursor - 1)
		role = match record.kind {
			Code => Role(Code)
			Emphasis => Role(Emphasis)
			Quote => Role(Quote)
			Strong => Role(Strong)
			_ => NoRole
		}
		match role {
			Role(value) => match Theme.inline_color(theme, value) {
				Themed(color) => {
					$color = Resolved(color)
				}
				Inherited => {}
			}
			NoRole => {}
		}
		$cursor = record.parent
	}
	match $color {
		Resolved(color) => color
		Unresolved => paragraph_color
	}
}

## One selected physical segment of a source: a contiguous grapheme-cluster
## range owned by one dense output font and one itemized script.
SelectedSegment : { clusters : Semantics.Range, font : U64, script : Font.Script }

build_ordered_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, { policy : Font.PolicyId, registry : Font.Registry }, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_ordered_plan = |authoring, owners, store, source_store, artifact_count, ordered, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store, artifact_count, limits.max_requests, theme, PolicySelectsFaces)?
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

	## Expand each logical request into its physical selected runs in the
	## exact order the preparation assigned requests.
	var $expanded = { origins: [], requests: [], selected: [], styles: [] }
	var $block_runs = List.repeat(ArtifactBlock(0), preparation.block_runs.len())
	var $block_index = 0
	while $block_index < preparation.block_runs.len() {
		match list_at(preparation.block_runs, $block_index) {
			ArtifactBlock(artifact) => {
				$block_runs = list_set($block_runs, $block_index, ArtifactBlock(artifact))
			}
			TextBlock({ body, label, level }) => {
				expanded_label = match label {
					NoLabel => NoLabel
					Label(logical) => {
						expanded = expand_logical(logical, preparation, $segments_per_source, $expanded, limits.max_requests)?
						$expanded = expanded.buffers
						Label(expanded.run)
					}
				}
				expanded_body = expand_logical(body, preparation, $segments_per_source, $expanded, limits.max_requests)?
				$expanded = expanded_body.buffers
				$block_runs = list_set($block_runs, $block_index, TextBlock({ body: expanded_body.run, label: expanded_label, level }))
			}
		}
		$block_index = $block_index + 1
	}
	physical_requests = $expanded.requests
	physical_styles = $expanded.styles
	physical_origins = if preparation.ranges.is_empty() WholeSources else Origins($expanded.origins)

	shape = match KernelShape.shape_selected_batch($fonts, source_store, { direction: LeftToRight, language: batch_language, writing_mode: Horizontal }, $expanded.selected, limits.shape) {
		Err(_) => return Err(ShapeFailure)
		Ok(value) => value
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: $block_runs,
			origins: physical_origins,
			requests: physical_requests,
			selection: OrderedFaces({ faces: $used_faces, fonts: $fonts, work: $selection_work }),
			shape,
			styles: physical_styles,
			work: {
				font_bytes: total_font_bytes($fonts),
				font_tables: total_font_tables($fonts),
				glyphs: shape.work.glyph_visits,
				metric_reads: shape.work.metric_reads,
				requests: physical_requests.len(),
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

## The convenience path's declared script set, plus runs whose script stays
## Common or Inherited after itemization (digits, punctuation, and spaces
## beside another script). Each cluster of such a run takes the first face in
## policy order that covers it; the convenience shaper applies no
## script-specific shaping, so no further fact is needed. Everything else is
## an explicit typed rejection rather than an implicit fallback face search.
declared_script : Str -> Bool
declared_script = |alias| alias == "Latn" or alias == "Hani" or alias == "Zyyy" or alias == "Zinh"

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

ExpandedBuffers : { origins : List(KernelFacadeShape.Origin), requests : List(KernelShape.SimpleRequest), selected : List(KernelShape.SelectedBatchRequest), styles : List(KernelFacadeShape.RunStyle) }

## Split one logical request range into its physical runs: each request's
## cluster range (its whole source, or a rich occurrence's sub-range)
## intersected with the source's selected face/script segments. Requests of
## one logical run share one source in cluster order (or, across explicit
## line breaks, one source per segment in order), so one forward segment
## cursor per source makes the expansion linear. The segment split is the per-source
## selection fact, never recomputed per occurrence.
expand_logical : KernelFacadeShape.LogicalRun, KernelFacadeShape.Preparation, List(List(SelectedSegment)), ExpandedBuffers, U64 -> Try({ buffers : ExpandedBuffers, run : KernelFacadeShape.LogicalRun }, KernelFacadeShape.Error)
expand_logical = |logical, preparation, segments_per_source, buffers, max_requests| {
	first = logical.physical.start()
	count = logical.physical.length()
	if count == 0 or first + count > preparation.requests.len() {
		return Err(OccurrenceCoverage({ actual: first + count, expected: preparation.requests.len() }))
	}
	ranged = !preparation.ranges.is_empty()
	physical_start = buffers.requests.len()
	var $selected = buffers.selected
	var $requests = buffers.requests
	var $styles = buffers.styles
	var $origins = buffers.origins
	var $cursor = 0
	var $cursor_source = U64.highest
	var $request_index = first
	while $request_index < first + count {
		request = list_at(preparation.requests, $request_index)
		style = list_at(preparation.styles, $request_index)
		source_index = request.source.index()

		## A logical run spans several sources only across explicit line
		## breaks; each source's segment cursor restarts at its origin.
		if source_index != $cursor_source {
			$cursor_source = source_index
			$cursor = 0
		}
		if source_index >= segments_per_source.len() {
			return Err(InvalidOccurrence({ block: 0, occurrence: $request_index }))
		}
		segments = list_at(segments_per_source, source_index)
		if segments.is_empty() {
			return Err(OccurrenceCoverage({ actual: 0, expected: 1 }))
		}
		range = if ranged list_at(preparation.ranges, $request_index) else { clusters: Semantics.Range.from_start_and_length(0, segment_end(list_at(segments, segments.len() - 1))), language: preparation.options.language, origin: { byte: 0, scalar: 0 } }
		range_start = range.clusters.start()
		range_end = range_start + range.clusters.length()
		while $cursor < segments.len() and segment_end(list_at(segments, $cursor)) <= range_start {
			$cursor = $cursor + 1
		}
		var $segment = $cursor
		while $segment < segments.len() and list_at(segments, $segment).clusters.start() < range_end {
			segment = list_at(segments, $segment)
			overlap_start = U64.max(segment.clusters.start(), range_start)
			overlap_end = U64.min(segment_end(segment), range_end)
			if $requests.len() + 1 > max_requests {
				return Err(LimitExceeded({ attempted: $requests.len() + 1, dimension: Requests, limit: max_requests }))
			}
			$selected = $selected.append({
				clusters: Semantics.Range.from_start_and_length(overlap_start, overlap_end - overlap_start),
				instance: Font.InstanceId.from_index(segment.font),
				language: range.language,
				occurrence: request.occurrence,
				script: segment.script,
				size: request.size,
				source: request.source,
			})
			$requests = $requests.append(request)
			$styles = $styles.append(style)
			if ranged {
				$origins = $origins.append(range.origin)
			}
			$segment = $segment + 1
		}
		$request_index = $request_index + 1
	}
	Ok({
		buffers: { origins: $origins, requests: $requests, selected: $selected, styles: $styles },
		run: { physical: Semantics.Range.from_start_and_length(physical_start, $requests.len() - physical_start) },
	})
}

segment_end : SelectedSegment -> U64
segment_end = |segment| segment.clusters.start() + segment.clusters.length()

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
## coupled before shaping so later text lowering receives an explicit fact:
## the property names the occurrence's whole range and presents exactly its
## non-empty generated source text (a bullet or a list number).
generated_label_evidence_valid : Semantics.ContentOccurrence, List(Semantics.TextProperty), List(KernelFacadeSources.Source) -> Bool
generated_label_evidence_valid = |occurrence, properties, sources| {
	match occurrence.source {
		Text(source_id, UnicodeRange(source_range)) => {
			property_range = occurrence.text_properties
			if property_range.length() != 1 or property_range.start() >= properties.len() or source_id.index() >= sources.len() {
				False
			} else {
				match list_at(properties, property_range.start()) {
					SourceToPresentation({ kind: GeneratedText, presentation, source }) => !presentation.is_empty() and presentation == list_at(sources, source_id.index()).unicode and text_ranges_equal(source, source_range)
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
	Bullet(_) | Paragraph | DestinationParagraph(_) | Link(_) | InternalLink(_) | Figure(_) | PageArtifact(_) | RichParagraph(_) => Theme.body_style(theme)
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
