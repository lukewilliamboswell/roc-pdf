import KernelWidgetObjects
import KernelAssociatedObjects
import Document
import KernelColor
import KernelContent
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelIdentity
import KernelObjectPlan
import KernelOutputBound
import KernelPageObjects
import KernelResourceObjects
import KernelTaggedObjects
import KernelFontObjects
import KernelImage
import KernelMetadata
import KernelNavigation
import KernelNavigationObjects
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelStructure
import KernelTagged
import Semantics

KernelTaggedTextStructure :: [].{
	Error : [
		Widgets(KernelWidgetObjects.Error),
		Associated(KernelAssociatedObjects.Error),
		ArithmeticOverflow,
		Font(KernelPdfFont.Error),
		FontCountMismatch({ fonts : U64, mappings : U64, planned : U64 }),
		Identity(KernelIdentity.Error),
		IntentProfileUnplanned({ attempted : U64, profiles : U64 }),
		Navigation(Document.NavigationError),
		NavigationObjects(KernelNavigationObjects.Error),
		Object(KernelObject.Error),
		ObjectCountMismatch({ actual : U64, expected : U64 }),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
		OutputBound(KernelOutputBound.Error),
		Pages(KernelPageObjects.Error),
		Resources(KernelResourceObjects.Error),
		Seal(KernelSeal.Error),
		TaggedObjects(KernelTaggedObjects.Error),
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

	## Post-layout navigation input mirroring the production-visual assembler: the
	## validated navigation store, the prepared per-fragment anchor
	## rectangles, and the authored outline-depth limit.
	NavigationInput : [
		NoNavigation,
		WithNavigation(
			{
				anchor_rects : List(KernelNavigation.AnchorRect),
				max_outline_depth : U64,
				store : KernelNavigation.Store,
			},
		),
	]

	Work : {
		annotation_objects : U64,
		content_bytes : U64,
		destinations_resolved : U64,
		font_objects : U64,
		font_program_bytes : U64,
		fonts : U64,
		label_node_objects : U64,
		metadata_bytes : U64,
		metadata_objects : U64,
		name_node_objects : U64,
		objects : U64,
		outline_objects : U64,
		pages : KernelPageObjects.Work,
		quad_numbers : U64,
		resources : KernelResourceObjects.Work,
		tagged_objects : KernelTaggedObjects.Work,
	}

	Plan :: { font_objects : List(KernelPdfFont.Objects), structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelFontObjects.Plan, KernelPdfText.ScenePlan, List(FontInput), Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, objects, text, fonts, limits| build_plan(tagged, colors, images, content, objects, text, fonts, NoDocumentFacts, NoNavigation, limits)

		## Document facts append the canonical XMP metadata stream after the
		## font objects and extend the catalog with the language, metadata,
		## and output-intent entries; the intent references the already
		## planned canonical profile stream. `NoDocumentFacts` is
		## byte-identical to `build`.
		build_with_facts : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelFontObjects.Plan, KernelPdfText.ScenePlan, List(FontInput), KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_with_facts = |tagged, colors, images, content, objects, text, fonts, facts, limits| build_plan(tagged, colors, images, content, objects, text, fonts, facts, NoNavigation, limits)

		## The navigation variant: destinations resolve to their paired
		## structure and geometric targets, annotation dictionaries with both
		## /SD and /D lower after the metadata stream, pages gain /Annots in
		## keyboard order, the catalog gains its navigation roots, annotation
		## spine items lower as OBJR kids, and the ParentTree gains one scalar
		## row per annotation. `NoNavigation` is byte-identical to
		## `build_with_facts`.
		build_with_navigation : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelFontObjects.Plan, KernelPdfText.ScenePlan, List(FontInput), KernelMetadata.PlanFacts, NavigationInput, Limits -> Try(Plan, Error)
		build_with_navigation = |tagged, colors, images, content, objects, text, fonts, facts, navigation, limits| build_plan(tagged, colors, images, content, objects, text, fonts, facts, navigation, limits)

		font_objects : Plan -> List(KernelPdfFont.Objects)
		font_objects = |plan| plan.font_objects

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelFontObjects.Plan, KernelPdfText.ScenePlan, List(KernelTaggedTextStructure.FontInput), KernelMetadata.PlanFacts, KernelTaggedTextStructure.NavigationInput, KernelTaggedTextStructure.Limits -> Try(KernelTaggedTextStructure.Plan, KernelTaggedTextStructure.Error)
build_plan = |tagged, colors, images, content, font_plan, text, fonts, facts, navigation, limits| {
	planned_fonts = KernelFontObjects.Plan.fonts(font_plan)
	mappings = KernelPdfText.ScenePlan.mappings(text)
	font_count = fonts.len()
	if font_count != mappings.len() or font_count != planned_fonts.len() {
		return Err(FontCountMismatch({ fonts: font_count, mappings: mappings.len(), planned: planned_fonts.len() }))
	}
	objects = KernelFontObjects.Plan.base(font_plan)
	base_count = KernelFontObjects.Plan.object_count(font_plan)
	catalog_facts = match facts {
		NoDocumentFacts => NoCatalogFacts
		WithDocumentFacts(data) => {
			ids = KernelMetadata.plan_objects(base_count) ? |_| ArithmeticOverflow
			profile_objects = KernelObjectPlan.Plan.profiles(objects)
			if data.profile.index() >= profile_objects.len() {
				return Err(IntentProfileUnplanned({ attempted: data.profile.index(), profiles: profile_objects.len() }))
			}
			WithCatalogFacts({
				condition_identifier: data.condition_identifier,
				language: data.language,
				metadata_stream: ids.stream,
				profile_stream: list_at(profile_objects, data.profile.index()).profile,
				registry_name: data.registry_name,
			})
		}
	}
	metadata_object_count = match facts {
		NoDocumentFacts => 0
		WithDocumentFacts(_) => 2
	}
	navigation_plan = match navigation {
		NoNavigation => NoNavigationPlan
		WithNavigation(input) => {
			resolved = KernelNavigation.resolve(input.store, KernelTagged.Plan.semantics(tagged), KernelTagged.Plan.occurrence_owners(tagged), input.anchor_rects) ? Navigation
			planned = KernelNavigationObjects.plan(checked_add(base_count, metadata_object_count)?, input.store) ? NavigationObjects
			var $annotation_pages = List.with_capacity(input.store.annotations.len())
			var $annotation_scan = 0
			while $annotation_scan < input.store.annotations.len() {
				$annotation_pages = $annotation_pages.append(list_at(input.store.annotations, $annotation_scan).page)
				$annotation_scan = $annotation_scan + 1
			}
			WithNavigationPlan({
				annotation_pages: $annotation_pages,
				max_outline_depth: input.max_outline_depth,
				planned,
				resolve_work: resolved.work,
				resolved: resolved.destinations,
				store: input.store,
			})
		}
	}
	widgets = match facts {
		NoDocumentFacts => NoWidgetPlan
		WithDocumentFacts(data) => KernelWidgetObjects.plan(data.widgets, checked_add(base_count, metadata_object_count)?) ? Widgets
	}
	navigation_facts = match navigation_plan {
		NoNavigationPlan => match widgets {
			NoWidgetPlan => NoNavigationObjects
			WithWidgetPlan(planned) => WithNavigationObjects({
				annotation_objects: planned.slots.map(|slot| slot.widget),
				annotation_pages: planned.slots.map(|slot| Semantics.PageId.from_index(slot.field.location.page)),
				dests_root: NoDestsRoot,
				ordered_annotations: widget_order(planned.slots.len()),
				outline_root: NoOutlineRoot,
				page_labels_root: NoPageLabelsRoot,
			})
		}
		WithNavigationPlan(plan_input) => WithNavigationObjects({
			annotation_objects: plan_input.planned.by_id,
			annotation_pages: plan_input.annotation_pages,
			dests_root: if (plan_input.planned.name_nodes.is_empty()) NoDestsRoot else DestsRootAt(list_at(plan_input.planned.name_nodes, 0)),
			ordered_annotations: plan_input.store.page_annotations,
			outline_root: plan_input.planned.outline_root,
			page_labels_root: if (plan_input.planned.label_nodes.is_empty()) NoPageLabelsRoot else PageLabelsRootAt(list_at(plan_input.planned.label_nodes, 0)),
		})
	}
	associated = match facts {
		NoDocumentFacts => NoAssociatedPlan
		WithDocumentFacts(data) => {
			after_metadata = checked_add(base_count, metadata_object_count)?
			after_navigation = match navigation_plan {
				NoNavigationPlan => after_metadata
				WithNavigationPlan(input) => checked_add(after_metadata, input.planned.total)?
			}
			KernelAssociatedObjects.plan(data.associated, after_navigation) ? Associated
		}
	}
	prefix = match (associated, widgets, navigation_plan) {
		(NoAssociatedPlan, NoWidgetPlan, _) => KernelTaggedObjects.Plan.build_with_navigation(tagged, objects, catalog_facts, navigation_facts, limits.object_limits)
		(WithAssociatedPlan(_), NoWidgetPlan, _) => KernelTaggedObjects.Plan.build_with_associated_files(tagged, objects, catalog_facts, navigation_facts, associated, limits.object_limits)
		(NoAssociatedPlan, WithWidgetPlan(planned), NoNavigationPlan) => KernelTaggedObjects.Plan.build_with_widgets(tagged, objects, catalog_facts, navigation_facts, planned, limits.object_limits)
		_ => return Err(Widgets(InvalidPlan))
	} ? TaggedObjects
	# Read the sidecars before passing the builder into the next stage.
	# Retaining each plan for its work record would keep the old builder alive.
	tagged_work = KernelTaggedObjects.Plan.work(prefix)
	planned_navigation_names = KernelTaggedObjects.Plan.navigation_names(prefix)
	page_count = KernelTagged.Plan.scenes(tagged).pages.len()
	content_work = KernelContent.Plan.work(content)
	content_stream_count = KernelContent.Plan.stream_count(content)
	font_object_count = KernelFontObjects.Plan.work(font_plan).font_objects
	font_xref = KernelFontObjects.Plan.xref(font_plan)
	pages = match navigation_plan {
		NoNavigationPlan => match widgets {
			NoWidgetPlan => KernelPageObjects.Plan.build_with_fonts(prefix, tagged, content, font_plan) ? Pages
			WithWidgetPlan(planned) => {
				per_page = widget_page_annotations(planned.slots, page_count)?
				KernelPageObjects.Plan.build_with_fonts_navigation(prefix, tagged, content, font_plan, per_page) ? Pages
			}
		}
		WithNavigationPlan(plan_input) => {
			var $per_page = List.with_capacity(page_count)
			var $page = 0
			while $page < page_count {
				start = list_at(plan_input.store.page_annotation_offsets, $page)
				end = list_at(plan_input.store.page_annotation_offsets, $page + 1)
				var $ids = List.with_capacity(end - start)
				var $slot = start
				while $slot < end {
					$ids = $ids.append(list_at(plan_input.planned.ordered, $slot))
					$slot = $slot + 1
				}
				$per_page = $per_page.append($ids)
				$page = $page + 1
			}
			KernelPageObjects.Plan.build_with_fonts_navigation(prefix, tagged, content, font_plan, $per_page) ? Pages
		}
	}
	page_work = KernelPageObjects.Plan.work(pages)
	root = KernelObjectPlan.Plan.catalog(objects)
	tree_nodes = KernelObjectPlan.Plan.page_tree(objects).len()
	resources = KernelResourceObjects.Plan.build(pages, colors, images, objects) ? Resources
	resource_work = KernelResourceObjects.Plan.work(resources)
	var $builder = KernelResourceObjects.Plan.builder(resources)
	var $font_objects = List.with_capacity(font_count)
	var $font_bytes = 0
	var $font_index = 0
	while $font_index < font_count {
		input = list_at(fonts, $font_index)
		font = KernelPdfFont.Plan.build($builder, input.font, input.plan, input.subset, input.descriptor, list_at(mappings, $font_index), limits.font_limits) ? Font
		emitted = KernelPdfFont.Plan.objects(font)
		planned = list_at(planned_fonts, $font_index)
		ensure_object(emitted.font_file, planned.first)?
		ensure_object(emitted.type0, planned.type0)?
		program_bytes = KernelPdfFont.Plan.work(font).font_program_bytes
		$builder = KernelPdfFont.Plan.builder(font)
		$font_objects = $font_objects.append(emitted)
		$font_bytes = checked_add($font_bytes, program_bytes)?
		$font_index = $font_index + 1
	}
	if $builder.store.objects.len() != base_count {
		return Err(ObjectCountMismatch({ actual: $builder.store.objects.len(), expected: base_count }))
	}
	{ builder: metadata_builder, metadata_bytes, metadata_objects, objects: after_metadata, xref: metadata_xref } = match facts {
		NoDocumentFacts => {
			builder: $builder,
			metadata_bytes: 0,
			metadata_objects: 0,
			objects: base_count,
			xref: font_xref,
		}
		WithDocumentFacts(data) => {
			ids = KernelMetadata.plan_objects(base_count) ? |_| ArithmeticOverflow
			with_stream = add_metadata_stream($builder, data.xmp, ids)?
			{
				builder: with_stream,
				metadata_bytes: data.xmp.len(),
				metadata_objects: 2,
				objects: checked_add(base_count, 2)?,
				xref: ids.xref,
			}
		}
	}
	{ builder: navigation_builder, objects: after_navigation, resolved: destinations_resolved, work: navigation_work, xref: navigation_xref } = match navigation_plan {
		NoNavigationPlan => {
			builder: metadata_builder,
			objects: after_metadata,
			resolved: 0,
			work: { annotation_objects: 0, label_node_objects: 0, name_node_objects: 0, outline_objects: 0, quad_numbers: 0 },
			xref: metadata_xref,
		}
		WithNavigationPlan(plan_input) => {
			navigation_names = match planned_navigation_names {
				WithNavigationNames(names) => names
				NoNavigationNames => {
					crash "navigation lowering lost its planned name table"
				}
			}
			var $page_objects = List.with_capacity(KernelObjectPlan.Plan.pages(objects).len())
			var $page_scan = 0
			while $page_scan < KernelObjectPlan.Plan.pages(objects).len() {
				$page_objects = $page_objects.append(list_at(KernelObjectPlan.Plan.pages(objects), $page_scan).page)
				$page_scan = $page_scan + 1
			}
			lowered = KernelNavigationObjects.add_objects(
				metadata_builder,
				navigation_names,
				plan_input.store,
				plan_input.resolved,
				plan_input.planned,
				{
					appearance_streams: [],
					page_objects: $page_objects,
					stream_count: content_stream_count,
					structure_elements: KernelObjectPlan.Plan.structure_elements(objects),
				},
				{ max_outline_depth: plan_input.max_outline_depth },
			) ? NavigationObjects
			{
				builder: lowered.builder,
				objects: checked_add(after_metadata, plan_input.planned.total)?,
				resolved: plan_input.resolve_work.destinations_resolved,
				work: lowered.work,
				xref: plan_input.planned.xref,
			}
		}
	}
	{ builder: associated_builder, objects: after_associated, ownership: association_ownership, xref: associated_xref } = match associated {
		NoAssociatedPlan => { builder: navigation_builder, objects: after_navigation, ownership: NoAssociationOwnership, xref: navigation_xref }
		WithAssociatedPlan(planned) => {
			lowered = KernelAssociatedObjects.lower(navigation_builder, planned, root) ? Associated
			{ builder: lowered.builder, objects: planned.object_count, ownership: lowered.ownership, xref: planned.xref }
		}
	}
	{ builder, objects: object_count, evidence: widget_evidence, xref } = match widgets {
		NoWidgetPlan => { builder: associated_builder, objects: after_associated, evidence: NoWidgetEvidence, xref: associated_xref }
		WithWidgetPlan(planned) => {
			page_objects = KernelObjectPlan.Plan.pages(objects).map(|page| page.page)
			lowered = KernelWidgetObjects.lower(associated_builder, planned, { catalog: root, pages: page_objects, content_streams: content_stream_count }) ? Widgets
			{ builder: lowered.builder, evidence: lowered.evidence, objects: KernelObject.ObjectId.number(planned.xref) - 1, xref: planned.xref }
		}
	}
	sealed = KernelSeal.seal(builder) ? Seal
	identity = KernelIdentity.digest(sealed) ? Identity
	bound = KernelOutputBound.calculate(sealed, xref) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		association_ownership,
		widget_evidence,
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelOutputBound.Bound.bytes(bound),
		page_count,
		root,
		sealed,
		tree_nodes,
		xref_object: xref,
	})
	Ok(
		KernelTaggedTextStructure.Plan.{
			font_objects: $font_objects,
			structure,
			work: {
				annotation_objects: navigation_work.annotation_objects,
				content_bytes: content_work.bytes_emitted,
				destinations_resolved,
				font_objects: font_object_count,
				font_program_bytes: $font_bytes,
				fonts: font_count,
				label_node_objects: navigation_work.label_node_objects,
				metadata_bytes,
				metadata_objects,
				name_node_objects: navigation_work.name_node_objects,
				objects: object_count,
				outline_objects: navigation_work.outline_objects,
				pages: page_work,
				quad_numbers: navigation_work.quad_numbers,
				resources: resource_work,
				tagged_objects: tagged_work,
			},
		},
	)
}

widget_order : U64 -> List(U64)
widget_order = |count| {
	var $items = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$items = $items.append($index)
		$index = $index + 1
	}
	$items
}

widget_page_annotations : List(KernelWidgetObjects.Slot), U64 -> Try(List(List(KernelObject.ObjectId)), KernelTaggedTextStructure.Error)
widget_page_annotations = |widgets, pages| {
	var $output = List.with_capacity(pages)
	var $page = 0
	var $widget = 0
	while $page < pages {
		var $refs = []
		while $widget < widgets.len() and list_at(widgets, $widget).field.location.page == $page {
			$refs = $refs.append(list_at(widgets, $widget).widget)
			$widget = $widget + 1
		}
		$output = $output.append($refs)
		$page = $page + 1
	}
	if $widget != widgets.len() {
		return Err(Widgets(InvalidPlan))
	}
	Ok($output)
}

NavigationPlanState := [
	NoNavigationPlan,
	WithNavigationPlan(
		{
			annotation_pages : List(Semantics.PageId),
			max_outline_depth : U64,
			planned : KernelNavigationObjects.Objects,
			resolve_work : KernelNavigation.ResolveWork,
			resolved : List(KernelNavigation.ResolvedDestination),
			store : KernelNavigation.Store,
		},
	),
]

## The metadata stream is the canonical XMP packet as an uncompressed
## `/Type /Metadata /Subtype /XML` stream: unfiltered so the packet stays
## byte-addressable, which the later PDF/A-4 profile also requires.
add_metadata_stream : KernelObject.Builder, List(U8), KernelMetadata.Objects -> Try(KernelObject.Builder, KernelTaggedTextStructure.Error)
add_metadata_stream = |builder, xmp, ids| {
	metadata_name = KernelObject.add_name(builder, Str.to_utf8("Metadata")) ? Object
	subtype_name = KernelObject.add_name(metadata_name.builder, Str.to_utf8("Subtype")) ? Object
	type_name = KernelObject.add_name(subtype_name.builder, Str.to_utf8("Type")) ? Object
	xml_name = KernelObject.add_name(type_name.builder, Str.to_utf8("XML")) ? Object
	subtype_value = KernelObject.add_name_value(xml_name.builder, xml_name.id) ? Object
	type_value = KernelObject.add_name_value(subtype_value.builder, metadata_name.id) ? Object
	payload = KernelObject.add_payload(type_value.builder, xmp, Generated) ? Object
	stream = KernelObject.add_stream_object(
		payload.builder,
		[
			{ key: subtype_name.id, value: subtype_value.id },
			{ key: type_name.id, value: type_value.id },
		],
		Unfiltered,
		payload.id,
	) ? Object
	ensure_object(stream.id, ids.stream)?
	ensure_object(stream.length_object, ids.length)?
	Ok(stream.builder)
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelTaggedTextStructure.Error)
ensure_object = |actual, expected| if (actual == expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

checked_add : U64, U64 -> Try(U64, KernelTaggedTextStructure.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => {
		crash "validated tagged text-structure index escaped"
	}
	Ok(value) => value
}
