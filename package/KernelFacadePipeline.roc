import Document
import Font
import KernelFacadeFragments
import KernelFacadeFurniture
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
import KernelFacadeReport
import KernelFacadeScenes
import KernelFacadeSemantics
import KernelFacadeShape
import KernelFacadeSources
import KernelFacadeText
import KernelFont
import KernelLineLayout
import KernelMetadata
import KernelNavigation
import KernelPageLayout
import KernelPdfFont
import KernelSemantics
import KernelShape
import KernelStabilization
import KernelStructure
import KernelTextSemantics
import Layout
import Theme

KernelFacadePipeline :: [].{
	Error : [
		Fragments(KernelFacadeFragments.Error),
		Furniture(KernelFacadeFurniture.Error),
		Lines(KernelFacadeLines.Error),
		Output(KernelFacadeOutput.Error),
		Pages(KernelFacadePages.Error),

		## Reference stabilization exhausted its pass budget, or repeated an
		## earlier non-identical reference state.
		ReferenceBudget({ passes : U64 }),
		ReferenceCycle({ first_seen_pass : U64, repeated_at_pass : U64 }),
		Scenes(KernelFacadeScenes.Error),
		Semantics(KernelFacadeSemantics.Error),
		Shape(KernelFacadeShape.Error),
		Text(KernelFacadeText.Error),
	]
	Stage : [FragmentsReady, LinesReady, OutputReady, PagesReady, ScenesReady, SemanticsReady, ShapeReady, TextReady]

	Limits :: {
		fragment_semantics : KernelSemantics.Limits,
		fragments : KernelFacadeFragments.Limits,
		lines : KernelFacadeLines.Limits,
		navigation : KernelNavigation.Limits,
		output : KernelFacadeOutput.Limits,
		pages : KernelFacadePages.Limits,
		scenes : KernelFacadeScenes.Limits,
		semantics : KernelFacadeSemantics.Limits,
		shape : KernelFacadeShape.Limits,
		text : KernelFacadeText.Limits,
	}.{
		make : {
			fragment_semantics : KernelSemantics.Limits,
			fragments : KernelFacadeFragments.Limits,
			lines : KernelFacadeLines.Limits,
			navigation : KernelNavigation.Limits,
			output : KernelFacadeOutput.Limits,
			pages : KernelFacadePages.Limits,
			scenes : KernelFacadeScenes.Limits,
			semantics : KernelFacadeSemantics.Limits,
			shape : KernelFacadeShape.Limits,
			text : KernelFacadeText.Limits,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	## `reference_passes` counts stabilization passes (zero without page
	## templates); `field_resolutions` counts resolved page-field values and
	## `furniture_items` furniture lines shaped, one per line per page.
	Work : {
		blocks : U64,
		field_resolutions : U64,
		final_runs : U64,
		fragments : U64,
		furniture_items : U64,
		lines : U64,
		objects : U64,
		occurrences : U64,
		pages : U64,
		reference_passes : U64,
		scene_commands : U64,
		shaped_runs : U64,
	}

	probe : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits, Stage -> Try(Work, Error)
	probe = |authoring, font, theme, page_size, descriptor, limits, stage| probe_plan(authoring, font, theme, page_size, descriptor, limits, stage)

	## The ordered-policy pipeline through pagination, furniture, text, and
	## fragments, without scene or PDF lowering: the work of a document
	## whose paint facts need document facts.
	probe_ordered : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, Limits -> Try(Work, Error)
	probe_ordered = |authoring, ordered, theme, page_size, limits| probe_ordered_plan(authoring, ordered, theme, page_size, limits)

	## `facts` holds the preparation report's compact facts when the build
	## collected them (`*_reporting`), and `NoFacts` otherwise.
	Plan :: { facts : [Facts(KernelFacadeReport.Facts), NoFacts], output : KernelFacadeOutput.Plan, work : Work }.{
		build : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build = |authoring, font, theme, page_size, descriptor, limits| build_plan(authoring, font, theme, page_size, descriptor, NoDocumentFacts, NoCollect, limits)

		## Document facts add the packaged intent profile to the scene color
		## store and flow to structure planning; `NoDocumentFacts` keeps the
		## plan byte-identical to `build`.
		build_with_facts : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_with_facts = |authoring, font, theme, page_size, descriptor, facts, limits| build_plan(authoring, font, theme, page_size, descriptor, facts, NoCollect, limits)

		## `build_with_facts` that also collects the preparation report's
		## compact facts (`facts`). The prepared output is identical.
		build_reporting : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_reporting = |authoring, font, theme, page_size, descriptor, facts, limits| build_plan(authoring, font, theme, page_size, descriptor, facts, Collect, limits)

		## The ordered multi-face pipeline. Selection, shaping, logical line
		## layout, boundary-splitting text materialization, and per-font
		## planning/subsetting compose the same downstream stages; the
		## single-face `build` path above is untouched.
		build_ordered : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build_ordered = |authoring, ordered, theme, page_size, descriptor, limits| build_ordered_pipeline(authoring, Policy(ordered), theme, page_size, descriptor, NoDocumentFacts, NoCollect, limits)

		build_ordered_with_facts : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_ordered_with_facts = |authoring, ordered, theme, page_size, descriptor, facts, limits| build_ordered_pipeline(authoring, Policy(ordered), theme, page_size, descriptor, facts, NoCollect, limits)

		build_ordered_reporting : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_ordered_reporting = |authoring, ordered, theme, page_size, descriptor, facts, limits| build_ordered_pipeline(authoring, Policy(ordered), theme, page_size, descriptor, facts, Collect, limits)

		## The style-face path with inline role faces: every run shapes in its
		## style's or innermost role's face, and the used faces become the
		## output fonts through the same multi-font stages as an ordered
		## policy. Furniture shapes in the body face, output font 0.
		build_styled_with_facts : Document.NormalizedAuthoring, KernelFacadeShape.StyledFaces, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_styled_with_facts = |authoring, styled, theme, page_size, descriptor, facts, limits| build_ordered_pipeline(authoring, Styled(styled), theme, page_size, descriptor, facts, NoCollect, limits)

		build_styled_reporting : Document.NormalizedAuthoring, KernelFacadeShape.StyledFaces, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_styled_reporting = |authoring, styled, theme, page_size, descriptor, facts, limits| build_ordered_pipeline(authoring, Styled(styled), theme, page_size, descriptor, facts, Collect, limits)

		output : Plan -> KernelFacadeOutput.Plan
		output = |plan| plan.output

		structure : Plan -> KernelStructure.Plan
		structure = |plan| KernelFacadeOutput.Plan.structure(plan.output)

		work : Plan -> Work
		work = |plan| plan.work

		facts : Plan -> [Facts(KernelFacadeReport.Facts), NoFacts]
		facts = |plan| plan.facts
	}
}

## The multi-font arms: an ordered policy, or style faces with inline role
## faces.
MultiFace : [Policy({ policy : Font.PolicyId, registry : Font.Registry }), Styled(KernelFacadeShape.StyledFaces)]

Upstream := {
	descriptor : KernelPdfFont.Descriptor,
	font : KernelFont.Inspection,
	layout_facts : [LayoutFacts(KernelFacadeReport.LayoutFacts), NoLayoutFacts],
	limits : KernelFacadePipeline.Limits,
	navigation : KernelFacadeFragments.NavigationAuthoring,
	ownership : List(KernelFacadeSemantics.BlockOwnership),
	page_size : Layout.Size,
	preliminary : KernelTextSemantics.Plan,
	text : KernelFacadeText.Plan,
	work : KernelFacadePipeline.Work,
}

## The authored navigation facts for the post-layout stage: link and
## destination records from the semantic stage, and the document outline and
## page-label ranges from normalized authoring.
navigation_authoring : KernelFacadeSemantics.Plan, Document.NormalizedAuthoring -> KernelFacadeFragments.NavigationAuthoring
navigation_authoring = |semantics, authoring| {
	links = KernelFacadeSemantics.Plan.links(semantics)
	destinations = KernelFacadeSemantics.Plan.destinations(semantics)
	if links.is_empty() and destinations.is_empty() and authoring.outline.is_empty() and authoring.page_labels.is_empty() {
		NoNavigationAuthoring
	} else {
		WithNavigationAuthoring({
			destinations,
			links,
			outline: authoring.outline,
			page_labels: authoring.page_labels,
		})
	}
}

navigation_input : KernelFacadeFragments.Plan, KernelNavigation.Limits -> [NoNavigation, WithNavigation({ anchor_rects : List(KernelNavigation.AnchorRect), max_outline_depth : U64, store : KernelNavigation.Store })]
navigation_input = |fragments, limits| match KernelFacadeFragments.Plan.navigation(fragments) {
	NoNavigationStore => NoNavigation
	WithNavigationStore(store) => WithNavigation({
		anchor_rects: KernelFacadeFragments.Plan.anchor_rects(fragments),
		max_outline_depth: KernelNavigation.Limits.max_outline_depth(limits),
		store,
	})
}

build_plan : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelFacadeReport.Request, KernelFacadePipeline.Limits -> Try(KernelFacadePipeline.Plan, KernelFacadePipeline.Error)
build_plan = |authoring, font, theme, page_size, descriptor, facts, request, limits| {
	upstream = build_upstream(authoring, font, theme, page_size, descriptor, request, limits)?
	fragments = KernelFacadeFragments.Plan.build_with_navigation(upstream.preliminary, upstream.text, upstream.navigation, limits.fragments, limits.fragment_semantics, limits.navigation) ? Fragments
	report_facts = match upstream.layout_facts {
		NoLayoutFacts => NoFacts
		LayoutFacts(layout_facts) => Facts(KernelFacadeReport.collect(layout_facts, upstream.ownership, KernelFacadeFragments.Plan.fragments(fragments), KernelFacadeText.Plan.text(KernelFacadeFragments.Plan.text(fragments)), upstream.work.pages))
	}
	scenes = KernelFacadeScenes.Plan.build_authoring_with_intent(fragments, page_size, authoring, intent_profile(facts), limits.scenes) ? Scenes
	output = KernelFacadeOutput.Plan.build_with_navigation(scenes, font, descriptor, facts, navigation_input(fragments, limits.navigation), limits.output) ? Output
	Ok(
		KernelFacadePipeline.Plan.{
			facts: report_facts,
			output,
			work: {
				..upstream.work,
				fragments: KernelFacadeFragments.Plan.fragments(fragments).len(),
				objects: KernelFacadeOutput.Plan.work(output).objects,
				scene_commands: KernelFacadeScenes.Plan.work(scenes).command_writes,
			},
		},
	)
}

build_ordered_pipeline : Document.NormalizedAuthoring, MultiFace, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelFacadeReport.Request, KernelFacadePipeline.Limits -> Try(KernelFacadePipeline.Plan, KernelFacadePipeline.Error)
build_ordered_pipeline = |authoring, multi, theme, page_size, descriptor, facts, request, limits| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = (match multi {
		Policy(ordered) => KernelFacadeShape.Plan.build_ordered(
			KernelFacadeSemantics.Plan.authoring(semantics),
			KernelFacadeSemantics.Plan.block_ownership(semantics),
			KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
			source_store,
			ordered,
			theme,
			limits.shape,
		)
		Styled(styled) => KernelFacadeShape.Plan.build_styled(
			KernelFacadeSemantics.Plan.authoring(semantics),
			KernelFacadeSemantics.Plan.block_ownership(semantics),
			KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
			source_store,
			styled,
			theme,
			limits.shape,
		)
	}) ? Shape
	furniture_selection = match multi {
		Policy(ordered) => PolicyFaces({ faces: KernelFacadeShape.Plan.selected_faces(shape), fonts: KernelFacadeShape.Plan.fonts(shape), policy: ordered.policy, registry: ordered.registry })
		Styled(styled) => match styled.fonts.first() {
			Ok(body) => SingleFace(body)
			Err(_) => {
				crash "styled font selection has no body face"
			}
		}
	}
	lines = KernelFacadeLines.Plan.build_ordered_authoring(authoring, shape, source_store, page_size, theme, limits.lines) ? Lines

	## The laid-out record is destructured at once so its plans stay uniquely
	## owned by the stages that consume them.
	{ pages, text, work: laid_work } = lay_out(authoring, shape, lines, page_size, theme, furniture_selection, source_store.len(), limits)?
	layout_facts = match request {
		Collect => LayoutFacts(KernelFacadeReport.layout(pages))
		NoCollect => NoLayoutFacts
	}

	## Furniture under an ordered policy may add faces the body did not use;
	## they follow the body's fonts in dense run-instance order.
	output_fonts = match KernelFacadeText.Plan.furniture(text) {
		WithFurniture(furniture) => {
			extra = KernelFacadeFurniture.Plan.extra_fonts(furniture)
			if extra.is_empty() KernelFacadeShape.Plan.fonts(shape) else KernelFacadeShape.Plan.fonts(shape).concat(extra)
		}
		NoFurniture => KernelFacadeShape.Plan.fonts(shape)
	}
	fragments = KernelFacadeFragments.Plan.build_with_navigation(preliminary, text, navigation_authoring(semantics, authoring), limits.fragments, limits.fragment_semantics, limits.navigation) ? Fragments
	page_total = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages)).len()
	report_facts = match layout_facts {
		NoLayoutFacts => NoFacts
		LayoutFacts(value) => Facts(KernelFacadeReport.collect(value, KernelFacadeSemantics.Plan.block_ownership(semantics), KernelFacadeFragments.Plan.fragments(fragments), KernelFacadeText.Plan.text(KernelFacadeFragments.Plan.text(fragments)), page_total))
	}
	scenes = KernelFacadeScenes.Plan.build_authoring_with_intent(fragments, page_size, authoring, intent_profile(facts), limits.scenes) ? Scenes
	output = KernelFacadeOutput.Plan.build_multi_with_navigation(scenes, output_fonts, descriptor, facts, navigation_input(fragments, limits.navigation), limits.output) ? Output
	shape_store = KernelFacadeShape.Plan.shape(shape).store
	line_store = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines))
	page_store = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages))
	final_store = KernelFacadeText.Plan.text(text)
	Ok(
		KernelFacadePipeline.Plan.{
			facts: report_facts,
			output,
			work: {
				blocks: authoring.blocks.len(),
				field_resolutions: laid_work.field_resolutions,
				final_runs: final_store.runs.len(),
				fragments: KernelFacadeFragments.Plan.fragments(fragments).len(),
				furniture_items: laid_work.furniture_items,
				lines: line_store.len(),
				objects: KernelFacadeOutput.Plan.work(output).objects,
				occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
				pages: page_store.len(),
				reference_passes: laid_work.reference_passes,
				scene_commands: KernelFacadeScenes.Plan.work(scenes).command_writes,
				shaped_runs: shape_store.runs.len(),
			},
		},
	)
}

intent_profile : KernelMetadata.PlanFacts -> KernelFacadeScenes.IntentProfile
intent_profile = |facts| match facts {
	NoDocumentFacts => NoIntentProfile
	WithDocumentFacts(_) => PackagedSrgbIntent
}

probe_plan : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelFacadePipeline.Limits, KernelFacadePipeline.Stage -> Try(KernelFacadePipeline.Work, KernelFacadePipeline.Error)
probe_plan = |authoring, font, theme, page_size, descriptor, limits, stage| {
	if stage == SemanticsReady or stage == ShapeReady or stage == LinesReady or stage == PagesReady {
		return probe_early(authoring, font, theme, page_size, limits, stage)
	}
	upstream = build_upstream(authoring, font, theme, page_size, descriptor, NoCollect, limits)?
	if stage == TextReady {
		return Ok(upstream.work)
	}
	fragments = KernelFacadeFragments.Plan.build(upstream.preliminary, upstream.text, limits.fragments, limits.fragment_semantics) ? Fragments
	fragment_work = { ..upstream.work, fragments: KernelFacadeFragments.Plan.fragments(fragments).len() }
	if stage == FragmentsReady {
		return Ok(fragment_work)
	}
	probe_intent = if authoring.figures.is_empty() and authoring.decorations.is_empty() NoIntentProfile else PackagedSrgbIntent
	scenes = KernelFacadeScenes.Plan.build_authoring_with_intent(fragments, page_size, authoring, probe_intent, limits.scenes) ? Scenes
	scene_work = { ..fragment_work, scene_commands: KernelFacadeScenes.Plan.work(scenes).command_writes }
	if stage == ScenesReady {
		return Ok(scene_work)
	}
	output = KernelFacadeOutput.Plan.build(scenes, font, descriptor, limits.output) ? Output
	Ok({ ..scene_work, objects: KernelFacadeOutput.Plan.work(output).objects })
}

probe_early : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelFacadePipeline.Limits, KernelFacadePipeline.Stage -> Try(KernelFacadePipeline.Work, KernelFacadePipeline.Error)
probe_early = |authoring, font, theme, page_size, limits, stage| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	work = {
		blocks: authoring.blocks.len(),
		field_resolutions: 0,
		final_runs: 0,
		fragments: 0,
		furniture_items: 0,
		lines: 0,
		objects: 0,
		occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
		pages: 0,
		reference_passes: 0,
		scene_commands: 0,
		shaped_runs: 0,
	}
	if stage == SemanticsReady {
		return Ok(work)
	}
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = KernelFacadeShape.Plan.build(
		KernelFacadeSemantics.Plan.authoring(semantics),
		KernelFacadeSemantics.Plan.block_ownership(semantics),
		KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
		source_store,
		font,
		theme,
		limits.shape,
	) ? Shape
	shape_work = { ..work, shaped_runs: KernelFacadeShape.Plan.shape(shape).store.runs.len() }
	if stage == ShapeReady {
		return Ok(shape_work)
	}
	lines = KernelFacadeLines.Plan.build_authoring(authoring, shape, source_store, page_size, theme, limits.lines) ? Lines
	line_work = { ..shape_work, lines: KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines)).len() }
	if stage == LinesReady {
		return Ok(line_work)
	}
	pages = match authoring.templates {
		NoTemplates => KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, limits.pages) ? Pages
		Templates(_) => {
			static = KernelFacadeFurniture.Static.build(authoring, theme, page_size) ? Furniture
			KernelFacadePages.Plan.build_with_template(authoring, shape, lines, page_size, theme, KernelFacadeFurniture.Static.flow(static), limits.pages) ? Pages
		}
	}
	Ok({ ..line_work, pages: KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages)).len() })
}

probe_ordered_plan : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelFacadePipeline.Limits -> Try(KernelFacadePipeline.Work, KernelFacadePipeline.Error)
probe_ordered_plan = |authoring, ordered, theme, page_size, limits| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = KernelFacadeShape.Plan.build_ordered(
		KernelFacadeSemantics.Plan.authoring(semantics),
		KernelFacadeSemantics.Plan.block_ownership(semantics),
		KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
		source_store,
		ordered,
		theme,
		limits.shape,
	) ? Shape
	selection = PolicyFaces({ faces: KernelFacadeShape.Plan.selected_faces(shape), fonts: KernelFacadeShape.Plan.fonts(shape), policy: ordered.policy, registry: ordered.registry })
	shaped_runs = KernelFacadeShape.Plan.shape(shape).store.runs.len()
	lines = KernelFacadeLines.Plan.build_ordered_authoring(authoring, shape, source_store, page_size, theme, limits.lines) ? Lines
	line_count = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines)).len()
	{ pages, text, work: laid_work } = lay_out(authoring, shape, lines, page_size, theme, selection, source_store.len(), limits)?
	page_count_value = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages)).len()
	final_runs = KernelFacadeText.Plan.text(text).runs.len()
	fragments = KernelFacadeFragments.Plan.build(preliminary, text, limits.fragments, limits.fragment_semantics) ? Fragments
	Ok({
		blocks: authoring.blocks.len(),
		field_resolutions: laid_work.field_resolutions,
		final_runs,
		fragments: KernelFacadeFragments.Plan.fragments(fragments).len(),
		furniture_items: laid_work.furniture_items,
		lines: line_count,
		objects: 0,
		occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
		pages: page_count_value,
		reference_passes: laid_work.reference_passes,
		scene_commands: 0,
		shaped_runs,
	})
}

build_upstream : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelFacadeReport.Request, KernelFacadePipeline.Limits -> Try(Upstream, KernelFacadePipeline.Error)
build_upstream = |authoring, font, theme, page_size, descriptor, request, limits| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = KernelFacadeShape.Plan.build(
		KernelFacadeSemantics.Plan.authoring(semantics),
		KernelFacadeSemantics.Plan.block_ownership(semantics),
		KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
		source_store,
		font,
		theme,
		limits.shape,
	) ? Shape
	lines = KernelFacadeLines.Plan.build_authoring(authoring, shape, source_store, page_size, theme, limits.lines) ? Lines

	## The laid-out record is destructured at once so its plans stay uniquely
	## owned by the stages that consume them.
	{ pages, text, work: laid_work } = lay_out(authoring, shape, lines, page_size, theme, SingleFace(font), source_store.len(), limits)?
	collected = match request {
		Collect => { layout: LayoutFacts(KernelFacadeReport.layout(pages)), ownership: KernelFacadeSemantics.Plan.block_ownership(semantics) }
		NoCollect => { layout: NoLayoutFacts, ownership: [] }
	}
	shape_store = KernelFacadeShape.Plan.shape(shape).store
	line_store = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines))
	page_store = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages))
	final_store = KernelFacadeText.Plan.text(text)
	Ok({
		descriptor,
		font,
		layout_facts: collected.layout,
		limits,
		navigation: navigation_authoring(semantics, authoring),
		ownership: collected.ownership,
		page_size,
		preliminary,
		text,
		work: {
			blocks: authoring.blocks.len(),
			field_resolutions: laid_work.field_resolutions,
			final_runs: final_store.runs.len(),
			fragments: 0,
			furniture_items: laid_work.furniture_items,
			lines: line_store.len(),
			objects: 0,
			occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
			pages: page_store.len(),
			reference_passes: laid_work.reference_passes,
			scene_commands: 0,
			shaped_runs: shape_store.runs.len(),
		},
	})
}

LaidOut : { pages : KernelFacadePages.Plan, text : KernelFacadeText.Plan, work : { field_resolutions : U64, furniture_items : U64, reference_passes : U64 } }

## Pagination and text materialization. A document without page templates
## has no layout-dependent reference and paginates once. A document with
## templates stabilizes its page fields by explicit reference states: the
## template stage fixes every flow frame before flow from region heights
## alone, pass 1 paginates the body (state: the page count), and pass 2
## resolves and proves the furniture with that state and recomputes it from
## the same pagination. No pass can change a flow frame, so pass 2 always
## repeats pass 1's state and stabilization ends after exactly two passes;
## the fixed budget of four passes and the cycle check still govern it.
lay_out : Document.NormalizedAuthoring, KernelFacadeShape.Plan, KernelFacadeLines.Plan, Layout.Size, Theme, [PolicyFaces(KernelFacadeFurniture.PolicyFonts), SingleFace(KernelFont.Inspection)], U64, KernelFacadePipeline.Limits -> Try(LaidOut, KernelFacadePipeline.Error)
lay_out = |authoring, shape, lines, page_size, theme, selection, source_base, limits| match authoring.templates {
	NoTemplates => {
		pages = KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, limits.pages) ? Pages
		text = KernelFacadeText.Plan.build(shape, lines, pages, limits.text) ? Text
		Ok({ pages, text, work: { field_resolutions: 0, furniture_items: 0, reference_passes: 0 } })
	}
	Templates(_) => {
		static = KernelFacadeFurniture.Static.build(authoring, theme, page_size) ? Furniture
		language = Language(authoring.language)
		furniture_limits = KernelFacadeFurniture.Limits.make({ max_inputs: 1000000, max_items: 4096, max_pieces: 1000000, shape: furniture_shape_limits, sources: furniture_source_limits })
		stabilized = KernelStabilization.stabilize(
			KernelStabilization.initial,
			reference_pass_budget,
			|state, candidate, _pass| match candidate {
				NoCandidate => {
					pages = KernelFacadePages.Plan.build_with_template(authoring, shape, lines, page_size, theme, KernelFacadeFurniture.Static.flow(static), limits.pages) ? Pages
					Ok({ candidate: Paginated(pages), state: { pages: page_count(pages), values: [] } })
				}
				Candidate(Paginated(pages)) | Candidate(Resolved({ furniture: _, pages })) => {
					furniture = KernelFacadeFurniture.Plan.resolve(static, state.pages, selection, language, source_base, furniture_limits) ? Furniture
					Ok({ candidate: Resolved({ furniture, pages }), state: { pages: page_count(pages), values: [] } })
				}
			},
		)?
		resolved = match stabilized.outcome {
			Stable({ passes, state: _, work: _ }) => match stabilized.candidate {
				Candidate(Resolved(value)) => { furniture: value.furniture, pages: value.pages, passes }
				_ => return Err(ReferenceBudget({ passes: passes }))
			}
			Cycle({ first_seen_pass, repeated: _, repeated_at_pass }) => return Err(ReferenceCycle({ first_seen_pass, repeated_at_pass }))
			BudgetExhausted({ attempted: _, passes, work: _ }) => return Err(ReferenceBudget({ passes: passes }))
		}
		body = KernelFacadeText.Plan.build(shape, lines, resolved.pages, limits.text) ? Text
		text = KernelFacadeText.Plan.with_furniture(body, resolved.furniture, limits.text) ? Text
		furniture_work = KernelFacadeFurniture.Plan.work(resolved.furniture)
		Ok({ pages: resolved.pages, text, work: { field_resolutions: furniture_work.field_resolutions, furniture_items: furniture_work.items_shaped, reference_passes: resolved.passes } })
	}
}

## The fixed pass budget of page-template reference stabilization.
reference_pass_budget : U64
reference_pass_budget = 4

page_count : KernelFacadePages.Plan -> U64
page_count = |pages| KernelFacadePages.Plan.pages(pages).len()

furniture_shape_limits : KernelShape.Limits
furniture_shape_limits = KernelShape.Limits.make({ max_clusters: 1000000, max_glyphs: 1000000, max_scalars: 1000000, max_source_bytes: 1000000 })

furniture_source_limits : KernelFacadeSources.Limits
furniture_source_limits = KernelFacadeSources.Limits.make({
	max_hash_probes: 4000000,
	max_inputs: 1000000,
	max_source_bytes: 1000000,
	max_source_scalars: 1000000,
	max_table_slots: 2097152,
	max_unique_sources: 1000000,
	unicode: { max_graphemes: 1000000, max_line_boundaries: 1000001, max_scalars: 1000000, max_script_runs: 2048 },
})
