import KernelEmit
import KernelSeal
import KernelStructure

Gate1Evidence :: [].{
	generate_blank : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank = |page_count| {
		plan = match KernelStructure.build_blank(page_count, A4) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 stress plan invariant failed"
			}
		}
		sealed = KernelStructure.Plan.sealed(plan)
		counts = KernelSeal.Plan.counts(sealed)
		build = KernelSeal.Plan.build_work(sealed)
		seal = KernelSeal.Plan.seal_work(sealed)
		bytes = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 stress emission invariant failed"
			}
		}

		{
			bytes,
			work: [
				page_count,
				KernelStructure.Plan.tree_node_count(plan),
				counts.objects,
				counts.values,
				counts.array_items,
				counts.dictionary_entries,
				build.edges_appended,
				seal.references_checked,
				bytes.len(),
			],
		}
	}

	retention_probe : U8 -> {
		backing : List(U8),
		bytes : List(U8),
		owned : List(U8),
		shared : List(U8),
		source : List(U8),
		work : List(U64),
	}
	retention_probe = |fill| {
		backing = List.repeat(fill, 8192)
		source = backing.sublist({ start: 4096, len: 64 })
		plan = match KernelStructure.build_unchanged_stream_probe(source) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 retention plan invariant failed"
			}
		}
		buffered = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => {
				crash "Gate 1 buffered retention invariant failed"
			}
		}
		shared_result = capture_resource(plan, ShareResourceChunks)
		owned_result = capture_resource(plan, OwnResourceChunks)

		if shared_result.bytes != buffered or owned_result.bytes != buffered {
			crash "Gate 1 retention policies changed output bytes"
		}

		{
			backing,
			bytes: buffered,
			owned: owned_result.resource,
			shared: shared_result.resource,
			source,
			work: [
				buffered.len(),
				shared_result.bytes.len(),
				owned_result.bytes.len(),
				shared_result.ranges,
				owned_result.ranges,
				shared_result.copied_bytes,
				owned_result.copied_bytes,
				source.len(),
			],
		}
	}
}

capture_resource : KernelStructure.Plan,
[OwnResourceChunks, ShareResourceChunks] -> {
	bytes : List(U8),
	copied_bytes : U64,
	ranges : U64,
	resource : List(U8),
}
capture_resource = |plan, retention| {
	var $encoder = match KernelEmit.start(plan, retention) {
		Ok(value) => value
		Err(_) => {
			crash "Gate 1 retention encoder invariant failed"
		}
	}
	var $bytes = []
	var $copied_bytes = 0
	var $ranges = 0
	var $resource = []
	var $done = False
	while $done == False {
		match KernelEmit.Encoder.next_infallible($encoder) {
			Done => {
				$done = True
			}
			Emit(segment, next) => {
				$bytes = append_all($bytes, segment.bytes)
				$copied_bytes = KernelEmit.Encoder.copied_resource_bytes(next)
				match segment.ownership {
					Generated => {}
					OwnedResource => {
						$ranges = $ranges + 1
						$resource = segment.bytes
					}
					SharedResource => {
						$ranges = $ranges + 1
						$resource = segment.bytes
					}
				}
				$encoder = next
			}
		}
	}

	{ bytes: $bytes, copied_bytes: $copied_bytes, ranges: $ranges, resource: $resource }
}

append_all : List(U8), List(U8) -> List(U8)
append_all = |target, source| {
	length = source.len()
	var $out = List.reserve(target, length)
	var $index = 0
	while $index < length {
		$out = $out.append(list_at(source, $index))
		$index = $index + 1
	}
	$out
}

list_at : List(a), U64 -> a
list_at = |list, index| match list.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 1 evidence index invariant failed"
	}
}
