app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.8.0/BUNcJDHxCd7xLVSe3WBioyXqR6tm1MqXwzwGgtnmqK43.tar.zst",
	pdf: "../package/all.roc",
}

import fuzz.Fuzz
import fuzz.Model
import pdf.KernelResourceGraph as Graph

target = Fuzz.suite([])

Action : [Connect({ source : U64, target : U64 }), Use(U64), Retain(U64)]

Rejection : [RawEdge(Graph.Edge), RawUse(U64), Self(U64), Missing(U64), Cycle({ planned : U64, resource : U64 }), Unexpected]

Facts : { authored_map : List(U64), dependencies : List(List(U64)), order : List(U64), payloads : List(List(U8)), roots : List(U64) }

edges : List(Graph.Edge)
edges = [{ source: 0, target: 1 }, { source: 0, target: 2 }, { source: 1, target: 0 }, { source: 2, target: 1 }]

authored : List(U8)
authored = [2, 1, 2]

machine : Model.Machine(List(Action), Action)
machine = {
	init: [],
	actions: |history| if (history.len() < 3) edges.map(|edge| Connect(edge)).concat([Use(0), Use(1), Use(2), Retain(0), Retain(1), Retain(2)]) else [],
	step: |history, action| history.append(action),
	rules: [
		Model.always("plan or exact diagnostic agrees with the authored graph", |history| check(authored, history)),
		Model.sometimes("two authored edges collapse to one direct dependency", |history| history == [Connect({ source: 0, target: 1 }), Connect({ source: 2, target: 1 }), Use(0)]),
		Model.sometimes("an alias edge becomes a self-cycle", |history| history == [Connect({ source: 0, target: 2 })]),
		Model.sometimes("a closure-only resource stays outside the root dictionary", |history| history == [Use(0), Retain(1)]),
		Model.sometimes("reachable distinct resources form a cycle", |history| history == [Connect({ source: 0, target: 1 }), Connect({ source: 1, target: 0 }), Use(0)]),
	],
}

expect {
	report = Model.explore(machine, { depth: 4, key: |history| history, verify: EveryStep })
	if report.verdict != Holds(Exhausted) {
		crash "${Model.explain(report)} ${Str.inspect(report.verdict)}"
	}
	report.states == 1111 and report.steps == 1110 and report.depth == 3 and report.reached.len() == 4
}

# Three distinct resources distinguish a direct edge from transitive closure.
expect check([3, 1, 2], [Use(0), Connect({ source: 0, target: 2 }), Connect({ source: 2, target: 1 })])

# Processing node 0 releases node 1 while node 2 is already ready.
expect check([2, 3, 1], [Connect({ source: 0, target: 2 }), Use(0), Retain(1)])

# A disjoint ready node is emitted before the planner diagnoses the cycle.
expect check([1, 2, 3], [Connect({ source: 0, target: 1 }), Connect({ source: 1, target: 0 }), Use(0), Retain(2)])

limits : Graph.Limits
limits = {
	max_collision_entries: 4,
	max_edges: 4,
	max_equality_bytes: 32,
	max_hash_bytes: 512,
	max_hashes: 4,
	max_ordering_work: 512,
	max_payload_bytes: 4,
	max_placements: 0,
	max_resources: 4,
	max_root_uses: 4,
	max_roots: 1,
	max_topological_work: 128,
}

descriptor : Graph.Descriptor
descriptor = { bit_depth: 0, components: 0, flags: 0, height: 0, kind: Function, subtype: 0, width: 0 }

check : List(U8), List(Action) -> Bool
check = |payload, history| {
	raw_edges = history.keep_oks(
		|action| match action {
			Connect(edge) => Ok(edge)
			_ => Err(OtherAction)
		},
	)
	raw_uses = history.keep_oks(
		|action| match action {
			Use(resource) => Ok(resource)
			_ => Err(OtherAction)
		},
	)
	retained = history.keep_oks(
		|action| match action {
			Retain(resource) => Ok(resource)
			_ => Err(OtherAction)
		},
	)
	actual = Graph.Plan.build_with_closure_uses(
		{
			digest_policy: TruncatedTestDigest(1),
			edges: raw_edges,
			payload_bytes: payload,
			placements: [],
			resources: payload.map_with_index(|_, start| { descriptor, length: 1, start }),
			root_count: 1,
			root_uses: raw_uses.map(|resource| { resource, root: 0 }),
		},
		retained.map(|resource| { resource, root: 0 }),
		limits,
	)
	actual.map_ok(|plan| observe(plan, payload.len())).map_err(observe_error) == expected(payload, raw_edges, raw_uses, retained)
}

observe : Graph.Plan, U64 -> Facts
observe = |plan, resource_count| {
	nodes = ids(Graph.Plan.resource_count(plan))
	{
		authored_map: ids(resource_count).map(|resource| Graph.Plan.canonical_index(plan, resource)),
		dependencies: nodes.map(|node| Graph.Plan.direct_dependencies(plan, node)),
		order: Graph.Plan.order(plan),
		payloads: nodes.map(|node| Graph.Plan.payload(plan, node)),
		roots: Graph.Plan.root_dictionary(plan, 0),
	}
}

observe_error : Graph.Error -> Rejection
observe_error = |error| match error {
	DuplicateEdge(edge) => RawEdge(edge)
	DuplicateRootUse({ root: 0, resource }) => RawUse(resource)
	SelfCycle({ resource }) => Self(resource)
	UnreachableResource({ resource }) => Missing(resource)
	DependencyCycle(cycle) => Cycle(cycle)
	_ => Unexpected
}

# A fixed descriptor, one-byte payloads and one digest bucket give an
# independent identity rule: use the numeric rank of the authored byte.
expected : List(U8), List(Graph.Edge), List(U64), List(U64) -> Try(Facts, Rejection)
expected = |payload, raw_edges, raw_uses, retained| {
	authored_ids = ids(payload.len())
	for source in authored_ids {
		for target_id in authored_ids {
			if raw_edges.count_if(|edge| edge == { source, target: target_id }) > 1 {
				return Err(RawEdge({ source, target: target_id }))
			}
		}
	}
	ordered_bytes = [1.U8, 2, 3].keep_if(|byte| payload.contains(byte))
	nodes = ids(ordered_bytes.len())
	canonical = payload.map(|byte| ordered_bytes.count_if(|other| other < byte))
	dependencies = nodes.map(|source| nodes.keep_if(|target_id| raw_edges.any(|edge|
		at(canonical, edge.source) == source and at(canonical, edge.target) == target_id)))
	for node in nodes {
		if at(dependencies, node).contains(node) {
			return Err(Self(node))
		}
	}
	for resource in authored_ids {
		if raw_uses.count_if(|used| used == resource) > 1 {
			return Err(RawUse(resource))
		}
	}
	roots = nodes.keep_if(|node| raw_uses.any(|resource| at(canonical, resource) == node))
	seeds = roots.concat(retained.map(|resource| at(canonical, resource)))
	reached = nodes.fold(
		seeds,
		|seen, _| {
			# One round extends an authored path by one edge. At most the number
			# of nodes is needed, even when the graph contains a cycle.
			nodes.keep_if(|node| seen.contains(node) or seen.any(|parent| at(dependencies, parent).contains(node)))
		},
	)
	match nodes.keep_if(|node| !reached.contains(node)).first() {
		Ok(resource) => return Err(Missing(resource))
		Err(ListWasEmpty) => {}
	}
	order = schedule(nodes, dependencies)?
	Ok({ authored_map: canonical, dependencies, order, payloads: ordered_bytes.map(|byte| [byte]), roots })
}

# Recompute the ready set from the unscheduled nodes on every iteration.
schedule : List(U64), List(List(U64)) -> Try(List(U64), Rejection)
schedule = |nodes, dependencies| {
	var $pending = nodes
	var $order = []
	while !$pending.is_empty() {
		pending = $pending
		ready = pending.keep_if(|node| at(dependencies, node).all(|dependency| !pending.contains(dependency)))
		match ready.first() {
			Err(ListWasEmpty) => return Err(Cycle({ planned: $order.len(), resource: at(pending, 0) }))
			Ok(node) => {
				$order = $order.append(node)
				$pending = pending.keep_if(|other| other != node)
			}
		}
	}
	Ok($order)
}

ids : U64 -> List(U64)
ids = |count| List.repeat(0, count).map_with_index(|_, index| index)

at : List(a), U64 -> a
at = |items, index| items.get(index) ?? crash "invalid model index"
