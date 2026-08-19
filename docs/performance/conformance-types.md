# contract-definition conformance-type slice

This record covers the define-only `Conformance` public type module. It does
not claim that profile validation or PDF emission exists.

## Input and complexity contract

- Profile-to-claim mapping is constant time and visits no input collection.
- Diagnostics are stored in one flat list. Each diagnostic retains compact
  scalar locations, validation stage, requirement IDs, standards clause
  references, and bounded detail strings rather than a document or resource
  payload.
- `ResourcePolicy` contains an explicit limit for every currently planned
  attacker-controlled dimension. Zero rejects that dimension and is never an
  unlimited sentinel.

## Ownership and allocation contract

- Claim sets and policies are fixed-shape records with no hidden collection.
- A diagnostic owns only its bounded text lists. Later validation stages
  consume one diagnostic accumulator, stop at the policy count or byte bound,
  and mark truncation without scanning merely to count discarded findings.
- The mapping function allocates no per-capability list and performs no `Iter`
  traversal.

Executable allocation and scaling evidence begins with the capability that performs
validation. This contract-definition slice is checked through type checking and unit tests,
as required for define-only capabilities by the roadmap.
