# Gate 1 closure review

## Outcome

The PDF 2.0 structural-kernel gate is complete. The machine-readable
capability matrix records `Pdf20` as available, and the public facade emits a
deterministic blank, single-page PDF 2.0 document for the `Standard` profile.
Meaningful authoring content and the `Archive` and `AccessibleArchive`
profiles remain outside this gate and fail transactionally with typed errors.
This closure does not claim the visual, tagged-content, text, PDF/A-4, or
PDF/UA-2 behavior assigned to later gates.

## Capability and evidence aggregation

| Gate 1 boundary | Implementation and focused evidence |
| --- | --- |
| Canonical lexical forms and flat object/value/edge storage | `KernelLex`, `KernelObject`, `gate-1-lexical-kernel.md`, `gate-1-object-store.md` |
| Sealing, stable allocation, stream lengths, and checked bounds | `KernelSeal`, `gate-1-sealed-plan.md`, `gate-1-output-bounds.md` |
| Catalog, page trees, pages, resources, streams, and trailer | `KernelStructure`, `gate-1-structure-lowering.md`, `gate-1-balanced-shape.md` |
| Xref stream, identifiers, `startxref`, and EOF | `KernelEmit`, `gate-1-identifiers.md`, `gate-1-structural-emission.md` |
| Stateful bounded DEFLATE | `KernelDeflate`, `gate-1-deflate.md`; independent `roc-deflate` and zlib decoding |
| Stable resource names | `KernelResource`, `gate-1-resource-names.md` |
| Page, name, number, ID, and ParentTree builders | `KernelTree`, `gate-1-balanced-indexes.md` |
| Linked outline hierarchy | `KernelOutline`, `gate-1-outline-hierarchy.md` |
| Buffered/chunked identity and retention policies | `KernelEmit`, `gate-1-resource-retention.md` |
| Atomic failures and supported-system determinism | `gate-1-negative-determinism.md` |
| Independent structural validation | byte-level checker, qpdf, Arlington, and strict PDFBox evidence recorded in `gate-1-arlington.md` and `gate-1-pdfbox.md` |

Blank, one-page, multi-page, large balanced-tree, 4,096-entry resource-name,
4,096-entry outline, large lexical, retained-resource, dynamic-compression,
and greater-than-4-GiB counting-sink fixtures cover the roadmap's scale and
failure boundaries. The optimized scenario manifest fixes exact allocation
counts and deterministic work counters for the pinned compiler and each CI
target. The full driver rejects snapshot, allocation, work, parser, and
conformance drift.

## Ownership and performance closure

Construction uses dense scalar-indexed stores and direct loops. Sealing
produces a compact replayable plan with checked output and compression bounds.
Emission walks that plan once, batches xref entries, and supports either
consume-and-release seamless resource slices or bounded owned chunks. Text and
byte payloads are stored once rather than re-encoded per lexical emission.
Scaled fixtures distinguish fixed allocations from per-item work, while
one-shot/shared inputs, immediate/retained output, bounded errors, and source
release cover the ownership cases required by the roadmap.

The package-owned compressor is deliberately replaceable. A future
`roc-deflate` adoption must preserve the current byte identity, bounds,
ownership, deterministic work, exact allocation, and retention contracts; its
present use as an independent decoder oracle is not a production dependency.

## Public-boundary audit

`package/main.roc` continues to expose only the high-level facade and the
advanced conceptual modules established by the architecture. Object IDs,
stores, tree builders, resource-name plans, lowering, sealing, compression,
and emission state remain package-private. The common `Pdf` path exposes no
PDF object internals.

## Next gate

Gate 2 may add the minimal tagged visual kernel. Until a later slice closes its
own capability and evidence boundary, the facade must keep rejecting meaningful
authoring content and unavailable profiles rather than dropping content,
substituting a blank document, or downgrading conformance.
