import KernelBalanced
import KernelEmit
import KernelIndex
import KernelObject
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

	generate_blank_with_indexes : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank_with_indexes = |entry_count| {
		limits = KernelIndex.Limits.make({ max_entries: entry_count, max_key_bytes: 4, value_count: entry_count })
		byte_entries = index_byte_entries(entry_count)
		number_entries = index_number_entries(entry_count)
		name_tree = build_byte_tree(byte_entries, NameTree, limits)
		id_tree = build_byte_tree(byte_entries, IDTree, limits)
		number_tree = build_number_tree(number_entries, NumberTree, limits)
		parent_tree = build_number_tree(number_entries, ParentTree, limits)
		name_audit = audit_byte_tree(name_tree)
		id_audit = audit_byte_tree(id_tree)
		number_audit = audit_number_tree(number_tree)
		parent_audit = audit_number_tree(parent_tree)
		blank = generate_blank(entry_count)

		nodes = name_audit.nodes + id_audit.nodes + number_audit.nodes + parent_audit.nodes
		limit_nodes = name_audit.limit_nodes + id_audit.limit_nodes + number_audit.limit_nodes + parent_audit.limit_nodes
		leaf_entries = name_audit.leaf_entries + id_audit.leaf_entries + number_audit.leaf_entries + parent_audit.leaf_entries
		limit_checksum = name_audit.limit_checksum + id_audit.limit_checksum + number_audit.limit_checksum + parent_audit.limit_checksum
		name_work = KernelIndex.ByteTree.work(name_tree)
		id_work = KernelIndex.ByteTree.work(id_tree)
		number_work = KernelIndex.NumberTree.work(number_tree)
		parent_work = KernelIndex.NumberTree.work(parent_tree)
		entries_checked = KernelIndex.Work.entries_checked(name_work) + KernelIndex.Work.entries_checked(id_work) + KernelIndex.Work.entries_checked(number_work) + KernelIndex.Work.entries_checked(parent_work)
		key_bytes_checked = KernelIndex.Work.key_bytes_checked(name_work) + KernelIndex.Work.key_bytes_checked(id_work) + KernelIndex.Work.key_bytes_checked(number_work) + KernelIndex.Work.key_bytes_checked(parent_work)
		ordering_steps = KernelIndex.Work.ordering_steps(name_work) + KernelIndex.Work.ordering_steps(id_work) + KernelIndex.Work.ordering_steps(number_work) + KernelIndex.Work.ordering_steps(parent_work)

		if entry_count != 4096 or nodes != 532 or limit_nodes != 528 or leaf_entries != 16384 or limit_checksum != 2162160 or entries_checked != 16384 or key_bytes_checked != 32768 or ordering_steps != 49110 {
			crash "Gate 1 index stress evidence changed"
		}

		{
			bytes: blank.bytes,
			work: [
				entry_count * 4,
				nodes,
				limit_nodes,
				leaf_entries,
				limit_checksum,
				entries_checked,
				key_bytes_checked,
				ordering_steps,
				blank.bytes.len(),
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

build_byte_tree : List(KernelIndex.ByteEntry), KernelIndex.ByteKind, KernelIndex.Limits -> KernelIndex.ByteTree
build_byte_tree = |entries, kind, limits| match KernelIndex.ByteTree.build(entries, kind, limits) {
	Ok(tree) => tree
	Err(_) => {
		crash "Gate 1 byte-key stress plan invariant failed"
	}
}

build_number_tree : List(KernelIndex.NumberEntry), KernelIndex.NumberKind, KernelIndex.Limits -> KernelIndex.NumberTree
build_number_tree = |entries, kind, limits| match KernelIndex.NumberTree.build(entries, kind, limits) {
	Ok(tree) => tree
	Err(_) => {
		crash "Gate 1 number-key stress plan invariant failed"
	}
}

audit_byte_tree : KernelIndex.ByteTree -> { leaf_entries : U64, limit_checksum : U64, limit_nodes : U64, nodes : U64 }
audit_byte_tree = |tree| {
	var $nodes = 0
	var $limit_nodes = 0
	var $leaf_entries = 0
	var $limit_checksum = 0
	var $level = 0
	while $level < KernelIndex.ByteTree.level_count(tree) {
		var $node_index = 0
		while $node_index < KernelIndex.ByteTree.node_count_at(tree, $level) {
			node = KernelIndex.ByteTree.node(tree, $level, $node_index)
			entry_span = KernelIndex.Node.entry_span(node)
			start = KernelBalanced.Span.start(entry_span)
			length = KernelBalanced.Span.length(entry_span)
			$nodes = $nodes + 1
			match KernelIndex.Node.limits(node) {
				NoLimits => if $level != 0 {
					crash "Gate 1 byte-key node omitted required limits"
				}
				NodeLimits({ first_index, last_index }) => {
					if $level == 0 or first_index != start or last_index != start + length - 1 {
						crash "Gate 1 byte-key node limits changed"
					}
					$limit_nodes = $limit_nodes + 1
					$limit_checksum = $limit_checksum + first_index + last_index
				}
			}
			match KernelIndex.Node.children(node) {
				Entries(span) => {
					$leaf_entries = $leaf_entries + KernelBalanced.Span.length(span)
				}
				Nodes(_) => {}
			}
			$node_index = $node_index + 1
		}
		$level = $level + 1
	}
	{ leaf_entries: $leaf_entries, limit_checksum: $limit_checksum, limit_nodes: $limit_nodes, nodes: $nodes }
}

audit_number_tree : KernelIndex.NumberTree -> { leaf_entries : U64, limit_checksum : U64, limit_nodes : U64, nodes : U64 }
audit_number_tree = |tree| {
	var $nodes = 0
	var $limit_nodes = 0
	var $leaf_entries = 0
	var $limit_checksum = 0
	var $level = 0
	while $level < KernelIndex.NumberTree.level_count(tree) {
		var $node_index = 0
		while $node_index < KernelIndex.NumberTree.node_count_at(tree, $level) {
			node = KernelIndex.NumberTree.node(tree, $level, $node_index)
			entry_span = KernelIndex.Node.entry_span(node)
			start = KernelBalanced.Span.start(entry_span)
			length = KernelBalanced.Span.length(entry_span)
			$nodes = $nodes + 1
			match KernelIndex.Node.limits(node) {
				NoLimits => if $level != 0 {
					crash "Gate 1 number-key node omitted required limits"
				}
				NodeLimits({ first_index, last_index }) => {
					if $level == 0 or first_index != start or last_index != start + length - 1 {
						crash "Gate 1 number-key node limits changed"
					}
					$limit_nodes = $limit_nodes + 1
					$limit_checksum = $limit_checksum + first_index + last_index
				}
			}
			match KernelIndex.Node.children(node) {
				Entries(span) => {
					$leaf_entries = $leaf_entries + KernelBalanced.Span.length(span)
				}
				Nodes(_) => {}
			}
			$node_index = $node_index + 1
		}
		$level = $level + 1
	}
	{ leaf_entries: $leaf_entries, limit_checksum: $limit_checksum, limit_nodes: $limit_nodes, nodes: $nodes }
}

index_byte_entries : U64 -> List(KernelIndex.ByteEntry)
index_byte_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		key = [
			$index.shr_wrap(24).to_u8_wrap(),
			$index.shr_wrap(16).to_u8_wrap(),
			$index.shr_wrap(8).to_u8_wrap(),
			$index.to_u8_wrap(),
		]
		value = KernelObject.ValueId.from_index($index)
		$entries = $entries.append(KernelIndex.ByteEntry.make(key, value))
		$index = $index + 1
	}
	$entries
}

index_number_entries : U64 -> List(KernelIndex.NumberEntry)
index_number_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		value = KernelObject.ValueId.from_index($index)
		$entries = $entries.append(KernelIndex.NumberEntry.make($index.to_i64_wrap(), value))
		$index = $index + 1
	}
	$entries
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
