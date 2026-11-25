import fuzz.Solve
import pdf.KernelBalanced
import pdf.KernelStructure

PageTreeProof := [].{}

## Every level of the structural page tree has at least one child and at
## most the page cap enforced by KernelStructure. Other index trees can
## admit larger counts, and this proof covers one level of child spans.
items = Solve.u64_in(1, KernelStructure.max_pages)

width = Solve.Uint.from_u64(KernelBalanced.Shape.fanout)

## A nonempty level has at most one group per child. Its first group
## starts at zero, and its final group covers exactly the remaining children.
expect Solve.prove_within(
	items,
	|available| {
		count = KernelBalanced.Partition.group_count(available, width)
		last_start = KernelBalanced.Partition.group_start(count - 1, width)
		Solve.all([
			count.gt(0),
			count.lte(available),
			KernelBalanced.Partition.group_start(Solve.num(0), width).eq(0),
			last_start.lt(available),
			(available - last_start).lte(width),
			(last_start + KernelBalanced.Partition.group_length(last_start, available, width, symbolic_minimum)).eq(available),
		])
	},
	5000,
) == Ok(Proved)

## The checked node index reaches a nonempty child span. Adjacent spans
## meet, so no child is skipped or assigned to both groups.
expect Solve.prove_within(
	{
		available: items,
		node: Solve.u64_in(0, KernelStructure.max_pages - 1),
	}.Solve,
	|{ available, node }| {
		count = KernelBalanced.Partition.group_count(available, width)
		start = KernelBalanced.Partition.group_start(node, width)
		length = KernelBalanced.Partition.group_length(start, available, width, symbolic_minimum)
		node.lt(count).implies(
			Solve.all([
				start.lt(available),
				length.gt(0),
				length.lte(width),
				(start + length).lte(available),
				(node + 1).lt(count).implies((start + length).eq(KernelBalanced.Partition.group_start(node + 1, width))),
			]),
		)
	},
	5000,
) == Ok(Proved)

symbolic_minimum : Solve.Uint, Solve.Uint -> Solve.Uint
symbolic_minimum = |left, right| Solve.if_else(left.lte(right), left, right)

## Walk the actual shape at fanout boundaries and at the page limit. Each
## next span must start where the last one ended in the dense node store.
covers_children : U64 -> Bool
covers_children = |pages| {
	shape = match KernelBalanced.Shape.build(pages, KernelStructure.max_pages) {
		Ok(value) => value
		Err(_) => return False
	}
	var $level = 0
	while $level < KernelBalanced.Shape.leaf_level(shape) {
		child_level = $level + 1
		first_child = KernelBalanced.Shape.level_offset(shape, child_level)
		limit = first_child + KernelBalanced.Shape.level_node_count(shape, child_level)
		parent_count = KernelBalanced.Shape.level_node_count(shape, $level)
		var $next_child = first_child
		var $parent = 0
		while $parent < parent_count {
			span = KernelBalanced.Shape.child_span(shape, $level, $parent)
			length = KernelBalanced.Span.length(span)
			if KernelBalanced.Span.start(span) != $next_child or length == 0 or length > KernelBalanced.Shape.fanout {
				return False
			}
			$next_child = $next_child + length
			$parent = $parent + 1
		}
		if $next_child != limit {
			return False
		}
		$level = $level + 1
	}
	True
}

expect [1, 31, 32, 33, 1024, 1025, KernelStructure.max_pages].all(covers_children)
