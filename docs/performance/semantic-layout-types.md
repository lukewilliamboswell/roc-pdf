# contract-definition semantic, layout, and scene type slice

This record covers the define-only `Semantics`, `Layout`, and `Scene` public
type modules. It does not claim that normalization, layout, scene validation,
tagged-PDF lowering, or emission exists.

## Representation and ownership contract

- Nodes, occurrences, fragments, namespaces, annotations, pages, streams,
  scene groups, commands, and resources use distinct opaque dense IDs.
- Fixed-shape records live in flat lists. Variable content-spine items,
  attributes, text properties, scene commands, page paint order, and reverse
  fragment indexes use exact `(start, length)` spans into flat buffers.
- Source Unicode and non-text bytes are each owned once. Occurrences and
  fragments retain IDs plus exact UTF-8-byte and Unicode-scalar ranges.
- The occurrence-to-fragment reverse index contains fragment IDs built later
  by counts and prefix sums; it does not duplicate fragment records or source
  payloads.
- Scene commands form an arena. Nested graphics groups refer to child spans,
  avoiding allocation-per-command recursive values while retaining balanced
  structure. Each root group has exactly one typed fragment or page-artifact
  owner. Contextual Artifact elements remain a separate semantic type.
- Layout continuations contain component/source IDs, a scalar cursor, and
  caller-defined compact state. Handlers are passed separately and are not
  retained in document or continuation data.

## Complexity and traversal contract

- Normalization will append each node, spine item, occurrence, fragment,
  relationship, scene group, and command once: `O(n)` visits and storage.
- Reverse fragment indexing will use counts plus prefix sums: `O(o + f)` time
  and storage for `o` occurrences and `f` fragments.
- Hot traversal is by direct dense-buffer index. No `Iter` value is stored in
  any schema in this slice.
- Layout engines must report exact source/candidate/cache/materialization work;
  exhaustion is a typed error state and cannot accept an approximation.

## Allocation evidence boundary

The public contract fixture proves that mixed semantic order, page/stream
fragmentation, differing paint order, page artifacts, contextual artifacts,
custom continuation state, stable layout, cycles, and budget exhaustion are
representable using the exposed package modules. Executable allocation and
scaled-work baselines begin with the capabilities implementing these stores and
algorithms, as required for define-only contract-definition capabilities by the roadmap.
