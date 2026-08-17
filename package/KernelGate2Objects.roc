import Color
import Image
import KernelBalanced
import KernelColor
import KernelContent
import KernelImage
import KernelObject
import KernelResourceUse
import KernelTagged
import Semantics

KernelGate2Objects :: [].{
	Dimension : [Objects, Pages]
	Error : [
		ArithmeticOverflow,
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		PageCountZero,
		ResourceCountMismatch({ actual : U64, expected : U64, kind : [ColorSpaces, Images] }),
		Shape(KernelBalanced.Error),
	]

	Limits :: { max_objects : U64, max_pages : U64 }.{
		make : { max_objects : U64, max_pages : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	## Canonical leaf-object counts from the Gate 4 resource plan: one object
	## family entry per canonical (deduplicated) leaf, with per-canonical-image
	## alpha soft-mask flags.
	LeafObjectCounts : { color_spaces : U64, image_alpha : List(Bool), profiles : U64 }

	StreamObjects : { length : KernelObject.ObjectId, stream : KernelObject.ObjectId }
	PageObjects : { content : StreamObjects, page : KernelObject.ObjectId }
	ProfileObjects : { profile : KernelObject.ObjectId, stream : StreamObjects }
	SoftMaskObjects : [HasSoftMask(StreamObjects), NoSoftMask]
	ImageObjects : { image : StreamObjects, soft_mask : SoftMaskObjects }

	Work : {
		color_space_objects : U64,
		contextual_artifact_objects : U64,
		image_objects : U64,
		namespace_objects : U64,
		object_identities : U64,
		page_objects : U64,
		page_tree_objects : U64,
		profile_objects : U64,
		soft_mask_objects : U64,
		structure_objects : U64,
	}

	Plan :: {
		catalog : KernelObject.ObjectId,
		color_spaces : List(KernelObject.ObjectId),
		contextual_artifacts : List(KernelObject.ObjectId),
		images : List(ImageObjects),
		namespaces : List(KernelObject.ObjectId),
		pages : List(PageObjects),
		page_tree : List(KernelObject.ObjectId),
		page_tree_shape : KernelBalanced.Shape,
		parent_tree : KernelObject.ObjectId,
		profiles : List(ProfileObjects),
		struct_tree_root : KernelObject.ObjectId,
		structure_elements : List(KernelObject.ObjectId),
		work : Work,
		xref : KernelObject.ObjectId,
	}.{
		build : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.Plan, KernelContent.Plan, Limits -> Try(Plan, Error)
		build = |tagged, colors, images, resource_use, content, limits| build_plan(tagged, colors, images, resource_use, content, limits)

		build_with_text : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.TextPlan, KernelContent.Plan, Limits -> Try(Plan, Error)
		build_with_text = |tagged, colors, images, resource_use, content, limits| build_text_plan(tagged, colors, images, resource_use, content, limits)

		## The Gate 4 leaf-deduplicated variant: authored stores are still
		## cross-checked against the derived use counts, but object identities
		## are planned for the canonical leaf counts, so each deduplicated
		## profile, color space, and image receives exactly one object.
		build_canonical : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.TextPlan, KernelContent.Plan, LeafObjectCounts, Limits -> Try(Plan, Error)
		build_canonical = |tagged, colors, images, resource_use, content, leaves, limits| build_canonical_plan(tagged, colors, images, resource_use, content, leaves, limits)

		catalog : Plan -> KernelObject.ObjectId
		catalog = |plan| plan.catalog

		color_spaces : Plan -> List(KernelObject.ObjectId)
		color_spaces = |plan| plan.color_spaces

		contextual_artifacts : Plan -> List(KernelObject.ObjectId)
		contextual_artifacts = |plan| plan.contextual_artifacts

		images : Plan -> List(ImageObjects)
		images = |plan| plan.images

		namespaces : Plan -> List(KernelObject.ObjectId)
		namespaces = |plan| plan.namespaces

		object_count : Plan -> U64
		object_count = |plan| plan.work.object_identities

		pages : Plan -> List(PageObjects)
		pages = |plan| plan.pages

		page_tree : Plan -> List(KernelObject.ObjectId)
		page_tree = |plan| plan.page_tree

		page_tree_shape : Plan -> KernelBalanced.Shape
		page_tree_shape = |plan| plan.page_tree_shape

		parent_tree : Plan -> KernelObject.ObjectId
		parent_tree = |plan| plan.parent_tree

		profiles : Plan -> List(ProfileObjects)
		profiles = |plan| plan.profiles

		struct_tree_root : Plan -> KernelObject.ObjectId
		struct_tree_root = |plan| plan.struct_tree_root

		structure_elements : Plan -> List(KernelObject.ObjectId)
		structure_elements = |plan| plan.structure_elements

		work : Plan -> Work
		work = |plan| plan.work

		xref : Plan -> KernelObject.ObjectId
		xref = |plan| plan.xref
	}
}

ObjectCounts := {
	color_spaces : U64,
	contextual_artifacts : U64,
	image_alpha : List(Bool),
	namespaces : U64,
	pages : U64,
	profiles : U64,
	structure_elements : U64,
}

build_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.Plan, KernelContent.Plan, KernelGate2Objects.Limits -> Try(KernelGate2Objects.Plan, KernelGate2Objects.Error)
build_plan = |tagged, colors, images, resource_use, content, limits| {
	semantic_store = KernelTagged.Plan.semantics(tagged)
	color_store = KernelColor.Plan.store(colors)
	image_store = KernelImage.Plan.store(images)
	resource_work = KernelResourceUse.Plan.work(resource_use)
	color_count = color_store.spaces.len()
	image_count = image_store.resources.len()
	if resource_work.color_space_resources != color_count {
		Err(ResourceCountMismatch({ actual: resource_work.color_space_resources, expected: color_count, kind: ColorSpaces }))
	} else if resource_work.image_resources != image_count {
		Err(ResourceCountMismatch({ actual: resource_work.image_resources, expected: image_count, kind: Images }))
	} else if KernelContent.Plan.stream_count(content) != KernelTagged.Plan.scenes(tagged).pages.len() {
		Err(LimitExceeded({ attempted: KernelContent.Plan.stream_count(content), dimension: Pages, limit: KernelTagged.Plan.scenes(tagged).pages.len() }))
	} else {
		alpha = collect_alpha(image_store)
		build_counts(
			{
				color_spaces: color_count,
				contextual_artifacts: semantic_store.contextual_artifacts.len(),
				image_alpha: alpha,
				namespaces: semantic_store.namespaces.len(),
				pages: KernelContent.Plan.stream_count(content),
				profiles: color_store.profiles.len(),
				structure_elements: semantic_store.nodes.len(),
			},
			limits,
		)
	}
}

build_text_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.TextPlan, KernelContent.Plan, KernelGate2Objects.Limits -> Try(KernelGate2Objects.Plan, KernelGate2Objects.Error)
build_text_plan = |tagged, colors, images, resource_use, content, limits| {
	semantic_store = KernelTagged.Plan.semantics(tagged)
	color_store = KernelColor.Plan.store(colors)
	image_store = KernelImage.Plan.store(images)
	resource_work = KernelResourceUse.TextPlan.work(resource_use)
	color_count = color_store.spaces.len()
	image_count = image_store.resources.len()
	if resource_work.color_space_resources != color_count {
		Err(ResourceCountMismatch({ actual: resource_work.color_space_resources, expected: color_count, kind: ColorSpaces }))
	} else if resource_work.image_resources != image_count {
		Err(ResourceCountMismatch({ actual: resource_work.image_resources, expected: image_count, kind: Images }))
	} else if KernelContent.Plan.stream_count(content) != KernelTagged.Plan.scenes(tagged).pages.len() {
		Err(LimitExceeded({ attempted: KernelContent.Plan.stream_count(content), dimension: Pages, limit: KernelTagged.Plan.scenes(tagged).pages.len() }))
	} else {
		alpha = collect_alpha(image_store)
		build_counts(
			{
				color_spaces: color_count,
				contextual_artifacts: semantic_store.contextual_artifacts.len(),
				image_alpha: alpha,
				namespaces: semantic_store.namespaces.len(),
				pages: KernelContent.Plan.stream_count(content),
				profiles: color_store.profiles.len(),
				structure_elements: semantic_store.nodes.len(),
			},
			limits,
		)
	}
}

build_canonical_plan : KernelTagged.Plan, KernelColor.Plan, KernelImage.Plan, KernelResourceUse.TextPlan, KernelContent.Plan, KernelGate2Objects.LeafObjectCounts, KernelGate2Objects.Limits -> Try(KernelGate2Objects.Plan, KernelGate2Objects.Error)
build_canonical_plan = |tagged, colors, images, resource_use, content, leaves, limits| {
	semantic_store = KernelTagged.Plan.semantics(tagged)
	color_store = KernelColor.Plan.store(colors)
	image_store = KernelImage.Plan.store(images)
	resource_work = KernelResourceUse.TextPlan.work(resource_use)
	color_count = color_store.spaces.len()
	image_count = image_store.resources.len()
	if resource_work.color_space_resources != color_count {
		Err(ResourceCountMismatch({ actual: resource_work.color_space_resources, expected: color_count, kind: ColorSpaces }))
	} else if resource_work.image_resources != image_count {
		Err(ResourceCountMismatch({ actual: resource_work.image_resources, expected: image_count, kind: Images }))
	} else if KernelContent.Plan.stream_count(content) != KernelTagged.Plan.scenes(tagged).pages.len() {
		Err(LimitExceeded({ attempted: KernelContent.Plan.stream_count(content), dimension: Pages, limit: KernelTagged.Plan.scenes(tagged).pages.len() }))
	} else {
		build_counts(
			{
				color_spaces: leaves.color_spaces,
				contextual_artifacts: semantic_store.contextual_artifacts.len(),
				image_alpha: leaves.image_alpha,
				namespaces: semantic_store.namespaces.len(),
				pages: KernelContent.Plan.stream_count(content),
				profiles: leaves.profiles,
				structure_elements: semantic_store.nodes.len(),
			},
			limits,
		)
	}
}

collect_alpha : Image.Store -> List(Bool)
collect_alpha = |store| {
	var $alpha = List.with_capacity(store.resources.len())
	var $index = 0
	while $index < store.resources.len() {
		resource = list_at(store.resources, $index)
		has_alpha = match resource.payload {
			Jpeg(_) => False
			Raster(raster) => match raster.alpha {
				NoAlpha => False
				PackedAlpha(_) => True
			}
		}
		$alpha = $alpha.append(has_alpha)
		$index = $index + 1
	}
	$alpha
}

build_counts : ObjectCounts, KernelGate2Objects.Limits -> Try(KernelGate2Objects.Plan, KernelGate2Objects.Error)
build_counts = |counts, limits| {
	if counts.pages == 0 {
		Err(PageCountZero)
	} else if counts.pages > limits.max_pages {
		Err(LimitExceeded({ attempted: counts.pages, dimension: Pages, limit: limits.max_pages }))
	} else {
		shape = KernelBalanced.Shape.build(counts.pages, limits.max_pages) ? Shape
		page_tree_count = KernelBalanced.Shape.node_count(shape)
		alpha_count = count_true(counts.image_alpha)
		fixed_count = checked_add(3, counts.namespaces)?
		structure_end = checked_add(checked_add(fixed_count, counts.structure_elements)?, counts.contextual_artifacts)?
		page_tree_end = checked_add(structure_end, page_tree_count)?
		page_object_count = checked_times(counts.pages, 3)?
		pages_end = checked_add(page_tree_end, page_object_count)?
		profile_object_count = checked_times(counts.profiles, 2)?
		profiles_end = checked_add(pages_end, profile_object_count)?
		colors_end = checked_add(profiles_end, counts.color_spaces)?
		base_image_objects = checked_times(counts.image_alpha.len(), 2)?
		soft_mask_objects = checked_times(alpha_count, 2)?
		image_object_count = checked_add(base_image_objects, soft_mask_objects)?
		object_count = checked_add(colors_end, image_object_count)?
		if object_count > limits.max_objects {
			Err(LimitExceeded({ attempted: object_count, dimension: Objects, limit: limits.max_objects }))
		} else {
			catalog = object_id(1)
			struct_tree_root = object_id(2)
			parent_tree = object_id(3)
			namespaces = object_ids(4, counts.namespaces)
			structure_start = checked_add(4, counts.namespaces)?
			structure_elements = object_ids(structure_start, counts.structure_elements)
			contextual_start = checked_add(structure_start, counts.structure_elements)?
			contextual_artifacts = object_ids(contextual_start, counts.contextual_artifacts)
			page_tree_start = checked_add(contextual_start, counts.contextual_artifacts)?
			page_tree = object_ids(page_tree_start, page_tree_count)
			pages_start = checked_add(page_tree_start, page_tree_count)?
			pages = page_rows(pages_start, counts.pages)
			profiles_start = checked_add(pages_start, page_object_count)?
			profiles = profile_rows(profiles_start, counts.profiles)
			colors_start = checked_add(profiles_start, profile_object_count)?
			color_spaces = object_ids(colors_start, counts.color_spaces)
			images_start = checked_add(colors_start, counts.color_spaces)?
			images = image_rows(images_start, counts.image_alpha)
			xref_number = checked_add(object_count, 1)?
			Ok(
				KernelGate2Objects.Plan.{
					catalog,
					color_spaces,
					contextual_artifacts,
					images,
					namespaces,
					pages,
					page_tree,
					page_tree_shape: shape,
					parent_tree,
					profiles,
					struct_tree_root,
					structure_elements,
					work: {
						color_space_objects: counts.color_spaces,
						contextual_artifact_objects: counts.contextual_artifacts,
						image_objects: base_image_objects,
						namespace_objects: counts.namespaces,
						object_identities: object_count,
						page_objects: page_object_count,
						page_tree_objects: page_tree_count,
						profile_objects: profile_object_count,
						soft_mask_objects,
						structure_objects: counts.structure_elements,
					},
					xref: object_id(xref_number),
				},
			)
		}
	}
}

page_rows : U64, U64 -> List(KernelGate2Objects.PageObjects)
page_rows = |start, count| {
	var $rows = List.with_capacity(count)
	var $index = 0
	while $index < count {
		page = start + $index * 3
		$rows = $rows.append({ content: { length: object_id(page + 2), stream: object_id(page + 1) }, page: object_id(page) })
		$index = $index + 1
	}
	$rows
}

profile_rows : U64, U64 -> List(KernelGate2Objects.ProfileObjects)
profile_rows = |start, count| {
	var $rows = List.with_capacity(count)
	var $index = 0
	while $index < count {
		profile = start + $index * 2
		stream = { length: object_id(profile + 1), stream: object_id(profile) }
		$rows = $rows.append({ profile: object_id(profile), stream })
		$index = $index + 1
	}
	$rows
}

image_rows : U64, List(Bool) -> List(KernelGate2Objects.ImageObjects)
image_rows = |start, alpha_flags| {
	var $rows = List.with_capacity(alpha_flags.len())
	var $next = start
	var $index = 0
	while $index < alpha_flags.len() {
		image = { length: object_id($next + 1), stream: object_id($next) }
		$next = $next + 2
		soft_mask = if list_at(alpha_flags, $index) {
			mask = { length: object_id($next + 1), stream: object_id($next) }
			$next = $next + 2
			HasSoftMask(mask)
		} else {
			NoSoftMask
		}
		$rows = $rows.append({ image, soft_mask })
		$index = $index + 1
	}
	$rows
}

object_ids : U64, U64 -> List(KernelObject.ObjectId)
object_ids = |start, count| {
	var $ids = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$ids = $ids.append(object_id(start + $index))
		$index = $index + 1
	}
	$ids
}

object_id : U64 -> KernelObject.ObjectId
object_id = |number| match KernelObject.ObjectId.from_number(number) {
	Err(_) => {
		crash "checked Gate 2 object number escaped"
	}
	Ok(id) => id
}

count_true : List(Bool) -> U64
count_true = |values| {
	var $count = 0
	var $index = 0
	while $index < values.len() {
		if list_at(values, $index) {
			$count = $count + 1
		}
		$index = $index + 1
	}
	$count
}

checked_add : U64, U64 -> Try(U64, KernelGate2Objects.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelGate2Objects.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated Gate 2 object-plan index escaped"
	}
}

## Object families receive stable contiguous identities, including alpha masks.
expect {
	plan = build_counts(
		{ color_spaces: 1, contextual_artifacts: 1, image_alpha: [False, True], namespaces: 1, pages: 1, profiles: 1, structure_elements: 2 },
		KernelGate2Objects.Limits.make({ max_objects: 20, max_pages: 1 }),
	)?
	first_page = list_at(plan.pages, 0)
	profile = list_at(plan.profiles, 0)
	first_image = list_at(plan.images, 0)
	second_image = list_at(plan.images, 1)
	KernelObject.ObjectId.number(plan.catalog) == 1 and
		KernelObject.ObjectId.number(plan.struct_tree_root) == 2 and
			KernelObject.ObjectId.number(plan.parent_tree) == 3 and
				KernelObject.ObjectId.number(list_at(plan.namespaces, 0)) == 4 and
					KernelObject.ObjectId.number(list_at(plan.structure_elements, 0)) == 5 and
						KernelObject.ObjectId.number(list_at(plan.structure_elements, 1)) == 6 and
							KernelObject.ObjectId.number(list_at(plan.contextual_artifacts, 0)) == 7 and
								KernelObject.ObjectId.number(list_at(plan.page_tree, 0)) == 8 and
									KernelObject.ObjectId.number(first_page.page) == 9 and
										KernelObject.ObjectId.number(first_page.content.stream) == 10 and
											KernelObject.ObjectId.number(first_page.content.length) == 11 and
												KernelObject.ObjectId.number(profile.profile) == 12 and
													KernelObject.ObjectId.number(profile.stream.length) == 13 and
														KernelObject.ObjectId.number(list_at(plan.color_spaces, 0)) == 14 and
															KernelObject.ObjectId.number(first_image.image.stream) == 15 and
																first_image.soft_mask == NoSoftMask and
																	KernelObject.ObjectId.number(second_image.image.stream) == 17 and
																		match second_image.soft_mask {
																			HasSoftMask(mask) => KernelObject.ObjectId.number(mask.stream) == 19 and KernelObject.ObjectId.number(mask.length) == 20 and KernelObject.ObjectId.number(plan.xref) == 21
																			NoSoftMask => False
																		}
}

## Object work separates stored objects from the generated xref object.
expect {
	plan = build_counts(
		{ color_spaces: 1, contextual_artifacts: 1, image_alpha: [False, True], namespaces: 1, pages: 1, profiles: 1, structure_elements: 2 },
		KernelGate2Objects.Limits.make({ max_objects: 20, max_pages: 1 }),
	)?
	work = KernelGate2Objects.Plan.work(plan)
	work.object_identities == 20 and work.page_objects == 3 and work.page_tree_objects == 1 and work.profile_objects == 2 and work.image_objects == 4 and work.soft_mask_objects == 2 and work.structure_objects == 2 and work.contextual_artifact_objects == 1
}

## Object limits reject the whole plan before any builder mutation.
expect match build_counts(
	{ color_spaces: 1, contextual_artifacts: 1, image_alpha: [False, True], namespaces: 1, pages: 1, profiles: 1, structure_elements: 2 },
	KernelGate2Objects.Limits.make({ max_objects: 19, max_pages: 1 }),
) {
	Err(LimitExceeded({ attempted: 20, dimension: Objects, limit: 19 })) => True
	_ => False
}

## A PDF object plan cannot omit the page-tree root.
expect match build_counts(
	{ color_spaces: 0, contextual_artifacts: 0, image_alpha: [], namespaces: 1, pages: 0, profiles: 0, structure_elements: 1 },
	KernelGate2Objects.Limits.make({ max_objects: 8, max_pages: 1 }),
) {
	Err(PageCountZero) => True
	_ => False
}
