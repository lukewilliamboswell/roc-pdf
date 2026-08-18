# Gate 4 Form-backed alpha soft masks

This records the design, semantics, ownership model, complexity, and evidence
for the fifth Gate 4 slice: ExtGState `/SMask` alpha soft masks whose masks
are Form XObjects held as explicit resources in the dependency DAG — the
capability the transparency slice
([gate-4-transparency.md](gate-4-transparency.md)) recorded as its next
dependency slice, built directly on that slice's isolated groups, canonical
ExtGState machinery, and blending space. It does not close Gate 4 and claims
no PDF/A-4 or PDF/UA-2 conformance.

## Scope and non-scope

Implemented:

- `Scene.SoftMask({ children, mask })`: a per-sample **alpha** soft mask —
  the alpha channel of the referenced mask Form rendered against a fully
  transparent backdrop — applied to the children's painting operations,
  lowered as the same balanced `q /GSn gs … Q` group constant opacity uses.
- The mask Form must be an explicit `IsolatedGroup` form; it therefore
  carries `/Group << /CS … /I true /S /Transparency >>` over the canonical
  packaged sRGB blending space (`MaskFormNotIsolated` otherwise; nothing is
  upgraded implicitly).
- Canonical mask states: one ExtGState per canonical mask Form, emitted as
  `<< /SMask << /G m 0 R /S /Alpha /Type /Mask >> /Type /ExtGState >>`, with
  `/G` referencing the canonical mask Form's stream object **directly** —
  soft masks never enter a resource dictionary.
- The state→mask-Form reference is a **direct DAG edge**: mask Forms stay
  reachable without dictionary entries, cycles through masks are ordinary
  graph cycles rejected before lowering, the mask Form's identity digest
  orders before the states that embed it, and repeated mask visuals share
  one physical state and Form without sharing any semantic ownership.
- Constant alpha and soft masks compose natively (independent graphics-state
  parameters; the spec multiplies them), including image `/SMask` per-sample
  alpha underneath — no interaction rules were invented.
- Explicit mask composition through isolated groups: a masked
  isolated-group form may itself apply masks internally (the group boundary
  resets the ambient mask, ISO 32000-2, 11.6.6), giving well-defined
  inner-times-outer products with shared streams.

Rejected, transactionally and with structured diagnostics:

- `NestedSoftMask` — a soft-mask group under another within one stream
  context: PDF's `gs` would replace rather than compose the mask, so the
  typed model rejects the shape and the isolated-group route above is the
  supported composition. This is the deliberate one-active-mask rule, not a
  missing feature.
- `FormMaskInAmbient` — a non-group form whose own stream applies a mask,
  executed under an ambient mask (the soft-mask analogue of the
  transparency slice's `FormOpacityInAmbient`, resolved by the same
  reversed DAG sweep with both ambient channels stopping at isolated-group
  boundaries).
- `TextInMaskForm` — semantic text transitively reachable in a mask
  rendering: mask content produces no marked content, MCIDs, or extraction
  presence, so text there would silently lose its semantics. Rejected for
  mask-reachable forms regardless of dual use.
- `MaskDepthExceeded` — the mask chain (a mask Form whose subtree applies
  further masks) is bounded by the new `max_mask_depth` budget, computed by
  a dependencies-first sweep, never by walking paths.
- Luminosity masks (`/S /Luminosity`), backdrop colors (`/BC`), transfer
  functions (`/TR`), knockout, and non-Normal blending remain structurally
  unrepresentable; the independent checker still scans for all of them.

## Canonical identity

A mask state's recipe is `tag ‖ Alpha-subtype ‖ digest(mask Form)` under an
`ExtGState` descriptor with **subtype one** (constant-alpha states keep
subtype zero, so their digests are unchanged and the two shapes can never
share a collision bucket). Because the payload is the mask Form's Merkle
digest, two authored mask Forms that deduplicate collapse their states too,
and authored-ID permutations cannot split an identity — the showcase's
authored twin mask proves both. Distinct mask Forms never merge because
their digests differ. The state's `/G` fact and the recipe agree by
construction: both come from the same canonical Form ordinal.

In form recipes a `SoftMask` command serializes as marker ‖ mask-Form digest
‖ children ‖ close, so a form's identity contains its mask dependencies
exactly as it contains its placed-form dependencies.

## Normalization pipeline

The transparency slice's derived-state pre-pass generalizes to one combined
derived-state space `[AlphaState(value), MaskState(form)]`: distinct
effective alphas and distinct authored mask Forms register dense
first-appearance indices during the same walk (each registry map allocated
only when the scene counted the corresponding commands), each walk frame
carries `(ambient alpha, opacity depth, mask context)`, in-stream nesting and
non-isolated mask targets reject immediately, and `PlaceForm` sites record
both ambient channels. Use collection touches mask states exactly like alpha
states; the state→mask-Form edges join the graph alongside the image→space
and space→profile edges.

After the ownership sweep, the transparency sweeps carry both channels
(direct masks are transparency facts, so masked pages get the page `/Group`
and require the blending space), and two mask-specific sweeps run **only for
documents that apply masks**: a reversed sweep marks mask-reachable forms
(for `TextInMaskForm`), and a forward, dependencies-first sweep computes
mask-chain depths over a counting-and-prefix-sum adjacency of the direct
edges (`MaskDepthExceeded`). Content lowering consumes the same dense
per-command canonical-state maps as opacity — the `SoftMask` emission branch
is the identical balanced-group mechanism.

## Complexity, allocation, and retention

- The pre-pass, use collection, sweeps, and lowering stay linear in
  commands, placements, forms, direct edges, and states; the mask sweeps add
  one visit per node and direct edge, and the graph keeps its documented
  factors over the grown node space.
- Mask registration is one 8-byte-per-form map allocated only for scenes
  with soft-mask commands; the ambient site facts ride in the existing
  per-arena lists (element widened, allocation count unchanged); maskless
  documents skip the mask sweeps entirely and keep their bytes identical —
  every pre-existing snapshot in the suite is byte-for-byte unchanged, with
  per-fixture allocation counts moving by single digits (the widened site
  records and gated checks), re-measured and recorded per case.
- Mask state recipes are 34 bytes appended to the canonical identity arena
  (`state_recipe_bytes`), retained through emission like every recipe. Mask
  state objects are small generated dictionaries; the mask Form stream is an
  ordinary canonical form stream emitted once regardless of how many states,
  streams, or placements reference it.
- No inner loop allocates or performs ARC work per command, edge, compared
  byte, or emitted byte; `unique` versus `retained` shows the usual
  retained-input allocation ratio with byte-identical output.

## Evidence

Roc `expect` coverage lives beside each module (scene validation, the
combined registry, gs lowering) and in `Gate4SoftMaskEvidence.roc`. Harness
cases (`tests/spec.json`, scenario revision `gate4-soft-masks-v1`, measured
on the pinned dev backend at `before_fixture_main`; `arm64mac` recorded equal
to the measured `x64musl` values, matching the suite convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 4577 | 6 mask groups → 2 authored → 1 canonical mask state, 4 authored → 3 canonical forms, 2 state objects, chain 1 |
| unique input | 2287 | one pipeline run, identical counters and bytes |
| retained input | 4548 | two pipeline runs over one retained input, identical bytes |
| reuse x100 | 4743 | 100 mask groups → 1 canonical mask state and Form |
| reuse x1000 | 35364 | 1000 mask groups → 1 canonical mask state and Form |
| masks x8 | 3390 | 8 distinct mask Forms → 8 states/objects, 1 shared band alpha state |
| masks x64 | 19313 | 64 distinct mask Forms → 64 states/objects |
| chain x2 | 1600 | chain depth 2 |
| chain x4 | 2094 | chain depth 4 (the budget) |
| atomic negatives | 2391 | 9 distinct rejections, 0 escaped plans |

What the scaling shows: `reuse` isolates per-mask-group work at one
canonical state (gs operators and content bytes scale while states, Forms,
recipes, and objects stay one); `masks` isolates per-canonical-mask work
(states, mask Form streams, state objects, and `/G` references scale exactly
8× while the shared band's alpha state stays one); `chain` isolates
mask-chain depth work inside the budget. The showcase covers the authored
twin deduplicating across two streams, mask-around-plain-form,
mask-around-isolated-form with internal mask composition, the
constant-times-mask product, and zero-coverage knockout, with meaningful and
artifact placements, logical order differing from paint order, and the
reversed authored-ID twin byte-compared in the scenario.

The nine atomic negatives: soft masks in a Gate 2 scene; a mask reference
out of range; `MaskFormNotIsolated`; `NestedSoftMask`; `FormMaskInAmbient`;
`TextInMaskForm` (through a minimal typed run store); `MaskDepthExceeded`;
a mask cycle through two forms (`DependencyCycle`); and a masked page
without the packaged sRGB blending space. Every rejection is a distinct
structured diagnostic with no plan and no bytes.

## Independent evidence

`scripts/check_gate4_soft_masks.py` parses the emitted bytes directly and
proves: every canonical mask state is exactly the Alpha-mask shape with one
object per canonical mask Form and `/G` resolving to an isolated-group Form
over the canonical blending space; mask-only Forms appear in no resource
dictionary while the selecting `gs` operands resolve through their own
stream's exact `/ExtGState` dictionaries and open balanced groups (the
shared `TransparencyFacts` now classifies both state shapes and its
forbidden-state scans cover `/Luminosity`, `/BC`, and `/TR`); mask reuse
resolves to one physical state across page and form streams while distinct
masks never merge; the chain fixtures link exactly N deep; and
MCID/ParentTree ownership stays placement-site. The shared form checker
accepts `/SMask /G` references as reachability roots. Length-preserving
mutation twins (mask subtype, mask kind, group isolation, blend mode) must
each be rejected.

`scripts/check_gate4_soft_mask_renderers.py` compares full 100×100 rasters
at **zero pixel and zero channel tolerance** against expectations
constructed independently from the typed scenario: geometry from the
authored rectangles, mask bands, and placements; colors from the per-sample
model `C = m·a·Cs + (1−m·a)·Cb` over the paint order. Pins are mechanically
validated against the model (one code for PDFium/PDFBox, three for MuPDF's
ICC pipeline on masked composites; calibrated gray through its pinned tone
behavior). Two version-scoped deviations are pinned exactly rather than
tolerated loosely: **PDFium 7988 re-evaluates the active mask in a placed
non-group form's translated space** (its masked plain-form band renders the
page-band × form-space-band intersection, validated against that
intersection model), and **PDFBox 3.0.8 renders a masked isolated-group form
one device row short at the top** (the companion of its pinned group-offset
from the transparency slice). The matrix passes on the showcase and the
shared-mask grid with PDFium Chromium 7988, PDFBox 3.0.8, and MuPDF 1.28.2.

`qpdf --check` (12.3.2) passes every new snapshot with no errors or
warnings; every fixture regenerates byte-for-byte. veraPDF 1.30.2
(`--flavour 4`, diagnostic only) reports exactly one rule on the mask
showcase — **6.7.2.1-1, the missing XMP metadata stream** — the same
deferred capability as the previous slices; masks introduce no new PDF/A
findings because the page transparency group and blending space already
cover 6.2.9.

## Structurally unrepresentable failure classes

- *Luminosity masks, backdrop colors, transfer functions, knockout,
  non-Normal blending*: no public type carries them; the Alpha subtype is a
  constant of the one mask-state emission site.
- *A mask dictionary disagreeing with the DAG*: the `/G` reference and the
  state's recipe both derive from the same canonical Form ordinal.
- *An unreachable mask Form*: reachable exactly through its state's direct
  edge; an unreferenced mask Form is the ordinary `UnreachableResource`.
- *Unbalanced mask groups*: the `q`/`gs` opening and its frame's `Q` remain
  one lowering unit; the checker verifies each `gs` opens a group.

## Exact remaining Gate 4 work

- Linear/radial shadings and supported tiling patterns — landed in
  [gate-4-shadings-patterns.md](gate-4-shadings-patterns.md).
- Canonical font leaf identity and deduplicated font-leaf emission —
  landed in [gate-4-font-leaves.md](gate-4-font-leaves.md).
- XMP metadata, document language, and output intents — landed in
  [gate-4-metadata-output-intent.md](gate-4-metadata-output-intent.md),
  which absorbed the 6.7.2.1 finding above.
- URI links, typed internal destinations with paired `/SD` + `/D`, named
  destinations, outlines, page labels, and annotation appearances — landed
  in [gate-4-navigation-annotations.md](gate-4-navigation-annotations.md).

This slice deliberately claims `Pdf20`/`Standard` output only.
