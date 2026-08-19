import KernelBalanced
import KernelDeflate
import KernelIdentity
import KernelObject
import KernelSeal
import KernelSha256

ContentPlan : [Deflated(List(U8)), EmptyGenerated, Unchanged(List(U8))]

## Document facts for the blank structural path: the validated catalog
## language, the canonical XMP packet bytes, and the packaged output-intent
## profile with its identifier facts. The caller has already validated all of
## them; this builder only lowers.
BlankFacts : {
	condition_identifier : Str,
	language : Str,
	profile_bytes : List(U8),
	profile_components : I64,
	registry_name : Str,
	xmp : List(U8),
}

DocumentFacts : [NoBlankFacts, WithBlankFacts(BlankFacts)]

KernelStructure :: [].{
	PageSize := [A4, Letter]
	PageGeometry := [Fixed(PageSize), Variable]
	Error : [
		Deflate(KernelDeflate.Error),
		Identity(KernelIdentity.Error),
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
			build_nonempty(page_count, page_size, EmptyGenerated, NoBlankFacts)
		}
	}

	## The blank structural plan extended with validated document facts: the
	## catalog gains `/Lang`, `/Metadata`, and `/OutputIntents`, and the plan
	## appends the uncompressed XMP metadata stream and the packaged ICC
	## profile stream after the page objects. The plan identity becomes the
	## sealed-store digest so distinct facts produce distinct file
	## identifiers.
	build_blank_with_facts : U64, PageSize, BlankFacts -> Try(Plan, Error)
	build_blank_with_facts = |page_count, page_size, facts| {
		if page_count == 0 {
			Err(PageCountZero)
		} else if page_count > max_pages {
			Err(PageLimitExceeded({ attempted: page_count, limit: max_pages }))
		} else {
			build_nonempty(page_count, page_size, EmptyGenerated, WithBlankFacts(facts))
		}
	}

	build_unchanged_stream_probe : List(U8) -> Try(Plan, Error)
	build_unchanged_stream_probe = |bytes| build_nonempty(1, A4, Unchanged(bytes), NoBlankFacts)

	build_deflate_stream_probe : List(U8), U64 -> Try(Plan, Error)
	build_deflate_stream_probe = |bytes, max_input_bytes| {
		bound = KernelDeflate.output_bound(bytes.len()) ? Deflate
		_ = KernelDeflate.Plan.prepare(
			bytes,
			KernelDeflate.Limits.make({ max_input_bytes, max_output_bytes: bound }),
		) ? Deflate
		build_nonempty(1, A4, Deflated(bytes), NoBlankFacts)
	}
}

max_pages : U64
max_pages = 1048576

build_nonempty : U64, KernelStructure.PageSize, ContentPlan, DocumentFacts -> Try(KernelStructure.Plan, KernelStructure.Error)
build_nonempty = |page_count, page_size, content_plan, facts| {
	payload_bytes = content_plan_bytes(content_plan).len()
	payload_total = checked_times(page_count, payload_bytes)?
	payload_output = content_plan_output_bound(content_plan)?
	payload_output_total = checked_times(page_count, payload_output)?
	facts_bound = facts_output_bound(facts)?
	output_bound = checked_add(checked_add(blank_output_bound(page_count)?, payload_output_total)?, facts_bound)?
	shape = KernelBalanced.Shape.build(page_count, max_pages) ? Shape
	leaf_level = KernelBalanced.Shape.leaf_level(shape)
	leaf_count = KernelBalanced.Shape.level_node_count(shape, leaf_level)
	node_count = KernelBalanced.Shape.node_count(shape)
	fact_budget = facts_limit_budget(facts)?
	object_limit = checked_add(checked_add(checked_linear(page_count, 3, 1)?, node_count)?, fact_budget.objects)?
	value_limit = checked_add(checked_add(checked_add(checked_linear(page_count, 4, 9)?, checked_linear(node_count, 5, 0)?)?, leaf_count)?, fact_budget.values)?
	dictionary_limit = checked_add(checked_add(checked_linear(page_count, 5, 1)?, checked_linear(node_count, 4, 0)?)?, fact_budget.dictionary_entries)?
	array_limit = checked_add(checked_add(checked_add(page_count, node_count)?, 3)?, fact_budget.array_items)?

	limits : KernelObject.Limits
	limits = {
		max_array_items: array_limit,
		max_byte_string_bytes: 0,
		max_byte_strings: 0,
		max_dictionary_entries: dictionary_limit,
		max_direct_depth: 8,
		max_name_bytes: checked_add(128, fact_budget.name_bytes)?,
		max_names: checked_add(10, fact_budget.names)?,
		max_objects: object_limit,
		max_payload_bytes: checked_add(payload_total, fact_budget.payload_bytes)?,
		max_payloads: checked_add(page_count, fact_budget.payloads)?,
		max_streams: checked_add(page_count, fact_budget.payloads)?,
		max_text_string_bytes: fact_budget.text_string_bytes,
		max_text_strings: fact_budget.text_strings,
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

	## Blank object numbering is catalog, page tree, then three objects per
	## page; document facts append the metadata stream and the ICC profile
	## stream (each with its length object) immediately after the pages.
	pages_end = checked_add(checked_add(1, KernelBalanced.Shape.node_count(shape))?, checked_times(page_count, 3)?)?
	prepared_facts = match facts {
		NoBlankFacts => { builder: pages_reference.builder, context: NoFactContext }
		WithBlankFacts(fact_data) => {
			fact_names = add_fact_names(pages_reference.builder)?
			metadata_id = KernelObject.ObjectId.from_number(checked_add(pages_end, 1)?) ? Object
			profile_id = KernelObject.ObjectId.from_number(checked_add(pages_end, 3)?) ? Object
			{
				builder: fact_names.builder,
				context: FactContext({ data: fact_data, metadata_id, names: fact_names.names, profile_id }),
			}
		}
	}
	catalog = match prepared_facts.context {
		NoFactContext => KernelObject.add_dictionary(
			prepared_facts.builder,
			[
				{ key: pages_name.id, value: pages_reference.id },
				{ key: type_name.id, value: catalog_type.id },
			],
		) ? Object
		FactContext({ data: fact_data, metadata_id, names: fact_names, profile_id }) => {
			lang_text = KernelObject.add_text_string(prepared_facts.builder, fact_data.language) ? Object
			lang_value = KernelObject.add_text_string_value(lang_text.builder, lang_text.id) ? Object
			metadata_reference = KernelObject.add_reference(lang_value.builder, metadata_id) ? Object
			destination = KernelObject.add_reference(metadata_reference.builder, profile_id) ? Object
			identifier_text = KernelObject.add_text_string(destination.builder, fact_data.condition_identifier) ? Object
			identifier_value = KernelObject.add_text_string_value(identifier_text.builder, identifier_text.id) ? Object
			registry_text = KernelObject.add_text_string(identifier_value.builder, fact_data.registry_name) ? Object
			registry_value = KernelObject.add_text_string_value(registry_text.builder, registry_text.id) ? Object
			subtype_value = KernelObject.add_name_value(registry_value.builder, fact_names.gts_pdfa1) ? Object
			intent_type_value = KernelObject.add_name_value(subtype_value.builder, fact_names.output_intent) ? Object
			intent = KernelObject.add_dictionary(
				intent_type_value.builder,
				[
					{ key: fact_names.dest_output_profile, value: destination.id },
					{ key: fact_names.output_condition_identifier, value: identifier_value.id },
					{ key: fact_names.registry_name, value: registry_value.id },
					{ key: fact_names.s, value: subtype_value.id },
					{ key: type_name.id, value: intent_type_value.id },
				],
			) ? Object
			intents = KernelObject.add_array(intent.builder, [intent.id]) ? Object
			KernelObject.add_dictionary(
				intents.builder,
				[
					{ key: fact_names.lang, value: lang_value.id },
					{ key: fact_names.metadata, value: metadata_reference.id },
					{ key: fact_names.output_intents, value: intents.id },
					{ key: pages_name.id, value: pages_reference.id },
					{ key: type_name.id, value: catalog_type.id },
				],
			) ? Object
		}
	}
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

	with_facts = match prepared_facts.context {
		NoFactContext => finished
		FactContext(context) => add_fact_streams(finished, type_name.id, context)?
	}
	sealed = KernelSeal.seal(with_facts) ? Seal
	identity = match prepared_facts.context {
		NoFactContext => match content_plan {
			Deflated(bytes) => GeneratedContentDigest(KernelSha256.digest(bytes) ? |_| IdentityInputTooLarge)
			EmptyGenerated => Blank
			Unchanged(bytes) => UnchangedContentDigest(KernelSha256.digest(bytes) ? |_| IdentityInputTooLarge)
		}
		FactContext(_) => {

			## With document facts the plan identity is the sealed-store
			## digest, so language, metadata, and intent facts change the file
			## identifier deterministically.
			plan_identity = KernelIdentity.digest(sealed) ? Identity
			NormalizedPlanDigest(plan_identity.digest)
		}
	}
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

BlankFactNames : {
	dest_output_profile : KernelObject.NameId,
	gts_pdfa1 : KernelObject.NameId,
	lang : KernelObject.NameId,
	metadata : KernelObject.NameId,
	n : KernelObject.NameId,
	output_condition_identifier : KernelObject.NameId,
	output_intent : KernelObject.NameId,
	output_intents : KernelObject.NameId,
	registry_name : KernelObject.NameId,
	s : KernelObject.NameId,
	subtype : KernelObject.NameId,
	xml : KernelObject.NameId,
}

FactContext : [
	FactContext({ data : BlankFacts, metadata_id : KernelObject.ObjectId, names : BlankFactNames, profile_id : KernelObject.ObjectId }),
	NoFactContext,
]

FactBudget : {
	array_items : U64,
	dictionary_entries : U64,
	name_bytes : U64,
	names : U64,
	objects : U64,
	payload_bytes : U64,
	payloads : U64,
	text_string_bytes : U64,
	text_strings : U64,
	values : U64,
}

facts_limit_budget : DocumentFacts -> Try(FactBudget, KernelStructure.Error)
facts_limit_budget = |facts| match facts {
	NoBlankFacts => Ok({
		array_items: 0,
		dictionary_entries: 0,
		name_bytes: 0,
		names: 0,
		objects: 0,
		payload_bytes: 0,
		payloads: 0,
		text_string_bytes: 0,
		text_strings: 0,
		values: 0,
	})
	WithBlankFacts(data) => {
		text_bytes = checked_add(
			checked_add(Str.to_utf8(data.language).len(), Str.to_utf8(data.condition_identifier).len())?,
			Str.to_utf8(data.registry_name).len(),
		)?
		payload_bytes = checked_add(data.xmp.len(), data.profile_bytes.len())?
		Ok({
			array_items: 2,
			dictionary_entries: 16,
			name_bytes: 128,
			names: 12,
			objects: 4,
			payload_bytes,
			payloads: 2,
			text_string_bytes: text_bytes,
			text_strings: 3,
			values: 24,
		})
	}
}

## The facts output bound covers the two appended stream payloads, the worst
## UTF-16 hex expansion of the three text strings, and a fixed allowance for
## the added dictionary syntax.
facts_output_bound : DocumentFacts -> Try(U64, KernelStructure.Error)
facts_output_bound = |facts| match facts {
	NoBlankFacts => Ok(0)
	WithBlankFacts(data) => {
		text_bytes = checked_add(
			checked_add(Str.to_utf8(data.language).len(), Str.to_utf8(data.condition_identifier).len())?,
			Str.to_utf8(data.registry_name).len(),
		)?
		payload_bytes = checked_add(data.xmp.len(), data.profile_bytes.len())?
		checked_add(checked_add(payload_bytes, checked_times(text_bytes, 4)?)?, 1024)
	}
}

add_fact_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : BlankFactNames }, KernelStructure.Error)
add_fact_names = |builder| {
	dest_output_profile = KernelObject.add_name(builder, Str.to_utf8("DestOutputProfile")) ? Object
	gts_pdfa1 = KernelObject.add_name(dest_output_profile.builder, Str.to_utf8("GTS_PDFA1")) ? Object
	lang = KernelObject.add_name(gts_pdfa1.builder, Str.to_utf8("Lang")) ? Object
	metadata = KernelObject.add_name(lang.builder, Str.to_utf8("Metadata")) ? Object
	n = KernelObject.add_name(metadata.builder, Str.to_utf8("N")) ? Object
	output_condition_identifier = KernelObject.add_name(n.builder, Str.to_utf8("OutputConditionIdentifier")) ? Object
	output_intent = KernelObject.add_name(output_condition_identifier.builder, Str.to_utf8("OutputIntent")) ? Object
	output_intents = KernelObject.add_name(output_intent.builder, Str.to_utf8("OutputIntents")) ? Object
	registry_name = KernelObject.add_name(output_intents.builder, Str.to_utf8("RegistryName")) ? Object
	s = KernelObject.add_name(registry_name.builder, Str.to_utf8("S")) ? Object
	subtype = KernelObject.add_name(s.builder, Str.to_utf8("Subtype")) ? Object
	xml = KernelObject.add_name(subtype.builder, Str.to_utf8("XML")) ? Object
	Ok({
		builder: xml.builder,
		names: {
			dest_output_profile: dest_output_profile.id,
			gts_pdfa1: gts_pdfa1.id,
			lang: lang.id,
			metadata: metadata.id,
			n: n.id,
			output_condition_identifier: output_condition_identifier.id,
			output_intent: output_intent.id,
			output_intents: output_intents.id,
			registry_name: registry_name.id,
			s: s.id,
			subtype: subtype.id,
			xml: xml.id,
		},
	})
}

## The metadata stream is the uncompressed canonical XMP packet; the profile
## stream is the packaged ICC payload shared as an unchanged resource.
add_fact_streams : KernelObject.Builder, KernelObject.NameId, { data : BlankFacts, metadata_id : KernelObject.ObjectId, names : BlankFactNames, profile_id : KernelObject.ObjectId } -> Try(KernelObject.Builder, KernelStructure.Error)
add_fact_streams = |builder, type_name, context| {
	subtype_value = KernelObject.add_name_value(builder, context.names.xml) ? Object
	metadata_type_value = KernelObject.add_name_value(subtype_value.builder, context.names.metadata) ? Object
	payload = KernelObject.add_payload(metadata_type_value.builder, context.data.xmp, Generated) ? Object
	stream = KernelObject.add_stream_object(
		payload.builder,
		[
			{ key: context.names.subtype, value: subtype_value.id },
			{ key: type_name, value: metadata_type_value.id },
		],
		Unfiltered,
		payload.id,
	) ? Object
	ensure_object_number(stream.id, KernelObject.ObjectId.number(context.metadata_id))?
	ensure_object_number(stream.length_object, KernelObject.ObjectId.number(context.metadata_id) + 1)?
	n_value = KernelObject.add_integer(stream.builder, context.data.profile_components) ? Object
	icc_payload = KernelObject.add_payload(n_value.builder, context.data.profile_bytes, UnchangedResource) ? Object
	icc_stream = KernelObject.add_stream_object(
		icc_payload.builder,
		[{ key: context.names.n, value: n_value.id }],
		Unfiltered,
		icc_payload.id,
	) ? Object
	ensure_object_number(icc_stream.id, KernelObject.ObjectId.number(context.profile_id))?
	ensure_object_number(icc_stream.length_object, KernelObject.ObjectId.number(context.profile_id) + 1)?
	Ok(icc_stream.builder)
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

## Document facts extend one blank page with the metadata and profile
## streams, a distinct sealed-plan identity, and the same page structure.
expect {
	facts : BlankFacts
	facts = {
		condition_identifier: "sRGB2014",
		language: "en-AU",
		profile_bytes: [0, 0, 0, 4],
		profile_components: 3,
		registry_name: "http://www.color.org",
		xmp: Str.to_utf8("<?xpacket?>"),
	}
	plan = KernelStructure.build_blank_with_facts(1, A4, facts)?
	other = KernelStructure.build_blank_with_facts(1, A4, { ..facts, language: "de-DE" })?
	store = KernelSeal.Plan.store(KernelStructure.Plan.sealed(plan))
	metadata_payload = list_at(store.payloads, 1)
	profile_payload = list_at(store.payloads, 2)
	identity_ok = match KernelStructure.Plan.identity(plan) {
		NormalizedPlanDigest(digest) => match KernelStructure.Plan.identity(other) {
			NormalizedPlanDigest(other_digest) => digest.len() == 32 and digest != other_digest
			_ => False
		}
		_ => False
	}

	KernelStructure.Plan.object_count(plan) == 9 and
		KernelObject.ObjectId.number(KernelStructure.Plan.xref_object(plan)) == 10 and
			metadata_payload.kind == Generated and
				metadata_payload.bytes == Str.to_utf8("<?xpacket?>") and
					profile_payload.kind == UnchangedResource and
						profile_payload.bytes == [0, 0, 0, 4] and
							identity_ok
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
