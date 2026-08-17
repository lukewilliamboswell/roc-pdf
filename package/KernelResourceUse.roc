import Color
import Image
import KernelColor
import KernelImage
import KernelScene
import Layout
import Scene
import Semantics

KernelResourceUse :: [].{
	IndexKind : [ColorSpaceIndex, ImageIndex]
	Error : [
		ArithmeticOverflow,
		ColorComponentMismatch({ actual : Color.ComponentCount, command : U64, expected : Color.ComponentCount, space : U64 }),
		CountMismatch({ actual : U64, declared : U64, kind : IndexKind }),
		OrphanResource({ index : U64, kind : IndexKind }),

		## A gradient stop's channel arity must match the shading's declared
		## validated color space.
		ShadingStopComponentMismatch({ actual : Color.ComponentCount, expected : Color.ComponentCount, shading : U64, stop : U64 }),
	]

	Work : {
		color_space_resources : U64,
		command_visits : U64,
		image_color_references : U64,
		image_placements : U64,
		image_resources : U64,
		image_reuses : U64,
		path_color_references : U64,
	}

	## Counts retain direct normalized resource use without scanning emitted PDF
	## operators. Image payload bytes remain owned only by `KernelImage.Plan`.
	Plan :: {
		color_use_counts : List(U64),
		image_use_counts : List(U64),
		work : Work,
	}.{
		build : KernelScene.Plan, KernelColor.Plan, KernelImage.Plan -> Try(Plan, Error)
		build = |scenes, colors, images| build_plan(scenes, colors, images)

		color_use_count : Plan, Color.SpaceId -> U64
		color_use_count = |plan, space| list_at(plan.color_use_counts, space.index())

		image_use_count : Plan, Image.Id -> U64
		image_use_count = |plan, image| list_at(plan.image_use_counts, image.index())

		work : Plan -> Work
		work = |plan| plan.work
	}

	TextWork : {
		color_space_resources : U64,
		command_visits : U64,
		image_color_references : U64,
		image_placements : U64,
		image_resources : U64,
		image_reuses : U64,
		path_color_references : U64,
		text_color_references : U64,
	}

	TextPlan :: {
		color_use_counts : List(U64),
		image_use_counts : List(U64),
		work : TextWork,
	}.{
		build : KernelScene.Plan, KernelColor.Plan, KernelImage.Plan -> Try(TextPlan, Error)
		build = |scenes, colors, images| build_text_plan(scenes, [], [], NoShadings, colors, images, NoBlending)

		## Gate 4 scenes count direct use across the page and form command
		## arenas, so a resource used only inside form content is not an
		## orphan.
		build_with_forms : KernelScene.FormPlan, KernelColor.Plan, KernelImage.Plan -> Try(TextPlan, Error)
		build_with_forms = |form_plan, colors, images| build_text_plan(
			KernelScene.FormPlan.page(form_plan),
			KernelScene.FormPlan.forms(form_plan).commands,
			[],
			NoShadings,
			colors,
			images,
			NoBlending,
		)

		## The transparency-aware variant: the page transparency group's
		## `/CS` reference is a genuine use of the blending space, so a space
		## referenced only by transparency groups is not an orphan.
		build_with_forms_and_blending : KernelScene.FormPlan, KernelColor.Plan, KernelImage.Plan, [Blending(U64), NoBlending] -> Try(TextPlan, Error)
		build_with_forms_and_blending = |form_plan, colors, images, blending| build_text_plan(
			KernelScene.FormPlan.page(form_plan),
			KernelScene.FormPlan.forms(form_plan).commands,
			[],
			NoShadings,
			colors,
			images,
			blending,
		)

		## The paint-aware variant: pattern-cell commands count direct use
		## like page and form content, and every shading credits its color
		## space once while its stop channels are validated against that
		## space's arity — so a space referenced only through gradient stops
		## is not an orphan.
		build_with_paints : KernelScene.PaintPlan, KernelColor.Plan, KernelImage.Plan, [Blending(U64), NoBlending] -> Try(TextPlan, Error)
		build_with_paints = |paint_plan, colors, images, blending| build_text_plan(
			KernelScene.FormPlan.page(KernelScene.PaintPlan.forms(paint_plan)),
			KernelScene.FormPlan.forms(KernelScene.PaintPlan.forms(paint_plan)).commands,
			KernelScene.PaintPlan.patterns(paint_plan).commands,
			WithShadings(KernelScene.PaintPlan.shadings(paint_plan)),
			colors,
			images,
			blending,
		)

		work : TextPlan -> TextWork
		work = |plan| plan.work
	}
}

CommandUse := {
	color_counts : List(U64),
	image_counts : List(U64),
	image_placements : U64,
	path_colors : U64,
}

TextCommandUse := {
	color_counts : List(U64),
	image_counts : List(U64),
	image_placements : U64,
	path_colors : U64,
	text_colors : U64,
}

build_plan : KernelScene.Plan, KernelColor.Plan, KernelImage.Plan -> Try(KernelResourceUse.Plan, KernelResourceUse.Error)
build_plan = |scene_plan, color_plan, image_plan| {
	declared = KernelScene.Plan.resources(scene_plan)
	color_count = KernelColor.Plan.space_count(color_plan)
	image_count = KernelImage.Plan.resource_count(image_plan)
	if KernelScene.Resources.color_space_count(declared) != color_count {
		Err(CountMismatch({ actual: color_count, declared: KernelScene.Resources.color_space_count(declared), kind: ColorSpaceIndex }))
	} else if KernelScene.Resources.image_count(declared) != image_count {
		Err(CountMismatch({ actual: image_count, declared: KernelScene.Resources.image_count(declared), kind: ImageIndex }))
	} else {
		scenes = KernelScene.Plan.scenes(scene_plan)
		command_use = collect_command_use(scenes.commands, color_plan, color_count, image_count)?
		with_images = collect_image_colors(KernelImage.Plan.store(image_plan), command_use.color_counts)?
		ensure_used(command_use.image_counts, ImageIndex)?
		ensure_used(with_images.color_counts, ColorSpaceIndex)?
		image_reuses = checked_sub(command_use.image_placements, image_count)?
		Ok(
			KernelResourceUse.Plan.{
				color_use_counts: with_images.color_counts,
				image_use_counts: command_use.image_counts,
				work: {
					color_space_resources: color_count,
					command_visits: scenes.commands.len(),
					image_color_references: with_images.image_colors,
					image_placements: command_use.image_placements,
					image_resources: image_count,
					image_reuses,
					path_color_references: command_use.path_colors,
				},
			},
		)
	}
}

build_text_plan : KernelScene.Plan, List(Scene.Command), List(Scene.Command), [NoShadings, WithShadings(Scene.ShadingStore)], KernelColor.Plan, KernelImage.Plan, [Blending(U64), NoBlending] -> Try(KernelResourceUse.TextPlan, KernelResourceUse.Error)
build_text_plan = |scene_plan, form_commands, pattern_commands, shadings, color_plan, image_plan, blending| {
	declared = KernelScene.Plan.resources(scene_plan)
	color_count = KernelColor.Plan.space_count(color_plan)
	image_count = KernelImage.Plan.resource_count(image_plan)
	if KernelScene.Resources.color_space_count(declared) != color_count {
		Err(CountMismatch({ actual: color_count, declared: KernelScene.Resources.color_space_count(declared), kind: ColorSpaceIndex }))
	} else if KernelScene.Resources.image_count(declared) != image_count {
		Err(CountMismatch({ actual: image_count, declared: KernelScene.Resources.image_count(declared), kind: ImageIndex }))
	} else {
		scenes = KernelScene.Plan.scenes(scene_plan)
		page_use = collect_text_command_use(scenes.commands, color_plan, List.repeat(0, color_count), List.repeat(0, image_count))?
		form_use = collect_text_command_use(form_commands, color_plan, page_use.color_counts, page_use.image_counts)?
		command_use = collect_text_command_use(pattern_commands, color_plan, form_use.color_counts, form_use.image_counts)?
		with_images = collect_image_colors(KernelImage.Plan.store(image_plan), command_use.color_counts)?
		with_shadings = match shadings {
			NoShadings => Ok({ color_counts: with_images.color_counts, shading_colors: 0 })
			WithShadings(store) => collect_shading_colors(store, color_plan, with_images.color_counts)
		}?
		blended_counts = match blending {
			NoBlending => with_shadings.color_counts
			Blending(space) => if space < with_shadings.color_counts.len() {
				match with_shadings.color_counts.set(space, list_at(with_shadings.color_counts, space) + 1) {
					Ok(next) => next
					Err(OutOfBounds) => {
						crash "checked blending index escaped"
					}
				}
			} else {
				with_shadings.color_counts
			}
		}
		ensure_used(command_use.image_counts, ImageIndex)?
		ensure_used(blended_counts, ColorSpaceIndex)?
		image_placements = checked_add(checked_add(page_use.image_placements, form_use.image_placements)?, command_use.image_placements)?
		image_reuses = checked_sub(image_placements, image_count)?
		Ok(
			KernelResourceUse.TextPlan.{
				color_use_counts: blended_counts,
				image_use_counts: command_use.image_counts,
				work: {
					color_space_resources: color_count,
					command_visits: scenes.commands.len() + form_commands.len() + pattern_commands.len(),
					image_color_references: with_images.image_colors,
					image_placements,
					image_resources: image_count,
					image_reuses,
					path_color_references: checked_add(checked_add(page_use.path_colors, form_use.path_colors)?, command_use.path_colors)?,
					text_color_references: checked_add(page_use.text_colors, form_use.text_colors)?,
				},
			},
		)
	}
}

## Each shading credits its declared color space once, and every stop's
## channel arity is checked against that space exactly once per stop.
collect_shading_colors : Scene.ShadingStore, KernelColor.Plan, List(U64) -> Try({ color_counts : List(U64), shading_colors : U64 }, KernelResourceUse.Error)
collect_shading_colors = |store, colors, initial_counts| {
	var $counts = initial_counts
	var $shading_index = 0
	var $error = NoError
	while $shading_index < store.shadings.len() and $error == NoError {
		shading = list_at(store.shadings, $shading_index)
		expected = KernelColor.Plan.components(colors, shading.space)
		var $stop_index = shading.stops.start()
		stop_end = shading.stops.start() + shading.stops.length()
		while $stop_index < stop_end and $error == NoError {
			actual = match list_at(store.stops, $stop_index).channels {
				Gray(_) => One
				Rgb(_) => Three
			}
			if actual != expected {
				$error = Invalid(ShadingStopComponentMismatch({ actual, expected, shading: $shading_index, stop: $stop_index }))
			}
			$stop_index = $stop_index + 1
		}
		if $error == NoError {
			match increment($counts, shading.space.index()) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(counts) => {
					$counts = counts
				}
			}
		}
		$shading_index = $shading_index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ color_counts: $counts, shading_colors: store.shadings.len() })
	}
}

collect_command_use : List(Scene.Command), KernelColor.Plan, U64, U64 -> Try(CommandUse, KernelResourceUse.Error)
collect_command_use = |commands, colors, color_count, image_count| {
	var $color_counts = List.repeat(0, color_count)
	var $image_counts = List.repeat(0, image_count)
	var $path_colors = 0
	var $image_placements = 0
	var $index = 0

	## Every per-resource count and the placement total are bounded by the
	## in-memory command length, so one preflight keeps the hot loop infallible.
	var $error = if commands.len() == U64.highest Invalid(ArithmeticOverflow) else NoError
	while $index < commands.len() and $error == NoError {
		match list_at(commands, $index) {
			DrawImage({ image, placement: _ }) => {
				image_index = image.index()
				next_count = list_at($image_counts, image_index) + 1
				$image_counts = match $image_counts.set(image_index, next_count) {
					Err(OutOfBounds) => {
						crash "validated image-use update escaped"
					}
					Ok(counts) => counts
				}
				$image_placements = $image_placements + 1
			}
			DrawPath({ path: _, style }) => match collect_style(style, $index, colors, $color_counts) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(collected) => {
					$color_counts = collected.counts
					$path_colors = match checked_add($path_colors, collected.references) {
						Err(error) => {
							$error = Invalid(error)
							$path_colors
						}
						Ok(value) => value
					}
				}
			}
			_ => {}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ color_counts: $color_counts, image_counts: $image_counts, image_placements: $image_placements, path_colors: $path_colors })
	}
}

collect_text_command_use : List(Scene.Command), KernelColor.Plan, List(U64), List(U64) -> Try(TextCommandUse, KernelResourceUse.Error)
collect_text_command_use = |commands, colors, initial_color_counts, initial_image_counts| {
	var $color_counts = initial_color_counts
	var $image_counts = initial_image_counts
	var $path_colors = 0
	var $text_colors = 0
	var $image_placements = 0
	var $index = 0
	var $error = if commands.len() == U64.highest Invalid(ArithmeticOverflow) else NoError
	while $index < commands.len() and $error == NoError {
		match list_at(commands, $index) {
			DrawImage({ image, placement: _ }) => {
				image_index = image.index()
				next_count = list_at($image_counts, image_index) + 1
				$image_counts = match $image_counts.set(image_index, next_count) {
					Err(OutOfBounds) => {
						crash "validated image-use update escaped"
					}
					Ok(counts) => counts
				}
				$image_placements = $image_placements + 1
			}
			DrawPath({ path: _, style }) => match collect_style(style, $index, colors, $color_counts) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(collected) => {
					$color_counts = collected.counts
					$path_colors = match checked_add($path_colors, collected.references) {
						Err(error) => {
							$error = Invalid(error)
							$path_colors
						}
						Ok(value) => value
					}
				}
			}
			DrawText({ paint, run: _ }) => {
				match collect_text_paint(paint, $index, colors, $color_counts) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(collected) => {
						$color_counts = collected.counts
						$text_colors = match checked_add($text_colors, collected.references) {
							Err(error) => {
								$error = Invalid(error)
								$text_colors
							}
							Ok(value) => value
						}
					}
				}
			}
			_ => {}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ color_counts: $color_counts, image_counts: $image_counts, image_placements: $image_placements, path_colors: $path_colors, text_colors: $text_colors })
	}
}

collect_text_paint : Scene.TextPaint, U64, KernelColor.Plan, List(U64) -> Try({ counts : List(U64), references : U64 }, KernelResourceUse.Error)
collect_text_paint = |paint, command, colors, counts| {
	with_fill = collect_color(paint.fill, command, colors, counts)?
	match paint.stroke {
		NoStroke => Ok(with_fill)
		Stroke({ color, width: _ }) => {
			with_stroke = collect_color(color, command, colors, with_fill.counts)?
			Ok({ counts: with_stroke.counts, references: checked_add(with_fill.references, with_stroke.references)? })
		}
	}
}

collect_style : Scene.PathStyle, U64, KernelColor.Plan, List(U64) -> Try({ counts : List(U64), references : U64 }, KernelResourceUse.Error)
collect_style = |style, command, colors, counts| {
	with_fill = match style.fill {
		NoFill => Ok({ counts, references: 0 })

		## A pattern fill selects a pattern resource, not a color-space
		## channel value; the pattern's own dependencies are graph facts.
		PatternFill(_) => Ok({ counts, references: 0 })
		SolidFill({ color, rule: _ }) => collect_color(color, command, colors, counts)
	}?
	match style.stroke {
		NoStroke => Ok(with_fill)
		SolidStroke(stroke) => {
			with_stroke = collect_color(stroke.color, command, colors, with_fill.counts)?
			Ok({ counts: with_stroke.counts, references: checked_add(with_fill.references, with_stroke.references)? })
		}
	}
}

collect_color : Color.Value, U64, KernelColor.Plan, List(U64) -> Try({ counts : List(U64), references : U64 }, KernelResourceUse.Error)
collect_color = |color, command, colors, counts| {
	expected = KernelColor.Plan.components(colors, color.space)
	actual = match color.channels {
		Gray(_) => One
		Rgb(_) => Three
	}
	if actual != expected {
		Err(ColorComponentMismatch({ actual, command, expected, space: color.space.index() }))
	} else {
		Ok({ counts: increment(counts, color.space.index())?, references: 1 })
	}
}

collect_image_colors : Image.Store, List(U64) -> Try({ color_counts : List(U64), image_colors : U64 }, KernelResourceUse.Error)
collect_image_colors = |store, initial_counts| {
	var $counts = initial_counts
	var $index = 0
	var $error = NoError
	while $index < store.resources.len() and $error == NoError {
		resource = list_at(store.resources, $index)
		space = match resource.payload {
			Jpeg(jpeg) => jpeg.color_space
			Raster(raster) => raster.color_space
		}
		match increment($counts, space.index()) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(counts) => {
				$counts = counts
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ color_counts: $counts, image_colors: store.resources.len() })
	}
}

ensure_used : List(U64), KernelResourceUse.IndexKind -> Try({}, KernelResourceUse.Error)
ensure_used = |counts, kind| {
	var $index = 0
	var $unused = NoUnused
	while $index < counts.len() and $unused == NoUnused {
		if list_at(counts, $index) == 0 {
			$unused = Unused($index)
		}
		$index = $index + 1
	}
	match $unused {
		NoUnused => Ok({})
		Unused(index) => Err(OrphanResource({ index, kind }))
	}
}

increment : List(U64), U64 -> Try(List(U64), KernelResourceUse.Error)
increment = |counts, index| {
	next = checked_add(list_at(counts, index), 1)?
	Ok(list_set(counts, index, next))
}

checked_add : U64, U64 -> Try(U64, KernelResourceUse.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_sub : U64, U64 -> Try(U64, KernelResourceUse.Error)
checked_sub = |left, right| match U64.minus_try(left, right) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated resource-use index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated resource-use update escaped"
	}
}

unit : I64 -> Layout.Unit
unit = |raw| Layout.Unit.from_raw(raw)

rect : I64, I64, I64, I64 -> Layout.Rect
rect = |x, y, width, height| { origin: { x: unit(x), y: unit(y) }, size: { height: unit(height), width: unit(width) } }

gray_space : U64 -> Color.SpaceRecord
gray_space = |index| {
	id: Color.SpaceId.from_index(index),
	space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }),
}

gray_value : U64 -> Color.Value
gray_value = |space| { channels: Gray(32768), space: Color.SpaceId.from_index(space) }

test_scene : Color.Value, U64 -> Scene.Store
test_scene = |color, image_count| {
	image_commands = if image_count == 0 [] else [
		DrawImage({ image: Image.Id.from_index(0), placement: rect(0, 0, 1000, 1000) }),
		DrawImage({ image: Image.Id.from_index(0), placement: rect(1000, 0, 1000, 1000) }),
	]
	commands = [DrawPath({ path: Scene.PathId.from_index(0), style: { fill: SolidFill({ color, rule: Nonzero }), stroke: NoStroke } })].concat(image_commands)
	{
		commands,
		dash_lengths: [],
		groups: [{ commands: Semantics.Range.from_start_and_length(0, commands.len()), id: Scene.GroupId.from_index(0), owner: PageArtifact(Background) }],
		page_groups: [Scene.GroupId.from_index(0)],
		pages: [{ boxes: { art: rect(0, 0, 10000, 10000), bleed: rect(0, 0, 10000, 10000), crop: rect(0, 0, 10000, 10000), media: rect(0, 0, 10000, 10000), trim: rect(0, 0, 10000, 10000) }, id: Semantics.PageId.from_index(0), paint_order: Semantics.Range.from_start_and_length(0, 1), rotation: Rotate0 }],
		path_segments: [Rectangle(rect(0, 0, 1000, 1000))],
		paths: [{ id: Scene.PathId.from_index(0), segments: Semantics.Range.from_start_and_length(0, 1) }],
	}
}

scene_limits : U64 -> KernelScene.Limits
scene_limits = |commands| KernelScene.Limits.make({ max_commands: commands, max_dash_lengths: 0, max_graphics_depth: 1, max_groups: 1, max_pages: 1, max_path_segments: 1, max_paths: 1 })

image_sources : Image.SourceStore
image_sources = {
	resources: [
		{
			id: Image.Id.from_index(0),
			payload: PackedPixels({ alpha: NoAlpha, color_space: Color.SpaceId.from_index(0), dimensions: { height: 1, width: 1 }, format: Gray8, pixels: [127], row_stride: 1 }),
		},
	],
}

color_limits : U64 -> KernelColor.Limits
color_limits = |spaces| KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: spaces, max_tags: 0 })

image_limits : KernelImage.Limits
image_limits = KernelImage.Limits.make({ max_decoded_bytes: 1, max_encoded_bytes: 0, max_height: 1, max_markers: 0, max_resources: 1, max_width: 1 })

## Repeated placements count twice while retaining one image payload resource.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [gray_space(0)], tags: [] }, color_limits(1))?
	images = KernelImage.Plan.build(image_sources, colors, image_limits)?
	scene = test_scene(gray_value(0), 1)
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), scene_limits(3))?
	plan = KernelResourceUse.Plan.build(scenes, colors, images)?
	work = KernelResourceUse.Plan.work(plan)
	KernelResourceUse.Plan.color_use_count(plan, Color.SpaceId.from_index(0)) == 2 and KernelResourceUse.Plan.image_use_count(plan, Image.Id.from_index(0)) == 2 and work.image_resources == 1 and work.image_placements == 2 and work.image_reuses == 1 and work.path_color_references == 1 and work.image_color_references == 1 and work.command_visits == 3
}

## Channel shape must agree with the selected validated color space.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [gray_space(0)], tags: [] }, color_limits(1))?
	images = KernelImage.Plan.build(image_sources, colors, image_limits)?
	rgb : Color.Value
	rgb = { channels: Rgb({ blue: 0, green: 0, red: 0 }), space: Color.SpaceId.from_index(0) }
	scene = test_scene(rgb, 1)
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), scene_limits(3))?
	match KernelResourceUse.Plan.build(scenes, colors, images) {
		Err(ColorComponentMismatch({ actual: Three, command: 0, expected: One, space: 0 })) => True
		_ => False
	}
}

## Declared scene resource counts cannot diverge from inspected stores.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [gray_space(0)], tags: [] }, color_limits(1))?
	images = KernelImage.Plan.build(image_sources, colors, image_limits)?
	scene = test_scene(gray_value(0), 1)
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 2, images: 1 }), scene_limits(3))?
	match KernelResourceUse.Plan.build(scenes, colors, images) {
		Err(CountMismatch({ actual: 1, declared: 2, kind: ColorSpaceIndex })) => True
		_ => False
	}
}

## Validated image payloads that never receive a placement are rejected.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [gray_space(0)], tags: [] }, color_limits(1))?
	images = KernelImage.Plan.build(image_sources, colors, image_limits)?
	scene = test_scene(gray_value(0), 0)
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), scene_limits(1))?
	match KernelResourceUse.Plan.build(scenes, colors, images) {
		Err(OrphanResource({ index: 0, kind: ImageIndex })) => True
		_ => False
	}
}

## Color spaces enter the normalized closure only when paint or image data uses them.
expect {
	colors = KernelColor.Plan.build({ profiles: [], spaces: [gray_space(0), gray_space(1)], tags: [] }, color_limits(2))?
	images = KernelImage.Plan.build(image_sources, colors, image_limits)?
	scene = test_scene(gray_value(0), 1)
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 2, images: 1 }), scene_limits(3))?
	match KernelResourceUse.Plan.build(scenes, colors, images) {
		Err(OrphanResource({ index: 1, kind: ColorSpaceIndex })) => True
		_ => False
	}
}
