# text-layout caller-font shared-input retention

This focused dev-backend slice closes the remaining one-face caller-font
ownership comparison in the text-layout readiness audit. It measures two complete,
independently authored public `Pdf.to_bytes_with` outputs, rather than a
private registry probe. Both outputs pass the existing original-byte caller
facade structural checker: the expected Type 0 subset, CIDs, `ToUnicode` map,
three text placements, and absence of an external font reference are checked
for each returned snapshot.

The shared case registers the 7,816-byte caller font once. Two separately
constructed `Pdf.Options` values retain that same complete `Font.Registry` and
produce byte-identical 10,348-byte documents. Registration is the sole parse:
the work carrier reports one resource, face, static instance, policy, and one
set of 17 table, 15 glyph, nine cmap, and four composite-edge visits. It also
observes 7,816 retained source bytes after both subset emissions and zero
registry input-copy bytes. The registry therefore carries the validation facts
and original immutable input through each selected output; the facade does not
fall back to the packaged font or re-register it per document.

The deliberately unique control copies the caller bytes into a second caller
allocation before registration and uses two independent registries. It reports
two inputs/resources/faces/instances/policies, 15,632 retained source bytes,
two exact inspections, and 7,816 caller-side copy bytes. The package registry
still records zero input-copy bytes. This is intentionally not a content-based
cross-registry deduplication claim: a complete caller-owned input allocation is
one resource identity, while reusing one completed registry is the explicit
sharing mechanism.

| Case | Caller inputs | Registrations | Retained source bytes after outputs | Registry-copied bytes | Outputs | Exact dev allocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Shared registry | 1 | 1 | 7,816 | 0 | 2 | 3,111 |
| Unique registry control | 2 | 2 | 15,632 | 0 | 2 | 3,151 |

The 40-allocation difference is reviewed as the intentional second caller
allocation plus independent registry/inspection state. It is not a baseline
rewrite caused by a compiler or optimization change: the compiler, target,
measurement boundary, snapshots, and deterministic output work remain the
same. Each output remains exactly 10,348 bytes with SHA-256
`be3fe13375d32d3d9f2cc98eecafe879ef0e1197559ef52439ef16d85dd2257f`.

The existing restricted-rights atomic negative remains the rejection boundary
for both shapes: invalid caller bytes fail transactionally during registration,
before any registry can be shared or supplied to `Pdf.Options`; it emits zero
PDF bytes. This slice adds no new accepted font format, fallback, or
cross-registry cache.

This evidence covers the single-face public facade. The ordered multi-face
policy path became a public selection path with its own two-face
shared/unique retention modes and cache review, recorded in
[`multiface-public-facade.md`](multiface-public-facade.md) and
[`cache-closure.md`](cache-closure.md). Hyphenation is not
accepted at text-layout, so a hyphenation cache is inapplicable rather than
silently claimed here.
