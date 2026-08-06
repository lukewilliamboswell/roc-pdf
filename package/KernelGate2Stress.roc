import Color
import Image
import KernelColor
import KernelContent
import KernelGate2Fixture
import KernelImage
import KernelResourceUse
import KernelScene
import KernelSemantics
import KernelTagged
import Scene
import Semantics

KernelGate2Stress :: [].{
	Error : [ArithmeticOverflow, Color(KernelColor.Error), Content(KernelContent.Error), Image(KernelImage.Error), ResourceUse(KernelResourceUse.Error), Scene(KernelScene.Error), Semantic(KernelSemantics.Error), Tagged(KernelTagged.Error), ZeroCommands]

	Report : {
		commands : U64,
		content_bytes : U64,
		content_command_visits : U64,
		content_image_placements : U64,
		content_max_frame_depth : U64,
		image_payload_bytes : U64,
		image_resource_count : U64,
		image_reuses : U64,
		image_use_count : U64,
		resource_command_visits : U64,
		scene_command_visits : U64,
		scene_image_placements : U64,
		scene_max_graphics_depth : U64,
	}

	run : U64 -> Try(Report, Error)
	run = |command_count| run_stress(command_count, 0)

	run_phase : U64, U8 -> Try(Report, Error)
	run_phase = |command_count, phase| run_stress(command_count, phase)
}

run_stress : U64, U8 -> Try(KernelGate2Stress.Report, KernelGate2Stress.Error)
run_stress = |command_count, phase| {
	if command_count == 0 {
		Err(ZeroCommands)
	} else {
		scene_plan = KernelScene.Plan.build(
			stress_scene(command_count),
			KernelScene.Resources.make({ color_spaces: 1, images: 1 }),
			KernelScene.Limits.make({
				max_commands: command_count,
				max_dash_lengths: 0,
				max_graphics_depth: 1,
				max_groups: 1,
				max_pages: 1,
				max_path_segments: 0,
				max_paths: 0,
			}),
		) ? Scene
		scene_work = KernelScene.Plan.work(scene_plan)
		base_report = {
			commands: command_count,
			content_bytes: 0,
			content_command_visits: 0,
			content_image_placements: 0,
			content_max_frame_depth: 0,
			image_payload_bytes: 0,
			image_resource_count: 0,
			image_reuses: 0,
			image_use_count: 0,
			resource_command_visits: 0,
			scene_command_visits: scene_work.command_visits,
			scene_image_placements: scene_work.image_placements,
			scene_max_graphics_depth: scene_work.max_graphics_depth,
		}
		if phase == 1 {
			Ok(base_report)
		} else {
			with_content = if phase == 2 {
				base_report
			} else {
				semantic_store = KernelGate2Fixture.semantics
				semantics = KernelSemantics.Plan.build(
					semantic_store,
					1,
					1,
					KernelSemantics.Limits.make({
						max_attributes: semantic_store.attributes.len(),
						max_content_spine: semantic_store.content_spine.len(),
						max_fragments: 1,
						max_namespaces: 1,
						max_nodes: 2,
						max_occurrences: 1,
						max_semantic_depth: 2,
					}),
				) ? Semantic
				tagged = KernelTagged.Plan.build(semantics, scene_plan) ? Tagged
				content_limit = checked_add(checked_times(command_count, 64)?, 128)?
				content = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: content_limit, max_content_streams: 1 })) ? Content
				content_work = KernelContent.Plan.work(content)
				{
					..base_report,
					content_bytes: content_work.bytes_emitted,
					content_command_visits: content_work.command_visits,
					content_image_placements: content_work.image_placements,
					content_max_frame_depth: content_work.max_frame_depth,
				}
			}
			if phase == 3 {
				Ok(with_content)
			} else {
				colors = KernelColor.Plan.build(color_store, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? Color
				images = KernelImage.Plan.build(image_sources, colors, KernelImage.Limits.make({ max_decoded_bytes: 1, max_encoded_bytes: 0, max_height: 1, max_markers: 0, max_resources: 1, max_width: 1 })) ? Image
				resource_use = KernelResourceUse.Plan.build(scene_plan, colors, images) ? ResourceUse
				resource_work = KernelResourceUse.Plan.work(resource_use)
				image_store = KernelImage.Plan.store(images)
				image_resource = list_at(image_store.resources, 0)
				payload_bytes = match image_resource.payload {
					Jpeg(jpeg) => jpeg.bytes.len()
					Raster(raster) => raster.pixels.len()
				}
				Ok({
					..with_content,
					image_payload_bytes: payload_bytes,
					image_resource_count: image_store.resources.len(),
					image_reuses: resource_work.image_reuses,
					image_use_count: KernelResourceUse.Plan.image_use_count(resource_use, Image.Id.from_index(0)),
					resource_command_visits: resource_work.command_visits,
				})
			}
		}
	}
}

color_store : Color.Store
color_store = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

image_sources : Image.SourceStore
image_sources = {
	resources: [
		{
			id: Image.Id.from_index(0),
			payload: PackedPixels({ alpha: NoAlpha, color_space: Color.SpaceId.from_index(0), dimensions: { height: 1, width: 1 }, format: Gray8, pixels: [127], row_stride: 1 }),
		},
	],
}

stress_scene : U64 -> Scene.Store
stress_scene = |command_count| {
	placement = KernelGate2Fixture.rect(0, 0, 1000, 1000)
	commands = List.repeat(DrawImage({ image: Image.Id.from_index(0), placement }), command_count)
	page_box = KernelGate2Fixture.rect(0, 0, 10000, 10000)
	{
		commands,
		dash_lengths: [],
		groups: [{ commands: Semantics.Range.from_start_and_length(0, command_count), id: Scene.GroupId.from_index(0), owner: Fragment(Semantics.FragmentId.from_index(0)) }],
		page_groups: [Scene.GroupId.from_index(0)],
		pages: [{ boxes: { art: page_box, bleed: page_box, crop: page_box, media: page_box, trim: page_box }, id: Semantics.PageId.from_index(0), paint_order: Semantics.Range.from_start_and_length(0, 1), rotation: Rotate0 }],
		path_segments: [],
		paths: [],
	}
}

checked_add : U64, U64 -> Try(U64, KernelGate2Stress.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

checked_times : U64, U64 -> Try(U64, KernelGate2Stress.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated Gate 2 stress index escaped"
	}
}
