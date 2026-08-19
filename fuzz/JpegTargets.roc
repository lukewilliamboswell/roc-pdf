import pdf.Color
import pdf.Image
import pdf.KernelColor
import pdf.KernelImage
import pdf.KernelSrgbProfile
import "../tests/assets/jpeg-fuzz-corpus/gray-16x16.jpg" as gray_jpeg : List(U8)
import "../tests/assets/jpeg-fuzz-corpus/rgb-comment.jpg" as comment_jpeg : List(U8)
import "../tests/assets/jpeg-fuzz-corpus/rgb-exif-orientation-1.jpg" as exif_jpeg : List(U8)
import "../tests/assets/jpeg-fuzz-corpus/rgb-exif-orientation-6.jpg" as rotated_jpeg : List(U8)

JpegTargets :: [].{

	## Pass raw fuzzer bytes to the bounded JPEG inspector. Typed inspection
	## errors are ordinary outcomes. A successful inspection must produce a
	## sanitized stream: framed by SOI/EOI, never longer than its source,
	## carrying dimensions and work counters that stay inside the declared
	## limits, and retaining only the two application segments a decoder needs to
	## interpret the retained pixels. A self-identified JFIF APP0 carries the
	## pixel density and a self-identified Adobe APP14 carries the colour
	## transform, so both are copied through. Every other application segment,
	## an Exif APP1 above all, and every comment segment is metadata the
	## architecture forbids copying into a PDF image stream, so none of them may
	## survive into the output.
	##
	## The inspector matches a frame's component count against the declared
	## space and rejects a disagreement, so a single-space store would send
	## every three-component image down the reject path and leave the facts
	## below unevaluated for all but greyscale input. Both spaces are therefore
	## inspected: whichever one the frame agrees with reaches these invariants,
	## and the other contributes an ordinary typed rejection.
	jpeg_mutation : List(U8) -> Bool
	jpeg_mutation = |bytes| inspected_under(bytes, gray_space) and inspected_under(bytes, srgb_space)
}

inspected_under : List(U8), Color.SpaceId -> Bool
inspected_under = |bytes, space| match inspect_encoded_jpeg(bytes, space) {
	Err(ColorFailure) => False
	Err(Rejected) => True
	Ok(plan) => sanitized_jpeg_invariants(plan, bytes)
}

inspect_encoded_jpeg : List(U8), Color.SpaceId -> Try(KernelImage.Plan, [ColorFailure, Rejected])
inspect_encoded_jpeg = |bytes, space| {
	colors = KernelColor.Plan.build(color_store, color_limits) ? |_| ColorFailure
	sources : Image.SourceStore
	sources = {
		resources: [
			{
				id: Image.Id.from_index(0),
				payload: EncodedJpeg({
					bytes,
					color_space: space,
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

## The emitted stream keeps JPEG framing, never grows past its source, retains
## no comment segment, and retains an application segment only when it is the
## JFIF APP0 or the Adobe APP14 that `KernelImage` deliberately copies through.
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
		if marker == 0xfe {
			return False
		}

		## `KernelImage` drops every application segment except the two whose
		## payload a decoder needs to interpret the pixels it kept: a JFIF APP0
		## supplies the pixel density and an Adobe APP14 supplies the colour
		## transform. Both are retained only when the payload identifies itself
		## and is long enough to carry the fields that identification promises,
		## so repeat those conditions here instead of trusting the marker alone.
		## An Exif APP1 is read for its orientation and then dropped, so it must
		## never appear.
		if marker >= 0xe0 and marker <= 0xef {
			length_here = list_at(bytes, $index + 2).to_u64() * 256 + list_at(bytes, $index + 3).to_u64()
			data_here = $index + 4
			is_jfif = marker == 0xe0 and length_here >= 16 and matches_at(bytes, data_here, [0x4a, 0x46, 0x49, 0x46, 0x00])
			is_adobe = marker == 0xee and length_here >= 14 and matches_at(bytes, data_here, [0x41, 0x64, 0x6f, 0x62, 0x65])
			if !is_jfif and !is_adobe {
				return False
			}
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

## One store carrying both component counts the inspector accepts: a calibrated
## grey space for single-component frames and the packaged sRGB profile for
## three-component frames. A greyscale-only store was why sixteen of the
## seventeen corpus seeds could never reach the accept path.
color_store : Color.Store
color_store = {
	profiles: [KernelSrgbProfile.profile(0, 0)],
	spaces: [
		{
			id: gray_space,
			space: CalibratedGray({
				black_point: { x: 0, y: 0, z: 0 },
				white_point: { x: 950000, y: 1000000, z: 1089000 },
			}),
		},
		{ id: srgb_space, space: Srgb(Color.ProfileId.from_index(0)) },
	],
	tags: KernelSrgbProfile.tags,
}

color_limits : KernelColor.Limits
color_limits = KernelColor.Limits.make({
	max_icc_bytes: KernelSrgbProfile.byte_count,
	max_profiles: 1,
	max_spaces: 2,
	max_tags: KernelSrgbProfile.tag_count,
})

gray_space : Color.SpaceId
gray_space = Color.SpaceId.from_index(0)

srgb_space : Color.SpaceId
srgb_space = Color.SpaceId.from_index(1)

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

## Compare a pattern against the bytes at an offset. The offset is derived from
## a declared segment length, which a sanitized stream is free to end short of,
## so a pattern that does not fit is reported as absent rather than read past
## the end of the list.
matches_at : List(U8), U64, List(U8) -> Bool
matches_at = |bytes, offset, pattern| {
	if offset + pattern.len() > bytes.len() {
		return False
	}
	var $index = 0
	while $index < pattern.len() {
		if list_at(bytes, offset + $index) != list_at(pattern, $index) {
			return False
		}
		$index = $index + 1
	}
	True
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Err(OutOfBounds) => crash "fuzz property escaped a validated dense index"
	Ok(value) => value
}

## The sanitized bytes an accepted source produced, for expects that need to
## distinguish "the invariants held" from "the inspector rejected the input and
## the invariants were never evaluated". `jpeg_mutation` deliberately cannot
## tell those apart, because a typed rejection is an ordinary outcome under
## mutation; a replayed seed asserting a retention fact must.
emitted_stream : List(U8), Color.SpaceId -> [None, Some(List(U8))]
emitted_stream = |bytes, space| match inspect_encoded_jpeg(bytes, space) {
	Err(_) => None
	Ok(plan) => {
		store = KernelImage.Plan.store(plan)
		match list_at(store.resources, 0).payload {
			Raster(_) => None
			Jpeg(jpeg) => Some(jpeg.bytes)
		}
	}
}

## Replay the greyscale baseline seed. This is the exact input the property
## rejected before the JFIF exemption was written down: like every real JPEG it
## opens with a JFIF APP0 that `KernelImage` copies through, and the blanket
## rejection of every application segment failed on it immediately. Its
## single-component frame reaches the accept path through the calibrated-grey
## space. Without this expect the whole invariant block only runs under the
## fuzzer.
expect JpegTargets.jpeg_mutation(gray_jpeg)

## Replay a seed carrying an already-upright Exif APP1 orientation. Its
## three-component frame reaches the accept path through the sRGB space, so this
## replays the APP1-stripping half of the retention rule: the inspector reads
## the orientation, resolves it before placement, and must not leave the segment
## in the emitted stream.
expect JpegTargets.jpeg_mutation(exif_jpeg)

## Replay a seed whose Exif orientation would need the pixels rotated.
## `resolve_orientation` admits only `TopLeft`, because rotating pixels is
## rasterization and the package refuses it rather than recovering silently, so
## this source must be rejected outright under either space.
expect JpegTargets.jpeg_mutation(rotated_jpeg)

## Replay a seed carrying a COM segment, which the retention rule forbids in the
## output. It reaches the accept path through the same sRGB space, so it pins
## the comment-stripping half of the rule.
expect JpegTargets.jpeg_mutation(comment_jpeg)

## The three expects above would each pass if the inspector had merely rejected
## its seed, so they are paired with positive evidence that the accept path was
## actually taken. Each seed must produce a stream, and the two carrying a
## segment the rule strips must produce a strictly shorter one.
expect emitted_stream(gray_jpeg, gray_space) != None

expect match emitted_stream(exif_jpeg, srgb_space) {
	None => Bool.False
	Some(bytes) => bytes.len() < exif_jpeg.len()
}

expect match emitted_stream(comment_jpeg, srgb_space) {
	None => Bool.False
	Some(bytes) => bytes.len() < comment_jpeg.len()
}

## A three-component frame is admitted only by the sRGB space and a
## single-component frame only by the calibrated-grey one, which is the reason
## the store carries both. If this ever inverts, the seeds above would silently
## stop exercising the accept path while their expects kept passing.
expect emitted_stream(exif_jpeg, gray_space) == None

expect emitted_stream(gray_jpeg, srgb_space) == None

## The rotation-requiring seed is rejected for its orientation rather than its
## components, so neither space admits it. Pinning both directions keeps the
## refusal attributable: a future change that started accepting it would fail
## here instead of quietly widening what reaches the store.
expect emitted_stream(rotated_jpeg, srgb_space) == None

expect emitted_stream(rotated_jpeg, gray_space) == None
