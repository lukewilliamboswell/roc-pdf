## Select the authored headings for one generated table of contents.
## Keys identify navigation targets. Display titles may repeat.
KernelContentsSelection :: [].{
	Target : [Named(Str), NoTarget]
	Heading : { level : U8, target : Target, title : Str }
	Scope : [Under(Str), WholeDocument]
	TitleOverride : { target : Str, title : Str }
	Options : { depth : U8, overrides : List(TitleOverride), scope : Scope }
	Limits : { max_entries : U64, max_title_overrides : U64 }

	default_max_title_overrides : U64
	default_max_title_overrides = 64

	Entry : { depth : U8, target : Str, title : Str }
	Work : { heading_visits : U64, override_visits : U64 }

	Error : [
		EmptySelection,
		InvalidDepth,
		InvalidHeading({ heading : U64 }),
		MissingScope,
		RepeatedScope,
		OverrideLimit({ limit : U64 }),
		EmptyOverride({ index : U64 }),
		RepeatedOverride({ index : U64 }),
		UnusedOverride({ index : U64 }),
	]

	## Start directly after a selected scope heading and stop at the next
	## heading at that level or above. An unanchored heading still closes
	## a scope and affects indentation, but has no target for a TOC entry.
	select : List(Heading), Options -> Try({ entries : List(Entry), work : Work }, Error)
	select = |headings, options| {
		{ entries, work, .. } = select_with_limits(headings, options, { max_entries: U64.highest, max_title_overrides: default_max_title_overrides })?
		Ok({ entries, work })
	}

	## Retain only the first `max_entries` matches. The total selected count
	## remains exact, and selection still validates every applicable heading
	## and override before a document-level entry limit can reject the result.
	select_with_limits : List(Heading), Options, Limits -> Try({ entries : List(Entry), selected : U64, work : Work }, Error)
	select_with_limits = |headings, options, limits| select_headings(headings, options, limits)
}

ScopeStart : { cursor : U64, level : U8, visits : U64 }

scope_start : List(KernelContentsSelection.Heading), KernelContentsSelection.Scope -> Try(ScopeStart, KernelContentsSelection.Error)
scope_start = |headings, scope| match scope {
	WholeDocument => Ok({ cursor: 0, level: 0, visits: 0 })
	Under(name) => {
		missing : [Found(ScopeStart), Missing]
		missing = Missing
		var $start = missing
		var $index = 0
		for heading in headings {
			match heading.target {
				Named(target) if target == name => match $start {
					Found(_) => return Err(RepeatedScope)
					Missing => {
						if heading.level < 1 or heading.level > 6 {
							return Err(InvalidHeading({ heading: $index }))
						}
						$start = Found({ cursor: $index + 1, level: heading.level, visits: headings.len() })
					}
				}
				_ => {}
			}
			$index = $index + 1
		}
		match $start {
			Found(start) => Ok(start)
			Missing => Err(MissingScope)
		}
	}
}

select_headings : List(KernelContentsSelection.Heading), KernelContentsSelection.Options, KernelContentsSelection.Limits -> Try({ entries : List(KernelContentsSelection.Entry), selected : U64, work : KernelContentsSelection.Work }, KernelContentsSelection.Error)
select_headings = |headings, { depth: max_depth, overrides, scope: requested_scope }, limits| {
	override_count = overrides.len()
	if max_depth == 0 or max_depth > 6 {
		return Err(InvalidDepth)
	}
	if override_count > limits.max_title_overrides {
		return Err(OverrideLimit({ limit: limits.max_title_overrides }))
	}
	{ search, visits: override_checks } = prepare_overrides(overrides)?
	scope = scope_start(headings, requested_scope)?
	var $used_overrides = List.repeat(False, override_count)
	var $entries = []
	var $selected = 0
	var $index = scope.cursor
	var $heading_visits = scope.visits
	var $override_visits = override_checks
	while $index < headings.len() {
		heading = list_at(headings, $index)
		$heading_visits = $heading_visits + 1
		if heading.level == 0 or heading.level > 6 {
			return Err(InvalidHeading({ heading: $index }))
		}
		if heading.level <= scope.level {
			break
		}
		depth = heading.level - scope.level
		match heading.target {
			Named(target) if depth <= max_depth => {
				found = match search {
					Linear(values) => override_for(values, target)
					Indexed(index) => indexed_override_for(index, target)
				}
				$override_visits = $override_visits + found.visits
				var $title = heading.title
				match found.value {
					NoOverride => {}
					Override({ index, title }) => {
						$title = title
						$used_overrides = list_set($used_overrides, index, True)
					}
				}
				if $selected < limits.max_entries {
					$entries = $entries.append({ depth, target, title: $title })
				}
				$selected = $selected + 1
			}
			_ => {}
		}
		$index = $index + 1
	}
	var $override_index = 0
	for used in $used_overrides {
		$override_visits = $override_visits + 1
		if !used {
			return Err(UnusedOverride({ index: $override_index }))
		}
		$override_index = $override_index + 1
	}
	if $selected == 0 {
		return Err(EmptySelection)
	}
	Ok({ entries: $entries, selected: $selected, work: { heading_visits: $heading_visits, override_visits: $override_visits } })
}

IndexedOverride : { key : List(U8), ordinal : U64, title : Str }

OverrideSearch : [Indexed(List(IndexedOverride)), Linear(List(KernelContentsSelection.TitleOverride))]

prepare_overrides : List(KernelContentsSelection.TitleOverride) -> Try({ search : OverrideSearch, visits : U64 }, KernelContentsSelection.Error)
prepare_overrides = |overrides| {
	count = overrides.len()
	if count <= KernelContentsSelection.default_max_title_overrides {
		visits = validate_overrides(overrides)?
		return Ok({ search: Linear(overrides), visits })
	}
	var $entries = []
	var $ordinal = 0
	var $checked = 0
	for item in overrides {
		$checked = $checked + 1
		if item.target.is_empty() or item.title.is_empty() {
			break
		}
		$entries = $entries.append({ key: item.target.to_utf8(), ordinal: $ordinal, title: item.title })
		$ordinal = $ordinal + 1
	}
	{ entries, visits } = sort_overrides($entries)
	var $duplicate = count
	var $adjacent = 1
	while $adjacent < entries.len() {
		first = list_at(entries, $adjacent - 1)
		second = list_at(entries, $adjacent)
		if first.key == second.key {
			$duplicate = U64.min($duplicate, second.ordinal)
		}
		$adjacent = $adjacent + 1
	}
	# Only the valid prefix was sorted. Its earliest duplicate therefore
	# takes precedence over the first empty override, if both exist.
	if $duplicate < count {
		return Err(RepeatedOverride({ index: $duplicate }))
	}
	if $ordinal < count {
		return Err(EmptyOverride({ index: $ordinal }))
	}
	Ok({ search: Indexed(entries), visits: $checked + visits + entries.len().minus_saturated(1) })
}

## Stable merges preserve authored order among equal keys. Count each
## comparison so larger inputs have deterministic sorting work evidence.
sort_overrides : List(IndexedOverride) -> { entries : List(IndexedOverride), visits : U64 }
sort_overrides = |input| {
	count = input.len()
	var $entries = input
	var $width = 1
	var $visits = 0
	while $width < count {
		var $merged = List.with_capacity(count)
		var $start = 0
		while $start < count {
			middle = $start + U64.min($width, count - $start)
			end = middle + U64.min($width, count - middle)
			var $left = $start
			var $right = middle
			while $left < middle or $right < end {
				take_left = if $left == middle {
					False
				} else if $right == end {
					True
				} else {
					$visits = $visits + 1
					compare_keys(list_at($entries, $left).key, list_at($entries, $right).key) != After
				}
				if take_left {
					$merged = $merged.append(list_at($entries, $left))
					$left = $left + 1
				} else {
					$merged = $merged.append(list_at($entries, $right))
					$right = $right + 1
				}
			}
			$start = end
		}
		$entries = $merged
		$width = $width + U64.min($width, count - $width)
	}
	{ entries: $entries, visits: $visits }
}

indexed_override_for : List(IndexedOverride), Str -> { value : [NoOverride, Override({ index : U64, title : Str })], visits : U64 }
indexed_override_for = |entries, target| {
	key = target.to_utf8()
	var $lower = 0
	var $upper = entries.len()
	var $visits = 0
	while $lower < $upper {
		middle = $lower + ($upper - $lower) // 2
		entry = list_at(entries, middle)
		$visits = $visits + 1
		match compare_keys(key, entry.key) {
			Before => {
				$upper = middle
			}
			After => {
				$lower = middle + 1
			}
			Same => return { value: Override({ index: entry.ordinal, title: entry.title }), visits: $visits }
		}
	}
	{ value: NoOverride, visits: $visits }
}

compare_keys : List(U8), List(U8) -> [Before, Same, After]
compare_keys = |left, right| {
	shared = U64.min(left.len(), right.len())
	var $index = 0
	while $index < shared {
		match list_at(left, $index).order_relative_to(list_at(right, $index)) {
			Before => return Before
			After => return After
			Same => {
				$index = $index + 1
			}
		}
	}
	left.len().order_relative_to(right.len())
}

validate_overrides : List(KernelContentsSelection.TitleOverride) -> Try(U64, KernelContentsSelection.Error)
validate_overrides = |overrides| {
	var $index = 0
	var $visits = 0
	for current in overrides {
		$visits = $visits + 1
		if current.target.is_empty() or current.title.is_empty() {
			return Err(EmptyOverride({ index: $index }))
		}
		var $earlier = 0
		while $earlier < $index {
			$visits = $visits + 1
			if list_at(overrides, $earlier).target == current.target {
				return Err(RepeatedOverride({ index: $index }))
			}
			$earlier = $earlier + 1
		}
		$index = $index + 1
	}
	Ok($visits)
}

override_for : List(KernelContentsSelection.TitleOverride), Str -> { value : [NoOverride, Override({ index : U64, title : Str })], visits : U64 }
override_for = |overrides, target| {
	var $index = 0
	for override in overrides {
		if override.target == target {
			return { value: Override({ index: $index, title: override.title }), visits: $index + 1 }
		}
		$index = $index + 1
	}
	{ value: NoOverride, visits: $index }
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(item) => item
	Err(OutOfBounds) => crash "validated contents selection index"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, item| match items.set(index, item) {
	Ok(updated) => updated
	Err(OutOfBounds) => crash "validated contents override index"
}

test_headings : List(KernelContentsSelection.Heading)
test_headings = [
	{ level: 1, target: Named("procedure"), title: "Procedure" },
	{ level: 2, target: Named("first"), title: "Recovery checks" },
	{ level: 3, target: Named("latent"), title: "Verification details" },
	{ level: 2, target: Named("second"), title: "Recovery checks" },
	{ level: 1, target: NoTarget, title: "Appendix" },
	{ level: 2, target: Named("outside"), title: "Outside the procedure" },
]

expect {
	whole = KernelContentsSelection.select(test_headings, { depth: 2, overrides: [], scope: WholeDocument })?
	whole.entries.map(|entry| entry.target) == ["procedure", "first", "second", "outside"] and whole.work.heading_visits == 6
}

expect {
	{ entries, work } = KernelContentsSelection.select(
		test_headings,
		{ depth: 1, overrides: [{ target: "second", title: "Follow-up checks" }], scope: Under("procedure") },
	)?
	entries == [
		{ depth: 1, target: "first", title: "Recovery checks" },
		{ depth: 1, target: "second", title: "Follow-up checks" },
	] and work == { heading_visits: 10, override_visits: 4 }
}

expect match KernelContentsSelection.select(test_headings, { depth: 1, overrides: [{ target: "outside", title: "Outside" }], scope: Under("procedure") }) {
	Err(UnusedOverride({ index: 0 })) => True
	_ => False
}

# A bounded result keeps its authored prefix and counts every selected
# heading and override exactly as the unbounded result does.
expect {
	options = { depth: 2, overrides: [{ target: "outside", title: "Last" }], scope: WholeDocument }
	full = KernelContentsSelection.select(test_headings, options)?
	bounded = KernelContentsSelection.select_with_limits(test_headings, options, { max_entries: 1, max_title_overrides: 1 })?
	bounded.entries == full.entries.take_first(1) and bounded.selected == full.entries.len() and bounded.work == full.work
}

expect {
	limits = { max_entries: 0, max_title_overrides: 1 }
	valid = list_at(test_headings, 0)
	invalid = KernelContentsSelection.select_with_limits([valid, { ..valid, level: 0 }], { depth: 2, overrides: [], scope: WholeDocument }, limits)
	unused = KernelContentsSelection.select_with_limits([valid], { depth: 2, overrides: [{ target: "unused", title: "Unused" }], scope: WholeDocument }, limits)
	invalid == Err(InvalidHeading({ heading: 1 })) and unused == Err(UnusedOverride({ index: 0 }))
}

many_overrides : U64 -> List(KernelContentsSelection.TitleOverride)
many_overrides = |count| {
	var $overrides = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$overrides = $overrides.append({ target: "target-${$index.to_str()}", title: "Title ${$index.to_str()}" })
		$index = $index + 1
	}
	$overrides
}

# The smallest authored duplicate wins across distinct lexical groups,
# unless an empty override precedes it.
expect {
	options = { depth: 6, overrides: many_overrides(65), scope: WholeDocument }
	first = list_at(options.overrides, 0)
	second = list_at(options.overrides, 1)
	duplicate = list_set(list_set(options.overrides, 4, second), 6, first)
	later_empty = list_set(duplicate, 8, { ..first, title: "" })
	earlier_empty = list_set(duplicate, 2, { ..first, title: "" })
	limits = { max_entries: 0, max_title_overrides: 65 }
	KernelContentsSelection.select_with_limits([], { ..options, overrides: later_empty }, limits) == Err(RepeatedOverride({ index: 4 }))
		and KernelContentsSelection.select_with_limits([], { ..options, overrides: earlier_empty }, limits) == Err(EmptyOverride({ index: 2 }))
		and KernelContentsSelection.select([], options) == Err(OverrideLimit({ limit: 64 }))
}

# Independently counted merge and binary-search visits for authored numeric
# identifiers keep a fourfold input increase close to linear growth.
expect [(128, 1753), (512, 8342)].all(
	|(count, visits)| {
		overrides = many_overrides(count)
		headings = overrides.map(|entry| { level: 1, target: Named(entry.target), title: "Original" })
		selected = match KernelContentsSelection.select_with_limits(headings, { depth: 6, overrides, scope: WholeDocument }, { max_entries: count, max_title_overrides: count }) {
			Ok(value) => value
			Err(_) => return False
		}
		selected.entries.map(|entry| { target: entry.target, title: entry.title }) == overrides
			and selected.selected == count
			and selected.work == { heading_visits: count, override_visits: visits }
	},
)
