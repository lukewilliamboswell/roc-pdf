import fuzz.Model
import pdf.Color
import pdf.KernelColor
import pdf.KernelFixture
import pdf.KernelForm
import pdf.KernelImage
import pdf.KernelScene
import pdf.KernelSrgbProfile
import pdf.Scene
import pdf.Semantics

FormAmbientTransparencyModel := [].{}

Ambient : [Alpha, Mask, AlphaAndMask]

Boundary : [NoBoundary, Left, Right, Relay, Leaf]

Effect : [Opaque, LocalAlpha, LocalMask]

Action : [Place(Ambient), Isolate(Boundary), Paint(Effect)]

World : { ambient : [Unplaced, Placed(Ambient)], boundary : [Unselected, Selected(Boundary)], effect : [Unpainted, Painted(Effect)] }

Outcome : [Allowed, ConflictingAlpha, ConflictingMask]

machine : { colors : KernelColor.Plan, images : KernelImage.Plan } -> Model.Machine(World, Action)
machine = |stores| {
	init: { ambient: Unplaced, boundary: Unselected, effect: Unpainted },
	actions: |world| match (world.ambient, world.boundary, world.effect) {
		(Unplaced, _, _) => [Place(Alpha), Place(Mask), Place(AlphaAndMask)]
		(_, Unselected, _) => [Isolate(NoBoundary), Isolate(Left), Isolate(Right), Isolate(Relay), Isolate(Leaf)]
		(_, _, Unpainted) => [Paint(Opaque), Paint(LocalAlpha), Paint(LocalMask)]
		_ => []
	},
	step: |world, action| match action {
		Place(ambient) => { ..world, ambient: Placed(ambient) }
		Isolate(boundary) => { ..world, boundary: Selected(boundary) }
		Paint(effect) => { ..world, effect: Painted(effect) }
	},
	rules: [
		Model.always("the Form planner agrees with each authored invocation path", |world| agrees(stores, world)),
		Model.sometimes("isolation on the unmasked branch does not clear the shared leaf's ambient mask", |world| world == { ambient: Placed(Mask), boundary: Selected(Right), effect: Painted(LocalMask) }),
		Model.sometimes("isolating the masked branch allows the shared leaf to apply its own mask", |world| world == { ambient: Placed(Mask), boundary: Selected(Left), effect: Painted(LocalMask) }),
		Model.sometimes("a shared isolated relay clears both ambient channels for its leaf", |world| world == { ambient: Placed(AlphaAndMask), boundary: Selected(Relay), effect: Painted(LocalAlpha) }),
		Model.sometimes("ambient alpha alone is compatible with a local mask", |world| world == { ambient: Placed(Alpha), boundary: Selected(NoBoundary), effect: Painted(LocalMask) }),
	],
}

# ISO 32000-2 §11.6.6 resets the alpha constants and soft mask when
# entering a transparency group. Follow the two authored invocation paths
# separately, including the unmodified right-hand page placement. The
# writer rejects a local override of the same channel on any active path.
expected : Ambient, Boundary, Effect -> Outcome
expected = |ambient, boundary, effect| {
	left_channels = match ambient {
		Alpha => [LocalAlpha]
		Mask => [LocalMask]
		AlphaAndMask => [LocalAlpha, LocalMask]
	}
	paths = [
		{ nodes: [Left, Relay, Leaf], active: left_channels },
		{ nodes: [Right, Relay, Leaf], active: [] },
	]
	conflict = paths.any(|path| !path.nodes.contains(boundary) and path.active.contains(effect))
	match (conflict, effect) {
		(True, LocalAlpha) => ConflictingAlpha
		(True, LocalMask) => ConflictingMask
		_ => Allowed
	}
}

agrees : { colors : KernelColor.Plan, images : KernelImage.Plan }, World -> Bool
agrees = |stores, world| match (world.ambient, world.boundary, world.effect) {
	(Placed(ambient), Selected(boundary), Painted(effect)) => {
		outcome = expected(ambient, boundary, effect)
		match planned(stores, ambient, boundary, effect) {
			Ok(facts) => outcome == Allowed and KernelForm.Facts.work(facts).transparency_pages == 1
			Err(FormFailure(FormOpacityInAmbient({ form }))) => outcome == ConflictingAlpha and form == 3
			Err(FormFailure(FormMaskInAmbient({ form }))) => outcome == ConflictingMask and form == 3
			Err(_) => False
		}
	}
	_ => True
}

Failure : [FormFailure(KernelForm.Error), SceneFailure(KernelScene.Error)]

planned : { colors : KernelColor.Plan, images : KernelImage.Plan }, Ambient, Boundary, Effect -> Try(KernelForm.Facts, Failure)
planned = |stores, ambient, boundary, effect| {
	scene = authored_scene(ambient)
	forms = authored_forms(ambient, boundary, effect)
	resources = KernelScene.Resources.with_forms({ color_spaces: 1, forms: forms.forms.len(), images: 0, text_runs: 0 })
	plan = KernelScene.FormPlan.build(
		scene,
		forms,
		resources,
		KernelScene.Limits.make({ max_commands: 4, max_dash_lengths: 0, max_graphics_depth: 3, max_groups: 1, max_pages: 1, max_path_segments: 1, max_paths: 1 }),
		KernelScene.FormLimits.make({ max_form_commands: 6, max_forms: 5 }),
	) ? SceneFailure
	facts = KernelForm.Facts.build(plan, { colors: stores.colors, font_count: 0, images: stores.images }, NoTextStore, limits) ? FormFailure
	Ok(facts)
}

authored_scene : Ambient -> Scene.Store
authored_scene = |ambient| {
	template = KernelFixture.scene
	page = template.pages.first() ?? crash "missing fixture page"
	commands = match ambient {
		Alpha => [alpha(2), place(1), place(0)]
		Mask => [mask(2), place(1), place(0)]
		AlphaAndMask => [alpha(2), place(1), mask(3), place(0)]
	}
	{
		..template,
		commands,
		groups: [{ commands: range(0, 2), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
		page_groups: [Scene.GroupId.from_index(0)],
		pages: [{ ..page, paint_order: range(0, 1) }],
	}
}

authored_forms : Ambient, Boundary, Effect -> Scene.FormStore
authored_forms = |ambient, boundary, effect| {
	draw = DrawPath({ path: Scene.PathId.from_index(0), style: { fill: SolidFill({ color: { channels: Rgb({ red: 0, green: 0, blue: 0 }), space: Color.SpaceId.from_index(0) }, rule: Nonzero }), stroke: NoStroke } })
	leaf = match effect {
		Opaque => [draw]
		LocalAlpha => [alpha(4), draw]
		LocalMask => [mask(4), draw]
	}
	box = KernelFixture.rect(0, 0, 1000, 1000)
	ordinary = [Left, Right, Relay, Leaf].map_with_index(
		|node, index| {
			bbox: box,
			commands: range(index, 1),
			group: if (node == boundary) IsolatedGroup else NoGroup,
			id: Scene.FormId.from_index(index),
		},
	)
	commands = [place(2), place(2), place(3)].concat(leaf)
	if ambient != Alpha or effect == LocalMask {
		{
			commands: commands.append(draw),
			forms: ordinary.append({ bbox: box, commands: range(commands.len(), 1), group: IsolatedGroup, id: Scene.FormId.from_index(4) }),
		}
	} else {
		{ commands, forms: ordinary }
	}
}

range : U64, U64 -> Semantics.IndexRange
range = |start, length| Semantics.IndexRange.from_start_and_length({ start, length })

place : U64 -> Scene.Command
place = |id| {
	zero = KernelFixture.unit(0)
	one = KernelFixture.unit(1000)
	PlaceForm({ form: Scene.FormId.from_index(id), transform: { a: one, b: zero, c: zero, d: one, e: zero, f: zero } })
}

alpha : U64 -> Scene.Command
alpha = |child| Opacity({ opacity: 32768, children: range(child, 1) })

mask : U64 -> Scene.Command
mask = |child| SoftMask({ children: range(child, 1), mask: Scene.FormId.from_index(4) })

limits : KernelForm.Limits
limits = KernelForm.Limits.make({
	graph: { max_collision_entries: 16, max_edges: 32, max_equality_bytes: 1024, max_hash_bytes: 1024, max_hashes: 32, max_ordering_work: 1024, max_payload_bytes: 1024, max_placements: 32, max_resources: 16, max_root_uses: 16, max_roots: 1, max_topological_work: 1024 },
	max_mask_depth: 1,
	max_opacity_depth: 2,
	max_recipe_bytes: 1024,
})

expect {
	colors = KernelColor.Plan.build(
		{ profiles: [KernelSrgbProfile.profile(0, 0)], spaces: [{ id: Color.SpaceId.from_index(0), space: Srgb(Color.ProfileId.from_index(0)) }], tags: KernelSrgbProfile.tags },
		KernelColor.Limits.make({ max_icc_bytes: KernelSrgbProfile.byte_count, max_profiles: 1, max_spaces: 1, max_tags: KernelSrgbProfile.tag_count }),
	) ?? crash "invalid sRGB fixture"
	images = KernelImage.Plan.build(
		{ resources: [] },
		colors,
		KernelImage.Limits.make({ max_decoded_bytes: 0, max_encoded_bytes: 0, max_height: 0, max_markers: 0, max_resources: 0, max_width: 0 }),
	) ?? crash "invalid empty image fixture"
	report = Model.explore(machine({ colors, images }), { depth: 4, key: |world| world, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 64 and report.steps == 63 and report.depth == 3 and report.reached.len() == 4
}
