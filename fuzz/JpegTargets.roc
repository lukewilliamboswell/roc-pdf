import pdf.Color
import pdf.Image
import pdf.KernelColor
import pdf.KernelImage

JpegTargets :: [].{

	## Pass raw fuzzer bytes to the bounded JPEG inspector. Typed inspection
	## errors are ordinary outcomes. A successful inspection must produce a
	## sanitized stream: framed by SOI/EOI, never longer than its source, free of
	## the application and comment metadata the architecture forbids copying into
	## a PDF image stream, and carrying dimensions and work counters that stay
	## inside the declared limits.
	jpeg_mutation : List(U8) -> Bool
	jpeg_mutation = |bytes| match inspect_encoded_jpeg(bytes) {
		Err(ColorFailure) => False
		Err(Rejected) => True
		Ok(plan) => sanitized_jpeg_invariants(plan, bytes)
	}
}

inspect_encoded_jpeg : List(U8) -> Try(KernelImage.Plan, [ColorFailure, Rejected])
inspect_encoded_jpeg = |bytes| {
	colors = KernelColor.Plan.build(gray_color_store, gray_color_limits) ? |_| ColorFailure
	sources : Image.SourceStore
	sources = {
		resources: [
			{
				id: Image.Id.from_index(0),
				payload: EncodedJpeg({
					bytes,
					color_space: Color.SpaceId.from_index(0),
					orientation_policy: ApplyBeforePlacement,
				}),
			},
		],
	}
	plan = KernelImage.Plan.build(sources, colors, jpeg_limits) ? |_| Rejected
	Ok(plan)
}

sanitized_jpeg_invariants : KernelImage.Plan, List(U8) -> Bool
sanitized_jpeg_invariants = |plan, source| {
	store = KernelImage.Plan.store(plan)
	work = KernelImage.Plan.work(plan)
	if store.resources.len() != 1 or
		work.resource_visits != 1 or
			work.bytes_checked != source.len() or
				work.markers_checked > jpeg_marker_limit {
		return False
	}
	resource = list_at(store.resources, 0)
	match resource.payload {
		Raster(_) => False
		Jpeg(jpeg) => {
			if jpeg.dimensions.height == 0 or
				jpeg.dimensions.width == 0 or
					jpeg.dimensions.height > jpeg_max_height or
						jpeg.dimensions.width > jpeg_max_width {
				return False
			}

			## An inspected orientation is resolved before placement; a source that
			## would still need a pixel transform must never reach the store.
			match jpeg.orientation {
				Applied(_) => {}
				NoExifOrientation => {}
				_ => return False
			}
			sanitized_stream(jpeg.bytes, source.len())
		}
	}
}

## The emitted stream keeps JPEG framing, never grows past its source, and
## retains no application or comment segment.
sanitized_stream : List(U8), U64 -> Bool
sanitized_stream = |bytes, source_length| {
	if bytes.len() > source_length or bytes.len() < 4 {
		return False
	}
	if list_at(bytes, 0) != 0xff or
		list_at(bytes, 1) != 0xd8 or
			list_at(bytes, bytes.len() - 2) != 0xff or
				list_at(bytes, bytes.len() - 1) != 0xd9 {
		return False
	}

	## Walk segment headers rather than scanning every byte: a quantization or
	## Huffman payload may legitimately contain a marker-looking pair, and a
	## byte scan would report that as a retained segment.
	var $index = 2
	while $index + 3 < bytes.len() {
		if list_at(bytes, $index) != 0xff {
			return False
		}
		marker = list_at(bytes, $index + 1)
		if marker == 0xfe or (marker >= 0xe0 and marker <= 0xef) {
			return False
		}

		## Entropy-coded scan data and the end marker carry no further headers.
		if marker == 0xda or marker == 0xd9 {
			return True
		}
		length = list_at(bytes, $index + 2).to_u64() * 256 + list_at(bytes, $index + 3).to_u64()

		## An inspected stream always declares a segment length that stays inside
		## the payload; stop conservatively rather than claim a violation.
		if length < 2 or $index + 2 + length > bytes.len() {
			return True
		}
		$index = $index + 2 + length
	}
	True
}

gray_color_store : Color.Store
gray_color_store = {
	profiles: [],
	spaces: [
		{
			id: Color.SpaceId.from_index(0),
			space: CalibratedGray({
				black_point: { x: 0, y: 0, z: 0 },
				white_point: { x: 950000, y: 1000000, z: 1089000 },
			}),
		},
	],
	tags: [],
}

gray_color_limits : KernelColor.Limits
gray_color_limits = KernelColor.Limits.make({ max_icc_bytes: 0, max_profiles: 0, max_spaces: 1, max_tags: 0 })

jpeg_limits : KernelImage.Limits
jpeg_limits = KernelImage.Limits.make({
	max_decoded_bytes: 16777216,
	max_encoded_bytes: 65536,
	max_height: jpeg_max_height,
	max_markers: jpeg_marker_limit,
	max_resources: 1,
	max_width: jpeg_max_width,
})

jpeg_marker_limit : U64
jpeg_marker_limit = 256

jpeg_max_height : U32
jpeg_max_height = 4096

jpeg_max_width : U32
jpeg_max_width = 4096

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}
