## Select the authored headings for one generated table of contents.
## Keys identify navigation targets. Display titles may repeat.
KernelContentsSelection :: [].{
	Target : [Named(Str), NoTarget]
	Heading : { level : U8, target : Target, title : Str }
	Scope : [Under(Str), WholeDocument]
	TitleOverride : { target : Str, title : Str }
	Options : { depth : U8, overrides : List(TitleOverride), scope : Scope }

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
	select = |headings, options| select_headings(headings, options)
}

max_overrides : U64
max_overrides = 64

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

select_headings : List(KernelContentsSelection.Heading), KernelContentsSelection.Options -> Try({ entries : List(KernelContentsSelection.Entry), work : KernelContentsSelection.Work }, KernelContentsSelection.Error)
select_headings = |headings, options| {
	if options.depth == 0 or options.depth > 6 {
		return Err(InvalidDepth)
	}
	if options.overrides.len() > max_overrides {
		return Err(OverrideLimit({ limit: max_overrides }))
	}
	override_checks = validate_overrides(options.overrides)?
	scope = scope_start(headings, options.scope)?
	var $used_overrides = List.repeat(False, options.overrides.len())
	var $entries = []
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
			Named(target) if depth <= options.depth => {
				found = override_for(options.overrides, target)
				$override_visits = $override_visits + found.visits
				var $title = heading.title
				match found.value {
					NoOverride => {}
					Override({ index, title }) => {
						$title = title
						$used_overrides = list_set($used_overrides, index, True)
					}
				}
				$entries = $entries.append({ depth, target, title: $title })
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
	if $entries.is_empty() {
		return Err(EmptySelection)
	}
	Ok({ entries: $entries, work: { heading_visits: $heading_visits, override_visits: $override_visits } })
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
