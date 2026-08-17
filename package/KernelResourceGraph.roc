import KernelSha256
import Scene
import Semantics

## Gate 4 resource-planning foundation.
##
## This module owns reusable resource identity, deterministic deduplication, and
## the explicit direct-edge resource dependency graph. It is deliberately
## independent of PDF object numbers, of the Gate 1/2 `KernelResource` name
## planner (which assigns dictionary names to an already-planned dense store),
## and of `KernelResourceUse` (which counts Gate 2 colour/image use inside one
## scene). Neither of those types carries dependency edges or payload identity,
## so Gate 4 introduces its own representation rather than widening theirs.
##
## Storage rules:
##
## - Resources, roots, and placements use dense scalar IDs and flat lists.
## - Payload bytes are owned exactly once by the caller-supplied byte
##   allocation; every resource is an exact `(start, length)` range into it and
##   deduplication shares those ranges instead of copying or compacting.
## - The graph stores direct edges only, as a compressed dependency store plus
##   its reverse index. No transitive-reachability set is ever materialized.
## - Every traversal is iterative over dense buffers; attacker-controlled depth
##   is walked with an explicit stack, never with recursion.
KernelResourceGraph :: [].{

	## Resource kinds that may participate in the dependency graph. Later Gate 4
	## kinds join by extending this union and the descriptor facts below; no PDF
	## dictionary or object internal enters this boundary. `ExtGState` joined
	## with the transparency slice; its rank is appended after the existing
	## kinds so no previously derived identity digest changes.
	Kind : [ColorSpace, ExtGState, Font, IccProfile, Image, Pattern, Shading, XObject]

	## Descriptor facts that must distinguish resources whose payload bytes alone
	## are insufficient. Two resources with identical bytes but any differing
	## descriptor field are never merged.
	Descriptor : {
		bit_depth : U64,
		components : U64,
		flags : U64,
		height : U64,
		kind : Kind,
		subtype : U64,
		width : U64,
	}

	## Placement-specific semantic ownership. `Semantic` associations survive
	## deduplication untouched; artifact-only placements stay ownership-neutral.
	Ownership : [
		Artifact(Scene.PageArtifactKind),
		Semantic({ fragment : Semantics.FragmentId, mcid : U64 }),
	]

	Reuse : [PlacementSpecific, Reusable]

	Placement : { ownership : Ownership, resource : U64, reuse : Reuse }

	## `source` directly depends on `target`; the target must be planned first.
	Edge : { source : U64, target : U64 }

	## One direct resource use by one content-stream root.
	RootUse : { resource : U64, root : U64 }

	Source : { descriptor : Descriptor, length : U64, start : U64 }

	## `DomainSeparatedSha256` is the production identity procedure: a versioned,
	## domain-separated SHA-256 over the descriptor facts, byte length, and
	## payload range. `TruncatedTestDigest` is a white-box test seam that keeps
	## that procedure intact and folds its output into a small modulus so
	## unrelated payloads share a collision bucket. It never weakens production
	## hashing, because the facade never selects it.
	DigestPolicy : [DomainSeparatedSha256, TruncatedTestDigest(U64)]

	Input : {
		digest_policy : DigestPolicy,
		edges : List(Edge),
		payload_bytes : List(U8),
		placements : List(Placement),
		resources : List(Source),
		root_count : U64,
		root_uses : List(RootUse),
	}

	Limits : {
		max_collision_entries : U64,
		max_edges : U64,
		max_equality_bytes : U64,
		max_hash_bytes : U64,
		max_hashes : U64,
		max_ordering_work : U64,
		max_payload_bytes : U64,
		max_placements : U64,
		max_resources : U64,
		max_root_uses : U64,
		max_roots : U64,
		max_topological_work : U64,
	}

	## Every failure is one stable structured value holding compact scalar IDs
	## and the exact failed bound. No diagnostic retains a payload.
	Error : [
		ArithmeticOverflow,
		ClosureResourceOutOfRange({ count : U64, resource : U64, use : U64 }),
		ClosureRootOutOfRange({ count : U64, root : U64, use : U64 }),
		CollisionEntryLimitExceeded({ attempted : U64, limit : U64 }),
		DependencyCycle({ planned : U64, resource : U64 }),
		DigestFailed({ resource : U64 }),
		DuplicateEdge({ source : U64, target : U64 }),
		DuplicateRootUse({ resource : U64, root : U64 }),
		EdgeLimitExceeded({ attempted : U64, limit : U64 }),
		EdgeSourceOutOfRange({ count : U64, edge : U64, source : U64 }),
		EdgeTargetOutOfRange({ count : U64, edge : U64, target : U64 }),
		EqualityByteLimitExceeded({ attempted : U64, limit : U64 }),
		HashByteLimitExceeded({ attempted : U64, limit : U64 }),
		HashLimitExceeded({ attempted : U64, limit : U64 }),
		OrderingWorkLimitExceeded({ attempted : U64, limit : U64 }),
		PayloadByteLimitExceeded({ attempted : U64, limit : U64 }),
		PayloadRangeInvalid({ available : U64, length : U64, resource : U64, start : U64 }),
		PlacementLimitExceeded({ attempted : U64, limit : U64 }),
		PlacementResourceOutOfRange({ count : U64, placement : U64, resource : U64 }),
		ResourceLimitExceeded({ attempted : U64, limit : U64 }),
		RootLimitExceeded({ attempted : U64, limit : U64 }),
		RootOutOfRange({ count : U64, root : U64, use : U64 }),
		RootResourceOutOfRange({ count : U64, resource : U64, use : U64 }),
		RootUseLimitExceeded({ attempted : U64, limit : U64 }),
		SelfCycle({ resource : U64 }),
		SemanticOwnershipMerge({ placement : U64, resource : U64 }),
		TopologicalWorkLimitExceeded({ attempted : U64, limit : U64 }),
		UnreachableResource({ resource : U64 }),
	]

	Work : {
		bytes_compared : U64,
		bytes_hashed : U64,
		closure_uses : U64,
		collision_entries : U64,
		copied_payload_bytes : U64,
		deduplicated_payloads : U64,
		descriptor_partitions : U64,
		direct_dictionary_entries : U64,
		direct_edges : U64,
		edge_visits : U64,
		equality_comparisons : U64,
		hashes : U64,
		nested_dictionary_entries : U64,
		node_visits : U64,
		ordering_byte_visits : U64,
		ordering_passes : U64,
		placements : U64,
		planned_resources : U64,
		ready_operations : U64,
		resources : U64,
		retained_payload_bytes : U64,
		roots : U64,
		sort_comparisons : U64,
		unique_payloads : U64,
	}

	Canonical : { descriptor : Descriptor, length : U64, start : U64 }

	## The versioned, domain-separated identity digest of one source range.
	## This is exactly the procedure `Plan.build` hashes with, exposed so Gate 4
	## canonical recipes can embed dependency identities without a second
	## digest implementation. Descriptor facts and byte length precede the
	## payload, so equal bytes under different descriptors never share a digest.
	identity_digest : Source, List(U8) -> Try(List(U8), Error)
	identity_digest = |source, payload_bytes| {
		available = payload_bytes.len()
		end = match U64.plus_try(source.start, source.length) {
			Err(Overflow) => available + 1
			Ok(value) => value
		}
		if end > available {
			Err(PayloadRangeInvalid({ available, length: source.length, resource: 0, start: source.start }))
		} else {
			match KernelSha256.digest_range(identity_prefix(source), payload_bytes, source.start, source.length) {
				Err(_) => Err(DigestFailed({ resource: 0 }))
				Ok(bytes) => Ok(bytes)
			}
		}
	}

	## The successful stage result. It keeps only the facts later planning and
	## lowering need: canonical resource descriptors and payload ranges, the
	## direct dependency store, the deterministic plan order, the per-root direct
	## dictionaries, the placement ownership records, and the source-to-canonical
	## map that lowering consumes to name authored references. The
	## authoring-side source list and the raw edge list are consumed and
	## dropped.
	Plan :: {
		canonical : List(Canonical),
		canonical_of : List(U64),
		dependency_offsets : List(U64),
		dependency_targets : List(U64),
		order : List(U64),
		payload_bytes : List(U8),
		placements : List(Placement),
		root_offsets : List(U64),
		root_targets : List(U64),
		work : Work,
	}.{
		build : Input, Limits -> Try(Plan, Error)
		build = |input, limits| build_plan(input, [], limits)

		## `build` plus closure-only uses: references that keep a resource
		## reachable (a page transparency group naming its blending space)
		## without entering any content stream's direct resource dictionary,
		## the dependency store, or the planning order. They participate in
		## closure proof only, so an otherwise-unused blending space is neither
		## `UnreachableResource` nor a spurious dictionary entry.
		build_with_closure_uses : Input, List(RootUse), Limits -> Try(Plan, Error)
		build_with_closure_uses = |input, closure_uses, limits| build_plan(input, closure_uses, limits)

		## The canonical identity of one authored source resource. Later stages
		## consume this map instead of re-deriving identity.
		canonical_index : Plan, U64 -> U64
		canonical_index = |plan, source| list_at(plan.canonical_of, source)

		## Canonical resources, i.e. unique payload identities after
		## deduplication.
		resource_count : Plan -> U64
		resource_count = |plan| plan.canonical.len()

		descriptor : Plan, U64 -> Descriptor
		descriptor = |plan, resource| list_at(plan.canonical, resource).descriptor

		## An immutable range of the single owned payload allocation. Shared
		## identities return the same range; nothing is copied.
		payload : Plan, U64 -> List(U8)
		payload = |plan, resource| {
			entry = list_at(plan.canonical, resource)
			plan.payload_bytes.sublist({ len: entry.length, start: entry.start })
		}

		## An immutable absolute range of the single owned payload allocation.
		## Canonical recipes record exact sub-ranges of their payloads (for
		## example an image's row-compacted planes); later stages consume those
		## ranges through this accessor without copying.
		payload_slice : Plan, U64, U64 -> List(U8)
		payload_slice = |plan, start, length| plan.payload_bytes.sublist({ len: length, start })

		## Deterministic topological order: every resource appears after all of
		## its direct dependencies.
		order : Plan -> List(U64)
		order = |plan| plan.order

		## Exactly the direct dependencies of one resource. Nested dictionaries
		## never contain a transitive dependency, so lowering consumes this
		## result without re-inferring anything.
		direct_dependencies : Plan, U64 -> List(U64)
		direct_dependencies = |plan, resource| span(plan.dependency_offsets, plan.dependency_targets, resource)

		## Exactly the direct resources one content stream references.
		root_dictionary : Plan, U64 -> List(U64)
		root_dictionary = |plan, root| span(plan.root_offsets, plan.root_targets, root)

		root_count : Plan -> U64
		root_count = |plan| plan.root_offsets.len() - 1

		placement_count : Plan -> U64
		placement_count = |plan| plan.placements.len()

		placement_at : Plan, U64 -> Placement
		placement_at = |plan, index| list_at(plan.placements, index)

		placements : Plan -> List(Placement)
		placements = |plan| plan.placements

		work : Plan -> Work
		work = |plan| plan.work
	}
}

Entry : {
	descriptor : KernelResourceGraph.Descriptor,
	fingerprint : U64,
	index : U64,
	length : U64,
	start : U64,
}

Pair : { left : U64, right : U64 }

Segment : { depth : U64, end : U64, start : U64 }

Order : [Ascending, Equal, Descending]

## The versioned domain separator. Changing the identity procedure changes this
## tag, so a stored identity can never be reinterpreted under new rules.
identity_domain : List(U8)
identity_domain = Str.to_utf8("roc-pdf/resource-identity/v1\n")

build_plan : KernelResourceGraph.Input, List(KernelResourceGraph.RootUse), KernelResourceGraph.Limits -> Try(KernelResourceGraph.Plan, KernelResourceGraph.Error)
build_plan = |input, closure_uses, limits| {
	resource_count = input.resources.len()
	edge_count = input.edges.len()
	root_use_count = input.root_uses.len()
	placement_count = input.placements.len()
	payload_length = input.payload_bytes.len()

	if resource_count > limits.max_resources {
		return Err(ResourceLimitExceeded({ attempted: resource_count, limit: limits.max_resources }))
	}
	if edge_count > limits.max_edges {
		return Err(EdgeLimitExceeded({ attempted: edge_count, limit: limits.max_edges }))
	}
	if input.root_count > limits.max_roots {
		return Err(RootLimitExceeded({ attempted: input.root_count, limit: limits.max_roots }))
	}
	total_uses = checked_add(root_use_count, closure_uses.len())?
	if total_uses > limits.max_root_uses {
		return Err(RootUseLimitExceeded({ attempted: total_uses, limit: limits.max_root_uses }))
	}
	if placement_count > limits.max_placements {
		return Err(PlacementLimitExceeded({ attempted: placement_count, limit: limits.max_placements }))
	}
	if payload_length > limits.max_payload_bytes {
		return Err(PayloadByteLimitExceeded({ attempted: payload_length, limit: limits.max_payload_bytes }))
	}
	if resource_count > limits.max_hashes {
		return Err(HashLimitExceeded({ attempted: resource_count, limit: limits.max_hashes }))
	}

	identity = build_identity(input, limits)?
	entries = sort_entries(identity.entries)
	classes = classify(entries.entries, input.payload_bytes, limits)?
	canonical_count = classes.canonical.len()

	dependencies = build_dependencies(input.edges, classes.canonical_of, resource_count, canonical_count)?
	roots = build_roots(input.root_uses, classes.canonical_of, resource_count, input.root_count)?
	closure_seeds = build_closure_seeds(closure_uses, classes.canonical_of, resource_count, input.root_count)?
	reachable = prove_closure(roots, closure_seeds, dependencies, canonical_count, limits)?
	planned = plan_order(dependencies, canonical_count, limits, reachable.work)?
	placements = build_placements(input.placements, classes.canonical_of, resource_count)?

	Ok(
		KernelResourceGraph.Plan.{
			canonical: classes.canonical,
			canonical_of: classes.canonical_of,
			dependency_offsets: dependencies.offsets,
			dependency_targets: dependencies.heads,
			order: planned.order,
			payload_bytes: input.payload_bytes,
			placements,
			root_offsets: roots.offsets,
			root_targets: roots.heads,
			work: {
				bytes_compared: classes.bytes_compared,
				bytes_hashed: identity.bytes_hashed,
				closure_uses: closure_uses.len(),
				collision_entries: classes.collision_entries,

				## Deduplication shares exact ranges of the one owned payload
				## allocation; it never compacts them into a second buffer.
				copied_payload_bytes: 0,
				deduplicated_payloads: resource_count - canonical_count,
				descriptor_partitions: classes.descriptor_partitions,
				direct_dictionary_entries: roots.heads.len(),
				direct_edges: dependencies.heads.len(),
				edge_visits: planned.edge_visits + reachable.edge_visits,
				equality_comparisons: classes.equality_comparisons,
				hashes: resource_count,
				nested_dictionary_entries: dependencies.heads.len(),
				node_visits: planned.node_visits + reachable.node_visits,
				ordering_byte_visits: classes.ordering_byte_visits,
				ordering_passes: classes.ordering_passes,
				placements: placement_count,
				planned_resources: planned.order.len(),
				ready_operations: planned.ready_operations,
				resources: resource_count,

				## The plan retains the caller's payload allocation unchanged, so
				## duplicate bytes stay resident until the caller releases it.
				retained_payload_bytes: payload_length,
				roots: input.root_count,
				sort_comparisons: entries.comparisons + dependencies.comparisons + roots.comparisons,
				unique_payloads: canonical_count,
			},
		},
	)
}

## Inspects and hashes every payload exactly once.
build_identity : KernelResourceGraph.Input, KernelResourceGraph.Limits -> Try({ bytes_hashed : U64, entries : List(Entry) }, KernelResourceGraph.Error)
build_identity = |input, limits| {
	available = input.payload_bytes.len()
	count = input.resources.len()
	var $entries = List.with_capacity(count)
	var $bytes_hashed = 0
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		source = list_at(input.resources, $index)
		end = match U64.plus_try(source.start, source.length) {
			Err(Overflow) => available + 1
			Ok(value) => value
		}
		if end > available {
			$failure = Failed(PayloadRangeInvalid({ available, length: source.length, resource: $index, start: source.start }))
		} else {
			attempted = checked_add($bytes_hashed, source.length)
			match attempted {
				Err(_) => {
					$failure = Failed(ArithmeticOverflow)
				}
				Ok(total) => {
					if total > limits.max_hash_bytes {
						$failure = Failed(HashByteLimitExceeded({ attempted: total, limit: limits.max_hash_bytes }))
					} else {
						digest = KernelSha256.digest_range(
							identity_prefix(source),
							input.payload_bytes,
							source.start,
							source.length,
						)
						match digest {
							Err(_) => {
								$failure = Failed(DigestFailed({ resource: $index }))
							}
							Ok(bytes) => {
								$bytes_hashed = total
								$entries = $entries.append({
									descriptor: source.descriptor,
									fingerprint: fold_fingerprint(leading_u64(bytes), input.digest_policy),
									index: $index,
									length: source.length,
									start: source.start,
								})
							}
						}
					}
				}
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({ bytes_hashed: $bytes_hashed, entries: $entries })
	}
}

## Domain, version, descriptor facts, and byte length precede the payload range,
## so bytes alone can never establish identity.
identity_prefix : KernelResourceGraph.Source -> List(U8)
identity_prefix = |source| {
	var $prefix = List.with_capacity(identity_domain.len() + 64)
	$prefix = $prefix.concat(identity_domain)
	$prefix = append_u64($prefix, kind_rank(source.descriptor.kind))
	$prefix = append_u64($prefix, source.descriptor.subtype)
	$prefix = append_u64($prefix, source.descriptor.width)
	$prefix = append_u64($prefix, source.descriptor.height)
	$prefix = append_u64($prefix, source.descriptor.components)
	$prefix = append_u64($prefix, source.descriptor.bit_depth)
	$prefix = append_u64($prefix, source.descriptor.flags)
	append_u64($prefix, source.length)
}

fold_fingerprint : U64, KernelResourceGraph.DigestPolicy -> U64
fold_fingerprint = |fingerprint, policy| match policy {
	DomainSeparatedSha256 => fingerprint
	TruncatedTestDigest(modulus) => if modulus == 0 fingerprint else U64.mod_by(fingerprint, modulus)
}

leading_u64 : List(U8) -> U64
leading_u64 = |bytes| {
	var $value = 0
	var $index = 0
	while $index < 8 {
		$value = $value.shl_wrap(8).bitwise_or(byte_at(bytes, $index).to_u64())
		$index = $index + 1
	}
	$value
}

## Digest buckets, exact descriptor/length partitioning, deterministic bytewise
## ordering, and adjacent exact equality. A digest match is only a candidate.
classify : List(Entry),
List(U8),
KernelResourceGraph.Limits -> Try(
	{
		bytes_compared : U64,
		canonical : List(KernelResourceGraph.Canonical),
		canonical_of : List(U64),
		collision_entries : U64,
		descriptor_partitions : U64,
		equality_comparisons : U64,
		ordering_byte_visits : U64,
		ordering_passes : U64,
	},
	KernelResourceGraph.Error,
)
classify = |entries, payload, limits| {
	count = entries.len()
	var $canonical = List.with_capacity(count)
	var $canonical_of = List.repeat(0, count)
	var $collision_entries = 0
	var $descriptor_partitions = 0
	var $ordering_passes = 0
	var $ordering_byte_visits = 0
	var $equality_comparisons = 0
	var $bytes_compared = 0
	var $failure = NoFailure
	var $index = 0

	while $index < count and $failure == NoFailure {
		bucket_end = run_end(entries, $index, count, SameFingerprint)
		if bucket_end - $index == 1 {
			entry = list_at(entries, $index)
			$canonical_of = list_set($canonical_of, entry.index, $canonical.len())
			$canonical = $canonical.append({ descriptor: entry.descriptor, length: entry.length, start: entry.start })
			$index = bucket_end
		} else {
			$collision_entries = $collision_entries + (bucket_end - $index)
			if $collision_entries > limits.max_collision_entries {
				$failure = Failed(CollisionEntryLimitExceeded({ attempted: $collision_entries, limit: limits.max_collision_entries }))
			} else {
				var $partition = $index
				while $partition < bucket_end {
					partition_end = run_end(entries, $partition, bucket_end, SameDescriptor)
					$descriptor_partitions = $descriptor_partitions + 1
					if partition_end - $partition == 1 {
						entry = list_at(entries, $partition)
						$canonical_of = list_set($canonical_of, entry.index, $canonical.len())
						$canonical = $canonical.append({ descriptor: entry.descriptor, length: entry.length, start: entry.start })
					} else {
						ordered = radix_order(entries, payload, $partition, partition_end)
						$ordering_passes = $ordering_passes + ordered.passes
						$ordering_byte_visits = $ordering_byte_visits + ordered.byte_visits
						confirmed = confirm_equality(entries, payload, ordered.order)
						$equality_comparisons = $equality_comparisons + confirmed.comparisons
						$bytes_compared = $bytes_compared + confirmed.bytes_compared
						var $member = 0
						while $member < ordered.order.len() {
							entry = list_at(entries, list_at(ordered.order, $member))
							if list_at(confirmed.classes, $member) == $member {
								$canonical_of = list_set($canonical_of, entry.index, $canonical.len())
								$canonical = $canonical.append({ descriptor: entry.descriptor, length: entry.length, start: entry.start })
							} else {
								leader = list_at(entries, list_at(ordered.order, list_at(confirmed.classes, $member)))
								$canonical_of = list_set($canonical_of, entry.index, list_at($canonical_of, leader.index))
							}
							$member = $member + 1
						}
					}
					$partition = partition_end
				}
				$index = bucket_end
			}
		}
	}

	if $failure == NoFailure and $ordering_byte_visits > limits.max_ordering_work {
		$failure = Failed(OrderingWorkLimitExceeded({ attempted: $ordering_byte_visits, limit: limits.max_ordering_work }))
	}
	if $failure == NoFailure and $bytes_compared > limits.max_equality_bytes {
		$failure = Failed(EqualityByteLimitExceeded({ attempted: $bytes_compared, limit: limits.max_equality_bytes }))
	}

	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok({
			bytes_compared: $bytes_compared,
			canonical: $canonical,
			canonical_of: $canonical_of,
			collision_entries: $collision_entries,
			descriptor_partitions: $descriptor_partitions,
			equality_comparisons: $equality_comparisons,
			ordering_byte_visits: $ordering_byte_visits,
			ordering_passes: $ordering_passes,
		})
	}
}

## Maximal run of equal keys starting at `start`, never scanning past `limit`.
## A descriptor partition is always bounded by its own digest bucket, because
## the next bucket can hold an entry with the same descriptor and byte length.
run_end : List(Entry), U64, U64, [SameDescriptor, SameFingerprint] -> U64
run_end = |entries, start, limit, mode| {
	first = list_at(entries, start)
	var $index = start + 1
	var $running = Bool.True
	while $running and $index < limit {
		candidate = list_at(entries, $index)
		same = match mode {
			SameDescriptor => candidate.length == first.length and descriptor_order(candidate.descriptor, first.descriptor) == Equal
			SameFingerprint => candidate.fingerprint == first.fingerprint
		}
		if same {
			$index = $index + 1
		} else {
			$running = Bool.False
		}
	}
	$index
}

## Iterative most-significant-byte radix refinement over one descriptor/length
## partition. Every entry contributes a byte visit only while it is still tied
## with another entry, so total work is bounded by the partition's entries plus
## its bytes; a counting pass runs only at a real split, of which there are at
## most `entries - 1`. There is no pairwise comparison.
radix_order : List(Entry), List(U8), U64, U64 -> { byte_visits : U64, order : List(U64), passes : U64 }
radix_order = |entries, payload, start, end| {
	var $order = List.with_capacity(end - start)
	var $seed = start
	while $seed < end {
		$order = $order.append($seed)
		$seed = $seed + 1
	}
	length = list_at(entries, start).length
	var $byte_visits = 0
	var $passes = 0
	var $stack = [{ depth: 0, end: end - start, start: 0 }]
	while $stack.len() > 0 {
		segment = list_at($stack, $stack.len() - 1)
		$stack = $stack.sublist({ len: $stack.len() - 1, start: 0 })
		var $depth = segment.depth
		var $splitting = Bool.False
		while !$splitting and $depth < length {
			first = partition_byte(entries, payload, $order, segment.start, $depth)
			var $scan = segment.start
			var $same = Bool.True
			while $scan < segment.end {
				if partition_byte(entries, payload, $order, $scan, $depth) != first {
					$same = Bool.False
				}
				$scan = $scan + 1
			}
			$byte_visits = $byte_visits + (segment.end - segment.start)
			if $same {
				$depth = $depth + 1
			} else {
				$splitting = Bool.True
			}
		}
		if $splitting {
			var $counts = List.repeat(0, 256)
			var $scan = segment.start
			while $scan < segment.end {
				value = partition_byte(entries, payload, $order, $scan, $depth).to_u64()
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
				value = partition_byte(entries, payload, $order, $scan, $depth).to_u64()
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

partition_byte : List(Entry), List(U8), List(U64), U64, U64 -> U8
partition_byte = |entries, payload, order, position, depth| {
	entry = list_at(entries, list_at(order, position))
	byte_at(payload, entry.start + depth)
}

## Adjacent exact equality after ordering. Each position records the position of
## its class leader; only `entries - 1` comparisons ever run.
confirm_equality : List(Entry), List(U8), List(U64) -> { bytes_compared : U64, classes : List(U64), comparisons : U64 }
confirm_equality = |entries, payload, order| {
	count = order.len()
	var $classes = List.with_capacity(count)
	var $bytes_compared = 0
	var $comparisons = 0
	var $leader = 0
	var $position = 0
	while $position < count {
		if $position == 0 {
			$classes = $classes.append(0)
		} else {
			previous = list_at(entries, list_at(order, $position - 1))
			current = list_at(entries, list_at(order, $position))
			$comparisons = $comparisons + 1
			compared = compare_payloads(payload, previous, current)
			$bytes_compared = $bytes_compared + compared.bytes
			if compared.equal {
				$classes = $classes.append($leader)
			} else {
				$leader = $position
				$classes = $classes.append($position)
			}
		}
		$position = $position + 1
	}
	{ bytes_compared: $bytes_compared, classes: $classes, comparisons: $comparisons }
}

## Descriptor and byte length already agree inside a partition; this confirms
## the payload bytes themselves and stops at the first difference.
compare_payloads : List(U8), Entry, Entry -> { bytes : U64, equal : Bool }
compare_payloads = |payload, left, right| {
	if left.length != right.length or descriptor_order(left.descriptor, right.descriptor) != Equal {
		{ bytes: 0, equal: Bool.False }
	} else {
		var $offset = 0
		var $equal = Bool.True
		while $equal and $offset < left.length {
			if byte_at(payload, left.start + $offset) != byte_at(payload, right.start + $offset) {
				$equal = Bool.False
			}
			$offset = $offset + 1
		}
		{ bytes: $offset, equal: $equal }
	}
}

## Validates every direct edge, rejects duplicates and self dependencies, and
## builds the canonical direct-edge store plus its reverse index. Only direct
## edges are stored.
build_dependencies : List(KernelResourceGraph.Edge),
List(U64),
U64,
U64 -> Try(
	{
		comparisons : U64,
		offsets : List(U64),
		reverse_offsets : List(U64),
		reverse_targets : List(U64),
		heads : List(U64),
	},
	KernelResourceGraph.Error,
)
build_dependencies = |edges, canonical_of, resource_count, canonical_count| {
	count = edges.len()
	var $pairs = List.with_capacity(count)
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		edge = list_at(edges, $index)
		if edge.source >= resource_count {
			$failure = Failed(EdgeSourceOutOfRange({ count: resource_count, edge: $index, source: edge.source }))
		} else if edge.target >= resource_count {
			$failure = Failed(EdgeTargetOutOfRange({ count: resource_count, edge: $index, target: edge.target }))
		} else {
			$pairs = $pairs.append({ left: edge.source, right: edge.target })
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	sorted = sort_pairs($pairs)
	duplicate = adjacent_duplicate(sorted.pairs)
	match duplicate {
		Found(pair) => return Err(DuplicateEdge({ source: pair.left, target: pair.right }))
		NotFound => {}
	}

	var $canonical_pairs = List.with_capacity(count)
	$index = 0
	while $index < count {
		pair = list_at(sorted.pairs, $index)
		$canonical_pairs = $canonical_pairs.append(
			{ left: list_at(canonical_of, pair.left), right: list_at(canonical_of, pair.right) },
		)
		$index = $index + 1
	}
	canonical_sorted = sort_pairs($canonical_pairs)
	unique = unique_pairs(canonical_sorted.pairs)
	self_cycle = self_pair(unique)
	match self_cycle {
		Found(resource) => return Err(SelfCycle({ resource: resource }))
		NotFound => {}
	}

	forward = compress_pairs(unique, canonical_count)
	reverse_input = sort_pairs(swap_pairs(unique))
	reverse = compress_pairs(reverse_input.pairs, canonical_count)
	Ok({
		comparisons: sorted.comparisons + canonical_sorted.comparisons + reverse_input.comparisons,
		offsets: forward.offsets,
		reverse_offsets: reverse.offsets,
		reverse_targets: reverse.heads,
		heads: forward.heads,
	})
}

## Each content-stream root receives exactly its direct canonical resources.
build_roots : List(KernelResourceGraph.RootUse),
List(U64),
U64,
U64 -> Try(
	{ comparisons : U64, offsets : List(U64), heads : List(U64) },
	KernelResourceGraph.Error,
)
build_roots = |root_uses, canonical_of, resource_count, root_count| {
	count = root_uses.len()
	var $pairs = List.with_capacity(count)
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		use = list_at(root_uses, $index)
		if use.root >= root_count {
			$failure = Failed(RootOutOfRange({ count: root_count, root: use.root, use: $index }))
		} else if use.resource >= resource_count {
			$failure = Failed(RootResourceOutOfRange({ count: resource_count, resource: use.resource, use: $index }))
		} else {
			$pairs = $pairs.append({ left: use.root, right: use.resource })
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => return Err(error)
		NoFailure => {}
	}

	sorted = sort_pairs($pairs)
	duplicate = adjacent_duplicate(sorted.pairs)
	match duplicate {
		Found(pair) => return Err(DuplicateRootUse({ resource: pair.right, root: pair.left }))
		NotFound => {}
	}

	var $canonical_pairs = List.with_capacity(count)
	$index = 0
	while $index < count {
		pair = list_at(sorted.pairs, $index)
		$canonical_pairs = $canonical_pairs.append({ left: pair.left, right: list_at(canonical_of, pair.right) })
		$index = $index + 1
	}

	## Two distinct source resources that deduplicate to one canonical identity
	## collapse into a single dictionary entry. That is deduplication, not a
	## duplicate declaration, so the exact-pair rejection above runs first.
	canonical_sorted = sort_pairs($canonical_pairs)
	unique = unique_pairs(canonical_sorted.pairs)
	compressed = compress_pairs(unique, root_count)
	Ok({ comparisons: sorted.comparisons + canonical_sorted.comparisons, offsets: compressed.offsets, heads: compressed.heads })
}

## Closure-only uses are validated like root uses and mapped to canonical
## identities, but they only seed the closure walk below; they never enter the
## per-root dictionaries, the dependency store, or the planning order.
build_closure_seeds : List(KernelResourceGraph.RootUse), List(U64), U64, U64 -> Try(List(U64), KernelResourceGraph.Error)
build_closure_seeds = |closure_uses, canonical_of, resource_count, root_count| {
	var $seeds = List.with_capacity(closure_uses.len())
	var $index = 0
	var $failure = NoFailure
	while $index < closure_uses.len() and $failure == NoFailure {
		use = list_at(closure_uses, $index)
		if use.root >= root_count {
			$failure = Failed(ClosureRootOutOfRange({ count: root_count, root: use.root, use: $index }))
		} else if use.resource >= resource_count {
			$failure = Failed(ClosureResourceOutOfRange({ count: resource_count, resource: use.resource, use: $index }))
		} else {
			$seeds = $seeds.append(list_at(canonical_of, use.resource))
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($seeds)
	}
}

## Iterative closure proof from every declared content-stream root. An explicit
## stack walks attacker-controlled depth; no per-node reachability set is built.
prove_closure : { comparisons : U64, offsets : List(U64), heads : List(U64) },
List(U64),
{ comparisons : U64, offsets : List(U64), reverse_offsets : List(U64), reverse_targets : List(U64), heads : List(U64) },
U64,
KernelResourceGraph.Limits -> Try(
	{ edge_visits : U64, node_visits : U64, work : U64 },
	KernelResourceGraph.Error,
)
prove_closure = |roots, closure_seeds, dependencies, canonical_count, limits| {
	var $seen = List.repeat(Bool.False, canonical_count)
	var $stack = List.with_capacity(canonical_count)
	var $node_visits = 0
	var $edge_visits = 0

	var $index = 0
	while $index < roots.heads.len() {
		resource = list_at(roots.heads, $index)
		if !list_at($seen, resource) {
			$seen = list_set($seen, resource, Bool.True)
			$stack = $stack.append(resource)
		}
		$index = $index + 1
	}

	$index = 0
	while $index < closure_seeds.len() {
		resource = list_at(closure_seeds, $index)
		if !list_at($seen, resource) {
			$seen = list_set($seen, resource, Bool.True)
			$stack = $stack.append(resource)
		}
		$index = $index + 1
	}

	while $stack.len() > 0 {
		resource = list_at($stack, $stack.len() - 1)
		$stack = $stack.sublist({ len: $stack.len() - 1, start: 0 })
		$node_visits = $node_visits + 1
		start = list_at(dependencies.offsets, resource)
		end = list_at(dependencies.offsets, resource + 1)
		var $edge = start
		while $edge < end {
			target = list_at(dependencies.heads, $edge)
			$edge_visits = $edge_visits + 1
			if !list_at($seen, target) {
				$seen = list_set($seen, target, Bool.True)
				$stack = $stack.append(target)
			}
			$edge = $edge + 1
		}
	}

	var $missing = NotFound
	$index = 0
	while $index < canonical_count and $missing == NotFound {
		if !list_at($seen, $index) {
			$missing = Found($index)
		}
		$index = $index + 1
	}
	match $missing {
		Found(resource) => return Err(UnreachableResource({ resource: resource }))
		NotFound => {}
	}

	work = checked_add($node_visits, $edge_visits)?
	if work > limits.max_topological_work {
		Err(TopologicalWorkLimitExceeded({ attempted: work, limit: limits.max_topological_work }))
	} else {
		Ok({ edge_visits: $edge_visits, node_visits: $node_visits, work })
	}
}

## Deterministic Kahn planning. Simultaneously available nodes are resolved by a
## binary min-heap over canonical resource IDs; those IDs are assigned from
## content-derived digest, descriptor, length, and bytewise order, so the plan
## is independent of insertion, map, and traversal order. Worst case is
## `O((V + E) log V)`.
plan_order : { comparisons : U64, offsets : List(U64), reverse_offsets : List(U64), reverse_targets : List(U64), heads : List(U64) },
U64,
KernelResourceGraph.Limits,
U64 -> Try(
	{ edge_visits : U64, node_visits : U64, order : List(U64), ready_operations : U64 },
	KernelResourceGraph.Error,
)
plan_order = |dependencies, canonical_count, limits, prior_work| {
	var $remaining = List.with_capacity(canonical_count)
	var $index = 0
	while $index < canonical_count {
		$remaining = $remaining.append(list_at(dependencies.offsets, $index + 1) - list_at(dependencies.offsets, $index))
		$index = $index + 1
	}

	var $heap = List.with_capacity(canonical_count)
	var $ready_operations = 0
	$index = 0
	while $index < canonical_count {
		if list_at($remaining, $index) == 0 {
			pushed = heap_push($heap, $index)
			$heap = pushed.heap
			$ready_operations = $ready_operations + pushed.operations
		}
		$index = $index + 1
	}

	var $order = List.with_capacity(canonical_count)
	var $node_visits = 0
	var $edge_visits = 0
	while $heap.len() > 0 {
		popped = heap_pop($heap)
		$heap = popped.heap
		$ready_operations = $ready_operations + popped.operations
		resource = popped.value
		$order = $order.append(resource)
		$node_visits = $node_visits + 1
		start = list_at(dependencies.reverse_offsets, resource)
		end = list_at(dependencies.reverse_offsets, resource + 1)
		var $edge = start
		while $edge < end {
			dependent = list_at(dependencies.reverse_targets, $edge)
			$edge_visits = $edge_visits + 1
			next = list_at($remaining, dependent) - 1
			$remaining = list_set($remaining, dependent, next)
			if next == 0 {
				pushed = heap_push($heap, dependent)
				$heap = pushed.heap
				$ready_operations = $ready_operations + pushed.operations
			}
			$edge = $edge + 1
		}
	}

	if $order.len() != canonical_count {
		var $blocked = 0
		var $found = NotFound
		while $blocked < canonical_count and $found == NotFound {
			if list_at($remaining, $blocked) > 0 {
				$found = Found($blocked)
			}
			$blocked = $blocked + 1
		}
		match $found {
			Found(resource) => return Err(DependencyCycle({ planned: $order.len(), resource: resource }))
			NotFound => return Err(ArithmeticOverflow)
		}
	}

	work = checked_add(checked_add(checked_add(prior_work, $node_visits)?, $edge_visits)?, $ready_operations)?
	if work > limits.max_topological_work {
		Err(TopologicalWorkLimitExceeded({ attempted: work, limit: limits.max_topological_work }))
	} else {
		Ok({ edge_visits: $edge_visits, node_visits: $node_visits, order: $order, ready_operations: $ready_operations })
	}
}

heap_push : List(U64), U64 -> { heap : List(U64), operations : U64 }
heap_push = |heap, value| {
	var $heap = heap.append(value)
	var $position = $heap.len() - 1
	var $operations = 1
	var $climbing = Bool.True
	while $climbing and $position > 0 {
		parent = U64.div_by($position - 1, 2)
		$operations = $operations + 1
		if list_at($heap, parent) > list_at($heap, $position) {
			$heap = swap($heap, parent, $position)
			$position = parent
		} else {
			$climbing = Bool.False
		}
	}
	{ heap: $heap, operations: $operations }
}

heap_pop : List(U64) -> { heap : List(U64), operations : U64, value : U64 }
heap_pop = |heap| {
	top = list_at(heap, 0)
	last = list_at(heap, heap.len() - 1)
	var $heap = heap.sublist({ len: heap.len() - 1, start: 0 })
	var $operations = 1
	if $heap.len() > 0 {
		$heap = list_set($heap, 0, last)
		var $position = 0
		var $sinking = Bool.True
		while $sinking {
			left = $position * 2 + 1
			right = left + 1
			var $smallest = $position
			if left < $heap.len() and list_at($heap, left) < list_at($heap, $smallest) {
				$smallest = left
			}
			if right < $heap.len() and list_at($heap, right) < list_at($heap, $smallest) {
				$smallest = right
			}
			$operations = $operations + 1
			if $smallest == $position {
				$sinking = Bool.False
			} else {
				$heap = swap($heap, $position, $smallest)
				$position = $smallest
			}
		}
	}
	{ heap: $heap, operations: $operations, value: top }
}

## Placement ownership survives deduplication. A `Semantic` association may
## never be declared reusable, because sharing it would erase the
## placement-specific semantic association.
build_placements : List(KernelResourceGraph.Placement), List(U64), U64 -> Try(List(KernelResourceGraph.Placement), KernelResourceGraph.Error)
build_placements = |placements, canonical_of, resource_count| {
	count = placements.len()
	var $result = List.with_capacity(count)
	var $index = 0
	var $failure = NoFailure
	while $index < count and $failure == NoFailure {
		placement = list_at(placements, $index)
		if placement.resource >= resource_count {
			$failure = Failed(PlacementResourceOutOfRange({ count: resource_count, placement: $index, resource: placement.resource }))
		} else {
			shareable = match placement.ownership {
				Artifact(_) => Bool.True
				Semantic(_) => Bool.False
			}
			if !shareable and placement.reuse == Reusable {
				$failure = Failed(SemanticOwnershipMerge({ placement: $index, resource: placement.resource }))
			} else {
				$result = $result.append(
					{ ownership: placement.ownership, resource: list_at(canonical_of, placement.resource), reuse: placement.reuse },
				)
			}
		}
		$index = $index + 1
	}
	match $failure {
		Failed(error) => Err(error)
		NoFailure => Ok($result)
	}
}

## Deterministic bottom-up merge sort. Worst case is `O(n log n)` on already
## ordered, reverse-ordered, and equal input; no first-pivot quicksort takes
## part in resource planning.
sort_entries : List(Entry) -> { comparisons : U64, entries : List(Entry) }
sort_entries = |entries| {
	count = entries.len()
	var $current = entries
	var $width = 1
	var $comparisons = 0
	while $width < count {
		var $output = List.with_capacity(count)
		var $start = 0
		while $start < count {
			middle = smaller($start + $width, count)
			end = smaller($start + $width + $width, count)
			var $left = $start
			var $right = middle
			while $left < middle and $right < end {
				a = list_at($current, $left)
				b = list_at($current, $right)
				$comparisons = $comparisons + 1
				if entry_order(a, b) == Descending {
					$output = $output.append(b)
					$right = $right + 1
				} else {
					$output = $output.append(a)
					$left = $left + 1
				}
			}
			while $left < middle {
				$output = $output.append(list_at($current, $left))
				$left = $left + 1
			}
			while $right < end {
				$output = $output.append(list_at($current, $right))
				$right = $right + 1
			}
			$start = $start + $width + $width
		}
		$current = $output
		$width = $width + $width
	}
	{ comparisons: $comparisons, entries: $current }
}

sort_pairs : List(Pair) -> { comparisons : U64, pairs : List(Pair) }
sort_pairs = |pairs| {
	count = pairs.len()
	var $current = pairs
	var $width = 1
	var $comparisons = 0
	while $width < count {
		var $output = List.with_capacity(count)
		var $start = 0
		while $start < count {
			middle = smaller($start + $width, count)
			end = smaller($start + $width + $width, count)
			var $left = $start
			var $right = middle
			while $left < middle and $right < end {
				a = list_at($current, $left)
				b = list_at($current, $right)
				$comparisons = $comparisons + 1
				if pair_order(a, b) == Descending {
					$output = $output.append(b)
					$right = $right + 1
				} else {
					$output = $output.append(a)
					$left = $left + 1
				}
			}
			while $left < middle {
				$output = $output.append(list_at($current, $left))
				$left = $left + 1
			}
			while $right < end {
				$output = $output.append(list_at($current, $right))
				$right = $right + 1
			}
			$start = $start + $width + $width
		}
		$current = $output
		$width = $width + $width
	}
	{ comparisons: $comparisons, pairs: $current }
}

entry_order : Entry, Entry -> Order
entry_order = |left, right| {
	if left.fingerprint != right.fingerprint {
		if left.fingerprint < right.fingerprint Ascending else Descending
	} else {
		descriptor = descriptor_order(left.descriptor, right.descriptor)
		if descriptor != Equal {
			descriptor
		} else if left.length != right.length {
			if left.length < right.length Ascending else Descending
		} else if left.index != right.index {
			if left.index < right.index Ascending else Descending
		} else {
			Equal
		}
	}
}

descriptor_order : KernelResourceGraph.Descriptor, KernelResourceGraph.Descriptor -> Order
descriptor_order = |left, right| {
	var $result = Equal
	$result = scalar_order($result, kind_rank(left.kind), kind_rank(right.kind))
	$result = scalar_order($result, left.subtype, right.subtype)
	$result = scalar_order($result, left.width, right.width)
	$result = scalar_order($result, left.height, right.height)
	$result = scalar_order($result, left.components, right.components)
	$result = scalar_order($result, left.bit_depth, right.bit_depth)
	scalar_order($result, left.flags, right.flags)
}

scalar_order : Order, U64, U64 -> Order
scalar_order = |current, left, right| {
	if current != Equal {
		current
	} else if left < right {
		Ascending
	} else if left > right {
		Descending
	} else {
		Equal
	}
}

pair_order : Pair, Pair -> Order
pair_order = |left, right| {
	if left.left != right.left {
		if left.left < right.left Ascending else Descending
	} else if left.right != right.right {
		if left.right < right.right Ascending else Descending
	} else {
		Equal
	}
}

adjacent_duplicate : List(Pair) -> [Found(Pair), NotFound]
adjacent_duplicate = |pairs| {
	var $index = 1
	var $found = NotFound
	while $index < pairs.len() and $found == NotFound {
		if pair_order(list_at(pairs, $index - 1), list_at(pairs, $index)) == Equal {
			$found = Found(list_at(pairs, $index))
		}
		$index = $index + 1
	}
	$found
}

unique_pairs : List(Pair) -> List(Pair)
unique_pairs = |pairs| {
	var $unique = List.with_capacity(pairs.len())
	var $index = 0
	while $index < pairs.len() {
		pair = list_at(pairs, $index)
		if $index == 0 or pair_order(list_at(pairs, if $index == 0 0 else $index - 1), pair) != Equal {
			$unique = $unique.append(pair)
		}
		$index = $index + 1
	}
	$unique
}

self_pair : List(Pair) -> [Found(U64), NotFound]
self_pair = |pairs| {
	var $index = 0
	var $found = NotFound
	while $index < pairs.len() and $found == NotFound {
		pair = list_at(pairs, $index)
		if pair.left == pair.right {
			$found = Found(pair.left)
		}
		$index = $index + 1
	}
	$found
}

swap_pairs : List(Pair) -> List(Pair)
swap_pairs = |pairs| {
	var $swapped = List.with_capacity(pairs.len())
	var $index = 0
	while $index < pairs.len() {
		pair = list_at(pairs, $index)
		$swapped = $swapped.append({ left: pair.right, right: pair.left })
		$index = $index + 1
	}
	$swapped
}

## Counting plus prefix sums over an already sorted pair list; no comparison
## sort and no per-edge allocation.
compress_pairs : List(Pair), U64 -> { offsets : List(U64), heads : List(U64) }
compress_pairs = |pairs, slots| {
	var $counts = List.repeat(0, slots)
	var $index = 0
	while $index < pairs.len() {
		left = list_at(pairs, $index).left
		$counts = list_set($counts, left, list_at($counts, left) + 1)
		$index = $index + 1
	}
	var $offsets = List.with_capacity(slots + 1)
	var $running = 0
	$index = 0
	$offsets = $offsets.append(0)
	while $index < slots {
		$running = $running + list_at($counts, $index)
		$offsets = $offsets.append($running)
		$index = $index + 1
	}
	var $heads = List.with_capacity(pairs.len())
	$index = 0
	while $index < pairs.len() {
		$heads = $heads.append(list_at(pairs, $index).right)
		$index = $index + 1
	}
	{ offsets: $offsets, heads: $heads }
}

span : List(U64), List(U64), U64 -> List(U64)
span = |offsets, heads, slot| {
	start = list_at(offsets, slot)
	end = list_at(offsets, slot + 1)
	heads.sublist({ len: end - start, start })
}

## Ranks are append-only: `ExtGState` takes the next free rank rather than an
## alphabetical slot, because the rank participates in every identity digest.
kind_rank : KernelResourceGraph.Kind -> U64
kind_rank = |kind| match kind {
	ColorSpace => 0
	Font => 1
	IccProfile => 2
	Image => 3
	Pattern => 4
	Shading => 5
	XObject => 6
	ExtGState => 7
}

append_u64 : List(U8), U64 -> List(U8)
append_u64 = |output, value| output
	.append(value.shr_wrap(56).to_u8_wrap())
	.append(value.shr_wrap(48).to_u8_wrap())
	.append(value.shr_wrap(40).to_u8_wrap())
	.append(value.shr_wrap(32).to_u8_wrap())
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

smaller : U64, U64 -> U64
smaller = |left, right| if left < right left else right

swap : List(U64), U64, U64 -> List(U64)
swap = |values, left, right| {
	first = list_at(values, left)
	second = list_at(values, right)
	list_set(list_set(values, left, second), right, first)
}

checked_add : U64, U64 -> Try(U64, KernelResourceGraph.Error)
checked_add = |left, right| match U64.plus_try(left, right) {
	Err(Overflow) => Err(ArithmeticOverflow)
	Ok(value) => Ok(value)
}

byte_at : List(U8), U64 -> U8
byte_at = |bytes, index| match bytes.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated resource payload index escaped"
	}
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "validated resource-graph index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "validated resource-graph update escaped"
	}
}

test_descriptor : KernelResourceGraph.Kind, U64 -> KernelResourceGraph.Descriptor
test_descriptor = |kind, subtype| {
	bit_depth: 8,
	components: 1,
	flags: 0,
	height: 1,
	kind: kind,
	subtype: subtype,
	width: 1,
}

open_limits : KernelResourceGraph.Limits
open_limits = {
	max_collision_entries: 1024,
	max_edges: 1024,
	max_equality_bytes: 1048576,
	max_hash_bytes: 1048576,
	max_hashes: 1024,
	max_ordering_work: 1048576,
	max_payload_bytes: 1048576,
	max_placements: 1024,
	max_resources: 1024,
	max_root_uses: 1024,
	max_roots: 64,
	max_topological_work: 1048576,
}

TestResource : { descriptor : KernelResourceGraph.Descriptor, payload : List(U8) }

## Flattens authored test resources into one owned payload allocation with exact
## ranges, exactly as a normalization stage would.
test_input : List(TestResource), List(KernelResourceGraph.Edge), U64, List(KernelResourceGraph.RootUse), List(KernelResourceGraph.Placement), KernelResourceGraph.DigestPolicy -> KernelResourceGraph.Input
test_input = |resources, edges, root_count, root_uses, placements, digest_policy| {
	var $bytes = List.with_capacity(64)
	var $sources = List.with_capacity(resources.len())
	var $index = 0
	while $index < resources.len() {
		resource = list_at(resources, $index)
		start = $bytes.len()
		$bytes = $bytes.concat(resource.payload)
		$sources = $sources.append({ descriptor: resource.descriptor, length: resource.payload.len(), start: start })
		$index = $index + 1
	}
	{
		digest_policy: digest_policy,
		edges: edges,
		payload_bytes: $bytes,
		placements: placements,
		resources: $sources,
		root_count: root_count,
		root_uses: root_uses,
	}
}

## The plan's identity-normalized shape: payload bytes in planned order. It is
## independent of the caller's insertion order and of every dense ID.
normalized_order : KernelResourceGraph.Plan -> List(List(U8))
normalized_order = |plan| KernelResourceGraph.Plan.order(plan).map(|id| KernelResourceGraph.Plan.payload(plan, id))

normalized_root : KernelResourceGraph.Plan, U64 -> List(List(U8))
normalized_root = |plan, root| KernelResourceGraph.Plan.root_dictionary(plan, root).map(|id| KernelResourceGraph.Plan.payload(plan, id))

normalized_dependencies : KernelResourceGraph.Plan, U64 -> List(List(U8))
normalized_dependencies = |plan, resource| KernelResourceGraph.Plan.direct_dependencies(plan, resource).map(|id| KernelResourceGraph.Plan.payload(plan, id))

## Confirms that every direct dependency is planned strictly before its
## dependent, without consulting any transitive set.
is_topological : KernelResourceGraph.Plan -> Bool
is_topological = |plan| {
	count = KernelResourceGraph.Plan.resource_count(plan)
	var $position = List.repeat(0, count)
	order = KernelResourceGraph.Plan.order(plan)
	var $index = 0
	while $index < order.len() {
		$position = list_set($position, list_at(order, $index), $index)
		$index = $index + 1
	}
	var $ordered = Bool.True
	$index = 0
	while $index < count {
		dependencies = KernelResourceGraph.Plan.direct_dependencies(plan, $index)
		var $edge = 0
		while $edge < dependencies.len() {
			if list_at($position, list_at(dependencies, $edge)) >= list_at($position, $index) {
				$ordered = Bool.False
			}
			$edge = $edge + 1
		}
		$index = $index + 1
	}
	$ordered
}

leaf : U64 -> TestResource
leaf = |tag| { descriptor: test_descriptor(Image, 0), payload: [tag.to_u8_wrap(), 0x41, 0x42, 0x43] }

## An empty resource graph plans nothing and reports no work beyond zero.
expect {
	plan = KernelResourceGraph.Plan.build(test_input([], [], 0, [], [], DomainSeparatedSha256), open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.resource_count(plan) == 0 and
		KernelResourceGraph.Plan.order(plan) == [] and
			work.hashes == 0 and
				work.collision_entries == 0 and
					work.unique_payloads == 0 and
						work.copied_payload_bytes == 0
}

## A leaf-only graph plans every resource and stores no direct edges. Ready
## nodes are resolved by ascending canonical identity, which is the documented
## total tie-break order.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }, { resource: 2, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.order(plan) == [0, 1, 2] and
		work.direct_edges == 0 and
			work.nested_dictionary_entries == 0 and
				work.direct_dictionary_entries == 3 and
					work.hashes == 3 and
						work.bytes_hashed == 12 and
							work.collision_entries == 0
}

## A linear nested chain plans dependencies first and keeps each nested
## dictionary limited to that resource's own direct dependency.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[{ source: 0, target: 1 }, { source: 1, target: 2 }],
		1,
		[{ resource: 0, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	normalized_order(plan) == [leaf(3).payload, leaf(2).payload, leaf(1).payload] and
		normalized_root(plan, 0) == [leaf(1).payload] and
			work.direct_edges == 2 and
				work.direct_dictionary_entries == 1 and
					work.node_visits == 6 and
						work.edge_visits == 4 and
							is_topological(plan)
}

## A branching DAG with one shared dependency stores that dependency once and
## still lists it in both nested dictionaries.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(3), leaf(4)],
		[{ source: 0, target: 1 }, { source: 0, target: 2 }, { source: 1, target: 3 }, { source: 2, target: 3 }],
		1,
		[{ resource: 0, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	shared = leaf(4).payload
	normalized_dependencies(plan, index_of(plan, leaf(2).payload)) == [shared] and
		normalized_dependencies(plan, index_of(plan, leaf(3).payload)) == [shared] and
			normalized_order(plan).get(0) == Ok(shared) and
				work.direct_edges == 4 and
					work.unique_payloads == 4 and
						is_topological(plan)
}

## Equivalent graphs supplied in adversarial insertion orders normalize to one
## plan, one set of nested dictionaries, and one root dictionary.
expect {
	forward = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[{ source: 0, target: 1 }, { source: 1, target: 2 }],
		1,
		[{ resource: 0, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	reversed = test_input(
		[leaf(3), leaf(2), leaf(1)],
		[{ source: 1, target: 0 }, { source: 2, target: 1 }],
		1,
		[{ resource: 2, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	shuffled = test_input(
		[leaf(2), leaf(3), leaf(1)],
		[{ source: 0, target: 1 }, { source: 2, target: 0 }],
		1,
		[{ resource: 2, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	first = KernelResourceGraph.Plan.build(forward, open_limits)?
	second = KernelResourceGraph.Plan.build(reversed, open_limits)?
	third = KernelResourceGraph.Plan.build(shuffled, open_limits)?
	normalized_order(first) == normalized_order(second) and
		normalized_order(second) == normalized_order(third) and
			normalized_root(first, 0) == normalized_root(third, 0) and
				KernelResourceGraph.Plan.work(first).sort_comparisons == KernelResourceGraph.Plan.work(third).sort_comparisons
}

## Byte-identical, descriptor-identical resources deduplicate to one payload
## identity while both root uses collapse to one dictionary entry.
expect {
	input = test_input(
		[leaf(1), leaf(1)],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.resource_count(plan) == 1 and
		work.unique_payloads == 1 and
			work.deduplicated_payloads == 1 and
				work.collision_entries == 2 and
					work.descriptor_partitions == 1 and
						work.equality_comparisons == 1 and
							work.bytes_compared == 4 and
								work.copied_payload_bytes == 0 and
									KernelResourceGraph.Plan.root_dictionary(plan, 0).len() == 1
}

## Equal payload bytes with different descriptors are never merged.
expect {
	same_bytes = [0x01, 0x02, 0x03, 0x04]
	input = test_input(
		[
			{ descriptor: test_descriptor(Image, 0), payload: same_bytes },
			{ descriptor: test_descriptor(Image, 1), payload: same_bytes },
			{ descriptor: test_descriptor(IccProfile, 0), payload: same_bytes },
		],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }, { resource: 2, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.resource_count(plan) == 3 and
		work.deduplicated_payloads == 0 and

		## Descriptor facts enter the digest, so unequal descriptors do not
		## even share a collision bucket.
			work.collision_entries == 0
}

## Repeated placements share one visual resource identity and retain distinct
## placement-specific semantic ownership and artifact classification.
expect {
	input = test_input(
		[leaf(1), leaf(1)],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }],
		[
			{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(7), mcid: 3 }), resource: 0, reuse: PlacementSpecific },
			{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(9), mcid: 4 }), resource: 1, reuse: PlacementSpecific },
			{ ownership: Artifact(Watermark), resource: 1, reuse: Reusable },
		],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	first = KernelResourceGraph.Plan.placement_at(plan, 0)
	second = KernelResourceGraph.Plan.placement_at(plan, 1)
	third = KernelResourceGraph.Plan.placement_at(plan, 2)
	KernelResourceGraph.Plan.resource_count(plan) == 1 and
		first.resource == second.resource and
			second.resource == third.resource and
				ownership_key(first.ownership) != ownership_key(second.ownership) and
					ownership_key(second.ownership) != ownership_key(third.ownership) and
						KernelResourceGraph.Plan.placement_count(plan) == 3
}

## Multiple content-stream roots each receive a complete, exact direct
## dictionary; a nested dependency never leaks into a root dictionary.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[{ source: 0, target: 2 }],
		2,
		[{ resource: 0, root: 0 }, { resource: 1, root: 1 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	normalized_root(plan, 0) == [leaf(1).payload] and
		normalized_root(plan, 1) == [leaf(2).payload] and
			normalized_dependencies(plan, index_of(plan, leaf(1).payload)) == [leaf(3).payload] and
				work.direct_dictionary_entries == 2 and
					work.nested_dictionary_entries == 1 and
						work.roots == 2
}

## A forced digest-collision bucket holding equal and unequal payloads merges
## only the exactly equal pair, and its ordering and equality work stays within
## the declared entries-plus-bytes bound rather than an all-pairs comparison.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(1), leaf(3)],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }, { resource: 2, root: 0 }, { resource: 3, root: 0 }],
		[],
		TruncatedTestDigest(1),
	)
	plan = KernelResourceGraph.Plan.build(input, open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	entries = 4
	bucket_bytes = 16
	work.collision_entries == entries and
		work.descriptor_partitions == 1 and
			work.unique_payloads == 3 and
				work.deduplicated_payloads == 1 and
					work.equality_comparisons == entries - 1 and
						work.bytes_compared <= bucket_bytes and
							work.ordering_byte_visits <= bucket_bytes + entries
}

## An out-of-range direct-edge source is rejected transactionally.
expect match KernelResourceGraph.Plan.build(
	test_input([leaf(1)], [{ source: 4, target: 0 }], 1, [{ resource: 0, root: 0 }], [], DomainSeparatedSha256),
	open_limits,
) {
	Err(EdgeSourceOutOfRange({ count: 1, edge: 0, source: 4 })) => Bool.True
	_ => Bool.False
}

## A missing nested dependency reachable from a stream root is rejected.
expect match KernelResourceGraph.Plan.build(
	test_input([leaf(1), leaf(2)], [{ source: 0, target: 2 }], 1, [{ resource: 0, root: 0 }], [], DomainSeparatedSha256),
	open_limits,
) {
	Err(EdgeTargetOutOfRange({ count: 2, edge: 0, target: 2 })) => Bool.True
	_ => Bool.False
}

## A self-cycle, a two-node cycle, and a longer cycle each fail with a stable
## structured diagnostic and no partial plan.
expect {
	self_cycle = KernelResourceGraph.Plan.build(
		test_input([leaf(1)], [{ source: 0, target: 0 }], 1, [{ resource: 0, root: 0 }], [], DomainSeparatedSha256),
		open_limits,
	)
	two_node = KernelResourceGraph.Plan.build(
		test_input(
			[leaf(1), leaf(2)],
			[{ source: 0, target: 1 }, { source: 1, target: 0 }],
			1,
			[{ resource: 0, root: 0 }],
			[],
			DomainSeparatedSha256,
		),
		open_limits,
	)
	longer = KernelResourceGraph.Plan.build(
		test_input(
			[leaf(1), leaf(2), leaf(3)],
			[{ source: 0, target: 1 }, { source: 1, target: 2 }, { source: 2, target: 0 }],
			1,
			[{ resource: 0, root: 0 }],
			[],
			DomainSeparatedSha256,
		),
		open_limits,
	)
	match self_cycle {
		Err(SelfCycle({ resource: 0 })) => match two_node {
			Err(DependencyCycle({ planned: 0, resource: 0 })) => match longer {
				Err(DependencyCycle({ planned: 0, resource: 0 })) => Bool.True
				_ => Bool.False
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Duplicate direct edges and duplicate root uses are forbidden by contract.
expect {
	duplicate_edge = KernelResourceGraph.Plan.build(
		test_input(
			[leaf(1), leaf(2)],
			[{ source: 0, target: 1 }, { source: 0, target: 1 }],
			1,
			[{ resource: 0, root: 0 }],
			[],
			DomainSeparatedSha256,
		),
		open_limits,
	)
	duplicate_use = KernelResourceGraph.Plan.build(
		test_input([leaf(1)], [], 1, [{ resource: 0, root: 0 }, { resource: 0, root: 0 }], [], DomainSeparatedSha256),
		open_limits,
	)
	match duplicate_edge {
		Err(DuplicateEdge({ source: 0, target: 1 })) => match duplicate_use {
			Err(DuplicateRootUse({ resource: 0, root: 0 })) => Bool.True
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## A resource that no declared content-stream root can reach fails the closure
## proof.
expect match KernelResourceGraph.Plan.build(
	test_input([leaf(1), leaf(2)], [], 1, [{ resource: 0, root: 0 }], [], DomainSeparatedSha256),
	open_limits,
) {
	Err(UnreachableResource(_)) => Bool.True
	_ => Bool.False
}

## A closure-only use keeps its resource reachable without adding it to any
## root dictionary, and its dependencies stay reachable through ordinary
## direct edges. The same input without the closure use fails closure.
expect {
	input = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[{ source: 1, target: 2 }],
		1,
		[{ resource: 0, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build_with_closure_uses(input, [{ resource: 1, root: 0 }], open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	without = KernelResourceGraph.Plan.build(input, open_limits)
	dictionary = normalized_root(plan, 0)
	dictionary == [[1, 0x41, 0x42, 0x43]] and
		work.closure_uses == 1 and
			work.planned_resources == 3 and
				match without {
					Err(UnreachableResource(_)) => Bool.True
					_ => Bool.False
				}
}

## A closure use over an authored twin resolves through the same canonical
## identity as the surviving twin, so deduplication still leaves one plan.
expect {
	input = test_input(
		[leaf(1), leaf(1)],
		[],
		1,
		[{ resource: 0, root: 0 }],
		[],
		DomainSeparatedSha256,
	)
	plan = KernelResourceGraph.Plan.build_with_closure_uses(input, [{ resource: 1, root: 0 }], open_limits)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.resource_count(plan) == 1 and work.deduplicated_payloads == 1 and work.closure_uses == 1
}

## Out-of-range closure uses are rejected with their own structured errors,
## and closure uses consume the shared root-use budget.
expect {
	input = test_input([leaf(1)], [], 1, [{ resource: 0, root: 0 }], [], DomainSeparatedSha256)
	bad_root = KernelResourceGraph.Plan.build_with_closure_uses(input, [{ resource: 0, root: 4 }], open_limits)
	bad_resource = KernelResourceGraph.Plan.build_with_closure_uses(input, [{ resource: 9, root: 0 }], open_limits)
	tight = KernelResourceGraph.Plan.build_with_closure_uses(input, [{ resource: 0, root: 0 }], { ..open_limits, max_root_uses: 1 })
	match bad_root {
		Err(ClosureRootOutOfRange({ count: 1, root: 4, use: 0 })) => match bad_resource {
			Err(ClosureResourceOutOfRange({ count: 1, resource: 9, use: 0 })) => match tight {
				Err(RootUseLimitExceeded({ attempted: 2, limit: 1 })) => Bool.True
				_ => Bool.False
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Out-of-range roots, root resources, and placements are rejected.
expect {
	bad_root = KernelResourceGraph.Plan.build(
		test_input([leaf(1)], [], 1, [{ resource: 0, root: 3 }], [], DomainSeparatedSha256),
		open_limits,
	)
	bad_root_resource = KernelResourceGraph.Plan.build(
		test_input([leaf(1)], [], 1, [{ resource: 5, root: 0 }], [], DomainSeparatedSha256),
		open_limits,
	)
	bad_placement = KernelResourceGraph.Plan.build(
		test_input(
			[leaf(1)],
			[],
			1,
			[{ resource: 0, root: 0 }],
			[{ ownership: Artifact(Background), resource: 6, reuse: Reusable }],
			DomainSeparatedSha256,
		),
		open_limits,
	)
	match bad_root {
		Err(RootOutOfRange({ count: 1, root: 3, use: 0 })) => match bad_root_resource {
			Err(RootResourceOutOfRange({ count: 1, resource: 5, use: 0 })) => match bad_placement {
				Err(PlacementResourceOutOfRange({ count: 1, placement: 0, resource: 6 })) => Bool.True
				_ => Bool.False
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Sharing a placement whose ownership is a placement-specific semantic
## association would erase that association, so it is rejected.
expect match KernelResourceGraph.Plan.build(
	test_input(
		[leaf(1)],
		[],
		1,
		[{ resource: 0, root: 0 }],
		[{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(1), mcid: 0 }), resource: 0, reuse: Reusable }],
		DomainSeparatedSha256,
	),
	open_limits,
) {
	Err(SemanticOwnershipMerge({ placement: 0, resource: 0 })) => Bool.True
	_ => Bool.False
}

## An impossible payload range and an overflowing one are the same atomic
## rejection.
expect {
	impossible = KernelResourceGraph.Plan.build(
		{
			digest_policy: DomainSeparatedSha256,
			edges: [],
			payload_bytes: [1, 2, 3],
			placements: [],
			resources: [{ descriptor: test_descriptor(Image, 0), length: 5, start: 0 }],
			root_count: 1,
			root_uses: [{ resource: 0, root: 0 }],
		},
		open_limits,
	)
	overflowing = KernelResourceGraph.Plan.build(
		{
			digest_policy: DomainSeparatedSha256,
			edges: [],
			payload_bytes: [1, 2, 3],
			placements: [],
			resources: [{ descriptor: test_descriptor(Image, 0), length: 1, start: U64.highest }],
			root_count: 1,
			root_uses: [{ resource: 0, root: 0 }],
		},
		open_limits,
	)
	match impossible {
		Err(PayloadRangeInvalid({ available: 3, length: 5, resource: 0, start: 0 })) => match overflowing {
			Err(PayloadRangeInvalid({ available: 3, length: 1, resource: 0, start: _ })) => Bool.True
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Every dimension-specific limit rejects the exact attempted dimension before
## any plan can escape.
expect {
	pair = [leaf(1), leaf(2)]
	uses = [{ resource: 0, root: 0 }, { resource: 1, root: 0 }]
	edges = [{ source: 0, target: 1 }]
	base = test_input(pair, edges, 1, uses, [], DomainSeparatedSha256)
	resources_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_resources: 1 })
	edges_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_edges: 0 })
	roots_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_roots: 0 })
	uses_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_root_uses: 1 })
	hashes_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_hashes: 1 })
	hash_bytes_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_hash_bytes: 5 })
	payload_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_payload_bytes: 7 })
	topological_limited = KernelResourceGraph.Plan.build(base, { ..open_limits, max_topological_work: 0 })
	match resources_limited {
		Err(ResourceLimitExceeded({ attempted: 2, limit: 1 })) => match edges_limited {
			Err(EdgeLimitExceeded({ attempted: 1, limit: 0 })) => match roots_limited {
				Err(RootLimitExceeded({ attempted: 1, limit: 0 })) => match uses_limited {
					Err(RootUseLimitExceeded({ attempted: 2, limit: 1 })) => match hashes_limited {
						Err(HashLimitExceeded({ attempted: 2, limit: 1 })) => match hash_bytes_limited {
							Err(HashByteLimitExceeded({ attempted: 8, limit: 5 })) => match payload_limited {
								Err(PayloadByteLimitExceeded({ attempted: 8, limit: 7 })) => match topological_limited {
									Err(TopologicalWorkLimitExceeded({ attempted: _, limit: 0 })) => Bool.True
									_ => Bool.False
								}
								_ => Bool.False
							}
							_ => Bool.False
						}
						_ => Bool.False
					}
					_ => Bool.False
				}
				_ => Bool.False
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Placement-count, collision-entry, ordering-work, and compared-byte budgets are
## each independently enforced.
expect {
	collision_input = test_input(
		[leaf(1), leaf(2), leaf(3)],
		[],
		1,
		[{ resource: 0, root: 0 }, { resource: 1, root: 0 }, { resource: 2, root: 0 }],
		[],
		TruncatedTestDigest(1),
	)
	placement_input = test_input(
		[leaf(1)],
		[],
		1,
		[{ resource: 0, root: 0 }],
		[{ ownership: Artifact(Header), resource: 0, reuse: Reusable }],
		DomainSeparatedSha256,
	)
	placements_limited = KernelResourceGraph.Plan.build(placement_input, { ..open_limits, max_placements: 0 })
	collisions_limited = KernelResourceGraph.Plan.build(collision_input, { ..open_limits, max_collision_entries: 2 })
	ordering_limited = KernelResourceGraph.Plan.build(collision_input, { ..open_limits, max_ordering_work: 0 })
	equality_limited = KernelResourceGraph.Plan.build(collision_input, { ..open_limits, max_equality_bytes: 0 })
	match placements_limited {
		Err(PlacementLimitExceeded({ attempted: 1, limit: 0 })) => match collisions_limited {
			Err(CollisionEntryLimitExceeded({ attempted: 3, limit: 2 })) => match ordering_limited {
				Err(OrderingWorkLimitExceeded(ordering)) => match equality_limited {
					Err(EqualityByteLimitExceeded(equality)) => ordering.limit == 0 and ordering.attempted > 0 and equality.limit == 0 and equality.attempted > 0
					_ => Bool.False
				}
				_ => Bool.False
			}
			_ => Bool.False
		}
		_ => Bool.False
	}
}

## Locates a canonical identity by its payload bytes so evidence never depends
## on a particular dense ID assignment.
index_of : KernelResourceGraph.Plan, List(U8) -> U64
index_of = |plan, payload| {
	var $index = 0
	var $found = 0
	while $index < KernelResourceGraph.Plan.resource_count(plan) {
		if KernelResourceGraph.Plan.payload(plan, $index) == payload {
			$found = $index
		}
		$index = $index + 1
	}
	$found
}

## Compact scalar projection of placement ownership used by evidence; the plan
## itself keeps the typed association untouched.
ownership_key : KernelResourceGraph.Ownership -> { fragment : U64, kind : U64, mcid : U64 }
ownership_key = |ownership| match ownership {
	Artifact(kind) => { fragment: 0, kind: artifact_rank(kind), mcid: 0 }
	Semantic(semantic) => { fragment: Semantics.FragmentId.index(semantic.fragment) + 1, kind: 100, mcid: semantic.mcid }
}

artifact_rank : Scene.PageArtifactKind -> U64
artifact_rank = |kind| match kind {
	Background => 1
	Decoration => 2
	Footer => 3
	Header => 4
	PageNumber => 5
	Watermark => 6
}

## Two distinct digest buckets may each hold entries with the same descriptor
## and byte length. A descriptor partition must never scan across the bucket
## boundary, or an entry would be classified twice.
expect {
	payloads = [leaf(1), leaf(1), leaf(2), leaf(2), leaf(3), leaf(3)]
	var $uses = List.with_capacity(6)
	var $index = 0
	while $index < 6 {
		$uses = $uses.append({ resource: $index, root: 0 })
		$index = $index + 1
	}
	plan = KernelResourceGraph.Plan.build(
		test_input(payloads, [], 1, $uses, [], TruncatedTestDigest(2)),
		open_limits,
	)?
	work = KernelResourceGraph.Plan.work(plan)
	KernelResourceGraph.Plan.resource_count(plan) == 3 and
		work.unique_payloads == 3 and
			work.deduplicated_payloads == 3 and work.descriptor_partitions == 2 and
				KernelResourceGraph.Plan.root_dictionary(plan, 0).len() == 3
}

## The exposed identity digest matches the descriptor-then-payload procedure:
## equal bytes with different descriptors differ, and an impossible range is
## the same atomic rejection the planner reports.
expect {
	bytes = [1, 2, 3, 4]
	first = KernelResourceGraph.identity_digest({ descriptor: test_descriptor(Image, 0), length: 4, start: 0 }, bytes)?
	same = KernelResourceGraph.identity_digest({ descriptor: test_descriptor(Image, 0), length: 4, start: 0 }, bytes)?
	other = KernelResourceGraph.identity_digest({ descriptor: test_descriptor(Image, 1), length: 4, start: 0 }, bytes)?
	out_of_range = match KernelResourceGraph.identity_digest({ descriptor: test_descriptor(Image, 0), length: 5, start: 0 }, bytes) {
		Err(PayloadRangeInvalid(_)) => Bool.True
		_ => Bool.False
	}
	first.len() == 32 and first == same and first != other and out_of_range
}
