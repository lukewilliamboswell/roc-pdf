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
		InvalidExif({ resource : U64 }),
		InvalidJpegMarker({ marker : U8, offset : U64, resource : U64 }),
		InvalidJpegSegment({ offset : U64, resource : U64 }),
		InvalidRowStride({ minimum : U64, resource : U64, stride : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		MarkerLimitExceeded({ attempted : U64, limit : U64, resource : U64 }),
		NonDenseIdentity({ actual : U64, expected : U64 }),
		OrientationRequiresTransform({ resource : U64 }),
		UnsupportedJpegComponents({ components : U8, resource : U64 }),
	]

	Limits :: { max_decoded_bytes : U64, max_encoded_bytes : U64, max_height : U32, max_markers : U64, max_resources : U64, max_width : U32 }.{
		make : { max_decoded_bytes : U64, max_encoded_bytes : U64, max_height : U32, max_markers : U64, max_resources : U64, max_width : U32 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : { bytes_checked : U64, markers_checked : U64, resource_visits : U64, rows_checked : U64 }

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
		var $markers_checked = 0
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
							match inspect_jpeg(jpeg, $index, colors, limits) {
								Err(error) => {
									$error = Invalid(error)
								}
								Ok(inspected) => {
									decoded = checked_times(inspected.decoded_row_bytes, inspected.jpeg.dimensions.height.to_u64())
									match decoded {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(decoded_bytes) => match checked_add($decoded_total, decoded_bytes) {
											Err(error) => {
												$error = Invalid(error)
											}
											Ok(total) => if total > limits.max_decoded_bytes {
												$error = Invalid(LimitExceeded({ attempted: total, dimension: DecodedBytes, limit: limits.max_decoded_bytes }))
											} else {
												$decoded_total = total
												$bytes_checked = $bytes_checked + jpeg.bytes.len()
												$markers_checked = $markers_checked + inspected.markers_checked
												$rows_checked = $rows_checked + inspected.jpeg.dimensions.height.to_u64()
												$resources = $resources.append({ id: source.id, payload: Jpeg(inspected.jpeg) })
											}
										}
									}
								}
							}
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
			NoError => Ok(KernelImage.Plan.{ store: { resources: $resources }, work: { bytes_checked: $bytes_checked, markers_checked: $markers_checked, resource_visits: sources.resources.len(), rows_checked: $rows_checked } })
		}
	}
}

JpegInspection := { decoded_row_bytes : U64, jpeg : Image.ValidatedJpeg, markers_checked : U64 }

inspect_jpeg : Image.JpegSource, U64, KernelColor.Plan, KernelImage.Limits -> Try(JpegInspection, KernelImage.Error)
inspect_jpeg = |source, resource, colors, limits| {
	bytes = source.bytes
	if bytes.len() < 4 or list_at(bytes, 0) != 0xff or list_at(bytes, 1) != 0xd8 {
		Err(InvalidJpegSegment({ offset: 0, resource }))
	} else if source.color_space.index() >= KernelColor.Plan.space_count(colors) {
		Err(ColorSpaceOutOfRange({ available: KernelColor.Plan.space_count(colors), index: source.color_space.index(), resource }))
	} else {
		var $output = [0xff, 0xd8]
		var $index = 2
		var $markers = 1
		var $width = 0
		var $height = 0
		var $component_count = 0
		var $found_frame = False
		var $found_dht = False
		var $found_dqt = False
		var $scan_count = 0
		var $orientation = NoExif
		var $done = False
		var $error = NoError
		while $done == False and $error == NoError {
			if $index >= bytes.len() or list_at(bytes, $index) != 0xff {
				$error = Invalid(InvalidJpegSegment({ offset: $index, resource }))
			} else {
				var $code_index = $index + 1
				while $code_index < bytes.len() and list_at(bytes, $code_index) == 0xff {
					$code_index = $code_index + 1
				}
				if $code_index >= bytes.len() {
					$error = Invalid(InvalidJpegSegment({ offset: $index, resource }))
				} else {
					marker = list_at(bytes, $code_index)
					marker_start = $code_index - 1
					$markers = $markers + 1
					if $markers > limits.max_markers {
						$error = Invalid(MarkerLimitExceeded({ attempted: $markers, limit: limits.max_markers, resource }))
					} else if marker == 0xd9 {
						if $found_frame == False or $found_dht == False or $found_dqt == False or $scan_count == 0 or $code_index + 1 != bytes.len() {
							$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
						} else {
							$output = $output.append(0xff).append(0xd9)
							$done = True
							$index = bytes.len()
						}
					} else if marker == 0x00 or marker == 0xd8 or (marker >= 0xd0 and marker <= 0xd7) {
						$error = Invalid(InvalidJpegMarker({ marker, offset: marker_start, resource }))
					} else if $code_index + 2 >= bytes.len() {
						$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
					} else {
						segment_length = read_u16_be(bytes, $code_index + 1).to_u64()
						data_start = $code_index + 3
						if segment_length < 2 or segment_length - 2 > bytes.len() - data_start {
							$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
						} else {
							data_length = segment_length - 2
							segment_end = data_start + data_length
							if marker == 0xc0 or marker == 0xc1 or marker == 0xc2 {
								if $found_frame {
									$error = Invalid(InvalidJpegMarker({ marker, offset: marker_start, resource }))
								} else {
									match inspect_frame(bytes, data_start, data_length, resource, colors, source.color_space, limits) {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(frame) => {
											$width = frame.width
											$height = frame.height
											$component_count = frame.components
											$found_frame = True
											$output = append_range($output, bytes, marker_start, segment_end)
										}
									}
								}
							} else if marker == 0xc4 {
								if !valid_huffman_tables(bytes, data_start, data_length) {
									$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
								} else {
									$found_dht = True
									$output = append_range($output, bytes, marker_start, segment_end)
								}
							} else if marker == 0xdb {
								if !valid_quantization_tables(bytes, data_start, data_length) {
									$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
								} else {
									$found_dqt = True
									$output = append_range($output, bytes, marker_start, segment_end)
								}
							} else if marker == 0xdd {
								if data_length != 2 {
									$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
								} else {
									$output = append_range($output, bytes, marker_start, segment_end)
								}
							} else if marker == 0xda {
								if $found_frame == False or !valid_scan_header(bytes, data_start, data_length, $component_count) {
									$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
								} else {
									$output = append_range($output, bytes, marker_start, segment_end)
									match scan_entropy(bytes, segment_end, $output, resource) {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(scan) => {
											$output = scan.output
											$index = scan.next_marker
											$scan_count = $scan_count + 1
										}
									}
								}
							} else if marker == 0xe0 {
								if data_length >= 5 and matches(bytes, data_start, [0x4a, 0x46, 0x49, 0x46, 0x00]) {
									if data_length < 14 {
										$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
									} else {
										$output = append_range($output, bytes, marker_start, segment_end)
									}
								}
							} else if marker == 0xe1 {
								if data_length >= 6 and matches(bytes, data_start, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]) {
									match inspect_exif_orientation(bytes, data_start, data_length, resource) {
										Err(error) => {
											$error = Invalid(error)
										}
										Ok(found) => match ($orientation, found) {
											(NoExif, next) => {
												$orientation = next
											}
											(_, NoExif) => {}
											_ => {
												$error = Invalid(
													InvalidExif({
														resource: resource,
													}),
												)
											}
										}
									}
								}
							} else if marker == 0xee {
								if data_length < 12 or !matches(bytes, data_start, [0x41, 0x64, 0x6f, 0x62, 0x65]) or list_at(bytes, data_start + 11) > 1 {
									$error = Invalid(InvalidJpegSegment({ offset: marker_start, resource }))
								} else {
									$output = append_range($output, bytes, marker_start, segment_end)
								}
							} else if (marker >= 0xe2 and marker <= 0xed) or marker == 0xef or marker == 0xfe {
								{}
							} else {
								$error = Invalid(InvalidJpegMarker({ marker, offset: marker_start, resource }))
							}

							if $error == NoError and marker != 0xda {
								$index = segment_end
							}
						}
					}
				}
			}
		}

		match $error {
			Invalid(error) => Err(error)
			NoError => {
				orientation_evidence = resolve_orientation($orientation, source.orientation_policy, resource)?
				components = if $component_count == 1 One else Three
				Ok({
					decoded_row_bytes: checked_times($width.to_u64(), $component_count.to_u64())?,
					jpeg: { bytes: $output, color_space: source.color_space, components, dimensions: { height: $height, width: $width }, orientation: orientation_evidence },
					markers_checked: $markers,
				})
			}
		}
	}
}

inspect_frame : List(U8), U64, U64, U64, KernelColor.Plan, Color.SpaceId, KernelImage.Limits -> Try({ components : U8, height : U32, width : U32 }, KernelImage.Error)
inspect_frame = |bytes, start, length, resource, colors, color_space, limits| {
	if length < 6 or list_at(bytes, start) != 8 {
		Err(InvalidJpegSegment({ offset: start, resource }))
	} else {
		height = read_u16_be(bytes, start + 1).to_u32()
		width = read_u16_be(bytes, start + 3).to_u32()
		components = list_at(bytes, start + 5)
		if components != 1 and components != 3 {
			Err(UnsupportedJpegComponents({ components, resource }))
		} else if length != 6 + components.to_u64() * 3 {
			Err(InvalidJpegSegment({ offset: start, resource }))
		} else if width == 0 or height == 0 {
			Err(InvalidDimensions({ height, resource, width }))
		} else if width > limits.max_width {
			Err(LimitExceeded({ attempted: width.to_u64(), dimension: Width, limit: limits.max_width.to_u64() }))
		} else if height > limits.max_height {
			Err(LimitExceeded({ attempted: height.to_u64(), dimension: Height, limit: limits.max_height.to_u64() }))
		} else {
			expected = if components == 1 One else Three
			if KernelColor.Plan.components(colors, color_space) != expected {
				Err(ColorComponentMismatch({ resource: resource }))
			} else if !valid_frame_components(bytes, start + 6, components) {
				Err(InvalidJpegSegment({ offset: start, resource }))
			} else {
				Ok({ components, height, width })
			}
		}
	}
}

valid_frame_components : List(U8), U64, U8 -> Bool
valid_frame_components = |bytes, start, count| {
	var $seen = List.repeat(0, 256)
	var $index = 0
	var $valid = True
	while $index < count.to_u64() and $valid {
		component = list_at(bytes, start + $index * 3).to_u64()
		sampling = list_at(bytes, start + $index * 3 + 1)
		quantization = list_at(bytes, start + $index * 3 + 2)
		if list_at($seen, component) != 0 or sampling.bitwise_and(0x0f) == 0 or sampling.shr_wrap(4) == 0 or quantization > 3 {
			$valid = False
		} else {
			$seen = list_set($seen, component, 1)
		}
		$index = $index + 1
	}
	$valid
}

valid_quantization_tables : List(U8), U64, U64 -> Bool
valid_quantization_tables = |bytes, start, length| {
	end = start + length
	var $index = start
	var $tables = zero_u64
	var $valid = True
	while $index < end and $valid {
		info = list_at(bytes, $index)
		precision = info.shr_wrap(4)
		if precision > 1 or info.bitwise_and(0x0f) > 3 {
			$valid = False
		} else {
			table_bytes = if precision == 0 64 else 128
			if table_bytes > end - ($index + 1) {
				$valid = False
			} else {
				$index = $index + 1 + table_bytes
				$tables = $tables + 1
			}
		}
	}
	$valid and $index == end and $tables > 0
}

valid_huffman_tables : List(U8), U64, U64 -> Bool
valid_huffman_tables = |bytes, start, length| {
	end = start + length
	var $index = start
	var $tables = zero_u64
	var $valid = True
	while $index < end and $valid {
		if end - $index < 17 {
			$valid = False
		} else {
			info = list_at(bytes, $index)
			if info.shr_wrap(4) > 1 or info.bitwise_and(0x0f) > 3 {
				$valid = False
			} else {
				var $count_index = 0
				var $symbols = 0
				while $count_index < 16 {
					$symbols = $symbols + list_at(bytes, $index + 1 + $count_index).to_u64()
					$count_index = $count_index + 1
				}
				if $symbols == 0 or $symbols > 256 or $symbols > end - ($index + 17) {
					$valid = False
				} else {
					$index = $index + 17 + $symbols
					$tables = $tables + 1
				}
			}
		}
	}
	$valid and $index == end and $tables > 0
}

valid_scan_header : List(U8), U64, U64, U8 -> Bool
valid_scan_header = |bytes, start, length, frame_components| {
	if length < 4 {
		False
	} else {
		components = list_at(bytes, start)
		components > 0 and components <= frame_components and length == 1 + components.to_u64() * 2 + 3
	}
}

scan_entropy : List(U8), U64, List(U8), U64 -> Try({ next_marker : U64, output : List(U8) }, KernelImage.Error)
scan_entropy = |bytes, start, output, resource| {
	var $index = start
	var $done = False
	var $error = NoError
	while $done == False and $error == NoError {
		if $index >= bytes.len() {
			$error = Invalid(InvalidJpegSegment({ offset: start, resource }))
		} else if list_at(bytes, $index) != 0xff {
			$index = $index + 1
		} else if $index + 1 >= bytes.len() {
			$error = Invalid(InvalidJpegSegment({ offset: $index, resource }))
		} else {
			next = list_at(bytes, $index + 1)
			if next == 0x00 or (next >= 0xd0 and next <= 0xd7) {
				$index = $index + 2
			} else if next == 0xff {
				$index = $index + 1
			} else {
				$done = True
			}
		}
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ next_marker: $index, output: append_range(output, bytes, start, $index) })
	}
}

inspect_exif_orientation : List(U8), U64, U64, U64 -> Try([Exif(Image.ExifOrientation), NoExif], KernelImage.Error)
inspect_exif_orientation = |bytes, start, length, resource| {
	tiff = start + 6
	end = start + length
	if end - tiff < 8 {
		Err(
			InvalidExif({
				resource: resource,
			}),
		)
	} else {
		little = list_at(bytes, tiff) == 0x49 and list_at(bytes, tiff + 1) == 0x49
		big = list_at(bytes, tiff) == 0x4d and list_at(bytes, tiff + 1) == 0x4d
		if (!little and !big) or read_u16_ordered(bytes, tiff + 2, little) != 42 {
			Err(
				InvalidExif({
					resource: resource,
				}),
			)
		} else {
			offset = read_u32_ordered(bytes, tiff + 4, little).to_u64()
			if offset > end - tiff or end - (tiff + offset) < 2 {
				Err(
					InvalidExif({
						resource: resource,
					}),
				)
			} else {
				ifd = tiff + offset
				count = read_u16_ordered(bytes, ifd, little).to_u64()
				table_bytes = match U64.times_try(count, 12) {
					Err(Overflow) => 0xffffffffffffffff
					Ok(value) => value
				}
				if table_bytes > end - (ifd + 2) {
					Err(
						InvalidExif({
							resource: resource,
						}),
					)
				} else {
					var $index = 0
					var $found = NoExif
					var $error = NoError
					while $index < count and $error == NoError {
						entry = ifd + 2 + $index * 12
						tag = read_u16_ordered(bytes, entry, little)
						if tag == 0x0112 {
							type = read_u16_ordered(bytes, entry + 2, little)
							items = read_u32_ordered(bytes, entry + 4, little)
							value = read_u16_ordered(bytes, entry + 8, little)
							if type != 3 or items != 1 or value < 1 or value > 8 or $found != NoExif {
								$error = Invalid(
									InvalidExif({
										resource: resource,
									}),
								)
							} else {
								$found = Exif(orientation_from_u16(value))
							}
						}
						$index = $index + 1
					}
					match $error {
						Invalid(error) => Err(error)
						NoError => Ok($found)
					}
				}
			}
		}
	}
}

resolve_orientation : [Exif(Image.ExifOrientation), NoExif], Image.OrientationPolicy, U64 -> Try(Image.OrientationEvidence, KernelImage.Error)
resolve_orientation = |orientation, policy, resource| match orientation {
	NoExif => Ok(NoExifOrientation)
	Exif(TopLeft) => match policy {
		ApplyBeforePlacement => Ok(Applied(TopLeft))
		RequireDisplayReady => Ok(ConfirmedDisplayReady)
	}
	Exif(_) => Err(
		OrientationRequiresTransform({
			resource: resource,
		}),
	)
}

orientation_from_u16 : U16 -> Image.ExifOrientation
orientation_from_u16 = |value| match value {
	1 => TopLeft
	2 => TopRight
	3 => BottomRight
	4 => BottomLeft
	5 => LeftTop
	6 => RightTop
	7 => RightBottom
	_ => LeftBottom
}

read_u16_be : List(U8), U64 -> U16
read_u16_be = |bytes, index| list_at(bytes, index).to_u16().shl_wrap(8).bitwise_or(list_at(bytes, index + 1).to_u16())

read_u16_ordered : List(U8), U64, Bool -> U16
read_u16_ordered = |bytes, index, little| if little list_at(bytes, index).to_u16().bitwise_or(list_at(bytes, index + 1).to_u16().shl_wrap(8)) else read_u16_be(bytes, index)

read_u32_ordered : List(U8), U64, Bool -> U32
read_u32_ordered = |bytes, index, little| if little list_at(bytes, index).to_u32()
	.bitwise_or(list_at(bytes, index + 1).to_u32().shl_wrap(8))
	.bitwise_or(list_at(bytes, index + 2).to_u32().shl_wrap(16))
	.bitwise_or(list_at(bytes, index + 3).to_u32().shl_wrap(24)) else list_at(bytes, index).to_u32().shl_wrap(24)
	.bitwise_or(list_at(bytes, index + 1).to_u32().shl_wrap(16))
	.bitwise_or(list_at(bytes, index + 2).to_u32().shl_wrap(8))
	.bitwise_or(list_at(bytes, index + 3).to_u32())

matches : List(U8), U64, List(U8) -> Bool
matches = |bytes, start, expected| {
	if start > bytes.len() or expected.len() > bytes.len() - start {
		False
	} else {
		var $index = 0
		var $matches = True
		while $index < expected.len() and $matches {
			if list_at(bytes, start + $index) != list_at(expected, $index) {
				$matches = False
			}
			$index = $index + 1
		}
		$matches
	}
}

append_range : List(U8), List(U8), U64, U64 -> List(U8)
append_range = |output, source, start, end| {
	var $output = output
	var $index = start
	while $index < end {
		$output = $output.append(list_at(source, $index))
		$index = $index + 1
	}
	$output
}

append_list : List(a), List(a) -> List(a)
append_list = |left, right| {
	var $output = left
	var $index = 0
	while $index < right.len() {
		$output = $output.append(list_at(right, $index))
		$index = $index + 1
	}
	$output
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

zero_u64 : U64
zero_u64 = 0

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated image index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated image update escaped"
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
test_limits = KernelImage.Limits.make({ max_decoded_bytes: 4, max_encoded_bytes: 32, max_height: 2, max_markers: 16, max_resources: 1, max_width: 2 })

jpeg_limits : KernelImage.Limits
jpeg_limits = KernelImage.Limits.make({ max_decoded_bytes: 4, max_encoded_bytes: 256, max_height: 2, max_markers: 16, max_resources: 1, max_width: 2 })

synthetic_jpeg : {} -> List(U8)
synthetic_jpeg = |_| {
	with_comment = append_list([0xff, 0xd8], [0xff, 0xfe, 0x00, 0x05, 1, 2, 3])
	quantization = append_list([0xff, 0xdb, 0x00, 0x43, 0x00], List.repeat(1, 64))
	with_quantization = append_list(with_comment, quantization)
	with_frame = append_list(with_quantization, [0xff, 0xc0, 0x00, 0x0b, 8, 0, 1, 0, 1, 1, 1, 0x11, 0])
	counts = append_list([1], List.repeat(0, 15))
	dc_table = append_list(append_list([0x00], counts), [0])
	ac_table = append_list(append_list([0x10], counts), [0])
	huffman = append_list([0xff, 0xc4, 0x00, 0x26], append_list(dc_table, ac_table))
	with_huffman = append_list(with_frame, huffman)
	with_scan = append_list(with_huffman, [0xff, 0xda, 0x00, 0x08, 1, 1, 0, 0, 0x3f, 0, 0])
	append_list(with_scan, [0xff, 0xd9])
}

synthetic_jpeg_with_exif : {} -> List(U8)
synthetic_jpeg_with_exif = |_| {
	base = synthetic_jpeg({})
	exif = [
		0xff,
		0xe1,
		0x00,
		0x22,
		0x45,
		0x78,
		0x69,
		0x66,
		0x00,
		0x00,
		0x49,
		0x49,
		0x2a,
		0x00,
		0x08,
		0x00,
		0x00,
		0x00,
		0x01,
		0x00,
		0x12,
		0x01,
		0x03,
		0x00,
		0x01,
		0x00,
		0x00,
		0x00,
		0x01,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
	]
	append_range(append_list([0xff, 0xd8], exif), base, 2, base.len())
}

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

## Zero raster dimensions are rejected before stride or payload arithmetic.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: PackedPixels({ ..test_raster, dimensions: { ..test_raster.dimensions, width: 0 } }) }] }

	match KernelImage.Plan.build(sources, colors, test_limits) {
		Err(InvalidDimensions({ height: 2, resource: 0, width: 0 })) => True
		_ => False
	}
}

## Supported JPEG markers are checked and irrelevant comments are stripped.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	input = synthetic_jpeg({})
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: input, color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] }
	plan = KernelImage.Plan.build(sources, colors, jpeg_limits)?
	store = KernelImage.Plan.store(plan)
	work = KernelImage.Plan.work(plan)
	resource = list_at(store.resources, 0)

	match resource.payload {
		Jpeg(jpeg) => jpeg.dimensions == { height: 1, width: 1 } and jpeg.components == One and jpeg.orientation == NoExifOrientation and jpeg.bytes.len() + 7 == input.len() and work.bytes_checked == input.len() and work.markers_checked == 7
		_ => False
	}
}

## Segment lengths are checked before any JPEG table access.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	bad = list_set(synthetic_jpeg({}), 11, 0xff)
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: bad, color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] }

	match KernelImage.Plan.build(sources, colors, jpeg_limits) {
		Err(InvalidJpegSegment(_)) => True
		_ => False
	}
}

## Top-left EXIF orientation becomes typed evidence and metadata is removed.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	input = synthetic_jpeg_with_exif({})
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: input, color_space: Color.SpaceId.from_index(0), orientation_policy: ApplyBeforePlacement }) }] }
	plan = KernelImage.Plan.build(sources, colors, jpeg_limits)?
	resource = list_at(KernelImage.Plan.store(plan).resources, 0)

	match resource.payload {
		Jpeg(jpeg) => jpeg.orientation == Applied(TopLeft) and jpeg.bytes.len() + 43 == input.len()
		_ => False
	}
}

## Encoded orientations needing pixel transforms never reach final placement.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	input = list_set(synthetic_jpeg_with_exif({}), 30, 6)
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: input, color_space: Color.SpaceId.from_index(0), orientation_policy: ApplyBeforePlacement }) }] }

	match KernelImage.Plan.build(sources, colors, jpeg_limits) {
		Err(OrientationRequiresTransform({ resource: 0 })) => True
		_ => False
	}
}

## Truncated JPEGs fail before marker inspection crosses input bounds.
expect {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits)?
	sources : Image.SourceStore
	sources = { resources: [{ id: Image.Id.from_index(0), payload: EncodedJpeg({ bytes: [0xff, 0xd8], color_space: Color.SpaceId.from_index(0), orientation_policy: RequireDisplayReady }) }] }

	match KernelImage.Plan.build(sources, colors, test_limits) {
		Err(InvalidJpegSegment({ offset: 0, resource: 0 })) => True
		_ => False
	}
}
