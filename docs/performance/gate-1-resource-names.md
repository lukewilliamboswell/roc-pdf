# Gate 1 stable resource names

## Sealed representation

`KernelResource.Plan` assigns private PDF resource names during planning, not
during public document construction. Inputs are dense resource identities in
the canonical kind order fixed at Gate 0: color space, font, ICC profile,
image, pattern, shading, then other XObject. The planner does not sort or use a
map. It rejects a kind reversal, duplicate or skipped identity, a nonzero first
identity for any kind, and entry or aggregate-name limits before a plan can
escape.

Names are package-versioned ASCII prefixes followed by the one-based canonical
unsigned identity: `CS`, `F`, `ICC`, `Im`, `P`, `Sh`, and `XO`. Prefixes remain
distinct even where multiple implementation kinds will later occupy one PDF
resource subdictionary. Feature lowerers consume the sealed name attached to
the earlier typed resource identity; they do not reconstruct a name from
object order or a hash traversal.

The plan retains the caller's single dense entry list, one exact-capacity byte
arena, and one dense span list. Each name is a seamless view into that arena,
so it adds no backing allocation per resource. Planning first validates and
computes the exact checked byte total, then fills the two unique output buffers
in one direct indexed pass. Lookup is constant time; validation and emission
are linear in entries plus decimal digits.

## Executable evidence

Focused Roc tests cover every kind prefix, the `F9` to `F10` decimal-width
transition, empty resources, kind reversal, duplicate/skipped/nonzero-first
identities, and exact entry and aggregate-byte limit failures.

The pinned optimized stress fixture seals 4,096 font identities into exactly
19,373 name bytes. It records 4,096 entry and identity checks, 4,095 adjacent
kind comparisons, 19,373 audited byte visits, and checksum 2,307,784,361. The
fixture adds four allocations to the unchanged 4,096-page scenario: the caller
entry list, the name-byte arena, the span list, and the outer evidence work
vector. There is no allocation per name or byte.

The resource-name fixture still emits the independently checked 1,084,927-byte
PDF with SHA-256
`bef875d56c7b93c4120aaea9e9f19bc90b3f4857e507a8bdb6aff6a8e07e5756`.
CI applies the same exact allocation count and work vector on arm64mac and
x64musl.
