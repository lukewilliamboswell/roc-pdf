# Gate 1 catalog and page-leaf lowering slice

## Scope and status

`KernelStructure` lowers one through 32 blank pages into the private object
builder and sealed plan. The exact object order is catalog, root page-tree
node, then one page object plus a consecutive content-stream/length-object pair
per page. Catalog, pages, page dictionaries, media boxes, empty resource
dictionaries, contents, parent links, and generation-zero references are all
represented through the same checked flat stores used by the generic kernel.

The current limit of 32 pages is the documented fixed page-tree fanout. Inputs
above it fail before allocating stores. This is partial Gate 1 evidence: the
reusable balanced-tree builder must add deterministic upper levels before the
package raises the limit or claims the thousands-of-pages capability.

## Representation and traversal

Names and shared direct values are stored once. Every page retains scalar IDs
for the common media box, empty resources dictionary, page type, and parent
reference rather than copying those values. Page dictionaries contribute five
flat edges each. Empty generated content payloads retain no byte allocation.

Lowering uses direct indexed loops for page references and page slices. It
performs `O(pages)` work with constant auxiliary scalar state plus the exact
output stores. All count formulas, object numbers, and xref-object assignment
use checked `U64` arithmetic before mutation. The builder limits are derived
from the accepted page count instead of reserving a global worst-case arena.

The lowerer does not materialize serialized objects, compressed streams, xref
bytes, or a list of per-page object lists. It produces the compact replayable
sealed plan consumed by the forthcoming shared emission transition.

## Evidence still required

Gate 1 completion still requires balanced upper page-tree levels, independent
page/object assertions, exact optimized allocations and visits, thousands-page
stress, xref and byte emission, external parser validation, and byte-identical
buffered/chunk modes.
