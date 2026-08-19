import Image
import KernelContent
import KernelFacadeScenes
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelObjectPlan
import KernelFontObjects
import KernelTaggedTextStructure
import KernelImage
import KernelMetadata
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelResourceUse
import KernelStructure
import KernelTextOwnership
import Text

KernelFacadeOutput :: [].{
	Error : [
		Content(KernelContent.Error),
		FontObjects(KernelFontObjects.Error),
		FontPlan(KernelFontPlan.Error),
		Images(KernelImage.Error),
		Objects(KernelObjectPlan.Error),
		Resources(KernelResourceUse.Error),
		Structure(KernelTaggedTextStructure.Error),
		Subset(KernelFontSubset.Error),
		Text(KernelPdfText.Error),
	]

	Limits :: {
		content : KernelContent.Limits,
		font_plan : KernelFontPlan.Limits,
		images : KernelImage.Limits,
		max_objects : U64,
		objects : KernelObjectPlan.Limits,
		structure : KernelTaggedTextStructure.Limits,
		text : KernelPdfText.Limits,
	}.{
		make : {
			content : KernelContent.Limits,
			font_plan : KernelFontPlan.Limits,
			images : KernelImage.Limits,
			max_objects : U64,
			objects : KernelObjectPlan.Limits,
			structure : KernelTaggedTextStructure.Limits,
			text : KernelPdfText.Limits,
		} -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		content_bytes : U64,
		content_command_visits : U64,
		font_entries : U64,
		font_objects : U64,
		glyph_usages : U64,
		metadata_bytes : U64,
		objects : U64,
		resource_command_visits : U64,
		subset_bytes : U64,
		text_content_bytes : U64,
		text_glyph_visits : U64,
		text_runs : U64,
	}

	Plan :: { structure : KernelStructure.Plan, work : Work }.{
		build : KernelFacadeScenes.Plan, KernelFont.Inspection, KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build = |scenes, font, descriptor, limits| build_plan(scenes, font, descriptor, NoDocumentFacts, NoNavigation, limits)

		## Document facts flow through unchanged to structure planning, which
		## appends the canonical XMP stream and catalog entries.
		build_with_facts : KernelFacadeScenes.Plan, KernelFont.Inspection, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_with_facts = |scenes, font, descriptor, facts, limits| build_plan(scenes, font, descriptor, facts, NoNavigation, limits)

		## Navigation input flows through unchanged to structure planning,
		## which resolves destinations and lowers the navigation objects.
		build_with_navigation : KernelFacadeScenes.Plan, KernelFont.Inspection, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelTaggedTextStructure.NavigationInput, Limits -> Try(Plan, Error)
		build_with_navigation = |scenes, font, descriptor, facts, navigation, limits| build_plan(scenes, font, descriptor, facts, navigation, limits)

		## Ordered multi-face output. Dense font index k owns one plan, one
		## sanitized subset, and the `F1_k` resource; a one-font list delegates
		## to the exact single-face path above.
		build_multi : KernelFacadeScenes.Plan, List(KernelFont.Inspection), KernelPdfFont.Descriptor, Limits -> Try(Plan, Error)
		build_multi = |scenes, fonts, descriptor, limits| build_multi_plan(scenes, fonts, descriptor, NoDocumentFacts, NoNavigation, limits)

		build_multi_with_facts : KernelFacadeScenes.Plan, List(KernelFont.Inspection), KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_multi_with_facts = |scenes, fonts, descriptor, facts, limits| build_multi_plan(scenes, fonts, descriptor, facts, NoNavigation, limits)

		build_multi_with_navigation : KernelFacadeScenes.Plan, List(KernelFont.Inspection), KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelTaggedTextStructure.NavigationInput, Limits -> Try(Plan, Error)
		build_multi_with_navigation = |scenes, fonts, descriptor, facts, navigation, limits| build_multi_plan(scenes, fonts, descriptor, facts, navigation, limits)

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelFacadeScenes.Plan, KernelFont.Inspection, KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelTaggedTextStructure.NavigationInput, KernelFacadeOutput.Limits -> Try(KernelFacadeOutput.Plan, KernelFacadeOutput.Error)
build_plan = |scenes, font, descriptor, facts, navigation, limits| {
	ownership = KernelFacadeScenes.Plan.ownership(scenes)
	scene = KernelFacadeScenes.Plan.scene(scenes)
	colors = KernelFacadeScenes.Plan.colors(scenes)
	text_store = KernelTextOwnership.Plan.text(ownership)
	usages = glyph_usages(text_store.glyphs)
	font_plan = KernelFontPlan.plan(font, usages, limits.font_plan) ? FontPlan
	subset = KernelFontSubset.build(font, font_plan) ? Subset
	images = KernelImage.Plan.build({ resources: [] }, colors, limits.images) ? Images
	resource_use = KernelResourceUse.TextPlan.build(scene, colors, images) ? Resources
	text = KernelPdfText.ScenePlan.build(ownership, [font_plan], limits.text) ? Text
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	content = KernelContent.Plan.build_with_text(tagged, KernelPdfText.ScenePlan.content(text), limits.content) ? Content
	objects = KernelObjectPlan.Plan.build_with_text(tagged, colors, images, resource_use, content, limits.objects) ? Objects
	font_objects = KernelFontObjects.Plan.build(objects, 1, limits.max_objects) ? FontObjects
	structure = KernelTaggedTextStructure.Plan.build_with_navigation(
		tagged,
		colors,
		images,
		content,
		font_objects,
		text,
		[{ descriptor, font, plan: font_plan, subset }],
		facts,
		navigation,
		limits.structure,
	) ? Structure
	content_work = KernelContent.Plan.work(content)
	resource_work = KernelResourceUse.TextPlan.work(resource_use)
	text_work = KernelPdfText.ScenePlan.work(text)
	structure_work = KernelTaggedTextStructure.Plan.work(structure)
	Ok(
		KernelFacadeOutput.Plan.{
			structure: KernelTaggedTextStructure.Plan.structure(structure),
			work: {
				content_bytes: content_work.bytes_emitted,
				content_command_visits: content_work.command_visits,
				font_entries: font_plan.entries.len(),
				font_objects: structure_work.font_objects,
				glyph_usages: usages.len(),
				metadata_bytes: structure_work.metadata_bytes,
				objects: structure_work.objects,
				resource_command_visits: resource_work.command_visits,
				subset_bytes: subset.work.output_bytes,
				text_content_bytes: text_work.content_bytes,
				text_glyph_visits: text_work.glyph_visits,
				text_runs: text_work.run_visits,
			},
		},
	)
}

build_multi_plan : KernelFacadeScenes.Plan, List(KernelFont.Inspection), KernelPdfFont.Descriptor, KernelMetadata.PlanFacts, KernelTaggedTextStructure.NavigationInput, KernelFacadeOutput.Limits -> Try(KernelFacadeOutput.Plan, KernelFacadeOutput.Error)
build_multi_plan = |scenes, fonts, descriptor, facts, navigation, limits| {
	if fonts.len() == 1 {
		return build_plan(scenes, list_at(fonts, 0), descriptor, facts, navigation, limits)
	}
	ownership = KernelFacadeScenes.Plan.ownership(scenes)
	scene = KernelFacadeScenes.Plan.scene(scenes)
	colors = KernelFacadeScenes.Plan.colors(scenes)
	text_store = KernelTextOwnership.Plan.text(ownership)

	## Glyph usage ownership is the run's exact dense instance fact; grouping
	## never re-derives a font from coverage or glyph IDs.
	var $usages_per_font = List.repeat([], fonts.len())
	var $total_usages = 0
	var $run_index = 0
	while $run_index < text_store.runs.len() {
		run = list_at(text_store.runs, $run_index)
		font_index = run.instance.index()
		if font_index >= fonts.len() {
			return Err(Text(FontPlanInvalid({ font: font_index })))
		}
		glyph_end = run.glyphs.start() + run.glyphs.length()
		if run.glyphs.start() > text_store.glyphs.len() or glyph_end > text_store.glyphs.len() {
			return Err(Text(RunInvalid({ run: $run_index })))
		}
		var $usages = list_at($usages_per_font, font_index)
		var $glyph_index = run.glyphs.start()
		while $glyph_index < glyph_end {
			$usages = $usages.append({ glyph: list_at(text_store.glyphs, $glyph_index).id.raw() })
			$total_usages = $total_usages + 1
			$glyph_index = $glyph_index + 1
		}
		$usages_per_font = list_set($usages_per_font, font_index, $usages)
		$run_index = $run_index + 1
	}

	var $font_plans = List.with_capacity(fonts.len())
	var $embedded = List.with_capacity(fonts.len())
	var $font_entries = 0
	var $subset_bytes = 0
	var $font_index = 0
	while $font_index < fonts.len() {
		font = list_at(fonts, $font_index)
		font_plan = KernelFontPlan.plan(font, list_at($usages_per_font, $font_index), limits.font_plan) ? FontPlan
		subset = KernelFontSubset.build(font, font_plan) ? Subset
		$font_entries = $font_entries + font_plan.entries.len()
		$subset_bytes = $subset_bytes + subset.work.output_bytes
		$font_plans = $font_plans.append(font_plan)
		$embedded = $embedded.append({ descriptor, font, plan: font_plan, subset })
		$font_index = $font_index + 1
	}

	images = KernelImage.Plan.build({ resources: [] }, colors, limits.images) ? Images
	resource_use = KernelResourceUse.TextPlan.build(scene, colors, images) ? Resources
	text = KernelPdfText.ScenePlan.build(ownership, $font_plans, limits.text) ? Text
	tagged = KernelTextOwnership.Plan.tagged(ownership)
	content = KernelContent.Plan.build_with_text(tagged, KernelPdfText.ScenePlan.content(text), limits.content) ? Content
	objects = KernelObjectPlan.Plan.build_with_text(tagged, colors, images, resource_use, content, limits.objects) ? Objects
	font_objects = KernelFontObjects.Plan.build(objects, fonts.len(), limits.max_objects) ? FontObjects
	structure = KernelTaggedTextStructure.Plan.build_with_navigation(
		tagged,
		colors,
		images,
		content,
		font_objects,
		text,
		$embedded,
		facts,
		navigation,
		limits.structure,
	) ? Structure
	content_work = KernelContent.Plan.work(content)
	resource_work = KernelResourceUse.TextPlan.work(resource_use)
	text_work = KernelPdfText.ScenePlan.work(text)
	structure_work = KernelTaggedTextStructure.Plan.work(structure)
	Ok(
		KernelFacadeOutput.Plan.{
			structure: KernelTaggedTextStructure.Plan.structure(structure),
			work: {
				content_bytes: content_work.bytes_emitted,
				content_command_visits: content_work.command_visits,
				font_entries: $font_entries,
				font_objects: structure_work.font_objects,
				glyph_usages: $total_usages,
				metadata_bytes: structure_work.metadata_bytes,
				objects: structure_work.objects,
				resource_command_visits: resource_work.command_visits,
				subset_bytes: $subset_bytes,
				text_content_bytes: text_work.content_bytes,
				text_glyph_visits: text_work.glyph_visits,
				text_runs: text_work.run_visits,
			},
		},
	)
}

glyph_usages : List(Text.Glyph) -> List(KernelFontPlan.Usage)
glyph_usages = |glyphs| {
	var $usages = List.with_capacity(glyphs.len())
	var $index = 0
	while $index < glyphs.len() {
		$usages = $usages.append({ glyph: list_at(glyphs, $index).id.raw() })
		$index = $index + 1
	}
	$usages
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated facade-output index escaped"
	}
	Ok(value) => value
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Err(OutOfBounds) => {
		crash "validated facade-output write escaped"
	}
	Ok(updated) => updated
}
