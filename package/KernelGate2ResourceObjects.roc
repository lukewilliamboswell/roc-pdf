import Color
import Image
import KernelColor
import KernelGate2Objects
import KernelGate2PageObjects
import KernelGate2PipelineFixture
import KernelGate2TaggedObjects
import KernelImage
import KernelLex
import KernelObject
import KernelSeal

KernelGate2ResourceObjects :: [].{
	Error : [
		Object(KernelObject.Error),
		ObjectOrder({ actual : KernelObject.ObjectId, expected : KernelObject.ObjectId }),
	]

	Work : {
		color_spaces : U64,
		image_rows : U64,
		images : U64,
		profile_bytes : U64,
		profiles : U64,
		raster_bytes : U64,
		soft_mask_rows : U64,
	}

	## Canonical leaf facts from the Gate 4 resource plan: for each canonical
	## profile, color space, and image, the lowest authored representative
	## whose validated store record lowers once; the authored-to-canonical
	## profile map that `[/ICCBased …]` arrays resolve through; and each
	## canonical raster image's row-compacted planes, shared as immutable
	## ranges of the canonical payload allocation (a JPEG entry keeps empty
	## planes and emits its sanitized store bytes unchanged).
	CanonicalLeaves : {
		color_names : List(U64),
		color_representatives : List(U64),
		image_planes : List({ alpha : List(U8), color : List(U8) }),
		image_representatives : List(U64),
		profile_names : List(U64),
		profile_representatives : List(U64),
	}

	Plan :: { builder : KernelObject.Builder, work : Work }.{
		build : KernelGate2PageObjects.Plan, KernelColor.Plan, KernelImage.Plan, KernelGate2Objects.Plan -> Try(Plan, Error)
		build = |pages, colors, images, objects| build_plan(pages, colors, images, objects)

		## The Gate 4 leaf-deduplicated variant: one object per canonical
		## profile, color space, and image, each lowered from its
		## representative's validated store record, byte-identical to the
		## object every merged authored twin would have produced.
		build_canonical : KernelGate2PageObjects.Plan, KernelColor.Plan, KernelImage.Plan, KernelGate2Objects.Plan, CanonicalLeaves -> Try(Plan, Error)
		build_canonical = |pages, colors, images, objects, leaves| build_canonical_leaf_plan(pages, colors, images, objects, leaves)

		builder : Plan -> KernelObject.Builder
		builder = |plan| plan.builder

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Names := {
	bits_per_component : KernelObject.NameId,
	black_point : KernelObject.NameId,
	cal_gray : KernelObject.NameId,
	color_space : KernelObject.NameId,
	device_gray : KernelObject.NameId,
	height : KernelObject.NameId,
	icc_based : KernelObject.NameId,
	image : KernelObject.NameId,
	n : KernelObject.NameId,
	s_mask : KernelObject.NameId,
	subtype : KernelObject.NameId,
	type_name : KernelObject.NameId,
	white_point : KernelObject.NameId,
	width : KernelObject.NameId,
	x_object : KernelObject.NameId,
}

ImageWork := { builder : KernelObject.Builder, image_rows : U64, raster_bytes : U64, soft_mask_rows : U64 }

build_plan : KernelGate2PageObjects.Plan, KernelColor.Plan, KernelImage.Plan, KernelGate2Objects.Plan -> Try(KernelGate2ResourceObjects.Plan, KernelGate2ResourceObjects.Error)
build_plan = |pages, colors, images, objects| {
	added_names = add_names(KernelGate2PageObjects.Plan.builder(pages))?
	profile_store = KernelColor.Plan.store(colors)
	image_store = KernelImage.Plan.store(images)
	profiles = add_profiles(added_names.builder, added_names.names, profile_store.profiles, KernelGate2Objects.Plan.profiles(objects))?
	spaces = add_color_spaces(profiles.builder, added_names.names, profile_store.spaces, objects)?
	image_work = add_images(spaces, added_names.names, image_store.resources, objects)?
	Ok(
		KernelGate2ResourceObjects.Plan.{
			builder: image_work.builder,
			work: {
				color_spaces: profile_store.spaces.len(),
				image_rows: image_work.image_rows,
				images: image_store.resources.len(),
				profile_bytes: profiles.bytes,
				profiles: profile_store.profiles.len(),
				raster_bytes: image_work.raster_bytes,
				soft_mask_rows: image_work.soft_mask_rows,
			},
		},
	)
}

build_canonical_leaf_plan : KernelGate2PageObjects.Plan, KernelColor.Plan, KernelImage.Plan, KernelGate2Objects.Plan, KernelGate2ResourceObjects.CanonicalLeaves -> Try(KernelGate2ResourceObjects.Plan, KernelGate2ResourceObjects.Error)
build_canonical_leaf_plan = |pages, colors, images, objects, leaves| {
	added_names = add_names(KernelGate2PageObjects.Plan.builder(pages))?
	profile_store = KernelColor.Plan.store(colors)
	image_store = KernelImage.Plan.store(images)
	profiles = add_canonical_profiles(added_names.builder, added_names.names, profile_store.profiles, leaves.profile_representatives, KernelGate2Objects.Plan.profiles(objects))?
	spaces = add_canonical_color_spaces(profiles.builder, added_names.names, profile_store.spaces, leaves, objects)?
	image_work = add_canonical_images(spaces, added_names.names, image_store.resources, leaves, objects)?
	Ok(
		KernelGate2ResourceObjects.Plan.{
			builder: image_work.builder,
			work: {
				color_spaces: leaves.color_representatives.len(),
				image_rows: image_work.image_rows,
				images: leaves.image_representatives.len(),
				profile_bytes: profiles.bytes,
				profiles: leaves.profile_representatives.len(),
				raster_bytes: image_work.raster_bytes,
				soft_mask_rows: image_work.soft_mask_rows,
			},
		},
	)
}

add_canonical_profiles : KernelObject.Builder, Names, List(Color.IccProfile), List(U64), List(KernelGate2Objects.ProfileObjects) -> Try({ builder : KernelObject.Builder, bytes : U64 }, KernelGate2ResourceObjects.Error)
add_canonical_profiles = |builder, names, profiles, representatives, planned| {
	var $builder = builder
	var $bytes = 0
	var $ordinal = 0
	var $error = NoError
	while $ordinal < representatives.len() and $error == NoError {
		profile = list_at(profiles, list_at(representatives, $ordinal))
		objects = list_at(planned, $ordinal)
		components = KernelObject.add_integer($builder, component_count(profile.components))
		match components {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(n) => match KernelObject.add_payload(n.builder, profile.bytes, UnchangedResource) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(payload) => match KernelObject.add_stream_object(payload.builder, [{ key: names.n, value: n.id }], Unfiltered, payload.id) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(stream) => if !KernelObject.ObjectId.is_eq(stream.id, objects.stream.stream) or !KernelObject.ObjectId.is_eq(stream.length_object, objects.stream.length) or !KernelObject.ObjectId.is_eq(stream.id, objects.profile) {
						$error = InvalidOrder({ actual: stream.id, expected: objects.profile })
					} else {
						$builder = stream.builder
						$bytes = $bytes + profile.bytes.len()
					}
				}
			}
		}
		$ordinal = $ordinal + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		InvalidOrder(order) => Err(ObjectOrder(order))
		NoError => Ok({ builder: $builder, bytes: $bytes })
	}
}

add_canonical_color_spaces : KernelObject.Builder, Names, List(Color.SpaceRecord), KernelGate2ResourceObjects.CanonicalLeaves, KernelGate2Objects.Plan -> Try(KernelObject.Builder, KernelGate2ResourceObjects.Error)
add_canonical_color_spaces = |builder, names, spaces, leaves, objects| {
	planned = KernelGate2Objects.Plan.color_spaces(objects)
	var $builder = builder
	var $ordinal = 0
	var $error = NoError
	while $ordinal < leaves.color_representatives.len() and $error == NoError {
		record = list_at(spaces, list_at(leaves.color_representatives, $ordinal))
		value = match record.space {
			CalibratedGray({ black_point, white_point }) => add_cal_gray($builder, names, black_point, white_point)
			IccBased({ components: _, profile }) => add_canonical_icc_based($builder, names, list_at(leaves.profile_names, profile.index()), objects)
			Srgb(profile) => add_canonical_icc_based($builder, names, list_at(leaves.profile_names, profile.index()), objects)
		}
		match value {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(added) => match KernelObject.add_object(added.builder, added.id) {
				Err(error) => {
					$error = Invalid(Object(error))
				}
				Ok(object) => if !KernelObject.ObjectId.is_eq(object.id, list_at(planned, $ordinal)) {
					$error = Invalid(ObjectOrder({ actual: object.id, expected: list_at(planned, $ordinal) }))
				} else {
					$builder = object.builder
				}
			}
		}
		$ordinal = $ordinal + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok($builder)
	}
}

## The `[/ICCBased …]` array references the canonical profile object the
## authored profile deduplicated to.
add_canonical_icc_based : KernelObject.Builder, Names, U64, KernelGate2Objects.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2ResourceObjects.Error)
add_canonical_icc_based = |builder, names, ordinal, objects| {
	kind = KernelObject.add_name_value(builder, names.icc_based) ? Object
	reference = KernelObject.add_reference(kind.builder, list_at(KernelGate2Objects.Plan.profiles(objects), ordinal).profile) ? Object
	array = KernelObject.add_array(reference.builder, [kind.id, reference.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_canonical_images : KernelObject.Builder, Names, List(Image.Resource), KernelGate2ResourceObjects.CanonicalLeaves, KernelGate2Objects.Plan -> Try(ImageWork, KernelGate2ResourceObjects.Error)
add_canonical_images = |builder, names, images, leaves, objects| {
	planned = KernelGate2Objects.Plan.images(objects)
	var $builder = builder
	var $ordinal = 0
	var $image_rows = 0
	var $raster_bytes = 0
	var $soft_mask_rows = 0
	var $error = NoError
	while $ordinal < leaves.image_representatives.len() and $error == NoError {
		resource = list_at(images, list_at(leaves.image_representatives, $ordinal))
		planes = list_at(leaves.image_planes, $ordinal)
		match add_canonical_image($builder, names, resource, planes, leaves, objects, list_at(planned, $ordinal)) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(added) => {
				$builder = added.builder
				$image_rows = $image_rows + added.image_rows
				$raster_bytes = $raster_bytes + added.raster_bytes
				$soft_mask_rows = $soft_mask_rows + added.soft_mask_rows
			}
		}
		$ordinal = $ordinal + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ builder: $builder, image_rows: $image_rows, raster_bytes: $raster_bytes, soft_mask_rows: $soft_mask_rows })
	}
}

## A canonical raster image emits the already row-compacted canonical planes,
## so no second full-size compaction copy exists at emission; a canonical JPEG
## emits its sanitized store bytes unchanged.
add_canonical_image : KernelObject.Builder, Names, Image.Resource, { alpha : List(U8), color : List(U8) }, KernelGate2ResourceObjects.CanonicalLeaves, KernelGate2Objects.Plan, KernelGate2Objects.ImageObjects -> Try(ImageWork, KernelGate2ResourceObjects.Error)
add_canonical_image = |builder, names, resource, planes, leaves, objects, planned| match resource.payload {
	Jpeg(jpeg) => {
		added = add_image_stream(builder, names, jpeg.bytes, canonical_color_target(leaves, objects, jpeg.color_space), jpeg.dimensions, NoSoftMaskReference, Dct, UnchangedResource, planned.image)?
		Ok({ builder: added, image_rows: jpeg.dimensions.height.to_u64(), raster_bytes: jpeg.bytes.len(), soft_mask_rows: 0 })
	}
	Raster(raster) => {
		soft_mask_reference = match planned.soft_mask {
			HasSoftMask(mask) => HasSoftMaskReference(mask.stream)
			NoSoftMask => NoSoftMaskReference
		}
		image = add_image_stream(builder, names, planes.color, canonical_color_target(leaves, objects, raster.color_space), raster.dimensions, soft_mask_reference, Deflate, Generated, planned.image)?
		match (raster.alpha, planned.soft_mask) {
			(NoAlpha, NoSoftMask) => Ok({ builder: image, image_rows: raster.dimensions.height.to_u64(), raster_bytes: planes.color.len(), soft_mask_rows: 0 })
			(PackedAlpha(_), HasSoftMask(mask)) => {
				soft = add_soft_mask(image, names, planes.alpha, raster.dimensions, mask)?
				Ok({ builder: soft, image_rows: raster.dimensions.height.to_u64(), raster_bytes: planes.color.len() + planes.alpha.len(), soft_mask_rows: raster.dimensions.height.to_u64() })
			}
			_ => {
				crash "planned Gate 4 canonical alpha shape escaped"
			}
		}
	}
}

canonical_color_target : KernelGate2ResourceObjects.CanonicalLeaves, KernelGate2Objects.Plan, Color.SpaceId -> KernelObject.ObjectId
canonical_color_target = |leaves, objects, space| list_at(KernelGate2Objects.Plan.color_spaces(objects), list_at(leaves.color_names, space.index()))

add_names : KernelObject.Builder -> Try({ builder : KernelObject.Builder, names : Names }, KernelGate2ResourceObjects.Error)
add_names = |builder| {
	bits = KernelObject.add_name(builder, Str.to_utf8("BitsPerComponent")) ? Object
	black = KernelObject.add_name(bits.builder, Str.to_utf8("BlackPoint")) ? Object
	cal_gray = KernelObject.add_name(black.builder, Str.to_utf8("CalGray")) ? Object
	color_space = KernelObject.add_name(cal_gray.builder, Str.to_utf8("ColorSpace")) ? Object
	device_gray = KernelObject.add_name(color_space.builder, Str.to_utf8("DeviceGray")) ? Object
	height = KernelObject.add_name(device_gray.builder, Str.to_utf8("Height")) ? Object
	icc_based = KernelObject.add_name(height.builder, Str.to_utf8("ICCBased")) ? Object
	image = KernelObject.add_name(icc_based.builder, Str.to_utf8("Image")) ? Object
	n = KernelObject.add_name(image.builder, Str.to_utf8("N")) ? Object
	s_mask = KernelObject.add_name(n.builder, Str.to_utf8("SMask")) ? Object
	subtype = KernelObject.add_name(s_mask.builder, Str.to_utf8("Subtype")) ? Object
	type_name = KernelObject.add_name(subtype.builder, Str.to_utf8("Type")) ? Object
	white = KernelObject.add_name(type_name.builder, Str.to_utf8("WhitePoint")) ? Object
	width = KernelObject.add_name(white.builder, Str.to_utf8("Width")) ? Object
	x_object = KernelObject.add_name(width.builder, Str.to_utf8("XObject")) ? Object
	Ok({
		builder: x_object.builder,
		names: {
			bits_per_component: bits.id,
			black_point: black.id,
			cal_gray: cal_gray.id,
			color_space: color_space.id,
			device_gray: device_gray.id,
			height: height.id,
			icc_based: icc_based.id,
			image: image.id,
			n: n.id,
			s_mask: s_mask.id,
			subtype: subtype.id,
			type_name: type_name.id,
			white_point: white.id,
			width: width.id,
			x_object: x_object.id,
		},
	})
}

add_profiles : KernelObject.Builder, Names, List(Color.IccProfile), List(KernelGate2Objects.ProfileObjects) -> Try({ builder : KernelObject.Builder, bytes : U64 }, KernelGate2ResourceObjects.Error)
add_profiles = |builder, names, profiles, planned| {
	var $builder = builder
	var $bytes = 0
	var $index = 0
	var $error = NoError
	while $index < profiles.len() and $error == NoError {
		profile = list_at(profiles, $index)
		objects = list_at(planned, profile.id.index())
		components = KernelObject.add_integer($builder, component_count(profile.components))
		match components {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(n) => match KernelObject.add_payload(n.builder, profile.bytes, UnchangedResource) {
				Err(error) => {
					$error = Invalid(error)
				}
				Ok(payload) => match KernelObject.add_stream_object(payload.builder, [{ key: names.n, value: n.id }], Unfiltered, payload.id) {
					Err(error) => {
						$error = Invalid(error)
					}
					Ok(stream) => if !KernelObject.ObjectId.is_eq(stream.id, objects.stream.stream) or !KernelObject.ObjectId.is_eq(stream.length_object, objects.stream.length) or !KernelObject.ObjectId.is_eq(stream.id, objects.profile) {
						$error = InvalidOrder({ actual: stream.id, expected: objects.profile })
					} else {
						$builder = stream.builder
						$bytes = $bytes + profile.bytes.len()
					}
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(Object(error))
		InvalidOrder(order) => Err(ObjectOrder(order))
		NoError => Ok({ builder: $builder, bytes: $bytes })
	}
}

add_color_spaces : KernelObject.Builder, Names, List(Color.SpaceRecord), KernelGate2Objects.Plan -> Try(KernelObject.Builder, KernelGate2ResourceObjects.Error)
add_color_spaces = |builder, names, spaces, objects| {
	planned = KernelGate2Objects.Plan.color_spaces(objects)
	var $builder = builder
	var $index = 0
	var $error = NoError
	while $index < spaces.len() and $error == NoError {
		record = list_at(spaces, $index)
		match add_color_space($builder, names, record.space, objects, list_at(planned, record.id.index())) {
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

add_color_space : KernelObject.Builder, Names, Color.Space, KernelGate2Objects.Plan, KernelObject.ObjectId -> Try(KernelObject.Builder, KernelGate2ResourceObjects.Error)
add_color_space = |builder, names, space, objects, expected| {
	value = match space {
		CalibratedGray({ black_point, white_point }) => add_cal_gray(builder, names, black_point, white_point)
		IccBased({ components: _, profile }) => add_icc_based(builder, names, profile, objects)
		Srgb(profile) => add_icc_based(builder, names, profile, objects)
	}?
	object = KernelObject.add_object(value.builder, value.id) ? Object
	ensure_object(object.id, expected)?
	Ok(object.builder)
}

add_cal_gray : KernelObject.Builder, Names, Color.Tristimulus, Color.Tristimulus -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2ResourceObjects.Error)
add_cal_gray = |builder, names, black_point, white_point| {
	black = add_tristimulus(builder, black_point)?
	white = add_tristimulus(black.builder, white_point)?
	dictionary = KernelObject.add_dictionary(
		white.builder,
		[
			{ key: names.black_point, value: black.id },
			{ key: names.white_point, value: white.id },
		],
	) ? Object
	kind = KernelObject.add_name_value(dictionary.builder, names.cal_gray) ? Object
	array = KernelObject.add_array(kind.builder, [kind.id, dictionary.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_icc_based : KernelObject.Builder, Names, Color.ProfileId, KernelGate2Objects.Plan -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2ResourceObjects.Error)
add_icc_based = |builder, names, profile, objects| {
	kind = KernelObject.add_name_value(builder, names.icc_based) ? Object
	reference = KernelObject.add_reference(kind.builder, list_at(KernelGate2Objects.Plan.profiles(objects), profile.index()).profile) ? Object
	array = KernelObject.add_array(reference.builder, [kind.id, reference.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_tristimulus : KernelObject.Builder, Color.Tristimulus -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2ResourceObjects.Error)
add_tristimulus = |builder, value| {
	x = add_millionth(builder, value.x)?
	y = add_millionth(x.builder, value.y)?
	z = add_millionth(y.builder, value.z)?
	array = KernelObject.add_array(z.builder, [x.id, y.id, z.id]) ? Object
	Ok({ builder: array.builder, id: array.id })
}

add_millionth : KernelObject.Builder, I64 -> Try({ builder : KernelObject.Builder, id : KernelObject.ValueId }, KernelGate2ResourceObjects.Error)
add_millionth = |builder, coefficient| {
	decimal = match KernelLex.Decimal.from_coefficient(coefficient, 6) {
		Err(_) => {
			crash "fixed Gate 2 tristimulus scale escaped"
		}
		Ok(valid) => valid
	}
	added = KernelObject.add_real(builder, decimal) ? Object
	Ok(added)
}

add_images : KernelObject.Builder, Names, List(Image.Resource), KernelGate2Objects.Plan -> Try(ImageWork, KernelGate2ResourceObjects.Error)
add_images = |builder, names, images, objects| {
	planned = KernelGate2Objects.Plan.images(objects)
	var $builder = builder
	var $index = 0
	var $image_rows = 0
	var $raster_bytes = 0
	var $soft_mask_rows = 0
	var $error = NoError
	while $index < images.len() and $error == NoError {
		resource = list_at(images, $index)
		match add_image($builder, names, resource, objects, list_at(planned, resource.id.index())) {
			Err(error) => {
				$error = Invalid(error)
			}
			Ok(added) => {
				$builder = added.builder
				$image_rows = $image_rows + added.image_rows
				$raster_bytes = $raster_bytes + added.raster_bytes
				$soft_mask_rows = $soft_mask_rows + added.soft_mask_rows
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ builder: $builder, image_rows: $image_rows, raster_bytes: $raster_bytes, soft_mask_rows: $soft_mask_rows })
	}
}

add_image : KernelObject.Builder, Names, Image.Resource, KernelGate2Objects.Plan, KernelGate2Objects.ImageObjects -> Try(ImageWork, KernelGate2ResourceObjects.Error)
add_image = |builder, names, resource, objects, planned| match resource.payload {
	Jpeg(jpeg) => {
		added = add_image_stream(builder, names, jpeg.bytes, list_at(KernelGate2Objects.Plan.color_spaces(objects), jpeg.color_space.index()), jpeg.dimensions, NoSoftMaskReference, Dct, UnchangedResource, planned.image)?
		Ok({ builder: added, image_rows: jpeg.dimensions.height.to_u64(), raster_bytes: jpeg.bytes.len(), soft_mask_rows: 0 })
	}
	Raster(raster) => {
		soft_mask_reference = match planned.soft_mask {
			HasSoftMask(mask) => HasSoftMaskReference(mask.stream)
			NoSoftMask => NoSoftMaskReference
		}
		pixels = compact_pixels(raster)
		image = add_image_stream(builder, names, pixels, list_at(KernelGate2Objects.Plan.color_spaces(objects), raster.color_space.index()), raster.dimensions, soft_mask_reference, Deflate, Generated, planned.image)?
		match (raster.alpha, planned.soft_mask) {
			(NoAlpha, NoSoftMask) => Ok({ builder: image, image_rows: raster.dimensions.height.to_u64(), raster_bytes: pixels.len(), soft_mask_rows: 0 })
			(PackedAlpha(alpha), HasSoftMask(mask)) => {
				bytes = compact_rows(alpha.bytes, alpha.row_stride, raster.dimensions.width.to_u64(), raster.dimensions.height.to_u64())
				soft = add_soft_mask(image, names, bytes, raster.dimensions, mask)?
				Ok({ builder: soft, image_rows: raster.dimensions.height.to_u64(), raster_bytes: pixels.len() + bytes.len(), soft_mask_rows: raster.dimensions.height.to_u64() })
			}
			_ => {
				crash "planned Gate 2 alpha shape escaped"
			}
		}
	}
}

SoftMaskReference := [HasSoftMaskReference(KernelObject.ObjectId), NoSoftMaskReference]

add_image_stream : KernelObject.Builder, Names, List(U8), KernelObject.ObjectId, Image.Dimensions, SoftMaskReference, KernelObject.FilterPlan, KernelObject.PayloadKind, KernelGate2Objects.StreamObjects -> Try(KernelObject.Builder, KernelGate2ResourceObjects.Error)
add_image_stream = |builder, names, bytes, color_target, dimensions, soft_mask, filter, kind, planned| {
	bits = KernelObject.add_integer(builder, 8) ? Object
	color = KernelObject.add_reference(bits.builder, color_target) ? Object
	height = KernelObject.add_integer(color.builder, dimensions.height.to_i64()) ? Object
	subtype = KernelObject.add_name_value(height.builder, names.image) ? Object
	type_value = KernelObject.add_name_value(subtype.builder, names.x_object) ? Object
	width = KernelObject.add_integer(type_value.builder, dimensions.width.to_i64()) ? Object
	with_entries = match soft_mask {
		NoSoftMaskReference => {
			builder: width.builder,
			entries: [
				{ key: names.bits_per_component, value: bits.id },
				{ key: names.color_space, value: color.id },
				{ key: names.height, value: height.id },
				{ key: names.subtype, value: subtype.id },
				{ key: names.type_name, value: type_value.id },
				{ key: names.width, value: width.id },
			],
		}
		HasSoftMaskReference(mask_object) => {
			mask = KernelObject.add_reference(width.builder, mask_object) ? Object
			{
				builder: mask.builder,
				entries: [
					{ key: names.bits_per_component, value: bits.id },
					{ key: names.color_space, value: color.id },
					{ key: names.height, value: height.id },
					{ key: names.s_mask, value: mask.id },
					{ key: names.subtype, value: subtype.id },
					{ key: names.type_name, value: type_value.id },
					{ key: names.width, value: width.id },
				],
			}
		}
	}
	payload = KernelObject.add_payload(with_entries.builder, bytes, kind) ? Object
	stream = KernelObject.add_stream_object(payload.builder, with_entries.entries, filter, payload.id) ? Object
	ensure_object(stream.id, planned.stream)?
	ensure_object(stream.length_object, planned.length)?
	Ok(stream.builder)
}

add_soft_mask : KernelObject.Builder, Names, List(U8), Image.Dimensions, KernelGate2Objects.StreamObjects -> Try(KernelObject.Builder, KernelGate2ResourceObjects.Error)
add_soft_mask = |builder, names, bytes, dimensions, planned| {
	bits = KernelObject.add_integer(builder, 8) ? Object
	color = KernelObject.add_name_value(bits.builder, names.device_gray) ? Object
	height = KernelObject.add_integer(color.builder, dimensions.height.to_i64()) ? Object
	subtype = KernelObject.add_name_value(height.builder, names.image) ? Object
	type_value = KernelObject.add_name_value(subtype.builder, names.x_object) ? Object
	width = KernelObject.add_integer(type_value.builder, dimensions.width.to_i64()) ? Object
	payload = KernelObject.add_payload(width.builder, bytes, Generated) ? Object
	stream = KernelObject.add_stream_object(
		payload.builder,
		[
			{ key: names.bits_per_component, value: bits.id },
			{ key: names.color_space, value: color.id },
			{ key: names.height, value: height.id },
			{ key: names.subtype, value: subtype.id },
			{ key: names.type_name, value: type_value.id },
			{ key: names.width, value: width.id },
		],
		Deflate,
		payload.id,
	) ? Object
	ensure_object(stream.id, planned.stream)?
	ensure_object(stream.length_object, planned.length)?
	Ok(stream.builder)
}

compact_pixels : Image.PackedRaster -> List(U8)
compact_pixels = |raster| {
	components = match raster.format {
		Gray8 => 1
		Rgb8 => 3
	}
	compact_rows(raster.pixels, raster.row_stride, raster.dimensions.width.to_u64() * components, raster.dimensions.height.to_u64())
}

compact_rows : List(U8), U64, U64, U64 -> List(U8)
compact_rows = |source, stride, row_bytes, height| {
	var $output = List.with_capacity(row_bytes * height)
	var $row = 0
	while $row < height {
		start = $row * stride
		var $column = 0
		while $column < row_bytes {
			$output = $output.append(list_at(source, start + $column))
			$column = $column + 1
		}
		$row = $row + 1
	}
	$output
}

component_count : Color.ComponentCount -> I64
component_count = |components| match components {
	One => 1
	Three => 3
}

ensure_object : KernelObject.ObjectId, KernelObject.ObjectId -> Try({}, KernelGate2ResourceObjects.Error)
ensure_object = |actual, expected| if KernelObject.ObjectId.is_eq(actual, expected) Ok({}) else Err(ObjectOrder({ actual, expected }))

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated Gate 2 resource-object index escaped"
	}
}

test_limits : KernelObject.Limits
test_limits = {
	max_array_items: 192,
	max_byte_string_bytes: 0,
	max_byte_strings: 0,
	max_dictionary_entries: 320,
	max_direct_depth: 8,
	max_name_bytes: 3072,
	max_names: 128,
	max_objects: 16,
	max_payload_bytes: 1024,
	max_payloads: 3,
	max_streams: 3,
	max_text_string_bytes: 64,
	max_text_strings: 1,
	max_values: 640,
}

## Resource lowering completes every planned object and produces a sealable store.
expect {
	pipeline = KernelGate2PipelineFixture.pipeline({})?
	prefix = KernelGate2TaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, test_limits)?
	pages = KernelGate2PageObjects.Plan.build(prefix, pipeline.tagged, pipeline.content, pipeline.objects)?
	resources = KernelGate2ResourceObjects.Plan.build(pages, pipeline.colors, pipeline.images, pipeline.objects)?
	sealed = KernelSeal.seal(KernelGate2ResourceObjects.Plan.builder(resources))?
	counts = KernelSeal.Plan.counts(sealed)
	work = KernelGate2ResourceObjects.Plan.work(resources)
	counts.objects == KernelGate2Objects.Plan.object_count(pipeline.objects) and counts.payloads == 2 and counts.streams == 2 and work.color_spaces == 1 and work.images == 1 and work.image_rows == 2 and work.raster_bytes == 4
}

## Padded raster and alpha rows compact into distinct image and soft-mask streams.
expect {
	pipeline = KernelGate2PipelineFixture.alpha_pipeline({})?
	prefix = KernelGate2TaggedObjects.Plan.build(pipeline.tagged, pipeline.objects, test_limits)?
	pages = KernelGate2PageObjects.Plan.build(prefix, pipeline.tagged, pipeline.content, pipeline.objects)?
	resources = KernelGate2ResourceObjects.Plan.build(pages, pipeline.colors, pipeline.images, pipeline.objects)?
	sealed = KernelSeal.seal(KernelGate2ResourceObjects.Plan.builder(resources))?
	counts = KernelSeal.Plan.counts(sealed)
	work = KernelGate2ResourceObjects.Plan.work(resources)
	counts.objects == KernelGate2Objects.Plan.object_count(pipeline.objects) and counts.payloads == 3 and counts.streams == 3 and work.raster_bytes == 8 and work.image_rows == 2 and work.soft_mask_rows == 2
}
