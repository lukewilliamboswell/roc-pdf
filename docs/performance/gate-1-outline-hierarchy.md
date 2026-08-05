# Gate 1 linked outline hierarchy

## Representation rule

PDF document outlines are not balanced search trees. ISO 32000-2:2020 12.3.3
Tables 150 and 151 represent each sibling level as a doubly linked list and use
`First`, `Last`, `Parent`, `Prev`, `Next`, and signed `Count` facts to express
the hierarchy and its open state. Inserting invisible balancing nodes is not an
available transformation: every outline item has user-visible identity and
would change the authored outline.

`KernelOutline.Plan` therefore consumes a dense preorder entry list and
preserves its sibling order exactly. Each entry carries a title ID, optional
target value ID, depth, and open state. Sealing checks the entry limit before
allocation, enforces an explicit depth limit, rejects a nonzero first depth and
skipped parent depths, and validates title and target IDs against facts from the
earlier object-value stores.

The sealed plan is a flat item list with dense opaque IDs. One forward pass
assigns parent, previous/next sibling, and first/last child links. One reverse
pass accumulates the number of descendants that would be visible if each item
were open. Items with children receive a positive `OpenCount` or negative-on-
emission `ClosedCount`; leaves omit `Count`. The outline root records the total
currently visible entry count and exact top-level first and last items.

## Complexity and evidence

Planning is `O(entries)` time and uses one final item allocation plus an
`O(depth)` ancestor stack. It creates no list per parent, sibling level, or
outline item. No traversal infers relationships from object numbering; a later
object lowerer consumes the sealed link and count facts directly.

Focused tests cover mixed open and closed subtrees, exact root and item counts,
root/parent/child/sibling links, a targetless grouping item, and named failures
for empty input, entry and depth limits, first-depth and skipped-depth errors,
and unresolved title or target IDs.

The pinned optimized stress fixture seals 4,096 entries arranged as 128
top-level items with 31 children each. Alternating top-level open state produces
an exact root visible count of 2,112. The fixture independently walks all 128
parent and 3,968 leaf items, checks 3,967 previous and next links, and records a
16,773,120 title/target identity checksum. Construction records 4,096 entries
checked, 4,096 items appended, 15,999 in-place item rewrites, 4,096 count
accumulations, and maximum depth one.

The outline fixture adds exactly four Roc allocations to the unchanged
4,096-page path: the caller entry list, final item list, and the two-element
ancestor stack's growth. Its total is 113,797 allocations; there is no
allocation per item or relationship. It emits the same 1,084,927-byte PDF with
SHA-256
`bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756`.
CI applies the exact allocation count and work vector on arm64mac and x64musl.

This slice seals the outline hierarchy. Feature-specific outline object
lowering and public destination/action construction remain at their roadmap
gates.
