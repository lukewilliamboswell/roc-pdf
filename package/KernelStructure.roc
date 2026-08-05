import KernelObject
import KernelSeal

KernelStructure :: [].{
	PageSize := [A4, Letter]
	Error : [
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : U64 }),
		PageCountZero,
		PageLimitExceeded({ attempted : U64, limit : U64 }),
		PlanSizeOverflow,
		Seal(KernelSeal.Error),
	]

	Plan :: {
		page_count : U64,
		root : KernelObject.ObjectId,
		sealed : KernelSeal.Plan,
		xref_object : KernelObject.ObjectId,
	}.{
		object_count : Plan -> U64
		object_count = |plan| KernelSeal.Plan.counts(plan.sealed).objects

		page_count : Plan -> U64
		page_count = |plan| plan.page_count

		root : Plan -> KernelObject.ObjectId
		root = |plan| plan.root

		sealed : Plan -> KernelSeal.Plan
		sealed = |plan| plan.sealed

		xref_object : Plan -> KernelObject.ObjectId
		xref_object = |plan| plan.xref_object
	}

	build_blank : U64, PageSize -> Try(Plan, Error)
	build_blank = |page_count, page_size| {
		if page_count == 0 {
			Err(PageCountZero)
		} else if page_count > max_pages {
			Err(PageLimitExceeded({ attempted: page_count, limit: max_pages }))
		} else {
			build_nonempty(page_count, page_size)
		}
	}
}

max_pages : U64
max_pages = 32

build_nonempty : U64, KernelStructure.PageSize -> Try(KernelStructure.Plan, KernelStructure.Error)
build_nonempty = |page_count, page_size| {
	object_limit = checked_linear(page_count, 3, 2)?
	value_limit = checked_linear(page_count, 4, 32)?
	dictionary_limit = checked_linear(page_count, 5, 5)?
	array_limit = checked_add(page_count, 4)?

	limits : KernelObject.Limits
	limits = {
		max_array_items: array_limit,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: dictionary_limit,
		max_direct_depth: 8,
		max_name_bytes: 128,
		max_names: 10,
		max_objects: object_limit,
		max_payload_bytes: 0,
		max_payloads: page_count,
		max_streams: page_count,
		max_text_string_bytes: 0,
		max_text_strings: 0,
		max_values: value_limit,
	}

	contents_name = KernelObject.add_name(KernelObject.init(limits), Str.to_utf8("Contents")) ? Object
	count_name = KernelObject.add_name(contents_name.builder, Str.to_utf8("Count")) ? Object
	kids_name = KernelObject.add_name(count_name.builder, Str.to_utf8("Kids")) ? Object
	media_box_name = KernelObject.add_name(kids_name.builder, Str.to_utf8("MediaBox")) ? Object
	page_name = KernelObject.add_name(media_box_name.builder, Str.to_utf8("Page")) ? Object
	pages_name = KernelObject.add_name(page_name.builder, Str.to_utf8("Pages")) ? Object
	parent_name = KernelObject.add_name(pages_name.builder, Str.to_utf8("Parent")) ? Object
	resources_name = KernelObject.add_name(parent_name.builder, Str.to_utf8("Resources")) ? Object
	type_name = KernelObject.add_name(resources_name.builder, Str.to_utf8("Type")) ? Object
	catalog_name = KernelObject.add_name(type_name.builder, Str.to_utf8("Catalog")) ? Object

	catalog_type = KernelObject.add_name_value(catalog_name.builder, catalog_name.id) ? Object
	pages_type = KernelObject.add_name_value(catalog_type.builder, pages_name.id) ? Object
	page_type = KernelObject.add_name_value(pages_type.builder, page_name.id) ? Object

	pages_id = KernelObject.ObjectId.from_number(2) ? Object
	pages_reference = KernelObject.add_reference(page_type.builder, pages_id) ? Object
	catalog = KernelObject.add_dictionary(
		pages_reference.builder,
		[
			{ key: pages_name.id, value: pages_reference.id },
			{ key: type_name.id, value: catalog_type.id },
		],
	) ? Object
	catalog_object = KernelObject.add_object(catalog.builder, catalog.id) ? Object
	ensure_object_number(catalog_object.id, 1)?

	page_references = add_page_references(catalog_object.builder, page_count)?
	kids = KernelObject.add_array(page_references.builder, page_references.values) ? Object
	count = KernelObject.add_integer(kids.builder, page_count.to_i64_wrap()) ? Object
	pages = KernelObject.add_dictionary(
		count.builder,
		[
			{ key: count_name.id, value: count.id },
			{ key: kids_name.id, value: kids.id },
			{ key: type_name.id, value: pages_type.id },
		],
	) ? Object
	pages_object = KernelObject.add_object(pages.builder, pages.id) ? Object
	ensure_object_number(pages_object.id, 2)?

	zero_x = KernelObject.add_integer(pages_object.builder, 0) ? Object
	zero_y = KernelObject.add_integer(zero_x.builder, 0) ? Object
	{ width, height } = page_dimensions(page_size)
	width_value = KernelObject.add_integer(zero_y.builder, width) ? Object
	height_value = KernelObject.add_integer(width_value.builder, height) ? Object
	media_box = KernelObject.add_array(
		height_value.builder,
		[zero_x.id, zero_y.id, width_value.id, height_value.id],
	) ? Object
	resources = KernelObject.add_dictionary(media_box.builder, []) ? Object
	parent = KernelObject.add_reference(resources.builder, pages_id) ? Object

	finished = add_pages(
		parent.builder,
		page_count,
		{
			contents: contents_name.id,
			media_box: media_box_name.id,
			page_type: page_type.id,
			parent: parent_name.id,
			parent_value: parent.id,
			resources: resources_name.id,
			resources_value: resources.id,
			type_name: type_name.id,
			media_box_value: media_box.id,
		},
	)?

	sealed = KernelSeal.seal(finished) ? Seal
	xref_number = checked_add(KernelSeal.Plan.counts(sealed).objects, 1)?
	xref_object = KernelObject.ObjectId.from_number(xref_number) ? Object

	Ok(
		KernelStructure.Plan.{
			page_count,
			root: catalog_object.id,
			sealed,
			xref_object,
		},
	)
}

PageFacts : {
	contents : KernelObject.NameId,
	media_box : KernelObject.NameId,
	media_box_value : KernelObject.ValueId,
	page_type : KernelObject.ValueId,
	parent : KernelObject.NameId,
	parent_value : KernelObject.ValueId,
	resources : KernelObject.NameId,
	resources_value : KernelObject.ValueId,
	type_name : KernelObject.NameId,
}

add_page_references : KernelObject.Builder, U64 -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelStructure.Error)
add_page_references = |builder, page_count| {
	var $builder = builder
	var $values = List.with_capacity(page_count)
	var $index = 0
	var $error = NoError
	while $index < page_count and $error == NoError {
		page_number = page_object_number($index)?
		page_object = KernelObject.ObjectId.from_number(page_number) ? Object
		match KernelObject.add_reference($builder, page_object) {
			Err(error) => {
				$error = Invalid(Object(error))
			}
			Ok(reference) => {
				$builder = reference.builder
				$values = $values.append(reference.id)
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ builder: $builder, values: $values })
	}
}

add_pages : KernelObject.Builder, U64, PageFacts -> Try(KernelObject.Builder, KernelStructure.Error)
add_pages = |builder, page_count, facts| {
	var $builder = builder
	var $index = 0
	var $error = NoError
	while $index < page_count and $error == NoError {
		page_number = page_object_number($index)?
		content_number = checked_add(page_number, 1)?

		content_object = KernelObject.ObjectId.from_number(content_number) ? Object
		match KernelObject.add_reference($builder, content_object) {
			Err(error) => {
				$error = Invalid(Object(error))
			}
			Ok(contents) => match KernelObject.add_dictionary(
				contents.builder,
				[
					{ key: facts.contents, value: contents.id },
					{ key: facts.media_box, value: facts.media_box_value },
					{ key: facts.parent, value: facts.parent_value },
					{ key: facts.resources, value: facts.resources_value },
					{ key: facts.type_name, value: facts.page_type },
				],
			) {
				Err(error) => {
					$error = Invalid(Object(error))
				}
				Ok(page) => match KernelObject.add_object(page.builder, page.id) {
					Err(error) => {
						$error = Invalid(Object(error))
					}
					Ok(page_object) => if KernelObject.ObjectId.number(page_object.id) != page_number {
						$error = Invalid(ObjectOrder({ actual: page_object.id, expected: page_number }))
					} else {
						match KernelObject.add_payload(page_object.builder, [], Generated) {
							Err(error) => {
								$error = Invalid(Object(error))
							}
							Ok(payload) => match KernelObject.add_stream_object(payload.builder, [], Deflate, payload.id) {
								Err(error) => {
									$error = Invalid(Object(error))
								}
								Ok(stream) => if KernelObject.ObjectId.number(stream.id) != content_number {
									$error = Invalid(ObjectOrder({ actual: stream.id, expected: content_number }))
								} else {
									$builder = stream.builder
								}
							}
						}
					}
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($builder)
	}
}

page_object_number : U64 -> Try(U64, KernelStructure.Error)
page_object_number = |index| checked_linear(index, 3, 3)

ensure_object_number : KernelObject.ObjectId, U64 -> Try({}, KernelStructure.Error)
ensure_object_number = |actual, expected|
	if KernelObject.ObjectId.number(actual) == expected {
		Ok({})
	} else {
		Err(ObjectOrder({ actual, expected }))
	}

page_dimensions : KernelStructure.PageSize -> { height : I64, width : I64 }
page_dimensions = |page_size| match page_size {
	A4 => { height: 842, width: 595 }
	Letter => { height: 792, width: 612 }
}

checked_linear : U64, U64, U64 -> Try(U64, KernelStructure.Error)
checked_linear = |value, multiplier, constant| {
	var $total = constant
	var $index = 0
	var $error = NoError
	while $index < multiplier and $error == NoError {
		match U64.plus_try($total, value) {
			Err(Overflow) => {
				$error = Overflowed
			}
			Ok(next) => {
				$total = next
			}
		}
		$index = $index + 1
	}

	match $error {
		Overflowed => Err(PlanSizeOverflow)
		NoError => Ok($total)
	}
}

checked_add : U64, U64 -> Try(U64, KernelStructure.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(PlanSizeOverflow)
	Ok(total) => Ok(total)
}

## One blank page lowers to catalog, pages, page, stream, and length objects.
expect {
	plan = KernelStructure.build_blank(1, A4)?

	actual =
		\\pages: ${Str.inspect(KernelStructure.Plan.page_count(plan))}
		\\objects: ${Str.inspect(KernelStructure.Plan.object_count(plan))}
		\\root: ${Str.inspect(KernelObject.ObjectId.number(KernelStructure.Plan.root(plan)))}
		\\xref: ${Str.inspect(KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)))}

	expected =
		\\pages: 1
		\\objects: 5
		\\root: 1
		\\xref: 6

	actual == expected
}

## Multi-page lowering preserves deterministic three-object page slices.
expect {
	plan = KernelStructure.build_blank(3, Letter)?

	KernelStructure.Plan.object_count(plan) == 11 and
		KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)) == 12
}

## Zero pages is a named structural failure and creates no partial plan.
expect match KernelStructure.build_blank(0, A4) {
	Err(PageCountZero) => True
	_ => False
}

## The explicit page limit rejects oversized work before allocating stores.
expect match KernelStructure.build_blank(max_pages + 1, A4) {
	Err(PageLimitExceeded({ attempted, limit })) => attempted == max_pages + 1 and limit == max_pages
	_ => False
}
