# Gate 1 flat object-store slice

## Scope and status

`KernelObject` is a private package module for constructing the PDF object
graph. It implements dense IDs, flat value and edge stores, preassigned stream
length-object references, explicit payload ownership kinds, checked dimensions,
direct-depth limits, canonical dictionary-key validation, and exact work
counters. The ledger remains `partial` until sealing validates all forward
references and the optimized emitter consumes the compact plan.

The module is imported privately by `Pdf` so its tests are in the package test
closure. It is intentionally absent from `package/main.roc`; object numbers,
spans, streams, and lexical storage are not public facade types.

## Representation and ownership

- Values, depths, array edges, dictionary edges, objects, streams, names, byte
  strings, text strings, and payloads each have one consumption-shaped store.
- Opaque `U64` IDs prevent accidental interchange between values, names,
  strings, payloads, streams, and indirect objects without tagged runtime
  wrappers. Object number zero is uninhabitable.
- Arrays and dictionaries are spans into flat edge buffers. Values therefore do
  not form recursive Roc lists or retain parent containers through child nodes.
- A stream retains a payload ID and a separately preassigned indirect length
  object ID. It never embeds or duplicates payload bytes.
- Generated and unchanged-resource payloads retain their input byte list once.
  The later chunk-retention policy will decide whether unchanged caller slices
  may be shared or must be copied into owned chunks.

The builder is consumed and returned by every successful operation so unique
list buffers can grow in place under optimized ARC. A failed operation returns
no modified builder and performs every bounds, index, key-order, and work check
before appending to a store.

## Traversal and complexity

All edge validation and appending uses indexed `while` loops. There is no
`Iter`, recursive object walk, map iteration, per-edge closure, or temporary
token list.

- Scalar insertion, indirect-object insertion, and interned-value insertion are
  constant work apart from amortized list growth.
- Array insertion is linear in its edge count and appends each edge once.
- Dictionary and stream insertion are linear in entries plus adjacent key-byte
  comparisons. Requiring already-sorted keys avoids an internal sort and makes
  order deterministic. Long common prefixes can be revisited between adjacent
  keys; the exact comparison count is recorded and all counter additions are
  overflow checked.
- Name and text validation is linear in input bytes. Byte strings and payloads
  are retained without a validation copy.
- Direct-container depth is stored beside each value, so a parent computes its
  depth during the same edge-validation pass instead of recursively walking the
  completed graph.

Count, cumulative-byte, direct-depth, index, and work arithmetic is checked
before mutation. Errors report the exact dimension, attempted value, limit, or
store kind.

## Evidence still required

Gate 1 now has sealing-time reference validation, compact emission-plan
measurements, exact optimized allocation scenarios, and thousands-of-pages
stress plus greater-than-4-GiB counting-sink coverage. Completion still
requires shared-versus-owned backing-storage retention evidence. Allocation or
work baseline changes will be reviewed as representation changes, not
mechanically accepted.
