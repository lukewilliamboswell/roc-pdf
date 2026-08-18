## Navigation object planning and lowering: link annotation dictionaries with
## their closed action union, the named-destination name tree, the outline
## hierarchy objects, and the page-label number tree. Object identities are
## planned arithmetically after an existing planned object count (fonts and
## the metadata stream included), in the documented order: annotation
## dictionaries in the total annotation order (page, then keyboard order),
## name-tree nodes in breadth-first order, the outline root followed by its
## items in authored preorder, then page-label tree nodes, then the shifted
## xref. Every lowered object lands exactly on its planned identity.
##
## Every fact consumed here was validated earlier: the navigation store by
## `KernelNavigation.validate`, the paired destination targets by
## `KernelNavigation.resolve`, ownership by the semantic and tagging stages.
## Nothing here re-parses names, re-derives ordering, or scans content.
import Document
import KernelBalanced
import KernelIndex
import KernelLex
import KernelNavigation
import KernelObject
import KernelOutline
import Layout
import Semantics

KernelNavigationObjects :: [].{
	Error : [
		ArithmeticOverflow,
		Index(KernelIndex.Error),
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
		Outline(KernelOutline.Error),
		Shape(KernelBalanced.Error),
	]

	## Planned navigation object identities. `ordered` follows the total
	## annotation order and is the emission order; `by_id` is the same set
	## reindexed by dense annotation identity for OBJR lowering.
	Objects : {
		by_id : List(KernelObject.ObjectId),
		label_nodes : List(KernelObject.ObjectId),
		name_nodes : List(KernelObject.ObjectId),
		ordered : List(KernelObject.ObjectId),
		outline_items : List(KernelObject.ObjectId),
		outline_root : [NoOutlineRoot, OutlineRootAt(KernelObject.ObjectId)],
		total : U64,
		xref : KernelObject.ObjectId,
	}

	## The navigation facts the tagged-object prefix consumes: planned
	## annotation objects for OBJR and the ParentTree, and the planned roots
	## the catalog references.
	TaggedFacts : [
		NoNavigationObjects,
		WithNavigationObjects(
			{
				annotation_objects : List(KernelObject.ObjectId),
				annotation_pages : List(Semantics.PageId),
				dests_root : [DestsRootAt(KernelObject.ObjectId), NoDestsRoot],
				ordered_annotations : List(U64),
				outline_root : [NoOutlineRoot, OutlineRootAt(KernelObject.ObjectId)],
				page_labels_root : [NoPageLabelsRoot, PageLabelsRootAt(KernelObject.ObjectId)],
			},
		),
	]

	## Names used by navigation lowering, added once and conditionally so a
	## plan without navigation keeps its exact name table and identity.
	Names : {
		a : KernelObject.NameId,
		a_lower : KernelObject.NameId,
		action : KernelObject.NameId,
		annot : KernelObject.NameId,
		ap : KernelObject.NameId,
		bs : KernelObject.NameId,
		contents : KernelObject.NameId,
		count : KernelObject.NameId,
		d : KernelObject.NameId,
		dest : KernelObject.NameId,
		dests : KernelObject.NameId,
		f : KernelObject.NameId,
		first : KernelObject.NameId,
		go_to : KernelObject.NameId,
		kids : KernelObject.NameId,
		last : KernelObject.NameId,
		limits : KernelObject.NameId,
		link : KernelObject.NameId,
		n : KernelObject.NameId,
		names : KernelObject.NameId,
		next : KernelObject.NameId,
		nums : KernelObject.NameId,
		obj : KernelObject.NameId,
		objr : KernelObject.NameId,
		outlines : KernelObject.NameId,
		p : KernelObject.NameId,
		page_labels : KernelObject.NameId,
		parent : KernelObject.NameId,
		prev : KernelObject.NameId,
		quad_points : KernelObject.NameId,
		r_lower : KernelObject.NameId,
		r_upper : KernelObject.NameId,
		rect : KernelObject.NameId,
		s : KernelObject.NameId,
		sd : KernelObject.NameId,
		st : KernelObject.NameId,
		struct_parent : KernelObject.NameId,
		subtype : KernelObject.NameId,
		title : KernelObject.NameId,
		type_name : KernelObject.NameId,
		uri : KernelObject.NameId,
		w : KernelObject.NameId,
		xyz : KernelObject.NameId,
	}

	Work : {
		annotation_objects : U64,
		label_node_objects : U64,
		name_node_objects : U64,
		outline_objects : U64,
		quad_numbers : U64,
	}

	## Plan navigation object identities after `base_count` existing objects.
	plan : U64, KernelNavigation.Store -> Try(Objects, Error)
	plan = |base_count, store| plan_objects(base_count, store)

	add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelObject.Error)
	add_names = |builder| add_navigation_names(builder)

	## Lower every navigation object onto its planned identity, in planned
	## order, after the caller's existing objects.
	add_objects : KernelObject.Builder, Names, KernelNavigation.Store, List(KernelNavigation.ResolvedDestination), Objects, LoweringContext, { max_outline_depth : U64 } -> Try({ builder : KernelObject.Builder, work : Work }, Error)
	add_objects = |builder, names, store, resolved, objects, context, limits| {
		annotations = add_annotation_objects(builder, names, store, resolved, objects, context)?
		name_tree = add_name_tree(annotations.builder, names, store, resolved, objects, context)?
		outline = add_outline_objects(name_tree.builder, names, store, objects, limits.max_outline_depth)?
		labels = add_label_tree(outline.builder, names, store, objects)?
		Ok({
			builder: labels.builder,
			work: {
				annotation_objects: store.annotations.len(),
				label_node_objects: objects.label_nodes.len(),
				name_node_objects: objects.name_nodes.len(),
				outline_objects: outline.objects,
				quad_numbers: annotations.quad_numbers,
			},
		})
	}

	## Earlier-stage object identities the annotation and destination
	## lowering references: page objects, structure-element objects, the
	## per-form appearance stream objects (dense by authored form identity),
	## and the content-stream count that offsets annotation ParentTree keys.
	LoweringContext : {
		appearance_streams : List(KernelObject.ObjectId),
		page_objects : List(KernelObject.ObjectId),
		stream_count : U64,
		structure_elements : List(KernelObject.ObjectId),
	}
}

plan_objects : U64, KernelNavigation.Store -> Try(KernelNavigationObjects.Objects, KernelNavigationObjects.Error)
plan_objects = |base_count, store| {
	annotation_count = store.annotations.len()
	var $ordered = List.with_capacity(annotation_count)
	var $ordinal = 0
	while $ordinal < annotation_count {
		$ordered = $ordered.append(object_id(checked_add(base_count, $ordinal + 1)?)?)
		$ordinal = $ordinal + 1
	}
	var $by_id = List.repeat(object_id_one, annotation_count)
	$ordinal = 0
	while $ordinal < annotation_count {
		annotation = list_at(store.page_annotations, $ordinal)
		$by_id = list_set($by_id, annotation, list_at($ordered, $ordinal))
		$ordinal = $ordinal + 1
	}

	names_start = checked_add(base_count, annotation_count)?
	name_node_count = if store.destinations.is_empty() {
		0
	} else {
		shape = KernelBalanced.Shape.build(store.destinations.len(), store.destinations.len()) ? Shape
		KernelBalanced.Shape.node_count(shape)
	}
	var $name_nodes = List.with_capacity(name_node_count)
	var $node = 0
	while $node < name_node_count {
		$name_nodes = $name_nodes.append(object_id(checked_add(names_start, $node + 1)?)?)
		$node = $node + 1
	}

	outline_start = checked_add(names_start, name_node_count)?
	outline_entry_count = store.outline_entries.len()
	outline_root = if outline_entry_count == 0 {
		NoOutlineRoot
	} else {
		OutlineRootAt(object_id(checked_add(outline_start, 1)?)?)
	}
	var $outline_items = List.with_capacity(outline_entry_count)
	var $entry = 0
	while $entry < outline_entry_count {
		$outline_items = $outline_items.append(object_id(checked_add(outline_start, $entry + 2)?)?)
		$entry = $entry + 1
	}
	outline_objects = if outline_entry_count == 0 0 else outline_entry_count + 1

	labels_start = checked_add(outline_start, outline_objects)?
	label_node_count = if store.label_ranges.is_empty() {
		0
	} else {
		shape = KernelBalanced.Shape.build(store.label_ranges.len(), store.label_ranges.len()) ? Shape
		KernelBalanced.Shape.node_count(shape)
	}
	var $label_nodes = List.with_capacity(label_node_count)
	$node = 0
	while $node < label_node_count {
		$label_nodes = $label_nodes.append(object_id(checked_add(labels_start, $node + 1)?)?)
		$node = $node + 1
	}

	total = checked_add(checked_add(checked_add(annotation_count, name_node_count)?, outline_objects)?, label_node_count)?
	Ok({
		by_id: $by_id,
		label_nodes: $label_nodes,
		name_nodes: $name_nodes,
		ordered: $ordered,
		outline_items: $outline_items,
		outline_root,
		total,
		xref: object_id(checked_add(checked_add(base_count, total)?, 1)?)?,
	})
}

add_navigation_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : KernelNavigationObjects.Names }, KernelObject.Error)
add_navigation_names = |builder| {
	a = KernelObject.add_name(builder, Str.to_utf8("A"))?
	ap = KernelObject.add_name(a.builder, Str.to_utf8("AP"))?
	action = KernelObject.add_name(ap.builder, Str.to_utf8("Action"))?
	annot = KernelObject.add_name(action.builder, Str.to_utf8("Annot"))?
	bs = KernelObject.add_name(annot.builder, Str.to_utf8("BS"))?
	contents = KernelObject.add_name(bs.builder, Str.to_utf8("Contents"))?
	count = KernelObject.add_name(contents.builder, Str.to_utf8("Count"))?
	d = KernelObject.add_name(count.builder, Str.to_utf8("D"))?
	dest = KernelObject.add_name(d.builder, Str.to_utf8("Dest"))?
	dests = KernelObject.add_name(dest.builder, Str.to_utf8("Dests"))?
	f = KernelObject.add_name(dests.builder, Str.to_utf8("F"))?
	first = KernelObject.add_name(f.builder, Str.to_utf8("First"))?
	go_to = KernelObject.add_name(first.builder, Str.to_utf8("GoTo"))?
	kids = KernelObject.add_name(go_to.builder, Str.to_utf8("Kids"))?
	last = KernelObject.add_name(kids.builder, Str.to_utf8("Last"))?
	limits = KernelObject.add_name(last.builder, Str.to_utf8("Limits"))?
	link = KernelObject.add_name(limits.builder, Str.to_utf8("Link"))?
	n = KernelObject.add_name(link.builder, Str.to_utf8("N"))?
	names = KernelObject.add_name(n.builder, Str.to_utf8("Names"))?
	next = KernelObject.add_name(names.builder, Str.to_utf8("Next"))?
	nums = KernelObject.add_name(next.builder, Str.to_utf8("Nums"))?
	obj = KernelObject.add_name(nums.builder, Str.to_utf8("OBJR"))?
	objr = obj
	obj_key = KernelObject.add_name(obj.builder, Str.to_utf8("Obj"))?
	outlines = KernelObject.add_name(obj_key.builder, Str.to_utf8("Outlines"))?
	p = KernelObject.add_name(outlines.builder, Str.to_utf8("P"))?
	page_labels = KernelObject.add_name(p.builder, Str.to_utf8("PageLabels"))?
	parent = KernelObject.add_name(page_labels.builder, Str.to_utf8("Parent"))?
	prev = KernelObject.add_name(parent.builder, Str.to_utf8("Prev"))?
	quad_points = KernelObject.add_name(prev.builder, Str.to_utf8("QuadPoints"))?
	r_upper = KernelObject.add_name(quad_points.builder, Str.to_utf8("R"))?
	rect = KernelObject.add_name(r_upper.builder, Str.to_utf8("Rect"))?
	s = KernelObject.add_name(rect.builder, Str.to_utf8("S"))?
	sd = KernelObject.add_name(s.builder, Str.to_utf8("SD"))?
	st = KernelObject.add_name(sd.builder, Str.to_utf8("St"))?
	struct_parent = KernelObject.add_name(st.builder, Str.to_utf8("StructParent"))?
	subtype = KernelObject.add_name(struct_parent.builder, Str.to_utf8("Subtype"))?
	title = KernelObject.add_name(subtype.builder, Str.to_utf8("Title"))?
	type_name = KernelObject.add_name(title.builder, Str.to_utf8("Type"))?
	uri = KernelObject.add_name(type_name.builder, Str.to_utf8("URI"))?
	w = KernelObject.add_name(uri.builder, Str.to_utf8("W"))?
	xyz = KernelObject.add_name(w.builder, Str.to_utf8("XYZ"))?
	a_lower = KernelObject.add_name(xyz.builder, Str.to_utf8("a"))?
	r_lower = KernelObject.add_name(a_lower.builder, Str.to_utf8("r"))?
	Ok({
		builder: r_lower.builder,
		names: {
			a: a.id,
			a_lower: a_lower.id,
			action: action.id,
			annot: annot.id,
			ap: ap.id,
			bs: bs.id,
			contents: contents.id,
			count: count.id,
			d: d.id,
			dest: dest.id,
			dests: dests.id,
			f: f.id,
			first: first.id,
			go_to: go_to.id,
			kids: kids.id,
			last: last.id,
			limits: limits.id,
			link: link.id,
			n: n.id,
			names: names.id,
			next: next.id,
			nums: nums.id,
			obj: obj_key.id,
			objr: objr.id,
			outlines: outlines.id,
			p: p.id,
			page_labels: page_labels.id,
			parent: parent.id,
			prev: prev.id,
			quad_points: quad_points.id,
			r_lower: r_lower.id,
			r_upper: r_upper.id,
			rect: rect.id,
			s: s.id,
			sd: sd.id,
			st: st.id,
			struct_parent: struct_parent.id,
			subtype: subtype.id,
			title: title.id,
			type_name: type_name.id,
			uri: uri.id,
			w: w.id,
			xyz: xyz.id,
		},
	})
}

## Annotation dictionaries in the total annotation order. Every internal GoTo
## action carries both the geometric `/D` and the structure `/SD` destination
## from one resolved record; a URI action carries the validated URI byte
## string. `/StructParent` is the content-stream count plus the annotation's
## ordinal — exactly the ParentTree key the tagged prefix emitted.
add_annotation_objects : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigation.Store, List(KernelNavigation.ResolvedDestination), KernelNavigationObjects.Objects, KernelNavigationObjects.LoweringContext -> Try({ builder : KernelObject.Builder, quad_numbers : U64 }, KernelNavigationObjects.Error)
add_annotation_objects = |builder, names, store, resolved, objects, context| {
	var $builder = builder
	var $quad_numbers = 0
	var $ordinal = 0
	while $ordinal < store.page_annotations.len() {
		annotation_index = list_at(store.page_annotations, $ordinal)
		annotation = list_at(store.annotations, annotation_index)
		action = add_action_value($builder, names, store, resolved, annotation.action, context)?
		appearance = match annotation.appearance {
			NoAppearance => { builder: action.builder, value: NoValue }
			NormalAppearance(form) => {
				stream = KernelObject.add_reference(action.builder, list_at(context.appearance_streams, form.index())) ? Object
				dictionary = KernelObject.add_dictionary(stream.builder, [{ key: names.n, value: stream.id }]) ? Object
				{ builder: dictionary.builder, value: WithValue(dictionary.id) }
			}
		}
		zero_width = KernelObject.add_integer(appearance.builder, 0) ? Object
		border_style = KernelObject.add_dictionary(zero_width.builder, [{ key: names.w, value: zero_width.id }]) ? Object
		description = match annotation.description {
			NoDescription => { builder: border_style.builder, value: NoValue }
			WithDescription(text) => {
				added_text = KernelObject.add_text_string(border_style.builder, text) ? Object
				value = KernelObject.add_text_string_value(added_text.builder, added_text.id) ? Object
				{ builder: value.builder, value: WithValue(value.id) }
			}
		}
		flags = KernelObject.add_integer(description.builder, if annotation.print 4 else 0) ? Object
		quads = add_quad_points(flags.builder, store, annotation.quads)?
		$quad_numbers = $quad_numbers + annotation.quads.length() * 8
		rect = add_rect_value(quads.builder, annotation.rect)?
		struct_parent = KernelObject.add_integer(rect.builder, checked_add(context.stream_count, $ordinal)?.to_i64_wrap()) ? Object
		link_subtype = KernelObject.add_name_value(struct_parent.builder, names.link) ? Object
		annot_type = KernelObject.add_name_value(link_subtype.builder, names.annot) ? Object

		var $entries = [{ key: names.a, value: action.id }]
		match appearance.value {
			NoValue => {}
			WithValue(value) => {
				$entries = $entries.append({ key: names.ap, value })
			}
		}
		$entries = $entries.append({ key: names.bs, value: border_style.id })
		match description.value {
			NoValue => {}
			WithValue(value) => {
				$entries = $entries.append({ key: names.contents, value })
			}
		}
		$entries = $entries.append({ key: names.f, value: flags.id })
		$entries = $entries.append({ key: names.quad_points, value: quads.id })
		$entries = $entries.append({ key: names.rect, value: rect.id })
		$entries = $entries.append({ key: names.struct_parent, value: struct_parent.id })
		$entries = $entries.append({ key: names.subtype, value: link_subtype.id })
		$entries = $entries.append({ key: names.type_name, value: annot_type.id })
		dictionary = KernelObject.add_dictionary(annot_type.builder, $entries) ? Object
		object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
		ensure_object(object.id, list_at(objects.ordered, $ordinal))?
		$builder = object.builder
		$ordinal = $ordinal + 1
	}
	Ok({ builder: $builder, quad_numbers: $quad_numbers })
}

add_action_value : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigation.Store, List(KernelNavigation.ResolvedDestination), KernelNavigation.Action, KernelNavigationObjects.LoweringContext -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_action_value = |builder, names, store, resolved, action, context| match action {
	UriAction(range) => {
		var $bytes = List.with_capacity(range.length())
		var $offset = 0
		while $offset < range.length() {
			$bytes = $bytes.append(list_at(store.uri_bytes, range.start() + $offset))
			$offset = $offset + 1
		}
		uri_string = KernelObject.add_byte_string(builder, $bytes) ? Object
		uri_value = KernelObject.add_byte_string_value(uri_string.builder, uri_string.id) ? Object
		subtype = KernelObject.add_name_value(uri_value.builder, names.uri) ? Object
		action_type = KernelObject.add_name_value(subtype.builder, names.action) ? Object
		added = KernelObject.add_dictionary(
			action_type.builder,
			[
				{ key: names.s, value: subtype.id },
				{ key: names.type_name, value: action_type.id },
				{ key: names.uri, value: uri_value.id },
			],
		) ? Object
		Ok(added)
	}
	GoToDestination(destination) => {
		target = list_at(resolved, destination.index())
		geometric = add_destination_array(builder, names, list_at(context.page_objects, target.page.index()), target)?
		structure = add_destination_array(geometric.builder, names, list_at(context.structure_elements, target.structure_element.index()), target)?
		subtype = KernelObject.add_name_value(structure.builder, names.go_to) ? Object
		action_type = KernelObject.add_name_value(subtype.builder, names.action) ? Object
		added = KernelObject.add_dictionary(
			action_type.builder,
			[
				{ key: names.d, value: geometric.id },
				{ key: names.s, value: subtype.id },
				{ key: names.sd, value: structure.id },
				{ key: names.type_name, value: action_type.id },
			],
		) ? Object
		Ok(added)
	}
}

## One destination array `[target /XYZ left top null]`: the geometric form
## references the page object, the structure form references the structure
## element, and both carry the identical resolved coordinates.
add_destination_array : KernelObject.Builder, KernelNavigationObjects.Names, KernelObject.ObjectId, KernelNavigation.ResolvedDestination -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_destination_array = |builder, names, target_object, target| {
	reference = KernelObject.add_reference(builder, target_object) ? Object
	fit = KernelObject.add_name_value(reference.builder, names.xyz) ? Object
	left = add_thousandths(fit.builder, target.left)?
	top = add_thousandths(left.builder, target.top)?
	zoom = KernelObject.add_null(top.builder) ? Object
	added = KernelObject.add_array(zoom.builder, [reference.id, fit.id, left.id, top.id, zoom.id]) ? Object
	Ok(added)
}

## QuadPoints in the pinned per-quad number order: top-left, top-right,
## bottom-left, bottom-right.
add_quad_points : KernelObject.Builder, KernelNavigation.Store, Semantics.Range -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_quad_points = |builder, store, range| {
	var $builder = builder
	var $values = List.with_capacity(range.length() * 8)
	var $index = 0
	while $index < range.length() {
		quad = list_at(store.quad_points, range.start() + $index)
		x_left = add_thousandths($builder, quad.x_left)?
		y_top = add_thousandths(x_left.builder, quad.y_top)?
		x_right = add_thousandths(y_top.builder, quad.x_right)?
		y_top_right = add_thousandths(x_right.builder, quad.y_top)?
		x_left_bottom = add_thousandths(y_top_right.builder, quad.x_left)?
		y_bottom = add_thousandths(x_left_bottom.builder, quad.y_bottom)?
		x_right_bottom = add_thousandths(y_bottom.builder, quad.x_right)?
		y_bottom_right = add_thousandths(x_right_bottom.builder, quad.y_bottom)?
		$builder = y_bottom_right.builder
		$values = $values
			.append(x_left.id)
			.append(y_top.id)
			.append(x_right.id)
			.append(y_top_right.id)
			.append(x_left_bottom.id)
			.append(y_bottom.id)
			.append(x_right_bottom.id)
			.append(y_bottom_right.id)
		$index = $index + 1
	}
	added = KernelObject.add_array($builder, $values) ? Object
	Ok(added)
}

add_rect_value : KernelObject.Builder, Layout.Rect -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_rect_value = |builder, rect| {
	x0 = add_thousandths(builder, rect.origin.x)?
	y0 = add_thousandths(x0.builder, rect.origin.y)?
	x1 = add_raw_thousandths(y0.builder, checked_add_i64(rect.origin.x.raw(), rect.size.width.raw())?)?
	y1 = add_raw_thousandths(x1.builder, checked_add_i64(rect.origin.y.raw(), rect.size.height.raw())?)?
	added = KernelObject.add_array(y1.builder, [x0.id, y0.id, x1.id, y1.id]) ? Object
	Ok(added)
}

## The named-destination name tree over `KernelIndex`'s fixed-fanout shape:
## per-destination `<< /D … /SD … >>` value dictionaries in name order, then
## one dictionary object per node in breadth-first order — `/Names` leaves,
## `/Kids` interior nodes, `/Limits` on every non-root node.
add_name_tree : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigation.Store, List(KernelNavigation.ResolvedDestination), KernelNavigationObjects.Objects, KernelNavigationObjects.LoweringContext -> Try({ builder : KernelObject.Builder }, KernelNavigationObjects.Error)
add_name_tree = |builder, names, store, resolved, objects, context| {
	if store.destinations.is_empty() {
		Ok({ builder: builder })
	} else {
		var $builder = builder
		var $entries = List.with_capacity(store.destinations.len())
		var $order = 0
		while $order < store.name_order.len() {
			destination_index = list_at(store.name_order, $order)
			target = list_at(resolved, destination_index)
			geometric = add_destination_array($builder, names, list_at(context.page_objects, target.page.index()), target)?
			structure = add_destination_array(geometric.builder, names, list_at(context.structure_elements, target.structure_element.index()), target)?
			value = KernelObject.add_dictionary(
				structure.builder,
				[
					{ key: names.d, value: geometric.id },
					{ key: names.sd, value: structure.id },
				],
			) ? Object
			$builder = value.builder
			$entries = $entries.append(KernelIndex.ByteEntry.make(name_bytes(store, destination_index), value.id))
			$order = $order + 1
		}
		counts = KernelObject.counts($builder)
		tree = KernelIndex.ByteTree.build(
			$entries,
			NameTree,
			KernelIndex.Limits.make({ max_entries: store.destinations.len(), max_key_bytes: store.name_bytes.len(), value_count: counts.values }),
		) ? Index
		emit_byte_tree($builder, names, tree, objects.name_nodes)
	}
}

emit_byte_tree : KernelObject.Builder, KernelNavigationObjects.Names, KernelIndex.ByteTree, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder }, KernelNavigationObjects.Error)
emit_byte_tree = |builder, names, tree, planned| {
	var $builder = builder
	var $global = 0
	var $level = 0
	while $level < KernelIndex.ByteTree.level_count(tree) {
		var $node = 0
		while $node < KernelIndex.ByteTree.node_count_at(tree, $level) {
			node = KernelIndex.ByteTree.node(tree, $level, $node)
			children = match KernelIndex.Node.children(node) {
				Nodes(span) => {
					kid_refs = add_planned_references($builder, planned, KernelBalanced.Span.start(span), KernelBalanced.Span.length(span))?
					kids = KernelObject.add_array(kid_refs.builder, kid_refs.values) ? Object
					{ builder: kids.builder, key: names.kids, value: kids.id }
				}
				Entries(span) => {
					var $items = List.with_capacity(KernelBalanced.Span.length(span) * 2)
					var $inner = $builder
					var $entry = KernelBalanced.Span.start(span)
					entry_end = KernelBalanced.Span.start(span) + KernelBalanced.Span.length(span)
					while $entry < entry_end {
						tree_entry = KernelIndex.ByteTree.entry(tree, $entry)
						key_string = KernelObject.add_byte_string($inner, KernelIndex.ByteEntry.key(tree_entry)) ? Object
						key_value = KernelObject.add_byte_string_value(key_string.builder, key_string.id) ? Object
						$inner = key_value.builder
						$items = $items.append(key_value.id).append(KernelIndex.ByteEntry.value(tree_entry))
						$entry = $entry + 1
					}
					array = KernelObject.add_array($inner, $items) ? Object
					{ builder: array.builder, key: names.names, value: array.id }
				}
			}
			limits_value = match KernelIndex.Node.limits(node) {
				NoLimits => { builder: children.builder, value: NoValue }
				NodeLimits({ first_index, last_index }) => {
					first_key = KernelObject.add_byte_string(children.builder, KernelIndex.ByteEntry.key(KernelIndex.ByteTree.entry(tree, first_index))) ? Object
					first_value = KernelObject.add_byte_string_value(first_key.builder, first_key.id) ? Object
					last_key = KernelObject.add_byte_string(first_value.builder, KernelIndex.ByteEntry.key(KernelIndex.ByteTree.entry(tree, last_index))) ? Object
					last_value = KernelObject.add_byte_string_value(last_key.builder, last_key.id) ? Object
					array = KernelObject.add_array(last_value.builder, [first_value.id, last_value.id]) ? Object
					{ builder: array.builder, value: WithValue(array.id) }
				}
			}
			entries = match limits_value.value {
				NoValue => [{ key: children.key, value: children.value }]
				WithValue(value) => if KernelObject.NameId.index(children.key) == KernelObject.NameId.index(names.kids) {
					[
						{ key: children.key, value: children.value },
						{ key: names.limits, value },
					]
				} else {
					[
						{ key: names.limits, value },
						{ key: children.key, value: children.value },
					]
				}
			}
			dictionary = KernelObject.add_dictionary(limits_value.builder, entries) ? Object
			object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
			ensure_object(object.id, list_at(planned, $global))?
			$builder = object.builder
			$global = $global + 1
			$node = $node + 1
		}
		$level = $level + 1
	}
	Ok({ builder: $builder })
}

## Outline objects: the authored preorder seals through `KernelOutline` and
## lowers as the linked hierarchy — the root with its exact visible count and
## first/last links, then one item per entry in authored order carrying its
## title, its destination name, its sibling and child links, and its signed
## visible-descendant count.
add_outline_objects : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigation.Store, KernelNavigationObjects.Objects, U64 -> Try({ builder : KernelObject.Builder, objects : U64 }, KernelNavigationObjects.Error)
add_outline_objects = |builder, names, store, objects, max_depth| {
	root_object = match objects.outline_root {
		NoOutlineRoot => return Ok({ builder, objects: 0 })
		OutlineRootAt(root) => root
	}
	var $builder = builder
	var $entries = List.with_capacity(store.outline_entries.len())
	var $index = 0
	while $index < store.outline_entries.len() {
		entry = list_at(store.outline_entries, $index)
		title = KernelObject.add_text_string($builder, entry.title) ? Object
		name_string = KernelObject.add_byte_string(title.builder, name_bytes(store, entry.destination.index())) ? Object
		name_value = KernelObject.add_byte_string_value(name_string.builder, name_string.id) ? Object
		$builder = name_value.builder
		$entries = $entries.append(KernelOutline.Entry.make({ depth: entry.depth, open: entry.open, target: TargetValue(name_value.id), title: title.id }))
		$index = $index + 1
	}
	counts = KernelObject.counts($builder)
	outline = KernelOutline.Plan.build(
		$entries,
		KernelOutline.Limits.make({
			max_depth,
			max_entries: store.outline_entries.len(),
			text_string_count: counts.text_strings,
			value_count: counts.values,
		}),
	) ? Outline

	first_reference = KernelObject.add_reference($builder, item_object(objects, KernelOutline.Plan.root_first(outline))) ? Object
	last_reference = KernelObject.add_reference(first_reference.builder, item_object(objects, KernelOutline.Plan.root_last(outline))) ? Object
	root_count = KernelObject.add_integer(last_reference.builder, KernelOutline.Plan.root_count(outline).to_i64_wrap()) ? Object
	root_type = KernelObject.add_name_value(root_count.builder, names.outlines) ? Object
	root_dictionary = KernelObject.add_dictionary(
		root_type.builder,
		[
			{ key: names.count, value: root_count.id },
			{ key: names.first, value: first_reference.id },
			{ key: names.last, value: last_reference.id },
			{ key: names.type_name, value: root_type.id },
		],
	) ? Object
	root_added = KernelObject.add_object(root_dictionary.builder, root_dictionary.id) ? Object
	ensure_object(root_added.id, root_object)?
	$builder = root_added.builder

	var $item = 0
	while $item < KernelOutline.Plan.entry_count(outline) {
		item = KernelOutline.Plan.item_at(outline, $item)
		$builder = add_outline_item($builder, names, objects, root_object, item, list_at(objects.outline_items, $item))?
		$item = $item + 1
	}
	Ok({ builder: $builder, objects: KernelOutline.Plan.entry_count(outline) + 1 })
}

add_outline_item : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigationObjects.Objects, KernelObject.ObjectId, KernelOutline.Item, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelNavigationObjects.Error)
add_outline_item = |builder, names, objects, root_object, item, expected| {
	count = match KernelOutline.Item.count(item) {
		Leaf => { builder, value: NoValue }
		OpenCount(open) => {
			added = KernelObject.add_integer(builder, open.to_i64_wrap()) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
		ClosedCount(closed) => {
			added = KernelObject.add_integer(builder, 0 - closed.to_i64_wrap()) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
	}
	target_value = match KernelOutline.Item.target(item) {
		TargetValue(value) => value
		NoTarget => {
			crash "validated outline entry lost its destination target"
		}
	}
	first = match KernelOutline.Item.first(item) {
		NoItem => { builder: count.builder, value: NoValue }
		OutlineItem(child) => {
			added = KernelObject.add_reference(count.builder, item_object(objects, child)) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
	}
	last = match KernelOutline.Item.last(item) {
		NoItem => { builder: first.builder, value: NoValue }
		OutlineItem(child) => {
			added = KernelObject.add_reference(first.builder, item_object(objects, child)) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
	}
	next = match KernelOutline.Item.next(item) {
		NoItem => { builder: last.builder, value: NoValue }
		OutlineItem(sibling) => {
			added = KernelObject.add_reference(last.builder, item_object(objects, sibling)) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
	}
	parent_reference = KernelObject.add_reference(
		next.builder,
		match KernelOutline.Item.parent(item) {
			OutlineRoot => root_object
			OutlineParent(parent) => item_object(objects, parent)
		},
	) ? Object
	prev = match KernelOutline.Item.previous(item) {
		NoItem => { builder: parent_reference.builder, value: NoValue }
		OutlineItem(sibling) => {
			added = KernelObject.add_reference(parent_reference.builder, item_object(objects, sibling)) ? Object
			{ builder: added.builder, value: WithValue(added.id) }
		}
	}
	title_value = KernelObject.add_text_string_value(prev.builder, KernelOutline.Item.title(item)) ? Object

	var $entries = []
	match count.value {
		NoValue => {}
		WithValue(value) => {
			$entries = $entries.append({ key: names.count, value })
		}
	}
	$entries = $entries.append({ key: names.dest, value: target_value })
	match first.value {
		NoValue => {}
		WithValue(value) => {
			$entries = $entries.append({ key: names.first, value })
		}
	}
	match last.value {
		NoValue => {}
		WithValue(value) => {
			$entries = $entries.append({ key: names.last, value })
		}
	}
	match next.value {
		NoValue => {}
		WithValue(value) => {
			$entries = $entries.append({ key: names.next, value })
		}
	}
	$entries = $entries.append({ key: names.parent, value: parent_reference.id })
	match prev.value {
		NoValue => {}
		WithValue(value) => {
			$entries = $entries.append({ key: names.prev, value })
		}
	}
	$entries = $entries.append({ key: names.title, value: title_value.id })
	dictionary = KernelObject.add_dictionary(title_value.builder, $entries) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, expected)?
	Ok(object.builder)
}

## The page-label number tree: one `<< /P … /S … /St … >>` value per range
## keyed by its start page index, emitted through the same fixed-fanout node
## machinery as the name tree with `/Nums` leaves and integer `/Limits`.
add_label_tree : KernelObject.Builder, KernelNavigationObjects.Names, KernelNavigation.Store, KernelNavigationObjects.Objects -> Try({ builder : KernelObject.Builder }, KernelNavigationObjects.Error)
add_label_tree = |builder, names, store, objects| {
	if store.label_ranges.is_empty() {
		Ok({ builder: builder })
	} else {
		var $builder = builder
		var $entries = List.with_capacity(store.label_ranges.len())
		var $index = 0
		while $index < store.label_ranges.len() {
			range = list_at(store.label_ranges, $index)
			var $label_entries = []
			prefixed = if Str.is_empty(range.prefix) {
				{ builder: $builder, value: NoValue }
			} else {
				text = KernelObject.add_text_string($builder, range.prefix) ? Object
				value = KernelObject.add_text_string_value(text.builder, text.id) ? Object
				{ builder: value.builder, value: WithValue(value.id) }
			}
			match prefixed.value {
				NoValue => {}
				WithValue(value) => {
					$label_entries = $label_entries.append({ key: names.p, value })
				}
			}
			styled = match range.style {
				NoNumber => { builder: prefixed.builder, value: NoValue }
				DecimalArabic => add_style_value(prefixed.builder, names.d)?
				LettersLower => add_style_value(prefixed.builder, names.a_lower)?
				LettersUpper => add_style_value(prefixed.builder, names.a)?
				RomanLower => add_style_value(prefixed.builder, names.r_lower)?
				RomanUpper => add_style_value(prefixed.builder, names.r_upper)?
			}
			match styled.value {
				NoValue => {}
				WithValue(value) => {
					$label_entries = $label_entries.append({ key: names.s, value })
				}
			}
			numbered = if range.start_number == 1 {
				{ builder: styled.builder, value: NoValue }
			} else {
				added = KernelObject.add_integer(styled.builder, range.start_number.to_i64_wrap()) ? Object
				{ builder: added.builder, value: WithValue(added.id) }
			}
			match numbered.value {
				NoValue => {}
				WithValue(value) => {
					$label_entries = $label_entries.append({ key: names.st, value })
				}
			}
			dictionary = KernelObject.add_dictionary(numbered.builder, $label_entries) ? Object
			$builder = dictionary.builder
			$entries = $entries.append(KernelIndex.NumberEntry.make(range.start_page.to_i64_wrap(), dictionary.id))
			$index = $index + 1
		}
		counts = KernelObject.counts($builder)
		tree = KernelIndex.NumberTree.build(
			$entries,
			NumberTree,
			KernelIndex.Limits.make({ max_entries: store.label_ranges.len(), max_key_bytes: 0, value_count: counts.values }),
		) ? Index
		emit_number_tree($builder, names, tree, objects.label_nodes)
	}
}

emit_number_tree : KernelObject.Builder, KernelNavigationObjects.Names, KernelIndex.NumberTree, List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder }, KernelNavigationObjects.Error)
emit_number_tree = |builder, names, tree, planned| {
	var $builder = builder
	var $global = 0
	var $level = 0
	while $level < KernelIndex.NumberTree.level_count(tree) {
		var $node = 0
		while $node < KernelIndex.NumberTree.node_count_at(tree, $level) {
			node = KernelIndex.NumberTree.node(tree, $level, $node)
			children = match KernelIndex.Node.children(node) {
				Nodes(span) => {
					kid_refs = add_planned_references($builder, planned, KernelBalanced.Span.start(span), KernelBalanced.Span.length(span))?
					kids = KernelObject.add_array(kid_refs.builder, kid_refs.values) ? Object
					{ builder: kids.builder, key: names.kids, value: kids.id }
				}
				Entries(span) => {
					var $items = List.with_capacity(KernelBalanced.Span.length(span) * 2)
					var $inner = $builder
					var $entry = KernelBalanced.Span.start(span)
					entry_end = KernelBalanced.Span.start(span) + KernelBalanced.Span.length(span)
					while $entry < entry_end {
						tree_entry = KernelIndex.NumberTree.entry(tree, $entry)
						key_value = KernelObject.add_integer($inner, KernelIndex.NumberEntry.key(tree_entry)) ? Object
						$inner = key_value.builder
						$items = $items.append(key_value.id).append(KernelIndex.NumberEntry.value(tree_entry))
						$entry = $entry + 1
					}
					array = KernelObject.add_array($inner, $items) ? Object
					{ builder: array.builder, key: names.nums, value: array.id }
				}
			}
			limits_value = match KernelIndex.Node.limits(node) {
				NoLimits => { builder: children.builder, value: NoValue }
				NodeLimits({ first_index, last_index }) => {
					first_key = KernelObject.add_integer(children.builder, KernelIndex.NumberEntry.key(KernelIndex.NumberTree.entry(tree, first_index))) ? Object
					last_key = KernelObject.add_integer(first_key.builder, KernelIndex.NumberEntry.key(KernelIndex.NumberTree.entry(tree, last_index))) ? Object
					array = KernelObject.add_array(last_key.builder, [first_key.id, last_key.id]) ? Object
					{ builder: array.builder, value: WithValue(array.id) }
				}
			}
			entries = match limits_value.value {
				NoValue => [{ key: children.key, value: children.value }]
				WithValue(value) => if KernelObject.NameId.index(children.key) == KernelObject.NameId.index(names.kids) {
					[
						{ key: children.key, value: children.value },
						{ key: names.limits, value },
					]
				} else {
					[
						{ key: names.limits, value },
						{ key: children.key, value: children.value },
					]
				}
			}
			dictionary = KernelObject.add_dictionary(limits_value.builder, entries) ? Object
			object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
			ensure_object(object.id, list_at(planned, $global))?
			$builder = object.builder
			$global = $global + 1
			$node = $node + 1
		}
		$level = $level + 1
	}
	Ok({ builder: $builder })
}

add_style_value : KernelObject.Builder, KernelObject.NameId -> Try({ builder : KernelObject.Builder, value : [NoValue, WithValue(KernelObject.ValueId)] }, KernelNavigationObjects.Error)
add_style_value = |builder, name| {
	added = KernelObject.add_name_value(builder, name) ? Object
	Ok({ builder: added.builder, value: WithValue(added.id) })
}

add_planned_references : KernelObject.Builder, List(KernelObject.ObjectId), U64, U64 -> Try({ builder : KernelObject.Builder, values : List(KernelObject.ValueId) }, KernelNavigationObjects.Error)
add_planned_references = |builder, planned, start, length| {
	var $builder = builder
	var $values = List.with_capacity(length)
	var $index = 0
	while $index < length {
		added = KernelObject.add_reference($builder, list_at(planned, start + $index)) ? Object
		$builder = added.builder
		$values = $values.append(added.id)
		$index = $index + 1
	}
	Ok({ builder: $builder, values: $values })
}

name_bytes : KernelNavigation.Store, U64 -> List(U8)
name_bytes = |store, destination_index| {
	range = list_at(store.destinations, destination_index).name
	var $bytes = List.with_capacity(range.length())
	var $offset = 0
	while $offset < range.length() {
		$bytes = $bytes.append(list_at(store.name_bytes, range.start() + $offset))
		$offset = $offset + 1
	}
	$bytes
}

item_object : KernelNavigationObjects.Objects, KernelOutline.ItemId -> KernelObject.ObjectId
item_object = |objects, item| list_at(objects.outline_items, KernelOutline.ItemId.index(item))

add_thousandths : KernelObject.Builder, Layout.Unit -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_thousandths = |builder, value| add_raw_thousandths(builder, value.raw())

add_raw_thousandths : KernelObject.Builder, I64 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelNavigationObjects.Error)
add_raw_thousandths = |builder, raw| {
	decimal = match KernelLex.Decimal.from_coefficient(raw, 3) {
		Err(_) => {
			crash "fixed navigation coordinate scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

checked_add : U64, U64 -> Try(U64, KernelNavigationObjects.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_add_i64 : I64, I64 -> Try(I64, KernelNavigationObjects.Error)
checked_add_i64 = |left, right| match I64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

object_id : U64 -> Try(KernelObject.ObjectId, KernelNavigationObjects.Error)
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => Err(ArithmeticOverflow)
	Ok(id) => Ok(id)
}

object_id_one : KernelObject.ObjectId
object_id_one = match KernelObject.ObjectId.from_number(1) {
	Err(_) => {
		crash "constant object number escaped"
	}
	Ok(id) => id
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelNavigationObjects.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated navigation object index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated navigation object update escaped"
	}
}

## Planned identities follow the documented order: annotations in total
## order, name-tree nodes, the outline root and its items, label nodes, and
## the shifted xref.
expect {
	store = {
		annotations: List.repeat(
			{
				action: UriAction(Semantics.Range.from_start_and_length(0, 0)),
				appearance: NoAppearance,
				description: NoDescription,
				keyboard_order: 0,
				page: Semantics.PageId.from_index(0),
				print: Bool.True,
				quads: Semantics.Range.from_start_and_length(0, 0),
				rect: { origin: { x: Layout.Unit.from_raw(0), y: Layout.Unit.from_raw(0) }, size: { height: Layout.Unit.from_raw(1), width: Layout.Unit.from_raw(1) } },
			},
			2,
		),
		destinations: [
			{
				anchor: Semantics.OccurrenceId.from_index(0),
				id: Semantics.DestinationId.from_index(0),
				name: Semantics.Range.from_start_and_length(0, 1),
				target: Semantics.NodeId.from_index(0),
			},
		],
		label_ranges: [{ prefix: "", start_number: 1, start_page: 0, style: DecimalArabic }],
		name_bytes: [65],
		name_order: [0],
		outline_entries: [
			{ depth: 0, destination: Semantics.DestinationId.from_index(0), open: Bool.True, title: "One" },
			{ depth: 1, destination: Semantics.DestinationId.from_index(0), open: Bool.False, title: "Two" },
		],
		page_annotation_offsets: [0, 2],
		page_annotations: [1, 0],
		quad_points: [],
		uri_bytes: [],
	}
	objects = KernelNavigationObjects.plan(10, store)?

	KernelObject.ObjectId.number(list_at(objects.ordered, 0)) == 11 and
		KernelObject.ObjectId.number(list_at(objects.ordered, 1)) == 12 and
			KernelObject.ObjectId.number(list_at(objects.by_id, 1)) == 11 and
				KernelObject.ObjectId.number(list_at(objects.by_id, 0)) == 12 and
					KernelObject.ObjectId.number(list_at(objects.name_nodes, 0)) == 13 and
						match objects.outline_root {
							OutlineRootAt(root) => KernelObject.ObjectId.number(root) == 14
							NoOutlineRoot => Bool.False
						} and
							KernelObject.ObjectId.number(list_at(objects.outline_items, 1)) == 16 and
								KernelObject.ObjectId.number(list_at(objects.label_nodes, 0)) == 17 and
									objects.total == 7 and
										KernelObject.ObjectId.number(objects.xref) == 18
}
