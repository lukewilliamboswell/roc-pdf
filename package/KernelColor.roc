import Color
import Semantics

KernelColor :: [].{
	Dimension : [IccBytes, IccProfiles, IccTags, Spaces]
	Error : [
		ArithmeticOverflow,
		ComponentMismatch({ profile : U64 }),
		DeclaredSizeMismatch({ actual : U64, declared : U64, profile : U64 }),
		DuplicateTagOwnership({ tag : U64 }),
		IndexOutOfRange({ available : U64, index : U64 }),
		InvalidCalibratedGray({ space : U64 }),
		InvalidIccSignature({ profile : U64 }),
		LimitExceeded({ attempted : U64, dimension : Dimension, limit : U64 }),
		NonDenseSpaceIdentity({ actual : U64, expected : U64 }),
		NonDenseProfileIdentity({ actual : U64, expected : U64 }),
		OrphanTag({ tag : U64 }),
		ProfileTooShort({ bytes : U64, profile : U64 }),
		SpanOutOfRange({ available : U64, length : U64, owner : U64, start : U64 }),
		TagRecordMismatch({ profile : U64, tag : U64 }),
		UnsupportedIccVersion({ profile : U64, version : U8 }),
	]

	Limits :: { max_icc_bytes : U64, max_profiles : U64, max_spaces : U64, max_tags : U64 }.{
		make : { max_icc_bytes : U64, max_profiles : U64, max_spaces : U64, max_tags : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Work : { bytes_checked : U64, profile_visits : U64, space_visits : U64, tag_edges_checked : U64, tags_checked : U64 }

	Plan :: { components : List(Color.ComponentCount), store : Color.Store, work : Work }.{
		build : Color.Store, Limits -> Try(Plan, Error)
		build = |store, limits| build_plan(store, limits)

		components : Plan, Color.SpaceId -> Color.ComponentCount
		components = |plan, space| list_at(plan.components, space.index())

		space_count : Plan -> U64
		space_count = |plan| plan.components.len()

		store : Plan -> Color.Store
		store = |plan| plan.store

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : Color.Store, KernelColor.Limits -> Try(KernelColor.Plan, KernelColor.Error)
build_plan = |store, limits| {
	check_limit(store.profiles.len(), limits.max_profiles, IccProfiles)?
	check_limit(store.spaces.len(), limits.max_spaces, Spaces)?
	check_limit(store.tags.len(), limits.max_tags, IccTags)?
	profiles = validate_profiles(store, limits.max_icc_bytes)?
	spaces = validate_spaces(store)?
	Ok(
		KernelColor.Plan.{
			components: spaces.components,
			store,
			work: {
				bytes_checked: profiles.bytes_checked,
				profile_visits: store.profiles.len(),
				space_visits: store.spaces.len(),
				tag_edges_checked: profiles.tag_edges_checked,
				tags_checked: store.tags.len(),
			},
		},
	)
}

validate_profiles : Color.Store, U64 -> Try({ bytes_checked : U64, tag_edges_checked : U64 }, KernelColor.Error)
validate_profiles = |store, max_bytes| {
	var $tag_owners = List.repeat(0, store.tags.len())
	var $profile_index = 0
	var $total_bytes = 0
	var $tag_edges = 0
	var $error = NoError
	while $profile_index < store.profiles.len() and $error == NoError {
		profile = list_at(store.profiles, $profile_index)
		if profile.id.index() != $profile_index {
			$error = Invalid(NonDenseProfileIdentity({ actual: profile.id.index(), expected: $profile_index }))
		}
		$total_bytes = match U64.plus_try($total_bytes, profile.bytes.len()) {
			Err(Overflow) => {
				$error = Invalid(ArithmeticOverflow)
				$total_bytes
			}
			Ok(total) => total
		}
		if $error == NoError and $total_bytes > max_bytes {
			$error = Invalid(LimitExceeded({ attempted: $total_bytes, dimension: IccBytes, limit: max_bytes }))
		} else if $error == NoError and profile.bytes.len() < 132 {
			$error = Invalid(ProfileTooShort({ bytes: profile.bytes.len(), profile: $profile_index }))
		} else if $error == NoError {
			declared_size = read_u32_be(profile.bytes, 0).to_u64()
			if declared_size != profile.bytes.len() {
				$error = Invalid(DeclaredSizeMismatch({ actual: profile.bytes.len(), declared: declared_size, profile: $profile_index }))
			} else if read_u32_be(profile.bytes, 36) != 0x61637370 {
				$error = Invalid(InvalidIccSignature({ profile: $profile_index }))
			} else {
				version = list_at(profile.bytes, 8)
				version_ok = match profile.version {
					IccV2 => version == 2
					IccV4 => version == 4
				}
				device_ok = match profile.components {
					One => read_u32_be(profile.bytes, 16) == 0x47524159
					Three => read_u32_be(profile.bytes, 16) == 0x52474220
				}
				if !version_ok {
					$error = Invalid(UnsupportedIccVersion({ profile: $profile_index, version }))
				} else if !device_ok {
					$error = Invalid(ComponentMismatch({ profile: $profile_index }))
				} else {
					tag_count = read_u32_be(profile.bytes, 128).to_u64()
					table_bytes = match U64.times_try(tag_count, 12) {
						Err(Overflow) => {
							$error = Invalid(ArithmeticOverflow)
							0
						}
						Ok(value) => value
					}
					table_end = match U64.plus_try(132, table_bytes) {
						Err(Overflow) => {
							$error = Invalid(ArithmeticOverflow)
							0
						}
						Ok(value) => value
					}
					if $error == NoError and (tag_count != profile.tags.length() or table_end > profile.bytes.len()) {
						$error = Invalid(TagRecordMismatch({ profile: $profile_index, tag: 0 }))
					} else if $error == NoError {
						span = validate_span(profile.tags, store.tags.len(), $profile_index)
						match span {
							Err(error) => {
								$error = Invalid(error)
							}
							Ok(valid_span) => {
								var $local = 0
								while $local < tag_count and $error == NoError {
									global = valid_span.start + $local
									if list_at($tag_owners, global) != 0 {
										$error = Invalid(DuplicateTagOwnership({ tag: global }))
									} else {
										$tag_owners = list_set($tag_owners, global, 1)
										tag = list_at(store.tags, global)
										record = 132 + $local * 12
										offset = read_u32_be(profile.bytes, record + 4).to_u64()
										length = read_u32_be(profile.bytes, record + 8).to_u64()
										if tag.signature.raw() != read_u32_be(profile.bytes, record) or tag.bytes.start() != offset or tag.bytes.length() != length or offset > profile.bytes.len() or length > profile.bytes.len() - offset {
											$error = Invalid(TagRecordMismatch({ profile: $profile_index, tag: global }))
										}
									}
									$local = $local + 1
									$tag_edges = $tag_edges + 1
								}
							}
						}
					}
				}
			}
		}
		$profile_index = $profile_index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => match first_zero($tag_owners) {
			AllMarked => Ok({ bytes_checked: $total_bytes, tag_edges_checked: $tag_edges })
			ZeroAt(tag) => Err(OrphanTag({ tag: tag }))
		}
	}
}

validate_spaces : Color.Store -> Try({ components : List(Color.ComponentCount) }, KernelColor.Error)
validate_spaces = |store| {
	var $components = []
	var $index = 0
	var $error = NoError
	while $index < store.spaces.len() and $error == NoError {
		record = list_at(store.spaces, $index)
		if record.id.index() != $index {
			$error = Invalid(NonDenseSpaceIdentity({ actual: record.id.index(), expected: $index }))
		} else {
			match record.space {
				CalibratedGray({ black_point, white_point }) => {
					if white_point.x <= 0 or white_point.y != 1000000 or white_point.z <= 0 or black_point.x < 0 or black_point.y < 0 or black_point.z < 0 or black_point.x > white_point.x or black_point.y > white_point.y or black_point.z > white_point.z {
						$error = Invalid(InvalidCalibratedGray({ space: $index }))
					} else {
						$components = $components.append(One)
					}
				}
				IccBased({ components, profile }) => if profile.index() >= store.profiles.len() {
					$error = Invalid(IndexOutOfRange({ available: store.profiles.len(), index: profile.index() }))
				} else if list_at(store.profiles, profile.index()).components != components {
					$error = Invalid(ComponentMismatch({ profile: profile.index() }))
				} else {
					$components = $components.append(components)
				}
				Srgb(profile) => if profile.index() >= store.profiles.len() {
					$error = Invalid(IndexOutOfRange({ available: store.profiles.len(), index: profile.index() }))
				} else if list_at(store.profiles, profile.index()).components != Three {
					$error = Invalid(ComponentMismatch({ profile: profile.index() }))
				} else {
					$components = $components.append(Three)
				}
			}
		}
		$index = $index + 1
	}
	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ components: $components })
	}
}

read_u32_be : List(U8), U64 -> U32
read_u32_be = |bytes, index| list_at(bytes, index).to_u32().shl_wrap(24)
	.bitwise_or(list_at(bytes, index + 1).to_u32().shl_wrap(16))
	.bitwise_or(list_at(bytes, index + 2).to_u32().shl_wrap(8))
	.bitwise_or(list_at(bytes, index + 3).to_u32())

validate_span : Semantics.Range, U64, U64 -> Try({ end : U64, start : U64 }, KernelColor.Error)
validate_span = |range, available, owner| {
	start = range.start()
	length = range.length()
	if start > available or length > available - start Err(SpanOutOfRange({ available, length, owner, start })) else Ok({ end: start + length, start })
}

check_limit : U64, U64, KernelColor.Dimension -> Try({}, KernelColor.Error)
check_limit = |attempted, limit, dimension| if attempted > limit Err(LimitExceeded({ attempted, dimension, limit })) else Ok({})

first_zero : List(U8) -> [AllMarked, ZeroAt(U64)]
first_zero = |marks| {
	var $index = 0
	var $result = AllMarked
	while $index < marks.len() and $result == AllMarked {
		if list_at(marks, $index) == 0 {
			$result = ZeroAt($index)
		}
		$index = $index + 1
	}
	$result
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated color index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated color update escaped"
	}
}

set_byte : List(U8), U64, U8 -> List(U8)
set_byte = |bytes, index, value| list_set(bytes, index, value)

set_u32_be : List(U8), U64, U32 -> List(U8)
set_u32_be = |bytes, index, value| {
	first = set_byte(bytes, index, value.shr_wrap(24).to_u8_wrap())
	second = set_byte(first, index + 1, value.shr_wrap(16).to_u8_wrap())
	third = set_byte(second, index + 2, value.shr_wrap(8).to_u8_wrap())
	set_byte(third, index + 3, value.to_u8_wrap())
}

test_profile_bytes : List(U8)
test_profile_bytes = {
	base = List.repeat(0, 132)
	with_size = set_u32_be(base, 0, 132)
	with_version = set_byte(with_size, 8, 4)
	with_space = set_u32_be(with_version, 16, 0x52474220)
	with_signature = set_u32_be(with_space, 36, 0x61637370)
	set_u32_be(with_signature, 128, 0)
}

test_profile : Color.IccProfile
test_profile = { bytes: test_profile_bytes, components: Three, id: Color.ProfileId.from_index(0), tags: Semantics.Range.from_start_and_length(0, 0), version: IccV4 }

test_store : Color.Store
test_store = {
	profiles: [test_profile],
	spaces: [
		{ id: Color.SpaceId.from_index(0), space: CalibratedGray({ black_point: { x: 0, y: 0, z: 0 }, white_point: { x: 950000, y: 1000000, z: 1089000 } }) },
		{ id: Color.SpaceId.from_index(1), space: Srgb(Color.ProfileId.from_index(0)) },
	],
	tags: [],
}

test_limits : KernelColor.Limits
test_limits = KernelColor.Limits.make({ max_icc_bytes: 132, max_profiles: 1, max_spaces: 2, max_tags: 0 })

## Typed gray and RGB spaces retain their exact component counts.
expect {
	plan = KernelColor.Plan.build(test_store, test_limits)?
	KernelColor.Plan.components(plan, Color.SpaceId.from_index(0)) == One and KernelColor.Plan.components(plan, Color.SpaceId.from_index(1)) == Three
}

## ICC inspection records bounded byte, profile, and space work.
expect {
	plan = KernelColor.Plan.build(test_store, test_limits)?
	work = KernelColor.Plan.work(plan)
	work.bytes_checked == 132 and work.profile_visits == 1 and work.space_visits == 2 and work.tags_checked == 0
}

## A malformed ICC signature is rejected before a color plan escapes.
expect {
	bad_bytes = set_byte(test_profile_bytes, 36, 0)
	profile = list_at(test_store.profiles, 0)
	bad = { ..test_store, profiles: [{ ..profile, bytes: bad_bytes }] }
	match KernelColor.Plan.build(bad, test_limits) {
		Err(InvalidIccSignature({ profile: 0 })) => True
		_ => False
	}
}
