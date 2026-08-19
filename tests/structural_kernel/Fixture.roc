import pdf.KernelBalanced
import pdf.KernelDeflate
import pdf.KernelEmit
import pdf.KernelIndex
import pdf.KernelLex
import pdf.KernelObject
import pdf.KernelOutline
import pdf.KernelResource
import pdf.KernelSeal
import pdf.KernelStructure

Fixture :: [].{
	generate_blank : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank = |page_count| {
		plan = match KernelStructure.build_blank(page_count, A4) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel stress plan invariant failed"
			}
		}
		sealed = KernelStructure.Plan.sealed(plan)
		counts = KernelSeal.Plan.counts(sealed)
		build = KernelSeal.Plan.build_work(sealed)
		seal = KernelSeal.Plan.seal_work(sealed)
		bytes = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel stress emission invariant failed"
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
			crash "structural-kernel index stress evidence changed"
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

	generate_blank_with_outline : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank_with_outline = |entry_count| {
		entries = outline_entries(entry_count)
		limits = KernelOutline.Limits.make({ max_depth: 1, max_entries: entry_count, text_string_count: entry_count, value_count: entry_count })
		plan = match KernelOutline.Plan.build(entries, limits) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel outline stress plan invariant failed"
			}
		}
		audit = audit_outline(plan)
		work = KernelOutline.Plan.work(plan)
		blank = generate_blank(entry_count)

		if entry_count != 4096 or KernelOutline.Plan.root_count(plan) != 2112 or KernelOutline.ItemId.index(KernelOutline.Plan.root_first(plan)) != 0 or KernelOutline.ItemId.index(KernelOutline.Plan.root_last(plan)) != 4064 or audit.top_level != 128 or audit.parents != 128 or audit.leaves != 3968 or audit.previous_links != 3967 or audit.next_links != 3967 or audit.identity_checksum != 16773120 or KernelOutline.Work.entries_checked(work) != 4096 or KernelOutline.Work.items_appended(work) != 4096 or KernelOutline.Work.item_rewrites(work) != 15999 or KernelOutline.Work.count_accumulations(work) != 4096 or KernelOutline.Work.max_depth_seen(work) != 1 {
			crash "structural-kernel outline stress evidence changed"
		}

		{
			bytes: blank.bytes,
			work: [
				entry_count,
				KernelOutline.Plan.root_count(plan),
				audit.top_level,
				audit.parents,
				audit.leaves,
				audit.previous_links,
				audit.next_links,
				audit.identity_checksum,
				KernelOutline.Work.entries_checked(work),
				KernelOutline.Work.items_appended(work),
				KernelOutline.Work.item_rewrites(work),
				KernelOutline.Work.count_accumulations(work),
				KernelOutline.Work.max_depth_seen(work),
				blank.bytes.len(),
			],
		}
	}

	generate_blank_with_resource_names : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank_with_resource_names = |entry_count| {
		entries = resource_name_entries(entry_count)
		plan = match KernelResource.Plan.build(
			entries,
			KernelResource.Limits.make({ max_entries: entry_count, max_name_bytes: U64.highest }),
		) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel resource-name stress plan invariant failed"
			}
		}
		audit = audit_resource_names(plan)
		work = KernelResource.Plan.work(plan)
		blank = generate_blank(entry_count)

		if entry_count != 4096 or KernelResource.Plan.entry_count(plan) != 4096 or KernelResource.Plan.name_bytes(plan) != 19373 or audit.byte_visits != 19373 {
			crash "structural-kernel resource-name stress evidence changed"
		}

		{
			bytes: blank.bytes,
			work: [
				entry_count,
				KernelResource.Plan.entry_count(plan),
				KernelResource.Plan.name_bytes(plan),
				KernelResource.Work.entries_checked(work),
				KernelResource.Work.identity_checks(work),
				KernelResource.Work.kind_comparisons(work),
				audit.byte_visits,
				audit.checksum,
				blank.bytes.len(),
			],
		}
	}

	generate_blank_with_lexical_values : U64 -> { bytes : List(U8), work : List(U64) }
	generate_blank_with_lexical_values = |entry_count| {
		metrics = if entry_count == 2048 {
			{ emitted_bytes: 206848, source_bytes: 24576, tokens: 18432 }
		} else if entry_count == 4096 {
			{ emitted_bytes: 413696, source_bytes: 49152, tokens: 36864 }
		} else {
			crash "structural-kernel lexical stress fixture requires 2048 or 4096 bundles"
		}
		seed = if entry_count == 2048 4096 else entry_count
		space = U64.mod_by(seed, 4064).to_u8_wrap()
		name = match KernelLex.Name.from_bytes([65, space, 66, 47, 35]) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel lexical name invariant failed"
			}
		}
		coefficient = seed.to_i64_wrap() - 2896
		scale = U64.mod_by(seed, 4093).to_u8_wrap()
		decimal = match KernelLex.Decimal.from_coefficient(coefficient, scale) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel lexical decimal invariant failed"
			}
		}
		byte_string = [0, U64.mod_by(seed, 3841).to_u8_wrap()]
		text_string = KernelLex.Text.from_str("A😀")
		var $lexical = List.with_capacity(metrics.emitted_bytes)
		var $index = 0
		while $index < entry_count {
			$lexical = KernelLex.append_boolean($lexical, True).append(124)
			$lexical = KernelLex.append_boolean($lexical, False).append(124)
			$lexical = KernelLex.append_null($lexical).append(124)
			$lexical = KernelLex.append_integer($lexical, I64.lowest).append(124)
			$lexical = KernelLex.append_unsigned($lexical, U64.highest).append(124)
			$lexical = KernelLex.append_real($lexical, decimal).append(124)
			$lexical = KernelLex.append_name($lexical, name).append(124)
			$lexical = KernelLex.append_byte_string($lexical, byte_string).append(124)
			$lexical = KernelLex.append_text($lexical, text_string).append(10)
			$index = $index + 1
		}
		audit = audit_bytes($lexical)
		blank = generate_blank(4096)

		if $lexical.len() != metrics.emitted_bytes or audit.byte_visits != metrics.emitted_bytes {
			crash "structural-kernel lexical stress evidence changed"
		}

		{
			bytes: blank.bytes,
			work: [
				entry_count,
				metrics.tokens,
				metrics.source_bytes,
				$lexical.len(),
				audit.byte_visits,
				audit.checksum,
				blank.bytes.len(),
			],
		}
	}

	generate_deflate_stream : U64 -> { bytes : List(U8), work : List(U64) }
	generate_deflate_stream = |input_bytes| {
		input = deflate_input(input_bytes)
		plan = match KernelStructure.build_deflate_stream_probe(input, input_bytes) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel DEFLATE stress plan invariant failed"
			}
		}
		result = capture_generated(plan)
		work = result.deflate
		{
			bytes: result.bytes,
			work: [
				input_bytes,
				KernelDeflate.Work.blocks(work),
				KernelDeflate.Work.candidate_visits(work),
				KernelDeflate.Work.hash_inserts(work),
				KernelDeflate.Work.tokens(work),
				KernelDeflate.Work.matches(work),
				KernelDeflate.Work.emitted_bytes(work),
				KernelDeflate.Work.max_chunk_bytes(work),
				result.generated_segments,
				result.bytes.len(),
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
				crash "structural-kernel retention plan invariant failed"
			}
		}
		buffered = match KernelEmit.to_bytes(plan) {
			Ok(value) => value
			Err(_) => {
				crash "structural-kernel buffered retention invariant failed"
			}
		}
		shared_result = capture_resource(plan, ShareResourceChunks)
		owned_result = capture_resource(plan, OwnResourceChunks)

		if shared_result.bytes != buffered or owned_result.bytes != buffered {
			crash "structural-kernel retention policies changed output bytes"
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

deflate_input : U64 -> List(U8)
deflate_input = |count| {
	var $bytes = List.with_capacity(count)
	var $index = 0
	while $index < count {
		byte = match U64.mod_by($index, 4) {
			0 => 113
			1 => 32
			2 => 81
			_ => 10
		}
		$bytes = $bytes.append(byte)
		$index = $index + 1
	}
	$bytes
}

capture_generated : KernelStructure.Plan -> { bytes : List(U8), deflate : KernelDeflate.Work, generated_segments : U64 }
capture_generated = |plan| {
	var $encoder = match KernelEmit.start(plan, OwnResourceChunks) {
		Ok(value) => value
		Err(_) => {
			crash "structural-kernel generated encoder invariant failed"
		}
	}
	var $bytes = []
	var $generated_segments = 0
	var $done = False
	while $done == False {
		match KernelEmit.Encoder.next_infallible($encoder) {
			Done => {
				$done = True
			}
			Emit(segment, next) => {
				$bytes = append_all($bytes, segment.bytes)
				if segment.ownership == Generated {
					$generated_segments = $generated_segments + 1
				}
				$encoder = next
			}
		}
	}
	{ bytes: $bytes, deflate: KernelEmit.Encoder.deflate_work($encoder), generated_segments: $generated_segments }
}

outline_entries : U64 -> List(KernelOutline.Entry)
outline_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		within_group = U64.mod_by($index, 32)
		group = U64.div_by($index, 32)
		depth = if within_group == 0 0 else 1
		open = depth == 0 and U64.mod_by(group, 2) == 0
		$entries = $entries.append(
			KernelOutline.Entry.make({
				depth,
				open,
				target: TargetValue(KernelObject.ValueId.from_index($index)),
				title: KernelObject.TextStringId.from_index($index),
			}),
		)
		$index = $index + 1
	}
	$entries
}

audit_outline : KernelOutline.Plan -> { identity_checksum : U64, leaves : U64, next_links : U64, parents : U64, previous_links : U64, top_level : U64 }
audit_outline = |plan| {
	var $identity_checksum = 0
	var $leaves = 0
	var $next_links = 0
	var $parents = 0
	var $previous_links = 0
	var $top_level = 0
	var $index = 0
	while $index < KernelOutline.Plan.entry_count(plan) {
		item = KernelOutline.Plan.item_at(plan, $index)
		within_group = U64.mod_by($index, 32)
		is_top = within_group == 0
		expected_parent = if is_top Absent else At($index - within_group)
		expected_previous = if is_top {
			if $index == 0 Absent else At($index - 32)
		} else if within_group == 1 {
			Absent
		} else {
			At($index - 1)
		}
		expected_next = if is_top {
			if $index + 32 < KernelOutline.Plan.entry_count(plan) At($index + 32) else Absent
		} else if within_group == 31 {
			Absent
		} else {
			At($index + 1)
		}

		if outline_parent_matches(KernelOutline.Item.parent(item), expected_parent) == False or outline_link_matches(KernelOutline.Item.previous(item), expected_previous) == False or outline_link_matches(KernelOutline.Item.next(item), expected_next) == False {
			crash "structural-kernel outline relationship evidence changed"
		}

		match KernelOutline.Item.previous(item) {
			NoItem => {}
			OutlineItem(_) => {
				$previous_links = $previous_links + 1
			}
		}
		match KernelOutline.Item.next(item) {
			NoItem => {}
			OutlineItem(_) => {
				$next_links = $next_links + 1
			}
		}

		if is_top {
			$top_level = $top_level + 1
			if outline_link_matches(KernelOutline.Item.first(item), At($index + 1)) == False or outline_link_matches(KernelOutline.Item.last(item), At($index + 31)) == False or outline_count_is_31(KernelOutline.Item.count(item)) == False {
				crash "structural-kernel outline parent evidence changed"
			}
			$parents = $parents + 1
		} else {
			if outline_link_matches(KernelOutline.Item.first(item), Absent) == False or outline_link_matches(KernelOutline.Item.last(item), Absent) == False or outline_count_is_leaf(KernelOutline.Item.count(item)) == False {
				crash "structural-kernel outline leaf evidence changed"
			}
			$leaves = $leaves + 1
		}

		$identity_checksum = $identity_checksum + KernelObject.TextStringId.index(KernelOutline.Item.title(item))
		match KernelOutline.Item.target(item) {
			NoTarget => {
				crash "structural-kernel outline target evidence changed"
			}
			TargetValue(value) => {
				$identity_checksum = $identity_checksum + KernelObject.ValueId.index(value)
			}
		}
		$index = $index + 1
	}
	{
		identity_checksum: $identity_checksum,
		leaves: $leaves,
		next_links: $next_links,
		parents: $parents,
		previous_links: $previous_links,
		top_level: $top_level,
	}
}

outline_link_matches : KernelOutline.Link, [Absent, At(U64)] -> Bool
outline_link_matches = |link, expected| match (link, expected) {
	(NoItem, Absent) => True
	(OutlineItem(id), At(index)) => KernelOutline.ItemId.index(id) == index
	_ => False
}

outline_parent_matches : KernelOutline.Parent, [Absent, At(U64)] -> Bool
outline_parent_matches = |parent, expected| match (parent, expected) {
	(OutlineRoot, Absent) => True
	(OutlineParent(id), At(index)) => KernelOutline.ItemId.index(id) == index
	_ => False
}

outline_count_is_31 : KernelOutline.Count -> Bool
outline_count_is_31 = |count| match count {
	ClosedCount(value) => value == 31
	Leaf => False
	OpenCount(value) => value == 31
}

outline_count_is_leaf : KernelOutline.Count -> Bool
outline_count_is_leaf = |count| match count {
	Leaf => True
	_ => False
}

build_byte_tree : List(KernelIndex.ByteEntry), KernelIndex.ByteKind, KernelIndex.Limits -> KernelIndex.ByteTree
build_byte_tree = |entries, kind, limits| match KernelIndex.ByteTree.build(entries, kind, limits) {
	Ok(tree) => tree
	Err(_) => {
		crash "structural-kernel byte-key stress plan invariant failed"
	}
}

build_number_tree : List(KernelIndex.NumberEntry), KernelIndex.NumberKind, KernelIndex.Limits -> KernelIndex.NumberTree
build_number_tree = |entries, kind, limits| match KernelIndex.NumberTree.build(entries, kind, limits) {
	Ok(tree) => tree
	Err(_) => {
		crash "structural-kernel number-key stress plan invariant failed"
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
					crash "structural-kernel byte-key node omitted required limits"
				}
				NodeLimits({ first_index, last_index }) => {
					if $level == 0 or first_index != start or last_index != start + length - 1 {
						crash "structural-kernel byte-key node limits changed"
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
					crash "structural-kernel number-key node omitted required limits"
				}
				NodeLimits({ first_index, last_index }) => {
					if $level == 0 or first_index != start or last_index != start + length - 1 {
						crash "structural-kernel number-key node limits changed"
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

resource_name_entries : U64 -> List(KernelResource.Entry)
resource_name_entries = |count| {
	var $entries = List.with_capacity(count)
	var $index = 0
	while $index < count {
		$entries = $entries.append(KernelResource.Entry.make(Font, $index))
		$index = $index + 1
	}
	$entries
}

audit_resource_names : KernelResource.Plan -> { byte_visits : U64, checksum : U64 }
audit_resource_names = |plan| {
	var $index = 0
	var $byte_visits = 0
	var $checksum = 0
	while $index < KernelResource.Plan.entry_count(plan) {
		entry = KernelResource.Plan.entry_at(plan, $index)
		match KernelResource.Entry.kind(entry) {
			Font => {}
			_ => {
				crash "structural-kernel resource-name kind changed"
			}
		}
		if KernelResource.Entry.identity(entry) != $index {
			crash "structural-kernel resource-name identity changed"
		}
		name = KernelResource.Plan.name_at(plan, $index)
		if name.is_empty() or list_at(name, 0) != 70 {
			crash "structural-kernel resource-name prefix changed"
		}
		var $byte_index = 0
		while $byte_index < name.len() {
			byte = list_at(name, $byte_index).to_u64()
			$checksum = $checksum + ($index + 1) * byte
			$byte_visits = $byte_visits + 1
			$byte_index = $byte_index + 1
		}
		$index = $index + 1
	}
	{ byte_visits: $byte_visits, checksum: $checksum }
}

audit_bytes : List(U8) -> { byte_visits : U64, checksum : U64 }
audit_bytes = |bytes| {
	var $index = 0
	var $checksum = 0
	while $index < bytes.len() {
		$checksum = $checksum + ($index + 1) * list_at(bytes, $index).to_u64()
		$index = $index + 1
	}
	{ byte_visits: $index, checksum: $checksum }
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
			crash "structural-kernel retention encoder invariant failed"
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
		crash "structural-kernel evidence index invariant failed"
	}
}
