# production-visual resource dependency graph and deterministic resource identity

This records the design, complexity, ownership, and evidence for the first
production-visual slice: the resource-planning foundation. It covers the direct-edge
resource dependency DAG, transactional rejection, deterministic topological
planning, complete per-content-stream direct resource plans, and deterministic
deduplication by digest candidate plus exact equality.

**Scope.** This is the reusable resource-planning boundary that later production-visual
work (Form XObjects, masks, patterns, annotation appearances, images, ICC
profiles) will plug into. It does not implement any of those PDF features, and
it does not close production-visual.

## Modules

- `package/KernelResourceGraph.roc` — resource identity, descriptors, payload
  identity, direct-edge graph validation, deterministic planning, and
  deduplication.
- `tests/resource_graph/Fixture.roc` — scaled scenarios, adversarial
  ordering, forced digest collisions, ownership paths, and the atomic negative
  sweep.
- `package/KernelSha256.roc` — gains `digest_range`, which hashes a prefix plus
  an exact range of an already-owned allocation. `digest` is now defined in
  terms of it and is byte-for-byte unchanged.

The Form XObject slice later extended this module compatibly:
`identity_digest` exposes the unchanged versioned identity procedure for one
source range (so canonical form recipes embed dependency identities without a
second digest implementation), and the plan additionally exposes `placements`
and the retained `canonical_index` map described under Ownership.

## Why a new representation

`KernelResource` assigns PDF dictionary *names* to an already-planned dense
store, and `KernelResourceUse` counts tagged-visual colour and image use inside one
scene. Neither carries dependency edges, payload identity, descriptor facts, or
placement ownership, so neither can express the production-visual contract. They are left
untouched; production-visual owns a separate boundary. This matches `architecture.md`
("Resources and annotations") without changing any enduring decision, so no
architecture or roadmap edit was required.

## Representation

- `Source` is `{ descriptor, start, length }` — an exact range into one flat
  caller-owned `payload_bytes` allocation. Resources, roots, edges, and
  placements are dense scalar IDs into flat lists. Nothing is recursive.
- `Descriptor` carries kind plus the scalar facts (`subtype`, `width`,
  `height`, `components`, `bit_depth`, `flags`) that must distinguish resources
  whose bytes alone are insufficient. Descriptor facts are hashed *before* the
  payload, so resources with equal bytes and unequal descriptors do not even
  share a collision bucket.
- Resource identity is independent of PDF object numbers; no PDF dictionary or
  object internal crosses this boundary.
- Reusable visual identity (`Canonical`) is separate from per-placement
  ownership (`Placement`, carrying `Ownership` and `Reuse`).
- The graph stores **direct edges only**, as a compressed dependency store
  (`dependency_offsets` + `dependency_heads`) plus a reverse index built by
  counting and prefix sums. No transitive-reachability set is built for any
  node.

## Identity and deduplication procedure

1. **Hash once.** Each payload is hashed exactly once with a versioned,
   domain-separated SHA-256 over
   `"roc-pdf/resource-identity/v1\n" || descriptor || length || payload`.
   `digest_range` reads the payload in place, so hashing copies zero payload
   bytes. `hashes == resources` and `bytes_hashed == payload_bytes` in every
   scenario.
2. **Bucket.** Entries are ordered by a deterministic bottom-up merge sort on
   `(fingerprint, descriptor, length, index)` — worst case `O(n log n)` on
   already ordered, reverse ordered, and equal input; no first-pivot quicksort.
3. **Candidate only.** A shared fingerprint is a *candidate*. Each bucket is
   partitioned by exact descriptor and exact byte length first.
4. **Order.** Each partition with more than one entry is ordered by an
   iterative most-significant-byte radix refinement with an explicit segment
   stack. An entry contributes a byte visit only while still tied with another
   entry, and a counting/scatter pass runs only at a real split, of which there
   are at most `entries - 1`. Declared bound: `O(bucket_entries +
   bucket_bytes)` byte work. There is **no all-pairs comparison**.
5. **Confirm.** Adjacent exact payload equality confirms each merge:
   `entries - 1` comparisons, stopping at the first differing byte. A hash
   collision is never treated as equality.
6. **Canonical IDs** are assigned in that content-derived order, so they do not
   depend on insertion, map, or traversal order.

## Planning

- **Closure.** An iterative stack walk from every declared content-stream root
  marks reachability over direct edges. Any canonical resource no root can
  reach is `UnreachableResource`. Attacker-controlled depth is never recursed.
- **Topological order.** Kahn's algorithm over the reverse index. Ready nodes
  are resolved by a binary min-heap on canonical ID — the documented **total**
  tie-break order, and content-derived, so adversarial insertion orders produce
  the identical normalized plan. Failure to plan every node is
  `DependencyCycle` naming the lowest still-blocked resource; a canonical
  self-edge is the separate `SelfCycle`.
- **Complexity.** `O(V + E)` for validation, closure, and dictionary
  construction; `O((V + E) log V)` for planning; `O(n log n)` for the identity
  and edge sorts; `O(entries + bytes)` for collision ordering and equality.
- **Direct dictionaries.** Each content-stream root receives exactly its direct
  canonical resources; each resource's nested dictionary contains exactly its
  own direct dependencies and never a transitive one. Both come from normalized
  facts. Resource use is never recovered by scanning serialized operators or
  PDF content bytes.

## Limits, arithmetic, and diagnostics

Every dimension has an explicit checked limit: resources, edges, roots, root
uses, placements, payload bytes, hashes, hashed bytes, collision entries,
ordering work, compared bytes, and topological work. All accumulation uses
checked arithmetic; an impossible or overflowing payload range is
`PayloadRangeInvalid`. Every failure is one stable structured value holding
compact scalar IDs and the exact failed bound — no diagnostic retains a
payload, so diagnostics stay bounded regardless of input size. Failure is
transactional: no plan, no partial plan, and no PDF bytes.

## Ownership

- **Consumed.** The whole `Input` — source list, raw edge list, root uses, and
  placements.
- **Retained.** The one `payload_bytes` allocation (moved, not copied), the
  canonical descriptor/range list, the direct dependency store and its reverse
  index, the plan order, the per-root dictionaries, the placement records,
  and — since the Form XObject slice — the source-to-canonical map, which
  lowering consumes through `canonical_index` instead of re-deriving identity.
  The map is one already-built `U64` list per source, so retaining it changes
  no allocation count.
- **Dropped.** The authoring-side source list and the raw edge list. No
  authoring tree or scene store survives.
- **Copied payload bytes: 0.** Deduplicated resources *share exact ranges* of
  the single owned allocation; identity, ordering, and equality all read that
  allocation in place. The plan does not compact payloads into a second buffer,
  so `retained_payload_bytes` equals the caller's original allocation length —
  duplicate bytes stay resident until the caller releases it. That is the
  honest retention statement: sharing avoids the copy, not the retention.
- **ARC.** The `unique` case hands a freshly built input straight to the
  planner (ordinary one-shot path); the `shared` case retains the same
  immutable input and plans it twice. Both produce the identical normalized
  plan — correctness never depends on uniqueness — at 857 versus 1712
  allocations for the same 100-resource input. That ratio is the retained-input
  cost, and no work counter changes between them.
- **No allocation per edge traversal, compared byte, or transitive
  dependency.** Traversals index dense buffers; the only collision-path
  allocations are the 256-slot counting buffers and one scratch segment per
  real radix split (at most `entries - 1`), which never run on the ordinary
  unique-digest path (`collision_entries == 0`).

## Evidence

Roc `expect` coverage in `KernelResourceGraph.roc`: empty graph, leaf-only
graph and its tie-break order, linear nested chain, branching DAG with a shared
dependency, adversarial insertion orders, byte-identical deduplication, equal
bytes with differing descriptors staying distinct, repeated placements keeping
distinct semantic and artifact ownership, multiple roots with exact direct
dictionaries, forced digest-collision bucket with equal and unequal payloads,
and negative twins for every rejection and every limit.

Harness cases (`tests/spec.json`, `scenario_revision`
`resource-graph-v1`, measured on the pinned dev backend at
`before_fixture_main`):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| chain x100 | 1718 | nodes 200, edges 198, ready 200 |
| chain x1000 | 16142 | nodes 2000, edges 1998, ready 2000 |
| fan x100 | 1718 | nodes 200, edges 198, ready 797 |
| fan x1000 | 16142 | nodes 2000, edges 1998, ready 11311 |
| dense x100 | 2898 | edges 780, direct edges 390 |
| dense x1000 | 28122 | edges 7980, direct edges 3990 |
| collide x100 | 904 | bucket 100, comparisons 99, bytes compared 792 |
| collide x1000 | 10571 | bucket 1000, comparisons 999, bytes compared 7991 |
| unique x100 | 857 | one planner run |
| shared x100 | 1712 | two planner runs, identical counters |
| atomic negatives | 386 | 18 rejections, 0 escaped plans |

What the scaling shows:

- `node_visits == 2 * resources` and `edge_visits == 2 * direct_edges` in every
  shape — closure and planning each visit every node and edge once, and nothing
  else does.
- `chain` versus `dense` at fixed node count isolates per-edge work
  (198 → 780 edge visits at 100 nodes).
- `chain` versus `fan` at fixed node and edge count isolates ready-set
  tie-break work (200 → 797 at 100 nodes; 2000 → 11311 at 1000), which is the
  `log V` factor and not a per-node constant.
- `bytes_hashed == 8 * resources` is the per-byte term; `hashes == resources`
  proves each payload is inspected once.
- The collision cases prove the entry-plus-byte bound: at 1000 entries the
  planner performs 999 adjacent equality comparisons and compares 7991 bytes
  against a 8000-byte bucket. All-pairs equality would have needed 499,500
  comparisons. `unique_payloads == 500` and `deduplicated_payloads == 500`
  prove that only exactly equal payloads merged.
- Allocation counts scale linearly in resources and edges, with no per-byte or
  per-transitive-dependency term.

Baselines for `arm64mac` are recorded equal to the measured `x64musl` values,
matching every existing case in the suite; they were not independently measured
on this host.
