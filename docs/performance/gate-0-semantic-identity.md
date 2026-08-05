# Gate 0 semantic identity and MathML type slice

## Scope

This define-only slice makes namespace mappings, emitted structure identity,
IDTree membership, cross-relations, structure-attribute applicability, author
assertions, and validated MathML roots explicit. It performs no normalization,
semantic validation, parsing, or PDF lowering.

## Representation and ownership

- Semantic nodes, emitted structure elements, IDTree strings, destinations,
  MathML subtrees, and author assertions have independent dense scalar IDs.
  None is a PDF object number.
- Element identifier strings live once in `element_identifiers`; nodes and
  relationships carry scalar `ElementId` values. Header, reference,
  destination, and annotation relations do not create extra structural parents.
- Role mappings retain both namespace IDs. Structure attributes retain their
  owner, typed standard or namespaced name, typed value, and either a role
  family or an exact range into the shared `attribute_roles` buffer.
- A MathML subtree points at an already normalized node range and root. Parsed
  input records only its source identity and bounded work counters; no raw,
  unchecked markup string is stored at the trusted boundary.
- Human semantic judgments remain explicit author-assertion records and never
  become inferred conformance facts.

## Complexity and lifetime

Identity, parent, and relationship checks are linear in dense nodes and edges
when implemented with dense state arrays. ID uniqueness and role lookup use
bounded maps keyed by compact identities; deterministic output orders by dense
identity rather than map iteration. Attribute applicability is `O(1)` for a
family or linear in the exact small role span unless a later gate records a
reviewed indexed representation.

MathML validation is linear in input UTF-8 bytes, nodes, attributes, and edges,
subject to the dimension-specific resource policy. Its exact byte, node, and
attribute counters distinguish scaling dimensions. Parser state and input
bytes are released after the normalized subtree and diagnostics are produced.

The stores contain no recursive node payloads, copied identifier strings,
stored iterators, closures, or duplicate MathML tree. Error lists remain bound
by `ResourcePolicy.max_diagnostics` and never carry a partially trusted graph.

## Gate evidence

`examples/advanced_semantics_contract.roc` compiles namespace-scoped role
mapping, exact attribute applicability, ID-based table headers, and a bounded
validated MathML parse boundary. Runtime validity and atomic negative behavior
belong to the gates implementing semantic normalization and MathML parsing.
