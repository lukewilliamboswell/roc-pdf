# contract-definition prepared-document boundary slice

## Scope

This define-only slice establishes the stable `Document.Prepared` integration
boundary, exact layout cache identities, bounded diagnostic batches, resource
use edges, per-phase work facts, and typed lifetime rules. It does not prepare,
validate, lower, seal, or emit a document.

## Representation and ownership

- Prepared semantics, placements, scene commands, text runs, fonts, images,
  profiles, and color spaces remain separate flat stores. Cross-store links are
  scalar IDs or exact ranges; the prepared record does not recursively embed
  payloads at use sites.
- Each resource use is one fixed-shape edge from a scene group to a font,
  image, color-space, or ICC identity. Repeated placement does not duplicate
  bytes, decoded planes, or semantic ownership.
- Every layout-affecting reference has an exact value and final state. The
  prepared type has no unresolved or approximate alternative.
- Custom layout functions, authoring blocks, speculative scenes, and caches do
  not cross their typed lifetime boundaries. Validated bytes needed by the
  encoder remain independently owned through emission.

## Cache, traversal, and complexity

Measurement keys contain exact constraints, source, style, and interned
resource state. Hyphenation keys additionally contain language, exact source
range, and pinned pattern identity. Font parse, instance, coverage, planning,
and shaping retain their existing exact typed keys.

Preparation uses direct indexed passes over normalized blocks, semantic nodes,
fragments, commands, and resource edges. Dense identity checks and prefix-sum
fragment indexing are linear. Any ordering that cannot use dense IDs consumes
the explicit comparison-work budget and requires deterministic worst-case
`O(n log n)` sorting. No hot byte, glyph, pixel, command, or edge pass relies on
`Iter` storage.

`PreparationWork` carries copied and retained payload bytes plus exact stage
dimensions. `Layout.Work` separates source, candidate, continuation, reference,
comparison, fragment, cache, and retained-cache work so favorable aggregate
timing cannot hide rescans or retention growth.

## Failure and diagnostics

Preparation returns `Try(Document.Prepared, Conformance.DiagnosticBatch)`.
Failure never exposes a partial prepared document. Diagnostics carry a stable
code, validation stage, compact location, internal requirement IDs, standards
clause references, and bounded details. The accumulator stops at its
deterministic count or detail-byte limit and marks the batch `Truncated`; it
does not continue scanning merely to count discarded findings.

## Evidence

`examples/advanced_prepared_contract.roc` compiles the stable boundary access,
exact measurement identity, resource-use edge, atomic error batch, clause and
stage facts, and lifetime policy. Runtime preparation, negative detection,
allocation, ARC, copied-byte, retained-byte, cache, and scaling evidence belongs
to the capabilities that implement those passes.
