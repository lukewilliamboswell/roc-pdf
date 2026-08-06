# Gate 1 shared balanced shape

## Representation rule

`KernelBalanced.Shape` is the shared topology for Gate 1 balanced structures.
It always uses a maximum fanout of 32 and left-packed breadth-first levels.
There is no flat-to-balanced size threshold: one item creates a root leaf, and
the 33rd item creates a root above two leaves. Tree-specific lowerers retain
their own ordering, key, `Limits`, `Count`, and object-numbering policy instead
of placing PDF semantics in the shared shape.

The opaque shape stores only the accepted item count, one node count and offset
per level, and the total node count. It does not store per-item or per-node
child ranges. Accessors derive a node's contiguous child-node and descendant-
item spans arithmetically from the sealed shape. The shape builder rejects zero
items and the caller's explicit item limit before allocating level storage;
node-offset accumulation is checked `U64` arithmetic.

## Page-tree integration evidence

The page-tree lowerer now consumes the shared shape rather than maintaining a
second topology implementation. Its PDF-specific work remains separate:
object numbering, parent references, descendant `/Count` values, `/Kids`
arrays, and checked object-store limits are all derived during structural
lowering.

Focused tests cover one item, the 33-item depth transition, the 4,096-item
stress shape, zero and over-limit failures, and the maximum accepted 1,048,576-
item shape. The maximum has level counts `[1, 32, 1024, 32768]` and exactly
33,825 nodes.

The pinned optimized 4,096-page whole-pipeline fixture remains byte-identical:
1,084,927 bytes with SHA-256
`bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756`.
Its current exact baseline is 134,274 allocations. All page, node, object,
value, edge, reference, and emitted-byte counters remain unchanged. The
20,481-allocation compiler-wide shift from the slice's original 113,793 count
is reviewed in `roc-nightly-2026-August-05-24f0b47.md`; it is not caused by the
opaque accessor boundary.

This slice establishes only the reusable topology and its page-tree use. Name,
number, ID, and ParentTree rules and evidence are recorded separately in
`gate-1-balanced-indexes.md`. The structurally distinct linked outline hierarchy
is recorded in `gate-1-outline-hierarchy.md`.
