import pdf.KernelContent
import pdf.KernelEmit
import pdf.KernelFixture
import pdf.KernelObjectPlan
import pdf.KernelPipelineFixture
import pdf.KernelScene
import pdf.KernelSemantics
import pdf.KernelTagged
import pdf.KernelTaggedStructure
import pdf.Pdf
import pdf.Scene
import pdf.Theme
import StructureOracle

PageViewport := [].{}

# Table 31 specifies clockwise quarter-turns and the page's viewport in
# unrotated default user space. Each literal below is a pair of opposite
# corners independently calculated from the authored origins and sizes.
expect {
	bytes = scene_pdf(distinct_boxes, Rotate270)?
	StructureOracle.single_page_viewport(bytes) == Ok({
		art: [-5.875, -2.5, 22.125, 20.5],
		bleed: [-7.25, -3.5, 25.5, 25.5],
		crop: [-8.5, -4.25, 27.5, 26.25],
		media: [-11.25, -7.75, 36, 28],
		rotation: Degrees(270),
		trim: [-6.5, -3, 23.9, 24.25],
	})
}

# The three production boxes have the crop box as default even when a
# separate crop box is present. Emission elides those three authored values.
expect {
	crop = distinct_boxes.crop
	boxes = { ..distinct_boxes, art: crop, bleed: crop, trim: crop }
	[(Rotate90, 90), (Rotate180, 180)].all(
		|(rotation, degrees)| match scene_pdf(boxes, rotation) {
			Err(_) => False
			Ok(bytes) => StructureOracle.single_page_viewport(bytes) == Ok({
				art: [],
				bleed: [],
				crop: [-8.5, -4.25, 27.5, 26.25],
				media: [-11.25, -7.75, 36, 28],
				rotation: Degrees(degrees),
				trim: [],
			})
		},
	)
}

# Custom integer sides are inclusive at both public portability bounds.
expect {
	document = Pdf.document({ contents: [], language: "en", title: "Viewport bounds" })
	theme = Theme.{ page_margin: { bottom: 0, left: 0, right: 0, top: 0 } }
	bytes = Pdf.to_bytes_with(document, { theme, page_size: Custom({ width: 3, height: 14400 }) }) ? |_| ViewportFixtureFailed
	StructureOracle.single_page_viewport(bytes) == Ok({ art: [], bleed: [], crop: [], media: [0, 0, 3, 14400], rotation: DefaultRotation, trim: [] })
}

# Use the existing visual fixture's validated resources. Only the page
# viewport changes, so it retains the same authored paint and semantic arena.
scene_pdf : Scene.PageBoxes, Scene.Rotation -> Try(List(U8), [ViewportFixtureFailed])
scene_pdf = |boxes, rotation| {
	fixture = KernelFixture.scene
	page = fixture.pages.first() ? |_| ViewportFixtureFailed
	scene = { ..fixture, pages: [{ ..page, boxes, rotation }] }
	scenes = KernelScene.Plan.build(scene, KernelScene.Resources.make({ color_spaces: 1, images: 1 }), KernelScene.Limits.make({ max_commands: 3, max_dash_lengths: 0, max_graphics_depth: 2, max_groups: 2, max_pages: 1, max_path_segments: 1, max_paths: 1 })) ? |_| ViewportFixtureFailed
	semantics = KernelSemantics.Plan.build(KernelFixture.semantics, 1, 1, KernelSemantics.Limits.make({ max_attributes: 0, max_content_spine: 2, max_fragments: 1, max_namespaces: 1, max_nodes: 2, max_occurrences: 1, max_semantic_depth: 2 })) ? |_| ViewportFixtureFailed
	tagged = KernelTagged.Plan.build(semantics, scenes) ? |_| ViewportFixtureFailed
	fixture_pipeline = KernelPipelineFixture.pipeline({}) ? |_| ViewportFixtureFailed
	{ colors, images, resource_use, .. } = fixture_pipeline
	content = KernelContent.Plan.build(tagged, KernelContent.Limits.make({ max_content_bytes: 512, max_content_streams: 1 })) ? |_| ViewportFixtureFailed
	objects = KernelObjectPlan.Plan.build(tagged, colors, images, resource_use, content, KernelObjectPlan.Limits.make({ max_objects: 32, max_pages: 1 })) ? |_| ViewportFixtureFailed
	structure = KernelTaggedStructure.Plan.build(tagged, colors, images, content, objects, KernelTaggedStructure.Limits.make({ object_limits: { max_array_items: 192, max_byte_string_bytes: 0, max_byte_strings: 0, max_dictionary_entries: 320, max_direct_depth: 8, max_name_bytes: 3072, max_names: 128, max_objects: 32, max_payload_bytes: 2048, max_payloads: 4, max_streams: 4, max_text_string_bytes: 64, max_text_strings: 1, max_values: 640 } })) ? |_| ViewportFixtureFailed
	KernelEmit.to_bytes(KernelTaggedStructure.Plan.structure(structure)).map_err(|_| ViewportFixtureFailed)
}

distinct_boxes : Scene.PageBoxes
distinct_boxes = {
	media: KernelFixture.rect(-11250, -7750, 47250, 35750),
	crop: KernelFixture.rect(-8500, -4250, 36000, 30500),
	bleed: KernelFixture.rect(-7250, -3500, 32750, 29000),
	trim: KernelFixture.rect(-6500, -3000, 30400, 27250),
	art: KernelFixture.rect(-5875, -2500, 28000, 23000),
}
