# Gate 4 color and image leaves

This records the design, ownership model, complexity, and evidence for the
third Gate 4 slice: the production color and image resource pipeline —
ICCBased sRGB through the pinned packaged profile, calibrated grayscale,
canonical (deduplicated) ICC/color-space/image leaf emission, alpha soft
masks, and complete direct resource dictionaries — built on the resource
graph in [gate-4-resource-graph.md](gate-4-resource-graph.md) and the form
machinery in [gate-4-form-xobjects.md](gate-4-form-xobjects.md). It does not
close Gate 4.

## Modules

- `vendor/icc/sRGB2014.icc` — the ICC's official sRGB v2 profile, pinned with
  digest, license, and retrieval chain (`vendor/icc/NOTICE.md`,
  `vendor/icc/LICENSE.txt`, `assets/provenance.json`) before it became a
  dependency, as the roadmap requires.
- `scripts/build_srgb_profile.py` → `package/KernelSrgbProfile.roc` — the
  packaged profile as compiled pure Roc package data: bytes, tag directory,
  and pinned digest, with generated expects that verify the digest and pass
  the profile through the real `KernelColor` inspection boundary.
- `KernelForm.roc` — leaf normalization joins form normalization: node space
  gains ICC-profile nodes, color spaces name their profiles as direct edges,
  leaf identity is *derived from the validated stores* (no caller-supplied
  leaf payloads except fonts), and canonical per-kind ordinals with
  authored-to-canonical name maps replace the former 1:1 stopgap.
- `KernelContent.roc` — content naming through the canonical maps: `/CS` and
  `/Im` operands name the canonical ordinal an authored resource deduplicated
  to (the Gate 2/3 paths keep authored naming unchanged).
- `KernelGate2Objects.roc` — `Plan.build_canonical`: object identities planned
  for canonical leaf counts while authored stores are still cross-checked.
- `KernelGate2ResourceObjects.roc` — `Plan.build_canonical`: one object per
  canonical profile/space/image, lowered from its representative's validated
  store record; raster emission consumes the canonical row-compacted planes
  as immutable ranges of the identity allocation, so no second full-size
  compaction copy exists at emission.
- `KernelGate4FormStructure.roc` — assembles the canonical leaf objects and
  dictionaries into the sealed plan.
- `KernelResourceGraph.roc` — gains `payload_slice`, the accessor canonical
  image planes are shared through.
- `Gate4ColorImageEvidence.roc` — scenario evidence.
- `scripts/check_gate4_color_images.py` — the independent structural checker.
- `scripts/check_gate4_color_image_renderers.py` — pinned PDFium/PDFBox/MuPDF
  rendering evidence.

## The packaged sRGB profile

The pinned asset is `sRGB2014.icc`, the ICC's official v2 sRGB profile
(3,024 bytes, embedded copyright "Copyright International Color Consortium,
2015", license permitting copying, distribution, and embedding without
restriction). The v2 profile is deliberate over the v4 preference profile:
output intents and ICCBased spaces want colorimetric sRGB rather than
perceptual preference re-rendering, the embedded stream is a twentieth of the
size, and ISO 32000-2 accepts ICC v2–v4 while excluding iccMAX, so no newer
family displaces the pin. Provenance, digests, the ISO 15076-1 profile-ID
MD5 self-check, and the retrieval chain are recorded in
`vendor/icc/NOTICE.md`; the packaged byte module re-verifies the digest under
`roc test`, and the emitted profile stream is byte-compared against the
vendored asset by the structural checker.

## Leaf identity

Every leaf's identity is derived once from its validated store record and
digested with the existing versioned domain-separated procedure; digests are
Merkle over the dependency DAG, computed in one topological sweep
(profiles before the spaces that embed their digests, spaces before images,
every leaf before form recipes):

- **ICC profile** — its exact sanitized bytes under an `IccProfile`
  descriptor carrying component count and ICC version.
- **Color space** — a typed recipe: calibrated gray serializes its exact
  white/black points; `Srgb` and `IccBased` serialize a tag plus the
  referenced profile's identity digest, so the two equivalent declarations
  share one identity by construction.
- **Image** — its color-space digest plus its canonical payload: the
  row-compacted planes (color then alpha) for a raster, or the sanitized DCT
  bytes for a JPEG, under a descriptor carrying dimensions, components, bit
  depth, and the alpha flag. Row padding never reaches identity or emission,
  so a padded raster and its compact twin deduplicate; equal pixels under
  different color spaces never merge because the embedded space digest
  differs; a raster and a JPEG never merge because descriptor subtype
  partitioning separates them before any byte comparison.
- **Font** — still the caller-supplied payload, 1:1 with the authored store;
  byte-identical authored font leaves remain the explicit
  `DuplicateLeafPayload` rejection until the font slice derives canonical
  font identity.

The digest remains a candidate only: the canonical graph run's descriptor
partitioning and exact byte equality confirm every merge, and the identity
arena (`retained_payload_bytes`) is the single allocation those comparisons
and the emitted raster planes share.

## Canonical emission

- Canonical ordinals per kind are assigned in canonical-ID order — the same
  documented content-derived total order forms already use — and every
  authored resource maps to its canonical ordinal (`color_names`,
  `image_names`, `profile_names`, mirroring `form_names`).
- Object planning (`build_canonical`) allocates exactly one object per
  canonical profile (stream plus indirect length), one per canonical color
  space, and one stream pair per canonical image plus a soft-mask pair when
  the canonical image carries alpha.
- Emission lowers each canonical leaf from its lowest authored
  representative: the ICC stream is the unchanged profile allocation
  (`UnchangedResource`, eligible for seamless-slice sharing in chunked
  output), the `[/ICCBased n R]` array resolves through the canonical
  profile map, raster planes deflate from the canonical arena ranges
  (`Generated`), and the DCT stream embeds the sanitized JPEG bytes
  unchanged. Alpha planes emit as `/DeviceGray` soft masks referenced by
  `/SMask`.
- Dictionaries stay exact direct uses per stream, now over canonical
  ordinals: pages consume their root dictionaries, forms their direct
  dependencies. Profiles never appear in any resource dictionary — they are
  reachable only through color-space arrays — and the dictionary partition
  carries an always-empty profile bucket so that fact is structural.
- JPEG orientation policy is unchanged and tested at this boundary: a
  conflicting EXIF orientation is the stable `OrientationRequiresTransform`
  rejection, and sanitized streams carry no application or comment metadata.

## Rebaseline of the form fixtures

Deriving leaf identity from the stores changed the identity preimages the
form slice had provisionally supplied by hand: the calibrated-gray leaf grew
from a 16-byte stopgap payload to its 49-byte typed recipe, and the image
leaf gained its 32-byte embedded space digest. Form recipes embed those
digests, so canonical form IDs (and with them `/XO` ordinal assignment)
permuted in the multi-form fixtures. The gate4 form snapshots and their
allocation/work baselines were regenerated under review: geometry, visuals,
structure, ownership, and every renderer expectation are unchanged (the full
pinned renderer matrix passes on the regenerated bytes), `bytes_hashed`
moved by exactly the +65 preimage bytes in the showcase, and allocations
moved only by the store-derivation path. This is the reviewed architectural
cause the baseline protocol requires, not a mechanical acceptance.

## Complexity, ownership, and retention contracts

- Store validation, leaf derivation, compaction, digesting, dictionary
  construction, and emission are linear in profiles, spaces, images, payload
  bytes, and edges; the two graph runs keep their documented
  `O((V+E) log V)` and `O(n log n)` factors; digest-collision buckets keep
  the bounded partition-plus-equality work (`collision_entries`,
  `bytes_compared` are recorded and scale linearly in the dedup fixtures).
- The identity arena is the one canonical payload allocation: profile bytes,
  leaf recipes, compacted planes, and form recipes are copied into it exactly
  once (`copied_leaf_bytes`, `leaf_recipe_bytes`), it is retained through
  emission (`retained_payload_bytes`), and raster deflate input is shared
  from it as immutable ranges — never copied again, and never exposed as an
  output chunk (Generated payloads are compressed into fresh bounded
  buffers). ICC and JPEG emission use the validated stores' own allocations,
  so an `UnchangedResource` chunk can never pin the internal arena.
- Row/chunk processing: compaction copies row by row; validation, hashing,
  equality, and deflate all consume ranges of existing allocations; at no
  point do two full-size intermediate copies of one plane coexist beyond the
  source store and the canonical arena.
- No allocation or ARC work per compared byte, hashed byte, compacted byte,
  or emitted byte in the inner loops; allocation counts scale with resources
  and placements and are recorded per scenario in `tests/spec.json`.

## Explicitly deferred

- Output intents, which join the XMP/PDF-A slices along with 6.7.2.1
  metadata. (The transparency page `/Group` this slice originally deferred
  under veraPDF's 6.2.9 rule landed with the transparency slice,
  [gate-4-transparency.md](gate-4-transparency.md), which regenerated this
  slice's showcase snapshots with the required group dictionary.)
- Canonical font leaf identity and font-leaf deduplication.
- CMYK, Separation/DeviceN/spot color, overprint, luminosity masks,
  non-Normal blending, shadings, and patterns (later Gate 4 slices or
  explicitly separate capabilities).
- Encoded-PNG passthrough (PNG remains an input transport decoded by a
  separate package; nothing here accepts a PNG container).

## Structurally unrepresentable failure classes

- *A dictionary disagreeing with use, or a merged placement fact*: unchanged
  from the form slice — dictionaries derive from the same normalized facts as
  the graph edges, and ownership stays placement-site.
- *An emitted twin object for merged leaves*: object identities are planned
  from canonical counts and emission iterates canonical representatives, so
  an authored twin cannot reach the object plan; the checker still counts
  and byte-compares every emitted leaf.
- *An ICC stream diverging from the pinned asset*: the packaged module is
  generated from the vendored bytes, verified by digest expects, validated by
  `KernelColor`, embedded unchanged, and byte-compared by the checker against
  the vendored file.

## Evidence

Roc `expect` coverage lives beside each module and in the evidence module.
Harness cases (`tests/spec.json`, scenario revision
`gate4-color-image-leaves-v1`, measured on the pinned dev backend at
`before_fixture_main`; `arm64mac` recorded equal to the measured `x64musl`
values, matching the suite convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 3573 | profiles 2 → 1, spaces 4 → 2, images 5 → 3, ICC 6048 bytes/32 tags checked, one 3024-byte profile stream emitted |
| unique input | 1788 | one pipeline run, identical counters and bytes |
| retained input | 3559 | two pipeline runs over one retained input, identical bytes |
| dedup x8 | 1124 | 8 authored → 1 canonical image, 1 emitted image object |
| dedup x64 | 2631 | 64 authored → 1 canonical image, output 2221 bytes |
| distinct x8 | 1622 | 8 canonical images, 8 emitted objects |
| distinct x64 | 7119 | 64 canonical images, output 19356 bytes |
| atomic negatives | 1164 | 24 distinct rejections, 0 escaped plans |

What the scaling shows: dedup isolates identity work (hashes, hashed bytes,
collision entries, equality comparisons, and compared bytes scale linearly
8 → 64 while canonical images, emitted objects, dictionaries, and object
counts stay fixed — the emitted file grows only by placement operators);
distinct isolates per-canonical-leaf cost (emitted images, raster bytes,
dictionary entries, references, and objects scale exactly 8x while equality
work stays zero because every digest is unique). The showcase proves
cross-declaration dedup (`Srgb` with `IccBased`, compact with padded, twin
profiles, twin gray-alpha images) with placements keeping distinct MCID
ownership, and its reversed authored-ID twin is byte-compared inside the
scenario. `unique` versus `shared` is the retained-input ARC cost with
byte-identical output.

The 24 atomic negatives cover the invalid-ICC classes (truncation, declared
size, signature, version, device-space/component mismatch, tag-record
mismatch, orphan tag, byte budget), invalid space declarations (component
mismatch, missing profile, uncharacterized calibrated point), invalid JPEG
streams (forbidden marker, escaping segment, unsupported component count,
conflicting EXIF orientation, gray/color mismatch), invalid rasters (format
mismatch, stride, plane length, alpha length, zero dimensions, decode
budget), and the graph boundary (an unreferenced profile is unreachable; the
canonical payload budget rejects transactionally). Every rejection is a
distinct structured diagnostic with no emitted bytes.

Every fixture regenerates byte-for-byte across repeated runs. `qpdf --check`
(12.3.2) passes every snapshot with no warnings.

Independent structural checking is `scripts/check_gate4_color_images.py`: it
byte-compares the emitted ICC stream against `vendor/icc/sRGB2014.icc`,
requires exactly one object per canonical leaf, decodes every Flate plane and
compares exact pixels, byte-compares the DCT stream against the sanitized
JPEG, verifies `/SMask` and `[/ICCBased …]` wiring, and re-proves the
used-equals-declared dictionary rule and placement-site MCID/ParentTree
ownership through the form checker's facts.

Pinned rendering is `scripts/check_gate4_color_image_renderers.py`. The
showcase, dedup, and distinct rasters are constructed independently from the
typed scenarios and match PDFium Chromium 7988 and PDFBox 3.0.8 with zero
pixel and zero channel tolerance, including the ICCBased sRGB raster and
fill, the flat DCT block (a DC-only baseline JPEG every conforming decoder
reproduces exactly), and the alpha soft-mask knockout of the gray raster's
transparent row. Color management is pinned per renderer, still at zero
tolerance: PDFBox displays the embedded sRGB2014 profile as identity; PDFium
maps pure green to (1, 255, 0) and the (64, 64, 192) fill to (63, 63, 192)
under its ICC pipeline; MuPDF 1.28.2 (via `--mutool`) shares the fill
mapping, keeps the primaries identical, renders calibrated gray through its
pinned sRGB tone tables from the form slice, and skips only the
distinct-grid lane because arbitrary calibrated values carry no pinned tone
triples.

veraPDF remains deliberately outside this slice's evidence lane: the slice
claims `Pdf20`/`Standard` only. A one-off `--flavour 4` smoke run over the
showcase parsed completely and reported exactly the two deferred-capability
rules: 6.7.2.1-1 (the missing XMP metadata stream) and 6.2.9-2 (a page
containing transparency — the alpha soft mask — without a PDF/A output
intent or page `/Group`). Both are precisely the capabilities named above as
deferred to the XMP/output-intent slices; the run is recorded as tool
validation, not a conformance claim.
