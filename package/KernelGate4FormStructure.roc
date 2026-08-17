import KernelColor
import KernelContent
import KernelFont
import KernelFontPlan
import KernelFontSubset
import KernelForm
import KernelGate2Identity
import KernelGate2Objects
import KernelGate2OutputBound
import KernelGate2PageObjects
import KernelGate2ResourceName
import KernelGate2ResourceObjects
import KernelGate2TaggedObjects
import KernelGate4FormObjects
import KernelImage
import KernelLex
import KernelObject
import KernelPdfFont
import KernelPdfText
import KernelSeal
import KernelStructure
import KernelTagged
import Layout

## Gate 4 object assembly: the Gate 2 tagged prefix, per-page exact direct
## resource dictionaries, the Gate 2 page tree and resource objects, canonical
## Form XObject stream objects with their own exact direct dictionaries, and
## the Type 0 font objects when text is present — sealed into one
## deterministic plan. Every dictionary entry comes from the form plan's
## normalized facts; nothing here re-derives sharing or scans operators.
KernelGate4FormStructure :: [].{
	Error : [
		ArithmeticOverflow,
		Font(KernelPdfFont.Error),
		FontCountMismatch({ fonts : U64, mappings : U64, planned : U64 }),
		FormStreamCountMismatch({ planned : U64, streams : U64 }),
		Identity(KernelGate2Identity.Error),
		Object(KernelObject.Error),
		ObjectCountMismatch({ actual : U64, expected : U64 }),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
		OutputBound(KernelGate2OutputBound.Error),
		Pages(KernelGate2PageObjects.Error),
		Resources(KernelGate2ResourceObjects.Error),
		Seal(KernelSeal.Error),
		TaggedObjects(KernelGate2TaggedObjects.Error),
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
		dictionary_references : U64,
		font_program_bytes : U64,
		fonts : U64,
		form_objects : U64,
		form_stream_bytes : U64,
		isolated_form_groups : U64,
		objects : U64,
		pages : KernelGate2PageObjects.Work,
		resources : KernelGate2ResourceObjects.Work,
		state_objects : U64,
		tagged_objects : KernelGate2TaggedObjects.Work,
		transparency_page_groups : U64,
	}

	Plan :: { structure : KernelStructure.Plan, work : Work }.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelGate4FormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(FontInput), text : KernelPdfText.ScenePlan })], Limits -> Try(Plan, Error)
		build = |tagged, colors, images, content, forms, objects, text, limits| build_plan(tagged, colors, images, content, forms, objects, text, limits)

		structure : Plan -> KernelStructure.Plan
		structure = |plan| plan.structure

		work : Plan -> Work
		work = |plan| plan.work
	}
}

StateNames := { blend_mode : KernelObject.NameId, ext_g_state : KernelObject.NameId, nonstroking_alpha : KernelObject.NameId, normal : KernelObject.NameId, stroking_alpha : KernelObject.NameId }

MaskNames := { alpha : KernelObject.NameId, g : KernelObject.NameId, mask : KernelObject.NameId, s_mask : KernelObject.NameId }

GroupNames := { cs : KernelObject.NameId, group : KernelObject.NameId, isolated : KernelObject.NameId, s : KernelObject.NameId, transparency : KernelObject.NameId }

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
	resources : KernelObject.NameId,
	state_names : [NoStateNames, WithStateNames(StateNames)],
	subtype : KernelObject.NameId,
	type_name : KernelObject.NameId,
	x_object : KernelObject.NameId,
}

ResourceNames := {
	color_spaces : List(KernelObject.NameId),
	fonts : List(KernelObject.NameId),
	forms : List(KernelObject.NameId),
	images : List(KernelObject.NameId),
	states : List(KernelObject.NameId),
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelContent.Plan, KernelForm.Plan, KernelGate4FormObjects.Plan, [NoTextObjects, WithTextObjects({ fonts : List(KernelGate4FormStructure.FontInput), text : KernelPdfText.ScenePlan })], KernelGate4FormStructure.Limits -> Try(KernelGate4FormStructure.Plan, KernelGate4FormStructure.Error)
build_plan = |tagged, colors, images, content, forms, objects, text, limits| {
	base = KernelGate4FormObjects.Plan.base(objects)
	planned_fonts = KernelGate4FormObjects.Plan.fonts(objects)
	canonical_forms = KernelForm.Plan.canonical_form_count(forms)
	if KernelContent.Plan.form_stream_count(content) != canonical_forms {
		return Err(FormStreamCountMismatch({ planned: canonical_forms, streams: KernelContent.Plan.form_stream_count(content) }))
	}
	match text {
		NoTextObjects => if planned_fonts.len() != 0 {
			return Err(FontCountMismatch({ fonts: 0, mappings: 0, planned: planned_fonts.len() }))
		} else {
			{}
		}
		WithTextObjects(input) => {
			mappings = KernelPdfText.ScenePlan.mappings(input.text)
			if input.fonts.len() == 0 or input.fonts.len() != mappings.len() or input.fonts.len() != planned_fonts.len() {
				return Err(FontCountMismatch({ fonts: input.fonts.len(), mappings: mappings.len(), planned: planned_fonts.len() }))
			}
			{}
		}
	}

	prefix = KernelGate2TaggedObjects.Plan.build(tagged, base, limits.object_limits) ? TaggedObjects

	## Deterministic resource names, created once for the canonical
	## (deduplicated) leaf and form counts, then one exact direct dictionary
	## value per page.
	leaf_counts = KernelForm.Plan.canonical_leaf_counts(forms)
	canonical_states = KernelForm.Plan.canonical_state_count(forms)
	page_transparency = KernelForm.Plan.page_transparency(forms)
	form_isolation = KernelForm.Plan.form_isolation(forms)
	with_groups = any_flag(page_transparency) or any_flag(form_isolation)
	with_masks = KernelForm.Plan.work(forms).canonical_mask_states > 0
	named = add_names(KernelGate2TaggedObjects.Plan.builder(prefix), canonical_states > 0, with_groups, with_masks)?
	resource_names = add_resource_names(named.builder, leaf_counts.color_spaces, leaf_counts.images, planned_fonts.len(), canonical_forms, canonical_states)?
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
	pages = match group_plan.value {
		NoGroupValue => KernelGate2PageObjects.Plan.build_with_page_resources($builder, tagged, content, base, $page_values, $references) ? Pages
		GroupValue(group_value) => {
			var $page_groups = List.with_capacity(page_count)
			var $group_page = 0
			while $group_page < page_count {
				entry = if list_at(page_transparency, $group_page) {
					$transparency_page_groups = $transparency_page_groups + 1
					WithGroup(group_value)
				} else {
					NoGroup
				}
				$page_groups = $page_groups.append(entry)
				$group_page = $group_page + 1
			}
			KernelGate2PageObjects.Plan.build_with_page_groups($builder, tagged, content, base, $page_values, $references, $page_groups) ? Pages
		}
	}
	var $image_planes = List.with_capacity(leaf_counts.images)
	var $plane_ordinal = 0
	while $plane_ordinal < leaf_counts.images {
		$image_planes = $image_planes.append(KernelForm.Plan.canonical_image_planes(forms, $plane_ordinal))
		$plane_ordinal = $plane_ordinal + 1
	}
	resources = KernelGate2ResourceObjects.Plan.build_canonical(
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
	var $form_builder = KernelGate2ResourceObjects.Plan.builder(resources)
	isolated_group_plan = add_isolated_group_value($form_builder, named.names, forms, base, form_isolation)?
	$form_builder = isolated_group_plan.builder
	var $isolated_form_groups = 0
	var $form_bytes = 0
	var $ordinal = 0
	while $ordinal < canonical_forms and $failure == NoFailure {
		canonical = KernelForm.Plan.canonical_form(forms, $ordinal)
		stream = KernelContent.Plan.form_stream(content, $ordinal)
		planned = list_at(KernelGate4FormObjects.Plan.forms(objects), $ordinal)
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
		planned_state = list_at(KernelGate4FormObjects.Plan.states(objects), $state_ordinal)
		state_result = match KernelForm.Plan.state_fact(forms, $state_ordinal) {
			Alpha(value) => add_state_object($state_builder, named.names, value, planned_state)
			Mask(mask_ordinal) => add_mask_state_object($state_builder, named.names, list_at(KernelGate4FormObjects.Plan.forms(objects), mask_ordinal).stream, planned_state)
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

	## Type 0 font objects land exactly at their planned identities.
	var $font_builder = $state_builder
	var $font_program_bytes = 0
	match text {
		NoTextObjects => {}
		WithTextObjects(input) => {
			mappings = KernelPdfText.ScenePlan.mappings(input.text)
			var $font_index = 0
			while $font_index < input.fonts.len() and $failure == NoFailure {
				font_input = list_at(input.fonts, $font_index)
				match KernelPdfFont.Plan.build(
					$font_builder,
					font_input.font,
					font_input.plan,
					font_input.subset,
					font_input.descriptor,
					list_at(mappings, $font_index),
					limits.font_limits,
				) {
					Err(error) => {
						$failure = Failed(Font(error))
					}
					Ok(font) => {
						emitted = KernelPdfFont.Plan.objects(font)
						planned = list_at(planned_fonts, $font_index)
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
				$font_index = $font_index + 1
			}
		}
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	expected = KernelGate4FormObjects.Plan.object_count(objects)
	if $font_builder.store.objects.len() != expected {
		return Err(ObjectCountMismatch({ actual: $font_builder.store.objects.len(), expected }))
	}
	sealed = KernelSeal.seal($font_builder) ? Seal
	identity = KernelGate2Identity.digest(sealed) ? Identity
	bound = KernelGate2OutputBound.calculate(sealed, KernelGate4FormObjects.Plan.xref(objects)) ? OutputBound
	structure = KernelStructure.Plan.from_sealed({
		identity: NormalizedPlanDigest(identity.digest),
		output_bound: KernelGate2OutputBound.Bound.bytes(bound),
		page_count,
		root: KernelGate2Objects.Plan.catalog(base),
		sealed,
		tree_nodes: KernelGate2Objects.Plan.page_tree(base).len(),
		xref_object: KernelGate4FormObjects.Plan.xref(objects),
	})
	Ok(
		KernelGate4FormStructure.Plan.{
			structure,
			work: {
				content_bytes: KernelContent.Plan.work(content).bytes_emitted,
				dictionary_references: $references,
				font_program_bytes: $font_program_bytes,
				fonts: planned_fonts.len(),
				form_objects: KernelGate4FormObjects.Plan.work(objects).form_objects,
				form_stream_bytes: $form_bytes,
				isolated_form_groups: $isolated_form_groups,
				objects: expected,
				pages: KernelGate2PageObjects.Plan.work(pages),
				resources: KernelGate2ResourceObjects.Plan.work(resources),
				state_objects: canonical_states,
				tagged_objects: KernelGate2TaggedObjects.Plan.work(prefix),
				transparency_page_groups: $transparency_page_groups,
			},
		},
	)
}

add_names : KernelObject.Builder, Bool, Bool, Bool -> Try({ builder : KernelObject.Builder, names : Names }, KernelGate4FormStructure.Error)
add_names = |builder, with_states, with_groups, with_masks| {
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
		{ builder: states.builder, names: NoGroupNames }
	}

	Ok({
		builder: groups.builder,
		names: {
			b_box: b_box.id,
			color_space: color_space.id,
			font: font.id,
			form: form.id,
			form_type: form_type.id,
			group_names: groups.names,
			mask_names: masks.names,
			matrix: matrix.id,
			resources: resources.id,
			state_names: states.names,
			subtype: subtype.id,
			type_name: type_name.id,
			x_object: x_object.id,
		},
	})
}

add_resource_names : KernelObject.Builder, U64, U64, U64, U64, U64 -> Try({ builder : KernelObject.Builder, names : ResourceNames }, KernelGate4FormStructure.Error)
add_resource_names = |builder, color_count, image_count, font_count, form_count, state_count| {
	color_names = add_indexed_names(builder, "CS", color_count)?
	image_names = add_indexed_names(color_names.builder, "Im", image_count)?
	font_names = add_indexed_names(image_names.builder, "F", font_count)?
	form_names = add_indexed_names(font_names.builder, "XO", form_count)?
	state_names = add_indexed_names(form_names.builder, "GS", state_count)?
	Ok({
		builder: state_names.builder,
		names: {
			color_spaces: color_names.ids,
			fonts: font_names.ids,
			forms: form_names.ids,
			images: image_names.ids,
			states: state_names.ids,
		},
	})
}

add_indexed_names : KernelObject.Builder, Str, U64 -> Try({ builder : KernelObject.Builder, ids : List(KernelObject.NameId) }, KernelGate4FormStructure.Error)
add_indexed_names = |builder, prefix, count| {
	var $builder = builder
	var $ids = List.with_capacity(count)
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		match KernelObject.add_name($builder, KernelGate2ResourceName.bytes(prefix, $index)) {
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
add_resource_dictionary : KernelObject.Builder, Names, ResourceNames, KernelForm.DictionaryPlan, KernelGate2Objects.Plan, KernelGate4FormObjects.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId, references : U64 }, KernelGate4FormStructure.Error)
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

color_space_targets : KernelGate2Objects.Plan, List(U64) -> List(KernelObject.ObjectId)
color_space_targets = |base, ordinals| {
	planned = KernelGate2Objects.Plan.color_spaces(base)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)))
		$index = $index + 1
	}
	$object_ids
}

image_targets : KernelGate2Objects.Plan, List(U64) -> List(KernelObject.ObjectId)
image_targets = |base, ordinals| {
	planned = KernelGate2Objects.Plan.images(base)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).image.stream)
		$index = $index + 1
	}
	$object_ids
}

font_targets : KernelGate4FormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
font_targets = |objects, ordinals| {
	planned = KernelGate4FormObjects.Plan.fonts(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).type0)
		$index = $index + 1
	}
	$object_ids
}

state_targets : KernelGate4FormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
state_targets = |objects, ordinals| {
	planned = KernelGate4FormObjects.Plan.states(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)))
		$index = $index + 1
	}
	$object_ids
}

form_targets : KernelGate4FormObjects.Plan, List(U64) -> List(KernelObject.ObjectId)
form_targets = |objects, ordinals| {
	planned = KernelGate4FormObjects.Plan.forms(objects)
	var $object_ids = List.with_capacity(ordinals.len())
	var $index = 0
	while $index < ordinals.len() {
		$object_ids = $object_ids.append(list_at(planned, list_at(ordinals, $index)).stream)
		$index = $index + 1
	}
	$object_ids
}

add_reference_entries : KernelObject.Builder, List(KernelObject.NameId), List(U64), List(KernelObject.ObjectId) -> Try({ builder : KernelObject.Builder, entries : List(KernelObject.DictionaryEntry) }, KernelGate4FormStructure.Error)
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

add_form_object : KernelObject.Builder, Names, ResourceNames, KernelForm.DictionaryPlan, Layout.Rect, List(U8), KernelGate2Objects.Plan, KernelGate4FormObjects.Plan, KernelGate4FormObjects.StreamObjects, GroupValue -> Try({ builder : KernelObject.Builder, references : U64 }, KernelGate4FormStructure.Error)
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
add_page_group_value : KernelObject.Builder, Names, KernelForm.Plan, KernelGate2Objects.Plan, List(Bool) -> Try({ builder : KernelObject.Builder, value : GroupValue }, KernelGate4FormStructure.Error)
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
			space = KernelObject.add_reference(builder, list_at(KernelGate2Objects.Plan.color_spaces(base), ordinal)) ? Object
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
add_isolated_group_value : KernelObject.Builder, Names, KernelForm.Plan, KernelGate2Objects.Plan, List(Bool) -> Try({ builder : KernelObject.Builder, value : GroupValue }, KernelGate4FormStructure.Error)
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
			space = KernelObject.add_reference(builder, list_at(KernelGate2Objects.Plan.color_spaces(base), blending_ordinal)) ? Object
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
add_state_object : KernelObject.Builder, Names, U64, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelGate4FormStructure.Error)
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
add_mask_state_object : KernelObject.Builder, Names, KernelObject.ObjectId, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelGate4FormStructure.Error)
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

## `U16` alpha to canonical PDF number: value * 10^9 / 65535 rounded half to
## even at nine decimal places — byte-identical to the channel mapping the
## content serializer uses, so `/ca 0.5000...` agrees with painted channels.
add_alpha_value : KernelObject.Builder, U64 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate4FormStructure.Error)
add_alpha_value = |builder, value| {
	numerator = value * 1000000000
	quotient = U64.div_by(numerator, 65535)
	remainder = U64.mod_by(numerator, 65535)
	twice = remainder * 2
	coefficient = if twice > 65535 or (twice == 65535 and U64.mod_by(quotient, 2) == 1) quotient + 1 else quotient
	decimal = match KernelLex.Decimal.from_coefficient(coefficient.to_i64_wrap(), 9) {
		Err(_) => {
			crash "fixed Gate 4 alpha scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

add_rect_value : KernelObject.Builder, Layout.Rect -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate4FormStructure.Error)
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
add_identity_matrix : KernelObject.Builder -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate4FormStructure.Error)
add_identity_matrix = |builder| {
	one = KernelObject.add_integer(builder, 1) ? Object
	zero = KernelObject.add_integer(one.builder, 0) ? Object
	array = KernelObject.add_array(zero.builder, [one.id, zero.id, zero.id, one.id, zero.id, zero.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_layout : KernelObject.Builder, Layout.Unit -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate4FormStructure.Error)
add_layout = |builder, value| {
	decimal = match KernelLex.Decimal.from_coefficient(value.raw(), 3) {
		Err(_) => {
			crash "fixed Gate 4 form scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelGate4FormStructure.Error)
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
		crash "validated Gate 4 form-structure index escaped"
	}
}
