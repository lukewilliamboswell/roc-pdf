import KernelObject

KernelOutline :: [].{
	Link := [NoItem, OutlineItem(ItemId)]
	Parent := [OutlineParent(ItemId), OutlineRoot]
	Count := [ClosedCount(U64), Leaf, OpenCount(U64)]
	Target := [NoTarget, TargetValue(KernelObject.ValueId)]

	Error : [
		ArithmeticOverflow,
		DepthJump({ actual : U64, index : U64, previous : U64 }),
		DepthLimitExceeded({ attempted : U64, index : U64, limit : U64 }),
		EntryCountZero,
		EntryLimitExceeded({ attempted : U64, limit : U64 }),
		FirstDepthNonzero(U64),
		TargetIndexOutOfRange({ available : U64, index : U64, value : KernelObject.ValueId }),
		TitleIndexOutOfRange({ available : U64, index : U64, title : KernelObject.TextStringId }),
	]

	ItemId :: U64.{
		from_index : U64 -> ItemId
		from_index = |index| ItemId.(index)

		index : ItemId -> U64
		index = |ItemId.(index)| index

		is_eq : ItemId, ItemId -> Bool
		is_eq = |ItemId.(left), ItemId.(right)| left == right
	}

	Limits :: {
		max_depth : U64,
		max_entries : U64,
		text_string_count : U64,
		value_count : U64,
	}.{
		make : { max_depth : U64, max_entries : U64, text_string_count : U64, value_count : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	Entry :: {
		depth : U64,
		open : Bool,
		target : Target,
		title : KernelObject.TextStringId,
	}.{
		make : { depth : U64, open : Bool, target : Target, title : KernelObject.TextStringId } -> Entry
		make = |entry| Entry.(entry)
	}

	Item :: {
		count : Count,
		first : Link,
		id : ItemId,
		last : Link,
		next : Link,
		parent : Parent,
		previous : Link,
		target : Target,
		title : KernelObject.TextStringId,
	}.{
		count : Item -> Count
		count = |item| item.count

		first : Item -> Link
		first = |item| item.first

		id : Item -> ItemId
		id = |item| item.id

		last : Item -> Link
		last = |item| item.last

		next : Item -> Link
		next = |item| item.next

		parent : Item -> Parent
		parent = |item| item.parent

		previous : Item -> Link
		previous = |item| item.previous

		target : Item -> Target
		target = |item| item.target

		title : Item -> KernelObject.TextStringId
		title = |item| item.title
	}

	Work :: {
		count_accumulations : U64,
		entries_checked : U64,
		item_rewrites : U64,
		items_appended : U64,
		max_depth_seen : U64,
	}.{
		count_accumulations : Work -> U64
		count_accumulations = |work| work.count_accumulations

		entries_checked : Work -> U64
		entries_checked = |work| work.entries_checked

		item_rewrites : Work -> U64
		item_rewrites = |work| work.item_rewrites

		items_appended : Work -> U64
		items_appended = |work| work.items_appended

		max_depth_seen : Work -> U64
		max_depth_seen = |work| work.max_depth_seen
	}

	Plan :: {
		items : List(Item),
		root_count : U64,
		root_first : ItemId,
		root_last : ItemId,
		work : Work,
	}.{
		build : List(Entry), Limits -> Try(Plan, Error)
		build = |entries, limits| build_plan(entries, limits)

		entry_count : Plan -> U64
		entry_count = |plan| plan.items.len()

		item : Plan, ItemId -> Item
		item = |plan, id| list_at(plan.items, ItemId.index(id))

		item_at : Plan, U64 -> Item
		item_at = |plan, index| list_at(plan.items, index)

		root_count : Plan -> U64
		root_count = |plan| plan.root_count

		root_first : Plan -> ItemId
		root_first = |plan| plan.root_first

		root_last : Plan -> ItemId
		root_last = |plan| plan.root_last

		work : Plan -> Work
		work = |plan| plan.work
	}
}

build_plan : List(KernelOutline.Entry), KernelOutline.Limits -> Try(KernelOutline.Plan, KernelOutline.Error)
build_plan = |entries, limits| {
	entry_count = entries.len()
	count_limit = if limits.max_entries < I64.highest.to_u64_wrap() limits.max_entries else I64.highest.to_u64_wrap()
	if entry_count == 0 {
		Err(EntryCountZero)
	} else if entry_count > count_limit {
		Err(EntryLimitExceeded({ attempted: entry_count, limit: count_limit }))
	} else {
		build_nonempty_plan(entries, limits)
	}
}

build_nonempty_plan : List(KernelOutline.Entry), KernelOutline.Limits -> Try(KernelOutline.Plan, KernelOutline.Error)
build_nonempty_plan = |entries, limits| {
	var $items = List.with_capacity(entries.len())
	var $ancestors = []
	var $root_first = NoItem
	var $root_last = NoItem
	var $entries_checked = 0
	var $item_rewrites = 0
	var $items_appended = 0
	var $max_depth_seen = 0
	var $previous_depth = 0
	var $index = 0
	var $error = NoError
	while $index < entries.len() and $error == NoError {
		entry = list_at(entries, $index)
		depth = entry.depth
		if $index == 0 and depth != 0 {
			$error = Invalid(FirstDepthNonzero(depth))
		} else if depth > limits.max_depth {
			$error = Invalid(DepthLimitExceeded({ attempted: depth, index: $index, limit: limits.max_depth }))
		} else if $index > 0 and depth > $previous_depth and depth - $previous_depth > 1 {
			$error = Invalid(DepthJump({ actual: depth, index: $index, previous: $previous_depth }))
		} else if KernelObject.TextStringId.index(entry.title) >= limits.text_string_count {
			$error = Invalid(TitleIndexOutOfRange({ available: limits.text_string_count, index: $index, title: entry.title }))
		} else {
			match entry.target {
				NoTarget => {}
				TargetValue(value) => if KernelObject.ValueId.index(value) >= limits.value_count {
					$error = Invalid(TargetIndexOutOfRange({ available: limits.value_count, index: $index, value }))
				}
			}
		}

		if $error == NoError {
			id = KernelOutline.ItemId.from_index($index)
			parent = if depth == 0 {
				OutlineRoot
			} else {
				OutlineParent(list_at($ancestors, depth - 1))
			}
			previous = match parent {
				OutlineRoot => $root_last
				OutlineParent(parent_id) => KernelOutline.Item.last(list_at($items, KernelOutline.ItemId.index(parent_id)))
			}

			match previous {
				NoItem => {}
				OutlineItem(previous_id) => {
					previous_item = list_at($items, KernelOutline.ItemId.index(previous_id))
					$items = list_set($items, KernelOutline.ItemId.index(previous_id), item_with_next(previous_item, id))
					$item_rewrites = checked_add($item_rewrites, 1)?
				}
			}

			match parent {
				OutlineRoot => {
					match $root_first {
						NoItem => {
							$root_first = OutlineItem(id)
						}
						OutlineItem(_) => {}
					}
					$root_last = OutlineItem(id)
				}
				OutlineParent(parent_id) => {
					parent_index = KernelOutline.ItemId.index(parent_id)
					parent_item = list_at($items, parent_index)
					$items = list_set($items, parent_index, item_with_child(parent_item, id))
					$item_rewrites = checked_add($item_rewrites, 1)?
				}
			}

			initial_count = if entry.open OpenCount(0) else ClosedCount(0)
			$items = $items.append(
				KernelOutline.Item.{
					count: initial_count,
					first: NoItem,
					id,
					last: NoItem,
					next: NoItem,
					parent,
					previous,
					target: entry.target,
					title: entry.title,
				},
			)
			$items_appended = checked_add($items_appended, 1)?
			$entries_checked = checked_add($entries_checked, 1)?
			if depth > $max_depth_seen {
				$max_depth_seen = depth
			}
			if depth < $ancestors.len() {
				$ancestors = item_id_set($ancestors, depth, id)
			} else {
				$ancestors = $ancestors.append(id)
			}
			$previous_depth = depth
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => finalize_counts(
			$items,
			unwrap_link($root_first),
			unwrap_link($root_last),
			{
				count_accumulations: 0,
				entries_checked: $entries_checked,
				item_rewrites: $item_rewrites,
				items_appended: $items_appended,
				max_depth_seen: $max_depth_seen,
			},
		)
	}
}

finalize_counts : List(KernelOutline.Item), KernelOutline.ItemId, KernelOutline.ItemId, { count_accumulations : U64, entries_checked : U64, item_rewrites : U64, items_appended : U64, max_depth_seen : U64 } -> Try(KernelOutline.Plan, KernelOutline.Error)
finalize_counts = |items, root_first, root_last, initial_work| {
	var $items = items
	var $root_count = 0
	var $count_accumulations = initial_work.count_accumulations
	var $item_rewrites = initial_work.item_rewrites
	var $index = $items.len()
	while $index > 0 {
		$index = $index - 1
		item = list_at($items, $index)
		magnitude = count_magnitude(item.count)
		contribution = checked_add(1, if count_is_open(item.count) magnitude else 0)?
		match item.parent {
			OutlineRoot => {
				$root_count = checked_add($root_count, contribution)?
			}
			OutlineParent(parent_id) => {
				parent_index = KernelOutline.ItemId.index(parent_id)
				parent = list_at($items, parent_index)
				parent_count = count_with_added_magnitude(parent.count, contribution)?
				$items = list_set($items, parent_index, item_with_count(parent, parent_count))
				$item_rewrites = checked_add($item_rewrites, 1)?
			}
		}
		final_count = match item.first {
			NoItem => Leaf
			OutlineItem(_) => item.count
		}
		$items = list_set($items, $index, item_with_count(item, final_count))
		$item_rewrites = checked_add($item_rewrites, 1)?
		$count_accumulations = checked_add($count_accumulations, 1)?
	}

	Ok(
		KernelOutline.Plan.{
			items: $items,
			root_count: $root_count,
			root_first,
			root_last,
			work: KernelOutline.Work.{
				count_accumulations: $count_accumulations,
				entries_checked: initial_work.entries_checked,
				item_rewrites: $item_rewrites,
				items_appended: initial_work.items_appended,
				max_depth_seen: initial_work.max_depth_seen,
			},
		},
	)
}

item_with_next : KernelOutline.Item, KernelOutline.ItemId -> KernelOutline.Item
item_with_next = |item, next| KernelOutline.Item.{
	count: item.count,
	first: item.first,
	id: item.id,
	last: item.last,
	next: OutlineItem(next),
	parent: item.parent,
	previous: item.previous,
	target: item.target,
	title: item.title,
}

item_with_child : KernelOutline.Item, KernelOutline.ItemId -> KernelOutline.Item
item_with_child = |item, child| KernelOutline.Item.{
	count: item.count,
	first: match item.first {
		NoItem => OutlineItem(child)
		OutlineItem(first) => OutlineItem(first)
	},
	id: item.id,
	last: OutlineItem(child),
	next: item.next,
	parent: item.parent,
	previous: item.previous,
	target: item.target,
	title: item.title,
}

item_with_count : KernelOutline.Item, KernelOutline.Count -> KernelOutline.Item
item_with_count = |item, count| KernelOutline.Item.{
	count,
	first: item.first,
	id: item.id,
	last: item.last,
	next: item.next,
	parent: item.parent,
	previous: item.previous,
	target: item.target,
	title: item.title,
}

count_magnitude : KernelOutline.Count -> U64
count_magnitude = |count| match count {
	ClosedCount(value) => value
	Leaf => 0
	OpenCount(value) => value
}

count_is_open : KernelOutline.Count -> Bool
count_is_open = |count| match count {
	ClosedCount(_) => False
	Leaf => False
	OpenCount(_) => True
}

count_with_added_magnitude : KernelOutline.Count, U64 -> Try(KernelOutline.Count, KernelOutline.Error)
count_with_added_magnitude = |count, addition| match count {
	ClosedCount(value) => Ok(ClosedCount(checked_add(value, addition)?))
	Leaf => {
		crash "outline parent count invariant failed"
	}
	OpenCount(value) => Ok(OpenCount(checked_add(value, addition)?))
}

unwrap_link : KernelOutline.Link -> KernelOutline.ItemId
unwrap_link = |link| match link {
	NoItem => {
		crash "nonempty outline root link invariant failed"
	}
	OutlineItem(id) => id
}

checked_add : U64, U64 -> Try(U64, KernelOutline.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "outline list invariant failed"
	}
}

list_set : List(KernelOutline.Item), U64, KernelOutline.Item -> List(KernelOutline.Item)
list_set = |list, index, value| match list.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "outline item update invariant failed"
	}
}

item_id_set : List(KernelOutline.ItemId), U64, KernelOutline.ItemId -> List(KernelOutline.ItemId)
item_id_set = |list, index, value| match list.set(index, value) {
	Ok(updated) => updated
	Err(OutOfBounds) => {
		crash "outline ancestor update invariant failed"
	}
}

is_open_count : KernelOutline.Count, U64 -> Bool
is_open_count = |count, expected| match count {
	OpenCount(actual) => actual == expected
	_ => False
}

is_closed_count : KernelOutline.Count, U64 -> Bool
is_closed_count = |count, expected| match count {
	ClosedCount(actual) => actual == expected
	_ => False
}

is_leaf : KernelOutline.Count -> Bool
is_leaf = |count| match count {
	Leaf => True
	_ => False
}

link_is : KernelOutline.Link, U64 -> Bool
link_is = |link, expected| match link {
	NoItem => False
	OutlineItem(id) => KernelOutline.ItemId.index(id) == expected
}

link_is_empty : KernelOutline.Link -> Bool
link_is_empty = |link| match link {
	NoItem => True
	OutlineItem(_) => False
}

parent_is : KernelOutline.Parent, U64 -> Bool
parent_is = |parent, expected| match parent {
	OutlineParent(id) => KernelOutline.ItemId.index(id) == expected
	OutlineRoot => False
}

parent_is_root : KernelOutline.Parent -> Bool
parent_is_root = |parent| match parent {
	OutlineParent(_) => False
	OutlineRoot => True
}

target_is_empty : KernelOutline.Target -> Bool
target_is_empty = |target| match target {
	NoTarget => True
	TargetValue(_) => False
}

test_title : U64 -> KernelObject.TextStringId
test_title = |index| KernelObject.TextStringId.from_index(index)

test_target : U64 -> KernelOutline.Target
test_target = |index| TargetValue(KernelObject.ValueId.from_index(index))

test_entry : U64, Bool, U64 -> KernelOutline.Entry
test_entry = |depth, open, index| KernelOutline.Entry.make({ depth, open, target: test_target(index), title: test_title(index) })

test_limits : KernelOutline.Limits
test_limits = KernelOutline.Limits.make({ max_depth: 8, max_entries: 32, text_string_count: 32, value_count: 32 })

## Preorder input seals exact parent, sibling, child, and visibility facts.
expect {
	plan = KernelOutline.Plan.build(
		[
			test_entry(0, True, 0),
			test_entry(1, True, 1),
			test_entry(2, True, 2),
			test_entry(1, False, 3),
			test_entry(2, True, 4),
			test_entry(0, False, 5),
		],
		test_limits,
	)?
	a = KernelOutline.Plan.item_at(plan, 0)
	b = KernelOutline.Plan.item_at(plan, 1)
	c = KernelOutline.Plan.item_at(plan, 2)
	d = KernelOutline.Plan.item_at(plan, 3)
	e = KernelOutline.Plan.item_at(plan, 4)
	f = KernelOutline.Plan.item_at(plan, 5)

	KernelOutline.Plan.root_count(plan) == 5 and
		is_open_count(KernelOutline.Item.count(a), 3) and
			is_open_count(KernelOutline.Item.count(b), 1) and
				is_leaf(KernelOutline.Item.count(c)) and
					is_closed_count(KernelOutline.Item.count(d), 1) and
						is_leaf(KernelOutline.Item.count(e)) and
							is_leaf(KernelOutline.Item.count(f)) and
								link_is(KernelOutline.Item.first(a), 1) and
									link_is(KernelOutline.Item.last(a), 3) and
										link_is(KernelOutline.Item.next(b), 3) and
											link_is(KernelOutline.Item.previous(d), 1) and
												parent_is(KernelOutline.Item.parent(e), 3) and
													KernelOutline.Plan.root_first(plan) == KernelOutline.ItemId.from_index(0) and
														KernelOutline.Plan.root_last(plan) == KernelOutline.ItemId.from_index(5)
}

## A single leaf has root links and no item Count or sibling links.
expect {
	plan = KernelOutline.Plan.build([test_entry(0, False, 0)], test_limits)?
	item = KernelOutline.Plan.item_at(plan, 0)
	KernelOutline.Plan.root_count(plan) == 1 and
		is_leaf(KernelOutline.Item.count(item)) and
			link_is_empty(KernelOutline.Item.previous(item)) and
				link_is_empty(KernelOutline.Item.next(item)) and
					parent_is_root(KernelOutline.Item.parent(item))
}

## Empty, nonzero-first-depth, skipped-depth, and explicit depth-limit inputs fail atomically.
expect {
	empty = KernelOutline.Plan.build([], test_limits)
	first = KernelOutline.Plan.build([test_entry(1, True, 0)], test_limits)
	jump = KernelOutline.Plan.build([test_entry(0, True, 0), test_entry(2, True, 1)], test_limits)
	deep = KernelOutline.Plan.build([test_entry(0, True, 0), test_entry(1, True, 1)], KernelOutline.Limits.make({ max_depth: 0, max_entries: 2, text_string_count: 2, value_count: 2 }))

	match empty {
		Err(EntryCountZero) => True
		_ => False
	} and match first {
		Err(FirstDepthNonzero(depth)) => depth == 1
		_ => False
	} and match jump {
		Err(DepthJump({ actual, index, previous })) => actual == 2 and index == 1 and previous == 0
		_ => False
	} and match deep {
		Err(DepthLimitExceeded({ attempted, index, limit })) => attempted == 1 and index == 1 and limit == 0
		_ => False
	}
}

## Entry, title-store, and target-store bounds are named before a plan escapes.
expect {
	over = KernelOutline.Plan.build([test_entry(0, True, 0), test_entry(0, True, 1)], KernelOutline.Limits.make({ max_depth: 1, max_entries: 1, text_string_count: 2, value_count: 2 }))
	bad_title = KernelOutline.Plan.build([test_entry(0, True, 1)], KernelOutline.Limits.make({ max_depth: 1, max_entries: 1, text_string_count: 1, value_count: 2 }))
	bad_target = KernelOutline.Plan.build([test_entry(0, True, 1)], KernelOutline.Limits.make({ max_depth: 1, max_entries: 1, text_string_count: 2, value_count: 1 }))

	match over {
		Err(EntryLimitExceeded({ attempted, limit })) => attempted == 2 and limit == 1
		_ => False
	} and match bad_title {
		Err(TitleIndexOutOfRange({ available, index, title })) => available == 1 and index == 0 and KernelObject.TextStringId.index(title) == 1
		_ => False
	} and match bad_target {
		Err(TargetIndexOutOfRange({ available, index, value })) => available == 1 and index == 0 and KernelObject.ValueId.index(value) == 1
		_ => False
	}
}

## Targetless grouping items are valid and retain their explicit target policy.
expect {
	entry = KernelOutline.Entry.make({ depth: 0, open: True, target: NoTarget, title: test_title(0) })
	plan = KernelOutline.Plan.build([entry], test_limits)?
	target_is_empty(KernelOutline.Item.target(KernelOutline.Plan.item_at(plan, 0)))
}
