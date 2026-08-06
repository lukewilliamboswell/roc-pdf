import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelGate2Identity
import KernelGate2OutputBound
import KernelGate2ResourceName
import KernelLex
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelStructure
import Layout

KernelGate3TextStructure :: [].{
	Error : [
		ArithmeticOverflow,
		Font(KernelPdfFont.Error),
		FontCountMismatch({ fonts : U64, mappings : U64 }),
		Identity(KernelGate2Identity.Error),
		Object(KernelObject.Error),
		ObjectCountMismatch({ actual : U64, expected : U64 }),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
		OutputBound(KernelGate2OutputBound.Error),
		PageSizeInvalid,
		Seal(KernelSeal.Error),
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
		fonts : U64,
		objects : U64,
		payload_bytes : U64,
	}

	Plan :: { font_objects : List(KernelPdfFont.Objects), structure : KernelStructure.Plan, work : Work }.{
		build : KernelPdfText.Plan, List(FontInput), Layout.Size, Limits -> Try(Plan, Error)
		build = |text, fonts, page_size, limits| build_plan(text, fonts, page_size, limits)

		font_objects : Plan -> List(KernelPdfFont.Objects)
		font_objects = |plan| plan.font_objects

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Names := {
	catalog : KernelObject.NameId,
	contents : KernelObject.NameId,
	count : KernelObject.NameId,
	font : KernelObject.NameId,
	font_resources : List(KernelObject.NameId),
	kids : KernelObject.NameId,
	media_box : KernelObject.NameId,
	page : KernelObject.NameId,
	pages : KernelObject.NameId,
	parent : KernelObject.NameId,
	resources : KernelObject.NameId,
	type_name : KernelObject.NameId,
}

build_plan : KernelPdfText.Plan, List(KernelGate3TextStructure.FontInput), Layout.Size, KernelGate3TextStructure.Limits -> Try(KernelGate3TextStructure.Plan, KernelGate3TextStructure.Error)
build_plan = |text, fonts, page_size, limits| {
	mappings = KernelPdfText.Plan.mappings(text)
	if fonts.len() == 0 or fonts.len() != mappings.len() {
		return Err(FontCountMismatch({ fonts: fonts.len(), mappings: mappings.len() }))
	}
	if page_size.width.raw() <= 0 or page_size.height.raw() <= 0 {
		return Err(PageSizeInvalid)
	}
	font_object_count = checked_times(fonts.len(), objects_per_font)?
	object_count = checked_add(base_object_count, font_object_count)?
	xref = object_id(checked_add(object_count, 1)?)
	added_names = add_names(KernelObject.init(limits.object_limits), fonts.len())?
	catalog = add_catalog(added_names.builder, added_names.names)?
	pages = add_pages(catalog, added_names.names)?
	page = add_page(pages, added_names.names, page_size, fonts.len())?
	content = add_content(page, KernelPdfText.Plan.bytes(text))?

	var $builder = content
	var $font_objects = List.with_capacity(fonts.len())
	var $font_index = 0
	var $font_bytes = 0
	while $font_index < fonts.len() {
		input = list_at(fonts, $font_index)
		font_plan = KernelPdfFont.Plan.build(
			$builder,
			input.font,
			input.plan,
			input.subset,
			input.descriptor,
			list_at(mappings, $font_index),
			limits.font_limits,
		) ? Font
		objects = KernelPdfFont.Plan.objects(font_plan)
		expected_start = base_object_count + $font_index * objects_per_font + 1
		ensure_object(objects.font_file, object_id(expected_start))?
		ensure_object(objects.type0, object_id(expected_start + objects_per_font - 1))?
		$builder = KernelPdfFont.Plan.builder(font_plan)
		$font_objects = $font_objects.append(objects)
		$font_bytes = checked_add($font_bytes, KernelPdfFont.Plan.work(font_plan).font_program_bytes)?
		$font_index = $font_index + 1
	}
	if $builder.store.objects.len() != object_count {
		return Err(ObjectCountMismatch({ actual: $builder.store.objects.len(), expected: object_count }))
	}
	sealed = KernelSeal.seal($builder) ? Seal
	identity = KernelGate2Identity.digest(sealed) ? Identity
	bound = KernelGate2OutputBound.calculate(sealed, xref) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelGate2OutputBound.Bound.bytes(bound),
		page_count: 1,
		root: object_id(1),
		sealed,
		tree_nodes: 1,
		xref_object: xref,
	})
	Ok(
		KernelGate3TextStructure.Plan.{
			font_objects: $font_objects,
			structure,
			work: {
				content_bytes: KernelPdfText.Plan.bytes(text).len(),
				font_objects: font_object_count,
				fonts: fonts.len(),
				objects: object_count,
				payload_bytes: checked_add(KernelPdfText.Plan.bytes(text).len(), $font_bytes)?,
			},
		},
	)
}

add_names : KernelObject.Builder, U64 -> Try({ builder : KernelObject.Builder, names : Names }, KernelGate3TextStructure.Error)
add_names = |builder, font_count| {
	catalog = KernelObject.add_name(builder, Str.to_utf8("Catalog")) ? Object
	contents = KernelObject.add_name(catalog.builder, Str.to_utf8("Contents")) ? Object
	count = KernelObject.add_name(contents.builder, Str.to_utf8("Count")) ? Object
	var $builder = count.builder
	var $font_resources = List.with_capacity(font_count)
	var $font_index = 0
	var $error = NoError
	while $font_index < font_count and $error == NoError {
		match KernelObject.add_name($builder, font_resource_name($font_index)) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(added) => {
				$builder = added.builder
				$font_resources = $font_resources.append(added.id)
			}
		}
		$font_index = $font_index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => {
			font = KernelObject.add_name($builder, Str.to_utf8("Font")) ? Object
			kids = KernelObject.add_name(font.builder, Str.to_utf8("Kids")) ? Object
			media_box = KernelObject.add_name(kids.builder, Str.to_utf8("MediaBox")) ? Object
			page = KernelObject.add_name(media_box.builder, Str.to_utf8("Page")) ? Object
			pages = KernelObject.add_name(page.builder, Str.to_utf8("Pages")) ? Object
			parent = KernelObject.add_name(pages.builder, Str.to_utf8("Parent")) ? Object
			resources = KernelObject.add_name(parent.builder, Str.to_utf8("Resources")) ? Object
			type_name = KernelObject.add_name(resources.builder, Str.to_utf8("Type")) ? Object
			Ok({
				builder: type_name.builder,
				names: {
					catalog: catalog.id,
					contents: contents.id,
					count: count.id,
					font: font.id,
					font_resources: $font_resources,
					kids: kids.id,
					media_box: media_box.id,
					page: page.id,
					pages: pages.id,
					parent: parent.id,
					resources: resources.id,
					type_name: type_name.id,
				},
			})
		}
	}
}

add_catalog : KernelObject.Builder, Names -> Try(KernelObject.Builder, KernelGate3TextStructure.Error)
add_catalog = |builder, names| {
	pages = KernelObject.add_reference(builder, object_id(2)) ? Object
	type_value = KernelObject.add_name_value(pages.builder, names.catalog) ? Object
	dictionary = KernelObject.add_dictionary(type_value.builder, [{ key: names.pages, value: pages.id }, { key: names.type_name, value: type_value.id }]) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, object_id(1))?
	Ok(object.builder)
}

add_pages : KernelObject.Builder, Names -> Try(KernelObject.Builder, KernelGate3TextStructure.Error)
add_pages = |builder, names| {
	count = KernelObject.add_integer(builder, 1) ? Object
	page = KernelObject.add_reference(count.builder, object_id(3)) ? Object
	kids = KernelObject.add_array(page.builder, [page.id]) ? Object
	type_value = KernelObject.add_name_value(kids.builder, names.pages) ? Object
	dictionary = KernelObject.add_dictionary(type_value.builder, [{ key: names.count, value: count.id }, { key: names.kids, value: kids.id }, { key: names.type_name, value: type_value.id }]) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, object_id(2))?
	Ok(object.builder)
}

add_page : KernelObject.Builder, Names, Layout.Size, U64 -> Try(KernelObject.Builder, KernelGate3TextStructure.Error)
add_page = |builder, names, size, font_count| {
	contents = KernelObject.add_reference(builder, object_id(4)) ? Object
	zero = KernelObject.add_integer(contents.builder, 0) ? Object
	width = add_layout(zero.builder, size.width)?
	height = add_layout(width.builder, size.height)?
	media_box = KernelObject.add_array(height.builder, [zero.id, zero.id, width.id, height.id]) ? Object
	parent = KernelObject.add_reference(media_box.builder, object_id(2)) ? Object
	font_resources = add_font_resources(parent.builder, names, font_count)?
	resources = KernelObject.add_dictionary(font_resources.builder, [{ key: names.font, value: font_resources.value }]) ? Object
	type_value = KernelObject.add_name_value(resources.builder, names.page) ? Object
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.contents, value: contents.id },
			{ key: names.media_box, value: media_box.id },
			{ key: names.parent, value: parent.id },
			{ key: names.resources, value: resources.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, object_id(3))?
	Ok(object.builder)
}

add_font_resources : KernelObject.Builder, Names, U64 -> Try({ builder : KernelObject.Builder, value : KernelObject.ValueId }, KernelGate3TextStructure.Error)
add_font_resources = |builder, names, count| {
	var $builder = builder
	var $entries = List.with_capacity(count)
	var $index = 0
	var $error = NoError
	while $index < count and $error == NoError {
		type0_number = base_object_count + $index * objects_per_font + objects_per_font
		match KernelObject.add_reference($builder, object_id(type0_number)) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(reference) => {
				$builder = reference.builder
				$entries = $entries.append({ key: list_at(names.font_resources, $index), value: reference.id })
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => {
			dictionary = KernelObject.add_dictionary($builder, $entries) ? Object
			Ok({ builder: dictionary.builder, value: dictionary.id })
		}
	}
}

add_content : KernelObject.Builder, List(U8) -> Try(KernelObject.Builder, KernelGate3TextStructure.Error)
add_content = |builder, bytes| {
	payload = KernelObject.add_payload(builder, bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(payload.builder, [], Deflate, payload.id) ? Object
	ensure_object(stream.id, object_id(4))?
	ensure_object(stream.length_object, object_id(5))?
	Ok(stream.builder)
}

add_layout : KernelObject.Builder, Layout.Unit -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate3TextStructure.Error)
add_layout = |builder, value| {
	decimal = KernelLex.Decimal.from_coefficient(value.raw(), 3) ? |_| PageSizeInvalid
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

font_resource_name : U64 -> List(U8)
font_resource_name = |index| KernelGate2ResourceName.bytes("F", index)

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelGate3TextStructure.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

object_id : U64 -> KernelObject.ObjectId
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => {
		crash "checked Gate 3 object number escaped"
	}
	Ok(id) => id
}

checked_add : U64, U64 -> Try(U64, KernelGate3TextStructure.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelGate3TextStructure.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated Gate 3 text-structure index escaped"
	}
	Ok(value) => value
}

base_object_count : U64
base_object_count = 5

objects_per_font : U64
objects_per_font = 9
