# Gate 4 linear/radial shadings and colored tiling patterns

This records the design, semantics, ownership model, complexity, and
evidence for the sixth Gate 4 slice: PDF 2.0 axial/radial shadings and a
deliberately bounded subset of colored tiling patterns, end to end through
the typed scene boundary, normalization, the resource DAG, sealed object
planning, serialization, and the evidence harness — built on the resource
graph ([gate-4-resource-graph.md](gate-4-resource-graph.md)), the Form
XObject machinery ([gate-4-form-xobjects.md](gate-4-form-xobjects.md)), the
canonical leaves ([gate-4-color-image-leaves.md](gate-4-color-image-leaves.md)),
and the transparency slices ([gate-4-transparency.md](gate-4-transparency.md),
[gate-4-soft-masks.md](gate-4-soft-masks.md)). It does not close Gate 4 and
claims no PDF/A-4 or PDF/UA-2 conformance.

## Supported and rejected capability boundary

Implemented:

- `Scene.PaintShading({ shading })`: paints the referenced shading across
  the current clip region with the `sh` operator, in page scenes, Form
  scenes, and pattern cells. Geometry is expressed in the user space of the
  paint site; authors bound the paint with `Clip` and position it with
  `Transform`.
- Axial (`/ShadingType 2`) and radial (`/ShadingType 3`) shadings with
  explicit fixed-point geometry, explicit ordered stops, explicit
  per-endpoint extension, and the existing device-independent color forms
  only (canonical ICCBased sRGB and calibrated grayscale).
- Deterministic PDF function construction: one exponential segment
  (`/FunctionType 2`, `/N 1`) per adjacent stop pair, assembled under one
  stitching function (`/FunctionType 3`) for multi-stop gradients; a
  two-stop gradient is its single segment function directly.
- `PatternFill({ pattern, rule })` in `PathStyle.fill`: colored tiling
  patterns (`/PatternType 1 /PaintType 1 /TilingType 1`) selected as the
  nonstroking paint (`/Pattern cs` + `/Pt<n> scn`), in page and Form
  scenes. The optional solid stroke of the same path keeps its typed solid
  color.
- Pattern cells as ownership-neutral reusable visual resources: an explicit
  cell command range over a dedicated flat pattern-command arena, explicit
  positive bounds and X/Y steps, and an explicit pattern-to-target-space
  matrix (identity retained and emitted explicitly). Cells may clip,
  transform, draw solid paths, place alpha-free images, paint shadings, and
  place text-free, transparency-free forms.
- Exact direct `/Shading` and `/Pattern` resource dictionaries per content
  stream, and exact direct nested dictionaries per pattern stream, derived
  during normalization.

Rejected, transactionally and with structured diagnostics (or structurally
unrepresentable):

- Mesh shadings (types 1, 4–7), arbitrary caller-supplied PDF functions,
  PostScript calculator functions, exponents other than 1, and non-`[0 1]`
  domains: no public type carries them; the independent checker scans every
  object for the forbidden types.
- Uncolored tiling patterns (`/PaintType 2`), non-constant tiling
  (`/TilingType 2/3`), and stroke patterns: structurally unrepresentable.
- Nested pattern invocation: a cell filling with a pattern is
  `PatternInPatternCell` at scene validation; a pattern-reachable form
  filling with a pattern is `NestedPatternInvocation`; a cycle through
  patterns and forms is the graph's ordinary `DependencyCycle`.
- Semantic text in pattern content: `TextInPatternCell` for direct cell
  text, `TextInPatternForm` for text transitively reachable through a
  placed form (tiled content repeats and is ownership-neutral, so semantic
  text there would lose or duplicate its semantics; there is no
  artifact-text carve-out in this slice).
- Transparency in pattern content: `TransparencyInPatternCell` for direct
  opacity/soft-mask groups, `AlphaImageInPattern` for an alpha image drawn
  in a cell, and `TransparencyInPattern` for a pattern-reachable form
  carrying any direct or transitive transparency or an isolated group.
  Pattern content is fully opaque in this subset; patterns and shadings
  *under* ambient opacity or soft masks at the placement site compose
  natively and are supported (the showcase proves the product).
- Degenerate geometry: `DegenerateShadingGeometry` (coincident axial
  endpoints; coincident radial circles; both radii zero),
  `NegativeShadingRadius`. A single zero radius (a cone endpoint) is
  supported.
- Invalid stops: `TooFewShadingStops` (fewer than two),
  `ShadingStopsNotIncreasing` (equal or descending offsets),
  `ShadingStopEndpointInvalid` (first stop not exactly 0 or last not
  exactly 65535), `ShadingStopComponentMismatch` (channel arity against the
  declared space), and the `ShadingStops` limit. Adjacent equal colors are
  retained as authored (a flat band is visually meaningful); they are never
  coalesced.
- Invalid patterns: `NonPositiveRect` bounds, `PatternStepInvalid`
  (non-positive steps), `PatternMatrixSingular`, `EmptyPatternCell`, and
  the store/arena budgets.
- An unused shading or pattern is the graph's `UnreachableResource`; a
  dictionary/use disagreement is structurally unrepresentable because both
  derive from one normalized fact set.

CMYK, Separation, DeviceN, spot color, overprint, and non-Normal blending
remain outside the whitelist as before.

## Public and normalized representations

Public (`Scene`): `ShadingId`/`PatternId` opaque dense IDs;
`GradientStop : { channels : Color.Channels, offset : U16 }` in one flat
stop list; `Shading` records with a typed `ShadingGeometry` union and a
stop range; `PatternCell` records with a command range into the flat
pattern arena; `ShadingStore`/`PatternStore` mirroring `FormStore`. No PDF
object numbers, resource names, dictionary keys, function shapes, or raw
operators are exposed.

Normalized: shadings, patterns, and the derived functions join the dense
node space after the derived graphics states
(`[colors][images][fonts][profiles][forms][states][shadings][patterns][functions]`),
with arithmetic node mapping and no per-node tables. The function layout is
derived once from the validated store (`shading_function_offsets` prefix
sums plus a `function_shadings` back-map): a two-stop shading derives one
segment; an `n`-stop shading derives `n-1` segments plus one stitching
function laid out segments-first so the root is always the last node of its
shading.

## Fixed-width numeric semantics

- Stop offsets are public `U16`: 0 is domain 0.0, 65535 is domain 1.0,
  `t = offset / 65535` exactly. The canonical PDF number is
  `round_half_even(offset × 10⁹, 65535)` at scale 9 — byte-identical to the
  channel and constant-alpha mapping, so stitch `/Bounds`, function
  `/C0`/`/C1`, painted channels, and `/ca` all agree on one arithmetic.
- Stop colors are the existing `U16` channels under the same mapping.
- Coordinates, radii, steps, and matrices are `Layout.Unit` (`I64`
  milli-points, 1000 per point) emitted at the exact scale-3 mapping `cm`
  and `re` operands use. Negative zero is unrepresentable (`I64` raw), all
  derived arithmetic is checked, and no host floating-point formatting
  exists anywhere in the path.
- `/Domain [0 1]` and `/Encode [0 1 …]` are emitted explicitly as integers;
  `/Extend` is always the explicit two-boolean array; radii must be
  non-negative; pattern steps must be strictly positive; pattern matrices
  must have a nonzero checked determinant.

## Canonical identity recipes

All identity flows through the existing versioned domain-separated digest
procedure, with descriptor partitioning first (`Shading` kind with the PDF
shading type as subtype and the channel arity as components; `Pattern` kind
with subtype 1; the new append-only `Function` kind, rank 8, with the PDF
function type as subtype — no existing digest changed):

- **Segment function** — tag ‖ channel arity ‖ exact `U16` stop colors
  (`C0`, `C1`). The domain, encode, and exponent are constants of the
  emission site, so the recipe is bijective with the emitted object; equal
  adjacent stop pairs deduplicate across shadings (the showcase pins the
  multi-stop gradient's middle segment shared with the pattern cell's
  ramp).
- **Stitching function** — tag ‖ segment count ‖ segment identity digests ‖
  exact interior `U16` offsets (the `/Bounds`).
- **Shading** — axial/radial tag ‖ exact `I64` geometry ‖ extend flags ‖
  color-space identity digest ‖ root-function identity digest. The function
  digest transitively commits every stop position and color, so identity
  contains every emitted and visually significant fact; a 2-stop gradient
  and a 3-stop gradient with a redundant interior stop stay distinct
  deliberately (their function subtrees differ, as do their streams).
- **Pattern** — bounds ‖ x/y steps ‖ matrix ‖ the canonical cell-command
  recipe over the shared serializer (geometry and styles inlined, every
  image/form/shading/pattern reference replaced by its identity digest,
  `PaintShading` as marker 10 ‖ shading digest, `PatternFill` as fill tag 2
  ‖ rule ‖ pattern digest).

Digests remain candidates only: the canonical graph run's descriptor/length
partitioning and exact byte equality confirm every merge, and adversarial
authored-ID permutation is byte-compared inside the showcase scenario.
Deduplication shares physical objects only; ownership stays at placement
sites (pattern streams and mask-free shading dictionaries carry no MCIDs,
`/StructParents`, or OBJR facts — the checker proves their absence).

## Resource DAG and closure

Derived edges: shading → color space, shading → root function, stitching
function → each segment; pattern → every direct cell use (spaces, images,
shadings, forms) from one deduplicating walk per cell (Pass C of the use
collection); page/form uses of shadings and patterns join root uses and
form edges through the same walker (`PaintShading` touches its shading
node, `PatternFill` its pattern node). Functions never enter a resource
dictionary — like ICC profiles they are reachable only through their
references, and the dictionary partition carries an always-empty function
bucket so the rule is structural. Cycles, closure, deterministic
topological planning, and per-stream exact direct dictionaries are the
graph's existing proofs over the grown node space; recipes digest in
topological order, so functions digest before shadings and every referenced
resource digests before the recipes that embed it.

The pattern-reachability sweep mirrors the mask sweep: one reversed
topological pass over the direct-edge adjacency (built by counting and
prefix sums) marks every form a pattern rendering can execute, then the
text/transparency/nested-invocation rejections read the already-computed
transitive facts. It runs only for documents that declare patterns.

## Function-object strategy

The simplest faithful representation of the exact stop model: exponential
interpolation per stop interval with `/N 1`, stitched with the exact
interior offsets as bounds and canonical `[0 1]` encode pairs. Stop
ordering and domains validate at the scene boundary before object planning;
function objects have deterministic content-derived identity and canonical
ordering; equal functions merge only after exact recipe equality; every
referenced function is an explicit graph node and planned object; and
construction is bounded by the per-shading stop budget (256), the shared
recipe-byte budget, and the graph's resource/object limits. No function
language is public, and independent inspection re-derives domains, bounds,
encode arrays, endpoint components, and adjacent-segment continuity from
the emitted objects alone.

## Object planning, lowering, and emission

- Objects append after the graphics states, before the fonts: one
  dictionary per canonical shading, one per canonical function, one
  stream/length pair per canonical pattern, each in canonical-ID order.
  Zero paint counts leave every existing plan identical.
- Shading dictionaries are exactly `/ColorSpace c 0 R /Coords […]
  /Domain [0 1] /Extend [a b] /Function f 0 R /ShadingType 2|3`; pattern
  streams are exactly `/BBox /Matrix /PaintType 1 /PatternType 1
  /Resources /TilingType 1 /Type /Pattern /XStep /YStep` over a deflated
  cell stream. Deferred keys (`/Background`, `/AntiAlias`, `/BBox` on
  shadings, transfer functions) emit nothing.
- Content lowering consumes the canonical name maps: `sh` paints name
  `Sh<ordinal>`, pattern fills lower to the exact `/Pattern cs` +
  `/Pt<ordinal> scn` selection, and each canonical pattern cell lowers
  exactly once from its representative's validated command range with no
  ownership wrapper. The paint names (`Shading`, `Pattern`, `Coords`, the
  function keys, the tiling keys) join the name table only when the plan
  contains the corresponding facts, so paint-free documents keep their
  exact bytes — every pre-existing snapshot in the suite is byte-for-byte
  unchanged.
- Pattern space follows ISO 32000-2 8.7.3.1: the matrix maps pattern space
  to the default space of the stream that uses the pattern, and a consuming
  form's placement transform composes on top. The showcase's transformed
  form placement uses a step-aligned translation deliberately, so the
  pinned renderers agree bytewise on tile positions regardless of their
  anchor interpretation.

## Complexity, allocation, ARC, and retention

- Validation, use collection, cell walks, the pattern sweep, recipe
  serialization, lowering, and emission are linear in commands, stops,
  cells, placements, direct edges, and recipe/content bytes; the graph
  keeps its documented `O((V+E) log V)` and `O(n log n)` factors over the
  grown node space. Function derivation is one pass over the shading store
  (prefix sums), never per paint.
- Per-stop work: one validation visit, one arity check, one recipe
  contribution; per-canonical-function work: one recipe, one digest, one
  object; per-canonical-shading work: one dictionary object and its
  references; per-paint work: one `sh`/`scn` emission and one touch;
  per-cell-command work: one validation visit, one use visit, one recipe
  visit, one lowering visit. The scaled cases isolate each term (below).
- Allocation shape: the paint stores are flat lists with spans; the
  function layout is two dense lists built once; cell walks reuse the
  shared deduplicating use-state; no inner loop allocates or performs ARC
  work per stop, command, edge, compared byte, or emitted byte. Stitch
  facts hold one small child-ordinal list per canonical stitching function
  (per canonical multi-stop shading, not per stop).
- Retention: recipes and leaf payloads stay in the one canonical identity
  arena (`retained_payload_bytes`, retained through emission); pattern
  streams are Generated payloads owned by the object store until emission
  (never shared as seamless resource chunks); emission facts (stop
  channels, bounds) lower from the validated shading store's own records.
  `unique` versus `retained` shows the usual retained-input allocation
  ratio (3821 versus 7597) with byte-identical output and identical work.
- Bounded diagnostics: every rejection is one structured value with
  compact indices and the exact failed bound; no diagnostic retains stops,
  arenas, or payloads.

## Rebaseline of existing fixtures

Every Gate 4 pipeline fixture now derives the (empty) paint layout during
`Facts` construction, moving allocation counts by +1 to +3 (+8/+10 for the
negative sweeps, which run the pipeline many times) with **no work-counter
changes**; the reviewed cause is the always-present one-element
function-offset prefix list per `Facts` run plus the widened plan records.
Bytes are unchanged for every pre-existing snapshot in the suite — the
paint names and buckets register only in plans that contain paint facts —
and Gate 1–3 fixtures kept their exact allocation counts. The full pinned
structural and renderer matrices pass on the unchanged bytes.

## Evidence

Roc `expect` coverage lives beside each module (stop/geometry validation in
`KernelScene`, recipes and sweeps in `KernelForm`, lowering in
`KernelContent`) and in `Gate4ShadingPatternEvidence.roc`. Harness cases
(`tests/spec.json`, scenario revision `gate4-shadings-patterns-v1`,
measured on the pinned dev backend at `before_fixture_main`; `arm64mac`
recorded equal to the measured `x64musl` values, matching the suite
convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 7642 | 7 authored → 6 canonical shadings, 10 → 8 functions, 3 → 2 patterns, 9 content `sh` paints, 3 pattern fills, 2 pattern streams, 40 objects |
| unique input | 3821 | one pipeline run, identical counters and bytes |
| retained input | 7597 | two pipeline runs over one retained input, identical bytes |
| share x100 | 4241 | 100 `sh` paints → 1 canonical shading/function/object |
| share x1000 | 32162 | 1000 `sh` paints → 1 canonical shading/function/object |
| distinct x8 | 2573 | 8 canonical shadings/functions/objects |
| distinct x64 | 13584 | 64 canonical shadings/functions/objects |
| stops x16 | 2304 | 16 stops → 15 segments + 1 stitch, one shading |
| stops x64 | 5931 | 64 stops → 63 segments + 1 stitch, one shading |
| pshare x100 | 3715 | 100 fills → 1 canonical pattern/stream |
| pshare x1000 | 28021 | 1000 fills → 1 canonical pattern/stream |
| pdistinct x8 | 2589 | 8 canonical patterns/streams |
| pdistinct x64 | 14696 | 64 canonical patterns/streams |
| pcells x16 | 1439 | 16 cell commands in one canonical pattern |
| pcells x64 | 2735 | 64 cell commands in one canonical pattern |
| atomic negatives | 2035 | 27 distinct rejections, 0 escaped plans |

What the scaling shows: `share`/`pshare` isolate per-placement work
(content `sh`/`scn` operators and use visits scale 100 → 1000 while
canonical shadings, functions, patterns, recipes, dictionaries, and objects
stay one); `distinct`/`pdistinct` isolate per-canonical-resource work
(shadings, functions, pattern streams, recipe bytes, dictionary entries,
edges, hashes, and objects scale exactly 8× while equality work stays
bounded); `stops` isolates per-stop and per-function work at one canonical
shading (stop visits, derived functions, function recipe bytes, and
function objects scale while the shading and its dictionary stay one);
`pcells` isolates per-cell-command work at one canonical pattern (cell
visits and pattern recipe/stream bytes scale while everything canonical
stays one). Counters, not timing, demonstrate the declared complexity.

The showcase covers, in one page with meaningful and artifact placements
and logical order differing from paint order: the two-stop horizontal
red-to-blue gradient; the diagonal asymmetric multi-stop gradient with
unextended corner knockout; the radial cone with differing centers/radii
and both extensions; the calibrated-gray gradient; the authored twin
shading deduplicating across a fragment and an artifact placement; a
one-color-fact-distinct shading staying distinct under an ambient opacity
group; two pattern fills whose cells are byte-identical but whose matrices
differ (identity versus doubled — distinct by exactly one visual fact); the
authored twin pattern deduplicating through a transformed form placement; a
pattern cell using a shading whose segment function is shared with the
multi-stop gradient; and a form painting both a pattern fill and the shared
shading. Its reversed authored-ID twin (spaces, shadings, and patterns
renumbered) is byte-compared inside the scenario.

The 27 atomic negatives: the Gate 2 and Gate 4 form-constructor gates;
out-of-range shading and pattern references; single-stop, misplaced-first,
misplaced-last, and non-increasing stops; degenerate axial geometry;
negative, coincident, and both-zero radial geometry; the per-shading stop
budget; a stop/space arity mismatch; non-positive steps; a singular
matrix; empty bounds; an empty cell; text, transparency, and a nested
pattern fill directly in a cell; text, transparency, and nested pattern
invocation through a placed form; an alpha image in a cell; a
pattern-form dependency cycle; and an unreachable declared shading. Every
rejection is a distinct structured diagnostic with no plan and no bytes.

## Independent evidence

`scripts/check_gate4_shadings.py` parses the emitted bytes directly and
proves: every shading dictionary is exactly the supported axial/radial
shape with exact coordinates, domain, extends, and resolvable
space/function references; every function is exactly the segment or
stitching shape, with strictly increasing interior bounds, canonical
encode, endpoint components at the exact canonical decimals, and
adjacent-segment stop continuity re-derived from the emitted objects; every
pattern stream is exactly the colored constant-spacing shape with positive
steps, an invertible matrix, exact nested dictionaries, and no marked
content, MCIDs, text, or `/StructParents`; every `sh` and pattern `scn`
operand resolves through its own stream's exact direct dictionary; function
objects appear in no dictionary; equal recipes share one physical object
while distinct recipes never merge (the twin/distinct/cross-shading
segment-sharing facts are asserted directly); no unsupported shading,
function, paint, or tiling type appears anywhere; and page MCID/ParentTree
ownership stays placement-site. Eleven length-preserving mutation twins
(shading type, coordinates, domain, extend array, function type, bounds
order, paint type, tiling type, steps, matrix, and a resource-dictionary
entry) must each be rejected, and the neutrality guards are additionally
exercised directly.

`scripts/check_gate4_shading_renderers.py` renders the original bytes with
PDFium Chromium 7988, PDFBox 3.0.8, and (via `--mutool`) MuPDF 1.28.2, and
compares full 100×100 rasters against expectations constructed
independently from the typed scenario: axial parameters from the projection
formula, radial coverage from the larger root of the circle-interpolation
quadratic with extension clamping, tiles from the authored cell geometry
under the authored matrices, and composites from the exact constant-alpha
model. Each pixel is checked against the per-channel envelope of that model
over the pixel footprint extended by a per-region sampling radius (half a
device pixel for direct `sh` regions, one for tiles and the radial
silhouette, 1.5 for the doubled tile grid) plus small pinned per-renderer
code tolerances, each justified next to its pin (ICC ±1; PDFium's radial
silhouette two-root resolution ≤9 codes; PDFBox's ~1/32-domain function
quantization ≤12; the between-code U16 alpha composite ±2). Flat regions
collapse to exact single-color envelopes. Version-scoped deviations are
pinned exactly rather than tolerated loosely: PDFBox 3.0.8's coarse radial
approximation (in-domain far-circle fallback plus an apex-side extension
blob) confines its radial band to the pinned blue-to-white family while
PDFium and MuPDF are held to the exact quadratic; MuPDF 1.28.2 leaves the
final device column of the *first* use of an unextended RGB axial shading
unpainted (the showcase's deduplicated twin paints the exact column the
first band drops, proving the cache identity); MuPDF displays calibrated
gray through its pinned sRGB-curve tone behavior, and calibrated gray
inside pattern tiles through a further tone path whose single authored
value is pinned to its exact code. The matrix passes on the showcase, the
shared-shading grid, and the shared-pattern grid with all three renderers.

`qpdf --check` (12.3.2) passes every new snapshot with no errors or
warnings, and every fixture regenerates byte-for-byte (the retained/unique
scenarios and the harness prove repeated generation). veraPDF 1.30.2
(`--flavour 4`, diagnostic only) reports exactly one rule on the showcase,
the pattern grid, and the stop ramp — **6.7.2.1-1, the missing XMP metadata
stream** — the same deferred capability as every previous slice; shadings
and patterns introduce no new PDF/A findings.

## Structurally unrepresentable failure classes

- *Unsupported shading/function/pattern shapes*: no public type carries
  them; the type integers are constants of the emission sites, and the
  checker scans every object for the forbidden values.
- *A dictionary disagreeing with use*: dictionaries and edges derive from
  one normalized fact set; the checker enforces used-equals-declared per
  stream externally.
- *A function leaking into a resource dictionary*: functions have no
  dictionary bucket; the partition's function bucket is structurally
  always empty and the checker verifies no dictionary entry names one.
- *Semantic ownership inside a reusable pattern*: cells reject text at
  validation and pattern streams receive no ownership wrapper at lowering,
  so MCIDs/`/StructParents`/OBJR cannot be authored into them; the checker
  still scans for all of them.
- *Stroke patterns and uncolored patterns*: `PatternFill` exists only in
  the fill position and PaintType/TilingType are emission-site constants.

## Exact remaining Gate 4 work

- Canonical font leaf identity and deduplicated font-leaf emission.
- XMP metadata, document language, output intents (which will absorb the
  6.7.2.1 finding above), URI links, typed internal destinations with
  paired `/SD`+`/D`, named destinations, outlines, page labels, and
  annotation appearances through this same scene/resource pipeline.

This slice deliberately claims `Pdf20`/`Standard` output only.
