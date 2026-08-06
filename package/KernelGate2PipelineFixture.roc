import Color
import Image
import KernelColor
import KernelContent
import KernelGate2Fixture
import KernelGate2Objects
import KernelImage
import KernelResourceUse
import KernelScene
import KernelTagged

KernelGate2PipelineFixture :: [].{
	Error : [
		ColorFailure(KernelColor.Error),
		ContentFailure(KernelContent.Error),
		ImageFailure(KernelImage.Error),
		ObjectPlanFailure(KernelGate2Objects.Error),
		ResourceUseFailure(KernelResourceUse.Error),
		SceneFailure(KernelScene.Error),
		TaggedFixtureFailure(KernelGate2Fixture.Error),
	]
	Pipeline : {
		colors : KernelColor.Plan,
		content : KernelContent.Plan,
		images : KernelImage.Plan,
		objects : KernelGate2Objects.Plan,
		resource_use : KernelResourceUse.Plan,
		tagged : KernelTagged.Plan,
	}

	pipeline : {} -> Try(Pipeline, Error)
	pipeline = |_| build_pipeline(False, False)

	contextual_pipeline : {} -> Try(Pipeline, Error)
	contextual_pipeline = |_| build_pipeline(True, False)

	alpha_pipeline : {} -> Try(Pipeline, Error)
	alpha_pipeline = |_| build_pipeline(False, True)
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
			payload: PackedPixels({
				alpha: NoAlpha,
				color_space: Color.SpaceId.from_index(0),
				dimensions: { height: 2, width: 2 },
				format: Gray8,
				pixels: [0, 64, 128, 255],
				row_stride: 2,
			}),
		},
	],
}

alpha_image_sources : Image.SourceStore
alpha_image_sources = {
	resources: [
		{
			id: Image.Id.from_index(0),
			payload: PackedPixels({
				alpha: PackedAlpha({ bytes: [255, 128, 7, 64, 0, 9], row_stride: 3 }),
				color_space: Color.SpaceId.from_index(0),
				dimensions: { height: 2, width: 2 },
				format: Gray8,
				pixels: [0, 64, 7, 128, 255, 9],
				row_stride: 3,
			}),
		},
	],
}

build_pipeline : Bool, Bool -> Try(KernelGate2PipelineFixture.Pipeline, KernelGate2PipelineFixture.Error)
build_pipeline = |contextual, alpha| {
	tagged = (if contextual KernelGate2Fixture.contextual_tagged_plan(1) else KernelGate2Fixture.tagged_plan(1)) ? TaggedFixtureFailure
	scenes = KernelScene.Plan.build(KernelGate2Fixture.scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 2, max_pages: 1, max_path_segments: 1, max_paths: 1 })) ? SceneFailure
	colors = KernelColor.Plan.build(color_store, KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })) ? ColorFailure
	sources = if alpha alpha_image_sources else image_sources
	images = KernelImage.Plan.build(sources, colors, KernelImage.Limits.make({ max_decoded_bytes: 12, max_encoded_bytes: 0, max_height: 2, max_markers: 0, max_resources: 1, max_width: 2 })) ? ImageFailure
	resource_use = KernelResourceUse.Plan.build(scenes, colors, images) ? ResourceUseFailure
	content = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 512, max_content_streams: 1 })) ? ContentFailure
	objects = KernelGate2Objects.Plan.build(tagged, colors, images, resource_use, content, KernelGate2Objects.Limits.make({ max_objects: 16, max_pages: 1 })) ? ObjectPlanFailure
	Ok({ colors, content, images, objects, resource_use, tagged })
}
