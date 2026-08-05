# Gate 0 closure review

## Outcome

The standards, representation, and test-contract gate is complete as a
define-only boundary. This does not claim PDF generation, runtime validation,
resource parsing, shaping, layout, conformance, lowering, or emission behavior.
Those claims remain gated by the later roadmap evidence.

## Capability and evidence aggregation

| Boundary | Typed or machine-checked evidence | Performance review |
| --- | --- | --- |
| Standards, claims, ledger, and assets | `conformance/`, `assets/provenance.json`, `scripts/check_contracts.py` | `gate-0-conformance-ledger.md`, `gate-0-asset-provenance.md` |
| Facade, author facts, theme, and compact builder | `package/Pdf.roc`, `package/Document.roc`, `package/Theme.roc`, public examples | `gate-0-facade-builder-types.md` |
| Semantics, layout, ownership, and scenes | `package/Semantics.roc`, `package/Layout.roc`, `package/Scene.roc`, contract examples | `gate-0-semantic-layout-types.md`, `gate-0-semantic-identity.md` |
| Text and exact font planning | `package/Text.roc`, `package/Font.roc`, `examples/advanced_text_contract.roc` | `gate-0-text-font-types.md` |
| Color, ICC, raster, and JPEG resources | `package/Color.roc`, `package/Image.roc`, `examples/advanced_resource_contract.roc` | `gate-0-resource-types.md` |
| Metadata and deterministic emission policy | `package/Metadata.roc`, `package/Encode.roc`, `examples/advanced_encode_contract.roc` | `gate-0-canonical-policy.md` |
| Stable prepared integration boundary | `Document.Prepared`, exact cache keys, bounded diagnostics, resource-use edges, and the prepared example | `gate-0-prepared-document.md` |
| Optimized scenario protocol | `tests/spec.json`, `scripts/test.py`, versioned host ABI, snapshot and allocation self-tests | `gate-0-scenario-protocol.md` |

The optimized CI matrix runs the same driver on native macOS AArch64 and Linux
x86-64. Both targets reproduce the 431-byte placeholder digest, one Roc
allocation, and exact work values of 431 byte visits for one pass and 1,724 for
four passes. The compiler release is named only by `.roc-version`; the harness
derives and checks `roc version` from that file.

## Public-boundary audit

`package/main.roc` exposes only the conceptual modules listed by the
architecture: the primary `Pdf` facade and advanced document, semantics,
layout, scene, text, font, image, color, metadata, encoder-policy, conformance,
and theme boundaries. Associated contracts such as `Document.Prepared` remain
nested under those modules.

The future PDF value store, object IDs, tree builders, lowering stages, sealed
plan implementation, lexical writer, compressor state, and byte-emission
machinery are private. Gate 1 must not add them to `package/main.roc`.

## Next gate

Gate 1 may begin with the private flat object/value/edge stores and checked
canonical lexical kernel. The facade must continue returning
`CapabilityUnavailable` until every Gate 1 capability and evidence item is
satisfied; a partial structural kernel is not a public generation claim.
