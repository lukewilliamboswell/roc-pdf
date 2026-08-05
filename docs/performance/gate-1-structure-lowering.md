# Gate 1 catalog and page-leaf lowering slice

## Scope and status

`KernelStructure` lowers one through 1,048,576 blank pages into the private
object builder and sealed plan. The exact object order is catalog, page-tree
nodes in breadth-first order, then one page object plus a consecutive content-
stream/length-object pair per page. Catalog, `/Pages` and page dictionaries,
media boxes, empty resource dictionaries, contents, parent links, descendant
counts, and generation-zero references are all represented through the same
checked flat stores used by the generic kernel.

The page tree uses a fixed fanout of 32 and a left-packed partition. Every leaf
is at the same depth; each non-root node and page has an explicit parent; and
each node records its exact descendant page count. The explicit package limit
is checked before shape or store allocation.

## Representation and traversal

Names and shared direct values are stored once. Every page retains scalar IDs
for the common media box, empty resources dictionary, page type, and its leaf's
shared parent reference rather than copying those values. Page dictionaries
contribute five flat edges each. Empty generated content payloads retain no
byte allocation.

Lowering uses direct indexed loops for tree levels, references, and page
slices. It performs `O(pages + nodes)` work. Shape metadata is one count and
offset per level; all other storage is the exact output store or a temporary
flat edge list bounded by fanout. All count formulas, object numbers, node
capacities, and xref-object assignment use checked `U64` arithmetic before
mutation. Builder limits are derived from the accepted page and node counts
instead of reserving a global worst-case arena.

The lowerer does not materialize serialized objects, compressed streams, xref
bytes, or a list of per-page object lists. It produces the compact replayable
sealed plan consumed by the forthcoming shared emission transition.

## Evidence still required

Focused Roc tests cover the single-node tree, the 33-page depth transition, and
a deterministic 4,096-page shape. The independent byte checker recursively
walks `/Kids`, `/Parent`, and `/Count` and rejects cycles, unreachable nodes,
mixed child kinds, and fanout violations.

The pinned optimized 4,096-page whole-pipeline fixture records exactly 113,794
Roc allocations, 133 tree nodes, 12,422 objects, 17,186 values, 4,232 array
edges, 21,013 dictionary edges, 25,245 total builder edges, 8,585 checked
references, and 1,084,927 emitted-byte visits. Its exact output hash is
`bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756`.
The independent checker validates all 4,096 pages and every xref offset. This
fixture exposed dynamic-shift code generation that corrupted runtime `U64`
byte emission; fixed-position shifts now make both offsets and identifier facts
correct for non-constant large plans.

Gate 1 completion still requires broader reusable builders for the other
required tree kinds, retained-memory evidence, and the remaining external
validators. CI must confirm the checked-in allocation count and hash on x64
Linux before the cross-system evidence is complete.
