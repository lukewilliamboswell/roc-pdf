# Gate 4 transparency: constant opacity, Normal blending, and isolated groups

This records the design, semantics, ownership model, complexity, and evidence
for the fourth Gate 4 slice: PDF 2.0 transparency as an end-to-end capability
built on the resource graph
([gate-4-resource-graph.md](gate-4-resource-graph.md)), the Form XObject
machinery ([gate-4-form-xobjects.md](gate-4-form-xobjects.md)), and the
canonical color/image/ICC leaves
([gate-4-color-image-leaves.md](gate-4-color-image-leaves.md)). It makes the
existing typed `Scene.Opacity` capability executable for the supported subset.
It does not close Gate 4 and claims no PDF/A-4 or PDF/UA-2 conformance.

## Scope and non-scope

Implemented:

- Constant non-stroking and stroking opacity (`/ca`, `/CA`) through canonical
  deduplicated `ExtGState` resources, with `/BM /Normal` emitted explicitly.
- Balanced `q … gs … Q` lowering around every non-opaque opacity group, in
  page scenes and inside Form XObject scenes.
- Explicit direct `ExtGState` dependencies and exact per-stream `/ExtGState`
  dictionaries derived during normalization, never by scanning operators.
- Page transparency `/Group << /CS … /S /Transparency >>` dictionaries on
  every page that (transitively, through placed forms) contains transparency,
  naming the canonical ICCBased sRGB blending space.
- Isolated Form transparency groups: `Scene.Form` gains the typed
  `group : [IsolatedGroup, NoGroup]` fact, lowered as
  `/Group << /CS … /I true /S /Transparency >>`.
- Nested opacity with exact, documented multiplicative effective-alpha
  semantics and a per-stream nesting budget.

Still rejected, transactionally and with structured diagnostics:

- Non-Normal blend modes, luminosity soft masks, knockout groups, overprint,
  CMYK/Separation/DeviceN/spot transparency, caller-supplied graphics-state
  dictionaries or raw operators, external streams, optional content. None of
  these are representable in the typed scene, so their "diagnostics" are
  structural absence rather than late validation (see the unrepresentable
  classes below).
- A non-group form whose own stream carries opacity, executed under a
  non-identity ambient alpha (`FormOpacityInAmbient`, below).
- Per-run `TextPaint.opacity` other than fully opaque remains the existing
  `TextPaintInvalid(OpacityNotOpaque)` rejection: text-paint alpha is a
  separate capability; text painted *inside* an opacity group composes
  through the same `gs` mechanism as every other painting operator.

**Deferred: Form-backed alpha soft masks.** ExtGState `/SMask` masks (an
alpha mask rendered from a Form XObject with its own isolated group) are the
recorded next dependency slice. Including them here would have forced the
mask-Form ownership, nesting-whitelist, and mask-reuse representation into an
already wide slice. Raster image `/SMask` alpha (per-sample) already shipped
in the color-image slice and composes with constant alpha natively — the
showcase proves the product. Nothing in this slice is a partial or silently
restricted mask path.

## Modules and stage boundaries

- `Scene.roc` — `Opacity` documented executable semantics; `Form.group`.
- `KernelScene.roc` — form-aware scenes validate opacity groups like any
  nested command range (`Resources.with_forms` gates the capability; Gate 2/3
  constructors keep rejecting it); opacity commands are counted validation
  work.
- `KernelResourceGraph.roc` — the `ExtGState` kind (append-only rank, so no
  existing identity digest changed) and closure-only uses
  (`build_with_closure_uses`): validated, canonical-mapped references that
  seed the closure proof without entering root dictionaries, the dependency
  store, or the planning order.
- `KernelForm.roc` — the opacity pre-pass, the transparency sweeps, canonical
  ExtGState identity, blending-space selection, page-transparency facts, the
  per-command canonical state maps, and the recipe extension.
- `KernelContent.roc` — `q … gs … Q` lowering from the normalized state maps.
- `KernelGate4FormObjects.roc` — one dictionary object per canonical state,
  planned between form streams and font objects (`build_with_states`; a zero
  state count leaves every existing plan identical).
- `KernelGate2PageObjects.roc` — `build_with_page_groups`, the per-page
  transparency `/Group` entry.
- `KernelGate4FormStructure.roc` — ExtGState objects, `/ExtGState` dictionary
  buckets, the shared page-group and isolated-group values, form `/Group`
  entries.
- `KernelResourceUse.roc` — `build_with_forms_and_blending` credits the page
  group's `/CS` reference as a genuine use of the blending space.
- `Gate4TransparencyEvidence.roc` — scenario evidence.
- `scripts/check_gate4_transparency.py` — the independent structural checker.
- `scripts/check_gate4_transparency_renderers.py` — the pinned
  PDFium/PDFBox/MuPDF matrix.

Stage contracts are unchanged: semantics and ownership exist before layout;
transparency is visual state carried by scene commands and form facts; MCIDs
and marked-content ownership remain placement-site facts of page streams; the
serializer consumes sealed normalized facts and repairs nothing.

## Effective-alpha semantics and the U16 mapping

`Scene.Opacity` carries one public `U16` alpha applied to both the
non-stroking and stroking constants. The **effective alpha of a painted
element is the product of every enclosing opacity group within its content
stream**, computed in exact fixed width:
`effective = round_half_even(ambient × own, 65535)` at each nesting step
(the denominator is odd, so the half-way tie cannot occur and the rounding is
plain nearest; the function keeps the shared round-half-even shape).

- 65535 is fully opaque and an **exact multiplicative identity**
  (`x·65535/65535 = x`). An opacity command whose own value is the identity
  **normalizes away entirely**: no resource, no operators, no recipe marker.
  This is a normalization decision, tested at every stage boundary, not a
  serializer optimization.
- Zero annihilates exactly and is a supported constant (invisible painting).
- A non-identity factor always lands strictly below 65535, so an emitted
  state's value is in `[0, 65534]` and the identity value doubles as the
  internal "no state" sentinel without collision.
- The canonical PDF number uses the identical mapping color channels use:
  `round_half_even(value × 10⁹, 65535)` emitted at scale 9 — 32768 emits
  `0.50000763`, 49152 emits `0.750011444`, 16384 emits `0.250003815`, zero
  emits `0`. `/ca`, `/CA`, and painted channel values therefore agree
  byte-for-byte on one canonical arithmetic.

Nested groups lower to nested `q /GS_eff gs … Q` pairs whose operands carry
the *effective* products, so PDF's replace-semantics `gs` implements the
typed multiplicative semantics exactly. The showcase pins the exactness:
0.75 × 2/3 (49152 then 43690) collapses onto the same canonical state as a
directly authored 0.5, because `49152 × 43690 = 32768 × 65535` exactly.

### Across form boundaries

A form without a transparency group is transparent to the graphics state, so
its painted elements multiply the ambient alpha natively — placing a plain
form under an opacity group needs nothing special. An **isolated group form**
resets the ambient constant alpha at its boundary (ISO 32000-2, 11.6.6: at
the start of group execution ca/CA/BM/SMask reset to their initial values,
and the enclosing state applies once to the group's composited result), so
its internal opacity is relative to the group and the one shared stream stays
valid under every placement context.

The single combination whose correct behavior one shared stream cannot
encode is a **non-group form whose own stream carries a non-opaque opacity
command, executed under a non-identity ambient alpha**: the inner `gs` would
replace, not multiply, and the required per-placement effective product has
no shared representation. That combination is the transactional rejection
`FormOpacityInAmbient`, resolved over the placement DAG (ambient context
propagates through non-group parents and stops at isolated-group
boundaries). Authors who need it isolate the form. This mirrors the form
slice's `TextFormMultiplyPlaced` rule: a structured rejection in place of
silent duplication or changed semantics.

## Canonical identity recipes

- **ExtGState** — a derived leaf per *distinct effective value*, never an
  authored resource: recipe `tag ‖ ca:U16 ‖ CA:U16 ‖ bm:Normal` under an
  `ExtGState` descriptor. The recipe contains every emitted fact (`/ca`,
  `/CA`, `/BM`); equal effective values share one recipe by construction and
  distinct values can never merge (the value is the payload). The canonical
  graph run still confirms by descriptor partition plus exact bytes, and
  canonical `GS` ordinals follow canonical-ID order like every other kind.
- **Transparency-group facts** — isolation is a *descriptor flag* of the
  form's identity (`flags = 1`), so an isolated form and its group-less twin
  never merge while every existing group-less form recipe (and digest) is
  byte-identical to before. Knockout is structurally absent (always false,
  no key emitted). The blending space is globally constant (the packaged
  ICCBased sRGB), so group recipes need no per-form space digest; if a future
  capability allows per-group blending spaces, the space digest joins the
  recipe then.
- **Form recipes** serialize opacity in *normalized lowered form*: an opaque
  group is transparent to the recipe (children inline, exactly as its stream
  emits nothing), and a non-opaque group serializes marker ‖ effective:U16 ‖
  children ‖ close. The recipe stays bijective with the emitted stream
  structure: visually identical but structurally different nestings (a direct
  0.25 versus 0.5 × 0.5) keep distinct identities because their streams
  differ, while authored-ID permutations and opaque wrappers cannot split an
  identity.

## Normalization pipeline

1. **Opacity pre-pass** (`derive_opacity`): one iterative walk per page group
   and per form over the two command arenas, carrying `(ambient, depth)` per
   frame. It computes each command's effective value, registers distinct
   values in first-appearance order (the 65536-entry map is allocated only
   when the scene counted at least one opacity command), records
   ambient-alpha facts at each `PlaceForm` site, per-form direct
   opacity/alpha facts, and per-page direct transparency. Depth beyond
   `max_opacity_depth` is `OpacityDepthExceeded` (per stream; cross-stream
   stacking is legal only through isolated groups, and form nesting is
   already bounded).
2. **Blending selection**: only when any transparency fact exists, profiles
   are probed once each by exact byte equality against the packaged
   `sRGB2014.icc`; the lowest authored `Srgb`/`IccBased` space over the
   packaged profile becomes the blending space. All equivalent declarations
   deduplicate to one canonical space downstream.
3. **Use collection** touches derived state nodes (appended after forms in
   the node space) exactly like leaves, so `gs` dependencies are edges and
   root uses of the same graph.
4. **Structure run** validates the DAG including state nodes; when
   transparency exists, one conservative closure-only use keeps the blending
   space reachable before per-page facts are known.
5. **Transparency sweeps** mirror the text sweeps: a forward topological pass
   folds transitive transparency per form (isolated children count), and a
   reversed pass resolves ambient contexts over the compressed per-edge
   ambient flags (parents first, one visit per direct edge). Then the
   `FormOpacityInAmbient` check, per-page transparency (direct facts plus
   placed transparency-bearing or isolated forms), and
   `MissingBlendingSpace({page})` for the first transparency page without a
   blending candidate.
6. **Canonical run** digests state recipes, deduplicates, assigns canonical
   per-kind ordinals, builds the dense per-command
   `command → canonical GS ordinal` maps for both arenas, exact per-stream
   dictionaries with the new `ExtGState` bucket, and the exact per-page
   closure uses.

Content lowering consumes the state maps: non-opaque group → `q`,
`/GS<n> gs`, children, `Q`; identity group → children with no operators.
Graphics state stays balanced by construction (the group opening and its
frame's close are one lowering unit), and lowering computes no policy.

## Resource graph, dictionaries, and objects

- Derived states are ordinary canonical leaves: direct edges from forms that
  use them, root uses from pages, closure, cycles, and deterministic
  planning all through the one graph implementation.
- The page group's `/CS` is a **closure-only use**: it keeps the blending
  space (and transitively its profile) reachable without fabricating a
  `/Resources` entry, so the checker's used-equals-declared rule stays exact.
  Closure-only uses are validated, share the root-use budget, and are
  counted work.
- Every content stream's dictionary is exactly its direct uses, now
  partitioned as ColorSpace / **ExtGState** / Font / XObject with canonical
  `GS<n>` names in ascending ordinal order. States shared across page and
  form streams resolve to one physical object (the showcase pins a state
  shared by a page group and an in-form group).
- Object planning appends one dictionary object per canonical state between
  the form streams and the font objects; emission is
  `<< /BM /Normal /CA a /Type /ExtGState /ca a >>`. One shared page-group
  value serves every transparency page; one shared isolated-group value
  serves every isolated form (they share the one blending space).
- The transparency names (`Group`, `ExtGState`, `BM`, `CA`, `ca`, `CS`, `I`,
  `S`, `Transparency`, `Normal`) join the name table only when the plan
  contains the corresponding facts, so a transparency-free document keeps
  its exact name table, normalized plan identity, and bytes.

## Complexity, allocation, ARC, and retention

- The opacity pre-pass, use collection, sweeps, state-map construction, and
  lowering are linear in commands, placements, forms, direct edges, states,
  and emitted bytes. The graph keeps its documented `O((V+E) log V)` and
  `O(n log n)` factors over a node space grown by the distinct-value count.
- Per-command work: one visit in the pre-pass and one in use collection
  (counted: `use_command_visits`, pre-pass visits inside
  `transparency_sweep_visits`' companions); per-group work: one registration
  and one `q/gs/Q` emission; per-canonical-state work: one recipe, one
  digest, one object, and its dictionary entries; per-edge work: one visit
  in each sweep. The scaled cases isolate each term (below).
- Allocation shape: the pre-pass allocates the two dense per-arena state and
  ambient lists plus one frame list per root; the 65536-entry value map is
  one allocation, only for scenes that contain opacity. No inner loop
  (walking, registering, sweeping, recipe or operator emission) allocates or
  performs ARC work per command, per edge, per compared byte, or per emitted
  byte; state recipes are bytes appended to the existing canonical identity
  arena (`state_recipe_bytes` counted, retained as part of
  `retained_identity_bytes` through emission).
- ARC: the unique and retained showcase cases produce identical bytes and
  counters at 2516 versus 5001 allocations — the retained-input cost of
  planning one immutable input twice, unchanged in kind from the previous
  slices.
- Emitted state objects and group values are generated plan values (never
  seamless resource slices); the ICC blending profile stream remains the
  validated store's own allocation, eligible for unchanged-resource sharing
  exactly as before.
- Peak/nesting storage: the walkers' frame lists grow with nesting depth,
  bounded by the graphics-depth and opacity-depth budgets; sweeps use the
  compressed child store built once by counting and prefix sums.
- Diagnostics stay compact structured values (form/page indices, attempted
  versus limit); no diagnostic retains payloads or scene stores.

## Evidence

Roc `expect` coverage lives beside each module (exact U16 endpoint and
rounding tests in `KernelForm`, gs lowering in `KernelContent`, scene
validation in `KernelScene`, closure-use behavior in `KernelResourceGraph`)
and in the evidence module. Harness cases (`tests/spec.json`, scenario
revision `gate4-transparency-v1`, measured on the pinned dev backend at
`before_fixture_main`; `arm64mac` recorded equal to the measured `x64musl`
values, matching the suite convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 5031 | 10 opacity commands → 9 groups → 4 canonical states, 1 opaque normalized, depth 2, 1 transparency page, 1 isolated form |
| unique input | 2516 | one pipeline run, identical counters and bytes |
| retained input | 5001 | two pipeline runs over one retained input, identical bytes |
| share x100 | 4422 | 100 groups → 1 canonical state, 100 gs operators |
| share x1000 | 35043 | 1000 groups → 1 canonical state, 1000 gs operators |
| states x100 | 9719 | 100 distinct values → 100 states/objects/dictionary entries |
| states x1000 | 88083 | 1000 distinct values → 1000 states/objects |
| nest x16 | 1977 | depth 16, 16 distinct effective products |
| nest x64 | 4885 | depth 64, 64 distinct effective products |
| forms x8 | 2803 | 8 canonical forms sharing 1 state, 8 form→state edges |
| forms x32 | 8046 | 32 canonical forms sharing 1 state, 32 edges |
| atomic negatives | 1989 | 12 distinct rejections, 0 escaped plans |

What the scaling shows: `share` isolates per-group work at one canonical
state (gs operators, graphics pairs, and content bytes scale 100 → 1000
while states, recipes, objects, and dictionary entries stay one); `states`
isolates per-canonical-state work (states, state objects, recipe bytes,
dictionary entries, and graph hashes scale exactly 10× while per-group work
matches `share`); `nest` isolates nesting-depth work with per-level distinct
products (`65534/65535` per level decrements the effective value exactly
once per level for the whole chain); `forms` isolates per-form and
per-edge work at one shared state (form dictionaries, form→state edges,
recipes, and objects scale while the state stays canonical across all form
streams). `unique` versus `retained` is the retained-input ARC cost with
byte-identical output.

The showcase covers, in one page with meaningful and artifact placements and
logical order differing from paint order: an intermediate constant on a
path; exact-product nesting collapsing onto a directly authored state; the
opaque identity emitting nothing; zero opacity; constant alpha over an
alpha-masked image (the per-sample × constant product); opacity around a
plain form placement; opacity inside a form (its state object shared with
the page's equal constant); and an isolated group with internal opacity and
an overlapping opaque shape placed under page opacity. Its reversed
authored-ID twin (spaces and forms renumbered) is byte-compared inside the
scenario.

The twelve atomic negatives: opacity in a Gate 2 scene; non-opaque
`TextPaint`; an empty opacity group; a transparency page without the
packaged sRGB space; an isolated group form forcing the same requirement
with fully opaque content; `FormOpacityInAmbient` directly and through a
nested placement chain; the opacity-depth budget; the recipe-byte budget on
an opacity-bearing form; the graph resource budget counting derived states;
an unplaced isolated form (unreachable); and the closure-use share of the
root-use budget. Every rejection is a distinct structured diagnostic with no
plan and no bytes.

## Independent evidence

`scripts/check_gate4_transparency.py` parses the emitted bytes directly and
proves, per fixture: every ExtGState object is exactly the canonical
Normal-blend constant-alpha shape with `/ca` equal to `/CA` and one object
per distinct alpha; every `gs` operand resolves through its own stream's
exact direct `/ExtGState` dictionary (the used-equals-declared rule now
covers graphics states) and opens the balanced `q`-then-`gs` group; page
`/Group` dictionaries resolve through the canonical ICCBased array to a
profile stream byte-identical to the vendored `sRGB2014.icc`; isolated forms
carry exactly `/Group << /CS n 0 R /I true /S /Transparency >>` over the
same blending space and non-isolated forms carry none; no `/SMask` state, no
non-Normal `/BM`, no knockout, and no transfer functions appear anywhere;
cross-stream state sharing resolves to one physical object while distinct
alphas never merge; and MCID/ParentTree ownership stays exactly the
placement-site page-stream facts. Length-preserving mutation twins (blend
mode, `/CA`-`/ca` disagreement, group subtype, isolation flag) must each be
rejected. The shared form checker now resolves `gs` operands and validates
`/Group`-when-present, with its existing fixtures unchanged.

`scripts/check_gate4_transparency_renderers.py` renders the original bytes
with PDFium Chromium 7988, PDFBox 3.0.8, and (via `--mutool`) MuPDF 1.28.2,
comparing full 100×100 rasters at **zero pixel and zero channel tolerance**
against expectations constructed independently from the typed scenario: the
geometry from the authored rectangles and placements, the colors from the
constant-alpha compositing model `C = α·Cs + (1−α)·Cb` over the paint order.
Because the canonical alphas are exact U16 ratios, most ideal composites
fall between 8-bit codes; the per-renderer resolved codes are pinned and
mechanically validated to sit within one code of the ideal model (two for
MuPDF, whose ICC pipeline adds the same ±1 its opaque sRGB fills show; its
calibrated-gray composites display through the pinned tone behavior the
form slice recorded). Two version-scoped renderer facts are pinned exactly
rather than tolerated loosely: PDFBox 3.0.8 places an isolated transparency
group's off-screen buffer one device row below the outer content, and MuPDF
composites calibrated gray in its display space. The matrix passes on the
showcase (opacity, exact nesting, isolation under page opacity, and the
soft-mask × constant-alpha knockout all visible through overlapping shapes)
and the shared-state grid.

`qpdf --check` (12.3.2) passes every new snapshot and the regenerated
color-image snapshots with no errors or warnings. Every fixture regenerates
byte-for-byte across repeated runs.

veraPDF 1.30.2 (`--flavour 4`, explicit run, diagnostic only): the
transparency showcase and the regenerated color-image showcase now fail
exactly one rule — **6.7.2.1-1, the missing XMP metadata stream**, which is
precisely the deferred XMP/PDF-A slice. The former 6.2.9-2 failure (a page
containing transparency without a PDF/A output intent or page `/Group`),
recorded as deferred by the color-image slice, is cleared by this slice's
page transparency groups. This remains tool validation, not a conformance
claim; no PDF/A-4 flavor is declared or implied by these fixtures.

## Rebaseline of existing fixtures

Every canonical-path fixture now runs the opacity pre-pass and the
transparency sweeps, moving allocation counts by +7 (grids) to +144 (the
form negative sweep) with **no work-counter changes**; the reviewed cause is
the pre-pass's dense per-arena state/ambient lists and per-root frame lists.
Bytes changed only for the color-image showcase family (6743 → 6784): its
alpha imagery makes the page a transparency page, so it gains exactly the
page `/Group << /CS n 0 R /S /Transparency >>` naming its canonical ICCBased
sRGB space — the correction its own performance record had listed as
deferred. The full pinned renderer matrix and structural checkers pass on
the regenerated bytes (appearance is unchanged; the group only declares the
blending space). All other Gate 1–4 snapshots are byte-identical, kept so
deliberately by registering the transparency names and group values only in
plans that contain transparency.

## Structurally unrepresentable failure classes

- *Unsupported blend modes, luminosity or ExtGState soft masks, knockout,
  overprint, transfer functions, raw graphics-state dictionaries*: no public
  type carries them; the emitted `/BM /Normal` is a constant of the one
  state-lowering site, and the independent checker still scans for all of
  them.
- *Invalid opacity representation or bounds*: the public alpha is `U16`;
  every value is meaningful, and the effective product cannot leave
  `[0, 65534]` (proved by the endpoint expects).
- *Unreachable graphics states*: state nodes are derived from uses, so a
  stateless resource cannot exist; the graph still re-proves closure.
- *Dictionary/use disagreement*: dictionaries derive from the same
  normalized facts as the edges; the checker enforces the rule externally.
- *Unbalanced opacity groups*: the `q`/`gs` opening and its frame's `Q` are
  one lowering unit; imbalance cannot be authored, and the checker counts
  pairs and verifies each `gs` opens a group.
- *Invalid isolation/knockout combination*: knockout is unrepresentable;
  isolation is a single typed fact.

## Exact remaining Gate 4 work

- Form-backed alpha soft masks (ExtGState `/SMask` with mask Forms as
  explicit DAG resources, bounded nesting, and a supported-combination
  whitelist) — the recommended next slice, now that isolated groups and the
  blending space exist for mask Forms to build on.
- Linear/radial shadings and supported tiling patterns.
- Canonical font leaf identity and deduplicated font-leaf emission.
- XMP metadata, document language, output intents (which will also absorb
  the 6.7.2.1 finding above), URI links/destinations/outlines/labels, and
  annotation appearances.

This slice deliberately claims `Pdf20`/`Standard` output only: PDF/A-4
requires the XMP and output-intent capabilities above, and PDF/UA-2 requires
the Gate 6 vocabulary, so no closure claim is made here.
