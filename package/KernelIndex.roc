import KernelBalanced
import KernelObject

KernelIndex :: [].{
	ByteKind := [IDTree, NameTree]
	NumberKind := [NumberTree, ParentTree]

	Error : [
		ArithmeticOverflow,
		DuplicateByteKey({ index : U64 }),
		DuplicateNumberKey({ index : U64 }),
		EntryCountZero,
		EntryLimitExceeded({ attempted : U64, limit : U64 }),
		KeyBytesLimitExceeded({ attempted : U64, index : U64, limit : U64 }),
		NegativeParentKey({ index : U64, key : I64 }),
		NonMonotonicByteKey({ index : U64 }),
		NonMonotonicNumberKey({ index : U64 }),
		Shape(KernelBalanced.Error),
		ValueIndexOutOfRange({ available : U64, index : U64, value : KernelObject.ValueId }),
	]

	Limits :: { max_entries : U64, max_key_bytes : U64, value_count : U64 }.{
		make : { max_entries : U64, max_key_bytes : U64, value_count : U64 } -> Limits
		make = |limits| Limits.(limits)
	}

	ByteEntry :: { key : List(U8), value : KernelObject.ValueId }.{
		key : ByteEntry -> List(U8)
		key = |entry| entry.key

		make : List(U8), KernelObject.ValueId -> ByteEntry
		make = |key_bytes, value| ByteEntry.{ key: key_bytes, value }

		value : ByteEntry -> KernelObject.ValueId
		value = |entry| entry.value
	}

	NumberEntry :: { key : I64, value : KernelObject.ValueId }.{
		key : NumberEntry -> I64
		key = |entry| entry.key

		make : I64, KernelObject.ValueId -> NumberEntry
		make = |number, value| NumberEntry.{ key: number, value }

		value : NumberEntry -> KernelObject.ValueId
		value = |entry| entry.value
	}

	Node :: {
		children : [Entries(KernelBalanced.Span), Nodes(KernelBalanced.Span)],
		entry_span : KernelBalanced.Span,
		limits : [NoLimits, NodeLimits({ first_index : U64, last_index : U64 })],
	}.{
		children : Node -> [Entries(KernelBalanced.Span), Nodes(KernelBalanced.Span)]
		children = |node| node.children

		entry_span : Node -> KernelBalanced.Span
		entry_span = |node| node.entry_span

		limits : Node -> [NoLimits, NodeLimits({ first_index : U64, last_index : U64 })]
		limits = |node| node.limits
	}

	Work :: {
		entries_checked : U64,
		key_bytes_checked : U64,
		node_count : U64,
		ordering_steps : U64,
	}.{
		entries_checked : Work -> U64
		entries_checked = |work| work.entries_checked

		key_bytes_checked : Work -> U64
		key_bytes_checked = |work| work.key_bytes_checked

		node_count : Work -> U64
		node_count = |work| work.node_count

		ordering_steps : Work -> U64
		ordering_steps = |work| work.ordering_steps
	}

	ByteTree :: {
		entries : List(ByteEntry),
		kind : ByteKind,
		shape : KernelBalanced.Shape,
		work : Work,
	}.{
		build : List(ByteEntry), ByteKind, Limits -> Try(ByteTree, Error)
		build = |entries, kind, limits| {
			entry_count = entries.len()
			validate_entry_count(entry_count, limits.max_entries)?
			validated = validate_byte_entries(entries, limits.max_key_bytes, limits.value_count)?
			shape = KernelBalanced.Shape.build(entry_count, limits.max_entries) ? Shape
			work = Work.{
				entries_checked: validated.entries_checked,
				key_bytes_checked: validated.key_bytes_checked,
				node_count: KernelBalanced.Shape.node_count(shape),
				ordering_steps: validated.ordering_steps,
			}
			Ok(ByteTree.{ entries, kind, shape, work })
		}

		entry : ByteTree, U64 -> ByteEntry
		entry = |tree, index| list_at(tree.entries, index)

		entry_count : ByteTree -> U64
		entry_count = |tree| tree.entries.len()

		kind : ByteTree -> ByteKind
		kind = |tree| tree.kind

		level_count : ByteTree -> U64
		level_count = |tree| KernelBalanced.Shape.level_count(tree.shape)

		node : ByteTree, U64, U64 -> Node
		node = |tree, level, index| index_node(tree.shape, level, index)

		node_count : ByteTree -> U64
		node_count = |tree| KernelBalanced.Shape.node_count(tree.shape)

		node_count_at : ByteTree, U64 -> U64
		node_count_at = |tree, level| KernelBalanced.Shape.level_node_count(tree.shape, level)

		work : ByteTree -> Work
		work = |tree| tree.work
	}

	NumberTree :: {
		entries : List(NumberEntry),
		kind : NumberKind,
		shape : KernelBalanced.Shape,
		work : Work,
	}.{
		build : List(NumberEntry), NumberKind, Limits -> Try(NumberTree, Error)
		build = |entries, kind, limits| {
			entry_count = entries.len()
			validate_entry_count(entry_count, limits.max_entries)?
			validated = validate_number_entries(entries, kind, limits.value_count)?
			shape = KernelBalanced.Shape.build(entry_count, limits.max_entries) ? Shape
			work = Work.{
				entries_checked: validated.entries_checked,
				key_bytes_checked: 0,
				node_count: KernelBalanced.Shape.node_count(shape),
				ordering_steps: validated.ordering_steps,
			}
			Ok(NumberTree.{ entries, kind, shape, work })
		}

		entry : NumberTree, U64 -> NumberEntry
		entry = |tree, index| list_at(tree.entries, index)

		entry_count : NumberTree -> U64
		entry_count = |tree| tree.entries.len()

		kind : NumberTree -> NumberKind
		kind = |tree| tree.kind

		level_count : NumberTree -> U64
		level_count = |tree| KernelBalanced.Shape.level_count(tree.shape)

		node : NumberTree, U64, U64 -> Node
		node = |tree, level, index| index_node(tree.shape, level, index)

		node_count : NumberTree -> U64
		node_count = |tree| KernelBalanced.Shape.node_count(tree.shape)

		node_count_at : NumberTree, U64 -> U64
		node_count_at = |tree, level| KernelBalanced.Shape.level_node_count(tree.shape, level)

		work : NumberTree -> Work
		work = |tree| tree.work
	}
}

validate_entry_count : U64, U64 -> Try({}, KernelIndex.Error)
validate_entry_count = |entry_count, entry_limit| {
	if entry_count == 0 {
		Err(EntryCountZero)
	} else if entry_count > entry_limit {
		Err(EntryLimitExceeded({ attempted: entry_count, limit: entry_limit }))
	} else {
		Ok({})
	}
}

validate_byte_entries : List(KernelIndex.ByteEntry), U64, U64 -> Try({ entries_checked : U64, key_bytes_checked : U64, ordering_steps : U64 }, KernelIndex.Error)
validate_byte_entries = |entries, key_byte_limit, value_count| {
	var $entries_checked = 0
	var $key_bytes_checked = 0
	var $ordering_steps = 0
	var $index = 0
	var $error = NoError
	while $index < entries.len() and $error == NoError {
		entry = list_at(entries, $index)
		key = KernelIndex.ByteEntry.key(entry)
		key_length = key.len()
		value = KernelIndex.ByteEntry.value(entry)
		if key_length > key_byte_limit {
			$error = Invalid(KeyBytesLimitExceeded({ attempted: key_length, index: $index, limit: key_byte_limit }))
		} else if KernelObject.ValueId.index(value) >= value_count {
			$error = Invalid(ValueIndexOutOfRange({ available: value_count, index: $index, value }))
		} else {
			$entries_checked = checked_add($entries_checked, 1)?
			$key_bytes_checked = checked_add($key_bytes_checked, key_length)?
			if $index > 0 {
				previous = KernelIndex.ByteEntry.key(list_at(entries, $index - 1))
				comparison = compare_bytes(previous, key)?
				$ordering_steps = checked_add($ordering_steps, comparison.steps)?
				match comparison.ordering {
					Equal => {
						$error = Invalid(DuplicateByteKey({ index: $index }))
					}
					Greater => {
						$error = Invalid(NonMonotonicByteKey({ index: $index }))
					}
					Less => {}
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ entries_checked: $entries_checked, key_bytes_checked: $key_bytes_checked, ordering_steps: $ordering_steps })
	}
}

validate_number_entries : List(KernelIndex.NumberEntry), KernelIndex.NumberKind, U64 -> Try({ entries_checked : U64, key_bytes_checked : U64, ordering_steps : U64 }, KernelIndex.Error)
validate_number_entries = |entries, kind, value_count| {
	is_parent_tree = match kind {
		NumberTree => False
		ParentTree => True
	}
	var $entries_checked = 0
	var $ordering_steps = 0
	var $index = 0
	var $error = NoError
	while $index < entries.len() and $error == NoError {
		entry = list_at(entries, $index)
		key = KernelIndex.NumberEntry.key(entry)
		value = KernelIndex.NumberEntry.value(entry)
		if is_parent_tree and key < 0 {
			$error = Invalid(NegativeParentKey({ index: $index, key }))
		} else if KernelObject.ValueId.index(value) >= value_count {
			$error = Invalid(ValueIndexOutOfRange({ available: value_count, index: $index, value }))
		} else {
			$entries_checked = checked_add($entries_checked, 1)?
			if $index > 0 {
				$ordering_steps = checked_add($ordering_steps, 1)?
				previous = KernelIndex.NumberEntry.key(list_at(entries, $index - 1))
				if key == previous {
					$error = Invalid(DuplicateNumberKey({ index: $index }))
				} else if key < previous {
					$error = Invalid(NonMonotonicNumberKey({ index: $index }))
				}
			}
		}
		$index = $index + 1
	}

	match $error {
		Invalid(error) => Err(error)
		NoError => Ok({ entries_checked: $entries_checked, key_bytes_checked: 0, ordering_steps: $ordering_steps })
	}
}

index_node : KernelBalanced.Shape, U64, U64 -> KernelIndex.Node
index_node = |shape, level, index| {
	entry_span = KernelBalanced.Shape.item_span(shape, level, index)
	start = KernelBalanced.Span.start(entry_span)
	length = KernelBalanced.Span.length(entry_span)
	children = if level == KernelBalanced.Shape.leaf_level(shape) {
		Entries(entry_span)
	} else {
		Nodes(KernelBalanced.Shape.child_span(shape, level, index))
	}
	limits = if level == 0 {
		NoLimits
	} else {
		NodeLimits({ first_index: start, last_index: start + length - 1 })
	}
	KernelIndex.Node.{ children, entry_span, limits }
}

compare_bytes : List(U8), List(U8) -> Try({ ordering : [Equal, Greater, Less], steps : U64 }, KernelIndex.Error)
compare_bytes = |left, right| {
	shared = if left.len() < right.len() left.len() else right.len()
	var $index = 0
	var $ordering = Equal
	var $steps = 1
	while $index < shared and $ordering == Equal {
		$steps = checked_add($steps, 1)?
		left_byte = list_at(left, $index)
		right_byte = list_at(right, $index)
		if left_byte < right_byte {
			$ordering = Less
		} else if left_byte > right_byte {
			$ordering = Greater
		}
		$index = $index + 1
	}

	ordering = match $ordering {
		Less => Less
		Greater => Greater
		Equal => if left.len() < right.len() {
			Less
		} else if left.len() > right.len() {
			Greater
		} else {
			Equal
		}
	}
	Ok({ ordering, steps: $steps })
}

checked_add : U64, U64 -> Try(U64, KernelIndex.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "sealed index invariant failed"
	}
}

test_limits : KernelIndex.Limits
test_limits = KernelIndex.Limits.make({ max_entries: 4096, max_key_bytes: 8, value_count: 4096 })

test_value : U64 -> KernelObject.ValueId
test_value = |index| KernelObject.ValueId.from_index(index)

byte_entry : List(U8), U64 -> KernelIndex.ByteEntry
byte_entry = |key, index| KernelIndex.ByteEntry.make(key, test_value(index))

number_entry : I64 -> KernelIndex.NumberEntry
number_entry = |key| KernelIndex.NumberEntry.make(key, test_value(key.to_u64_wrap()))

four_byte_key : U64 -> List(U8)
four_byte_key = |value| [
	value.shr_wrap(24).to_u8_wrap(),
	value.shr_wrap(16).to_u8_wrap(),
	value.shr_wrap(8).to_u8_wrap(),
	value.to_u8_wrap(),
]

byte_entries : U64 -> List(KernelIndex.ByteEntry)
byte_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$entries = $entries.append(byte_entry(four_byte_key($index), $index))
		$index = $index + 1
	}
	$entries
}

number_entries : U64 -> List(KernelIndex.NumberEntry)
number_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$entries = $entries.append(number_entry($index.to_i64_wrap()))
		$index = $index + 1
	}
	$entries
}

## Byte-key trees use unsigned lexicographic ordering and shared balanced nodes.
expect {
	tree = KernelIndex.ByteTree.build(byte_entries(33), NameTree, test_limits)?
	root = KernelIndex.ByteTree.node(tree, 0, 0)
	right = KernelIndex.ByteTree.node(tree, 1, 1)

	KernelIndex.ByteTree.entry_count(tree) == 33 and
		KernelIndex.ByteTree.node_count(tree) == 3 and
			KernelIndex.Node.limits(root) == NoLimits and
				KernelIndex.Node.limits(right) == NodeLimits({ first_index: 32, last_index: 32 })
}

## ID trees retain their distinct sealed kind without changing key policy.
expect {
	tree = KernelIndex.ByteTree.build(byte_entries(1), IDTree, test_limits)?
	match KernelIndex.ByteTree.kind(tree) {
		IDTree => True
		NameTree => False
	}
}

## Duplicate and descending byte keys are distinct named failures.
expect {
	duplicate = [byte_entry([1], 0), byte_entry([1], 1)]
	descending = [byte_entry([2], 0), byte_entry([1], 1)]

	match KernelIndex.ByteTree.build(duplicate, NameTree, test_limits) {
		Err(DuplicateByteKey({ index })) => index == 1
		_ => False
	} and match KernelIndex.ByteTree.build(descending, NameTree, test_limits) {
		Err(NonMonotonicByteKey({ index })) => index == 1
		_ => False
	}
}

## Byte ordering is unsigned lexicographic, including prefix and empty keys.
expect {
	ordered = [byte_entry([], 0), byte_entry([0], 1), byte_entry([0, 255], 2), byte_entry([1], 3)]
	prefix_reversed = [byte_entry([1, 0], 0), byte_entry([1], 1)]
	unsigned_reversed = [byte_entry([255], 0), byte_entry([0], 1)]

	match KernelIndex.ByteTree.build(ordered, NameTree, test_limits) {
		Ok(_) => True
		Err(_) => False
	} and match KernelIndex.ByteTree.build(prefix_reversed, NameTree, test_limits) {
		Err(NonMonotonicByteKey({ index })) => index == 1
		_ => False
	} and match KernelIndex.ByteTree.build(unsigned_reversed, NameTree, test_limits) {
		Err(NonMonotonicByteKey({ index })) => index == 1
		_ => False
	}
}

## Byte-key size limits fail before shape allocation.
expect match KernelIndex.ByteTree.build([byte_entry([0, 1, 2], 0)], NameTree, KernelIndex.Limits.make({ max_entries: 1, max_key_bytes: 2, value_count: 1 })) {
	Err(KeyBytesLimitExceeded({ attempted, index, limit })) => attempted == 3 and index == 0 and limit == 2
	_ => False
}

## Number trees retain exact stress topology and linear validation work.
expect {
	tree = KernelIndex.NumberTree.build(number_entries(4096), NumberTree, test_limits)?
	work = KernelIndex.NumberTree.work(tree)

	KernelIndex.NumberTree.node_count(tree) == 133 and
		KernelIndex.Work.entries_checked(work) == 4096 and
			KernelIndex.Work.ordering_steps(work) == 4095
}

## ParentTree keys are non-negative in addition to being strictly monotonic.
expect match KernelIndex.NumberTree.build([number_entry(-1)], ParentTree, test_limits) {
	Err(NegativeParentKey({ index, key })) => index == 0 and key == -1
	_ => False
}

## Sealing rejects values that do not exist in the earlier object-value store.
expect match KernelIndex.NumberTree.build([number_entry(1)], NumberTree, KernelIndex.Limits.make({ max_entries: 1, max_key_bytes: 0, value_count: 1 })) {
	Err(ValueIndexOutOfRange({ available, index, value })) => available == 1 and index == 0 and KernelObject.ValueId.index(value) == 1
	_ => False
}

## Duplicate and descending number keys are distinct named failures.
expect {
	duplicate = [number_entry(1), number_entry(1)]
	descending = [number_entry(2), number_entry(1)]

	match KernelIndex.NumberTree.build(duplicate, NumberTree, test_limits) {
		Err(DuplicateNumberKey({ index })) => index == 1
		_ => False
	} and match KernelIndex.NumberTree.build(descending, NumberTree, test_limits) {
		Err(NonMonotonicNumberKey({ index })) => index == 1
		_ => False
	}
}

## Empty and over-limit entry lists are rejected before validation or shape work.
expect {
	empty = KernelIndex.ByteTree.build([], NameTree, test_limits)
	over = KernelIndex.NumberTree.build(number_entries(2), NumberTree, KernelIndex.Limits.make({ max_entries: 1, max_key_bytes: 0, value_count: 2 }))

	match empty {
		Err(EntryCountZero) => True
		_ => False
	} and match over {
		Err(EntryLimitExceeded({ attempted, limit })) => attempted == 2 and limit == 1
		_ => False
	}
}
