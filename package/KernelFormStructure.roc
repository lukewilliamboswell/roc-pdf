import Color
import Document
import KernelColor
import KernelContent
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelForm
import KernelIdentity
import KernelObjectPlan
import KernelOutputBound
import KernelPageObjects
import KernelResourceName
import KernelResourceObjects
import KernelTaggedObjects
import KernelFormObjects
import KernelImage
import KernelLex
import KernelMetadata
import KernelNavigation
import KernelNavigationObjects
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelStructure
import KernelTagged
import Layout
import Scene
import Semantics

## production-visual object assembly: the tagged-visual tagged prefix, per-page exact direct
## resource dictionaries, the tagged-visual page tree and resource objects, canonical
## Form XObject stream objects with their own exact direct dictionaries, and
## the Type 0 font objects when text is present — sealed into one
## deterministic plan. Every dictionary entry comes from the form plan's
## normalized facts; nothing here re-derives sharing or scans operators.
KernelFormStructure :: [].{
	Error : [
		ArithmeticOverflow,
		Font(KernelPdfFont.Error),
		FontCountMismatch({ authored : U64, fonts : U64, mappings : U64, planned : U64 }),
		FormStreamCountMismatch({ planned : U64, streams : U64 }),
		IntentProfileUnplanned({ attempted : U64, profiles : U64 }),
		PatternStreamCountMismatch({ planned : U64, streams : U64 }),
		ShadingStoreMismatch({ shadings : U64, supplied : U64 }),
		Identity(KernelIdentity.Error),
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

	## Post-layout navigation input: the validated navigation store plus the
	## prepared per-fragment anchor rectangles destination resolution consumes,
	## and the authored outline-depth limit the sealed outline plan re-checks.
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
		dictionary_references : U64,
		font_program_bytes : U64,
		fonts : U64,
		form_objects : U64,
		form_stream_bytes : U64,
		function_objects : U64,
		isolated_form_groups : U64,
		label_node_objects : U64,
		metadata_bytes : U64,
		metadata_objects : U64,
		name_node_objects : U64,
		objects : U64,
		outline_objects : U64,
		quad_numbers : U64,
		pages : KernelPageObjects.Work,
		pattern_objects : U64,
		pattern_stream_bytes : U64,
		resources : KernelResourceObjects.Work,
		shading_objects : U64,
		state_objects : U64,
		tagged_objects : KernelTaggedObjects.Work,
		transparency_page_groups : U64,
	}

	Plan :: { structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelFormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(FontInput), text : KernelPdfText.ScenePlan })], Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, forms, objects, text, limits| build_plan(tagged, colors, images, content, forms, objects, text, Scene.no_shadings, NoDocumentFacts, NoNavigation, limits)

		## The paint-aware variant: shading, function, and tiling-pattern
		## objects lower between the graphics states and the font objects,
		## with stop offsets and channel values read from the validated
		## shading store the plan was normalized from.
		build_with_paints : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelFormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(FontInput), text : KernelPdfText.ScenePlan })], Scene.ShadingStore, Limits -> Try(Plan, Error)
		build_with_paints = |tagged, colors, images, content, forms, objects, text, shading_store, limits| build_plan(tagged, colors, images, content, forms, objects, text, shading_store, NoDocumentFacts, NoNavigation, limits)

		## The document-fact variant: the catalog gains its validated language,
		## metadata, and packaged-sRGB output-intent entries, the canonical XMP
		## stream lowers after the font objects, and the intent references the
		## canonical (deduplicated) profile stream that ICCBased color spaces
		## share. `NoDocumentFacts` is byte-identical to the entries above.
		build_with_facts : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelFormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(FontInput), text : KernelPdfText.ScenePlan })], Scene.ShadingStore, KernelMetadata.PlanFacts, Limits -> Try(Plan, Error)
		build_with_facts = |tagged, colors, images, content, forms, objects, text, shading_store, facts, limits| build_plan(tagged, colors, images, content, forms, objects, text, shading_store, facts, NoNavigation, limits)

		## The navigation variant: destinations resolve to their paired
		## structure and geometric targets, link annotation dictionaries with
		## both `/SD` and `/D` lower after the metadata stream, pages gain
		## their `/Annots` arrays in keyboard order, the catalog gains its
		## `/Names`, `/Outlines`, and `/PageLabels` roots, annotation spine
		## items lower as OBJR kids, and the ParentTree gains one scalar row
		## per annotation. `NoNavigation` is byte-identical to
		## `build_with_facts`.
		build_with_navigation : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelFormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(FontInput), text : KernelPdfText.ScenePlan })], Scene.ShadingStore, KernelMetadata.PlanFacts, NavigationInput, Limits -> Try(Plan, Error)
		build_with_navigation = |tagged, colors, images, content, forms, objects, text, shading_store, facts, navigation, limits| build_plan(tagged, colors, images, content, forms, objects, text, shading_store, facts, navigation, limits)

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

StateNames := { blend_mode : KernelObject.NameId, ext_g_state : KernelObject.NameId, nonstroking_alpha : KernelObject.NameId, normal : KernelObject.NameId, stroking_alpha : KernelObject.NameId }

MaskNames := { alpha : KernelObject.NameId, g : KernelObject.NameId, mask : KernelObject.NameId, s_mask : KernelObject.NameId }

GroupNames := { cs : KernelObject.NameId, group : KernelObject.NameId, isolated : KernelObject.NameId, s : KernelObject.NameId, transparency : KernelObject.NameId }

PaintNames := {
	c0 : KernelObject.NameId,
	c1 : KernelObject.NameId,
	coords : KernelObject.NameId,
	domain : KernelObject.NameId,
	extend : KernelObject.NameId,
	function : KernelObject.NameId,
	function_type : KernelObject.NameId,
	n : KernelObject.NameId,
	shading : KernelObject.NameId,
	shading_type : KernelObject.NameId,
}

StitchNames := { bounds : KernelObject.NameId, encode : KernelObject.NameId, functions : KernelObject.NameId }

PatternKeyNames := {
	paint_type : KernelObject.NameId,
	pattern : KernelObject.NameId,
	pattern_type : KernelObject.NameId,
	tiling_type : KernelObject.NameId,
	x_step : KernelObject.NameId,
	y_step : KernelObject.NameId,
}

## The graphics-state and transparency-group names join the table only when
## the plan actually contains those facts, so a plan without transparency
## keeps its exact name table and normalized plan identity.
Names := {
	b_box : KernelObject.NameId,
	color_space : KernelObject.NameId,
	font : KernelObject.NameId,
	form : KernelObject.NameId,
	form_type : KernelObject.NameId,
	group_names : [NoGroupNames, WithGroupNames(GroupNames)],
	mask_names : [NoMaskNames, WithMaskNames(MaskNames)],
	matrix : KernelObject.NameId,
	paint_names : [NoPaintNames, WithPaintNames(PaintNames)],
	pattern_key_names : [NoPatternKeyNames, WithPatternKeyNames(PatternKeyNames)],
	resources : KernelObject.NameId,
	state_names : [NoStateNames, WithStateNames(StateNames)],
	stitch_names : [NoStitchNames, WithStitchNames(StitchNames)],
	subtype : KernelObject.NameId,
	type_name : KernelObject.NameId,
	x_object : KernelObject.NameId,
}

ResourceNames := {
	color_spaces : List(KernelObject.NameId),
	fonts : List(KernelObject.NameId),
	forms : List(KernelObject.NameId),
	images : List(KernelObject.NameId),
	patterns : List(KernelObject.NameId),
	shadings : List(KernelObject.NameId),
	states : List(KernelObject.NameId),
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelFormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(KernelFormStructure.FontInput), text : KernelPdfText.ScenePlan })], Scene.ShadingStore, KernelMetadata.PlanFacts, KernelFormStructure.NavigationInput, KernelFormStructure.Limits -> Try(KernelFormStructure.Plan, KernelFormStructure.Error)
build_plan = |tagged, colors, images, content, forms, objects, text, shading_store, facts, navigation, limits| {
	base = KernelFormObjects.Plan.base(objects)
	planned_fonts = KernelFormObjects.Plan.fonts(objects)
	canonical_forms = KernelForm.Plan.canonical_form_count(forms)
	canonical_shadings = KernelForm.Plan.canonical_shading_count(forms)
	canonical_functions = KernelForm.Plan.canonical_function_count(forms)
	canonical_patterns = KernelForm.Plan.canonical_pattern_count(forms)
	if KernelContent.Plan.form_stream_count(content) != canonical_forms {
		return Err(FormStreamCountMismatch({ planned: canonical_forms, streams: KernelContent.Plan.form_stream_count(content) }))
	}
	if KernelContent.Plan.pattern_stream_count(content) != canonical_patterns {
		return Err(PatternStreamCountMismatch({ planned: canonical_patterns, streams: KernelContent.Plan.pattern_stream_count(content) }))
	}
	if KernelForm.Plan.work(forms).authored_shadings != shading_store.shadings.len() {
		return Err(ShadingStoreMismatch({ shadings: KernelForm.Plan.work(forms).authored_shadings, supplied: shading_store.shadings.len() }))
	}

	## One bundle per canonical font: the supplied authored bundles and their
	## collected mappings must match the plan's authored count exactly, and
	## the planned object identities must match the canonical count exactly.
	authored_fonts = KernelForm.Plan.work(forms).authored_fonts
	font_representatives = KernelForm.Plan.canonical_font_representatives(forms)
	match text {
		NoTextObjects => if planned_fonts.len() != 0 or authored_fonts != 0 {
			return Err(FontCountMismatch({ authored: authored_fonts, fonts: 0, mappings: 0, planned: planned_fonts.len() }))
		} else {
			{}
		}
		WithTextObjects(input) => {
			mappings = KernelPdfText.ScenePlan.mappings(input.text)
			if input.fonts.len() == 0 or input.fonts.len() != mappings.len() or input.fonts.len() != authored_fonts or planned_fonts.len() != font_representatives.len() {
				return Err(FontCountMismatch({ authored: authored_fonts, fonts: input.fonts.len(), mappings: mappings.len(), planned: planned_fonts.len() }))
			}
			{}
		}
	}

	base_object_count = KernelFormObjects.Plan.object_count(objects)
	catalog_facts = match facts {
		NoDocumentFacts => NoCatalogFacts
		WithDocumentFacts(data) => {
			ids = KernelMetadata.plan_objects(base_object_count) ? |_| ArithmeticOverflow
			profile_ordinals = KernelForm.Plan.profile_names(forms)
			if data.profile.index() >= profile_ordinals.len() {
				return Err(IntentProfileUnplanned({ attempted: data.profile.index(), profiles: profile_ordinals.len() }))
			}
			ordinal = list_at(profile_ordinals, data.profile.index())
			profile_objects = KernelObjectPlan.Plan.profiles(base)
			if ordinal >= profile_objects.len() {
				return Err(IntentProfileUnplanned({ attempted: ordinal, profiles: profile_objects.len() }))
			}
			WithCatalogFacts({
				condition_identifier: data.condition_identifier,
				language: data.language,
				metadata_stream: ids.stream,
				profile_stream: list_at(profile_objects, ordinal).profile,
				registry_name: data.registry_name,
			})
		}
	}
	metadata_object_count = match facts {
		NoDocumentFacts => 0
		WithDocumentFacts(_) => 2
	}

	## Navigation planning and resolution: destinations resolve through the
	## tagging stage's occurrence-owner map and the prepared anchor geometry,
	## and every navigation object identity is planned after the metadata
	## objects so the tagged prefix can reference annotation objects, the
	## page lowering can reference /Annots entries, and the catalog can
	## reference the name-tree, outline, and page-label roots.
	navigation_plan = match navigation {
		NoNavigation => NoNavigationPlan
		WithNavigation(input) => {
			resolved = KernelNavigation.resolve(
				input.store,
				KernelTagged.Plan.semantics(tagged),
				KernelTagged.Plan.occurrence_owners(tagged),
				input.anchor_rects,
			) ? Navigation
			planned = KernelNavigationObjects.plan(checked_add(base_object_count, metadata_object_count)?, input.store) ? NavigationObjects
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
				resolved: resolved.destinations,
				resolve_work: resolved.work,
				store: input.store,
			})
		}
	}

	## Normal appearances integrate through the shared form pipeline: every
	## referenced appearance is a canonical Form XObject whose bounding box
	## must be exactly `[0 0 w h]` with the annotation rectangle's extents,
	## so the identity `/Matrix` maps appearance space onto `/Rect` one to
	## one. Sharing one canonical form across annotations never merges their
	## occurrences; a geometric disagreement is a per-annotation rejection.
	match navigation_plan {
		NoNavigationPlan => {}
		WithNavigationPlan(plan_input) => {
			appearance_names = KernelForm.Plan.form_names(forms)
			var $appearance_check = 0
			while $appearance_check < plan_input.store.annotations.len() {
				annotation = list_at(plan_input.store.annotations, $appearance_check)
				match annotation.appearance {
					NoAppearance => {}
					NormalAppearance(form) => {
						if form.index() >= appearance_names.len() {
							return Err(Navigation(AppearanceFormOutOfRange({ annotation: $appearance_check, attempted: form.index(), forms: appearance_names.len() })))
						}
						canonical = KernelForm.Plan.canonical_form(forms, list_at(appearance_names, form.index()))
						if canonical.bbox.origin.x.raw() != 0 or
							canonical.bbox.origin.y.raw() != 0 or
								canonical.bbox.size.width.raw() != annotation.rect.size.width.raw() or
									canonical.bbox.size.height.raw() != annotation.rect.size.height.raw() {
							return Err(Navigation(AppearanceGeometryMismatch({ annotation: $appearance_check, form: form.index() })))
						}
					}
				}
				$appearance_check = $appearance_check + 1
			}
		}
	}
	navigation_facts = match navigation_plan {
		NoNavigationPlan => NoNavigationObjects
		WithNavigationPlan(plan_input) => WithNavigationObjects({
			annotation_objects: plan_input.planned.by_id,
			annotation_pages: plan_input.annotation_pages,
			dests_root: if plan_input.planned.name_nodes.is_empty() NoDestsRoot else DestsRootAt(list_at(plan_input.planned.name_nodes, 0)),
			ordered_annotations: plan_input.store.page_annotations,
			outline_root: plan_input.planned.outline_root,
			page_labels_root: if plan_input.planned.label_nodes.is_empty() NoPageLabelsRoot else PageLabelsRootAt(list_at(plan_input.planned.label_nodes, 0)),
		})
	}
	prefix = KernelTaggedObjects.Plan.build_with_navigation(tagged, base, catalog_facts, navigation_facts, limits.object_limits) ? TaggedObjects

	## Deterministic resource names, created once for the canonical
	## (deduplicated) leaf and form counts, then one exact direct dictionary
	## value per page.
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(forms)
	canonical_states = KernelForm.Plan.canonical_state_count(forms)
	page_transparency = KernelForm.Plan.page_transparency(forms)
	form_isolation = KernelForm.Plan.form_isolation(forms)
	with_groups = any_flag(page_transparency) or any_flag(form_isolation)
	with_masks = KernelForm.Plan.work(forms).canonical_mask_states > 0
	var $with_stitch = Bool.False
	var $stitch_scan = 0
	while $stitch_scan < canonical_functions {
		match KernelForm.Plan.canonical_function_fact(forms, $stitch_scan) {
			SegmentFact(_) => {}
			StitchFact(_) => {
				$with_stitch = Bool.True
			}
		}
		$stitch_scan = $stitch_scan + 1
	}
	named = add_names(KernelTaggedObjects.Plan.builder(prefix), canonical_states > 0, with_groups, with_masks, canonical_shadings > 0, $with_stitch, canonical_patterns > 0)?
	resource_names = add_resource_names(named.builder, leaf_counts.color_spaces, leaf_counts.images, planned_fonts.len(), canonical_forms, canonical_states, canonical_shadings, canonical_patterns)?
	var $builder = resource_names.builder
	page_count = KernelTagged.Plan.scenes(tagged).pages.len()
	var $page_values = List.with_capacity(page_count)
	var $references = 0
	var $page = 0
	var $failure = NoFailure
	while $page < page_count and $failure == NoFailure {
		match add_resource_dictionary($builder, named.names, resource_names.names, KernelForm.Plan.page_dictionary(forms, $page), base, objects) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(added) => {
				$builder = added.builder
				$page_values = $page_values.append(added.id)
				$references = $references + added.references
			}
		}
		$page = $page + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## One shared transparency group value serves every transparency page: its
	## `/CS` references the canonical blending-space object the normalized plan
	## selected. A document without transparency pages plans no group value and
	## takes the unchanged page path, keeping its exact plan identity.
	group_plan = add_page_group_value($builder, named.names, forms, base, page_transparency)?
	$builder = group_plan.builder
	var $transparency_page_groups = 0
	var $page_groups = List.with_capacity(page_count)
	var $group_page = 0
	while $group_page < page_count {
		entry = match group_plan.value {
			NoGroupValue => NoGroup
			GroupValue(group_value) => if list_at(page_transparency, $group_page) {
				$transparency_page_groups = $transparency_page_groups + 1
				WithGroup(group_value)
			} else {
				NoGroup
			}
		}
		$page_groups = $page_groups.append(entry)
		$group_page = $group_page + 1
	}
	pages = match navigation_plan {
		NoNavigationPlan => match group_plan.value {
			NoGroupValue => KernelPageObjects.Plan.build_with_page_resources($builder, tagged, content, base, $page_values, $references) ? Pages
			GroupValue(_) => KernelPageObjects.Plan.build_with_page_groups($builder, tagged, content, base, $page_values, $references, $page_groups) ? Pages
		}
		WithNavigationPlan(plan_input) => {

			## Per-page /Annots reference arrays in keyboard order, built
			## from the planned annotation identities before the pages
			## reference them.
			var $annots = List.with_capacity(page_count)
			var $annots_builder = $builder
			var $annots_page = 0
			var $annots_failure = NoFailure
			while $annots_page < page_count and $annots_failure == NoFailure {
				start = list_at(plan_input.store.page_annotation_offsets, $annots_page)
				end = list_at(plan_input.store.page_annotation_offsets, $annots_page + 1)
				if end == start {
					$annots = $annots.append(NoAnnots)
				} else {
					var $refs = List.with_capacity(end - start)
					var $slot = start
					while $slot < end and $annots_failure == NoFailure {
						match KernelObject.add_reference($annots_builder, list_at(plan_input.planned.ordered, $slot)) {
							Err(error) => {
								$annots_failure = Failed(Object(error))
							}
							Ok(added) => {
								$annots_builder = added.builder
								$refs = $refs.append(added.id)
							}
						}
						$slot = $slot + 1
					}
					match $annots_failure {
						Failed(_) => {}
						NoFailure => match KernelObject.add_array($annots_builder, $refs) {
							Err(error) => {
								$annots_failure = Failed(Object(error))
							}
							Ok(array) => {
								$annots_builder = array.builder
								$annots = $annots.append(WithAnnots(array.id))
							}
						}
					}
				}
				$annots_page = $annots_page + 1
			}
			match $annots_failure {
				Failed(error) => return Err(error)
				NoFailure => {}
			}
			KernelPageObjects.Plan.build_with_page_navigation($annots_builder, tagged, content, base, $page_values, $references, $page_groups, $annots) ? Pages
		}
	}
	var $image_planes = List.with_capacity(leaf_counts.images)
	var $plane_ordinal = 0
	while $plane_ordinal < leaf_counts.images {
		$image_planes = $image_planes.append(KernelForm.Plan.canonical_image_planes(forms, $plane_ordinal))
		$plane_ordinal = $plane_ordinal + 1
	}
	resources = KernelResourceObjects.Plan.build_canonical(
		pages,
		colors,
		images,
		base,
		{
			color_names: KernelForm.Plan.color_names(forms),
			color_representatives: KernelForm.Plan.canonical_color_representatives(forms),
			image_planes: $image_planes,
			image_representatives: KernelForm.Plan.canonical_image_representatives(forms),
			profile_names: KernelForm.Plan.profile_names(forms),
			profile_representatives: KernelForm.Plan.canonical_profile_representatives(forms),
		},
	) ? Resources

	## Canonical Form XObject stream objects in canonical order, each with its
	## complete direct dictionary, explicit bounding box, the canonical
	## identity matrix, and — for isolated transparency groups — the explicit
	## `/Group` dictionary naming the canonical blending space. Deferred
	## capabilities emit no keys at all. One shared isolated-group value
	## serves every isolated form because they share one blending space.
	var $form_builder = KernelResourceObjects.Plan.builder(resources)
	isolated_group_plan = add_isolated_group_value($form_builder, named.names, forms, base, form_isolation)?
	$form_builder = isolated_group_plan.builder
	var $isolated_form_groups = 0
	var $form_bytes = 0
	var $ordinal = 0
	while $ordinal < canonical_forms and $failure == NoFailure {
		canonical = KernelForm.Plan.canonical_form(forms, $ordinal)
		stream = KernelContent.Plan.form_stream(content, $ordinal)
		planned = list_at(KernelFormObjects.Plan.forms(objects), $ordinal)
		form_group = if list_at(form_isolation, $ordinal) {
			match isolated_group_plan.value {
				NoGroupValue => NoGroupValue
				GroupValue(value) => GroupValue(value)
			}
		} else {
			NoGroupValue
		}
		match form_group {
			NoGroupValue => {}
			GroupValue(_) => {
				$isolated_form_groups = $isolated_form_groups + 1
			}
		}
		match add_form_object($form_builder, named.names, resource_names.names, KernelForm.Plan.form_dictionary(forms, $ordinal), canonical.bbox, stream.bytes, base, objects, planned, form_group) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(added) => {
				$form_builder = added.builder
				$references = $references + added.references
				$form_bytes = $form_bytes + stream.bytes.len()
			}
		}
		$ordinal = $ordinal + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical graphics-state objects in canonical order: constant-alpha
	## states carry the exact effective alphas under the Normal blend mode,
	## and soft-mask states carry the Alpha mask dictionary referencing their
	## canonical mask form's stream object directly.
	var $state_builder = $form_builder
	var $state_ordinal = 0
	while $state_ordinal < canonical_states and $failure == NoFailure {
		planned_state = list_at(KernelFormObjects.Plan.states(objects), $state_ordinal)
		state_result = match KernelForm.Plan.state_fact(forms, $state_ordinal) {
			Alpha(value) => add_state_object($state_builder, named.names, value, planned_state)
			Mask(mask_ordinal) => add_mask_state_object($state_builder, named.names, list_at(KernelFormObjects.Plan.forms(objects), mask_ordinal).stream, planned_state)
		}
		match state_result {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(next) => {
				$state_builder = next
			}
		}
		$state_ordinal = $state_ordinal + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical shading dictionaries in canonical order: each names its
	## canonical color-space object, its exact coordinates, the explicit
	## domain, its extend flags, and its canonical root function object.
	var $paint_builder = $state_builder
	var $shading_ordinal = 0
	while $shading_ordinal < canonical_shadings and $failure == NoFailure {
		fact = KernelForm.Plan.canonical_shading_fact(forms, $shading_ordinal)
		planned_shading = list_at(KernelFormObjects.Plan.shadings(objects), $shading_ordinal)
		match add_shading_object($paint_builder, named.names, fact, base, objects, planned_shading) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(next) => {
				$paint_builder = next
			}
		}
		$shading_ordinal = $shading_ordinal + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical function dictionaries: exponential segment functions carry
	## the exact stop colors of their representative shading, and stitching
	## functions carry the exact interior stop offsets as bounds with the
	## canonical segment references, all read from the validated store.
	var $function_ordinal = 0
	while $function_ordinal < canonical_functions and $failure == NoFailure {
		fact = KernelForm.Plan.canonical_function_fact(forms, $function_ordinal)
		planned_function = list_at(KernelFormObjects.Plan.functions(objects), $function_ordinal)
		match add_function_object($paint_builder, named.names, shading_store, fact, objects, planned_function) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(next) => {
				$paint_builder = next
			}
		}
		$function_ordinal = $function_ordinal + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Canonical tiling-pattern stream objects, each with its complete
	## direct dictionary, explicit bounds, steps, matrix, and the colored
	## constant-spacing tiling policy.
	var $pattern_bytes = 0
	var $pattern_ordinal = 0
	while $pattern_ordinal < canonical_patterns and $failure == NoFailure {
		canonical_cell = KernelForm.Plan.canonical_pattern(forms, $pattern_ordinal)
		pattern_stream = KernelContent.Plan.pattern_stream(content, $pattern_ordinal)
		planned_pattern = list_at(KernelFormObjects.Plan.patterns(objects), $pattern_ordinal)
		match add_pattern_object($paint_builder, named.names, resource_names.names, KernelForm.Plan.pattern_dictionary(forms, $pattern_ordinal), canonical_cell, pattern_stream.bytes, base, objects, planned_pattern) {
			Err(error) => {
				$failure = Failed(error)
			}
			Ok(added) => {
				$paint_builder = added.builder
				$references = $references + added.references
				$pattern_bytes = $pattern_bytes + pattern_stream.bytes.len()
			}
		}
		$pattern_ordinal = $pattern_ordinal + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	## Type 0 font objects: exactly one physical bundle per canonical font,
	## in canonical order, lowered from its lowest authored representative's
	## validated facts and that representative's collected mappings, landing
	## exactly at the planned identities. A duplicate bundle for one
	## canonical identity is structurally unrepresentable here.
	var $font_builder = $paint_builder
	var $font_program_bytes = 0
	match text {
		NoTextObjects => {}
		WithTextObjects(input) => {
			mappings = KernelPdfText.ScenePlan.mappings(input.text)
			var $font_ordinal = 0
			while $font_ordinal < font_representatives.len() and $failure == NoFailure {
				representative = list_at(font_representatives, $font_ordinal)
				font_input = list_at(input.fonts, representative)
				match KernelPdfFont.Plan.build(
					$font_builder,
					font_input.font,
					font_input.plan,
					font_input.subset,
					font_input.descriptor,
					list_at(mappings, representative),
					limits.font_limits,
				) {
					Err(error) => {
						$failure = Failed(Font(error))
					}
					Ok(font) => {
						emitted = KernelPdfFont.Plan.objects(font)
						planned = list_at(planned_fonts, $font_ordinal)
						if !KernelObject.ObjectId.is_eq(emitted.font_file, planned.first) {
							$failure = Failed(ObjectOrder({ actual: emitted.font_file, expected: planned.first }))
						} else if !KernelObject.ObjectId.is_eq(emitted.type0, planned.type0) {
							$failure = Failed(ObjectOrder({ actual: emitted.type0, expected: planned.type0 }))
						} else {
							$font_builder = KernelPdfFont.Plan.builder(font)
							$font_program_bytes = $font_program_bytes + KernelPdfFont.Plan.work(font).font_program_bytes
						}
					}
				}
				$font_ordinal = $font_ordinal + 1
			}
		}
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	if $font_builder.store.objects.len() != base_object_count {
		return Err(ObjectCountMismatch({ actual: $font_builder.store.objects.len(), expected: base_object_count }))
	}
	finished = match facts {
		NoDocumentFacts => {
			builder: $font_builder,
			metadata_bytes: 0,
			metadata_objects: 0,
			objects: base_object_count,
			xref: KernelFormObjects.Plan.xref(objects),
		}
		WithDocumentFacts(data) => {
			ids = KernelMetadata.plan_objects(base_object_count) ? |_| ArithmeticOverflow
			with_stream = add_metadata_stream($font_builder, data.xmp, ids)?
			{
				builder: with_stream,
				metadata_bytes: data.xmp.len(),
				metadata_objects: 2,
				objects: base_object_count + 2,
				xref: ids.xref,
			}
		}
	}

	## Navigation objects lower last, after the metadata stream, landing
	## exactly on their planned identities; the xref shifts past them.
	navigated = match navigation_plan {
		NoNavigationPlan => {
			builder: finished.builder,
			objects: finished.objects,
			work: { annotation_objects: 0, label_node_objects: 0, name_node_objects: 0, outline_objects: 0, quad_numbers: 0 },
			resolved: 0,
			xref: finished.xref,
		}
		WithNavigationPlan(plan_input) => {
			navigation_names = match KernelTaggedObjects.Plan.navigation_names(prefix) {
				WithNavigationNames(names) => names
				NoNavigationNames => {
					crash "navigation lowering lost its planned name table"
				}
			}
			var $appearance_streams = List.with_capacity(KernelForm.Plan.form_names(forms).len())
			var $appearance_scan = 0
			while $appearance_scan < KernelForm.Plan.form_names(forms).len() {
				ordinal = list_at(KernelForm.Plan.form_names(forms), $appearance_scan)
				$appearance_streams = $appearance_streams.append(list_at(KernelFormObjects.Plan.forms(objects), ordinal).stream)
				$appearance_scan = $appearance_scan + 1
			}
			var $page_objects = List.with_capacity(page_count)
			var $page_scan = 0
			while $page_scan < page_count {
				$page_objects = $page_objects.append(list_at(KernelObjectPlan.Plan.pages(base), $page_scan).page)
				$page_scan = $page_scan + 1
			}
			lowered = KernelNavigationObjects.add_objects(
				finished.builder,
				navigation_names,
				plan_input.store,
				plan_input.resolved,
				plan_input.planned,
				{
					appearance_streams: $appearance_streams,
					page_objects: $page_objects,
					stream_count: KernelContent.Plan.stream_count(content),
					structure_elements: KernelObjectPlan.Plan.structure_elements(base),
				},
				{ max_outline_depth: plan_input.max_outline_depth },
			) ? NavigationObjects
			{
				builder: lowered.builder,
				objects: checked_add(finished.objects, plan_input.planned.total)?,
				work: lowered.work,
				resolved: plan_input.resolve_work.destinations_resolved,
				xref: plan_input.planned.xref,
			}
		}
	}
	expected = navigated.objects
	sealed = KernelSeal.seal(navigated.builder) ? Seal
	identity = KernelIdentity.digest(sealed) ? Identity
	bound = KernelOutputBound.calculate(sealed, navigated.xref) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelOutputBound.Bound.bytes(bound),
		page_count,
		root: KernelObjectPlan.Plan.catalog(base),
		sealed,
		tree_nodes: KernelObjectPlan.Plan.page_tree(base).len(),
		xref_object: navigated.xref,
	})
	Ok(
		KernelFormStructure.Plan.{
			structure,
			work: {
				annotation_objects: navigated.work.annotation_objects,
				content_bytes: KernelContent.Plan.work(content).bytes_emitted,
				destinations_resolved: navigated.resolved,
				dictionary_references: $references,
				font_program_bytes: $font_program_bytes,
				fonts: planned_fonts.len(),
				form_objects: KernelFormObjects.Plan.work(objects).form_objects,
				form_stream_bytes: $form_bytes,
				function_objects: canonical_functions,
				isolated_form_groups: $isolated_form_groups,
				label_node_objects: navigated.work.label_node_objects,
				metadata_bytes: finished.metadata_bytes,
				metadata_objects: finished.metadata_objects,
				name_node_objects: navigated.work.name_node_objects,
				objects: expected,
				outline_objects: navigated.work.outline_objects,
				pages: KernelPageObjects.Plan.work(pages),
				pattern_objects: canonical_patterns,
				pattern_stream_bytes: $pattern_bytes,
				quad_numbers: navigated.work.quad_numbers,
				resources: KernelResourceObjects.Plan.work(resources),
				shading_objects: canonical_shadings,
				state_objects: canonical_states,
				tagged_objects: KernelTaggedObjects.Plan.work(prefix),
				transparency_page_groups: $transparency_page_groups,
			},
		},
	)
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

checked_add : U64, U64 -> Try(U64, KernelFormStructure.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

## The metadata stream is the canonical XMP packet as an uncompressed
## `/Type /Metadata /Subtype /XML` stream appended after the font objects.
add_metadata_stream : KernelObject.Builder, List(U8), KernelMetadata.Objects -> Try(KernelObject.Builder, KernelFormStructure.Error)
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
	if !KernelObject.ObjectId.is_eq(stream.id, ids.stream) {
		return Err(ObjectOrder({ actual: stream.id, expected: ids.stream }))
	}
	if !KernelObject.ObjectId.is_eq(stream.length_object, ids.length) {
		return Err(ObjectOrder({ actual: stream.length_object, expected: ids.length }))
	}
	Ok(stream.builder)
}

add_names : KernelObject.Builder, Bool, Bool, Bool, Bool, Bool, Bool -> Try({ builder : KernelObject.Builder, names : Names }, KernelFormStructure.Error)
add_names = |builder, with_states, with_groups, with_masks, with_shadings, with_stitch, with_patterns| {
	b_box = KernelObject.add_name(builder, Str.to_utf8("BBox")) ? Object
	color_space = KernelObject.add_name(b_box.builder, Str.to_utf8("ColorSpace")) ? Object
	font = KernelObject.add_name(color_space.builder, Str.to_utf8("Font")) ? Object
	form = KernelObject.add_name(font.builder, Str.to_utf8("Form")) ? Object
	form_type = KernelObject.add_name(form.builder, Str.to_utf8("FormType")) ? Object
	matrix = KernelObject.add_name(form_type.builder, Str.to_utf8("Matrix")) ? Object
	resources = KernelObject.add_name(matrix.builder, Str.to_utf8("Resources")) ? Object
	subtype = KernelObject.add_name(resources.builder, Str.to_utf8("Subtype")) ? Object
	type_name = KernelObject.add_name(subtype.builder, Str.to_utf8("Type")) ? Object
	x_object = KernelObject.add_name(type_name.builder, Str.to_utf8("XObject")) ? Object

	states = if with_states {
		blend_mode = KernelObject.add_name(x_object.builder, Str.to_utf8("BM")) ? Object
		stroking_alpha = KernelObject.add_name(blend_mode.builder, Str.to_utf8("CA")) ? Object
		ext_g_state = KernelObject.add_name(stroking_alpha.builder, Str.to_utf8("ExtGState")) ? Object
		normal = KernelObject.add_name(ext_g_state.builder, Str.to_utf8("Normal")) ? Object
		nonstroking_alpha = KernelObject.add_name(normal.builder, Str.to_utf8("ca")) ? Object
		{
			builder: nonstroking_alpha.builder,
			names: WithStateNames({ blend_mode: blend_mode.id, ext_g_state: ext_g_state.id, nonstroking_alpha: nonstroking_alpha.id, normal: normal.id, stroking_alpha: stroking_alpha.id }),
		}
	} else {
		{ builder: x_object.builder, names: NoStateNames }
	}

	masks = if with_masks {
		alpha = KernelObject.add_name(states.builder, Str.to_utf8("Alpha")) ? Object
		g = KernelObject.add_name(alpha.builder, Str.to_utf8("G")) ? Object
		mask = KernelObject.add_name(g.builder, Str.to_utf8("Mask")) ? Object
		s_mask = KernelObject.add_name(mask.builder, Str.to_utf8("SMask")) ? Object
		{
			builder: s_mask.builder,
			names: WithMaskNames({ alpha: alpha.id, g: g.id, mask: mask.id, s_mask: s_mask.id }),
		}
	} else {
		{ builder: states.builder, names: NoMaskNames }
	}

	groups = if with_groups {
		cs = KernelObject.add_name(masks.builder, Str.to_utf8("CS")) ? Object
		group = KernelObject.add_name(cs.builder, Str.to_utf8("Group")) ? Object
		isolated = KernelObject.add_name(group.builder, Str.to_utf8("I")) ? Object
		s = KernelObject.add_name(isolated.builder, Str.to_utf8("S")) ? Object
		transparency = KernelObject.add_name(s.builder, Str.to_utf8("Transparency")) ? Object
		{
			builder: transparency.builder,
			names: WithGroupNames({ cs: cs.id, group: group.id, isolated: isolated.id, s: s.id, transparency: transparency.id }),
		}
	} else {
		{ builder: masks.builder, names: NoGroupNames }
	}

	## The shading, stitching-function, and tiling-pattern names join the
	## table only when the plan contains the corresponding canonical
	## resources, so paint-free plans keep their exact name tables.
	paints = if with_shadings {
		c0 = KernelObject.add_name(groups.builder, Str.to_utf8("C0")) ? Object
		c1 = KernelObject.add_name(c0.builder, Str.to_utf8("C1")) ? Object
		coords = KernelObject.add_name(c1.builder, Str.to_utf8("Coords")) ? Object
		domain = KernelObject.add_name(coords.builder, Str.to_utf8("Domain")) ? Object
		extend = KernelObject.add_name(domain.builder, Str.to_utf8("Extend")) ? Object
		function = KernelObject.add_name(extend.builder, Str.to_utf8("Function")) ? Object
		function_type = KernelObject.add_name(function.builder, Str.to_utf8("FunctionType")) ? Object
		n = KernelObject.add_name(function_type.builder, Str.to_utf8("N")) ? Object
		shading = KernelObject.add_name(n.builder, Str.to_utf8("Shading")) ? Object
		shading_type = KernelObject.add_name(shading.builder, Str.to_utf8("ShadingType")) ? Object
		{
			builder: shading_type.builder,
			names: WithPaintNames({ c0: c0.id, c1: c1.id, coords: coords.id, domain: domain.id, extend: extend.id, function: function.id, function_type: function_type.id, n: n.id, shading: shading.id, shading_type: shading_type.id }),
		}
	} else {
		{ builder: groups.builder, names: NoPaintNames }
	}

	stitches = if with_stitch {
		bounds = KernelObject.add_name(paints.builder, Str.to_utf8("Bounds")) ? Object
		encode = KernelObject.add_name(bounds.builder, Str.to_utf8("Encode")) ? Object
		functions = KernelObject.add_name(encode.builder, Str.to_utf8("Functions")) ? Object
		{
			builder: functions.builder,
			names: WithStitchNames({ bounds: bounds.id, encode: encode.id, functions: functions.id }),
		}
	} else {
		{ builder: paints.builder, names: NoStitchNames }
	}

	patterns = if with_patterns {
		paint_type = KernelObject.add_name(stitches.builder, Str.to_utf8("PaintType")) ? Object
		pattern = KernelObject.add_name(paint_type.builder, Str.to_utf8("Pattern")) ? Object
		pattern_type = KernelObject.add_name(pattern.builder, Str.to_utf8("PatternType")) ? Object
		tiling_type = KernelObject.add_name(pattern_type.builder, Str.to_utf8("TilingType")) ? Object
		x_step = KernelObject.add_name(tiling_type.builder, Str.to_utf8("XStep")) ? Object
		y_step = KernelObject.add_name(x_step.builder, Str.to_utf8("YStep")) ? Object
		{
			builder: y_step.builder,
			names: WithPatternKeyNames({ paint_type: paint_type.id, pattern: pattern.id, pattern_type: pattern_type.id, tiling_type: tiling_type.id, x_step: x_step.id, y_step: y_step.id }),
		}
	} else {
		{ builder: stitches.builder, names: NoPatternKeyNames }
	}

	Ok({
		builder: patterns.builder,
		names: {
			b_box: b_box.id,
			color_space: color_space.id,
			font: font.id,
			form: form.id,
			form_type: form_type.id,
			group_names: groups.names,
			mask_names: masks.names,
			matrix: matrix.id,
			paint_names: paints.names,
			pattern_key_names: patterns.names,
			resources: resources.id,
			state_names: states.names,
			stitch_names: stitches.names,
			subtype: subtype.id,
			type_name: type_name.id,
			x_object: x_object.id,
		},
	})
}

add_resource_names : KernelObject.Builder, U64, U64, U64, U64, U64, U64, U64 -> Try({ builder : KernelObject.Builder, names : ResourceNames }, KernelFormStructure.Error)
add_resource_names = |builder, color_count, image_count, font_count, form_count, state_count, shading_count, pattern_count| {
	color_names = add_indexed_names(builder, "CS", color_count)?
	image_names = add_indexed_names(color_names.builder, "Im", image_count)?
	font_names = add_indexed_names(image_names.builder, "F", font_count)?
	form_names = add_indexed_names(font_names.builder, "XO", form_count)?
	state_names = add_indexed_names(form_names.builder, "GS", state_count)?
	shading_names = add_indexed_names(state_names.builder, "Sh", shading_count)?
	pattern_names = add_indexed_names(shading_names.builder, "Pt", pattern_count)?
	Ok({
		builder: pattern_names.builder,
		names: {
			color_spaces: color_names.ids,
			fonts: font_names.ids,
			forms: form_names.ids,
			images: image_names.ids,
			patterns: pattern_names.ids,
			shadings: shading_names.ids,
			states: state_names.ids,
		},
	})
}

add_indexed_names : KernelObject.Builder, Str, U64 -> Try({ builder : KernelObject.Builder, ids : List(KernelObject.NameId) }, KernelFormStructure.Error)
add_indexed_names = |builder, prefix, count| {
	var $builder = builder
	var $ids = List.with_capacity(count)
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		match KernelObject.add_name($builder, KernelResourceName.bytes(prefix, $index)) {
			Err(error) => {
				$failure = Failed(Object(error))
			}
			Ok(name) => {
				$builder = name.builder
				$ids = $ids.append(name.id)
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({ builder: $builder, ids: $ids })
	}
}

## One exact direct resource dictionary: only the kinds a stream directly uses
## appear, each subdictionary holds exactly the stream's direct entries, and
## keys are already in canonical ascending order.
add_resource_dictionary : KernelObject.Builder, Names, ResourceNames, KernelForm.DictionaryPlan, KernelObjectPlan.Plan, KernelFormObjects.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId, references : U64 }, KernelFormStructure.Error)
add_resource_dictionary = |builder, names, resource_names, dictionary, base, objects| {
	var $builder = builder
	var $entries = []
	var $references = 0

	if dictionary.color_spaces.len() > 0 {
		collected = add_reference_entries($builder, resource_names.color_spaces, dictionary.color_spaces, color_space_targets(base, dictionary.color_spaces))?
		$builder = collected.builder
		value = KernelObject.add_dictionary($builder, collected.entries) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: names.color_space, value: value.id })
		$references = $references + collected.entries.len()
	}
	if dictionary.ext_g_states.len() > 0 {
		state_names = match names.state_names {
			WithStateNames(state) => state
			NoStateNames => {
				crash "graphics state emitted without its planned names"
			}
		}
		collected = add_reference_entries($builder, resource_names.states, dictionary.ext_g_states, state_targets(objects, dictionary.ext_g_states))?
		$builder = collected.builder
		value = KernelObject.add_dictionary($builder, collected.entries) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: state_names.ext_g_state, value: value.id })
		$references = $references + collected.entries.len()
	}
	if dictionary.fonts.len() > 0 {
		collected = add_reference_entries($builder, resource_names.fonts, dictionary.fonts, font_targets(objects, dictionary.fonts))?
		$builder = collected.builder
		value = KernelObject.add_dictionary($builder, collected.entries) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: names.font, value: value.id })
		$references = $references + collected.entries.len()
	}
	if dictionary.patterns.len() > 0 {
		pattern_key_names = match names.pattern_key_names {
			WithPatternKeyNames(bundle) => bundle
			NoPatternKeyNames => {
				crash "pattern dictionary emitted without its planned names"
			}
		}
		collected = add_reference_entries($builder, resource_names.patterns, dictionary.patterns, pattern_targets(objects, dictionary.patterns))?
		$builder = collected.builder
		value = KernelObject.add_dictionary($builder, collected.entries) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: pattern_key_names.pattern, value: value.id })
		$references = $references + collected.entries.len()
	}
	if dictionary.shadings.len() > 0 {
		paint_names = match names.paint_names {
			WithPaintNames(bundle) => bundle
			NoPaintNames => {
				crash "shading dictionary emitted without its planned names"
			}
		}
		collected = add_reference_entries($builder, resource_names.shadings, dictionary.shadings, shading_targets(objects, dictionary.shadings))?
		$builder = collected.builder
		value = KernelObject.add_dictionary($builder, collected.entries) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: paint_names.shading, value: value.id })
		$references = $references + collected.entries.len()
	}
	if dictionary.images.len() > 0 or dictionary.forms.len() > 0 {
		image_entries = add_reference_entries($builder, resource_names.images, dictionary.images, image_targets(base, dictionary.images))?
		$builder = image_entries.builder
		form_entries = add_reference_entries($builder, resource_names.forms, dictionary.forms, form_targets(objects, dictionary.forms))?
		$builder = form_entries.builder
		value = KernelObject.add_dictionary($builder, image_entries.entries.concat(form_entries.entries)) ? Object
		$builder = value.builder
		$entries = $entries.append({ key: names.x_object, value: value.id })
		$references = $references + image_entries.entries.len() + form_entries.entries.len()
	}

	resources = KernelObject.add_dictionary($builder, $entries) ? Object
	Ok({ builder: resources.builder, id: resources.id, references: $references })
}

color_space_targets : KernelObjectPlan.Plan, List(U64) -> List(KernelObject.ObjectId)
color_space_targets = |base, ordinals| {
	planned = KernelObjectPlan.Plan.color_spaces(base)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)))
		$index = $index + 1
	}
	$object_ids
}

image_targets : KernelObjectPlan.Plan, List(U64) -> List(KernelObject.ObjectId)
image_targets = |base, ordinals| {
	planned = KernelObjectPlan.Plan.images(base)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).image.stream)
		$index = $index + 1
	}
	$object_ids
}

font_targets : KernelFormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
font_targets = |objects, ordinals| {
	planned = KernelFormObjects.Plan.fonts(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).type0)
		$index = $index + 1
	}
	$object_ids
}

state_targets : KernelFormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
state_targets = |objects, ordinals| {
	planned = KernelFormObjects.Plan.states(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)))
		$index = $index + 1
	}
	$object_ids
}

pattern_targets : KernelFormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
pattern_targets = |objects, ordinals| {
	planned = KernelFormObjects.Plan.patterns(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).stream)
		$index = $index + 1
	}
	$object_ids
}

shading_targets : KernelFormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
shading_targets = |objects, ordinals| {
	planned = KernelFormObjects.Plan.shadings(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)))
		$index = $index + 1
	}
	$object_ids
}

form_targets : KernelFormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
form_targets = |objects, ordinals| {
	planned = KernelFormObjects.Plan.forms(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).stream)
		$index = $index + 1
	}
	$object_ids
}

add_reference_entries : KernelObject.Builder, List(KernelObject.NameId), List(U64), List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelFormStructure.Error)
add_reference_entries = |builder, names, ordinals, object_ids| {
	var $builder = builder
	var $entries = List.with_capacity(ordinals.len())
	var $index = 0
	var $failure = NoFailure
	while $index < ordinals.len() and $failure == NoFailure {
		match KernelObject.add_reference($builder, list_at(object_ids, $index)) {
			Err(error) => {
				$failure = Failed(Object(error))
			}
			Ok(reference) => {
				$builder = reference.builder
				$entries = $entries.append({ key: list_at(names, list_at(ordinals, $index)), value: reference.id })
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({ builder: $builder, entries: $entries })
	}
}

add_form_object : KernelObject.Builder, Names, ResourceNames, KernelForm.DictionaryPlan, Layout.Rect, List(U8), KernelObjectPlan.Plan, KernelFormObjects.Plan, KernelFormObjects.StreamObjects, GroupValue -> Try({ builder : KernelObject.Builder, references : U64 }, KernelFormStructure.Error)
add_form_object = |builder, names, resource_names, dictionary, bbox, bytes, base, objects, planned, group| {
	resources = add_resource_dictionary(builder, names, resource_names, dictionary, base, objects)?
	b_box = add_rect_value(resources.builder, bbox)?
	form_type = KernelObject.add_integer(b_box.builder, 1) ? Object
	matrix = add_identity_matrix(form_type.builder)?
	subtype = KernelObject.add_name_value(matrix.builder, names.form) ? Object
	type_value = KernelObject.add_name_value(subtype.builder, names.x_object) ? Object
	payload = KernelObject.add_payload(type_value.builder, bytes, Generated) ? Object
	entries = match group {
		NoGroupValue => [
			{ key: names.b_box, value: b_box.id },
			{ key: names.form_type, value: form_type.id },
			{ key: names.matrix, value: matrix.id },
			{ key: names.resources, value: resources.id },
			{ key: names.subtype, value: subtype.id },
			{ key: names.type_name, value: type_value.id },
		]
		GroupValue(group_value) => [
			{ key: names.b_box, value: b_box.id },
			{ key: names.form_type, value: form_type.id },
			{
				key: match names.group_names {
					WithGroupNames(bundle) => bundle.group
					NoGroupNames => {
						crash "isolated form emitted without its planned names"
					}
				},
				value: group_value,
			},
			{ key: names.matrix, value: matrix.id },
			{ key: names.resources, value: resources.id },
			{ key: names.subtype, value: subtype.id },
			{ key: names.type_name, value: type_value.id },
		]
	}
	stream = KernelObject.add_stream_object(
		payload.builder,
		entries,
		Deflate,
		payload.id,
	) ? Object
	ensure_object(stream.id, planned.stream)?
	ensure_object(stream.length_object, planned.length)?
	Ok({ builder: stream.builder, references: resources.references })
}

GroupValue := [GroupValue(KernelObject.ValueId), NoGroupValue]

## The shared page transparency group: `<< /CS ... /S /Transparency >>`. The
## isolation and knockout keys are ignored on a page group (ISO 32000-2,
## 11.4.7), so the canonical page group omits them.
add_page_group_value : KernelObject.Builder, Names, KernelForm.Plan, KernelObjectPlan.Plan, List(Bool) -> Try({ builder : KernelObject.Builder, value : GroupValue }, KernelFormStructure.Error)
add_page_group_value = |builder, names, forms, base, page_transparency| {
	var $needed = Bool.False
	var $page = 0
	while $page < page_transparency.len() {
		if list_at(page_transparency, $page) {
			$needed = Bool.True
		}
		$page = $page + 1
	}
	if !$needed {
		return Ok({ builder, value: NoGroupValue })
	}
	match KernelForm.Plan.blending(forms) {
		NoBlending => Ok({ builder, value: NoGroupValue })
		Blending(ordinal) => {
			group_names = match names.group_names {
				WithGroupNames(group) => group
				NoGroupNames => {
					crash "page transparency group emitted without its planned names"
				}
			}
			space = KernelObject.add_reference(builder, list_at(KernelObjectPlan.Plan.color_spaces(base), ordinal)) ? Object
			kind = KernelObject.add_name_value(space.builder, group_names.transparency) ? Object
			value = KernelObject.add_dictionary(
				kind.builder,
				[
					{ key: group_names.cs, value: space.id },
					{ key: group_names.s, value: kind.id },
				],
			) ? Object
			Ok({ builder: value.builder, value: GroupValue(value.id) })
		}
	}
}

## The shared isolated form transparency group:
## `<< /CS ... /I true /S /Transparency >>`. Knockout stays absent (false).
add_isolated_group_value : KernelObject.Builder, Names, KernelForm.Plan, KernelObjectPlan.Plan, List(Bool) -> Try({ builder : KernelObject.Builder, value : GroupValue }, KernelFormStructure.Error)
add_isolated_group_value = |builder, names, forms, base, form_isolation| {
	var $needed = Bool.False
	var $ordinal = 0
	while $ordinal < form_isolation.len() {
		if list_at(form_isolation, $ordinal) {
			$needed = Bool.True
		}
		$ordinal = $ordinal + 1
	}
	if !$needed {
		return Ok({ builder, value: NoGroupValue })
	}
	match KernelForm.Plan.blending(forms) {
		NoBlending => Ok({ builder, value: NoGroupValue })
		Blending(blending_ordinal) => {
			group_names = match names.group_names {
				WithGroupNames(group) => group
				NoGroupNames => {
					crash "isolated transparency group emitted without its planned names"
				}
			}
			space = KernelObject.add_reference(builder, list_at(KernelObjectPlan.Plan.color_spaces(base), blending_ordinal)) ? Object
			isolated = KernelObject.add_boolean(space.builder, Bool.True) ? Object
			kind = KernelObject.add_name_value(isolated.builder, group_names.transparency) ? Object
			value = KernelObject.add_dictionary(
				kind.builder,
				[
					{ key: group_names.cs, value: space.id },
					{ key: group_names.isolated, value: isolated.id },
					{ key: group_names.s, value: kind.id },
				],
			) ? Object
			Ok({ builder: value.builder, value: GroupValue(value.id) })
		}
	}
}

## One canonical ExtGState object: the exact effective constant alpha at both
## `/ca` and `/CA` under the explicit Normal blend mode, using the identical
## canonical U16-to-decimal mapping content color channels use.
add_state_object : KernelObject.Builder, Names, U64, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelFormStructure.Error)
add_state_object = |builder, names, value, planned| {
	state_names = match names.state_names {
		WithStateNames(state) => state
		NoStateNames => {
			crash "graphics state emitted without its planned names"
		}
	}
	blend = KernelObject.add_name_value(builder, state_names.normal) ? Object
	stroking = add_alpha_value(blend.builder, value)?
	nonstroking = add_alpha_value(stroking.builder, value)?
	kind = KernelObject.add_name_value(nonstroking.builder, state_names.ext_g_state) ? Object
	dictionary = KernelObject.add_dictionary(
		kind.builder,
		[
			{ key: state_names.blend_mode, value: blend.id },
			{ key: state_names.stroking_alpha, value: stroking.id },
			{ key: names.type_name, value: kind.id },
			{ key: state_names.nonstroking_alpha, value: nonstroking.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, planned)?
	Ok(object.builder)
}

## One canonical soft-mask ExtGState object:
## `<< /SMask << /G m 0 R /S /Alpha /Type /Mask >> /Type /ExtGState >>`.
## The mask subtype is always Alpha (luminosity is unrepresentable), the
## transfer function stays absent (the Identity default), and `/G`
## references the canonical mask form's stream object directly — soft masks
## never enter a resource dictionary.
add_mask_state_object : KernelObject.Builder, Names, KernelObject.ObjectId, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelFormStructure.Error)
add_mask_state_object = |builder, names, mask_stream, planned| {
	mask_names = match names.mask_names {
		WithMaskNames(bundle) => bundle
		NoMaskNames => {
			crash "soft-mask state emitted without its planned names"
		}
	}
	state_names = match names.state_names {
		WithStateNames(bundle) => bundle
		NoStateNames => {
			crash "soft-mask state emitted without its planned names"
		}
	}
	group = KernelObject.add_reference(builder, mask_stream) ? Object
	subtype = KernelObject.add_name_value(group.builder, mask_names.alpha) ? Object
	mask_kind = KernelObject.add_name_value(subtype.builder, mask_names.mask) ? Object
	group_names = match names.group_names {
		WithGroupNames(bundle) => bundle
		NoGroupNames => {
			crash "soft-mask state emitted without its planned names"
		}
	}
	mask_dictionary = KernelObject.add_dictionary(
		mask_kind.builder,
		[
			{ key: mask_names.g, value: group.id },
			{ key: group_names.s, value: subtype.id },
			{ key: names.type_name, value: mask_kind.id },
		],
	) ? Object
	kind = KernelObject.add_name_value(mask_dictionary.builder, state_names.ext_g_state) ? Object
	dictionary = KernelObject.add_dictionary(
		kind.builder,
		[
			{ key: mask_names.s_mask, value: mask_dictionary.id },
			{ key: names.type_name, value: kind.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, planned)?
	Ok(object.builder)
}

## One canonical shading dictionary object:
## `<< /ColorSpace c 0 R /Coords [...] /Domain [0 1] /Extend [a b]
## /Function f 0 R /ShadingType 2|3 >>`. The domain is emitted explicitly,
## coordinates use the exact scale-3 layout mapping content geometry uses,
## and the extend flags are always present.
add_shading_object : KernelObject.Builder, Names, KernelForm.ShadingFact, KernelObjectPlan.Plan, KernelFormObjects.Plan, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelFormStructure.Error)
add_shading_object = |builder, names, fact, base, objects, planned| {
	paint_names = match names.paint_names {
		WithPaintNames(bundle) => bundle
		NoPaintNames => {
			crash "shading emitted without its planned names"
		}
	}
	space = KernelObject.add_reference(builder, list_at(KernelObjectPlan.Plan.color_spaces(base), fact.space)) ? Object
	coords = match fact.geometry {
		Axial({ end, start }) => {
			x0 = add_layout(space.builder, start.x)?
			y0 = add_layout(x0.builder, start.y)?
			x1 = add_layout(y0.builder, end.x)?
			y1 = add_layout(x1.builder, end.y)?
			array = KernelObject.add_array(y1.builder, [x0.id, y0.id, x1.id, y1.id]) ? Object
			{ builder: array.builder, id: array.id, shading_type: 2 }
		}
		Radial({ end_center, end_radius, start_center, start_radius }) => {
			x0 = add_layout(space.builder, start_center.x)?
			y0 = add_layout(x0.builder, start_center.y)?
			r0 = add_layout(y0.builder, start_radius)?
			x1 = add_layout(r0.builder, end_center.x)?
			y1 = add_layout(x1.builder, end_center.y)?
			r1 = add_layout(y1.builder, end_radius)?
			array = KernelObject.add_array(r1.builder, [x0.id, y0.id, r0.id, x1.id, y1.id, r1.id]) ? Object
			{ builder: array.builder, id: array.id, shading_type: 3 }
		}
	}
	domain = add_domain_array(coords.builder)?
	extend_start = KernelObject.add_boolean(domain.builder, fact.extend_start) ? Object
	extend_end = KernelObject.add_boolean(extend_start.builder, fact.extend_end) ? Object
	extend = KernelObject.add_array(extend_end.builder, [extend_start.id, extend_end.id]) ? Object
	function = KernelObject.add_reference(extend.builder, list_at(KernelFormObjects.Plan.functions(objects), fact.function)) ? Object
	shading_type = KernelObject.add_integer(function.builder, coords.shading_type) ? Object
	dictionary = KernelObject.add_dictionary(
		shading_type.builder,
		[
			{ key: names.color_space, value: space.id },
			{ key: paint_names.coords, value: coords.id },
			{ key: paint_names.domain, value: domain.id },
			{ key: paint_names.extend, value: extend.id },
			{ key: paint_names.function, value: function.id },
			{ key: paint_names.shading_type, value: shading_type.id },
		],
	) ? Object
	object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
	ensure_object(object.id, planned)?
	Ok(object.builder)
}

## One canonical function dictionary object. A segment function is
## `<< /C0 [...] /C1 [...] /Domain [0 1] /FunctionType 2 /N 1 >>` over the
## exact stop colors; a stitching function is `<< /Bounds [...] /Domain
## [0 1] /Encode [0 1 ...] /FunctionType 3 /Functions [...] >>` whose
## bounds are the exact interior stop offsets under the identical
## `U16`-to-decimal mapping color channels use.
add_function_object : KernelObject.Builder, Names, Scene.ShadingStore, KernelForm.FunctionFact, KernelFormObjects.Plan, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelFormStructure.Error)
add_function_object = |builder, names, shading_store, fact, objects, planned| {
	paint_names = match names.paint_names {
		WithPaintNames(bundle) => bundle
		NoPaintNames => {
			crash "shading function emitted without its planned names"
		}
	}
	match fact {
		SegmentFact({ segment, shading }) => {
			record = list_at(shading_store.shadings, shading)
			first = list_at(shading_store.stops, record.stops.start() + segment)
			second = list_at(shading_store.stops, record.stops.start() + segment + 1)
			c0 = add_channel_array(builder, first.channels)?
			c1 = add_channel_array(c0.builder, second.channels)?
			domain = add_domain_array(c1.builder)?
			function_type = KernelObject.add_integer(domain.builder, 2) ? Object
			exponent = KernelObject.add_integer(function_type.builder, 1) ? Object
			dictionary = KernelObject.add_dictionary(
				exponent.builder,
				[
					{ key: paint_names.c0, value: c0.id },
					{ key: paint_names.c1, value: c1.id },
					{ key: paint_names.domain, value: domain.id },
					{ key: paint_names.function_type, value: function_type.id },
					{ key: paint_names.n, value: exponent.id },
				],
			) ? Object
			object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
			ensure_object(object.id, planned)?
			Ok(object.builder)
		}
		StitchFact({ children, shading }) => {
			stitch_names = match names.stitch_names {
				WithStitchNames(bundle) => bundle
				NoStitchNames => {
					crash "stitching function emitted without its planned names"
				}
			}
			record = list_at(shading_store.shadings, shading)
			var $builder = builder
			var $bound_ids = List.with_capacity(record.stops.length() - 2)
			var $bound = 1
			var $bound_failure = NoFailure
			while $bound < record.stops.length() - 1 and $bound_failure == NoFailure {
				offset = list_at(shading_store.stops, record.stops.start() + $bound).offset
				match add_alpha_value($builder, offset.to_u64()) {
					Err(error) => {
						$bound_failure = Failed(error)
					}
					Ok(added) => {
						$builder = added.builder
						$bound_ids = $bound_ids.append(added.id)
					}
				}
				$bound = $bound + 1
			}
			match $bound_failure {
				Failed(error) => return Err(error)
				NoFailure => {}
			}
			bounds = KernelObject.add_array($builder, $bound_ids) ? Object
			domain = add_domain_array(bounds.builder)?
			zero = KernelObject.add_integer(domain.builder, 0) ? Object
			one = KernelObject.add_integer(zero.builder, 1) ? Object
			var $encode_ids = List.with_capacity(children.len() * 2)
			var $segment_scan = 0
			while $segment_scan < children.len() {
				$encode_ids = $encode_ids.append(zero.id)
				$encode_ids = $encode_ids.append(one.id)
				$segment_scan = $segment_scan + 1
			}
			encode = KernelObject.add_array(one.builder, $encode_ids) ? Object
			function_type = KernelObject.add_integer(encode.builder, 3) ? Object
			var $reference_builder = function_type.builder
			var $child_ids = List.with_capacity(children.len())
			var $child = 0
			var $child_failure = NoFailure
			while $child < children.len() and $child_failure == NoFailure {
				match KernelObject.add_reference($reference_builder, list_at(KernelFormObjects.Plan.functions(objects), list_at(children, $child))) {
					Err(error) => {
						$child_failure = Failed(Object(error))
					}
					Ok(reference) => {
						$reference_builder = reference.builder
						$child_ids = $child_ids.append(reference.id)
					}
				}
				$child = $child + 1
			}
			match $child_failure {
				Failed(error) => return Err(error)
				NoFailure => {}
			}
			functions = KernelObject.add_array($reference_builder, $child_ids) ? Object
			dictionary = KernelObject.add_dictionary(
				functions.builder,
				[
					{ key: stitch_names.bounds, value: bounds.id },
					{ key: paint_names.domain, value: domain.id },
					{ key: stitch_names.encode, value: encode.id },
					{ key: paint_names.function_type, value: function_type.id },
					{ key: stitch_names.functions, value: functions.id },
				],
			) ? Object
			object = KernelObject.add_object(dictionary.builder, dictionary.id) ? Object
			ensure_object(object.id, planned)?
			Ok(object.builder)
		}
	}
}

## One canonical tiling-pattern stream object: the colored constant-spacing
## policy (`/PaintType 1 /TilingType 1`), explicit bounds, steps, and
## matrix, and exactly its direct nested resource dictionary.
add_pattern_object : KernelObject.Builder, Names, ResourceNames, KernelForm.DictionaryPlan, KernelForm.CanonicalPattern, List(U8), KernelObjectPlan.Plan, KernelFormObjects.Plan, KernelFormObjects.StreamObjects -> Try({ builder : KernelObject.Builder, references : U64 }, KernelFormStructure.Error)
add_pattern_object = |builder, names, resource_names, dictionary, cell, bytes, base, objects, planned| {
	pattern_key_names = match names.pattern_key_names {
		WithPatternKeyNames(bundle) => bundle
		NoPatternKeyNames => {
			crash "tiling pattern emitted without its planned names"
		}
	}
	resources = add_resource_dictionary(builder, names, resource_names, dictionary, base, objects)?
	b_box = add_rect_value(resources.builder, cell.bbox)?
	matrix = add_matrix_value(b_box.builder, cell.matrix)?
	paint_type = KernelObject.add_integer(matrix.builder, 1) ? Object
	pattern_type = KernelObject.add_integer(paint_type.builder, 1) ? Object
	tiling_type = KernelObject.add_integer(pattern_type.builder, 1) ? Object
	type_value = KernelObject.add_name_value(tiling_type.builder, pattern_key_names.pattern) ? Object
	x_step = add_layout(type_value.builder, cell.x_step)?
	y_step = add_layout(x_step.builder, cell.y_step)?
	payload = KernelObject.add_payload(y_step.builder, bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(
		payload.builder,
		[
			{ key: names.b_box, value: b_box.id },
			{ key: names.matrix, value: matrix.id },
			{ key: pattern_key_names.paint_type, value: paint_type.id },
			{ key: pattern_key_names.pattern_type, value: pattern_type.id },
			{ key: names.resources, value: resources.id },
			{ key: pattern_key_names.tiling_type, value: tiling_type.id },
			{ key: names.type_name, value: type_value.id },
			{ key: pattern_key_names.x_step, value: x_step.id },
			{ key: pattern_key_names.y_step, value: y_step.id },
		],
		Deflate,
		payload.id,
	) ? Object
	ensure_object(stream.id, planned.stream)?
	ensure_object(stream.length_object, planned.length)?
	Ok({ builder: stream.builder, references: resources.references })
}

## Channel values use the identical `U16`-to-scale-9-decimal mapping the
## content serializer and constant alphas use.
add_channel_array : KernelObject.Builder, Color.Channels -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_channel_array = |builder, channels| match channels {
	Gray(gray) => {
		value = add_alpha_value(builder, gray.to_u64())?
		array = KernelObject.add_array(value.builder, [value.id]) ? Object
		Ok({ builder: array.builder, id: array.id })
	}
	Rgb({ blue, green, red }) => {
		red_value = add_alpha_value(builder, red.to_u64())?
		green_value = add_alpha_value(red_value.builder, green.to_u64())?
		blue_value = add_alpha_value(green_value.builder, blue.to_u64())?
		array = KernelObject.add_array(blue_value.builder, [red_value.id, green_value.id, blue_value.id]) ? Object
		Ok({ builder: array.builder, id: array.id })
	}
}

## The explicit `[0 1]` domain every shading and function declares.
add_domain_array : KernelObject.Builder -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_domain_array = |builder| {
	zero = KernelObject.add_integer(builder, 0) ? Object
	one = KernelObject.add_integer(zero.builder, 1) ? Object
	array = KernelObject.add_array(one.builder, [zero.id, one.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

## A pattern matrix at the exact scale-3 layout mapping `cm` operands use.
add_matrix_value : KernelObject.Builder, Scene.Matrix -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_matrix_value = |builder, matrix| {
	a = add_layout(builder, matrix.a)?
	b = add_layout(a.builder, matrix.b)?
	c = add_layout(b.builder, matrix.c)?
	d = add_layout(c.builder, matrix.d)?
	e = add_layout(d.builder, matrix.e)?
	f = add_layout(e.builder, matrix.f)?
	array = KernelObject.add_array(f.builder, [a.id, b.id, c.id, d.id, e.id, f.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

## `U16` alpha to canonical PDF number: value * 10^9 / 65535 rounded half to
## even at nine decimal places — byte-identical to the channel mapping the
## content serializer uses, so `/ca 0.5000...` agrees with painted channels.
add_alpha_value : KernelObject.Builder, U64 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_alpha_value = |builder, value| {
	numerator = value * 1000000000
	quotient = U64.div_by(numerator, 65535)
	remainder = U64.mod_by(numerator, 65535)
	twice = remainder * 2
	coefficient = if twice > 65535 or (twice == 65535 and U64.mod_by(quotient, 2) == 1) quotient + 1 else quotient
	decimal = match KernelLex.Decimal.from_coefficient(coefficient.to_i64_wrap(), 9) {
		Err(_) => {
			crash "fixed production-visual alpha scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

add_rect_value : KernelObject.Builder, Layout.Rect -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_rect_value = |builder, rect| {
	x0 = add_layout(builder, rect.origin.x)?
	y0 = add_layout(x0.builder, rect.origin.y)?
	x1 = add_layout(y0.builder, Layout.Unit.from_raw(rect.origin.x.raw() + rect.size.width.raw()))?
	y1 = add_layout(x1.builder, Layout.Unit.from_raw(rect.origin.y.raw() + rect.size.height.raw()))?
	array = KernelObject.add_array(y1.builder, [x0.id, y0.id, x1.id, y1.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

## The documented canonical `/Matrix` for this slice: placement transforms are
## entirely placement-side facts, so every form declares the identity matrix.
add_identity_matrix : KernelObject.Builder -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_identity_matrix = |builder| {
	one = KernelObject.add_integer(builder, 1) ? Object
	zero = KernelObject.add_integer(one.builder, 0) ? Object
	array = KernelObject.add_array(zero.builder, [one.id, zero.id, zero.id, one.id, zero.id, zero.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_layout : KernelObject.Builder, Layout.Unit -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelFormStructure.Error)
add_layout = |builder, value| {
	decimal = match KernelLex.Decimal.from_coefficient(value.raw(), 3) {
		Err(_) => {
			crash "fixed production-visual form scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelFormStructure.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

any_flag : List(Bool) -> Bool
any_flag = |flags| {
	var $index = 0
	var $found = Bool.False
	while $index < flags.len() and !$found {
		if list_at(flags, $index) {
			$found = Bool.True
		}
		$index = $index + 1
	}
	$found
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated production-visual form-structure index escaped"
	}
}
