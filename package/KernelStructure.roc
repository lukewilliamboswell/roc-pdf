import KernelBalanced
import KernelDeflate
import KernelObject
import KernelSeal
import KernelSha256

ContentPlan : [Deflated(List(U8)), EmptyGenerated, Unchanged(List(U8))]

KernelStructure :: [].{
	PageSize := [A4, Letter]
	PageGeometry := [Fixed(PageSize), Variable]
	Error : [
		Deflate(KernelDeflate.Error),
		IdentityInputTooLarge,
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : U64 }),
		PageCountZero,
		PageLimitExceeded({ attempted : U64, limit : U64 }),
		PlanSizeOverflow,
		Seal(KernelSeal.Error),
		Shape(KernelBalanced.Error),
	]

	Plan :: {
		identity : [Blank, GeneratedContentDigest(List(U8)), NormalizedPlanDigest(List(U8)), UnchangedContentDigest(List(U8))],
		output_bound : U64,
		page_count : U64,
		page_geometry : PageGeometry,
		root : KernelObject.ObjectId,
		sealed : KernelSeal.Plan,
		tree_nodes : U64,
		xref_object : KernelObject.ObjectId,
	}.{
		identity : Plan -> [Blank, GeneratedContentDigest(List(U8)), NormalizedPlanDigest(List(U8)), UnchangedContentDigest(List(U8))]
		identity = |plan| plan.identity

		object_count : Plan -> U64
		object_count = |plan| KernelSeal.Plan.counts(plan.sealed).objects

		output_bound : Plan -> U64
		output_bound = |plan| plan.output_bound

		page_count : Plan -> U64
		page_count = |plan| plan.page_count

		page_geometry : Plan -> PageGeometry
		page_geometry = |plan| plan.page_geometry

		release_payload_bytes : Plan, KernelObject.PayloadId -> Plan
		release_payload_bytes = |plan, payload| Plan.{
			identity: plan.identity,
			output_bound: plan.output_bound,
			page_count: plan.page_count,
			page_geometry: plan.page_geometry,
			root: plan.root,
			sealed: KernelSeal.Plan.release_payload_bytes(plan.sealed, payload),
			tree_nodes: plan.tree_nodes,
			xref_object: plan.xref_object,
		}

		root : Plan -> KernelObject.ObjectId
		root = |plan| plan.root

		sealed : Plan -> KernelSeal.Plan
		sealed = |plan| plan.sealed

		tree_node_count : Plan -> U64
		tree_node_count = |plan| plan.tree_nodes

		xref_object : Plan -> KernelObject.ObjectId
		xref_object = |plan| plan.xref_object

		from_sealed : {
			identity : [Blank, GeneratedContentDigest(List(U8)), NormalizedPlanDigest(List(U8)), UnchangedContentDigest(List(U8))],
			output_bound : U64,
			page_count : U64,
			root : KernelObject.ObjectId,
			sealed : KernelSeal.Plan,
			tree_nodes : U64,
			xref_object : KernelObject.ObjectId,
		} -> Plan
		from_sealed = |facts| Plan.{
			identity: facts.identity,
			output_bound: facts.output_bound,
			page_count: facts.page_count,
			page_geometry: Variable,
			root: facts.root,
			sealed: facts.sealed,
			tree_nodes: facts.tree_nodes,
			xref_object: facts.xref_object,
		}
	}

	build_blank : U64, PageSize -> Try(Plan, Error)
	build_blank = |page_count, page_size| {
		if page_count == 0 {
			Err(PageCountZero)
		} else if page_count > max_pages {
			Err(PageLimitExceeded({ attempted: page_count, limit: max_pages }))
		} else {
			build_nonempty(page_count, page_size, EmptyGenerated)
		}
	}

	build_unchanged_stream_probe : List(U8) -> Try(Plan, Error)
	build_unchanged_stream_probe = |bytes| build_nonempty(1, A4, Unchanged(bytes))

	build_deflate_stream_probe : List(U8), U64 -> Try(Plan, Error)
	build_deflate_stream_probe = |bytes, max_input_bytes| {
		bound = KernelDeflate.output_bound(bytes.len()) ? Deflate
		_ = KernelDeflate.Plan.prepare(
			bytes,
			KernelDeflate.Limits.make({ max_input_bytes, max_output_bytes: bound }),
		) ? Deflate
		build_nonempty(1, A4, Deflated(bytes))
	}
}

max_pages : U64
max_pages = 1048576

build_nonempty : U64, KernelStructure.PageSize, ContentPlan -> Try(KernelStructure.Plan, KernelStructure.Error)
build_nonempty = |page_count, page_size, content_plan| {
	payload_bytes = content_plan_bytes(content_plan).len()
	payload_total = checked_times(page_count, payload_bytes)?
	payload_output = content_plan_output_bound(content_plan)?
	payload_output_total = checked_times(page_count, payload_output)?
	output_bound = checked_add(blank_output_bound(page_count)?, payload_output_total)?
	identity = match content_plan {
		Deflated(bytes) => GeneratedContentDigest(KernelSha256.digest(bytes) ? |_| IdentityInputTooLarge)
		EmptyGenerated => Blank
		Unchanged(bytes) => UnchangedContentDigest(KernelSha256.digest(bytes) ? |_| IdentityInputTooLarge)
	}
	shape = KernelBalanced.Shape.build(page_count, max_pages) ? Shape
	leaf_level = KernelBalanced.Shape.leaf_level(shape)
	leaf_count = KernelBalanced.Shape.level_node_count(shape, leaf_level)
	node_count = KernelBalanced.Shape.node_count(shape)
	object_limit = checked_add(checked_linear(page_count, 3, 1)?, node_count)?
	value_limit = checked_add(checked_add(checked_linear(page_count, 4, 9)?, checked_linear(node_count, 5, 0)?)?, leaf_count)?
	dictionary_limit = checked_add(checked_linear(page_count, 5, 1)?, checked_linear(node_count, 4, 0)?)?
	array_limit = checked_add(checked_add(page_count, node_count)?, 3)?

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
		max_payload_bytes: payload_total,
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

	page_tree = add_page_tree_nodes(
		catalog_object.builder,
		shape,
		{
			count: count_name.id,
			kids: kids_name.id,
			pages_type: pages_type.id,
			parent: parent_name.id,
			type_name: type_name.id,
		},
	)?

	zero_x = KernelObject.add_integer(page_tree, 0) ? Object
	zero_y = KernelObject.add_integer(zero_x.builder, 0) ? Object
	{ width, height } = page_dimensions(page_size)
	width_value = KernelObject.add_integer(zero_y.builder, width) ? Object
	height_value = KernelObject.add_integer(width_value.builder, height) ? Object
	media_box = KernelObject.add_array(
		height_value.builder,
		[zero_x.id, zero_y.id, width_value.id, height_value.id],
	) ? Object
	resources = KernelObject.add_dictionary(media_box.builder, []) ? Object
	parents = add_leaf_parent_references(resources.builder, shape)?

	finished = add_pages(
		parents.builder,
		shape,
		page_count,
		content_plan,
		{
			contents: contents_name.id,
			media_box: media_box_name.id,
			page_type: page_type.id,
			parent: parent_name.id,
			parent_values: parents.values,
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
			identity,
			output_bound,
			page_count,
			page_geometry: Fixed(page_size),
			root: catalog_object.id,
			sealed,
			tree_nodes: node_count,
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
	parent_values : List(KernelObject.ValueId),
	resources : KernelObject.NameId,
	resources_value : KernelObject.ValueId,
	type_name : KernelObject.NameId,
}

PageTreeFacts : {
	count : KernelObject.NameId,
	kids : KernelObject.NameId,
	pages_type : KernelObject.ValueId,
	parent : KernelObject.NameId,
	type_name : KernelObject.NameId,
}

add_page_tree_nodes : KernelObject.Builder, KernelBalanced.Shape, PageTreeFacts -> Try(KernelObject.Builder, KernelStructure.Error)
add_page_tree_nodes = |builder, shape, facts| {
	var $builder = builder
	var $level = 0
	var $error = NoError
	while $level < KernelBalanced.Shape.level_count(shape) and $error == NoError {
		level_nodes = KernelBalanced.Shape.level_node_count(shape, $level)
		var $node = 0
		while $node < level_nodes and $error == NoError {
			match add_page_tree_node($builder, shape, facts, $level, $node) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(next) => {
					$builder = next
				}
			}
			$node = $node + 1
		}
		$level = $level + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($builder)
	}
}

add_page_tree_node : KernelObject.Builder, KernelBalanced.Shape, PageTreeFacts, U64, U64 -> Try(KernelObject.Builder, KernelStructure.Error)
add_page_tree_node = |builder, shape, facts, level, node| {
	is_leaf = level == KernelBalanced.Shape.leaf_level(shape)
	child_span = if is_leaf {
		KernelBalanced.Shape.item_span(shape, level, node)
	} else {
		KernelBalanced.Shape.child_span(shape, level, node)
	}
	child_start = KernelBalanced.Span.start(child_span)
	child_count = KernelBalanced.Span.length(child_span)
	first_child = if is_leaf {
		page_object_number(shape, child_start)?
	} else {
		checked_add(2, child_start)?
	}
	stride = if is_leaf 3 else 1
	children = add_object_references(builder, first_child, child_count, stride)?
	kids = KernelObject.add_array(children.builder, children.values) ? Object
	item_span = KernelBalanced.Shape.item_span(shape, level, node)
	descendants = KernelBalanced.Span.length(item_span)
	count = KernelObject.add_integer(kids.builder, descendants.to_i64_wrap()) ? Object

	with_dictionary = if level == 0 {
		KernelObject.add_dictionary(
			count.builder,
			[
				{ key: facts.count, value: count.id },
				{ key: facts.kids, value: kids.id },
				{ key: facts.type_name, value: facts.pages_type },
			],
		) ? Object
	} else {
		parent_index = U64.div_by(node, KernelBalanced.Shape.fanout)
		parent_number = node_object_number(shape, level - 1, parent_index)?
		parent_object = KernelObject.ObjectId.from_number(parent_number) ? Object
		parent = KernelObject.add_reference(count.builder, parent_object) ? Object
		KernelObject.add_dictionary(
			parent.builder,
			[
				{ key: facts.count, value: count.id },
				{ key: facts.kids, value: kids.id },
				{ key: facts.parent, value: parent.id },
				{ key: facts.type_name, value: facts.pages_type },
			],
		) ? Object
	}

	object = KernelObject.add_object(with_dictionary.builder, with_dictionary.id) ? Object
	expected = node_object_number(shape, level, node)?
	ensure_object_number(object.id, expected)?
	Ok(object.builder)
}

add_object_references : KernelObject.Builder, U64, U64, U64 -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelStructure.Error)
add_object_references = |builder, first_number, count, stride| {
	var $builder = builder
	var $values = List.with_capacity(count)
	var $index = 0
	var $error = NoError
	while $index < count and $error == NoError {
		number = checked_linear($index, stride, first_number)?
		object = KernelObject.ObjectId.from_number(number) ? Object
		match KernelObject.add_reference($builder, object) {
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

add_leaf_parent_references : KernelObject.Builder, KernelBalanced.Shape -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelStructure.Error)
add_leaf_parent_references = |builder, shape| {
	leaf_level = KernelBalanced.Shape.leaf_level(shape)
	leaf_count = KernelBalanced.Shape.level_node_count(shape, leaf_level)
	first_leaf = node_object_number(shape, leaf_level, 0)?
	add_object_references(builder, first_leaf, leaf_count, 1)
}

add_pages : KernelObject.Builder, KernelBalanced.Shape, U64, ContentPlan, PageFacts -> Try(KernelObject.Builder, KernelStructure.Error)
add_pages = |builder, shape, page_count, content_plan, facts| {
	var $builder = builder
	var $index = 0
	var $error = NoError
	while $index < page_count and $error == NoError {
		page_number = page_object_number(shape, $index)?
		content_number = checked_add(page_number, 1)?
		leaf_index = U64.div_by($index, KernelBalanced.Shape.fanout)
		parent_value = list_at(facts.parent_values, leaf_index)

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
					{ key: facts.parent, value: parent_value },
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
						{ bytes, filter, kind } = match content_plan {
							Deflated(source) => { bytes: source, filter: Deflate, kind: Generated }
							EmptyGenerated => { bytes: [], filter: Deflate, kind: Generated }
							Unchanged(source) => { bytes: source, filter: Unfiltered, kind: UnchangedResource }
						}
						match KernelObject.add_payload(page_object.builder, bytes, kind) {
							Err(error) => {
								$error = Invalid(Object(error))
							}
							Ok(payload) => match KernelObject.add_stream_object(payload.builder, [], filter, payload.id) {
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

node_object_number : KernelBalanced.Shape, U64, U64 -> Try(U64, KernelStructure.Error)
node_object_number = |shape, level, index| checked_add(checked_add(2, KernelBalanced.Shape.level_offset(shape, level))?, index)

page_object_number : KernelBalanced.Shape, U64 -> Try(U64, KernelStructure.Error)
page_object_number = |shape, index| checked_linear(index, 3, checked_add(2, KernelBalanced.Shape.node_count(shape))?)

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "page-tree shape invariant failed"
	}
}

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

checked_times : U64, U64 -> Try(U64, KernelStructure.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(PlanSizeOverflow)
	Ok(total) => Ok(total)
}

blank_bytes_per_page_bound : U64
blank_bytes_per_page_bound = 1024

blank_fixed_bytes_bound : U64
blank_fixed_bytes_bound = 4096

blank_output_bound : U64 -> Try(U64, KernelStructure.Error)
blank_output_bound = |page_count| checked_add(checked_times(page_count, blank_bytes_per_page_bound)?, blank_fixed_bytes_bound)

content_plan_bytes : ContentPlan -> List(U8)
content_plan_bytes = |content_plan| match content_plan {
	Deflated(bytes) => bytes
	EmptyGenerated => []
	Unchanged(bytes) => bytes
}

content_plan_output_bound : ContentPlan -> Try(U64, KernelStructure.Error)
content_plan_output_bound = |content_plan| match content_plan {
	Deflated(bytes) => if bytes.is_empty() {
		Ok(0)
	} else {
		match KernelDeflate.output_bound(bytes.len()) {
			Err(error) => Err(Deflate(error))
			Ok(bound) => Ok(bound)
		}
	}
	EmptyGenerated => Ok(0)
	Unchanged(bytes) => Ok(bytes.len())
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

## Variable-page plans carry a normalized identity without pretending to use a fixed page size.
expect {
	blank = KernelStructure.build_blank(1, A4)?
	plan = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest([1, 2, 3]),
		output_bound: KernelStructure.Plan.output_bound(blank),
		page_count: 1,
		root: KernelStructure.Plan.root(blank),
		sealed: KernelStructure.Plan.sealed(blank),
		tree_nodes: KernelStructure.Plan.tree_node_count(blank),
		xref_object: KernelStructure.Plan.xref_object(blank),
	})
	geometry_ok = match KernelStructure.Plan.page_geometry(plan) {
		Variable => True
		Fixed(_) => False
	}
	identity_ok = match KernelStructure.Plan.identity(plan) {
		NormalizedPlanDigest([1, 2, 3]) => True
		_ => False
	}
	geometry_ok and identity_ok
}

## Nonempty generated bytes carry a checked DEFLATE bound and remain generated input.
expect {
	bytes = Str.to_utf8("BT /Span BMC EMC ET\n")
	plan = KernelStructure.build_deflate_stream_probe(bytes, bytes.len())?
	store = KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan))
	payload = list_at(store.payloads, 0)
	stream = list_at(store.streams, 0)
	compressed_bound = KernelDeflate.output_bound(bytes.len())?

	KernelStructure.Plan.output_bound(plan) == blank_output_bound(1)? + compressed_bound and
		payload.bytes == bytes and
			payload.kind == Generated and
				stream.filter == Deflate and
					match KernelStructure.Plan.identity(plan) {
						GeneratedContentDigest(digest) => digest.len() == 32
						_ => False
					}
}

## Multi-page lowering preserves deterministic three-object page slices.
expect {
	plan = KernelStructure.build_blank(3, Letter)?

	actual =
		\\nodes: ${Str.inspect(KernelStructure.Plan.tree_node_count(plan))}
		\\objects: ${Str.inspect(KernelStructure.Plan.object_count(plan))}
		\\xref: ${Str.inspect(KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)))}

	expected =
		\\nodes: 1
		\\objects: 11
		\\xref: 12

	actual == expected
}

## The 33rd page creates two leaf nodes under one fixed-fanout root.
expect {
	plan = KernelStructure.build_blank(33, A4)?

	actual =
		\\nodes: ${Str.inspect(KernelStructure.Plan.tree_node_count(plan))}
		\\objects: ${Str.inspect(KernelStructure.Plan.object_count(plan))}
		\\xref: ${Str.inspect(KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)))}

	expected =
		\\nodes: 3
		\\objects: 103
		\\xref: 104

	actual == expected
}

## Thousands of pages preserve one balanced depth and deterministic node counts.
expect {
	plan = KernelStructure.build_blank(4096, A4)?

	actual =
		\\nodes: ${Str.inspect(KernelStructure.Plan.tree_node_count(plan))}
		\\objects: ${Str.inspect(KernelStructure.Plan.object_count(plan))}

	expected =
		\\nodes: 133
		\\objects: 12422

	actual == expected
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

## The maximum accepted plan fixes a checked pre-emission output bound.
expect blank_output_bound(max_pages) == Ok(1073745920)

## An unchanged stream extends the sealed bound and identity without copying its bytes.
expect {
	bytes = [37, 32, 114, 101, 115, 111, 117, 114, 99, 101, 10]
	plan = KernelStructure.build_unchanged_stream_probe(bytes)?
	store = KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan))
	payload = list_at(store.payloads, 0)
	stream = list_at(store.streams, 0)

	KernelStructure.Plan.output_bound(plan) == blank_output_bound(1)? + bytes.len() and
		payload.bytes == bytes and
			payload.kind == UnchangedResource and
				stream.filter == Unfiltered and
					match KernelStructure.Plan.identity(plan) {
						UnchangedContentDigest(digest) => digest.len() == 32
						_ => False
					}
}
