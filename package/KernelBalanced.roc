KernelBalanced :: [].{
	Error : [
		ArithmeticOverflow,
		ItemCountZero,
		ItemLimitExceeded({ attempted : U64, limit : U64 }),
	]

	Span :: { length : U64, start : U64 }.{
		length : Span -> U64
		length = |span| span.length

		start : Span -> U64
		start = |span| span.start
	}

	Shape :: {
		item_count : U64,
		level_counts : List(U64),
		level_offsets : List(U64),
		nodes : U64,
	}.{
		build : U64, U64 -> Try(Shape, Error)
		build = |item_count, item_limit| {
			if item_count == 0 {
				Err(ItemCountZero)
			} else if item_count > item_limit {
				Err(ItemLimitExceeded({ attempted: item_count, limit: item_limit }))
			} else {
				build_nonempty_shape(item_count)
			}
		}

		child_span : Shape, U64, U64 -> Span
		child_span = |shape, level, node| {
			if level >= shape.level_counts.len() {
				crash "balanced shape level invariant failed"
			} else if node >= list_at(shape.level_counts, level) {
				crash "balanced shape node invariant failed"
			} else if level + 1 >= shape.level_counts.len() {
				crash "balanced leaf node has no child-node span"
			}
			start_in_level = node * fixed_fanout
			available = list_at(shape.level_counts, level + 1)
			Span.{
				length: bounded_count(start_in_level, available, fixed_fanout),
				start: list_at(shape.level_offsets, level + 1) + start_in_level,
			}
		}

		fanout : U64
		fanout = fixed_fanout

		item_count : Shape -> U64
		item_count = |shape| shape.item_count

		item_span : Shape, U64, U64 -> Span
		item_span = |shape, level, node| {
			if level >= shape.level_counts.len() {
				crash "balanced shape level invariant failed"
			} else if node >= list_at(shape.level_counts, level) {
				crash "balanced shape node invariant failed"
			}
			capacity = node_item_capacity(shape, level)
			start = node * capacity
			Span.{ start, length: bounded_count(start, shape.item_count, capacity) }
		}

		leaf_level : Shape -> U64
		leaf_level = |shape| shape.level_counts.len() - 1

		level_count : Shape -> U64
		level_count = |shape| shape.level_counts.len()

		level_node_count : Shape, U64 -> U64
		level_node_count = |shape, level| list_at(shape.level_counts, level)

		level_offset : Shape, U64 -> U64
		level_offset = |shape, level| list_at(shape.level_offsets, level)

		node_count : Shape -> U64
		node_count = |shape| shape.nodes
	}
}

fixed_fanout : U64
fixed_fanout = 32

build_nonempty_shape : U64 -> Try(KernelBalanced.Shape, KernelBalanced.Error)
build_nonempty_shape = |item_count| {
	var $bottom_counts = [ceil_div(item_count, fixed_fanout)?]
	var $current = list_at($bottom_counts, 0)
	while $current > 1 {
		$current = ceil_div($current, fixed_fanout)?
		$bottom_counts = $bottom_counts.append($current)
	}

	level_count = $bottom_counts.len()
	var $level_counts = List.with_capacity(level_count)
	var $reverse_index = level_count
	while $reverse_index > 0 {
		$reverse_index = $reverse_index - 1
		$level_counts = $level_counts.append(list_at($bottom_counts, $reverse_index))
	}

	var $level_offsets = List.with_capacity(level_count)
	var $nodes = 0
	var $index = 0
	while $index < level_count {
		$level_offsets = $level_offsets.append($nodes)
		$nodes = checked_add($nodes, list_at($level_counts, $index))?
		$index = $index + 1
	}

	Ok(
		KernelBalanced.Shape.{
			item_count,
			level_counts: $level_counts,
			level_offsets: $level_offsets,
			nodes: $nodes,
		},
	)
}

node_item_capacity : KernelBalanced.Shape, U64 -> U64
node_item_capacity = |shape, level| {
	remaining = KernelBalanced.Shape.level_count(shape) - level
	var $capacity = 1
	var $index = 0
	while $index < remaining {
		if $capacity > U64.div_by(KernelBalanced.Shape.item_count(shape), fixed_fanout) {
			$capacity = KernelBalanced.Shape.item_count(shape)
		} else {
			$capacity = $capacity * fixed_fanout
		}
		$index = $index + 1
	}
	$capacity
}

bounded_count : U64, U64, U64 -> U64
bounded_count = |start, available, limit|
	if start >= available {
		0
	} else {
		remaining = available - start
		if remaining < limit remaining else limit
	}

ceil_div : U64, U64 -> Try(U64, KernelBalanced.Error)
ceil_div = |value, divisor| {
	quotient = U64.div_by(value, divisor)
	if U64.mod_by(value, divisor) == 0 {
		Ok(quotient)
	} else {
		checked_add(quotient, 1)
	}
}

checked_add : U64, U64 -> Try(U64, KernelBalanced.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(total) => Ok(total)
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "balanced shape index invariant failed"
	}
}

## One item produces one root that is also a leaf.
expect {
	shape = KernelBalanced.Shape.build(1, 1024)?
	span = KernelBalanced.Shape.item_span(shape, 0, 0)

	KernelBalanced.Shape.level_count(shape) == 1 and
		KernelBalanced.Shape.node_count(shape) == 1 and
			KernelBalanced.Span.start(span) == 0 and
				KernelBalanced.Span.length(span) == 1
}

## The 33rd item creates two leaves beneath one root.
expect {
	shape = KernelBalanced.Shape.build(33, 1024)?
	children = KernelBalanced.Shape.child_span(shape, 0, 0)
	left = KernelBalanced.Shape.item_span(shape, 1, 0)
	right = KernelBalanced.Shape.item_span(shape, 1, 1)

	KernelBalanced.Shape.level_count(shape) == 2 and
		KernelBalanced.Shape.node_count(shape) == 3 and
			KernelBalanced.Span.start(children) == 1 and
				KernelBalanced.Span.length(children) == 2 and
					KernelBalanced.Span.length(left) == 32 and
						KernelBalanced.Span.start(right) == 32 and
							KernelBalanced.Span.length(right) == 1
}

## Thousands of items retain the same fixed-fanout left-packed shape as pages.
expect {
	shape = KernelBalanced.Shape.build(4096, 1048576)?

	KernelBalanced.Shape.level_count(shape) == 3 and
		KernelBalanced.Shape.level_node_count(shape, 0) == 1 and
			KernelBalanced.Shape.level_node_count(shape, 1) == 4 and
				KernelBalanced.Shape.level_node_count(shape, 2) == 128 and
					KernelBalanced.Shape.node_count(shape) == 133
}

## Shape limits fail before allocating level storage.
expect match KernelBalanced.Shape.build(1025, 1024) {
	Err(ItemLimitExceeded({ attempted, limit })) => attempted == 1025 and limit == 1024
	_ => False
}

## Empty index structures are rejected before shape allocation.
expect match KernelBalanced.Shape.build(0, 1024) {
	Err(ItemCountZero) => True
	_ => False
}

## The package maximum has four levels and an exact fixed-fanout node count.
expect {
	shape = KernelBalanced.Shape.build(1048576, 1048576)?

	KernelBalanced.Shape.level_count(shape) == 4 and
		KernelBalanced.Shape.level_node_count(shape, 0) == 1 and
			KernelBalanced.Shape.level_node_count(shape, 1) == 32 and
				KernelBalanced.Shape.level_node_count(shape, 2) == 1024 and
					KernelBalanced.Shape.level_node_count(shape, 3) == 32768 and
						KernelBalanced.Shape.node_count(shape) == 33825
}
