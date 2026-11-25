import fuzz.Model
import pdf.Color
import pdf.Image
import pdf.KernelColor
import pdf.KernelFixture
import pdf.KernelForm
import pdf.KernelImage
import pdf.KernelScene
import pdf.Scene
import pdf.Semantics

AppearanceTransparencyModel := [].{}

Leaf : [Opaque, ConstantAlpha, Isolated, ImageMask]

Owners : [FirstPage, SecondPage, BothPages, RepeatedSecondPage]

Action : [Paint(Leaf), Wrap, Attach(Owners)]

World : { leaf : [NoLeaf, Leaf(Leaf)], owners : [Unattached, Owners(Owners)], wrappers : U64 }

machine : Model.Machine(World, Action)
machine = {
	init: { leaf: NoLeaf, owners: Unattached, wrappers: 0 },
	actions: |world| match (world.leaf, world.owners) {
		(NoLeaf, _) => [Paint(Opaque), Paint(ConstantAlpha), Paint(Isolated), Paint(ImageMask)]
		(_, Owners(_)) => []
		(_, Unattached) => {
			attachments = [Attach(FirstPage), Attach(SecondPage), Attach(BothPages), Attach(RepeatedSecondPage)]
			if (world.wrappers == 2) attachments else attachments.append(Wrap)
		}
	},
	step: |world, action| match action {
		Paint(leaf) => { ..world, leaf: Leaf(leaf) }
		Wrap => { ..world, wrappers: world.wrappers + 1 }
		Attach(owners) => { ..world, owners: Owners(owners) }
	},
	rules: [
		Model.always("the first page needing a blend space agrees with the annotation appearances", agrees),
		Model.sometimes("a nested image mask needs blending only on the second page", |world| world.leaf == Leaf(ImageMask) and world.wrappers == 2 and world.owners == Owners(RepeatedSecondPage)),
		Model.sometimes("an isolated leaf needs blending even without alpha", |world| world.leaf == Leaf(Isolated) and world.owners == Owners(BothPages)),
		Model.sometimes("an opaque nested appearance does not require blending", |world| world.leaf == Leaf(Opaque) and world.wrappers == 2 and world.owners == Owners(SecondPage)),
	],
}

# Annex Q.2 starts at each annotation's appearance. The only painted leaf
# in the authored chain either contributes one of the Q.2–Q.4 facts or none.
# With no blend space, the planner must identify the first affected page.
agrees : World -> Bool
agrees = |world| match (world.leaf, world.owners) {
	(Leaf(leaf), Owners(owners)) => {
		uses = match owners {
			FirstPage => [0]
			SecondPage => [1]
			BothPages => [1, 0]
			RepeatedSecondPage => [1, 1]
		}
		first_page = if (uses.contains(0)) 0 else 1
		match planned(leaf, world.wrappers, uses) {
			Ok(facts) => leaf == Opaque and KernelForm.Facts.work(facts).transparency_pages == 0
			Err(FormFailure(MissingBlendingSpace({ page }))) => leaf != Opaque and page == first_page
			Err(_) => False
		}
	}
	_ => True
}

Failure : [ColorFailure(KernelColor.Error), FormFailure(KernelForm.Error), ImageFailure(KernelImage.Error), SceneFailure(KernelScene.Error)]

planned : Leaf, U64, List(U64) -> Try(KernelForm.Facts, Failure)
planned = |leaf, wrappers, pages| {
	scene = blank_pages({})
	forms = appearance_forms(leaf, wrappers)
	resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: forms.forms.len(), images: if (leaf == ImageMask) 1 else 0, text_runs: 0 })
	paint = KernelScene.PaintPlan.build(
		scene,
		forms,
		Scene.no_shadings,
		Scene.no_patterns,
		resources,
		KernelScene.Limits.make({ max_commands: 0, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 0, max_pages: 2, max_path_segments: 1, max_paths: 1 }),
		KernelScene.FormLimits.make({ max_form_commands: 4, max_forms: 3 }),
		KernelScene.PaintLimits.make({ max_pattern_commands: 0, max_patterns: 0, max_shading_stops: 0, max_shadings: 0 }),
	) ? SceneFailure
	colors = KernelColor.Plan.build(
		{ profiles: [], spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }], tags: [] },
		KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 }),
	) ? ColorFailure
	images = KernelImage.Plan.build(
		{ resources: if (leaf == ImageMask) [masked_image] else [] },
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 2, max_encoded_bytes: 0, max_height: 1, max_markers: 0, max_resources: 1, max_width: 1 }),
	) ? ImageFailure
	facts = KernelForm.Facts.build_with_navigation(paint, { colors, font_count: 0, images }, NoTextStore, pages.map(|page| { page, form: 0 }), limits) ? FormFailure
	Ok(facts)
}

blank_pages : {} -> Scene.Store
blank_pages = |_| {
	template = KernelFixture.scene
	page = template.pages.first() ?? crash "empty fixture pages"
	{ ..template, commands: [], groups: [], page_groups: [], pages: [0, 1].map(|index| { ..page, id: Semantics.PageId.from_index(index), paint_order: KernelFixture.empty_range }) }
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

appearance_forms : Leaf, U64 -> Scene.FormStore
appearance_forms = |leaf, wrappers| {
	box = KernelFixture.rect(0, 0, 10000, 10000)
	identity = { a: KernelFixture.unit(1000), b: KernelFixture.unit(0), c: KernelFixture.unit(0), d: KernelFixture.unit(1000), e: KernelFixture.unit(0), f: KernelFixture.unit(0) }
	callers = List.repeat({}, wrappers).map_with_index(|_, index| PlaceForm({ form: Scene.FormId.from_index(index + 1), transform: identity }))
	path = DrawPath({ path: Scene.PathId.from_index(0), style: { fill: SolidFill({ color: { channels: Gray(32768), space: Color.SpaceId.from_index(0) }, rule: Nonzero }), stroke: NoStroke } })
	draw = match leaf {
		ConstantAlpha => [Opacity({ opacity: 32768, children: range(wrappers + 1, 1) }), path]
		ImageMask => [DrawImage({ image: Image.Id.from_index(0), placement: box })]
		Opaque | Isolated => [path]
	}
	{
		commands: callers.concat(draw),
		forms: List.repeat({}, wrappers + 1).map_with_index(
			|_, index| {
				bbox: box,
				commands: range(index, 1),
				group: if (index == wrappers and leaf == Isolated) IsolatedGroup else NoGroup,
				id: Scene.FormId.from_index(index),
			},
		),
	}
}

masked_image : Image.SourceResource
masked_image = {
	id: Image.Id.from_index(0),
	payload: PackedPixels({ alpha: PackedAlpha({ bytes: [128], row_stride: 1 }), color_space: Color.SpaceId.from_index(0), dimensions: { height: 1, width: 1 }, format: Gray8, pixels: [64], row_stride: 1 }),
}

limits : KernelForm.Limits
limits = KernelForm.Limits.make({
	graph: { max_collision_entries: 16, max_edges: 32, max_equality_bytes: 1024, max_hash_bytes: 1024, max_hashes: 32, max_ordering_work: 1024, max_payload_bytes: 1024, max_placements: 32, max_resources: 16, max_root_uses: 16, max_roots: 2, max_topological_work: 1024 },
	max_mask_depth: 1,
	max_opacity_depth: 2,
	max_recipe_bytes: 1024,
})

expect {
	report = Model.explore(machine, { depth: 5, key: |world| (world.leaf, world.owners, world.wrappers), verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 61 and report.depth == 4 and report.steps == 60 and report.reached.len() == 3
}
