KernelResourceRadix :: [].{

	## Iterative most-significant-byte radix refinement over one descriptor/length
	## partition. Every entry contributes a byte visit only while it is still tied
	## with another entry, so total work is bounded by the partition's entries plus
	## its bytes; a counting pass runs only at a real split, of which there are at
	## most `entries - 1`. There is no pairwise comparison.
	order : U64, U64, U64, (U64, U64 -> U8) -> { byte_visits : U64, order : List(U64), passes : U64 }
	order = |start, end, length, byte_at| {
		var $order = List.with_capacity(end - start)
		var $seed = start
		while $seed < end {
			$order = $order.append($seed)
			$seed = $seed + 1
		}
		var $byte_visits = 0
		var $passes = 0
		var $stack = [{ depth: 0, end: end - start, start: 0 }]
		while $stack.len() > 0 {
			segment = list_at($stack, $stack.len() - 1)
			$stack = $stack.sublist({ len: $stack.len() - 1, start: 0 })
			var $depth = segment.depth
			var $splitting = False
			while !$splitting and $depth < length {
				first = byte_at(list_at($order, segment.start), $depth)
				var $scan = segment.start
				var $same = True
				while $scan < segment.end {
					if byte_at(list_at($order, $scan), $depth) != first {
						$same = False
					}
					$scan = $scan + 1
				}
				$byte_visits = $byte_visits + (segment.end - segment.start)
				if $same {
					$depth = $depth + 1
				} else {
					$splitting = True
				}
			}
			if $splitting {
				var $counts = List.repeat(0, 256)
				var $scan = segment.start
				while $scan < segment.end {
					value = byte_at(list_at($order, $scan), $depth).to_u64()
					$counts = list_set($counts, value, list_at($counts, value) + 1)
					$scan = $scan + 1
				}
				$byte_visits = $byte_visits + (segment.end - segment.start)
				var $offsets = List.repeat(0, 256)
				var $running = 0
				var $value = 0
				while $value < 256 {
					$offsets = list_set($offsets, $value, $running)
					$running = $running + list_at($counts, $value)
					$value = $value + 1
				}
				var $scratch = List.repeat(0, segment.end - segment.start)
				$scan = segment.start
				while $scan < segment.end {
					value = byte_at(list_at($order, $scan), $depth).to_u64()
					$scratch = list_set($scratch, list_at($offsets, value), list_at($order, $scan))
					$offsets = list_set($offsets, value, list_at($offsets, value) + 1)
					$scan = $scan + 1
				}
				$byte_visits = $byte_visits + (segment.end - segment.start)
				$scan = 0
				while $scan < $scratch.len() {
					$order = list_set($order, segment.start + $scan, list_at($scratch, $scan))
					$scan = $scan + 1
				}
				$passes = $passes + 1
				$running = segment.start
				$value = 0
				while $value < 256 {
					size = list_at($counts, $value)
					if size > 1 {
						$stack = $stack.append({ depth: $depth + 1, end: $running + size, start: $running })
					}
					$running = $running + size
					$value = $value + 1
				}
			}
		}
		{ byte_visits: $byte_visits, order: $order, passes: $passes }
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => crash "resource radix index escaped"
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => crash "resource radix update escaped"
}
