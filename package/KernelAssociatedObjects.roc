import KernelAssociatedFiles
import KernelBalanced
import KernelIndex
import KernelLex
import KernelNavigationObjects
import KernelObject

## ISO 19005-4:2020 6.9 and Annex A, ISO 32000-2:2020 7.7.4,
## 7.9.6, 7.11 and 14.13 with the published file-specification errata.
KernelAssociatedObjects :: [].{
	Error : [
		ArithmeticOverflow,
		InvalidAssociation,
		Object(KernelObject.Error),
		Index(KernelIndex.Error),
		Shape(KernelBalanced.Error),
		Tree(KernelNavigationObjects.Error),
	]

	Association : { file : KernelAssociatedFiles.Entry, specification : KernelObject.ObjectId, stream : KernelObject.ObjectId }
	Ownership : [NoAssociationOwnership, AssociationOwnership({ af : U64, embedded_files : U64 })]
	Input : [NoAssociatedFiles, WithAssociatedFiles(KernelAssociatedFiles.Plan)]
	Destinations : [DestsRootAt(KernelObject.ObjectId), NoDestsRoot]

	Plan : { associations : List(Association), nodes : List(KernelObject.ObjectId), shape : KernelBalanced.Shape, object_count : U64, xref : KernelObject.ObjectId }
	Planned : [NoAssociatedPlan, WithAssociatedPlan(Plan)]

	## One stream and its length plus an indirect file specification per
	## filename, then the name-tree nodes in canonical breadth-first order.
	plan : Input, U64 -> Try(Planned, Error)
	plan = |input, base| match input {
		NoAssociatedFiles => Ok(NoAssociatedPlan)
		WithAssociatedFiles(files) => {
			entries = KernelAssociatedFiles.Plan.entries(files)
			if base > U64.highest - (5 * entries.len() + 2) {
				return Err(ArithmeticOverflow)
			}
			shape = KernelBalanced.Shape.build(entries.len(), KernelAssociatedFiles.limits.count) ? Shape
			var $associations = List.with_capacity(entries.len())
			var $number = base + 1
			for file in entries {
				stream = KernelObject.ObjectId.from_number($number) ? Object
				specification = KernelObject.ObjectId.from_number($number + 2) ? Object
				$associations = $associations.append({ file, specification, stream })
				$number = $number + 3
			}
			node_count = KernelBalanced.Shape.node_count(shape)
			var $nodes = List.with_capacity(node_count)
			var $index = 0
			while $index < node_count {
				object = KernelObject.ObjectId.from_number($number) ? Object
				$nodes = $nodes.append(object)
				$number = $number + 1
				$index = $index + 1
			}
			xref = KernelObject.ObjectId.from_number($number) ? Object
			Ok(WithAssociatedPlan({ associations: $associations, nodes: $nodes, shape, object_count: $number - 1, xref }))
		}
	}

	## Catalog AF and EmbeddedFiles refer to exactly the same file-specification
	## objects. Dests shares the single catalog Names dictionary when present.
	catalog_entries : KernelObject.Builder, Plan, Destinations -> Try({ builder : KernelObject.Builder, af : KernelObject.DictionaryEntry, names : KernelObject.DictionaryEntry }, Error)
	catalog_entries = |builder, planned, destinations| {
		af_key = name(builder, "AF")?
		af = add_af_array(af_key.builder, planned.associations)?
		dests = match destinations {
			NoDestsRoot => { builder: af.builder, entry: [] }
			DestsRootAt(root) => {
				key = name(af.builder, "Dests")?
				target = KernelObject.add_reference(key.builder, root) ? Object
				{ builder: target.builder, entry: [{ key: key.id, value: target.id }] }
			}
		}
		embedded_key = name(dests.builder, "EmbeddedFiles")?
		root = KernelObject.add_reference(embedded_key.builder, list_at(planned.nodes, 0)) ? Object
		names = KernelObject.add_dictionary(root.builder, dests.entry.append({ key: embedded_key.id, value: root.id })) ? Object
		names_key = name(names.builder, "Names")?
		Ok({ builder: names_key.builder, af: { key: af_key.id, value: af.id }, names: { key: names_key.id, value: names.id } })
	}

	## Append the typed files and verify the graph before sealing. Payloads
	## are handed to the ordinary unchanged-resource emission path as-is.
	lower : KernelObject.Builder, Plan, KernelObject.ObjectId -> Try({ builder : KernelObject.Builder, ownership : Ownership }, Error)
	lower = |builder, planned, catalog| {
		first_payload = KernelObject.counts(builder).payloads
		names = add_names(builder)?
		var $builder = names.builder
		var $entries = List.with_capacity(planned.associations.len())
		for association in planned.associations {
			lowered = add_association($builder, names.names, association)?
			$builder = lowered.builder
			$entries = $entries.append(KernelIndex.ByteEntry.make(association.file.key, lowered.id))
		}
		value_count = KernelObject.counts($builder).values
		tree = KernelIndex.ByteTree.build($entries, NameTree, KernelIndex.Limits.make({ max_entries: planned.associations.len(), max_key_bytes: 258, value_count })) ? Index
		emitted = KernelNavigationObjects.emit_name_tree($builder, names.names.tree, tree, planned.nodes) ? Tree
		ownership = verify(emitted.builder.store, planned, catalog, first_payload)?
		Ok({ builder: emitted.builder, ownership })
	}

	## Bound independent dictionary inspection before wrapping the store as
	## sealed. Exposed internally for atomic lowered-plan tests.
	verify : KernelObject.Store, Plan, KernelObject.ObjectId, U64 -> Try(Ownership, Error)
	verify = |store, planned, catalog, first_payload| verify_associations(store, planned, catalog, first_payload)
}

add_af_array : KernelObject.Builder, List(KernelAssociatedObjects.Association) -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelAssociatedObjects.Error)
add_af_array = |builder, associations| {
	var $builder = builder
	var $references = List.with_capacity(associations.len())
	for association in associations {
		reference = KernelObject.add_reference($builder, association.specification) ? Object
		$builder = reference.builder
		$references = $references.append(reference.id)
	}
	KernelObject.add_array($builder, $references).map_err(|error| Object(error))
}

Names : {
	af_relationship : KernelObject.NameId,
	desc : KernelObject.NameId,
	ef : KernelObject.NameId,
	embedded_file : KernelObject.NameId,
	f : KernelObject.NameId,
	filespec : KernelObject.NameId,
	mod_date : KernelObject.NameId,
	params : KernelObject.NameId,
	size : KernelObject.NameId,
	subtype : KernelObject.NameId,
	tree : KernelNavigationObjects.TreeNames,
	type_name : KernelObject.NameId,
	uf : KernelObject.NameId,
}

add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelAssociatedObjects.Error)
add_names = |builder| {
	relationship = name(builder, "AFRelationship")?
	desc = name(relationship.builder, "Desc")?
	ef = name(desc.builder, "EF")?
	embedded_file = name(ef.builder, "EmbeddedFile")?
	f = name(embedded_file.builder, "F")?
	filespec = name(f.builder, "Filespec")?
	kids = name(filespec.builder, "Kids")?
	limits = name(kids.builder, "Limits")?
	names = name(limits.builder, "Names")?
	mod_date = name(names.builder, "ModDate")?
	params = name(mod_date.builder, "Params")?
	size = name(params.builder, "Size")?
	subtype = name(size.builder, "Subtype")?
	type_name = name(subtype.builder, "Type")?
	uf = name(type_name.builder, "UF")?
	Ok({
		builder: uf.builder,
		names: {
			af_relationship: relationship.id,
			desc: desc.id,
			ef: ef.id,
			embedded_file: embedded_file.id,
			f: f.id,
			filespec: filespec.id,
			mod_date: mod_date.id,
			params: params.id,
			size: size.id,
			subtype: subtype.id,
			tree: { kids: kids.id, limits: limits.id, names: names.id },
			type_name: type_name.id,
			uf: uf.id,
		},
	})
}

add_association : KernelObject.Builder, Names, KernelAssociatedObjects.Association -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelAssociatedObjects.Error)
add_association = |builder, names, { file, specification, stream }| {
	payload = KernelObject.add_payload(builder, file.bytes, UnchangedResource) ? Object
	embedded_type = KernelObject.add_name_value(payload.builder, names.embedded_file) ? Object
	media_name = KernelObject.add_name(embedded_type.builder, file.media_type) ? Object
	media_value = KernelObject.add_name_value(media_name.builder, media_name.id) ? Object
	size = KernelObject.add_integer(media_value.builder, file.bytes.len().to_i64_wrap()) ? Object
	mod_date = text(size.builder, file.modified)?
	params = KernelObject.add_dictionary(mod_date.builder, [{ key: names.mod_date, value: mod_date.id }, { key: names.size, value: size.id }]) ? Object
	embedded = KernelObject.add_stream_object(
		params.builder,
		[
			{ key: names.params, value: params.id },
			{ key: names.subtype, value: media_value.id },
			{ key: names.type_name, value: embedded_type.id },
		],
		Unfiltered,
		payload.id,
	) ? Object
	if embedded.id != stream {
		return Err(InvalidAssociation)
	}
	target = KernelObject.add_reference(embedded.builder, stream) ? Object
	ef = KernelObject.add_dictionary(target.builder, [{ key: names.f, value: target.id }, { key: names.uf, value: target.id }]) ? Object
	relation = name(ef.builder, relationship_name(file.relationship))?
	relation_value = KernelObject.add_name_value(relation.builder, relation.id) ? Object
	description = text(relation_value.builder, file.description)?
	filename = text(description.builder, file.legacy_filename)?
	unicode_filename = text(filename.builder, file.filename)?
	spec_type = KernelObject.add_name_value(unicode_filename.builder, names.filespec) ? Object
	dictionary = KernelObject.add_dictionary(
		spec_type.builder,
		[
			{ key: names.af_relationship, value: relation_value.id },
			{ key: names.desc, value: description.id },
			{ key: names.ef, value: ef.id },
			{ key: names.f, value: filename.id },
			{ key: names.type_name, value: spec_type.id },
			{ key: names.uf, value: unicode_filename.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	if object.id != specification {
		return Err(InvalidAssociation)
	}
	reference = KernelObject.add_reference(object.builder, specification) ? Object
	Ok(reference)
}

relationship_name : KernelAssociatedFiles.Relationship -> Str
relationship_name = |value| match value {
	Alternative => "Alternative"
	Data => "Data"
	Source => "Source"
	Supplement => "Supplement"
}

name : KernelObject.Builder, Str -> Try({ builder : KernelObject.Builder, id : KernelObject.NameId }, KernelAssociatedObjects.Error)
name = |builder, value| KernelObject.add_name(builder, Str.to_utf8(value)).map_err(|error| Object(error))

text : KernelObject.Builder, Str -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelAssociatedObjects.Error)
text = |builder, value| {
	string = KernelObject.add_text_string(builder, value) ? Object
	KernelObject.add_text_string_value(string.builder, string.id).map_err(|error| Object(error))
}

list_at : List(a), U64 -> a
list_at = |list, index| list.get(index) ?? crash "planned associated-file index escaped its list"

verify_associations : KernelObject.Store, KernelAssociatedObjects.Plan, KernelObject.ObjectId, U64 -> Try(KernelAssociatedObjects.Ownership, KernelAssociatedObjects.Error)
verify_associations = |store, planned, catalog, first_payload| {
	if store.objects.len() != planned.object_count or store.payloads.len() != first_payload + planned.associations.len() {
		return Err(InvalidAssociation)
	}

	catalog_fields = object_dictionary(store, catalog)?
	af = field_entry(store, catalog_fields, "AF")?
	af_entries = array(store, value_at(store, af.value)?)?
	names = dictionary(value_at(store, field_entry(store, catalog_fields, "Names")?.value)?)?
	embedded_files = field_entry(store, names, "EmbeddedFiles")?
	if !ref_matches(value_at(store, embedded_files.value)?, list_at(planned.nodes, 0)) or af_entries.length != planned.associations.len() {
		return Err(InvalidAssociation)
	}
	var $index = 0
	for association in planned.associations {
		if !ref_matches(array_value(store, af_entries.start + $index)?, association.specification) {
			return Err(InvalidAssociation)
		}
		verify_file(store, association, first_payload + $index)?
		$index = $index + 1
	}
	verify_tree(store, planned)?
	Ok(AssociationOwnership({ af: af.index, embedded_files: embedded_files.index }))
}

verify_file : KernelObject.Store, KernelAssociatedObjects.Association, U64 -> Try({}, KernelAssociatedObjects.Error)
verify_file = |store, { file, specification, stream }, payload_index| {
	spec = object_dictionary(store, specification)?
	if spec.length != 6
		or !named(store, field(store, spec, "Type")?, Str.to_utf8("Filespec"))?
		or !named(store, field(store, spec, "AFRelationship")?, Str.to_utf8(relationship_name(file.relationship)))?
		or !text_matches(store, field(store, spec, "Desc")?, file.description)?
		or !text_matches(store, field(store, spec, "F")?, file.legacy_filename)?
		or !text_matches(store, field(store, spec, "UF")?, file.filename)? {
		return Err(InvalidAssociation)
	}
	ef = dictionary(field(store, spec, "EF")?)?
	if ef.length != 2 or !ref_matches(field(store, ef, "F")?, stream) or !ref_matches(field(store, ef, "UF")?, stream) {
		return Err(InvalidAssociation)
	}
	stream_id = match object_value(store, stream)? {
		Stream(id) => id
		_ => return Err(InvalidAssociation)
	}
	embedded = store.streams.get(KernelObject.StreamId.index(stream_id)) ? |_| InvalidAssociation
	source = store.payloads.get(payload_index) ? |_| InvalidAssociation
	if embedded.source != KernelObject.PayloadId.from_index(payload_index)
		or embedded.filter != Unfiltered
		or source.kind != UnchangedResource
		or source.bytes.len() != file.bytes.len()
		or embedded.dictionary.length != 3 {
		return Err(InvalidAssociation)
	}
	params = dictionary(field(store, embedded.dictionary, "Params")?)?
	if !named(store, field(store, embedded.dictionary, "Type")?, Str.to_utf8("EmbeddedFile"))?
		or !named(store, field(store, embedded.dictionary, "Subtype")?, file.media_type)?
		or params.length != 2
		or !text_matches(store, field(store, params, "ModDate")?, file.modified)?
		or !int_matches(field(store, params, "Size")?, file.bytes.len().to_i64_wrap()) {
		return Err(InvalidAssociation)
	}
	Ok({})
}

verify_tree : KernelObject.Store, KernelAssociatedObjects.Plan -> Try({}, KernelAssociatedObjects.Error)
verify_tree = |store, planned| {
	shape = planned.shape
	leaf_level = KernelBalanced.Shape.leaf_level(shape)
	var $level = 0
	while $level <= leaf_level {
		var $node = 0
		count = KernelBalanced.Shape.level_node_count(shape, $level)
		while $node < count {
			global_index = KernelBalanced.Shape.level_offset(shape, $level) + $node
			node_fields = object_dictionary(store, list_at(planned.nodes, global_index))?
			source = KernelBalanced.Shape.item_span(shape, $level, $node)
			start = KernelBalanced.Span.start(source)
			length = KernelBalanced.Span.length(source)
			if global_index == 0 {
				if node_fields.length != 1 {
					return Err(InvalidAssociation)
				}
			} else {
				limits = array(store, field(store, node_fields, "Limits")?)?
				if node_fields.length != 2 or limits.length != 2
					or !byte_string_matches(store, list_at(store.array_items, limits.start), list_at(planned.associations, start).file.key)?
					or !byte_string_matches(store, list_at(store.array_items, limits.start + 1), list_at(planned.associations, start + length - 1).file.key)? {
					return Err(InvalidAssociation)
				}
			}
			if $level == leaf_level {
				pairs = array(store, field(store, node_fields, "Names")?)?
				if pairs.length != length * 2 {
					return Err(InvalidAssociation)
				}
				var $slot = 0
				while $slot < length {
					expected = list_at(planned.associations, start + $slot)
					pair_index = pairs.start + 2 * $slot
					if !byte_string_matches(store, list_at(store.array_items, pair_index), expected.file.key)?
						or !ref_matches(array_value(store, pair_index + 1)?, expected.specification) {
						return Err(InvalidAssociation)
					}
					$slot = $slot + 1
				}
			} else {
				kids = array(store, field(store, node_fields, "Kids")?)?
				span = KernelBalanced.Shape.child_span(shape, $level, $node)
				if kids.length != KernelBalanced.Span.length(span) {
					return Err(InvalidAssociation)
				}
				var $slot = 0
				while $slot < kids.length {
					expected = list_at(planned.nodes, KernelBalanced.Span.start(span) + $slot)
					if !ref_matches(array_value(store, kids.start + $slot)?, expected) {
						return Err(InvalidAssociation)
					}
					$slot = $slot + 1
				}
			}
			$node = $node + 1
		}
		$level = $level + 1
	}
	Ok({})
}

object_value : KernelObject.Store, KernelObject.ObjectId -> Try(KernelObject.Value, KernelAssociatedObjects.Error)
object_value = |store, object_id| {
	object = store.objects.get(KernelObject.ObjectId.number(object_id) - 1) ? |_| InvalidAssociation
	match object.content {
		Stored(id) => value_at(store, id)
		LengthOf(_) => Err(InvalidAssociation)
	}
}

object_dictionary : KernelObject.Store, KernelObject.ObjectId -> Try(KernelObject.Span, KernelAssociatedObjects.Error)
object_dictionary = |store, id| dictionary(object_value(store, id)?)

dictionary : KernelObject.Value -> Try(KernelObject.Span, KernelAssociatedObjects.Error)
dictionary = |value| match value {
	Dictionary(span) => Ok(span)
	_ => Err(InvalidAssociation)
}

array : KernelObject.Store, KernelObject.Value -> Try(KernelObject.Span, KernelAssociatedObjects.Error)
array = |store, value| match value {
	Array(span) if span.start <= store.array_items.len() and span.length <= store.array_items.len() - span.start => Ok(span)
	_ => Err(InvalidAssociation)
}

array_value : KernelObject.Store, U64 -> Try(KernelObject.Value, KernelAssociatedObjects.Error)
array_value = |store, index| value_at(store, store.array_items.get(index) ? |_| InvalidAssociation)

value_at : KernelObject.Store, KernelObject.ValueId -> Try(KernelObject.Value, KernelAssociatedObjects.Error)
value_at = |store, id| store.values.get(KernelObject.ValueId.index(id)).map_err(|_| InvalidAssociation)

field : KernelObject.Store, KernelObject.Span, Str -> Try(KernelObject.Value, KernelAssociatedObjects.Error)
field = |store, span, key| value_at(store, field_entry(store, span, key)?.value)

field_entry : KernelObject.Store, KernelObject.Span, Str -> Try({ index : U64, value : KernelObject.ValueId }, KernelAssociatedObjects.Error)
field_entry = |store, span, key| {
	expected = Str.to_utf8(key)
	var $i = 0
	while $i < span.length {
		entry = store.dictionary_entries.get(span.start + $i) ? |_| InvalidAssociation
		encoded = store.names.get(KernelObject.NameId.index(entry.key)) ? |_| InvalidAssociation
		if KernelLex.Name.bytes(encoded) == expected {
			return Ok({ index: span.start + $i, value: entry.value })
		}
		$i = $i + 1
	}
	Err(InvalidAssociation)
}

named : KernelObject.Store, KernelObject.Value, List(U8) -> Try(Bool, KernelAssociatedObjects.Error)
named = |store, value, expected| match value {
	Name(id) => {
		encoded = store.names.get(KernelObject.NameId.index(id)) ? |_| InvalidAssociation
		Ok(KernelLex.Name.bytes(encoded) == expected)
	}
	_ => Ok(False)
}

text_matches : KernelObject.Store, KernelObject.Value, Str -> Try(Bool, KernelAssociatedObjects.Error)
text_matches = |store, value, expected| match value {
	TextString(id) => {
		encoded = store.text_strings.get(KernelObject.TextStringId.index(id)) ? |_| InvalidAssociation
		Ok(KernelLex.Text.bytes(encoded) == Str.to_utf8(expected))
	}
	_ => Ok(False)
}

byte_string_matches : KernelObject.Store, KernelObject.ValueId, List(U8) -> Try(Bool, KernelAssociatedObjects.Error)
byte_string_matches = |store, id, expected| match value_at(store, id)? {
	ByteString(string) => {
		actual = store.byte_strings.get(KernelObject.ByteStringId.index(string)) ? |_| InvalidAssociation
		Ok(actual == expected)
	}
	_ => Ok(False)
}

ref_matches : KernelObject.Value, KernelObject.ObjectId -> Bool
ref_matches = |value, expected| match value {
	Reference(id) => id == expected
	_ => False
}

int_matches : KernelObject.Value, I64 -> Bool
int_matches = |value, expected| match value {
	Integer(actual) => actual == expected
	_ => False
}
