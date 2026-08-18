# Gate 4 canonical font leaves

This records the design, semantics, ownership model, complexity, and evidence
for the seventh Gate 4 slice: canonical resource identity for sanitized
embedded font subsets and deduplicated font-leaf emission — the Gate 3 Type 0
font pipeline integrated end to end with the Gate 4 direct-edge resource
graph, canonical planning, exact direct dictionaries, object lowering,
sealing, serialization, and the evidence harness. It is built on the resource
graph ([gate-4-resource-graph.md](gate-4-resource-graph.md)), the Form
XObject machinery ([gate-4-form-xobjects.md](gate-4-form-xobjects.md)), the
canonical leaves ([gate-4-color-image-leaves.md](gate-4-color-image-leaves.md)),
and the Gate 3 font slices
([gate-3-font-planning.md](gate-3-font-planning.md),
[gate-3-font-subsetting.md](gate-3-font-subsetting.md),
[gate-3-pdf-font-objects.md](gate-3-pdf-font-objects.md)). It does not close
Gate 4 and claims no PDF/A-4 or PDF/UA-2 conformance.

## Scope and non-goals

Implemented:

- Canonical font-leaf identity derived once from validated earlier-stage
  facts (inspection, glyph-closure plan, sanitized subset, descriptor
  policy, and collected Unicode mappings) — never from caller payload
  bytes, authored dense IDs, emitted names, object numbers, or serialized
  content.
- Exactly one physical nine-object Type 0 bundle emitted per canonical
  font leaf; authored twins collapse; distinct recipes never merge.
- Content font selection (`Tf`) lowered through the canonical
  authored-to-canonical name map, exactly like `/CS`, `/Im`, `/GS`, `/Sh`,
  and `/Pt`, so form recipes and emitted bytes are independent of authored
  font numbering.
- Exact per-stream direct `/Font` dictionaries over canonical `F<n>`
  ordinals.

Explicitly not in this slice (unchanged rejections or later slices):

- No new font technology: TrueType-flavoured OpenType only; CFF/CFF2,
  variable instances, and color fonts stay rejected at inspection.
- No vertical writing mode, no encoding other than Identity-H, no
  additional text rendering modes.
- No shaping, coverage, or Unicode capability change; Gate 3 boundaries are
  consumed, not extended.
- No opportunistic subset unioning: different glyph closures from one face
  remain distinct canonical leaves (their sanitized programs, widths, CID
  maps, and mappings differ; a shared larger subset would change emitted
  bytes and retention).
- Pattern cells continue to reject semantic text; nothing here broadens the
  pattern-cell capability.
- XMP, output intents, links, outlines, labels, and annotation appearances
  remain the following slices. No PDF/A-4 or PDF/UA-2 claim is made.

## The canonical unit

The canonical unit is the complete **font bundle**: the nine consecutive
objects the Gate 3 lowering emits per font (FontFile2 stream and its length,
CIDToGIDMap stream and its length, ToUnicode stream and its length, font
descriptor, CIDFontType2 descendant, Type 0 parent). The bundle is one
inseparable graph leaf:

- The subset program, CID map, widths, descriptor, and ToUnicode stream are
  all derived from one validated `(inspection, plan, subset, mappings,
  descriptor-policy)` bundle; sharing a component across two bundles would
  create cross-links between otherwise distinct subsets for no payload
  gain (the components are small and fully determined by the bundle).
- Validated source font faces, shaping instances, and glyph-closure plans
  remain earlier-stage facts; they are inputs to the bundle, not graph
  nodes. The registry-level sharing story for source faces is the Gate 3
  contract ([gate-3-caller-font-retention.md](gate-3-caller-font-retention.md))
  and is unchanged.

## Canonical identity and exact equality

Identity flows through the existing versioned domain-separated digest
procedure with descriptor partitioning first (`Font` kind, subtype 0 = the
supported TrueType-flavoured CIDFontType2 form). The payload is a **typed
recipe, bijective with the emitted bundle**, produced by the new
`KernelFontLeaf` module. The recipe is authoritative and simultaneously the
relevant-byte authority, because it serializes every emitted fact in its
exact emitted form *and* embeds the exact sanitized subset-program bytes:

1. recipe tag (1) — the bundle shape version;
2. the six-byte deterministic subset tag, then the length-prefixed
   validated PostScript name (together the emitted BaseFont);
3. descriptor policy facts: flags, italic angle, StemV (exact emitted
   integers);
4. scaled metrics exactly as emitted: Ascent, CapHeight, Descent, and the
   FontBBox corners, produced by the same shared scaling helpers the object
   lowering uses (`KernelPdfFont.scaled_signed_metric`);
5. the width table: entry count, then per CID the exact emitted `/W`
   integer (`KernelPdfFont.scaled_unsigned_metric`) and the content flag.
   The entry count also commits the identity CIDToGIDMap stream (CID =
   subset glyph ID is validated, so the map is `2 × entries` bytes of
   identity);
6. the ToUnicode facts: mapping count, then per content CID the exact
   scalar sequence — the exact `bfchar` content of the emitted CMap;
7. the sanitized subset program: length, then the exact bytes.

Facts that are constants of the one emission site are documented rather
than serialized, exactly as the shading/function recipes document `/N 1`
and `[0 1]` domains: Identity-H encoding, horizontal writing mode,
CIDSystemInfo Adobe-Identity-0, `/DW 1000`, the `/W [0 [...]]` shape, the
unfiltered FontFile2 with `/Length1`, and the fixed ToUnicode
header/footer/blocking. There is no representable variation instance,
vertical mode, or alternative encoding, so none of those can differ between
two bundles that reach emission.

Consequences, each proven by evidence:

- Equal glyph sets with different Unicode mappings, different metrics
  policies, or different descriptor facts never merge (fields 3–6 differ).
- Different glyph closures from one face never merge (fields 2, 5, 7
  differ).
- Different source faces never merge even with similar names/metrics
  (field 7 differs; the subset tag in field 2 hashes the source digest).
- Embedding-permission and hinting differences are inside the sanitized
  program's retained `OS/2`/`cvt `/`fpgm`/`gasp`/`prep` tables, so they are
  inside field 7.
- Two independently supplied source buffers that sanitize to the same
  supported subset with the same mappings produce byte-identical recipes
  and may share — and only then.

Hash equality stays a candidate only: the canonical graph run partitions by
exact descriptor and byte length and confirms by exact payload equality
with the documented bounded radix ordering; forced digest-collision
evidence uses the graph's white-box `TruncatedTestDigest` seam over real
font recipes containing both exact twins and distinct recipes.

`KernelFontLeaf.build` refuses to derive identity from inconsistent facts:
descriptor policy, subset-tag charset, PostScript-name charset, dense
CID/subset-glyph agreement, recorded subset length versus actual bytes,
width scaling overflow, and the mappings-versus-content-flags agreement
(missing, unexpected, unordered, empty, or invalid-scalar mappings) are all
typed rejections before any digest exists. The unchanged `KernelPdfFont`
lowering re-validates the same facts at emission, so a plan and its emitted
bundle cannot disagree.

## Subset naming policy

The deterministic subset tag is the unchanged Gate 3 policy: six uppercase
letters derived from SHA-256 over the inspected source-font digest and the
ordered retained original glyph IDs, joined to the validated PostScript name
with `+`. Properties, restated for this slice:

- It depends only on canonical stable facts (source-face bytes and the
  exact glyph set); authored order, registration order, object numbers,
  and unrelated resources cannot move it.
- It is a valid PDF name: the tag is `[A-Z]{6}` by construction and the
  PostScript name is charset-validated (no delimiters, whitespace,
  controls, non-ASCII, `#`, or `+`), at both the identity and the emission
  boundary.
- It is stable for identical explicit inputs and package versions.
- It cannot silently alias distinct canonical leaves, because the tag is
  never a binding mechanism: streams bind fonts through canonical `F<n>`
  resource names and object references, and merging is decided solely by
  exact recipe equality. Two canonical leaves that deliberately share a
  tag (same face and glyph set, different ToUnicode facts) emit two
  bundles; the distinctness evidence pins exactly this case.
- Collision handling is bounded: the tag is fixed-width, needs no probing
  or renaming pass, and the deterministic total order across leaves is the
  graph's canonical-ID order.

Resource names are `F<n>` over canonical font ordinals assigned in
canonical-ID order — the same documented content-derived total order every
other canonical kind uses — so names are independent of authored names and
registration order.

## Pipeline integration

- **Font selection is naming, so it moved to lowering.** Prepared run
  bodies from `KernelPdfText.ScenePlan` no longer bake `/F<authored> …
  Tf`; the `TextRun` carries its authored font ordinal and size, and
  `KernelContent.emit_text` emits the selection through the naming map
  (authored ordinal on the Gate 2/3 paths — byte-identical output — and
  the canonical map on the Gate 4 path). This removes the form slice's
  documented stopgap ("font references inside those bytes use the planned
  dense font identity") and makes form recipes and bytes independent of
  authored font numbering.
- **Form recipes** serialize a text command as paint facts, the font
  leaf's identity digest, the exact run size, and the prepared
  ActualText/body bytes — bijective with the emitted stream, which emits
  the canonical `Tf` selection followed by those bytes.
- **Leaves.** `KernelForm` consumes derived font-leaf recipes through the
  same `Leaf` shape every other leaf uses; the fonts-stay-1:1 rule and its
  `DuplicateLeafPayload` rejection are deleted. Canonical font ordinals,
  representatives, and the authored-to-canonical `font_names` map follow
  the exact color/image mechanism; dictionary buckets, closure,
  reachability (`UnreachableResource` for an unused authored font), cycle
  proofs, and deterministic planning are the graph's existing machinery
  over the unchanged `Font` node range.
- **Objects.** `KernelGate4FormObjects` plans `9 × canonical fonts`
  objects after the patterns; `KernelGate4FormStructure` emits one bundle
  per canonical ordinal from its lowest authored representative's
  validated facts and that representative's collected mappings, and
  cross-checks authored/mapping/planned counts. Emitting a duplicate
  bundle for one canonical identity is structurally unrepresentable:
  object identities are planned from the canonical count and emission
  iterates canonical representatives once, in canonical order.

## Ownership, copying, retention, and complexity

- **The identity arena no longer retains caller font programs.** The form
  slice's stopgap copied the entire authored payload (the whole inspected
  font) into the canonical payload allocation; the recipe replaces it, so
  the arena holds the sanitized subset plus the typed facts. The showcase
  retains 23,764 identity-arena bytes across its three canonical bundles
  where the stopgap would have copied and hashed the 506,716 bytes of its
  four authored font programs; the sharing grid holds one 5,747-byte
  recipe under 1000 placements (`retained_identity_bytes`, recorded per
  scenario). Recipe bytes are budgeted by the graph's existing
  `max_payload_bytes`; count and per-dimension limits are unchanged.
- The inspected source allocation itself remains owned by the Gate 3
  registry contract through final emission (metrics and the PostScript
  name range are read from it at lowering); that retention is recorded in
  [gate-3-caller-font-retention.md](gate-3-caller-font-retention.md) and
  is not changed or duplicated here — nothing in this slice copies the
  source payload.
- Recipe derivation is linear in width entries + mapping scalars + subset
  bytes; each authored font derives exactly one recipe, each canonical
  font digests once, plans one object bundle, and appears once per using
  stream's dictionary. Per placement (per run) the only work is the
  existing run-body copy plus one `Tf` naming — no per-placement parse,
  subset, hash, or allocation of font data, proven by the sharing scale
  scenarios' counters.
- Canonicalization keeps the graph's documented `O((V+E) log V)` and
  `O(n log n)` factors and the bounded collision partition-plus-equality
  work; there is no all-pairs comparison (the forced-collision scenario
  pins `entries − 1` adjacent comparisons and byte totals).
- No inner loop (recipe serialization, digesting, equality, dictionary
  partition, emission) allocates or performs ARC work per compared,
  hashed, or emitted byte.

## Structurally unrepresentable failure classes

- *A duplicate physical bundle for one canonical identity*: object counts
  come from the canonical count and emission iterates representatives
  (the checker still counts and byte-compares every bundle).
- *A dictionary/use disagreement*: dictionaries derive from the same
  normalized fact set as the graph edges; the independent checker enforces
  used-equals-declared per stream externally.
- *Canonically equal recipes with different emitted bytes*: the recipe is
  bijective with the bundle, and both the recipe and the emission read the
  same validated bundle record; count/order guards reject a caller that
  supplies disagreeing lists.
- *Unsupported technology, writing mode, encoding, or instance shape*: not
  representable at this boundary; inspection and shaping rejected them in
  earlier stages, and the emission site has no alternative form.
- *Semantic ownership inside a reusable font bundle*: font objects carry
  no MCIDs, `/StructParents`, OBJR, or ownership wrappers by construction;
  placement semantics stay in page streams and placement records.

## Evidence

Roc `expect` coverage lives beside the modules (`KernelFontLeaf`: exact
recipe bytes, emitted-metric scaling agreement, every distinctness axis,
and every rejection; `KernelContent`: the `Tf` selection emitted through
both naming maps over one prepared body) and in
`Gate4FontLeafEvidence.roc`. Harness cases (`tests/spec.json`,
scenario revision `gate4-font-leaves-v1`, measured on the pinned dev
backend at `before_fixture_main`; `arm64mac` recorded equal to the
measured `x64musl` values, matching the suite convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 14564 | 4 authored → 3 canonical fonts, 5 runs over 2 pages + a form, 27 font objects, twin confirmed by 1 comparison over 5956 bytes |
| facts (distinctness matrix) | 7548 | 5 authored → 5 canonical leaves, 45 font objects, one BaseFont tag shared by three bundles |
| unique input | 7282 | one pipeline run, identical counters and bytes |
| retained input | 14561 | two pipeline runs over one retained input, identical bytes |
| share x100 | 17938 | 100 runs/placements → 1 canonical font, 9 font objects, 5747 recipe bytes |
| share x1000 | 129486 | 1000 runs/placements → 1 canonical font, still 9 font objects and 5747 recipe bytes |
| dedupe x8 | 6892 | 8 authored equivalent bundles → 1 canonical, 7 adjacent comparisons over 40229 bytes |
| dedupe x64 | 16973 | 64 authored → 1 canonical, 63 comparisons over 362061 bytes, one emitted bundle |
| distinct x8 | 17925 | 8 canonical fonts, 72 font objects, reverse-order byte-compare |
| distinct x64 | 71387 | 64 canonical fonts, 576 font objects, reverse-order byte-compare |
| collide x8 | 10364 | one forced bucket of 8: 4 twins → 1 + 4 distinct, 3 comparisons |
| collide x64 | 12828 | one forced bucket of 64 → 33 canonical, 39 comparisons, no all-pairs work |
| atomic negatives | 19319 | 11 distinct rejections, 0 escaped plans, 0 escaped bytes |

What the scaling shows: `share` isolates per-placement work at one
canonical font — run visits, glyph visits, text placements, and emitted
content bytes scale 100 → 1000 while recipe bytes (5747), leaf digests,
canonical fonts, dictionary entries, and the nine font objects stay exactly
one bundle's worth, so reuse costs no per-placement font parse, subset,
hash, copy, or retention. `dedupe` isolates identity work — recipe bytes,
hashed bytes, collision entries, and adjacent equality comparisons scale
8 → 64 (7 → 63 comparisons, exactly entries minus one) while canonical
fonts, emitted bundles, dictionary entries, and objects stay one.
`distinct` isolates per-canonical work — recipes, digests, dictionary
entries, and the nine-object bundles scale exactly 8×, with the fully
reversed adversarial authoring byte-compared inside the scenario at both
scales. `collide` drives the same derived recipes through the graph's
white-box `TruncatedTestDigest(1)` seam: all 64 entries land in one
fingerprint bucket, descriptor/length partitioning plus bounded radix
ordering and adjacent exact equality merge only the 32 true twins (33
canonical resources), and the counters pin 39 comparisons over 178173
bytes — not the 2016 comparisons of all-pairs equality.

The showcase covers, across two pages: one canonical subset shared by
three semantic placements — two page-level runs on different pages and one
run painted inside a Form XObject — plus an independently authored
equivalent bundle that collapses into it, one distinct-closure leaf from
the same face, and one leaf from a different source face; logical order
differs from paint order on page one, per-stream `/Font` dictionaries are
exact direct uses, and the reversed adversarial authoring (the authored
fonts renumbered in reverse, every run's instance remapped) is
byte-compared inside the scenario. The `facts` case pins the distinctness matrix in one document:
the base `{A, B}` closure; the same face with the genuinely different
closure `{A}`; two bundles sharing that exact glyph set that differ in one
emitted fact each — the ToUnicode mapping (the same subset glyph extracts
as `A` versus `Å`) and the StemV descriptor policy — so three bundles
deliberately share one BaseFont subset tag while remaining three distinct
physical bundles, proving a shared tag cannot merge distinct canonical
leaves; and a different source face (the caller fixture face).

The 11 atomic negatives in the harness sweep cover the identity boundary
(`KernelFontLeaf`: an invalid descriptor policy, a corrupted subset tag,
subset bytes disagreeing with their recorded length, and a
missing/unexpected/empty/surrogate-scalar Unicode mapping each as its own
twin), the plan boundary (`LeafCountMismatch` for a supplied leaf list
disagreeing with the declared count, `UnreachableResource` for an authored
font no stream uses, and the graph payload budget rejecting recipe bytes
transactionally), and the assembly boundary (`FontCountMismatch` for a
bundle list disagreeing with the plan). The `KernelFontLeaf` module
expects additionally pin the remaining leaf rejections (invalid PostScript
name, empty and non-dense plans, zero units-per-em) and every distinctness
axis at the recipe level. Every rejection is a distinct structured
diagnostic with no plan and no bytes; the two existing text-form ownership
rejections (`TextFormMultiplyPlaced`, `ArtifactTextInForm`) stay covered by
the unchanged form-text scenario.

## Independent evidence

`scripts/check_gate4_fonts.py` parses the emitted bytes directly and
proves, per fixture: exactly one nine-object bundle per canonical font — a
Type 0 parent with Identity-H and a tagged BaseFont, a CIDFontType2
descendant with the canonical UTF-16BE Adobe-Identity-0 `CIDSystemInfo`
and `/DW 1000`, a descriptor whose `FontName` agrees and whose program is
`FontFile2` only, an unfiltered subset stream whose `/Length1` equals its
exact bytes, an identity `CIDToGIDMap` stream byte-compared against the
dense `2 × glyphs` map, and a ToUnicode CMap whose `bfchar` entries are
re-parsed as ascending in-range CIDs. The embedded subset itself is
re-verified as an independent font check: sfnt signature, allowlisted
table set, per-table checksums, the whole-font `checkSumAdjustment`, one
long `hmtx` metric per glyph, and the emitted `/W` array equal to the
subset's own `hmtx` advances scaled by its `unitsPerEm`. Every `Tf`
operand resolves through its own stream's exact direct `/Font` dictionary
(the used-equals-declared rule now covers fonts), deduplicated authored
fonts resolve to one physical bundle while no two emitted bundles are
exact twins, the deliberate shared-tag trio stays three bundles, no
`FontFile`/`FontFile3` or non-Type 0 font shape appears anywhere, and
MCID/ParentTree ownership stays placement-site on every page of the
two-page showcase. Seven length-preserving mutation twins (font subtype,
descendant subtype, Identity-H encoding, `/DW`, subset-tag casing, the
CIDToGIDMap identity bytes, and the sfnt signature) must each be rejected,
and the checker self-test runs in `./scripts/test.py` alongside the other
Gate 4 checkers.

`scripts/check_gate4_font_renderers.py` runs the pinned matrix live:
PDFium Chromium 7988 and PDFBox 3.0.8 render the distinctness matrix, the
collapse grid, the distinct-subset grid, and the shared-subset grid at
72 dpi, and every declared placement region must carry glyph ink while
everything outside stays blank (structural facts remain the primary
oracle; renderer agreement is corroboration). PDFBox extraction pins each
fixture's exact stream-order text — proving the mapping-distinctness axis
end to end: the same subset glyph extracts as `A` under one bundle and `Å`
under its mapping-distinct twin — including the pinned
duplicate-overlapping-text suppression on the deliberately overlapping
sharing grid (36 of 100 painted glyphs survive as distinct positions, all
through the one shared mapping). With `--mutool`, MuPDF 1.28.2 renders the
same fixtures plus both pages of the two-page showcase (the single-page
PDFium/PDFBox adapters deliberately reject multi-page fixtures) and its
text extraction reproduces each page's stream-order text. Every embedded
subset in every checked fixture is exported and revalidated with the
pinned fontTools 4.61.1 in checksum-verifying mode, re-proving table
checksums, glyph closure, cmap coverage of the content CIDs, and width
agreement with the emitted `/W` array. The complete matrix passes live
with all three engines.

`qpdf --check` (12.3.2) passes every new snapshot with no errors or
warnings, and every fixture regenerates byte-for-byte (the
unique/retained scenarios and the harness prove repeated generation).
veraPDF 1.30.2 (`--flavour 4`, diagnostic only) reports exactly one rule
on the showcase, the distinctness matrix, and the sharing grid —
**6.7.2.1-1, the missing XMP metadata stream** — the same deferred
capability as every previous slice; canonical font leaves introduce no new
PDF/A findings. This remains tool validation, not a conformance claim.

## Reviewed rebaselines

All 175 pre-existing snapshots in the suite are byte-identical; only
allocation counts and three recorded counters moved, from two uniform
causes:

- **Gate 4 canonical-path fixtures, −1 allocation per planner run.**
  Deleting the fonts-stay-1:1 duplicate-payload check removes its per-run
  canonical-count scratch list: −1 for single-run fixtures, −2 for the
  unique/retained pairs' second run, −3 for the form negative sweep. No
  work counter changed.
- **Gate 3 scene-text fixtures, +6 to +72 allocations.** The `Tf`
  selection now lowers through `KernelContent`'s checked naming path (a
  constant number of bounded appends per placement) instead of being baked
  into the prepared body, and each prepared run record carries its font
  ordinal and size. The movement scales with placements and pipeline runs
  (+6 to +29 for one-document fixtures, +36/+72 for the multi-face and
  caller retention pairs, which run two documents), and
  `prepared_text_bytes` drops by exactly the 12-byte `Tf` line per run
  (245 → 233; 103 → 91 for the reordered-ActualText case). The facade
  ×1000/×10000 materialization counters are untouched (their measured
  phase excludes content lowering).
- **`Gate 4 text inside a meaningful form`, bytes unchanged.** Both causes
  plus the recipe replacing the whole-font payload: allocations
  1618 → 1633, `text_content_bytes` 245 → 233 (the moved `Tf` line), and
  `recipe_bytes` 334 → 362 (the form recipe now embeds the 32-byte font
  identity digest and 8-byte size instead of the 12-byte prepared `Tf`
  line). The snapshot is byte-identical: the single font's canonical
  ordinal equals its authored ordinal, so every name, object, and stream
  survives unchanged — and the identity arena now retains the ~6 KB
  bundle recipe instead of the whole 166,300-byte face.

Gate 1/2 fixtures and every fontless byte snapshot are untouched.

## Exact remaining Gate 4 work

- XMP metadata, document language, and output intents — landed in
  [gate-4-metadata-output-intent.md](gate-4-metadata-output-intent.md),
  which absorbed the 6.7.2.1 finding above.
- URI links, typed internal destinations with paired `/SD` + `/D`, named
  destinations, outlines, and page labels — landed in
  [gate-4-navigation-annotations.md](gate-4-navigation-annotations.md).
- Annotation appearances through this same scene/resource pipeline — landed in
  [gate-4-navigation-annotations.md](gate-4-navigation-annotations.md).

This slice deliberately claims `Pdf20`/`Standard` output only.
