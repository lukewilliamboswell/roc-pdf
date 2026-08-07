import KernelColor
import KernelContent
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelGate2Identity
import KernelGate2Objects
import KernelGate2OutputBound
import KernelGate2PageObjects
import KernelGate2ResourceObjects
import KernelGate2TaggedObjects
import KernelGate3FontObjects
import KernelImage
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelStructure
import KernelTagged

KernelGate3TaggedTextStructure :: [].{
	Error : [
		ArithmeticOverflow,
		Font(KernelPdfFont.Error),
		FontCountMismatch({ fonts : U64, mappings : U64, planned : U64 }),
		Identity(KernelGate2Identity.Error),
		ObjectCountMismatch({ actual : U64, expected : U64 }),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
		OutputBound(KernelGate2OutputBound.Error),
		Pages(KernelGate2PageObjects.Error),
		Resources(KernelGate2ResourceObjects.Error),
		Seal(KernelSeal.Error),
		TaggedObjects(KernelGate2TaggedObjects.Error),
	]

	FontInput : {
		descriptor : KernelPdfFont.Descriptor,
		font : KernelFont.Inspection,
		plan : KernelFontPlan.Plan,
		subset : KernelFontSubset.Subset,
	}

	Limits :: { font_limits : KernelPdfFont.Limits, object_limits : KernelObject.Limits }.{
		make : { font_limits : KernelPdfFont.Limits, object_limits : KernelObject.Limits } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : {
		content_bytes : U64,
		font_objects : U64,
		font_program_bytes : U64,
		fonts : U64,
		objects : U64,
		pages : KernelGate2PageObjects.Work,
		resources : KernelGate2ResourceObjects.Work,
		tagged_objects : KernelGate2TaggedObjects.Work,
	}

	Plan :: { font_objects : List(KernelPdfFont.Objects), structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelGate3FontObjects.Plan, KernelPdfText.ScenePlan, List(FontInput), Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, objects, text, fonts, limits| build_plan(tagged, colors, images, content, objects, text, fonts, limits)

		font_objects : Plan -> List(KernelPdfFont.Objects)
		font_objects = |plan| plan.font_objects

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelGate3FontObjects.Plan, KernelPdfText.ScenePlan, List(KernelGate3TaggedTextStructure.FontInput), KernelGate3TaggedTextStructure.Limits -> Try(KernelGate3TaggedTextStructure.Plan, KernelGate3TaggedTextStructure.Error)
build_plan = |tagged, colors, images, content, font_plan, text, fonts, limits| {
	planned_fonts = KernelGate3FontObjects.Plan.fonts(font_plan)
	mappings = KernelPdfText.ScenePlan.mappings(text)
	if fonts.len() == 0 or fonts.len() != mappings.len() or fonts.len() != planned_fonts.len() {
		return Err(FontCountMismatch({ fonts: fonts.len(), mappings: mappings.len(), planned: planned_fonts.len() }))
	}
	objects = KernelGate3FontObjects.Plan.base(font_plan)
	prefix = KernelGate2TaggedObjects.Plan.build(tagged, objects, limits.object_limits) ? TaggedObjects
	pages = KernelGate2PageObjects.Plan.build_with_fonts(prefix, tagged, content, font_plan) ? Pages
	resources = KernelGate2ResourceObjects.Plan.build(pages, colors, images, objects) ? Resources
	var $builder = KernelGate2ResourceObjects.Plan.builder(resources)
	var $font_objects = List.with_capacity(fonts.len())
	var $font_bytes = 0
	var $font_index = 0
	while $font_index < fonts.len() {
		input = list_at(fonts, $font_index)
		font = KernelPdfFont.Plan.build(
			$builder,
			input.font,
			input.plan,
			input.subset,
			input.descriptor,
			list_at(mappings, $font_index),
			limits.font_limits,
		) ? Font
		emitted = KernelPdfFont.Plan.objects(font)
		planned = list_at(planned_fonts, $font_index)
		ensure_object(emitted.font_file, planned.first)?
		ensure_object(emitted.type0, planned.type0)?
		$builder = KernelPdfFont.Plan.builder(font)
		$font_objects = $font_objects.append(emitted)
		$font_bytes = checked_add($font_bytes, KernelPdfFont.Plan.work(font).font_program_bytes)?
		$font_index = $font_index + 1
	}
	expected = KernelGate3FontObjects.Plan.object_count(font_plan)
	if $builder.store.objects.len() != expected {
		return Err(ObjectCountMismatch({ actual: $builder.store.objects.len(), expected }))
	}
	sealed = KernelSeal.seal($builder) ? Seal
	identity = KernelGate2Identity.digest(sealed) ? Identity
	bound = KernelGate2OutputBound.calculate(sealed, KernelGate3FontObjects.Plan.xref(font_plan)) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelGate2OutputBound.Bound.bytes(bound),
		page_count: KernelTagged.Plan.scenes(tagged).pages.len(),
		root: KernelGate2Objects.Plan.catalog(objects),
		sealed,
		tree_nodes: KernelGate2Objects.Plan.page_tree(objects).len(),
		xref_object: KernelGate3FontObjects.Plan.xref(font_plan),
	})
	Ok(
		KernelGate3TaggedTextStructure.Plan.{
			font_objects: $font_objects,
			structure,
			work: {
				content_bytes: KernelContent.Plan.work(content).bytes_emitted,
				font_objects: KernelGate3FontObjects.Plan.work(font_plan).font_objects,
				font_program_bytes: $font_bytes,
				fonts: fonts.len(),
				objects: expected,
				pages: KernelGate2PageObjects.Plan.work(pages),
				resources: KernelGate2ResourceObjects.Plan.work(resources),
				tagged_objects: KernelGate2TaggedObjects.Plan.work(prefix),
			},
		},
	)
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelGate3TaggedTextStructure.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

checked_add : U64, U64 -> Try(U64, KernelGate3TaggedTextStructure.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated tagged text-structure index escaped"
	}
	Ok(value) => value
}
