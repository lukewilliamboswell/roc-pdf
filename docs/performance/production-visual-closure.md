# Gate 4 production-visual closure

## Decision

Gate 4 is closed for the `Pdf20`/`Standard` compiler boundary. Every capability
listed by the Gate 4 roadmap has executable positive evidence, atomic negative
evidence, deterministic serialization, structural inspection, applicable
renderer coverage, and focused allocation/work records under the pinned dev
backend.

This decision does not claim PDF/A-4 or PDF/UA-2. It also does not promote
semantic figure authoring (Gate 6) or custom layout builders (Gate 8). Those
boundaries depend on facts Gate 4 must not infer from painted pixels.

## Aggregated evidence

| Capability | Primary evidence |
| --- | --- |
| resource graph, exact identity, names, and retention | `resource-graph.md`, `resource-names.md`, `resource-retention.md` |
| Form XObjects and nested resource closure | `form-xobjects.md` |
| ICC/sRGB, JPEG, packed raster, alpha, and deterministic compression | `color-image-leaves.md`, `deflate.md` |
| constant opacity, isolated groups, and soft masks | `transparency.md`, `soft-masks.md` |
| axial/radial shadings and tiling patterns | `shadings-patterns.md` |
| canonical sanitized font leaves | `font-leaves.md` |
| XMP, language, packaged output intent | `metadata-output-intent.md` |
| URI/internal links, paired destinations, outlines, labels, appearances | `navigation-annotations.md` |

The last slice reports that all 200 earlier snapshots stayed byte-identical
while its reviewed allocation changes came from dense ownership maps,
conditional page dictionaries, and navigation-aware facade stages. No
deterministic work counter changed. The complete suite remains the authority
for exact per-case counts; this document does not duplicate mutable baseline
numbers.

## Public-boundary audit

- `Pdf` remains the primary authoring experience and emits only `Standard`.
- `Pdf.Prepared` is opaque. Preparation validates and seals once; buffered and
  chunked emission consume the same plan.
- Theme text colors accept typed 16-bit sRGB and resolve through the packaged
  profile/output intent. Unknown or device color has no representation.
- The facade performs one dense style scan to select calibrated-gray-compatible
  legacy output or the sRGB painting space, followed by the existing direct
  scene-materialization pass: `2r` color checks, `O(r)` time, and no new list or
  per-run allocation for `r` final runs. Default black documents retain their
  prior calibrated-gray bytes.
- PDF object modules and `Kernel*` types are absent from generated public docs.
- Image resources are implemented compiler inputs, but a painted image is not
  mislabeled as a semantic figure. JPEG/packed-raster facade constructors wait
  for the Gate 6 semantic contract; PNG is outside the accepted source policy.
- Unicode analysis uses `roc-lang/unicode` package release 4.0.0, which supplies
  the pinned Unicode 17 data/API boundary.

## Verification contract

`./scripts/test.py --allocation-baselines` is the Gate 4 closure command on the
pinned Linux target. `./scripts/docs.sh` additionally generates every exposed
module and fails if a private `Kernel*` name reaches the published API. The
nine gallery programs compile against basic-cli 0.22.0 and generate their
checked-in PDF outputs from the public package root.

The 2026-08-19 local rc2 pass completed repository contracts, generated-doc
auditing, 397 package tests through the public facade, 66 builder tests, and
byte-identical regeneration of all nine gallery PDFs. The exact-allocation
harness correctly refused to run because the local compiler was
`release-fast-d71437c6`, not the pinned
`nightly-2026-08-18-e9be50a`; CI with the pinned nightly remains required before
publishing rc2. No allocation baseline was changed under the wrong compiler.
