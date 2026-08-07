import Color
import Document
import Font
import KernelFacadeSemantics
import KernelFacadeSources
import KernelFont
import KernelShape
import Layout
import Semantics
import Text
import Theme

KernelFacadeShape :: [].{
	Dimension : [Requests]
	Error : [
		ArtifactTextPending({ artifacts : U64 }),
		InvalidOccurrence({ block : U64, occurrence : U64 }),
		LanguageMismatch({ occurrence : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		OccurrenceCoverage({ actual : U64, expected : U64 }),
		ShapeFailure,
		UnsupportedThemeFace({ block : U64, face : U64 }),
	]
	Limits :: { max_requests : U64, shape : KernelShape.Limits }.{
		make : { max_requests : U64, shape : KernelShape.Limits } -> Limits
		make = |limits| Limits.(limits)
	}
	BlockRuns : [ArtifactBlock(U64), TextBlock({ body : Text.RunId, label : [Label(Text.RunId), NoLabel] })]
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
	Preparation :: { block_runs : List(BlockRuns), options : KernelShape.BatchOptions, requests : List(KernelShape.SimpleRequest), styles : List(RunStyle) }.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, U64, U64, U64, Theme -> Try(Preparation, Error)
		build = |authoring, owners, store, source_count, artifact_count, max_requests, theme| prepare_plan(authoring, owners, store, source_count, artifact_count, max_requests, theme)

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
		shape : KernelShape.Batch,
		styles : List(RunStyle),
		work : Work,
	}.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, KernelFont.Inspection, Theme, Limits -> Try(Plan, Error)
		build = |authoring, owners, store, sources, artifact_count, font, theme, limits| build_plan(authoring, owners, store, sources, artifact_count, font, theme, limits)

		block_runs : Plan -> List(BlockRuns)
		block_runs = |plan| plan.block_runs

		shape : Plan -> KernelShape.Batch
		shape = |plan| plan.shape

		styles : Plan -> List(RunStyle)
		styles = |plan| plan.styles

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, KernelFont.Inspection, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_plan = |authoring, owners, store, source_store, artifact_count, font, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store.len(), artifact_count, limits.max_requests, theme)?
	shape = match KernelShape.shape_simple_batch(font, source_store, preparation.options, preparation.requests, limits.shape) {
		Err(_) => return Err(ShapeFailure)
		Ok(value) => value
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: preparation.block_runs,
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

prepare_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, U64, U64, U64, Theme -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_plan = |authoring, owners, store, source_count, artifact_count, max_requests, theme| {
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
				body_style = style_for(block.kind, theme)
				if body_style.font.index() != 0 {
					return Err(UnsupportedThemeFace({ block: $block_index, face: body_style.font.index() }))
				}
				label_run = match label {
					NoLabel => NoLabel
					Label(occurrence_id) => {
						label_style = Theme.body_style(theme)
						if label_style.font.index() != 0 {
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
						run = Text.RunId.from_index($request_index)
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
				body_run = Text.RunId.from_index($request_index)
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

style_for : Document.NormalizedBlockKind, Theme -> Theme.TextStyle
style_for = |kind, theme| match kind {
	Title => Theme.title_style(theme)
	Heading(_) => Theme.heading_style(theme)
	Bullet(_) | Paragraph => Theme.body_style(theme)
	PageArtifact(_) => Theme.body_style(theme)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade shaping index escaped"
	}
	Ok(value) => value
}
