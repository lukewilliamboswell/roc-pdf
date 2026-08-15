import KernelEmit
import KernelResourceGraph
import KernelStructure
import Semantics

## Gate 4 resource-planning evidence.
##
## Every scenario builds one flat payload allocation, one dense resource store,
## and one direct-edge graph, then reports the planner's deterministic work
## counters. Scenario shapes are chosen so fixed, per-resource, per-edge,
## per-root, and per-byte work can be told apart across scales:
##
## - `chain`   : depth `n`, `n - 1` edges. Proves the iterative traversal walks
##               attacker-controlled depth without recursion.
## - `fan`     : depth 2, `n - 1` edges from one root resource. Proves the
##               ready-set tie-break cost under a wide simultaneously available
##               set.
## - `dense`   : a fixed out-degree window, about `4n` edges over `n` nodes.
##               Isolates per-edge work from per-node work.
## - `collide` : a forced digest-collision bucket holding equal and unequal
##               payloads under the white-box digest seam.
## - `shared`  : the same immutable input planned twice, once on the ordinary
##               one-shot path and once with the caller retaining the value.
Gate4ResourceGraphEvidence :: [].{
	EvidenceError : [
		AdversarialOrderDiverged,
		CollisionMergedUnequalPayloads,
		EvidenceFailure,
		InvalidScale,
		MissingRejection(U64),
		NotTopological,
		OwnershipDiverged,
		PlanRejected(KernelResourceGraph.Error),
		SharedInputDiverged,
		UnexpectedPlan,
	]

	## Positive scaled scenarios. `mode` selects the shape described above.
	resource_plan : Str, U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	resource_plan = |mode, scale| {
		if scale < 2 or scale > 20000 {
			return Err(InvalidScale)
		}
		plan = build_scenario(mode, scale)?
		if !topological(plan) {
			return Err(NotTopological)
		}

		## The same logical graph supplied in a reversed insertion order must
		## normalize to the same plan, dictionaries, and dependency store.
		reversed = build_reversed(mode, scale)?
		if normalized(plan) != normalized(reversed) {
			return Err(AdversarialOrderDiverged)
		}

		bytes = blank_pdf({})?
		Ok({ bytes, work: work_vector(KernelResourceGraph.Plan.work(plan), 0) })
	}

	## Forced digest collisions: `scale` resources whose payloads repeat every
	## `scale / 2` entries, all folded into one bucket by the white-box seam.
	## Equal payloads merge; unequal payloads never do.
	collision_plan : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	collision_plan = |scale| {
		if scale < 2 or scale > 20000 or U64.mod_by(scale, 2) != 0 {
			return Err(InvalidScale)
		}
		plan = build_collision(scale)?
		work = KernelResourceGraph.Plan.work(plan)
		expected_unique = U64.div_by(scale, 2)

		## A collision bucket may never merge unequal payloads, and its declared
		## work must stay within entries plus bucket bytes rather than the
		## `entries * (entries - 1) / 2` an all-pairs comparison would need.
		bucket_bytes = scale * payload_width
		if work.unique_payloads != expected_unique or work.deduplicated_payloads != expected_unique {
			return Err(CollisionMergedUnequalPayloads)
		}
		if work.collision_entries != scale or work.descriptor_partitions != 1 {
			return Err(CollisionMergedUnequalPayloads)
		}
		if work.equality_comparisons != scale - 1 or work.bytes_compared > bucket_bytes {
			return Err(CollisionMergedUnequalPayloads)
		}
		if work.ordering_byte_visits > bucket_bytes + bucket_bytes + scale {
			return Err(CollisionMergedUnequalPayloads)
		}
		bytes = blank_pdf({})?
		Ok({ bytes, work: work_vector(work, 0) })
	}

	## Ownership evidence. `Unique` hands a freshly built input straight to the
	## planner, so the ordinary one-shot path owns it; `Retained` keeps the same
	## immutable input alive and plans it twice. Correctness never depends on
	## uniqueness: both produce the identical plan and copy no payload bytes, and
	## the retained path differs only in allocation and retention cost.
	ownership_plan : [Retained, Unique], U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	ownership_plan = |retention, scale| {
		if scale < 2 or scale > 20000 {
			return Err(InvalidScale)
		}
		planned = match retention {
			Unique => KernelResourceGraph.Plan.build(scenario_input("fan", scale, Forward), scenario_limits(scale)) ? PlanRejected
			Retained => {
				input = scenario_input("fan", scale, Forward)
				first = KernelResourceGraph.Plan.build(input, scenario_limits(scale)) ? PlanRejected
				second = KernelResourceGraph.Plan.build(input, scenario_limits(scale)) ? PlanRejected
				if normalized(first) != normalized(second) {
					return Err(SharedInputDiverged)
				}
				first
			}
		}
		unique = planned
		work = KernelResourceGraph.Plan.work(unique)
		if work.copied_payload_bytes != 0 or work.retained_payload_bytes != scale * payload_width {
			return Err(OwnershipDiverged)
		}
		if !ownership_survives(unique) {
			return Err(OwnershipDiverged)
		}
		bytes = blank_pdf({})?
		Ok({ bytes, work: work_vector(work, 0) })
	}

	## Atomic negative twins. Each rejection is a distinct structured diagnostic,
	## none produces a plan, and the fixture still emits only the unrelated blank
	## document, never a partial resource plan.
	atomic_negatives : U64 -> Try({ bytes : List(U8), work : List(U64) }, EvidenceError)
	atomic_negatives = |runtime_context| {
		if runtime_context != 1 {
			return Err(EvidenceFailure)
		}
		rejections = check_negatives(runtime_context)?
		bytes = blank_pdf({})?
		Ok({ bytes, work: [rejections, 0, bytes.len()] })
	}
}

payload_width : U64
payload_width = 8

blank_pdf : {} -> Try(List(U8), Gate4ResourceGraphEvidence.EvidenceError)
blank_pdf = |{}| {
	plan = KernelStructure.build_blank(1, A4) ? |_| EvidenceFailure
	bytes = KernelEmit.to_bytes(plan) ? |_| EvidenceFailure
	Ok(bytes)
}

image_descriptor : U64 -> KernelResourceGraph.Descriptor
image_descriptor = |subtype| {
	bit_depth: 8,
	components: 1,
	flags: 0,
	height: 1,
	kind: Image,
	subtype: subtype,
	width: 1,
}

## Eight distinct payload bytes per resource, written once into one owned
## allocation. Nothing is copied again for identity, ordering, or equality.
append_payload : List(U8), U64 -> List(U8)
append_payload = |bytes, value| bytes
	.append(value.shr_wrap(56).to_u8_wrap())
	.append(value.shr_wrap(48).to_u8_wrap())
	.append(value.shr_wrap(40).to_u8_wrap())
	.append(value.shr_wrap(32).to_u8_wrap())
	.append(value.shr_wrap(24).to_u8_wrap())
	.append(value.shr_wrap(16).to_u8_wrap())
	.append(value.shr_wrap(8).to_u8_wrap())
	.append(value.to_u8_wrap())

scenario_limits : U64 -> KernelResourceGraph.Limits
scenario_limits = |scale| {
	max_collision_entries: scale + 8,
	max_edges: scale * 8 + 8,
	max_equality_bytes: scale * payload_width + 8,
	max_hash_bytes: scale * payload_width + 8,
	max_hashes: scale + 8,
	max_ordering_work: scale * payload_width * 4 + 8,
	max_payload_bytes: scale * payload_width + 8,
	max_placements: scale + 8,
	max_resources: scale + 8,
	max_root_uses: scale + 8,
	max_roots: 4,
	max_topological_work: scale * 32 + 32,
}

## `Forward` writes resource `i` at dense ID `i`; `Reversed` writes it at
## `scale - 1 - i`. Both describe the same logical graph, so a normalized plan
## must not be able to tell them apart.
scenario_input : Str, U64, [Forward, Reversed] -> KernelResourceGraph.Input
scenario_input = |mode, scale, direction| {
	var $bytes = List.with_capacity(scale * payload_width)
	var $resources = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		start = $bytes.len()
		$bytes = append_payload($bytes, logical_of(direction, scale, $index) + 1)
		$resources = $resources.append({ descriptor: image_descriptor(0), length: payload_width, start: start })
		$index = $index + 1
	}

	var $edges = List.with_capacity(scale * 4)
	var $index_2 = 0
	while $index_2 < scale {
		logical = logical_of(direction, scale, $index_2)
		if mode == "chain" {
			if logical + 1 < scale {
				$edges = $edges.append({ source: $index_2, target: dense_of(direction, scale, logical + 1) })
			}
		} else if mode == "fan" {
			if logical == 0 {
				var $target = 1
				while $target < scale {
					$edges = $edges.append({ source: $index_2, target: dense_of(direction, scale, $target) })
					$target = $target + 1
				}
			}
		} else {
			var $step = 1
			while $step <= 4 {
				if logical + $step < scale {
					$edges = $edges.append({ source: $index_2, target: dense_of(direction, scale, logical + $step) })
				}
				$step = $step + 1
			}
		}
		$index_2 = $index_2 + 1
	}

	## Every scenario declares one content-stream root that directly uses only
	## the graph's entry resource; every other resource must be proved reachable
	## through direct edges alone.
	root_uses = [{ resource: dense_of(direction, scale, 0), root: 0 }]
	placements = [
		{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(0), mcid: 0 }), resource: dense_of(direction, scale, 0), reuse: PlacementSpecific },
		{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(1), mcid: 1 }), resource: dense_of(direction, scale, 0), reuse: PlacementSpecific },
		{ ownership: Artifact(Watermark), resource: dense_of(direction, scale, 0), reuse: Reusable },
	]
	{
		digest_policy: DomainSeparatedSha256,
		edges: $edges,
		payload_bytes: $bytes,
		placements: placements,
		resources: $resources,
		root_count: 1,
		root_uses: root_uses,
	}
}

logical_of : [Forward, Reversed], U64, U64 -> U64
logical_of = |direction, scale, dense| match direction {
	Forward => dense
	Reversed => scale - 1 - dense
}

dense_of : [Forward, Reversed], U64, U64 -> U64
dense_of = |direction, scale, logical| match direction {
	Forward => logical
	Reversed => scale - 1 - logical
}

build_scenario : Str, U64 -> Try(KernelResourceGraph.Plan, Gate4ResourceGraphEvidence.EvidenceError)
build_scenario = |mode, scale| {
	plan = KernelResourceGraph.Plan.build(scenario_input(mode, scale, Forward), scenario_limits(scale)) ? PlanRejected
	Ok(plan)
}

build_reversed : Str, U64 -> Try(KernelResourceGraph.Plan, Gate4ResourceGraphEvidence.EvidenceError)
build_reversed = |mode, scale| {
	plan = KernelResourceGraph.Plan.build(scenario_input(mode, scale, Reversed), scenario_limits(scale)) ? PlanRejected
	Ok(plan)
}

collision_input : U64 -> KernelResourceGraph.Input
collision_input = |scale| {
	half = U64.div_by(scale, 2)
	var $bytes = List.with_capacity(scale * payload_width)
	var $resources = List.with_capacity(scale)
	var $index = 0
	while $index < scale {
		start = $bytes.len()
		$bytes = append_payload($bytes, U64.mod_by($index, half) + 1)
		$resources = $resources.append({ descriptor: image_descriptor(0), length: payload_width, start: start })
		$index = $index + 1
	}
	var $uses = List.with_capacity(scale)
	$index = 0
	while $index < scale {
		$uses = $uses.append({ resource: $index, root: 0 })
		$index = $index + 1
	}
	{

		## The white-box seam folds the production digest into one bucket. The
		## digest procedure itself is unchanged, so this cannot weaken the
		## production identity path.
		digest_policy: TruncatedTestDigest(1),
		edges: [],
		payload_bytes: $bytes,
		placements: [],
		resources: $resources,
		root_count: 1,
		root_uses: $uses,
	}
}

build_collision : U64 -> Try(KernelResourceGraph.Plan, Gate4ResourceGraphEvidence.EvidenceError)
build_collision = |scale| {
	plan = KernelResourceGraph.Plan.build(collision_input(scale), scenario_limits(scale)) ? PlanRejected
	Ok(plan)
}

work_vector : KernelResourceGraph.Work, U64 -> List(U64)
work_vector = |work, diagnostics| [
	work.resources,
	work.direct_edges,
	work.roots,
	work.node_visits,
	work.edge_visits,
	work.ready_operations,
	work.planned_resources,
	work.direct_dictionary_entries,
	work.nested_dictionary_entries,
	work.hashes,
	work.bytes_hashed,
	work.collision_entries,
	work.descriptor_partitions,
	work.ordering_passes,
	work.ordering_byte_visits,
	work.equality_comparisons,
	work.bytes_compared,
	work.unique_payloads,
	work.deduplicated_payloads,
	work.retained_payload_bytes,
	work.copied_payload_bytes,
	work.placements,
	work.sort_comparisons,
	diagnostics,
]

## The normalized plan identity: planned payloads, the root dictionary, and every
## nested direct dictionary, all expressed as payload bytes rather than dense
## IDs.
normalized : KernelResourceGraph.Plan -> List(List(U8))
normalized = |plan| {
	order = KernelResourceGraph.Plan.order(plan)
	var $result = List.with_capacity(order.len() * 2 + 2)
	var $index = 0
	while $index < order.len() {
		resource = list_at(order, $index)
		$result = $result.append(KernelResourceGraph.Plan.payload(plan, resource))
		var $dependencies = KernelResourceGraph.Plan.direct_dependencies(plan, resource)
		var $edge = 0
		while $edge < $dependencies.len() {
			$result = $result.append(KernelResourceGraph.Plan.payload(plan, list_at($dependencies, $edge)))
			$edge = $edge + 1
		}
		$result = $result.append([])
		$index = $index + 1
	}
	var $root = 0
	while $root < KernelResourceGraph.Plan.root_count(plan) {
		dictionary = KernelResourceGraph.Plan.root_dictionary(plan, $root)
		var $entry = 0
		while $entry < dictionary.len() {
			$result = $result.append(KernelResourceGraph.Plan.payload(plan, list_at(dictionary, $entry)))
			$entry = $entry + 1
		}
		$result = $result.append([])
		$root = $root + 1
	}
	$result
}

topological : KernelResourceGraph.Plan -> Bool
topological = |plan| {
	count = KernelResourceGraph.Plan.resource_count(plan)
	order = KernelResourceGraph.Plan.order(plan)
	var $position = List.repeat(0, count)
	var $index = 0
	while $index < order.len() {
		$position = list_set($position, list_at(order, $index), $index)
		$index = $index + 1
	}
	var $ordered = order.len() == count
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

## Repeated placements of one deduplicated visual identity must keep distinct
## semantic associations and a distinct artifact classification.
ownership_survives : KernelResourceGraph.Plan -> Bool
ownership_survives = |plan| {
	if KernelResourceGraph.Plan.placement_count(plan) != 3 {
		Bool.False
	} else {
		first = KernelResourceGraph.Plan.placement_at(plan, 0)
		second = KernelResourceGraph.Plan.placement_at(plan, 1)
		third = KernelResourceGraph.Plan.placement_at(plan, 2)
		semantic_ok = semantic_key(first.ownership) == 1 and semantic_key(second.ownership) == 2 and semantic_key(third.ownership) == 0
		semantic_ok and first.resource == second.resource and second.resource == third.resource
	}
}

semantic_key : KernelResourceGraph.Ownership -> U64
semantic_key = |ownership| match ownership {
	Artifact(_) => 0
	Semantic(semantic) => Semantics.FragmentId.index(semantic.fragment) + 1
}

negative_limits : KernelResourceGraph.Limits
negative_limits = {
	max_collision_entries: 64,
	max_edges: 64,
	max_equality_bytes: 4096,
	max_hash_bytes: 4096,
	max_hashes: 64,
	max_ordering_work: 4096,
	max_payload_bytes: 4096,
	max_placements: 64,
	max_resources: 64,
	max_root_uses: 64,
	max_roots: 8,
	max_topological_work: 4096,
}

negative_input : List(KernelResourceGraph.Edge), U64, List(KernelResourceGraph.RootUse), List(KernelResourceGraph.Placement), U64, KernelResourceGraph.DigestPolicy -> KernelResourceGraph.Input
negative_input = |edges, root_count, root_uses, placements, resource_count, digest_policy| {
	var $bytes = List.with_capacity(resource_count * payload_width)
	var $resources = List.with_capacity(resource_count)
	var $index = 0
	while $index < resource_count {
		start = $bytes.len()
		$bytes = append_payload($bytes, $index + 1)
		$resources = $resources.append({ descriptor: image_descriptor(0), length: payload_width, start: start })
		$index = $index + 1
	}
	{
		digest_policy: digest_policy,
		edges: edges,
		payload_bytes: $bytes,
		placements: placements,
		resources: $resources,
		root_count: root_count,
		root_uses: root_uses,
	}
}

rejected : U64,
Try(KernelResourceGraph.Plan, KernelResourceGraph.Error),
[
	CollisionEntries,
	Cycle,
	DuplicateEdge,
	DuplicateRootUse,
	EdgeLimit,
	EdgeSource,
	EdgeTarget,
	EqualityBytes,
	HashBytes,
	OrderingWork,
	PayloadRange,
	PlacementRange,
	ResourceLimit,
	SelfCycle,
	SemanticMerge,
	TopologicalWork,
	Unreachable,
] -> Try({}, Gate4ResourceGraphEvidence.EvidenceError)
rejected = |ordinal, result, expected| {
	matched = match result {
		Ok(_) => Bool.False
		Err(error) => match expected {
			CollisionEntries => match error {
				CollisionEntryLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			Cycle => match error {
				DependencyCycle({ planned: 0, resource: 0 }) => Bool.True
				_ => Bool.False
			}
			DuplicateEdge => match error {
				DuplicateEdge(_) => Bool.True
				_ => Bool.False
			}
			DuplicateRootUse => match error {
				DuplicateRootUse(_) => Bool.True
				_ => Bool.False
			}
			EdgeLimit => match error {
				EdgeLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			EdgeSource => match error {
				EdgeSourceOutOfRange(_) => Bool.True
				_ => Bool.False
			}
			EdgeTarget => match error {
				EdgeTargetOutOfRange(_) => Bool.True
				_ => Bool.False
			}
			EqualityBytes => match error {
				EqualityByteLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			HashBytes => match error {
				HashByteLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			OrderingWork => match error {
				OrderingWorkLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			PayloadRange => match error {
				PayloadRangeInvalid(_) => Bool.True
				_ => Bool.False
			}
			PlacementRange => match error {
				PlacementResourceOutOfRange(_) => Bool.True
				_ => Bool.False
			}
			ResourceLimit => match error {
				ResourceLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			SelfCycle => match error {
				SelfCycle(_) => Bool.True
				_ => Bool.False
			}
			SemanticMerge => match error {
				SemanticOwnershipMerge(_) => Bool.True
				_ => Bool.False
			}
			TopologicalWork => match error {
				TopologicalWorkLimitExceeded(_) => Bool.True
				_ => Bool.False
			}
			Unreachable => match error {
				UnreachableResource(_) => Bool.True
				_ => Bool.False
			}
		}
	}
	if matched {
		Ok({})
	} else {
		Err(MissingRejection(ordinal))
	}
}

## Every negative twin below is atomic: one input differs from a valid scenario
## in exactly one way, and each returns a distinct bounded diagnostic.
check_negatives : U64 -> Try(U64, Gate4ResourceGraphEvidence.EvidenceError)
check_negatives = |context| {

	## `context` is always 1 here, but it arrives from the runtime argument list
	## so the whole rejection sweep is evaluated at runtime and its bounded work
	## and allocation cost are actually measured.
	one = context
	two = context + 1
	three = context + 2
	outside = context + 8
	root_zero = [{ resource: 0, root: 0 }]
	rejected(1, KernelResourceGraph.Plan.build(negative_input([{ source: outside, target: 0 }], 1, root_zero, [], two, DomainSeparatedSha256), negative_limits), EdgeSource)?
	rejected(2, KernelResourceGraph.Plan.build(negative_input([{ source: 0, target: outside }], 1, root_zero, [], two, DomainSeparatedSha256), negative_limits), EdgeTarget)?
	rejected(3, KernelResourceGraph.Plan.build(negative_input([{ source: 0, target: 0 }], 1, root_zero, [], one, DomainSeparatedSha256), negative_limits), SelfCycle)?
	rejected(
		4,
		KernelResourceGraph.Plan.build(
			negative_input([{ source: 0, target: 1 }, { source: 1, target: 0 }], 1, root_zero, [], two, DomainSeparatedSha256),
			negative_limits,
		),
		Cycle,
	)?
	rejected(
		5,
		KernelResourceGraph.Plan.build(
			negative_input(
				[{ source: 0, target: 1 }, { source: 1, target: 2 }, { source: 2, target: 0 }],
				1,
				root_zero,
				[],
				three,
				DomainSeparatedSha256,
			),
			negative_limits,
		),
		Cycle,
	)?
	rejected(6, KernelResourceGraph.Plan.build(negative_input([], 1, root_zero, [], two, DomainSeparatedSha256), negative_limits), Unreachable)?
	rejected(
		7,
		KernelResourceGraph.Plan.build(
			negative_input([{ source: 0, target: 1 }, { source: 0, target: 1 }], 1, root_zero, [], two, DomainSeparatedSha256),
			negative_limits,
		),
		DuplicateEdge,
	)?
	rejected(
		8,
		KernelResourceGraph.Plan.build(
			negative_input([], 1, [{ resource: 0, root: 0 }, { resource: 0, root: 0 }], [], one, DomainSeparatedSha256),
			negative_limits,
		),
		DuplicateRootUse,
	)?
	rejected(
		9,
		KernelResourceGraph.Plan.build(negative_input([], 1, root_zero, [], two, DomainSeparatedSha256), { ..negative_limits, max_resources: 1 }),
		ResourceLimit,
	)?
	rejected(
		10,
		KernelResourceGraph.Plan.build(
			negative_input([{ source: 0, target: 1 }], 1, root_zero, [], two, DomainSeparatedSha256),
			{ ..negative_limits, max_edges: 0 },
		),
		EdgeLimit,
	)?
	rejected(
		11,
		KernelResourceGraph.Plan.build(negative_input([], 1, root_zero, [], two, DomainSeparatedSha256), { ..negative_limits, max_hash_bytes: 8 }),
		HashBytes,
	)?
	rejected(
		12,
		KernelResourceGraph.Plan.build(
			negative_input([], 1, [{ resource: 0, root: 0 }, { resource: 1, root: 0 }], [], two, TruncatedTestDigest(1)),
			{ ..negative_limits, max_collision_entries: 1 },
		),
		CollisionEntries,
	)?
	rejected(
		13,
		KernelResourceGraph.Plan.build(
			negative_input([], 1, [{ resource: 0, root: 0 }, { resource: 1, root: 0 }], [], two, TruncatedTestDigest(1)),
			{ ..negative_limits, max_ordering_work: 0 },
		),
		OrderingWork,
	)?
	rejected(
		14,
		KernelResourceGraph.Plan.build(
			negative_input([], 1, [{ resource: 0, root: 0 }, { resource: 1, root: 0 }], [], two, TruncatedTestDigest(1)),
			{ ..negative_limits, max_equality_bytes: 0 },
		),
		EqualityBytes,
	)?
	rejected(
		15,
		KernelResourceGraph.Plan.build(
			negative_input([{ source: 0, target: 1 }], 1, root_zero, [], two, DomainSeparatedSha256),
			{ ..negative_limits, max_topological_work: 0 },
		),
		TopologicalWork,
	)?
	rejected(
		16,
		KernelResourceGraph.Plan.build(
			{
				digest_policy: DomainSeparatedSha256,
				edges: [],
				payload_bytes: [1, 2, 3],
				placements: [],
				resources: [{ descriptor: image_descriptor(0), length: 1, start: U64.highest }],
				root_count: 1,
				root_uses: root_zero,
			},
			negative_limits,
		),
		PayloadRange,
	)?
	rejected(
		17,
		KernelResourceGraph.Plan.build(
			negative_input(
				[],
				1,
				root_zero,
				[{ ownership: Semantic({ fragment: Semantics.FragmentId.from_index(0), mcid: 0 }), resource: 0, reuse: Reusable }],
				one,
				DomainSeparatedSha256,
			),
			negative_limits,
		),
		SemanticMerge,
	)?
	rejected(
		18,
		KernelResourceGraph.Plan.build(
			negative_input([], 1, root_zero, [{ ownership: Artifact(Background), resource: outside, reuse: Reusable }], one, DomainSeparatedSha256),
			negative_limits,
		),
		PlacementRange,
	)?
	Ok(context * 18)
}

list_at : List(a), U64 -> a
list_at = |items, index| match items.get(index) {
	Ok(value) => value
	Err(OutOfBounds) => {
		crash "Gate 4 resource-graph evidence index escaped"
	}
}

list_set : List(a), U64, a -> List(a)
list_set = |items, index, value| match items.set(index, value) {
	Ok(next) => next
	Err(OutOfBounds) => {
		crash "Gate 4 resource-graph evidence update escaped"
	}
}

## A four-node fan plans its shared dependencies first, keeps one direct root
## entry, and copies no payload bytes.
expect {
	result = Gate4ResourceGraphEvidence.resource_plan("fan", 4)?
	result.work == [4, 3, 1, 8, 6, 13, 4, 1, 3, 4, 32, 0, 0, 0, 0, 0, 0, 4, 0, 32, 0, 3, 13, 0]
}

## A forced collision bucket merges only exactly equal payloads.
expect {
	result = Gate4ResourceGraphEvidence.collision_plan(4)?
	result.work.get(11) == Ok(4) and result.work.get(17) == Ok(2) and result.work.get(18) == Ok(2)
}

## Every negative twin is rejected and no plan escapes.
expect {
	result = Gate4ResourceGraphEvidence.atomic_negatives(1)?
	result.work.get(0) == Ok(18) and result.work.get(1) == Ok(0)
}
