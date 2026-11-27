import Color
import Image
import KernelImage
import KernelResourceRadix

KernelFacadeImages :: [].{

	## The original ordinal remains available for diagnostics. The alias table
	## maps every image command to its canonical resource in first-use order.
	Inputs : { ordinals : List(U64), sources : Image.SourceStore }
	Work : { candidate_hashes : U64, candidate_bytes_hashed : U64, comparison_bytes : U64, recent_matches : U64, radix_byte_visits : U64 }
	Dimension : [HashBytes, ComparisonBytes, OlderComparisonBytes]
	Error : [WorkLimit({ attempted : U64, dimension : Dimension, limit : U64, resource : U64 })]
	Sharing : { aliases : List(Image.Id), inputs : Inputs, work : Work }

	share : Image.SourceStore -> Try(Sharing, Error)
	share = |sources| share_with_budgets(sources, Image.Budgets.default)

	## Exact work counts combine four comparison lanes. Radix refinement
	## contributes at most three visits per byte charged to the hash budget.
	identity_work_ceiling : U64
	identity_work_ceiling = U64.highest // 4

	share_with_budgets : Image.SourceStore, Image.Budgets -> Try(Sharing, Error)
	share_with_budgets = |sources, budgets| {
		if sources.resources.len() <= 1 {
			return Ok(unchanged(sources, empty_work))
		}
		share_sources(sources, Production, budgets, identity_work_limits(budgets))
	}

	image_at : List(Image.Id), U64 -> Image.Id
	image_at = |aliases, ordinal| {
		if aliases.is_empty() {
			Image.Id.from_index(ordinal)
		} else {
			list_at(aliases, ordinal)
		}
	}
}

empty_work : KernelFacadeImages.Work
empty_work = { candidate_hashes: 0, candidate_bytes_hashed: 0, comparison_bytes: 0, recent_matches: 0, radix_byte_visits: 0 }

unchanged : Image.SourceStore, KernelFacadeImages.Work -> KernelFacadeImages.Sharing
unchanged = |sources, work| { aliases: [], inputs: { ordinals: [], sources }, work }

SourcePlanes : {
	bytes : List(U8),
	alpha : List(U8),
	descriptor : (U64, U64, U64, U64, U64, U64),
}

is_jpeg : Image.SourceResource -> Bool
is_jpeg = |source| match source.payload {
	EncodedJpeg(_) => True
	PackedPixels(_) => False
}

admissible : Image.SourceResource, Image.Budgets -> Bool
admissible = |source, budgets| match source.payload {
	PackedPixels(raster) => KernelImage.admits_facade_raster(raster, budgets)
	EncodedJpeg(jpeg) => KernelImage.admits_facade_jpeg(jpeg, budgets)
}

source_planes : Image.SourceResource -> SourcePlanes
source_planes = |source| match source.payload {
	PackedPixels(raster) => {
		{ bytes, stride } = raster_alpha(raster)
		{ bytes: raster.pixels, alpha: bytes, descriptor: raster_descriptor(raster, stride) }
	}
	EncodedJpeg(jpeg) => {
		format = match jpeg.orientation_policy {
			RequireDisplayReady => 4
			ApplyBeforePlacement => 5
		}
		{ bytes: jpeg.bytes, alpha: [], descriptor: (0, 0, jpeg.color_space.index(), 0, format, 0) }
	}
}

## The format field distinguishes gray and RGB rasters with or without alpha
## from JPEG sources under either orientation policy. JPEG dimensions are
## derived later by inspection. Plane lengths partition collision buckets.
Key : {
	fields : List(U64),
	lengths : (U64, U64),
}

Candidate : { key : Key, ordinal : U64 }

Fingerprint : { value : U64, ordinal : U64 }

DigestPolicy : [Production, ForceCollision]

WorkLimits : { max_hash_bytes : U64, max_comparison_bytes : U64 }

## Placed source comparisons have a separate budget from physical byte
## storage. The candidate budget also bounds radix and adjacent equality
## work, since each candidate participates in at most one collision bucket.
identity_work_limits : Image.Budgets -> WorkLimits
identity_work_limits = |budgets| {
	max_hash_bytes: budgets.max_identity_hash_bytes,
	max_comparison_bytes: budgets.max_identity_comparison_bytes,
}

share_sources : Image.SourceStore, DigestPolicy, Image.Budgets, WorkLimits -> Try(KernelFacadeImages.Sharing, KernelFacadeImages.Error)
share_sources = |sources, policy, budgets, limits| {
	count = sources.resources.len()
	var $leaders = List.with_capacity(count)
	var $candidates = []
	empty_history = { recent: count, older: count, comparison_bytes: 0, older_comparison_bytes: 0 }
	var $raster_history = empty_history
	var $jpeg_history = empty_history
	var $recent_matches = 0
	var $eligible = True
	var $ordinal = 0
	while $ordinal < count {
		source = list_at(sources.resources, $ordinal)
		if !$eligible or !admissible(source, budgets) {
			$leaders = $leaders.append($ordinal)
			$eligible = False
		} else {
			current = source_planes(source)
			plane_bytes = current.bytes.len() + current.alpha.len()
			jpeg = is_jpeg(source)
			history = if (jpeg) $jpeg_history else $raster_history
			var $comparison_bytes = history.comparison_bytes
			var $older_comparison_bytes = history.older_comparison_bytes
			var $leader = count
			var $probe = history.recent
			while $leader == count and $probe < count {
				previous = planes_at(sources, $probe)
				if same_layout(current, previous) {
					if $probe == history.recent {
						$comparison_bytes = $comparison_bytes.plus_saturated(plane_bytes)
						if $comparison_bytes > limits.max_comparison_bytes {
							return Err(WorkLimit({ attempted: $comparison_bytes, dimension: ComparisonBytes, limit: limits.max_comparison_bytes, resource: $ordinal }))
						}
					} else {
						$older_comparison_bytes = $older_comparison_bytes.plus_saturated(plane_bytes)
						if $older_comparison_bytes > limits.max_comparison_bytes {
							return Err(WorkLimit({ attempted: $older_comparison_bytes, dimension: OlderComparisonBytes, limit: limits.max_comparison_bytes, resource: $ordinal }))
						}
					}
					if exact_planes(current, previous) {
						$leader = $probe
					}
				}
				$probe = if ($probe == history.recent) history.older else count
			}
			if $leader == count {
				$candidates = $candidates.append({ key: sample_key(current, policy), ordinal: $ordinal })
				$leader = $ordinal
			} else {
				$recent_matches = $recent_matches + 1
			}
			updated = {
				recent: $leader,
				older: if ($leader == history.recent) history.older else history.recent,
				comparison_bytes: $comparison_bytes,
				older_comparison_bytes: $older_comparison_bytes,
			}
			if jpeg {
				$jpeg_history = updated
			} else {
				$raster_history = updated
			}
			$leaders = $leaders.append($leader)
		}
		$ordinal = $ordinal + 1
	}
	ordered = $candidates.sort_with(
		|left, right| {
			order = compare_fields(left.key.fields, right.key.fields)
			if (order == Same) left.ordinal.order_relative_to(right.ordinal) else order
		},
	)
	var $candidate_hashes = 0
	var $candidate_bytes = 0
	var $radix_byte_visits = 0
	var $start = 0
	while $start < ordered.len() {
		first = list_at(ordered, $start)
		var $end = $start + 1
		while $end < ordered.len() and list_at(ordered, $end).key == first.key {
			$end = $end + 1
		}
		if $end - $start > 1 {
			(color_len, alpha_len) = first.key.lengths
			length = color_len + alpha_len

			## Charge the whole bucket before hashing any input in it. The byte
			## bound also covers the exact refinement that can follow the digest.
			$candidate_bytes = $candidate_bytes.plus_saturated(($end - $start).times_saturated(length))
			if $candidate_bytes > limits.max_hash_bytes {
				return Err(WorkLimit({ attempted: $candidate_bytes, dimension: HashBytes, limit: limits.max_hash_bytes, resource: first.ordinal }))
			}
			$candidate_hashes = $candidate_hashes + ($end - $start)
			fingerprints = fingerprint_bucket(sources, ordered, $start, $end, policy)
			var $fingerprint_start = 0
			while $fingerprint_start < fingerprints.len() {
				value = list_at(fingerprints, $fingerprint_start).value
				var $fingerprint_end = $fingerprint_start + 1
				while $fingerprint_end < fingerprints.len() and list_at(fingerprints, $fingerprint_end).value == value {
					$fingerprint_end = $fingerprint_end + 1
				}
				if $fingerprint_end - $fingerprint_start > 1 {
					classes = exact_classes(sources, fingerprints, $fingerprint_start, $fingerprint_end, first.key.lengths)
					$radix_byte_visits = $radix_byte_visits + classes.radix_byte_visits
					for { ordinal, leader } in classes.members {
						$leaders = list_set($leaders, ordinal, leader)
					}
				}
				$fingerprint_start = $fingerprint_end
			}
		}
		$start = $end
	}
	comparison_bytes = $jpeg_history.comparison_bytes + $jpeg_history.older_comparison_bytes + $raster_history.comparison_bytes + $raster_history.older_comparison_bytes
	work = { candidate_hashes: $candidate_hashes, candidate_bytes_hashed: $candidate_bytes, comparison_bytes, recent_matches: $recent_matches, radix_byte_visits: $radix_byte_visits }
	if $leaders.fold_with_index_until(True, |_, leader, ordinal| if (leader == ordinal) Continue(True) else Break(False)) {
		return Ok(unchanged(sources, work))
	}
	var $aliases = List.with_capacity(count)
	var $ordinals = []
	var $resources = []
	$ordinal = 0
	while $ordinal < count {
		leader = list_at($leaders, $ordinal)
		if leader == $ordinal {
			id = Image.Id.from_index($resources.len())
			$aliases = $aliases.append(id)
			$ordinals = $ordinals.append($ordinal)
			$resources = $resources.append({ id, payload: list_at(sources.resources, $ordinal).payload })
		} else {
			id = list_at($aliases, leader)
			$aliases = $aliases.append(id)
		}
		$ordinal = $ordinal + 1
	}
	Ok({ aliases: $aliases, inputs: { ordinals: $ordinals, sources: { resources: $resources } }, work })
}

## Fixed-width samples only reject unequal candidates. Their contents are
## never accepted as proof that payloads match. Read up to three lanes from
## each plane, without making byte slices or allocating a digest.
sample_key : SourcePlanes, DigestPolicy -> Key
sample_key = |planes, policy| {
	(width, height, space, row_stride, format, alpha_stride) = planes.descriptor
	color_len = planes.bytes.len()
	alpha_len = planes.alpha.len()
	(head, middle, tail, alpha_head, alpha_middle, alpha_tail) = match policy {
		Production => {
			(a, b, c) = sample(planes.bytes)
			(d, e, f) = sample(planes.alpha)
			(a, b, c, d, e, f)
		}
		ForceCollision => (0, 0, 0, 0, 0, 0)
	}
	{ fields: [width, height, space, row_stride, format, alpha_stride, color_len, alpha_len, head, middle, tail, alpha_head, alpha_middle, alpha_tail], lengths: (color_len, alpha_len) }
}

sample : List(U8) -> (U64, U64, U64)
sample = |bytes| {
	length = bytes.len()
	if length >= 8 {
		last = length - 8
		(read_lane(bytes, 0), read_lane(bytes, last // 2), read_lane(bytes, last))
	} else {
		var $head = 0
		for byte in bytes {
			$head = $head.shl_wrap(8).bitwise_or(byte.to_u64())
		}
		($head, 0, 0)
	}
}

read_lane : List(U8), U64 -> U64
read_lane = |bytes, offset| U64.from_le_bytes(bytes, offset) ?? crash "image sample escaped its plane"

fingerprint_bucket : Image.SourceStore, List(Candidate), U64, U64, DigestPolicy -> List(Fingerprint)
fingerprint_bucket = |sources, ordered, start, end, policy| {
	var $fingerprints = List.with_capacity(end - start)
	var $position = start
	while $position < end {
		ordinal = list_at(ordered, $position).ordinal
		value = fingerprint(planes_at(sources, ordinal), policy)
		$fingerprints = $fingerprints.append({ ordinal, value })
		$position = $position + 1
	}
	$fingerprints.sort_with(
		|left, right| {
			order = left.value.order_relative_to(right.value)
			if (order == Same) left.ordinal.order_relative_to(right.ordinal) else order
		},
	)
}

fingerprint : SourcePlanes, DigestPolicy -> U64
fingerprint = |planes, policy| match policy {
	Production => {
		digest = if planes.alpha.is_empty() {
			Crypto.SHA256.hash(planes.bytes)
		} else {
			Crypto.SHA256.Hasher.empty().write(planes.bytes).write(planes.alpha).finish()
		}
		read_lane(digest.to_bytes(), 0)
	}
	ForceCollision => 0
}

compare_fields : List(U64), List(U64) -> [Before, Same, After]
compare_fields = |left, right| {
	var $index = 0
	while $index < left.len() {
		order = list_at(left, $index).order_relative_to(list_at(right, $index))
		if order != Same {
			return order
		}
		$index = $index + 1
	}
	Same
}

raster_descriptor : Image.PackedRaster, U64 -> (U64, U64, U64, U64, U64, U64)
raster_descriptor = |raster, alpha_stride| {
	format = match raster.format {
		Gray8 => 0
		Rgb8 => 1
	}
	alpha = match raster.alpha {
		NoAlpha => 0
		PackedAlpha(_) => 2
	}
	(raster.dimensions.width.to_u64(), raster.dimensions.height.to_u64(), raster.color_space.index(), raster.row_stride, format + alpha, alpha_stride)
}

raster_alpha : Image.PackedRaster -> { bytes : List(U8), stride : U64 }
raster_alpha = |raster| match raster.alpha {
	NoAlpha => { bytes: [], stride: 0 }
	PackedAlpha({ bytes, row_stride }) => { bytes, stride: row_stride }
}

same_layout : SourcePlanes, SourcePlanes -> Bool
same_layout = |left, right| left.descriptor == right.descriptor and left.bytes.len() == right.bytes.len() and left.alpha.len() == right.alpha.len()

exact_planes : SourcePlanes, SourcePlanes -> Bool
exact_planes = |left, right| equal_bytes(left.bytes, right.bytes) and equal_bytes(left.alpha, right.alpha)

## The equal-length comparison skips digest work when a drawing reuses the
## recent candidate. SIMD narrows the byte walk without allocating slices.
equal_bytes : List(U8), List(U8) -> Bool
equal_bytes = |left, right| {
	length = left.len()
	if length != right.len() {
		return False
	}
	var $index = 0
	while $index < length.minus_saturated(15) {
		if U8x16.load(left, $index) != U8x16.load(right, $index) {
			return False
		}
		$index = $index + 16
	}
	while $index < length {
		if list_at(left, $index) != list_at(right, $index) {
			return False
		}
		$index = $index + 1
	}
	True
}

## Sorting the fixed descriptor and hash key breaks ties by source ordinal.
## Bytewise radix
## refinement preserves input order for exact matches within a collision
## bucket, so adjacent equality can select the lowest original ordinal.
exact_classes : Image.SourceStore, List(Fingerprint), U64, U64, (U64, U64) -> { members : List({ leader : U64, ordinal : U64 }), radix_byte_visits : U64 }
exact_classes = |sources, ordered, start, end, (color_len, alpha_len)| {
	first = list_at(ordered, start)
	first_raster = planes_at(sources, first.ordinal)
	var $position = start + 1
	while $position < end and exact_planes(first_raster, planes_at(sources, list_at(ordered, $position).ordinal)) {
		$position = $position + 1
	}
	if $position == end {
		return { members: ordered.sublist({ start, len: end - start }).map(|candidate| { leader: first.ordinal, ordinal: candidate.ordinal }), radix_byte_visits: 0 }
	}
	refined = KernelResourceRadix.order(
		start,
		end,
		color_len + alpha_len,
		|member, offset| {
			planes = planes_at(sources, list_at(ordered, member).ordinal)
			if offset < color_len {
				list_at(planes.bytes, offset)
			} else {
				list_at(planes.alpha, offset - color_len)
			}
		},
	)
	var $leader = list_at(ordered, list_at(refined.order, 0)).ordinal
	var $classes = List.with_capacity(end - start)
	for member in refined.order {
		ordinal = list_at(ordered, member).ordinal
		if !exact_planes(planes_at(sources, $leader), planes_at(sources, ordinal)) {
			$leader = ordinal
		}
		$classes = $classes.append({ leader: $leader, ordinal })
	}
	{ members: $classes, radix_byte_visits: refined.byte_visits }
}

planes_at : Image.SourceStore, U64 -> SourcePlanes
planes_at = |sources, ordinal| source_planes(list_at(sources.resources, ordinal))

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "facade image index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => crash "facade image update escaped"
}

test_raster : U64, List(U8) -> Image.SourceResource
test_raster = |ordinal, alpha| {
	id: Image.Id.from_index(ordinal),
	payload: PackedPixels({
		alpha: PackedAlpha({ bytes: alpha, row_stride: 2 }),
		color_space: Color.SpaceId.from_index(0),
		dimensions: { width: 2, height: 1 },
		format: Rgb8,
		pixels: [30, 60, 90, 120, 150, 180],
		row_stride: 6,
	}),
}

# A nonadjacent repeat still belongs to the lowest original ordinal. Two
# rasters with identical color planes and different alpha never merge.
expect {
	sources = { resources: [test_raster(0, [0, 255]), test_raster(1, [0, 255]), test_raster(2, [255, 0]), test_raster(3, [0, 255])] }
	shared = KernelFacadeImages.share(sources)?
	shared.aliases.map(|id| id.index()) == [0, 0, 1, 0]
		and shared.inputs.ordinals == [0, 2]
		and shared.work == { candidate_hashes: 0, candidate_bytes_hashed: 0, comparison_bytes: 32, recent_matches: 2, radix_byte_visits: 0 }
}

# Deliberately place both distinct payloads in one fingerprint bucket. The
# radix path keeps byte-equal resources in authored order even when the byte
# ordering of the two distinct alpha planes reverses first-source order.
expect {
	sources = { resources: [test_raster(0, [255, 0]), test_raster(1, [0, 255]), test_raster(2, [160, 160]), test_raster(3, [255, 0]), test_raster(4, [0, 255]), test_raster(5, [160, 160])] }
	shared = share_sources(sources, ForceCollision, Image.Budgets.default, identity_work_limits(Image.Budgets.default))?
	shared.aliases.map(|id| id.index()) == [0, 1, 2, 0, 1, 2]
		and shared.inputs.ordinals == [0, 1, 2]
		and shared.work.radix_byte_visits > 0
}

# Malformed lengths never enter byte matching. Validation in the next stage
# still sees the authored diagnostic ordinal after an earlier duplicate.
expect {
	sources = { resources: [test_raster(0, [0, 255]), test_raster(1, [0, 255]), test_raster(2, List.repeat(0, 1024))] }
	shared = KernelFacadeImages.share(sources)?
	shared.aliases.map(|id| id.index()) == [0, 0, 1]
		and shared.inputs.ordinals == [0, 2]
		and shared.work.candidate_bytes_hashed == 0
}

# Reject before reading either over-budget candidate, with its original
# source ordinal and candidate work dimension intact.
expect {
	a = test_raster(0, [0, 255])
	repeated = { resources: [a, test_raster(1, [0, 255])] }
	distinct = { resources: [a, test_raster(1, [255, 0])] }
	hash_limit = match share_sources(distinct, ForceCollision, Image.Budgets.default, { max_hash_bytes: 8, max_comparison_bytes: 8 }) {
		Err(WorkLimit({ attempted: 16, dimension: HashBytes, limit: 8, resource: 0 })) => True
		_ => False
	}
	comparison_limit = match share_sources(repeated, Production, Image.Budgets.default, { max_hash_bytes: 8, max_comparison_bytes: 0 }) {
		Err(WorkLimit({ attempted: 8, dimension: ComparisonBytes, limit: 0, resource: 1 })) => True
		_ => False
	}
	hash_limit and comparison_limit
}

# Identical JPEG bytes under different orientation policies keep distinct
# source identities. A nonadjacent twin shares the first source's ID.
expect {
	jpeg = |ordinal, orientation_policy| {
		id: Image.Id.from_index(ordinal),
		payload: EncodedJpeg({ bytes: [0xff, 0xd8, 0xff, 0xd9], color_space: Color.SpaceId.from_index(0), orientation_policy }),
	}
	sources = { resources: [jpeg(0, RequireDisplayReady), jpeg(1, ApplyBeforePlacement), jpeg(2, RequireDisplayReady)] }
	shared = share_sources(sources, ForceCollision, Image.Budgets.default, identity_work_limits(Image.Budgets.default))?
	shared.aliases.map(|id| id.index()) == [0, 1, 0]
		and shared.inputs.ordinals == [0, 1]
		and shared.work.radix_byte_visits == 0
}

# Distinct source stamps in the first eight bytes bypass full hashing
# and exact classification even when the rest of every plane matches.
expect {
	base = List.repeat(0, 64)
	var $resources = List.with_capacity(64)
	var $ordinal = 0
	while $ordinal < 64 {
		pixels = list_set(base, 0, $ordinal.to_u8_wrap())
		$resources = $resources.append({
			id: Image.Id.from_index($ordinal),
			payload: PackedPixels({
				alpha: NoAlpha,
				color_space: Color.SpaceId.from_index(0),
				dimensions: { width: 64, height: 1 },
				format: Gray8,
				pixels,
				row_stride: 64,
			}),
		})
		$ordinal = $ordinal + 1
	}
	shared = KernelFacadeImages.share({ resources: $resources })?
	shared.aliases.is_empty()
		and shared.work.candidate_hashes == 0
		and shared.work.candidate_bytes_hashed == 0
		and shared.work.comparison_bytes == 8000
		and shared.work.radix_byte_visits == 0
}

# These otherwise distinct planes vary in a byte outside all three samples.
# The complete digest and exact equality still resolve a repeat through its
# first authored ordinal even when it has left the recent window.
expect {
	gray = |ordinal, shade| {
		pixels = list_set(List.repeat(0, 32), 9, shade)
		{
			id: Image.Id.from_index(ordinal),
			payload: PackedPixels({ alpha: NoAlpha, color_space: Color.SpaceId.from_index(0), dimensions: { width: 32, height: 1 }, format: Gray8, pixels, row_stride: 32 }),
		}
	}
	sources = { resources: [gray(0, 80), gray(1, 40), gray(2, 20), gray(3, 80)] }
	shared = KernelFacadeImages.share_with_budgets(sources, { max_identity_hash_bytes: 128 })?
	low = match KernelFacadeImages.share_with_budgets(sources, { max_identity_hash_bytes: 127 }) {
		Err(WorkLimit({ attempted: 128, dimension: HashBytes, limit: 127, resource: 0 })) => True
		_ => False
	}
	shared.aliases.map(|id| id.index()) == [0, 1, 2, 0]
		and shared.inputs.ordinals == [0, 1, 2]
		and shared.work.candidate_hashes == 4
		and shared.work.candidate_bytes_hashed == 128
		and low
}

# A missing first marker after SOI never enters candidate matching.
expect {
	bad_source = |ordinal| {
		id: Image.Id.from_index(ordinal),
		payload: EncodedJpeg({
			bytes: [0xff, 0xd8, 0, 0],
			color_space: Color.SpaceId.from_index(0),
			orientation_policy: RequireDisplayReady,
		}),
	}
	sources = { resources: [bad_source(0), bad_source(1)] }
	shared = KernelFacadeImages.share(sources)?
	shared.aliases.is_empty() and shared.work.candidate_bytes_hashed == 0
}

# The extra lookup has its own allowance. Accept A/B/A even when the two
# most-recent comparisons have used up the original allowance.
expect {
	sources = { resources: [test_raster(0, [0, 255]), test_raster(1, [255, 0]), test_raster(2, [0, 255])] }
	shared = share_sources(sources, Production, Image.Budgets.default, { max_hash_bytes: 0, max_comparison_bytes: 16 })?
	shared.aliases.map(|id| id.index()) == [0, 1, 0]
		and shared.work.comparison_bytes == 24
		and shared.work.candidate_hashes == 0
}

# Two recent JPEGs must not evict a repeatedly placed raster. Raster and
# JPEG comparisons also have independent work allowances.
expect {
	jpeg = |ordinal, end_marker| {
		id: Image.Id.from_index(ordinal),
		payload: EncodedJpeg({
			bytes: [0xff, 0xd8, 0xff, end_marker],
			color_space: Color.SpaceId.from_index(0),
			orientation_policy: RequireDisplayReady,
		}),
	}
	sources = {
		resources: [
			test_raster(0, [0, 255]),
			jpeg(1, 0xd9),
			jpeg(2, 0xe0),
			test_raster(3, [0, 255]),
			jpeg(4, 0xd9),
			jpeg(5, 0xe0),
			test_raster(6, [0, 255]),
		],
	}
	shared = share_sources(sources, Production, Image.Budgets.default, { max_hash_bytes: 0, max_comparison_bytes: 16 })?
	shared.aliases.map(|id| id.index()) == [0, 1, 2, 0, 1, 2, 0]
		and shared.work.comparison_bytes == 36
		and shared.work.candidate_hashes == 0
}

# A larger admitted raster can share at its exact comparison budget. The
# default width and a lower work cap reject in their respective stages.
expect {
	width = Image.Budgets.default.max_width + 1
	length = width.to_u64()
	raster = {
		alpha: NoAlpha,
		color_space: Color.SpaceId.from_index(0),
		dimensions: { width, height: 1 },
		format: Gray8,
		pixels: List.repeat(0, length),
		row_stride: length,
	}
	sources = { resources: [0, 1].map(|index| { id: Image.Id.from_index(index), payload: PackedPixels(raster) }) }
	default = KernelFacadeImages.share(sources)?
	wide_budget = Image.Budgets.{ max_width: width, max_identity_comparison_bytes: length }
	shared = KernelFacadeImages.share_with_budgets(sources, wide_budget)?
	low = match KernelFacadeImages.share_with_budgets(sources, { max_width: width, max_identity_comparison_bytes: length - 1 }) {
		Err(WorkLimit({ attempted, dimension: ComparisonBytes, limit, resource: 1 })) => attempted == length and limit == length - 1
		_ => False
	}
	default.aliases.is_empty() and shared.aliases.map(|id| id.index()) == [0, 0] and shared.work.comparison_bytes == length and low
}
