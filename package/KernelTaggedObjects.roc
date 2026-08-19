import KernelObjectPlan
import KernelPipelineFixture
import KernelMetadata
import KernelNavigationObjects
import KernelObject
import KernelTagged
import Semantics

KernelTaggedObjects :: [].{

	## `AnnotationObjectUnplanned` protects paths that cannot lower annotation
	## objects: an annotation spine item on a plan without planned annotation
	## object identities is a structured rejection, never a silent drop.
	Error : [
		AnnotationObjectUnplanned({ annotation : U64 }),
		InvalidFigureAlternative({ node : U64 }),
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
	]

	Work : {
		annotation_entries : U64,
		contextual_artifacts : U64,
		k_items : U64,
		namespaces : U64,
		parent_entries : U64,
		parent_rows : U64,
		structure_elements : U64,
	}

	Plan :: { builder : KernelObject.Builder, navigation_names : [NoNavigationNames, WithNavigationNames(KernelNavigationObjects.Names)], work : Work }.{
		build : KernelTagged.Plan, KernelObjectPlan.Plan, KernelObject.Limits -> Try(Plan, Error)
		build = |tagged, objects, limits| build_plan(tagged, objects, NoCatalogFacts, NoNavigationObjects, limits)

		## Document facts extend the catalog with its validated language, the
		## planned metadata stream, and the packaged sRGB output intent whose
		## profile stream the planner has already assigned. `NoCatalogFacts`
		## keeps the plan byte-identical to `build`.
		build_with_facts : KernelTagged.Plan, KernelObjectPlan.Plan, KernelMetadata.CatalogFacts, KernelObject.Limits -> Try(Plan, Error)
		build_with_facts = |tagged, objects, facts, limits| build_plan(tagged, objects, facts, NoNavigationObjects, limits)

		## Navigation facts extend the prefix with the planned annotation,
		## named-destination, outline, and page-label identities: the catalog
		## gains its `/Names`, `/Outlines`, and `/PageLabels` entries, every
		## annotation spine item lowers as an OBJR object reference, and the
		## ParentTree gains one scalar row per annotation after the
		## content-stream rows. `NoNavigationObjects` keeps the plan
		## byte-identical to `build_with_facts`.
		build_with_navigation : KernelTagged.Plan, KernelObjectPlan.Plan, KernelMetadata.CatalogFacts, KernelNavigationObjects.TaggedFacts, KernelObject.Limits -> Try(Plan, Error)
		build_with_navigation = |tagged, objects, facts, navigation, limits| build_plan(tagged, objects, facts, navigation, limits)

		builder : Plan -> KernelObject.Builder
		builder = |plan| plan.builder

		navigation_names : Plan -> [NoNavigationNames, WithNavigationNames(KernelNavigationObjects.Names)]
		navigation_names = |plan| plan.navigation_names

		work : Plan -> Work
		work = |plan| plan.work
	}
}

NavigationLowering := [
	NoNavigationLowering,
	WithNavigationLowering(
		{
			annotation_objects : List(KernelObject.ObjectId),
			annotation_pages : List(Semantics.PageId),
			dests_root : [DestsRootAt(KernelObject.ObjectId), NoDestsRoot],
			names : KernelNavigationObjects.Names,
			ordered_annotations : List(U64),
			outline_root : [NoOutlineRoot, OutlineRootAt(KernelObject.ObjectId)],
			page_labels_root : [NoPageLabelsRoot, PageLabelsRootAt(KernelObject.ObjectId)],
		},
	),
]

Names := {
	a : KernelObject.NameId,
	artifact : KernelObject.NameId,
	catalog : KernelObject.NameId,
	k : KernelObject.NameId,
	mark_info : KernelObject.NameId,
	marked : KernelObject.NameId,
	mcid : KernelObject.NameId,
	mcr : KernelObject.NameId,
	namespaces : KernelObject.NameId,
	namespace : KernelObject.NameId,
	ns : KernelObject.NameId,
	nums : KernelObject.NameId,
	o : KernelObject.NameId,
	p : KernelObject.NameId,
	pages : KernelObject.NameId,
	pagination : KernelObject.NameId,
	parent_tree : KernelObject.NameId,
	parent_tree_next_key : KernelObject.NameId,
	pg : KernelObject.NameId,
	s : KernelObject.NameId,
	struct_elem : KernelObject.NameId,
	struct_tree_root : KernelObject.NameId,
	type_name : KernelObject.NameId,
}

build_plan : KernelTagged.Plan, KernelObjectPlan.Plan, KernelMetadata.CatalogFacts, KernelNavigationObjects.TaggedFacts, KernelObject.Limits -> Try(KernelTaggedObjects.Plan, KernelTaggedObjects.Error)
build_plan = |tagged, objects, facts, navigation, limits| {
	semantics = KernelTagged.Plan.semantics(tagged)
	added_names = add_names(KernelObject.init(limits))?
	prepared = match facts {
		NoCatalogFacts => { builder: added_names.builder, input: NoCatalogInput }
		WithCatalogFacts(input) => {
			fact_names = add_fact_names(added_names.builder)?
			{ builder: fact_names.builder, input: CatalogInput({ facts: input, names: fact_names.names }) }
		}
	}
	lowering = match navigation {
		NoNavigationObjects => { builder: prepared.builder, value: NoNavigationLowering }
		WithNavigationObjects(input) => {
			navigation_names = KernelNavigationObjects.add_names(prepared.builder) ? Object
			{
				builder: navigation_names.builder,
				value: WithNavigationLowering({
					annotation_objects: input.annotation_objects,
					annotation_pages: input.annotation_pages,
					dests_root: input.dests_root,
					names: navigation_names.names,
					ordered_annotations: input.ordered_annotations,
					outline_root: input.outline_root,
					page_labels_root: input.page_labels_root,
				}),
			}
		}
	}
	with_catalog = add_catalog(lowering.builder, added_names.names, prepared.input, lowering.value, objects)?
	with_root = add_structure_root(with_catalog, added_names.names, tagged, lowering.value, objects)?
	with_parent_tree = add_parent_tree(with_root, added_names.names, tagged, lowering.value, objects)?
	with_namespaces = add_namespaces(with_parent_tree, added_names.names, semantics, objects)?
	with_structure = add_structure_elements(with_namespaces, added_names.names, tagged, lowering.value, objects)?
	with_artifacts = add_contextual_artifacts(with_structure, added_names.names, semantics, objects)?
	annotation_entries = match lowering.value {
		NoNavigationLowering => 0
		WithNavigationLowering(input) => input.ordered_annotations.len()
	}
	Ok(
		KernelTaggedObjects.Plan.{
			builder: with_artifacts,
			navigation_names: match lowering.value {
				NoNavigationLowering => NoNavigationNames
				WithNavigationLowering(input) => WithNavigationNames(input.names)
			},
			work: {
				annotation_entries,
				contextual_artifacts: semantics.contextual_artifacts.len(),
				k_items: KernelTagged.Plan.k_items(tagged).len(),
				namespaces: semantics.namespaces.len(),
				parent_entries: KernelTagged.Plan.parent_entries(tagged).len(),
				parent_rows: KernelTagged.Plan.parent_rows(tagged).len(),
				structure_elements: semantics.nodes.len(),
			},
		},
	)
}

add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelTaggedObjects.Error)
add_names = |builder| {
	a = KernelObject.add_name(builder, Str.to_utf8("A")) ? Object
	artifact = KernelObject.add_name(a.builder, Str.to_utf8("Artifact")) ? Object
	catalog = KernelObject.add_name(artifact.builder, Str.to_utf8("Catalog")) ? Object
	k = KernelObject.add_name(catalog.builder, Str.to_utf8("K")) ? Object
	mark_info = KernelObject.add_name(k.builder, Str.to_utf8("MarkInfo")) ? Object
	marked = KernelObject.add_name(mark_info.builder, Str.to_utf8("Marked")) ? Object
	mcid = KernelObject.add_name(marked.builder, Str.to_utf8("MCID")) ? Object
	mcr = KernelObject.add_name(mcid.builder, Str.to_utf8("MCR")) ? Object
	namespace = KernelObject.add_name(mcr.builder, Str.to_utf8("Namespace")) ? Object
	namespaces = KernelObject.add_name(namespace.builder, Str.to_utf8("Namespaces")) ? Object
	ns = KernelObject.add_name(namespaces.builder, Str.to_utf8("NS")) ? Object
	nums = KernelObject.add_name(ns.builder, Str.to_utf8("Nums")) ? Object
	o = KernelObject.add_name(nums.builder, Str.to_utf8("O")) ? Object
	p = KernelObject.add_name(o.builder, Str.to_utf8("P")) ? Object
	pages = KernelObject.add_name(p.builder, Str.to_utf8("Pages")) ? Object
	pagination = KernelObject.add_name(pages.builder, Str.to_utf8("Pagination")) ? Object
	parent_tree = KernelObject.add_name(pagination.builder, Str.to_utf8("ParentTree")) ? Object
	parent_tree_next_key = KernelObject.add_name(parent_tree.builder, Str.to_utf8("ParentTreeNextKey")) ? Object
	pg = KernelObject.add_name(parent_tree_next_key.builder, Str.to_utf8("Pg")) ? Object
	s = KernelObject.add_name(pg.builder, Str.to_utf8("S")) ? Object
	struct_elem = KernelObject.add_name(s.builder, Str.to_utf8("StructElem")) ? Object
	struct_tree_root = KernelObject.add_name(struct_elem.builder, Str.to_utf8("StructTreeRoot")) ? Object
	type_name = KernelObject.add_name(struct_tree_root.builder, Str.to_utf8("Type")) ? Object
	Ok({
		builder: type_name.builder,
		names: {
			a: a.id,
			artifact: artifact.id,
			catalog: catalog.id,
			k: k.id,
			mark_info: mark_info.id,
			marked: marked.id,
			mcid: mcid.id,
			mcr: mcr.id,
			namespace: namespace.id,
			namespaces: namespaces.id,
			ns: ns.id,
			nums: nums.id,
			o: o.id,
			p: p.id,
			pages: pages.id,
			pagination: pagination.id,
			parent_tree: parent_tree.id,
			parent_tree_next_key: parent_tree_next_key.id,
			pg: pg.id,
			s: s.id,
			struct_elem: struct_elem.id,
			struct_tree_root: struct_tree_root.id,
			type_name: type_name.id,
		},
	})
}

## Names required only by document facts are added conditionally so plans
## without facts keep their exact name table and identity digest.
FactNames := {
	dest_output_profile : KernelObject.NameId,
	gts_pdfa1 : KernelObject.NameId,
	lang : KernelObject.NameId,
	metadata : KernelObject.NameId,
	output_condition_identifier : KernelObject.NameId,
	output_intent : KernelObject.NameId,
	output_intents : KernelObject.NameId,
	registry_name : KernelObject.NameId,
}

CatalogInputFacts : [CatalogInput({ facts : KernelMetadata.CatalogInput, names : FactNames }), NoCatalogInput]

add_fact_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : FactNames }, KernelTaggedObjects.Error)
add_fact_names = |builder| {
	dest_output_profile = KernelObject.add_name(builder, Str.to_utf8("DestOutputProfile")) ? Object
	gts_pdfa1 = KernelObject.add_name(dest_output_profile.builder, Str.to_utf8("GTS_PDFA1")) ? Object
	lang = KernelObject.add_name(gts_pdfa1.builder, Str.to_utf8("Lang")) ? Object
	metadata = KernelObject.add_name(lang.builder, Str.to_utf8("Metadata")) ? Object
	output_condition_identifier = KernelObject.add_name(metadata.builder, Str.to_utf8("OutputConditionIdentifier")) ? Object
	output_intent = KernelObject.add_name(output_condition_identifier.builder, Str.to_utf8("OutputIntent")) ? Object
	output_intents = KernelObject.add_name(output_intent.builder, Str.to_utf8("OutputIntents")) ? Object
	registry_name = KernelObject.add_name(output_intents.builder, Str.to_utf8("RegistryName")) ? Object
	Ok({
		builder: registry_name.builder,
		names: {
			dest_output_profile: dest_output_profile.id,
			gts_pdfa1: gts_pdfa1.id,
			lang: lang.id,
			metadata: metadata.id,
			output_condition_identifier: output_condition_identifier.id,
			output_intent: output_intent.id,
			output_intents: output_intents.id,
			registry_name: registry_name.id,
		},
	})
}

add_catalog : KernelObject.Builder, Names, CatalogInputFacts, NavigationLowering, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_catalog = |builder, names, catalog_input, navigation, objects| {
	marked = KernelObject.add_boolean(builder, True) ? Object
	mark_info = KernelObject.add_dictionary(marked.builder, [{ key: names.marked, value: marked.id }]) ? Object
	pages = KernelObject.add_reference(mark_info.builder, list_at(KernelObjectPlan.Plan.page_tree(objects), 0)) ? Object
	structure = KernelObject.add_reference(pages.builder, KernelObjectPlan.Plan.struct_tree_root(objects)) ? Object
	type_value = add_name_value(structure.builder, names.catalog)?
	metadata_values = match catalog_input {
		NoCatalogInput => { builder: type_value.builder, values: NoMetadataValues }
		CatalogInput({ facts, names: fact_names }) => {
			lang_text = KernelObject.add_text_string(type_value.builder, facts.language) ? Object
			lang_value = KernelObject.add_text_string_value(lang_text.builder, lang_text.id) ? Object
			metadata_reference = KernelObject.add_reference(lang_value.builder, facts.metadata_stream) ? Object
			intent = add_output_intent(metadata_reference.builder, names, fact_names, facts)?
			intents = KernelObject.add_array(intent.builder, [intent.id]) ? Object
			{ builder: intents.builder, values: WithMetadataValues({ fact_names, intents: intents.id, lang: lang_value.id, metadata: metadata_reference.id }) }
		}
	}
	navigation_values = match navigation {
		NoNavigationLowering => { builder: metadata_values.builder, values: NoNavigationValues }
		WithNavigationLowering(input) => {
			dests = match input.dests_root {
				NoDestsRoot => { builder: metadata_values.builder, value: NoValue }
				DestsRootAt(root) => {
					root_reference = KernelObject.add_reference(metadata_values.builder, root) ? Object
					dictionary = KernelObject.add_dictionary(root_reference.builder, [{ key: input.names.dests, value: root_reference.id }]) ? Object
					{ builder: dictionary.builder, value: WithValue(dictionary.id) }
				}
			}
			outline = match input.outline_root {
				NoOutlineRoot => { builder: dests.builder, value: NoValue }
				OutlineRootAt(root) => {
					root_reference = KernelObject.add_reference(dests.builder, root) ? Object
					{ builder: root_reference.builder, value: WithValue(root_reference.id) }
				}
			}
			labels = match input.page_labels_root {
				NoPageLabelsRoot => { builder: outline.builder, value: NoValue }
				PageLabelsRootAt(root) => {
					root_reference = KernelObject.add_reference(outline.builder, root) ? Object
					{ builder: root_reference.builder, value: WithValue(root_reference.id) }
				}
			}
			{ builder: labels.builder, values: WithNavigationValues({ dests: dests.value, labels: labels.value, names: input.names, outline: outline.value }) }
		}
	}
	var $entries = []
	match metadata_values.values {
		NoMetadataValues => {}
		WithMetadataValues(values) => {
			$entries = $entries.append({ key: values.fact_names.lang, value: values.lang })
		}
	}
	$entries = $entries.append({ key: names.mark_info, value: mark_info.id })
	match metadata_values.values {
		NoMetadataValues => {}
		WithMetadataValues(values) => {
			$entries = $entries.append({ key: values.fact_names.metadata, value: values.metadata })
		}
	}
	match navigation_values.values {
		NoNavigationValues => {}
		WithNavigationValues(values) => {
			match values.dests {
				NoValue => {}
				WithValue(value) => {
					$entries = $entries.append({ key: values.names.names, value })
				}
			}
			match values.outline {
				NoValue => {}
				WithValue(value) => {
					$entries = $entries.append({ key: values.names.outlines, value })
				}
			}
		}
	}
	match metadata_values.values {
		NoMetadataValues => {}
		WithMetadataValues(values) => {
			$entries = $entries.append({ key: values.fact_names.output_intents, value: values.intents })
		}
	}
	match navigation_values.values {
		NoNavigationValues => {}
		WithNavigationValues(values) => match values.labels {
			NoValue => {}
			WithValue(value) => {
				$entries = $entries.append({ key: values.names.page_labels, value })
			}
		}
	}
	$entries = $entries.append({ key: names.pages, value: pages.id })
	$entries = $entries.append({ key: names.struct_tree_root, value: structure.id })
	$entries = $entries.append({ key: names.type_name, value: type_value.id })
	dictionary = KernelObject.add_dictionary(navigation_values.builder, $entries) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, KernelObjectPlan.Plan.catalog(objects))?
	Ok(object.builder)
}

## The output intent is one direct dictionary inside the catalog's
## `/OutputIntents` array: the PDF/A subtype, the packaged profile's condition
## identifier and registry, and an indirect reference to the planned ICC
## profile stream that color spaces may also share.
add_output_intent : KernelObject.Builder, Names, FactNames, KernelMetadata.CatalogInput -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelTaggedObjects.Error)
add_output_intent = |builder, names, fact_names, facts| {
	destination = KernelObject.add_reference(builder, facts.profile_stream) ? Object
	identifier_text = KernelObject.add_text_string(destination.builder, facts.condition_identifier) ? Object
	identifier_value = KernelObject.add_text_string_value(identifier_text.builder, identifier_text.id) ? Object
	registry_text = KernelObject.add_text_string(identifier_value.builder, facts.registry_name) ? Object
	registry_value = KernelObject.add_text_string_value(registry_text.builder, registry_text.id) ? Object
	subtype_value = add_name_value(registry_value.builder, fact_names.gts_pdfa1)?
	intent_type_value = add_name_value(subtype_value.builder, fact_names.output_intent)?
	added = KernelObject.add_dictionary(
		intent_type_value.builder,
		[
			{ key: fact_names.dest_output_profile, value: destination.id },
			{ key: fact_names.output_condition_identifier, value: identifier_value.id },
			{ key: fact_names.registry_name, value: registry_value.id },
			{ key: names.s, value: subtype_value.id },
			{ key: names.type_name, value: intent_type_value.id },
		],
	) ? Object
	Ok(added)
}

add_structure_root : KernelObject.Builder, Names, KernelTagged.Plan, NavigationLowering, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_structure_root = |builder, names, tagged, navigation, objects| {
	semantics = KernelTagged.Plan.semantics(tagged)
	document = list_at(semantics.nodes, semantics.document_root.index())
	k = KernelObject.add_reference(builder, list_at(KernelObjectPlan.Plan.structure_elements(objects), document.structure_element.index())) ? Object
	namespace_refs = add_references(k.builder, KernelObjectPlan.Plan.namespaces(objects))?
	namespaces = KernelObject.add_array(namespace_refs.builder, namespace_refs.values) ? Object
	parent_tree = KernelObject.add_reference(namespaces.builder, KernelObjectPlan.Plan.parent_tree(objects)) ? Object
	annotation_keys = match navigation {
		NoNavigationLowering => 0
		WithNavigationLowering(input) => input.ordered_annotations.len()
	}
	next_key = KernelObject.add_integer(parent_tree.builder, (KernelTagged.Plan.parent_rows(tagged).len() + annotation_keys).to_i64_wrap()) ? Object
	type_value = add_name_value(next_key.builder, names.struct_tree_root)?
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.k, value: k.id },
			{ key: names.namespaces, value: namespaces.id },
			{ key: names.parent_tree, value: parent_tree.id },
			{ key: names.parent_tree_next_key, value: next_key.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, KernelObjectPlan.Plan.struct_tree_root(objects))?
	Ok(object.builder)
}

add_parent_tree : KernelObject.Builder, Names, KernelTagged.Plan, NavigationLowering, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_parent_tree = |builder, names, tagged, navigation, objects| {
	rows = KernelTagged.Plan.parent_rows(tagged)
	entries = KernelTagged.Plan.parent_entries(tagged)
	structure = KernelObjectPlan.Plan.structure_elements(objects)
	var $builder = builder
	var $numbers = List.with_capacity(rows.len() * 2)
	var $row_index = 0
	var $error = NoError
	while $row_index < rows.len() and $error == NoError {
		row = list_at(rows, $row_index)
		match KernelObject.add_integer($builder, row.content_stream.index().to_i64_wrap()) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(key) => match add_parent_entry_references(key.builder, entries, row.entries, structure) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(references) => match KernelObject.add_array(references.builder, references.values) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(array) => {
						$builder = array.builder
						$numbers = $numbers.append(key.id).append(array.id)
					}
				}
			}
		}
		$row_index = $row_index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => {
			match navigation {
				NoNavigationLowering => {}
				WithNavigationLowering(input) => {

					## One scalar ParentTree row per annotation after the
					## content-stream rows: the key is the annotation's
					## `/StructParent` value and the value is one direct
					## reference to its owning structure element.
					annotation_owners = KernelTagged.Plan.annotation_owners(tagged)
					var $ordinal = 0
					while $ordinal < input.ordered_annotations.len() {
						annotation = list_at(input.ordered_annotations, $ordinal)
						owner = list_at(annotation_owners, annotation)
						key = KernelObject.add_integer($builder, (rows.len() + $ordinal).to_i64_wrap()) ? Object
						value = KernelObject.add_reference(key.builder, list_at(structure, owner.index())) ? Object
						$builder = value.builder
						$numbers = $numbers.append(key.id).append(value.id)
						$ordinal = $ordinal + 1
					}
				}
			}
			nums = KernelObject.add_array($builder, $numbers) ? Object
			dictionary = KernelObject.add_dictionary(nums.builder, [{ key: names.nums, value: nums.id }]) ? Object
			object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
			ensure_object(object.id, KernelObjectPlan.Plan.parent_tree(objects))?
			Ok(object.builder)
		}
	}
}

add_namespaces : KernelObject.Builder, Names, Semantics.Store, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_namespaces = |builder, names, semantics, objects| {
	ids = KernelObjectPlan.Plan.namespaces(objects)
	var $builder = builder
	var $index = 0
	var $error = NoError
	while $index < semantics.namespaces.len() and $error == NoError {
		namespace = list_at(semantics.namespaces, $index)
		match add_namespace($builder, names, namespace, list_at(ids, namespace.id.index())) {
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

add_namespace : KernelObject.Builder, Names, Semantics.Namespace, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_namespace = |builder, names, namespace, expected| {
	text = KernelObject.add_text_string(builder, namespace.uri) ? Object
	text_value = KernelObject.add_text_string_value(text.builder, text.id) ? Object
	type_value = add_name_value(text_value.builder, names.namespace)?
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.ns, value: text_value.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, expected)?
	Ok(object.builder)
}

add_structure_elements : KernelObject.Builder, Names, KernelTagged.Plan, NavigationLowering, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_structure_elements = |builder, names, tagged, navigation, objects| {
	semantics = KernelTagged.Plan.semantics(tagged)
	nodes_by_structure = index_nodes_by_structure(semantics.nodes)
	ids = KernelObjectPlan.Plan.structure_elements(objects)
	var $builder = builder
	var $structure_index = 0
	var $error = NoError
	while $structure_index < ids.len() and $error == NoError {
		node = list_at(semantics.nodes, list_at(nodes_by_structure, $structure_index).index())
		match add_structure_element($builder, names, tagged, navigation, objects, node, list_at(ids, $structure_index)) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(next) => {
				$builder = next
			}
		}
		$structure_index = $structure_index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($builder)
	}
}

add_structure_element : KernelObject.Builder, Names, KernelTagged.Plan, NavigationLowering, KernelObjectPlan.Plan, Semantics.Node, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_structure_element = |builder, names, tagged, navigation, objects, node, expected| {
	semantics = KernelTagged.Plan.semantics(tagged)
	node_k = list_at(KernelTagged.Plan.node_k(tagged), node.id.index())
	k_values = add_k_items(builder, names, KernelTagged.Plan.k_items(tagged), node_k.items, navigation, objects)?
	k = KernelObject.add_array(k_values.builder, k_values.values) ? Object
	ns = KernelObject.add_reference(k.builder, list_at(KernelObjectPlan.Plan.namespaces(objects), node.role.namespace.index())) ? Object
	parent_object = match node.parent {
		DocumentRoot => KernelObjectPlan.Plan.struct_tree_root(objects)
		ParentNode(parent) => {
			parent_node = list_at(semantics.nodes, parent.index())
			list_at(KernelObjectPlan.Plan.structure_elements(objects), parent_node.structure_element.index())
		}
	}
	p = KernelObject.add_reference(ns.builder, parent_object) ? Object
	role_name = KernelObject.add_name(p.builder, Str.to_utf8(node.role.local_name)) ? Object
	s = KernelObject.add_name_value(role_name.builder, role_name.id) ? Object
	type_value = add_name_value(s.builder, names.struct_elem)?
	base_entries = if node_k.items.length() == 0 {
		[
			{ key: names.ns, value: ns.id },
			{ key: names.p, value: p.id },
			{ key: names.s, value: s.id },
			{ key: names.type_name, value: type_value.id },
		]
	} else {
		[
			{ key: names.k, value: k.id },
			{ key: names.ns, value: ns.id },
			{ key: names.p, value: p.id },
			{ key: names.s, value: s.id },
			{ key: names.type_name, value: type_value.id },
		]
	}
	with_alternative = if node.role.local_name == "Figure" {
		if node.text_properties.length() != 1 or node.text_properties.start() >= semantics.text_properties.len() {
			return Err(InvalidFigureAlternative({ node: node.id.index() }))
		}
		alternative = match list_at(semantics.text_properties, node.text_properties.start()) {
			AlternativeText(value) => value
			_ => return Err(InvalidFigureAlternative({ node: node.id.index() }))
		}
		alt_name = KernelObject.add_name(type_value.builder, Str.to_utf8("Alt")) ? Object
		alt_text = KernelObject.add_text_string(alt_name.builder, alternative) ? Object
		alt_value = KernelObject.add_text_string_value(alt_text.builder, alt_text.id) ? Object
		{ builder: alt_value.builder, entries: [{ key: alt_name.id, value: alt_value.id }].concat(base_entries) }
	} else {
		{ builder: type_value.builder, entries: base_entries }
	}
	dictionary = KernelObject.add_dictionary(with_alternative.builder, with_alternative.entries) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, expected)?
	Ok(object.builder)
}

add_k_items : KernelObject.Builder, Names, List(KernelTagged.KItem), Semantics.Range, NavigationLowering, KernelObjectPlan.Plan -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelTaggedObjects.Error)
add_k_items = |builder, names, items, range, navigation, objects| {
	var $builder = builder
	var $values = List.with_capacity(range.length())
	var $index = range.start()
	end = range.start() + range.length()
	var $error = NoError
	while $index < end and $error == NoError {
		item = list_at(items, $index)
		added = match item {
			AnnotationChild(annotation) => match navigation {
				NoNavigationLowering => return Err(AnnotationObjectUnplanned({ annotation: annotation.index() }))
				WithNavigationLowering(input) => add_objr($builder, names, input, annotation, objects)
			}
			ChildStructure(child) => KernelObject.add_reference($builder, list_at(KernelObjectPlan.Plan.structure_elements(objects), child.index()))
			ContextualArtifactChild(artifact) => KernelObject.add_reference($builder, list_at(KernelObjectPlan.Plan.contextual_artifacts(objects), artifact.index()))
			MarkedContent(reference) => add_mcr($builder, names, reference, objects)
		}
		match added {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(value) => {
				$builder = value.builder
				$values = $values.append(value.id)
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => Ok({ builder: $builder, values: $values })
	}
}

add_mcr : KernelObject.Builder, Names, KernelTagged.MarkedContentReference, KernelObjectPlan.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelObject.Error)
add_mcr = |builder, names, reference, objects| {
	mcid = KernelObject.add_integer(builder, reference.mcid.to_i64_wrap())?
	page = list_at(KernelObjectPlan.Plan.pages(objects), reference.page.index())
	pg = KernelObject.add_reference(mcid.builder, page.page)?
	type_value = KernelObject.add_name_value(pg.builder, names.mcr)?
	KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.mcid, value: mcid.id },
			{ key: names.pg, value: pg.id },
			{ key: names.type_name, value: type_value.id },
		],
	)
}

## An annotation spine item lowers as an OBJR: the object reference to the
## planned annotation dictionary plus the page it appears on.
add_objr : KernelObject.Builder, Names, { annotation_objects : List(KernelObject.ObjectId), annotation_pages : List(Semantics.PageId), dests_root : [DestsRootAt(KernelObject.ObjectId), NoDestsRoot], names : KernelNavigationObjects.Names, ordered_annotations : List(U64), outline_root : [NoOutlineRoot, OutlineRootAt(KernelObject.ObjectId)], page_labels_root : [NoPageLabelsRoot, PageLabelsRootAt(KernelObject.ObjectId)] }, Semantics.AnnotationId, KernelObjectPlan.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelObject.Error)
add_objr = |builder, names, input, annotation, objects| {
	annotation_index = annotation.index()
	target = KernelObject.add_reference(builder, list_at(input.annotation_objects, annotation_index))?
	page = list_at(KernelObjectPlan.Plan.pages(objects), list_at(input.annotation_pages, annotation_index).index())
	pg = KernelObject.add_reference(target.builder, page.page)?
	type_value = KernelObject.add_name_value(pg.builder, input.names.objr)?
	KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: input.names.obj, value: target.id },
			{ key: names.pg, value: pg.id },
			{ key: names.type_name, value: type_value.id },
		],
	)
}

add_contextual_artifacts : KernelObject.Builder, Names, Semantics.Store, KernelObjectPlan.Plan -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_contextual_artifacts = |builder, names, semantics, objects| {
	ids = KernelObjectPlan.Plan.contextual_artifacts(objects)
	structure = KernelObjectPlan.Plan.structure_elements(objects)
	var $builder = builder
	var $index = 0
	var $error = NoError
	while $index < semantics.contextual_artifacts.len() and $error == NoError {
		artifact = list_at(semantics.contextual_artifacts, $index)
		parent = list_at(semantics.nodes, artifact.parent.index())
		match add_contextual_artifact($builder, names, list_at(structure, parent.structure_element.index()), list_at(ids, artifact.id.index())) {
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

add_contextual_artifact : KernelObject.Builder, Names, KernelObject.ObjectId, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelTaggedObjects.Error)
add_contextual_artifact = |builder, names, parent_object, expected| {
	owner = add_name_value(builder, names.artifact)?
	pagination = add_name_value(owner.builder, names.pagination)?
	attributes = KernelObject.add_dictionary(
		pagination.builder,
		[
			{ key: names.o, value: owner.id },
			{ key: names.type_name, value: pagination.id },
		],
	) ? Object
	parent = KernelObject.add_reference(attributes.builder, parent_object) ? Object
	s = add_name_value(parent.builder, names.artifact)?
	type_value = add_name_value(s.builder, names.struct_elem)?
	dictionary = KernelObject.add_dictionary(
		type_value.builder,
		[
			{ key: names.a, value: attributes.id },
			{ key: names.p, value: parent.id },
			{ key: names.s, value: s.id },
			{ key: names.type_name, value: type_value.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, expected)?
	Ok(object.builder)
}

add_parent_entry_references : KernelObject.Builder, List(KernelTagged.MarkedContentReference), Semantics.Range, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelObject.Error)
add_parent_entry_references = |builder, entries, range, structure| {
	var $builder = builder
	var $values = List.with_capacity(range.length())
	var $index = range.start()
	end = range.start() + range.length()
	var $error = NoError
	while $index < end and $error == NoError {
		reference = list_at(entries, $index)
		match KernelObject.add_reference($builder, list_at(structure, reference.structure_element.index())) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(added) => {
				$builder = added.builder
				$values = $values.append(added.id)
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ builder: $builder, values: $values })
	}
}

add_references : KernelObject.Builder, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelTaggedObjects.Error)
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
			Ok(added) => {
				$builder = added.builder
				$values = $values.append(added.id)
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		NoError => Ok({ builder: $builder, values: $values })
	}
}

add_name_value : KernelObject.Builder, KernelObject.NameId -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelTaggedObjects.Error)
add_name_value = |builder, name| {
	added = KernelObject.add_name_value(builder, name) ? Object
	Ok(added)
}

index_nodes_by_structure : List(Semantics.Node) -> List(Semantics.NodeId)
index_nodes_by_structure = |nodes| {
	var $index = List.repeat(Semantics.NodeId.from_index(0), nodes.len())
	var $node_index = 0
	while $node_index < nodes.len() {
		node = list_at(nodes, $node_index)
		$index = list_set($index, node.structure_element.index(), node.id)
		$node_index = $node_index + 1
	}
	$index
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelTaggedObjects.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated tagged-object index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated tagged-object update escaped"
	}
}

test_limits : KernelObject.Limits
test_limits = {
	max_array_items: 64,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 128,
	max_direct_depth: 8,
	max_name_bytes: 1024,
	max_names: 64,
	max_objects: 16,
	max_payload_bytes: 0,
	max_payloads: 0,
	max_streams: 0,
	max_text_string_bytes: 64,
	max_text_strings: 1,
	max_values: 256,
}

## The tagged prefix consumes every planned object identity before the page tree.
expect {
	pipeline = KernelPipelineFixture.pipeline({})?
	plan = KernelTaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, test_limits)?
	counts = KernelObject.counts(KernelTaggedObjects.Plan.builder(plan))
	first_page_tree = list_at(KernelObjectPlan.Plan.page_tree(pipeline.objects), 0)
	counts.objects + 1 == KernelObject.ObjectId.number(first_page_tree) and KernelTaggedObjects.Plan.work(plan) == { annotation_entries: 0, contextual_artifacts: 0, k_items: 2, namespaces: 1, parent_entries: 1, parent_rows: 1, structure_elements: 2 }
}

## Contextual Artifact structure elements remain distinct planned objects.
expect {
	pipeline = KernelPipelineFixture.contextual_pipeline({})?
	plan = KernelTaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, test_limits)?
	counts = KernelObject.counts(KernelTaggedObjects.Plan.builder(plan))
	first_page_tree = list_at(KernelObjectPlan.Plan.page_tree(pipeline.objects), 0)
	counts.objects + 1 == KernelObject.ObjectId.number(first_page_tree) and KernelTaggedObjects.Plan.work(plan).contextual_artifacts == 1 and KernelTaggedObjects.Plan.work(plan).k_items == 3
}
