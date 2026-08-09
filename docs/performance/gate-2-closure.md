# Gate 2 closure review

## Outcome

The minimal tagged visual kernel gate is complete. This is a private compiler-
pipeline capability boundary: it does not make the future Gate 3 authoring
facade or the `PdfUa2`, `StaticPdfA4`, or archival profiles available. Public
unsupported content and profiles continue to fail transactionally rather than
being dropped, substituted, or downgraded.

## Capability and evidence aggregation

| Gate 2 boundary | Implementation and focused evidence |
| --- | --- |
| Checked page boxes, rotation, fixed-point coordinates, transforms, paths, clipping, paint state, and bounded graphics nesting | `KernelGeometry`, `KernelScene`, `gate-2-geometry.md` |
| PDF 2.0 `Document`/`P` semantics, namespace, contextual Artifact, occurrence reverse index, paint ownership, MCIDs, ParentTree, and mixed `/K` | `KernelSemantics`, `KernelTagged`, `KernelGate2TaggedObjects`, `gate-2-semantics.md`, `gate-2-tagged-plan.md` |
| Typed gray/RGB color, bounded raster/JPEG inspection and sanitization, alpha, and resource reuse | `KernelColor`, `KernelImage`, `KernelResourceUse`, `KernelGate2ResourceObjects`, `gate-2-resources.md` |
| Canonical content, stable resource names, sealed object identities, checked emission bound, file identity, and deterministic PDF bytes | `KernelContent`, `KernelGate2ResourceName`, `KernelGate2Objects`, `KernelGate2OutputBound`, `KernelGate2Structure`, `gate-2-content.md`, `gate-2-objects.md` |
| Exact normalized emitted structure and independent negative twins | `scripts/check_gate2.py`, `gate-2-negative.md` |
| Independent appearance and hand-constructed pixel oracle | PDFium Chromium 7988, PDFBox 3.0.8, `scripts/check_gate2_renderers.py`, `gate-2-renderers.md` |
| Optimized ownership, allocation, work, and scale evidence | contextual minimal fixture and million-command image-reuse fixture in `tests/spec.json` |

The retained contextual fixture is 2,059 bytes with SHA-256
`4ff0fbba665a479924b9e35d1e7f131ae594b699fafd8a273de9ace0ee687840`.
It records 662 Roc allocations. The 28-allocation increase over the earlier
minimal fixture is the reviewed fixed cost of one contextual Artifact object
and its mixed `/K` relationship; it is not proportional to paint commands or
resource payload size.

The million-command fixture now records 131 allocations. The compiler-caused
shift from its original 129 count to 136 is reviewed in
`roc-nightly-2026-August-05-24f0b47.md`; the later five-allocation decrease is
the reviewed result of keeping semantic ownership-marker buffers unique across
their direct update loops. It visits exactly one
million scene, content, and resource commands, records 999,999 reuses of one
one-byte image payload, reaches graphics depth one, and produces 29,000,023
content bytes without copying the image payload per placement. The fixture is
iterative and does not consume the host stack per command.

## Stage and public-boundary audit

Every later stage consumes facts from its opaque predecessor: content lowering
does not infer semantic ownership; ParentTree lowering does not infer paint
order; resource lowering consumes normalized use counts; object assignment
precedes every forward reference; and output bounds are calculated from the
sealed graph. The common `Pdf` path exposes none of these object identities,
stores, or lowering plans.

The package remains pure Roc, generation-only, and free of external Roc
package dependencies. PDFium, PDFBox, qpdf, Arlington, and zlib are test-only
oracles. Gate 3 may now build searchable international text and the useful
public authoring facade on this closed boundary.
