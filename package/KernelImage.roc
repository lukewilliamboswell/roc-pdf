import Color
import Image
import KernelColor

KernelImage :: [].{
	Dimension : [DecodedBytes, EncodedBytes, Height, Resources, Width]
	Error : [
		ArithmeticOverflow,
		ColorComponentMismatch({ resource : U64 }),
		ColorSpaceOutOfRange({ available : U64, index : U64, resource : U64 }),
		DecodedLengthMismatch({ actual : U64, expected : U64, resource : U64 }),
		InvalidDimensions({ height : U32, resource : U64, width : U32 }),
		InvalidRowStride({ minimum : U64, resource : U64, stride : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		NonDenseIdentity({ actual : U64, expected : U64 }),
		UnsupportedJpeg({ resource : U64 }),
	]

	Limits :: { max_decoded_bytes : U64, max_encoded_bytes : U64, max_height : U32, max_resources : U64, max_width : U32 }.{
		make : { max_decoded_bytes : U64, max_encoded_bytes : U64, max_height : U32, max_resources : U64, max_width : U32 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : { bytes_checked : U64, resource_visits : U64, rows_checked : U64 }

	Plan :: { store : Image.Store, work : Work }.{
		build : Image.SourceStore, KernelColor.Plan, Limits -> Try(Plan, Error)
		build = |sources, colors, limits| build_plan(sources, colors, limits)

		resource_count : Plan -> U64
		resource_count = |plan| plan.store.resources.len()

		store : Plan -> Image.Store
		store = |plan| plan.store

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : Image.SourceStore, KernelColor.Plan, KernelImage.Limits -> Try(KernelImage.Plan, KernelImage.Error)
build_plan = |sources, colors, limits| {
	if sources.resources.len() > limits.max_resources {
		Err(LimitExceeded({ attempted: sources.resources.len(), dimension: Resources, limit: limits.max_resources }))
	} else {
		var $resources = []
		var $index = 0
		var $bytes_checked = 0
		var $rows_checked = 0
		var $decoded_total = 0
		var $encoded_total = 0
		var $error = NoError
		while $index < sources.resources.len() and $error == NoError {
			source = list_at(sources.resources, $index)
			if source.id.index() != $index {
				$error = Invalid(NonDenseIdentity({ actual: source.id.index(), expected: $index }))
			} else {
				match source.payload {
					EncodedJpeg(jpeg) => {
						$encoded_total = match checked_add($encoded_total, jpeg.bytes.len()) {
							Err(error) => {
								$error = Invalid(error)
								$encoded_total
							}
							Ok(total) => total
						}
						if $error == NoError and $encoded_total > limits.max_encoded_bytes {
							$error = Invalid(LimitExceeded({ attempted: $encoded_total, dimension: EncodedBytes, limit: limits.max_encoded_bytes }))
						} else if $error == NoError {
							$error = Invalid(UnsupportedJpeg({ resource: $index }))
						}
					}
					PackedPixels(raster) => match validate_raster(raster, $index, colors, limits) {
						Err(error) => {
							$error = Invalid(error)
						}
						Ok(work) => {
							match checked_add($decoded_total, work.bytes_checked) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(total) => if total > limits.max_decoded_bytes {
									$error = Invalid(LimitExceeded({ attempted: total, dimension: DecodedBytes, limit: limits.max_decoded_bytes }))
								} else {
									$decoded_total = total
									$bytes_checked = $bytes_checked + work.bytes_checked
									$rows_checked = $rows_checked + work.rows_checked
									$resources = $resources.append({ id: source.id, payload: Raster(raster) })
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
			NoError => Ok(KernelImage.Plan.{ store: { resources: $resources }, work: { bytes_checked: $bytes_checked, resource_visits: sources.resources.len(), rows_checked: $rows_checked } })
		}
	}
}

validate_raster : Image.PackedRaster, U64, KernelColor.Plan, KernelImage.Limits -> Try({ bytes_checked : U64, rows_checked : U64 }, KernelImage.Error)
validate_raster = |raster, resource, colors, limits| {
	width = raster.dimensions.width
	height = raster.dimensions.height
	space_index = raster.color_space.index()
	if width == 0 or height == 0 {
		Err(InvalidDimensions({ height, resource, width }))
	} else if width > limits.max_width {
		Err(LimitExceeded({ attempted: width.to_u64(), dimension: Width, limit: limits.max_width.to_u64() }))
	} else if height > limits.max_height {
		Err(LimitExceeded({ attempted: height.to_u64(), dimension: Height, limit: limits.max_height.to_u64() }))
	} else if space_index >= KernelColor.Plan.space_count(colors) {
		Err(ColorSpaceOutOfRange({ available: KernelColor.Plan.space_count(colors), index: space_index, resource }))
	} else {
		expected_components = match raster.format {
			Gray8 => One
			Rgb8 => Three
		}
		if KernelColor.Plan.components(colors, raster.color_space) != expected_components {
			Err(
				ColorComponentMismatch({
					resource: resource,
				}),
			)
		} else {
			component_width = match raster.format {
				Gray8 => 1
				Rgb8 => 3
			}
			minimum_stride = checked_times(width.to_u64(), component_width)?
			if raster.row_stride < minimum_stride {
				Err(InvalidRowStride({ minimum: minimum_stride, resource, stride: raster.row_stride }))
			} else {
				expected_pixels = checked_times(raster.row_stride, height.to_u64())?
				if raster.pixels.len() != expected_pixels {
					Err(DecodedLengthMismatch({ actual: raster.pixels.len(), expected: expected_pixels, resource }))
				} else {
					match raster.alpha {
						NoAlpha => Ok({ bytes_checked: expected_pixels, rows_checked: height.to_u64() })
						PackedAlpha({ bytes, row_stride }) => {
							if row_stride < width.to_u64() {
								Err(InvalidRowStride({ minimum: width.to_u64(), resource, stride: row_stride }))
							} else {
								expected_alpha = checked_times(row_stride, height.to_u64())?
								if bytes.len() != expected_alpha {
									Err(DecodedLengthMismatch({ actual: bytes.len(), expected: expected_alpha, resource }))
								} else {
									Ok({ bytes_checked: checked_add(expected_pixels, expected_alpha)?, rows_checked: height.to_u64() * 2 })
								}
							}
						}
					}
				}
			}
		}
	}
}

checked_add : U64, U64 -> Try(U64, KernelImage.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

checked_times : U64, U64 -> Try(U64, KernelImage.Error)
checked_times = |left, right| match U64.times_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated image index escaped"
	}
}

gray_color_store : Color.Store
gray_color_store = {
	profiles: [],
	spaces: [{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) }],
	tags: [],
}

gray_color_limits : KernelColor.Limits
gray_color_limits = KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })

test_raster : Image.PackedRaster
test_raster = { alpha: NoAlpha, color_space: Color.SpaceId.from_index(0), dimensions: { height: 2, width: 2 }, format: Gray8, pixels: [0, 64, 128, 255], row_stride: 2 }

test_limits : KernelImage.Limits
test_limits = KernelImage.Limits.make({ max_decoded_bytes: 4, max_encoded_bytes: 32, max_height: 2, max_resources: 1, max_width: 2 })

## Packed gray raster rows are validated without pixel-record allocation.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: PackedPixels(test_raster) }] }
	plan = KernelImage.Plan.build(sources, colors, test_limits)?
	work = KernelImage.Plan.work(plan)

	KernelImage.Plan.resource_count(plan) == 1 and work.bytes_checked == 4 and work.rows_checked == 2
}

## Raster formats must match their typed color-space component count.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: PackedPixels({ ..test_raster, format: Rgb8 }) }] }

	match KernelImage.Plan.build(sources, colors, test_limits) {
		Err(ColorComponentMismatch({ resource: 0 })) => True
		_ => False
	}
}

## Encoded JPEGs remain explicit until bounded marker inspection succeeds.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: [0xff, 0xd8], color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] }

	match KernelImage.Plan.build(sources, colors, test_limits) {
		Err(UnsupportedJpeg({ resource: 0 })) => True
		_ => False
	}
}
