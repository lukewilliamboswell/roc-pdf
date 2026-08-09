import KernelBalanced
import KernelContent
import KernelGate2Objects
import KernelGate2PipelineFixture
import KernelGate2ResourceName
import KernelGate2TaggedObjects
import KernelGate3FontObjects
import KernelLex
import KernelObject
import KernelTagged
import Layout
import Scene
import Semantics

KernelGate2PageObjects :: [].{
	Error : [
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
	]

	Work : {
		box_values : U64,
		content_streams : U64,
		page_tree_edges : U64,
		page_tree_nodes : U64,
		pages : U64,
		resource_references : U64,
	}

	Plan :: { builder : KernelObject.Builder, work : Work }.{
		build : KernelGate2TaggedObjects.Plan, KernelTagged.Plan, KernelContent.Plan, KernelGate2Objects.Plan -> Try(Plan, Error)
		build = |prefix, tagged, content, objects| build_plan(prefix, tagged, content, objects)

		build_with_fonts : KernelGate2TaggedObjects.Plan, KernelTagged.Plan, KernelContent.Plan, KernelGate3FontObjects.Plan -> Try(Plan, Error)
		build_with_fonts = |prefix, tagged, content, objects| build_font_plan(prefix, tagged, content, objects)

		builder : Plan -> KernelObject.Builder
		builder = |plan| plan.builder

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Names := {
	art_box : KernelObject.NameId,
	bleed_box : KernelObject.NameId,
	color_space : KernelObject.NameId,
	contents : KernelObject.NameId,
	count : KernelObject.NameId,
	crop_box : KernelObject.NameId,
	kids : KernelObject.NameId,
	media_box : KernelObject.NameId,
	page : KernelObject.NameId,
	pages : KernelObject.NameId,
	parent : KernelObject.NameId,
	resources : KernelObject.NameId,
	rotate : KernelObject.NameId,
	s : KernelObject.NameId,
	struct_parents : KernelObject.NameId,
	tabs : KernelObject.NameId,
	trim_box : KernelObject.NameId,
	type_name : KernelObject.NameId,
	x_object : KernelObject.NameId,
}

Resources := { builder : KernelObject.Builder, references : U64, value : KernelObject.ValueId }

build_plan : KernelGate2TaggedObjects.Plan, KernelTagged.Plan, KernelContent.Plan, KernelGate2Objects.Plan -> Try(KernelGate2PageObjects.Plan, KernelGate2PageObjects.Error)
build_plan = |prefix, tagged, content, objects| {
	added_names = add_names(KernelGate2TaggedObjects.Plan.builder(prefix))?
	resources = add_resources(added_names.builder, added_names.names, objects)?
	page_tree = add_page_tree(resources.builder, added_names.names, objects)?
	pages = add_pages(page_tree.builder, added_names.names, resources.value, tagged, content, objects)?
	Ok(
		KernelGate2PageObjects.Plan.{
			builder: pages,
			work: {
				box_values: KernelTagged.Plan.scenes(tagged).pages.len() * 5,
				content_streams: KernelContent.Plan.stream_count(content),
				page_tree_edges: page_tree.edges,
				page_tree_nodes: KernelBalanced.Shape.node_count(KernelGate2Objects.Plan.page_tree_shape(objects)),
				pages: KernelTagged.Plan.scenes(tagged).pages.len(),
				resource_references: resources.references,
			},
		},
	)
}

build_font_plan : KernelGate2TaggedObjects.Plan, KernelTagged.Plan, KernelContent.Plan, KernelGate3FontObjects.Plan -> Try(KernelGate2PageObjects.Plan, KernelGate2PageObjects.Error)
build_font_plan = |prefix, tagged, content, font_objects| {
	objects = KernelGate3FontObjects.Plan.base(font_objects)
	added_names = add_names(KernelGate2TaggedObjects.Plan.builder(prefix))?
	font_name = KernelObject.add_name(added_names.builder, Str.to_utf8("Font")) ? Object
	resources = add_resources_with_fonts(font_name.builder, added_names.names, font_name.id, objects, KernelGate3FontObjects.Plan.fonts(font_objects))?
	page_tree = add_page_tree(resources.builder, added_names.names, objects)?
	pages = add_pages(page_tree.builder, added_names.names, resources.value, tagged, content, objects)?
	Ok(
		KernelGate2PageObjects.Plan.{
			builder: pages,
			work: {
				box_values: KernelTagged.Plan.scenes(tagged).pages.len() * 5,
				content_streams: KernelContent.Plan.stream_count(content),
				page_tree_edges: page_tree.edges,
				page_tree_nodes: KernelBalanced.Shape.node_count(KernelGate2Objects.Plan.page_tree_shape(objects)),
				pages: KernelTagged.Plan.scenes(tagged).pages.len(),
				resource_references: resources.references,
			},
		},
	)
}

add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelGate2PageObjects.Error)
add_names = |builder| {
	art_box = KernelObject.add_name(builder, Str.to_utf8("ArtBox")) ? Object
	bleed_box = KernelObject.add_name(art_box.builder, Str.to_utf8("BleedBox")) ? Object
	color_space = KernelObject.add_name(bleed_box.builder, Str.to_utf8("ColorSpace")) ? Object
	contents = KernelObject.add_name(color_space.builder, Str.to_utf8("Contents")) ? Object
	count = KernelObject.add_name(contents.builder, Str.to_utf8("Count")) ? Object
	crop_box = KernelObject.add_name(count.builder, Str.to_utf8("CropBox")) ? Object
	kids = KernelObject.add_name(crop_box.builder, Str.to_utf8("Kids")) ? Object
	media_box = KernelObject.add_name(kids.builder, Str.to_utf8("MediaBox")) ? Object
	page = KernelObject.add_name(media_box.builder, Str.to_utf8("Page")) ? Object
	pages = KernelObject.add_name(page.builder, Str.to_utf8("Pages")) ? Object
	parent = KernelObject.add_name(pages.builder, Str.to_utf8("Parent")) ? Object
	resources = KernelObject.add_name(parent.builder, Str.to_utf8("Resources")) ? Object
	rotate = KernelObject.add_name(resources.builder, Str.to_utf8("Rotate")) ? Object
	s = KernelObject.add_name(rotate.builder, Str.to_utf8("S")) ? Object
	struct_parents = KernelObject.add_name(s.builder, Str.to_utf8("StructParents")) ? Object
	tabs = KernelObject.add_name(struct_parents.builder, Str.to_utf8("Tabs")) ? Object
	trim_box = KernelObject.add_name(tabs.builder, Str.to_utf8("TrimBox")) ? Object
	type_name = KernelObject.add_name(trim_box.builder, Str.to_utf8("Type")) ? Object
	x_object = KernelObject.add_name(type_name.builder, Str.to_utf8("XObject")) ? Object
	Ok({
		builder: x_object.builder,
		names: {
			art_box: art_box.id,
			bleed_box: bleed_box.id,
			color_space: color_space.id,
			contents: contents.id,
			count: count.id,
			crop_box: crop_box.id,
			kids: kids.id,
			media_box: media_box.id,
			page: page.id,
			pages: pages.id,
			parent: parent.id,
			resources: resources.id,
			rotate: rotate.id,
			s: s.id,
			struct_parents: struct_parents.id,
			tabs: tabs.id,
			trim_box: trim_box.id,
			type_name: type_name.id,
			x_object: x_object.id,
		},
	})
}

add_resources : KernelObject.Builder, Names, KernelGate2Objects.Plan -> Try(Resources, KernelGate2PageObjects.Error)
add_resources = |builder, names, objects| {
	colors = add_named_references(builder, "CS", KernelGate2Objects.Plan.color_spaces(objects))?
	images = add_image_references(colors.builder, KernelGate2Objects.Plan.images(objects))?
	color_dictionary = KernelObject.add_dictionary(images.builder, colors.entries) ? Object
	image_dictionary = KernelObject.add_dictionary(color_dictionary.builder, images.entries) ? Object
	resources = KernelObject.add_dictionary(
		image_dictionary.builder,
		[
			{ key: names.color_space, value: color_dictionary.id },
			{ key: names.x_object, value: image_dictionary.id },
		],
	) ? Object
	Ok({ builder: resources.builder, references: colors.entries.len() + images.entries.len(), value: resources.id })
}

add_resources_with_fonts : KernelObject.Builder, Names, KernelObject.NameId, KernelGate2Objects.Plan, List(KernelGate3FontObjects.FontObjects) -> Try(Resources, KernelGate2PageObjects.Error)
add_resources_with_fonts = |builder, names, font_name, objects, fonts| {
	colors = add_named_references(builder, "CS", KernelGate2Objects.Plan.color_spaces(objects))?
	images = add_image_references(colors.builder, KernelGate2Objects.Plan.images(objects))?
	font_references = add_font_references(images.builder, fonts)?
	color_dictionary = KernelObject.add_dictionary(font_references.builder, colors.entries) ? Object
	image_dictionary = KernelObject.add_dictionary(color_dictionary.builder, images.entries) ? Object
	font_dictionary = KernelObject.add_dictionary(image_dictionary.builder, font_references.entries) ? Object
	resources = KernelObject.add_dictionary(
		font_dictionary.builder,
		[
			{ key: names.color_space, value: color_dictionary.id },
			{ key: font_name, value: font_dictionary.id },
			{ key: names.x_object, value: image_dictionary.id },
		],
	) ? Object
	Ok({ builder: resources.builder, references: colors.entries.len() + font_references.entries.len() + images.entries.len(), value: resources.id })
}

add_font_references : KernelObject.Builder, List(KernelGate3FontObjects.FontObjects) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelGate2PageObjects.Error)
add_font_references = |builder, fonts| {
	var $objects = List.with_capacity(fonts.len())
	var $index = 0
	while $index < fonts.len() {
		$objects = $objects.append(list_at(fonts, $index).type0)
		$index = $index + 1
	}
	add_named_references(builder, "F", $objects)
}

add_named_references : KernelObject.Builder, Str, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelGate2PageObjects.Error)
add_named_references = |builder, prefix, objects| {
	var $builder = builder
	var $entries = List.with_capacity(objects.len())
	var $index = 0
	var $error = NoError
	while $index < objects.len() and $error == NoError {
		name_bytes = KernelGate2ResourceName.bytes(prefix, $index)
		match KernelObject.add_name($builder, name_bytes) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(name) => match KernelObject.add_reference(name.builder, list_at(objects, $index)) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(reference) => {
					$builder = reference.builder
					$entries = $entries.append({ key: name.id, value: reference.id })
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => Ok({ builder: $builder, entries: $entries })
	}
}

add_image_references : KernelObject.Builder, List(KernelGate2Objects.ImageObjects) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelGate2PageObjects.Error)
add_image_references = |builder, images| {
	var $objects = List.with_capacity(images.len())
	var $index = 0
	while $index < images.len() {
		$objects = $objects.append(list_at(images, $index).image.stream)
		$index = $index + 1
	}
	add_named_references(builder, "Im", $objects)
}

add_page_tree : KernelObject.Builder, Names, KernelGate2Objects.Plan -> Try({ builder : KernelObject.Builder, edges : U64 }, KernelGate2PageObjects.Error)
add_page_tree = |builder, names, objects| {
	shape = KernelGate2Objects.Plan.page_tree_shape(objects)
	var $builder = builder
	var $level = 0
	var $edges = 0
	var $error = NoError
	while $level < KernelBalanced.Shape.level_count(shape) and $error == NoError {
		var $node = 0
		while $node < KernelBalanced.Shape.level_node_count(shape, $level) and $error == NoError {
			match add_page_tree_node($builder, names, objects, $level, $node) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(added) => {
					$builder = added.builder
					$edges = $edges + added.edges
				}
			}
			$node = $node + 1
		}
		$level = $level + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ builder: $builder, edges: $edges })
	}
}

add_page_tree_node : KernelObject.Builder, Names, KernelGate2Objects.Plan, U64, U64 -> Try({ builder : KernelObject.Builder, edges : U64 }, KernelGate2PageObjects.Error)
add_page_tree_node = |builder, names, objects, level, node| {
	shape = KernelGate2Objects.Plan.page_tree_shape(objects)
	is_leaf = level == KernelBalanced.Shape.leaf_level(shape)
	span = if is_leaf KernelBalanced.Shape.item_span(shape, level, node) else KernelBalanced.Shape.child_span(shape, level, node)
	children = (if is_leaf add_page_references(builder, KernelGate2Objects.Plan.pages(objects), span) else add_tree_references(builder, KernelGate2Objects.Plan.page_tree(objects), span))?
	kids = KernelObject.add_array(children.builder, children.values) ? Object
	descendants = KernelBalanced.Span.length(KernelBalanced.Shape.item_span(shape, level, node))
	count = KernelObject.add_integer(kids.builder, descendants.to_i64_wrap()) ? Object
	type_value = KernelObject.add_name_value(count.builder, names.pages) ? Object
	global = KernelBalanced.Shape.level_offset(shape, level) + node
	entries = if level == 0 {
		[
			{ key: names.count, value: count.id },
			{ key: names.kids, value: kids.id },
			{ key: names.type_name, value: type_value.id },
		]
	} else {
		parent_global = KernelBalanced.Shape.level_offset(shape, level - 1) + U64.div_by(node, KernelBalanced.Shape.fanout)
		parent = KernelObject.add_reference(type_value.builder, list_at(KernelGate2Objects.Plan.page_tree(objects), parent_global)) ? Object
		[
			{ key: names.count, value: count.id },
			{ key: names.kids, value: kids.id },
			{ key: names.parent, value: parent.id },
			{ key: names.type_name, value: type_value.id },
		]
	}
	dictionary = KernelObject.add_dictionary(type_value.builder, entries) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, list_at(KernelGate2Objects.Plan.page_tree(objects), global))?
	Ok({ builder: object.builder, edges: KernelBalanced.Span.length(span) })
}

add_page_references : KernelObject.Builder, List(KernelGate2Objects.PageObjects), KernelBalanced.Span -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelGate2PageObjects.Error)
add_page_references = |builder, pages, span| {
	var $objects = List.with_capacity(KernelBalanced.Span.length(span))
	var $index = KernelBalanced.Span.start(span)
	end = $index + KernelBalanced.Span.length(span)
	while $index < end {
		$objects = $objects.append(list_at(pages, $index).page)
		$index = $index + 1
	}
	add_references(builder, $objects)
}

add_tree_references : KernelObject.Builder, List(KernelObject.ObjectId), KernelBalanced.Span -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelGate2PageObjects.Error)
add_tree_references = |builder, objects, span| {
	var $children = List.with_capacity(KernelBalanced.Span.length(span))
	var $index = KernelBalanced.Span.start(span)
	end = $index + KernelBalanced.Span.length(span)
	while $index < end {
		$children = $children.append(list_at(objects, $index))
		$index = $index + 1
	}
	add_references(builder, $children)
}

add_references : KernelObject.Builder, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelGate2PageObjects.Error)
add_references = |builder, objects| {
	var $builder = builder
	var $values = List.with_capacity(objects.len())
	var $index = 0
	var $error = NoError
	while $index < objects.len() and $error == NoError {
		match KernelObject.add_reference($builder, list_at(objects, $index)) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(reference) => {
				$builder = reference.builder
				$values = $values.append(reference.id)
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => Ok({ builder: $builder, values: $values })
	}
}

add_pages : KernelObject.Builder, Names, KernelObject.ValueId, KernelTagged.Plan, KernelContent.Plan, KernelGate2Objects.Plan -> Try(KernelObject.Builder, KernelGate2PageObjects.Error)
add_pages = |builder, names, resources, tagged, content, objects| {
	scenes = KernelTagged.Plan.scenes(tagged)
	page_objects = KernelGate2Objects.Plan.pages(objects)
	shape = KernelGate2Objects.Plan.page_tree_shape(objects)
	leaf_offset = KernelBalanced.Shape.level_offset(shape, KernelBalanced.Shape.leaf_level(shape))
	page_type = KernelObject.add_name_value(builder, names.page) ? Object
	tabs_s = KernelObject.add_name_value(page_type.builder, names.s) ? Object
	var $builder = tabs_s.builder
	var $index = 0
	var $error = NoError
	while $index < scenes.pages.len() and $error == NoError {
		page = list_at(scenes.pages, $index)
		planned = list_at(page_objects, $index)
		parent_index = leaf_offset + U64.div_by($index, KernelBalanced.Shape.fanout)
		match add_page($builder, names, resources, page_type.id, tabs_s.id, page, KernelContent.Plan.stream(content, Semantics.ContentStreamId.from_index($index)), list_at(KernelGate2Objects.Plan.page_tree(objects), parent_index), planned) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(next) => {
				$builder = next
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($builder)
	}
}

add_page : KernelObject.Builder, Names, KernelObject.ValueId, KernelObject.ValueId, KernelObject.ValueId, Scene.Page, KernelContent.Stream, KernelObject.ObjectId, KernelGate2Objects.PageObjects -> Try(KernelObject.Builder, KernelGate2PageObjects.Error)
add_page = |builder, names, resources, page_type, tabs_s, page, content, parent_object, planned| {
	art = add_rect(builder, page.boxes.art)?
	bleed = add_rect(art.builder, page.boxes.bleed)?
	contents = KernelObject.add_reference(bleed.builder, planned.content.stream) ? Object
	crop = add_rect(contents.builder, page.boxes.crop)?
	media = add_rect(crop.builder, page.boxes.media)?
	parent = KernelObject.add_reference(media.builder, parent_object) ? Object
	rotate = KernelObject.add_integer(parent.builder, rotation_degrees(page.rotation)) ? Object
	struct_parents = KernelObject.add_integer(rotate.builder, content.stream.index().to_i64_wrap()) ? Object
	trim = add_rect(struct_parents.builder, page.boxes.trim)?
	dictionary = KernelObject.add_dictionary(
		trim.builder,
		[
			{ key: names.art_box, value: art.value },
			{ key: names.bleed_box, value: bleed.value },
			{ key: names.contents, value: contents.id },
			{ key: names.crop_box, value: crop.value },
			{ key: names.media_box, value: media.value },
			{ key: names.parent, value: parent.id },
			{ key: names.resources, value: resources },
			{ key: names.rotate, value: rotate.id },
			{ key: names.struct_parents, value: struct_parents.id },
			{ key: names.tabs, value: tabs_s },
			{ key: names.trim_box, value: trim.value },
			{ key: names.type_name, value: page_type },
		],
	) ? Object
	page_object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(page_object.id, planned.page)?
	payload = KernelObject.add_payload(page_object.builder, content.bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(payload.builder, [], Deflate, payload.id) ? Object
	ensure_object(stream.id, planned.content.stream)?
	ensure_object(stream.length_object, planned.content.length)?
	Ok(stream.builder)
}

add_rect : KernelObject.Builder, Layout.Rect -> Try({ builder : KernelObject.Builder, value : KernelObject.ValueId }, KernelGate2PageObjects.Error)
add_rect = |builder, rect| {
	x0 = add_layout(builder, rect.origin.x)?
	y0 = add_layout(x0.builder, rect.origin.y)?
	x1 = add_layout(y0.builder, Layout.Unit.from_raw(rect.origin.x.raw() + rect.size.width.raw()))?
	y1 = add_layout(x1.builder, Layout.Unit.from_raw(rect.origin.y.raw() + rect.size.height.raw()))?
	array = KernelObject.add_array(y1.builder, [x0.id, y0.id, x1.id, y1.id]) ? Object
	Ok({ builder: array.builder, value: array.id })
}

add_layout : KernelObject.Builder, Layout.Unit -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2PageObjects.Error)
add_layout = |builder, value| {
	decimal = match KernelLex.Decimal.from_coefficient(value.raw(), 3) {
		Err(_) => {
			crash "fixed Gate 2 page scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

rotation_degrees : Scene.Rotation -> I64
rotation_degrees = |rotation| match rotation {
	Rotate0 => 0
	Rotate90 => 90
	Rotate180 => 180
	Rotate270 => 270
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelGate2PageObjects.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated Gate 2 page-object index escaped"
	}
}

test_limits : KernelObject.Limits
test_limits = {
	max_array_items: 128,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 256,
	max_direct_depth: 8,
	max_name_bytes: 2048,
	max_names: 96,
	max_objects: 16,
	max_payload_bytes: 512,
	max_payloads: 1,
	max_streams: 1,
	max_text_string_bytes: 64,
	max_text_strings: 1,
	max_values: 512,
}

## Page lowering consumes the planned page-tree, page, stream, and length IDs.
expect {
	pipeline = KernelGate2PipelineFixture.pipeline({})?
	prefix = KernelGate2TaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, test_limits)?
	plan = KernelGate2PageObjects.Plan.build(prefix, pipeline.tagged, pipeline.content, pipeline.objects)?
	counts = KernelObject.counts(KernelGate2PageObjects.Plan.builder(plan))
	first_color = list_at(KernelGate2Objects.Plan.color_spaces(pipeline.objects), 0)
	work = KernelGate2PageObjects.Plan.work(plan)
	counts.objects + 1 == KernelObject.ObjectId.number(first_color) and counts.payloads == 1 and counts.streams == 1 and work.pages == 1 and work.page_tree_nodes == 1 and work.page_tree_edges == 1 and work.box_values == 5 and work.resource_references == 2
}

## The additive Gate 3 path references each planned Type 0 font without widening Gate 2 plans.
expect {
	pipeline = KernelGate2PipelineFixture.pipeline({})?
	fonts = KernelGate3FontObjects.Plan.build(pipeline.objects, 1, 24)?
	prefix = KernelGate2TaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, { ..test_limits, max_objects: 24 })?
	plan = KernelGate2PageObjects.Plan.build_with_fonts(prefix, pipeline.tagged, pipeline.content, fonts)?
	work = KernelGate2PageObjects.Plan.work(plan)
	font = list_at(KernelGate3FontObjects.Plan.fonts(fonts), 0)
	KernelObject.ObjectId.number(font.type0) == KernelGate3FontObjects.Plan.object_count(fonts) and work.resource_references == 3
}
