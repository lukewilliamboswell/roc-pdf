import Document
import Font
import KernelFacadeFragments
import KernelFacadeLines
import KernelFacadeOutput
import KernelFacadePages
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
import KernelStructure
import KernelTextSemantics
import Layout
import Theme

KernelFacadePipeline :: [].{
	Error : [
		Fragments(KernelFacadeFragments.Error),
		Lines(KernelFacadeLines.Error),
		Output(KernelFacadeOutput.Error),
		Pages(KernelFacadePages.Error),
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

	Work : {
		blocks : U64,
		final_runs : U64,
		fragments : U64,
		lines : U64,
		objects : U64,
		occurrences : U64,
		pages : U64,
		scene_commands : U64,
		shaped_runs : U64,
	}

	probe : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits, Stage -> Try(Work, Error)
	probe = |authoring, font, theme, page_size, descriptor, limits, stage| probe_plan(authoring, font, theme, page_size, descriptor, limits, stage)

	Plan :: { output : KernelFacadeOutput.Plan, work : Work }.{
		build : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build = |authoring, font, theme, page_size, descriptor, limits| build_plan(authoring, font, theme, page_size, descriptor, NoDocumentFacts, limits)

		## Document facts add the packaged intent profile to the scene color
		## store and flow to structure planning; `NoDocumentFacts` keeps the
		## plan byte-identical to `build`.
		build_with_facts : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_with_facts = |authoring, font, theme, page_size, descriptor, facts, limits| build_plan(authoring, font, theme, page_size, descriptor, facts, limits)

		## The ordered multi-face pipeline. Selection, shaping, logical line
		## layout, boundary-splitting text materialization, and per-font
		## planning/subsetting compose the same downstream stages; the
		## single-face `build` path above is untouched.
		build_ordered : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build_ordered = |authoring, ordered, theme, page_size, descriptor, limits| build_ordered_pipeline(authoring, ordered, theme, page_size, descriptor, NoDocumentFacts, limits)

		build_ordered_with_facts : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_ordered_with_facts = |authoring, ordered, theme, page_size, descriptor, facts, limits| build_ordered_pipeline(authoring, ordered, theme, page_size, descriptor, facts, limits)

		output : Plan -> KernelFacadeOutput.Plan
		output = |plan| plan.output

		structure : Plan -> KernelStructure.Plan
		structure = |plan| KernelFacadeOutput.Plan.structure(plan.output)

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Upstream := {
	descriptor : KernelPdfFont.Descriptor,
	font : KernelFont.Inspection,
	limits : KernelFacadePipeline.Limits,
	navigation : KernelFacadeFragments.NavigationAuthoring,
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

build_plan : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelFacadePipeline.Limits -> Try(KernelFacadePipeline.Plan, KernelFacadePipeline.Error)
build_plan = |authoring, font, theme, page_size, descriptor, facts, limits| {
	upstream = build_upstream(authoring, font, theme, page_size, descriptor, limits)?
	fragments = KernelFacadeFragments.Plan.build_with_navigation(upstream.preliminary, upstream.text, upstream.navigation, limits.fragments, limits.fragment_semantics, limits.navigation) ? Fragments
	scenes = KernelFacadeScenes.Plan.build_authoring_with_intent(fragments, page_size, authoring, intent_profile(facts), limits.scenes) ? Scenes
	output = KernelFacadeOutput.Plan.build_with_navigation(scenes, font, descriptor, facts, navigation_input(fragments, limits.navigation), limits.output) ? Output
	Ok(
		KernelFacadePipeline.Plan.{
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

build_ordered_pipeline : Document.NormalizedAuthoring, { policy : Font.PolicyId, registry : Font.Registry }, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelFacadePipeline.Limits -> Try(KernelFacadePipeline.Plan, KernelFacadePipeline.Error)
build_ordered_pipeline = |authoring, ordered, theme, page_size, descriptor, facts, limits| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = KernelFacadeShape.Plan.build_ordered(
		KernelFacadeSemantics.Plan.authoring(semantics),
		KernelFacadeSemantics.Plan.block_ownership(semantics),
		KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
		source_store,
		KernelFacadeSemantics.Plan.artifacts(semantics).len(),
		ordered,
		theme,
		limits.shape,
	) ? Shape
	lines = KernelFacadeLines.Plan.build_ordered(shape, source_store, page_size, theme, limits.lines) ? Lines
	pages = KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, limits.pages) ? Pages
	text = KernelFacadeText.Plan.build(shape, lines, pages, limits.text) ? Text
	fragments = KernelFacadeFragments.Plan.build_with_navigation(preliminary, text, navigation_authoring(semantics, authoring), limits.fragments, limits.fragment_semantics, limits.navigation) ? Fragments
	scenes = KernelFacadeScenes.Plan.build_authoring_with_intent(fragments, page_size, authoring, intent_profile(facts), limits.scenes) ? Scenes
	output = KernelFacadeOutput.Plan.build_multi_with_navigation(scenes, KernelFacadeShape.Plan.fonts(shape), descriptor, facts, navigation_input(fragments, limits.navigation), limits.output) ? Output
	shape_store = KernelFacadeShape.Plan.shape(shape).store
	line_store = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines))
	page_store = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages))
	final_store = KernelFacadeText.Plan.text(text)
	Ok(
		KernelFacadePipeline.Plan.{
			output,
			work: {
				blocks: authoring.blocks.len(),
				final_runs: final_store.runs.len(),
				fragments: KernelFacadeFragments.Plan.fragments(fragments).len(),
				lines: line_store.len(),
				objects: KernelFacadeOutput.Plan.work(output).objects,
				occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
				pages: page_store.len(),
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
	upstream = build_upstream(authoring, font, theme, page_size, descriptor, limits)?
	if stage == TextReady {
		return Ok(upstream.work)
	}
	fragments = KernelFacadeFragments.Plan.build(upstream.preliminary, upstream.text, limits.fragments, limits.fragment_semantics) ? Fragments
	fragment_work = { ..upstream.work, fragments: KernelFacadeFragments.Plan.fragments(fragments).len() }
	if stage == FragmentsReady {
		return Ok(fragment_work)
	}
	probe_intent = if authoring.figures.is_empty() NoIntentProfile else PackagedSrgbIntent
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
		final_runs: 0,
		fragments: 0,
		lines: 0,
		objects: 0,
		occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
		pages: 0,
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
		KernelFacadeSemantics.Plan.artifacts(semantics).len(),
		font,
		theme,
		limits.shape,
	) ? Shape
	shape_work = { ..work, shaped_runs: KernelFacadeShape.Plan.shape(shape).store.runs.len() }
	if stage == ShapeReady {
		return Ok(shape_work)
	}
	lines = KernelFacadeLines.Plan.build(shape, source_store, page_size, theme, limits.lines) ? Lines
	line_work = { ..shape_work, lines: KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines)).len() }
	if stage == LinesReady {
		return Ok(line_work)
	}
	pages = KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, limits.pages) ? Pages
	Ok({ ..line_work, pages: KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages)).len() })
}

build_upstream : Document.NormalizedAuthoring, KernelFont.Inspection, Theme, Layout.Size, KernelPdfFont.Descriptor, KernelFacadePipeline.Limits -> Try(Upstream, KernelFacadePipeline.Error)
build_upstream = |authoring, font, theme, page_size, descriptor, limits| {
	semantics = KernelFacadeSemantics.Plan.build(authoring, limits.semantics) ? Semantics
	preliminary = KernelFacadeSemantics.Plan.preliminary(semantics)
	source_store = KernelFacadeSources.Plan.sources(KernelFacadeSemantics.Plan.sources(semantics))
	shape = KernelFacadeShape.Plan.build(
		KernelFacadeSemantics.Plan.authoring(semantics),
		KernelFacadeSemantics.Plan.block_ownership(semantics),
		KernelSemantics.Plan.store(KernelTextSemantics.Plan.semantics(preliminary)),
		source_store,
		KernelFacadeSemantics.Plan.artifacts(semantics).len(),
		font,
		theme,
		limits.shape,
	) ? Shape
	lines = KernelFacadeLines.Plan.build(shape, source_store, page_size, theme, limits.lines) ? Lines
	pages = KernelFacadePages.Plan.build(authoring, shape, lines, page_size, theme, limits.pages) ? Pages
	text = KernelFacadeText.Plan.build(shape, lines, pages, limits.text) ? Text
	shape_store = KernelFacadeShape.Plan.shape(shape).store
	line_store = KernelLineLayout.BatchPlan.lines(KernelFacadeLines.Plan.line(lines))
	page_store = KernelPageLayout.Plan.pages(KernelFacadePages.Plan.page(pages))
	final_store = KernelFacadeText.Plan.text(text)
	Ok({
		descriptor,
		font,
		limits,
		navigation: navigation_authoring(semantics, authoring),
		page_size,
		preliminary,
		text,
		work: {
			blocks: authoring.blocks.len(),
			final_runs: final_store.runs.len(),
			fragments: 0,
			lines: line_store.len(),
			objects: 0,
			occurrences: KernelFacadeSemantics.Plan.work(semantics).occurrence_writes,
			pages: page_store.len(),
			scene_commands: 0,
			shaped_runs: shape_store.runs.len(),
		},
	})
}
