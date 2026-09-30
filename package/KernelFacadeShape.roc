import Color
import Document
import Font
import KernelFacadeSemantics
import KernelFacadeSources
import KernelFont
import KernelUnicode
import KernelShape
import Layout
import Scene
import Semantics
import Text
import Theme
import unicode.Scalar

KernelFacadeShape :: [].{
	Dimension : [Requests]
	Error : [
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

		## Text the shaping path cannot shape, located at its block and,
		## in a rich paragraph, its text inline: a script outside the
		## path's set, a multi-scalar cluster, or a scalar no selected face
		## covers. `scalars` is the failing cluster, relative to the text.
		UnsupportedText({ block : U64, inline : [AtInline(U64), NoInline], reason : [Cluster, Coverage(U32), Script(Str)], scalars : Semantics.Range }),
	]

	## The facade's resolved font selection. `Single` is the existing exact
	## one-face path; `Ordered` carries the caller registry and the
	## Theme-selected finite policy for per-cluster coverage selection.
	##
	## `Styled` is the style-face path with inline role faces: candidate 0
	## is the body face and `roles` names each role's candidate face.
	FontSelection : [Ordered({ policy : Font.PolicyId, registry : Font.Registry }), Single(KernelFont.Inspection), Styled(StyledFaces)]

	## The candidate faces of the style-face path with inline role faces:
	## `faces` and `fonts` are parallel, candidate 0 is the body face, and a
	## role's `Candidate(k)` names its face.
	StyledFaces : { faces : List(Font.FaceId), fonts : List(KernelFont.Inspection), roles : { code : RoleFace, emphasis : RoleFace, quote : RoleFace, strong : RoleFace } }
	RoleFace : [Candidate(U64), Inherited]
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

	## A code span keeps its words whole. UAX #14 allows a break after a
	## hyphen before a letter, so `--lumen-indigo` or `kubectl-rollout`
	## would otherwise break inside the identifier. Each word of a code
	## leaf (a maximal run of scalars other than U+0020) that has a
	## break opportunity inside it is one hold: a scalar range of its
	## source, named with the first physical run of its leaf so a caller
	## can find the line request of its segment. Line layout withholds the
	## tailorable opportunities inside a hold; breaks after the spaces
	## between words stay, so a long command still wraps between words.
	CodeHold : { run : U64, scalars : Semantics.Range }

	## The dense output font each inline role's face has for drawing labels.
	LabelInstances : { code : U64, emphasis : U64, quote : U64, strong : U64 }

	## `ContentlessCell` is a table cell with no content: it has no run, so
	## line layout gives it no line and pagination sizes its row from its
	## other cells.
	BlockRuns : [ContentlessCell, TextBlock({ body : LogicalRun, label : [Label(LogicalRun), NoLabel], level : U64 })]
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

	## One ordered-policy selection of a whole source outside the body text
	## (a page-furniture line): its cluster segments in order, each with its
	## selected face and itemized script, under the same declared-script,
	## coverage, and shaping-provision rules as body text.
	select_source : Font.Registry, Font.PolicyId, KernelFacadeSources.Source, U64, Semantics.Language -> Try(List({ clusters : Semantics.Range, face : Font.FaceId, script : Font.Script }), Error)
	select_source = |registry, policy, source, index, language| select_source_segments(registry, policy, source, index, language)

	## `ranges` is empty unless the document has a rich paragraph; then it
	## holds one entry per request, in request order.
	Preparation :: { block_runs : List(BlockRuns), options : KernelShape.BatchOptions, ranges : List(RequestRange), requests : List(KernelShape.SimpleRequest), styles : List(RunStyle) }.{
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, Theme -> Try(Preparation, Error)
		build = |authoring, owners, store, sources, max_requests, theme| prepare_plan(authoring, owners, store, sources, max_requests, theme, RequireFace(Theme.body_font(theme).index()))

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
		build : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), KernelFont.Inspection, Theme, Limits -> Try(Plan, Error)
		build = |authoring, owners, store, sources, font, theme, limits| build_plan(authoring, owners, store, sources, font, theme, limits)

		## The ordered multi-face arm: policy resolution, once-per-unique-source
		## coverage planning, physical-run splitting, and selected shaping. The
		## single-face `build` path above is untouched by this entry point.
		build_ordered : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), { policy : Font.PolicyId, registry : Font.Registry }, Theme, Limits -> Try(Plan, Error)
		build_ordered = |authoring, owners, store, sources, ordered, theme, limits| build_ordered_plan(authoring, owners, store, sources, ordered, theme, limits)

		## The style-face arm with inline role faces: each text run shapes in
		## the face of its innermost role with a face, or in the body face,
		## and only the faces some run uses become output fonts, body first.
		build_styled : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), StyledFaces, Theme, Limits -> Try(Plan, Error)
		build_styled = |authoring, owners, store, sources, styled, theme, limits| build_styled_plan(authoring, owners, store, sources, styled, theme, limits)

		block_runs : Plan -> List(BlockRuns)
		block_runs = |plan| plan.block_runs

		origins : Plan -> Origins
		origins = |plan| plan.origins

		## The dense output font of each inline role's face for drawing
		## labels under style faces: the body font (0) for a role without a
		## face. `styled` is the style faces the plan was built with.
		label_instances : Plan, StyledFaces -> LabelInstances
		label_instances = |plan, styled| {
			selected = match plan.selection {
				OrderedFaces(ordered) => ordered.faces
				SingleFace => []
			}
			dense = |role| match role {
				Inherited => 0
				Candidate(candidate) => {
					face = list_at(styled.faces, candidate).index()
					var $index = 0
					var $found = 0
					while $index < selected.len() {
						if list_at(selected, $index).index() == face {
							$found = $index
						}
						$index = $index + 1
					}
					$found
				}
			}
			{ code: dense(styled.roles.code), emphasis: dense(styled.roles.emphasis), quote: dense(styled.roles.quote), strong: dense(styled.roles.strong) }
		}

		## The code holds of block `block`'s body (see `CodeHold`).
		code_holds : Plan, Document.NormalizedAuthoring, U64, List(KernelFacadeSources.Source) -> List(CodeHold)
		code_holds = |plan, authoring, block, sources| block_code_holds(plan, authoring, block, sources)

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

## The placeholder every block's runs start from; each block overwrites it.
unset_block_runs : KernelFacadeShape.BlockRuns
unset_block_runs = TextBlock({ body: { physical: Semantics.Range.from_start_and_length(0, 0) }, label: NoLabel, level: 0 })

logical_run_single : Text.RunId -> KernelFacadeShape.LogicalRun
logical_run_single = |run| { physical: Semantics.Range.from_start_and_length(run.index(), 1) }

build_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), KernelFont.Inspection, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_plan = |authoring, owners, store, source_store, font, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store, limits.max_requests, theme, RequireFace(Theme.body_font(theme).index()))?

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
		Err(_) => return Err(
			match locate_text_failure(authoring, preparation, store, source_store, [single_face_rules(font)], |_| 0) {
				Located(located) => located
				NotLocated => ShapeFailure
			},
		)
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

build_styled_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), KernelFacadeShape.StyledFaces, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_styled_plan = |authoring, owners, store, source_store, styled, theme, limits| {
	validate_style_faces(authoring, theme, styled)?
	preparation = prepare_plan(authoring, owners, store, source_store, limits.max_requests, theme, CandidateFaces)?
	candidates = request_candidates(authoring, preparation, styled, theme)

	## Dense output fonts: the body face, then each role face some run or
	## drawing label uses, in candidate order.
	var $used = List.repeat(Bool.False, styled.fonts.len())
	$used = list_set($used, 0, Bool.True)
	for candidate in candidates {
		$used = list_set($used, candidate, Bool.True)
	}
	for candidate in label_candidates(authoring, styled) {
		$used = list_set($used, candidate, Bool.True)
	}
	var $dense = List.repeat(0, styled.fonts.len())
	var $faces = []
	var $fonts = []
	var $candidate = 0
	while $candidate < styled.fonts.len() {
		if list_at($used, $candidate) {
			$dense = list_set($dense, $candidate, $fonts.len())
			$faces = $faces.append(list_at(styled.faces, $candidate))
			$fonts = $fonts.append(list_at(styled.fonts, $candidate))
		}
		$candidate = $candidate + 1
	}
	latin = Font.Script.from_iso15924("Latn")
	var $selected = List.with_capacity(preparation.requests.len())
	var $index = 0
	while $index < preparation.requests.len() {
		request = list_at(preparation.requests, $index)
		range = if preparation.ranges.is_empty() whole_source_range(source_store, request.source, preparation.options.language) else list_at(preparation.ranges, $index)
		instance = Font.InstanceId.from_index(list_at($dense, list_at(candidates, $index)))
		$selected = $selected.append({ clusters: range.clusters, instance, language: range.language, occurrence: request.occurrence, script: latin, size: request.size, source: request.source })
		$index = $index + 1
	}
	shape = match KernelShape.shape_selected_batch($fonts, source_store, { direction: LeftToRight, language: preparation.options.language, writing_mode: Horizontal }, $selected, limits.shape) {
		Ok(value) => value
		Err(_) => {
			rules = styled.fonts.map(|font| single_face_rules(font))
			return Err(
				match locate_text_failure(authoring, preparation, store, source_store, rules, |request| list_at(candidates, request)) {
					Located(located) => located
					NotLocated => ShapeFailure
				},
			)
		}
	}
	Ok(
		KernelFacadeShape.Plan.{
			block_runs: preparation.block_runs,
			origins: request_origins(preparation.ranges),
			requests: preparation.requests,
			selection: OrderedFaces({ faces: $faces, fonts: $fonts, work: { coverage_span_visits: 0, face_visits: 0, grapheme_visits: 0, planned_sources: 0, selection_ranges: 0 } }),
			shape,
			styles: preparation.styles,
			work: {
				font_bytes: total_font_bytes($fonts),
				font_tables: total_font_tables($fonts),
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

## The candidate face of every request: the face of the innermost inline
## role with a face around a rich text leaf, else the body face (candidate
## 0). Labels and plain blocks shape in the body face.
request_candidates : Document.NormalizedAuthoring, KernelFacadeShape.Preparation, KernelFacadeShape.StyledFaces, Theme -> List(U64)
request_candidates = |authoring, preparation, styled, theme| {
	var $candidates = List.repeat(0, preparation.requests.len())
	var $block = 0
	while $block < preparation.block_runs.len() {
		match (list_at(authoring.blocks, $block).kind, list_at(preparation.block_runs, $block)) {
			(RichParagraph(_), _) | (_, ContentlessCell) => {}
			(kind, TextBlock({ body, label: _, level: _ })) => {
				## A plain block's body shapes in its style's face (a title or
				## heading face); its generated label stays in the body face.
				face = style_for(kind, theme).font
				if face.index() != styled_body_face(styled) {
					$candidates = list_set($candidates, body.physical.start(), candidate_of(styled, face))
				}
			}
		}
		match (list_at(authoring.blocks, $block).kind, list_at(preparation.block_runs, $block)) {
			(RichParagraph(paragraph), TextBlock({ body, label: _, level: _ })) => {
				rich = list_at(authoring.rich_paragraphs, paragraph)
				var $inline = rich.inlines
				while $inline < rich.inlines + rich.length {
					record = list_at(authoring.inlines, $inline)
					match record.kind {
						Text(_) => {
							request = body.physical.start() + record.first_leaf
							$candidates = list_set($candidates, request, role_candidate(authoring.inlines, record.parent, styled))
						}
						_ => {}
					}
					$inline = $inline + 1
				}
			}
			_ => {}
		}
		$block = $block + 1
	}
	$candidates
}

## The candidate faces drawing labels are set in, besides the body face,
## in drawing order. A document whose labels all use the body face scans
## its drawings and allocates nothing.
label_candidates : Document.NormalizedAuthoring, KernelFacadeShape.StyledFaces -> List(U64)
label_candidates = |authoring, styled| {
	var $candidates = []
	for figure in authoring.figures {
		$candidates = append_label_candidates($candidates, figure.drawing, styled)
	}
	for custom in authoring.customs {
		$candidates = append_label_candidates($candidates, custom.panel, styled)
	}
	$candidates
}

append_label_candidates : List(U64), Document.ValidatedDrawing, KernelFacadeShape.StyledFaces -> List(U64)
append_label_candidates = |candidates, drawing, styled| match drawing {
	InvalidDrawing(_) => candidates
	ValidDrawing(value) => {
		var $candidates = candidates
		for command in value.commands {
			match command {
				FlowText(boxed) => match label_role_face(Box.unbox(boxed).face, styled) {
					Candidate(candidate) => {
						$candidates = $candidates.append(candidate)
					}
					Inherited => {}
				}
				_ => {}
			}
		}
		$candidates
	}
}

## A label face's candidate: its role's face, or none for the body face or
## a role the theme gives no face.
label_role_face : Scene.LabelFace, KernelFacadeShape.StyledFaces -> KernelFacadeShape.RoleFace
label_role_face = |face, styled| match face {
	BodyFace => Inherited
	RoleFace(Code) => styled.roles.code
	RoleFace(Emphasis) => styled.roles.emphasis
	RoleFace(Quote) => styled.roles.quote
	RoleFace(Strong) => styled.roles.strong
}

styled_body_face : KernelFacadeShape.StyledFaces -> U64
styled_body_face = |styled| list_at(styled.faces, 0).index()

## The candidate of a style face that `validate_style_faces` accepted.
candidate_of : KernelFacadeShape.StyledFaces, Font.FaceId -> U64
candidate_of = |styled, face| {
	var $index = 0
	while $index < styled.faces.len() {
		if list_at(styled.faces, $index).index() == face.index() {
			return $index
		}
		$index = $index + 1
	}
	crash "validated style face escaped its candidates"
}

## Every title and heading style face some block uses must be a candidate
## face; the facade builds the candidates from the theme, so this is the
## stage precondition that no block silently shapes in another face.
validate_style_faces : Document.NormalizedAuthoring, Theme, KernelFacadeShape.StyledFaces -> Try({}, KernelFacadeShape.Error)
validate_style_faces = |authoring, theme, styled| {
	var $block = 0
	while $block < authoring.blocks.len() {
		face = style_for(list_at(authoring.blocks, $block).kind, theme).font
		if !styled.faces.any(|known| known.index() == face.index()) {
			return Err(UnsupportedThemeFace({ block: $block, face: face.index() }))
		}
		$block = $block + 1
	}
	Ok({})
}

role_candidate : List(Document.NormalizedInline), U64, KernelFacadeShape.StyledFaces -> U64
role_candidate = |inlines, parent, styled| {
	var $cursor = parent
	while $cursor != 0 {
		record = list_at(inlines, $cursor - 1)
		face = match record.kind {
			Code => styled.roles.code
			Emphasis => styled.roles.emphasis
			Quote => styled.roles.quote
			Strong => styled.roles.strong
			_ => Inherited
		}
		match face {
			Candidate(index) => return index
			Inherited => {}
		}
		$cursor = record.parent
	}
	0
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
## body face (`RequireFace` with the theme's body face index); the
## style-face path with several faces checks every style face against its
## candidates before preparation (`CandidateFaces`); the ordered-policy path
## resolves fonts per cluster instead, so style face identities are
## deliberately not consulted there.
FaceCheck : [CandidateFaces, PolicySelectsFaces, RequireFace(U64)]

## Whether a style's face breaks the single-face requirement.
face_rejected : FaceCheck, Theme.TextStyle -> Bool
face_rejected = |check, style| match check {
	RequireFace(face) => style.font.index() != face
	CandidateFaces | PolicySelectsFaces => Bool.False
}

## Request ranges exist only when a rich paragraph does. A document without
## one keeps the exact whole-source preparation and its buffers; a document
## with one prepares every request with its exact cluster range, language,
## and occurrence origin.
prepare_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), U64, Theme, FaceCheck -> Try(KernelFacadeShape.Preparation, KernelFacadeShape.Error)
prepare_plan = |authoring, owners, store, sources, max_requests, theme, face_check| {
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
	var $block_runs = List.repeat(unset_block_runs, authoring.blocks.len())
	var $request_index = 0
	var $block_index = 0
	while $block_index < authoring.blocks.len() {
		owner = list_at(owners, $block_index)
		match owner {
			ContentlessCell => {
				$block_runs = list_set($block_runs, $block_index, ContentlessCell)
			}
			RichTextBlock({ label: _, level: _, occurrences }) => return Err(InvalidOccurrence({ block: $block_index, occurrence: occurrences.start() }))
			TextBlock({ body, label, level }) => {
				body_style = block_style(authoring, $block_index, theme)
				if face_rejected(face_check, body_style) {
					return Err(UnsupportedThemeFace({ block: $block_index, face: body_style.font.index() }))
				}
				label_run = match label {
					NoLabel => NoLabel
					Label(occurrence_id) => {
						label_style = Theme.body_style(theme)
						if face_rejected(face_check, label_style) {
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
						$styles = $styles.append({ color: scoped_text_color(authoring, $block_index, theme, label_style.color), leading: label_style.leading })
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
	var $block_runs = List.repeat(unset_block_runs, authoring.blocks.len())
	var $block_index = 0
	while $block_index < authoring.blocks.len() {
		block = list_at(authoring.blocks, $block_index)
		first_request = $requests.len()
		at = { authoring, block: $block_index, face_check, language: batch_options.language, sources, store, theme }
		match list_at(owners, $block_index) {
			ContentlessCell => {
				$block_runs = list_set($block_runs, $block_index, ContentlessCell)
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
	body_style = block_style(at.authoring, at.block, at.theme)
	if face_rejected(at.face_check, body_style) {
		return Err(UnsupportedThemeFace({ block: at.block, face: body_style.font.index() }))
	}
	var $ranges = ranges
	var $requests = requests
	var $styles = styles
	match label {
		NoLabel => {}
		Label(occurrence_id) => {
			label_style = Theme.body_style(at.theme)
			if face_rejected(at.face_check, label_style) {
				return Err(UnsupportedThemeFace({ block: at.block, face: label_style.font.index() }))
			}
			occurrence = whole_occurrence(at, occurrence_id)?
			if !generated_label_evidence_valid(occurrence.value, at.store.text_properties, at.sources) {
				return Err(GeneratedLabelEvidenceInvalid({ block: at.block, occurrence: occurrence_id.index() }))
			}
			$requests = $requests.append({ occurrence: occurrence_id, size: label_style.size, source: occurrence.source })
			$styles = $styles.append({ color: scoped_text_color(at.authoring, at.block, at.theme, label_style.color), leading: label_style.leading })
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
		if face_rejected(at.face_check, label_style) {
			return Err(UnsupportedThemeFace({ block: at.block, face: label_style.font.index() }))
		}
		occurrence = whole_occurrence(at, occurrence_id)?
		if !generated_label_evidence_valid(occurrence.value, at.store.text_properties, at.sources) {
			return Err(GeneratedLabelEvidenceInvalid({ block: at.block, occurrence: occurrence_id.index() }))
		}
		Ok({
			ranges: ranges.append(whole_source_range(at.sources, occurrence.source, at.language)),
			requests: requests.append({ occurrence: occurrence_id, size: label_style.size, source: occurrence.source }),
			styles: styles.append({ color: scoped_text_color(at.authoring, at.block, at.theme, label_style.color), leading: label_style.leading }),
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
	if face_rejected(at.face_check, body) {
		return Err(UnsupportedThemeFace({ block: at.block, face: body.font.index() }))
	}
	paragraph_color = header_cell_color(at.authoring, at.block, at.theme, scoped_text_color(at.authoring, at.block, at.theme, body.color))
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
				$script_run = inline_script(analysis.script_runs, $script_run, scalar_start, scalar_end, at.block, $inline)?
				cluster_start = cluster_at(analysis.graphemes, $cluster, scalar_start, at.block, $inline)?
				cluster_end = cluster_at(analysis.graphemes, cluster_start, scalar_end, at.block, $inline)?
				$cluster = cluster_end
				$requests = $requests.append({ occurrence: Semantics.OccurrenceId.from_index(occurrence_index), size: inline_size(at.authoring.inlines, record.parent, at.theme, body.size), source: located.id })
				$styles = $styles.append({ color: inline_color(at.authoring, at.block, record.parent, at.theme, paragraph_color), leading: body.leading })
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

## Column header cells (scope `Column` or `Both`) paint in the theme's
## table header color and row header cells (scope `Row`) in its row header
## color, each when set; every other rich block paints in its paragraph
## color.
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
	style = Theme.table_style(theme)
	match (style.header_color, style.row_header_color) {
		(Inherited, Inherited) => paragraph_color
		(column_color, row_color) => {
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
			selected = match list_at(authoring.cells, $low).kind {
				HeaderCell(Row) => row_color
				HeaderCell(_) => column_color
				DataCell => Inherited
			}
			match selected {
				Themed(color) => color
				Inherited => paragraph_color
			}
		}
	}
}

## The code holds of one block, in run and scalar order. A block without
## a `Code` inline returns `[]` after one scan of its inline records and
## allocates nothing; a code leaf whose scalar range has no interior
## opportunity adds nothing, and only a leaf with one reads its bytes to
## find its words.
block_code_holds : KernelFacadeShape.Plan, Document.NormalizedAuthoring, U64, List(KernelFacadeSources.Source) -> List(KernelFacadeShape.CodeHold)
block_code_holds = |plan, authoring, block, sources| {
	rich = match list_at(authoring.blocks, block).kind {
		RichParagraph(paragraph) => list_at(authoring.rich_paragraphs, paragraph)
		_ => return []
	}
	body = match list_at(plan.block_runs, block) {
		TextBlock({ body: value, label: _, level: _ }) => value.physical
		ContentlessCell => return []
	}
	end = rich.inlines + rich.length
	has_code = {
		var $scan = rich.inlines
		var $found = False
		while !$found and $scan < end {
			$found = is_code(list_at(authoring.inlines, $scan).kind)
			$scan = $scan + 1
		}
		$found
	}
	if !has_code or body.length() == 0 {
		return []
	}
	store = plan.shape.store
	first_occurrence = list_at(plan.requests, body.start()).occurrence.index()
	var $holds = []
	var $run = body.start()
	var $index = rich.inlines
	while $index < end {
		record = list_at(authoring.inlines, $index)
		match record.kind {
			Text({ byte_length: _, byte_start, text }) => {
				leaf = record.first_leaf
				while $run < body.start() + body.length() and list_at(plan.requests, $run).occurrence.index() - first_occurrence < leaf {
					$run = $run + 1
				}
				first_run = $run
				while $run < body.start() + body.length() and list_at(plan.requests, $run).occurrence.index() - first_occurrence == leaf {
					$run = $run + 1
				}
				if $run > first_run and inside_code(authoring.inlines, record.parent) {
					first_cluster = list_at(store.runs, first_run).clusters.start()
					last = list_at(store.runs, $run - 1).clusters
					start = list_at(store.clusters, first_cluster).source.scalars.start()
					last_scalars = list_at(store.clusters, last.start() + last.length() - 1).source.scalars
					finish = last_scalars.start() + last_scalars.length()
					boundaries = list_at(sources, list_at(plan.requests, first_run).source.index()).analysis.line_boundaries
					if interior_opportunity(boundaries, start, finish) {
						$holds = append_word_holds($holds, text, first_run, byte_start, boundaries)
					}
				}
			}
			_ => {}
		}
		$index = $index + 1
	}
	$holds
}

## Whether inline `parent` (encoded `0` or `i + 1`) or one of its
## ancestors is a code span.
inside_code : List(Document.NormalizedInline), U64 -> Bool
inside_code = |inlines, parent| {
	var $cursor = parent
	var $found = False
	while !$found and $cursor != 0 {
		record = list_at(inlines, $cursor - 1)
		$found = is_code(record.kind)
		$cursor = record.parent
	}
	$found
}

is_code : Document.NormalizedInlineKind -> Bool
is_code = |kind| match kind {
	Code => True
	_ => False
}

## Whether a boundary strictly inside `start..finish` allows a break a
## hold can withhold (`Allowed` and `Tailorable`).
interior_opportunity : List(KernelUnicode.LineBoundary), U64, U64 -> Bool
interior_opportunity = |boundaries, start, finish| {
	var $scalar = start + 1
	var $found = False
	while !$found and $scalar < finish {
		boundary = list_at(boundaries, $scalar)
		$found = boundary.decision == Allowed and boundary.authority == Tailorable
		$scalar = $scalar + 1
	}
	$found
}

## One hold per word of a code leaf's text (maximal runs of scalars other
## than U+0020) that has a break opportunity inside it. `byte_start` is the
## leaf's first byte in its source; words are found with `split_first`,
## which slices the text without copying it, and each word's byte range is
## converted to scalars through the boundaries' byte offsets.
append_word_holds : List(KernelFacadeShape.CodeHold), Str, U64, U64, List(KernelUnicode.LineBoundary) -> List(KernelFacadeShape.CodeHold)
append_word_holds = |holds, text, run, byte_start, boundaries| {
	var $holds = holds
	var $rest = text
	var $offset = byte_start
	var $done = False
	while !$done {
		word_bytes = match $rest.split_first(" ") {
			Ok({ before, after }) => {
				$rest = after
				before.count_utf8_bytes()
			}
			Err(NotFound) => {
				$done = True
				$rest.count_utf8_bytes()
			}
		}
		start = scalar_of_byte(boundaries, $offset)
		finish = scalar_of_byte(boundaries, $offset + word_bytes)
		if finish > start + 1 and interior_opportunity(boundaries, start, finish) {
			$holds = $holds.append({ run, scalars: Semantics.Range.from_start_and_length(start, finish - start) })
		}
		$offset = $offset + word_bytes + 1
	}
	$holds
}

## The scalar at byte offset `byte` of a source: boundaries hold one entry
## per scalar offset with its byte offset, in increasing order.
scalar_of_byte : List(KernelUnicode.LineBoundary), U64 -> U64
scalar_of_byte = |boundaries, byte| {
	var $low = 0
	var $high = boundaries.len()
	while $low < $high {
		middle = $low + ($high - $low) // 2
		if list_at(boundaries, middle).byte_offset < byte {
			$low = middle + 1
		} else {
			$high = middle
		}
	}
	$low
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

## Every itemized script run a leaf overlaps must be in the facade's
## declared set: Latin or Han, with Common and Inherited, whose Common-run
## rule applies later. Han on the single-face path is then located by the
## shaping rejection as a coverage gap or an unsupported script. Returns
## the advanced run cursor; leaves arrive in scalar order.
inline_script : List(KernelUnicode.ScriptRun), U64, U64, U64, U64, U64 -> Try(U64, KernelFacadeShape.Error)
inline_script = |runs, from, scalar_start, scalar_end, block, inline| {
	var $cursor = from
	while $cursor < runs.len() and list_at(runs, $cursor).range.scalar_end <= scalar_start {
		$cursor = $cursor + 1
	}
	var $probe = $cursor
	while $probe < runs.len() and list_at(runs, $probe).range.scalar_start < scalar_end {
		script = list_at(runs, $probe).script

		## Han is declared on both paths; on the single-face path the
		## shaping rejection then locates it as a coverage gap or an
		## unsupported script.
		accepted = script == "Latn" or script == "Zyyy" or script == "Zinh" or script == "Hani"
		if !accepted {
			return Err(UnsupportedInlineScript({ block, inline, script }))
		}
		$probe = $probe + 1
	}
	Ok($cursor)
}

## The innermost themed inline role around a leaf decides its color; with
## no themed role the leaf paints like its paragraph.
## A text leaf's size: the paragraph size scaled by the innermost inline
## role with a scale, in thousandths of a point rounded down. The facade
## validates every scale (50 to 100 percent) before preparation.
inline_size : List(Document.NormalizedInline), U64, Theme, Layout.Unit -> Layout.Unit
inline_size = |inlines, parent, theme, size| {
	var $cursor = parent
	while $cursor != 0 {
		record = list_at(inlines, $cursor - 1)
		scale = match record.kind {
			Code => Theme.inline_scale(theme, Code)
			Emphasis => Theme.inline_scale(theme, Emphasis)
			Quote => Theme.inline_scale(theme, Quote)
			Strong => Theme.inline_scale(theme, Strong)
			_ => Inherited
		}
		match scale {
			Percent(percent) => return Layout.Unit.from_raw(size.raw() * percent.to_i64_wrap() // 100)
			Inherited => {}
		}
		$cursor = record.parent
	}
	size
}

inline_color : Document.NormalizedAuthoring, U64, U64, Theme, Color.SourceValue -> Color.SourceValue
inline_color = |authoring, block, parent, theme, paragraph_color| {
	var $cursor = parent
	var $color = Unresolved
	while $cursor != 0 and $color == Unresolved {
		record = list_at(authoring.inlines, $cursor - 1)
		role = match record.kind {
			Code => Role(Code)
			Emphasis => Role(Emphasis)
			Link(_) | InternalLink(_) => Role(Link)
			Quote => Role(Quote)
			Strong => Role(Strong)
			_ => NoRole
		}
		match role {
			Role(value) => match role_color(authoring, block, theme, value) {
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

## One role's color for a block: the innermost enclosing `Pdf.scoped`
## group that colors the role, else the theme. A document without scopes
## never walks its groups.
role_color : Document.NormalizedAuthoring, U64, Theme, Theme.ScopeRole -> Theme.InlineColor
role_color = |authoring, block, theme, role| {
	if !authoring.scopes.is_empty() {
		var $code = list_at(authoring.blocks, block).parent
		while $code != 0 {
			group = list_at(authoring.groups, $code - 1)
			match group.kind {
				Scope(index) => match list_at(authoring.scopes, index.to_u64()).color(role) {
					Themed(color) => return Themed(color)
					Inherited => {}
				}
				_ => {}
			}
			$code = group.parent
		}
	}
	match role {
		Code => Theme.inline_color(theme, Code)
		Emphasis => Theme.inline_color(theme, Emphasis)
		Link => Theme.link_style(theme).color
		Quote => Theme.inline_color(theme, Quote)
		Strong => Theme.inline_color(theme, Strong)
		Text => Inherited
	}
}

## A block's ordinary text color: the innermost scope's `Text` color, else
## `color`. A document without scopes never walks its groups.
scoped_text_color : Document.NormalizedAuthoring, U64, Theme, Color.SourceValue -> Color.SourceValue
scoped_text_color = |authoring, block, theme, color| {
	if authoring.scopes.is_empty() {
		return color
	}
	match role_color(authoring, block, theme, Text) {
		Themed(scoped) => scoped
		Inherited => color
	}
}

## A plain block's text style: its kind's theme style, with a link block
## colored by the innermost scope's link color when one applies.
block_style : Document.NormalizedAuthoring, U64, Theme -> Theme.TextStyle
block_style = |authoring, block, theme| {
	kind = list_at(authoring.blocks, block).kind
	style = style_for(kind, theme)
	match kind {
		Link(_) | InternalLink(_) if !authoring.scopes.is_empty() => match role_color(authoring, block, theme, Link) {
			Themed(color) => { ..style, color }
			Inherited => style
		}
		_ if !authoring.scopes.is_empty() => { ..style, color: scoped_text_color(authoring, block, theme, style.color) }
		_ => style
	}
}

select_source_segments : Font.Registry, Font.PolicyId, KernelFacadeSources.Source, U64, Semantics.Language -> Try(List({ clusters : Semantics.Range, face : Font.FaceId, script : Font.Script }), KernelFacadeShape.Error)
select_source_segments = |registry, policy, source, index, language| {
	faces = registry.policy_faces(policy) ? PolicyInvalid
	clusters = ordered_source_clusters(source, index)?
	selection = match registry.plan({ clusters, language, policy, source: Semantics.TextSourceId.from_index(index) }) {
		Complete(value) => value
		Rejected(errors) => return Err(FontSelectionRejected(errors))
	}
	segments = ordered_segments(selection.face_ranges, source.analysis.script_runs, faces, index)?
	store = registry.store()
	var $selected = List.with_capacity(segments.len())
	for segment in segments {
		face = list_at(faces, segment.font)
		if face.index() >= store.faces.len() or list_at(store.faces, face.index()).provision != BuiltIn {
			return Err(FontSelectionRejected([UnsupportedBuiltInShaping({ cluster: segment.clusters.start(), script: segment.script })]))
		}
		$selected = $selected.append({ clusters: segment.clusters, face, script: segment.script })
	}
	Ok($selected)
}

## One selected physical segment of a source: a contiguous grapheme-cluster
## range owned by one dense output font and one itemized script.
SelectedSegment : { clusters : Semantics.Range, font : U64, script : Font.Script }

build_ordered_plan : Document.NormalizedAuthoring, List(KernelFacadeSemantics.BlockOwnership), Semantics.Store, List(KernelFacadeSources.Source), { policy : Font.PolicyId, registry : Font.Registry }, Theme, KernelFacadeShape.Limits -> Try(KernelFacadeShape.Plan, KernelFacadeShape.Error)
build_ordered_plan = |authoring, owners, store, source_store, ordered, theme, limits| {
	preparation = prepare_plan(authoring, owners, store, source_store, limits.max_requests, theme, PolicySelectsFaces)?
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
		clusters = match ordered_source_clusters(source, $source_index) {
			Ok(value) => value
			Err(error) => return Err(ordered_failure(authoring, preparation, store, source_store, ordered.registry, policy_faces, error))
		}
		selection = match ordered.registry.plan({ clusters, language: batch_language, policy: ordered.policy, source: Semantics.TextSourceId.from_index($source_index) }) {
			Complete(value) => value
			Rejected(errors) => return Err(ordered_failure(authoring, preparation, store, source_store, ordered.registry, policy_faces, FontSelectionRejected(errors)))
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
		segments = match ordered_segments(list_at($ranges_per_source, $source_index), source.analysis.script_runs, $used_faces, $source_index) {
			Ok(value) => value
			Err(error) => return Err(ordered_failure(authoring, preparation, store, source_store, ordered.registry, policy_faces, error))
		}
		$segments_per_source = $segments_per_source.append(segments)
		$source_index = $source_index + 1
	}

	## Expand each logical request into its physical selected runs in the
	## exact order the preparation assigned requests.
	var $expanded = { origins: [], requests: [], selected: [], styles: [] }
	var $block_runs = List.repeat(unset_block_runs, preparation.block_runs.len())
	var $block_index = 0
	while $block_index < preparation.block_runs.len() {
		match list_at(preparation.block_runs, $block_index) {
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
			ContentlessCell => {
				$block_runs = list_set($block_runs, $block_index, ContentlessCell)
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

	## A link block paints in the body style with the theme's link color.
	Link(_) | InternalLink(_) => {
		body = Theme.body_style(theme)
		match Theme.link_style(theme).color {
			Themed(color) => { ..body, color }
			Inherited => body
		}
	}
	Title => Theme.title_style(theme)
	Heading(level) | DestinationHeading({ level, name: _ }) => Theme.heading_level_style(theme, heading_level(level))

	## A figure's anchor line is shaped in the body style; pagination gives
	## it the figure's (scaled) drawing height as its leading. A contentless
	## cell shapes nothing; its style is the body style of its row.
	Bullet(_) | Paragraph | DestinationParagraph(_) | EmptyCell | Figure(_) | FigureCaption(_) | RichParagraph(_) => Theme.body_style(theme)
}

## Semantic planning rejects a heading level outside 1 to 6
## (`UnsupportedHeadingLevel`) before shaping.
heading_level : U8 -> Theme.HeadingLevel
heading_level = |level| match level {
	1 => H1
	2 => H2
	3 => H3
	4 => H4
	5 => H5
	6 => H6
	_ => crash "validated heading level escaped"
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

## The rules a shaping path applies to one scalar: whether its itemized
## script is outside the facade's declared set, declared but not shaped by
## this path, or shaped; and whether a selected face covers it.
TextRules : { covers : U32 -> Bool, script : Str -> [Declared, Shaped, Undeclared] }

TextFailure : { cluster : U64, reason : [Cluster, Coverage(U32), Script(Str)], scalar : U64 }

## Locate the first text a shaping path cannot shape, in document order, as
## the block (and, in a rich paragraph, the text inline) that owns it and
## the failing cluster's scalars relative to that text. Runs only on a
## shaping rejection: each source is scanned once for its failing clusters,
## script before cluster before coverage, and each request then finds its
## first failure by binary search, so the scan is linear in the text plus
## `requests * log(failures)`.
##
## `rules` holds one rule set per face in use and `rule_of` names the set
## that applies to a request; each set scans every source once.
locate_text_failure : Document.NormalizedAuthoring, KernelFacadeShape.Preparation, Semantics.Store, List(KernelFacadeSources.Source), List(TextRules), (U64 -> U64) -> [Located(KernelFacadeShape.Error), NotLocated]
locate_text_failure = |authoring, preparation, store, sources, rules, rule_of| {
	failures = rules.map(|rule| sources.map(|source| source_failures(source, rule)))
	var $block = 0
	while $block < preparation.block_runs.len() {
		match list_at(preparation.block_runs, $block) {
			TextBlock({ body, label, level: _ }) => {
				match label {
					Label(run) => match request_failure(preparation, store, list_at(failures, rule_of(run.physical.start())), run.physical.start()) {
						Found(found) => return Located(UnsupportedText({ block: $block, inline: NoInline, reason: found.reason, scalars: found.scalars }))
						None => {}
					}
					NoLabel => {}
				}
				var $request = body.physical.start()
				while $request < body.physical.start() + body.physical.length() {
					match request_failure(preparation, store, list_at(failures, rule_of($request)), $request) {
						Found(found) => {
							inline = match list_at(authoring.blocks, $block).kind {
								RichParagraph(paragraph) => leaf_inline(authoring, list_at(authoring.rich_paragraphs, paragraph), $request - body.physical.start())
								_ => NoInline
							}
							return Located(UnsupportedText({ block: $block, inline, reason: found.reason, scalars: found.scalars }))
						}
						None => {}
					}
					$request = $request + 1
				}
			}
			ContentlessCell => {}
		}
		$block = $block + 1
	}
	NotLocated
}

## The first failing cluster inside one request's occurrence, relative to
## the occurrence's first scalar.
request_failure : KernelFacadeShape.Preparation, Semantics.Store, List(List(TextFailure)), U64 -> [Found({ reason : [Cluster, Coverage(U32), Script(Str)], scalars : Semantics.Range }), None]
request_failure = |preparation, store, failures, request_index| {
	request = list_at(preparation.requests, request_index)
	occurrence = list_at(store.occurrences, request.occurrence.index())
	match occurrence.source {
		Text(id, UnicodeRange(range)) => {
			if id.index() >= failures.len() {
				return None
			}
			listed = list_at(failures, id.index())
			start = range.scalars.start()
			end = start + range.scalars.length()
			var $low = 0
			var $high = listed.len()
			while $low < $high {
				middle = $low + ($high - $low) // 2
				if list_at(listed, middle).scalar < start {
					$low = middle + 1
				} else {
					$high = middle
				}
			}
			if $low < listed.len() and list_at(listed, $low).scalar < end {
				failure = list_at(listed, $low)
				Found({ reason: failure.reason, scalars: Semantics.Range.from_start_and_length(failure.scalar - start, failure.cluster) })
			} else {
				None
			}
		}
		_ => None
	}
}

## The text inline of a rich paragraph that holds leaf `leaf`.
leaf_inline : Document.NormalizedAuthoring, Document.NormalizedRich, U64 -> [AtInline(U64), NoInline]
leaf_inline = |authoring, rich, leaf| {
	var $inline = rich.inlines
	while $inline < rich.inlines + rich.length {
		record = list_at(authoring.inlines, $inline)
		match record.kind {
			Text(_) => if record.first_leaf == leaf {
				return AtInline($inline)
			}
			_ => {}
		}
		$inline = $inline + 1
	}
	NoInline
}

## Every cluster of one source that the rules reject, in scalar order, keyed
## by its first scalar.
source_failures : KernelFacadeSources.Source, TextRules -> List(TextFailure)
source_failures = |source, rules| {
	analysis = source.analysis
	var $failures = []
	var $run = 0
	var $grapheme = 0
	var $reported_cluster = U64.highest
	for located in Scalar.iter(source.unicode) {
		scalar_index = located.scalar_index
		while $run < analysis.script_runs.len() and list_at(analysis.script_runs, $run).range.scalar_end <= scalar_index {
			$run = $run + 1
		}
		while $grapheme < analysis.graphemes.len() and list_at(analysis.graphemes, $grapheme).scalar_end <= scalar_index {
			$grapheme = $grapheme + 1
		}
		script = if $run < analysis.script_runs.len() list_at(analysis.script_runs, $run).script else ""
		cluster = if $grapheme < analysis.graphemes.len() {
			record = list_at(analysis.graphemes, $grapheme)
			{ length: record.scalar_end - record.scalar_start, start: record.scalar_start }
		} else {
			{ length: 1, start: scalar_index }
		}
		value = Scalar.to_u32(located.scalar)
		script_rule = (rules.script)(script)
		reason = if script_rule == Undeclared {
			Failed(Script(script))
		} else if cluster.length != 1 {
			Failed(Cluster)
		} else if !(rules.covers)(value) {
			Failed(Coverage(value))
		} else if script_rule == Declared {
			Failed(Script(script))
		} else {
			Passed
		}
		match reason {
			Failed(why) => if cluster.start != $reported_cluster {
				$failures = $failures.append({ cluster: cluster.length, reason: why, scalar: cluster.start })
				$reported_cluster = cluster.start
			}
			Passed => {}
		}
	}
	$failures
}

## An ordered-path coverage or script rejection, located when the policy's
## faces cannot shape some text; any other rejection is kept.
ordered_failure : Document.NormalizedAuthoring, KernelFacadeShape.Preparation, Semantics.Store, List(KernelFacadeSources.Source), Font.Registry, List(Font.FaceId), KernelFacadeShape.Error -> KernelFacadeShape.Error
ordered_failure = |authoring, preparation, store, sources, registry, faces, error| {
	var $fonts = List.with_capacity(faces.len())
	for face in faces {
		match registry.prepared_face(face) {
			Ok(font) => {
				$fonts = $fonts.append(font)
			}
			Err(_) => return error
		}
	}
	match locate_text_failure(authoring, preparation, store, sources, [policy_rules($fonts)], |_| 0) {
		Located(located) => located
		NotLocated => error
	}
}

## The single-face rules: Latin with Common and Inherited, covered by the
## one face with a glyph other than `.notdef`. Han is declared but shaped
## only through an ordered policy, so uncovered Han is a coverage gap and
## covered Han an unsupported script.
single_face_rules : KernelFont.Inspection -> TextRules
single_face_rules = |font| {
	covers: |scalar| match KernelFont.glyph_for_scalar(font, scalar) {
		Some(glyph) => glyph != 0
		None => False
	},
	script: |alias| if alias == "Latn" or alias == "Zyyy" or alias == "Zinh" Shaped else if alias == "Hani" Declared else Undeclared,
}

## The ordered-policy rules: the declared script set, covered by any face
## of the policy.
policy_rules : List(KernelFont.Inspection) -> TextRules
policy_rules = |fonts| {
	covers: |scalar| fonts.any(
		|font| match KernelFont.glyph_for_scalar(font, scalar) {
			Some(glyph) => glyph != 0
			None => False
		},
	),
	script: |alias| if declared_script(alias) Shaped else Undeclared,
}
