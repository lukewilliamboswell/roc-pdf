# Gate 4 Form XObjects

This records the design, ownership model, complexity, and evidence for the
second Gate 4 slice: Form XObjects as an end-to-end PDF 2.0 capability built on
the resource-planning foundation in
[gate-4-resource-graph.md](gate-4-resource-graph.md). It does not close Gate 4.

## Modules

- `Scene.roc` — public `FormId`, `Form`, `FormStore`, and the `PlaceForm`
  scene command.
- `KernelScene.roc` — form-aware scene validation (`Plan.build_with_forms`)
  that validates form content with the same command rules as page content.
- `KernelResourceGraph.roc` — gains `identity_digest`, exposing the existing
  versioned domain-separated identity procedure for one source range so form
  recipes can embed dependency identities without duplicating digest logic.
- `KernelForm.roc` — form normalization: direct-use facts, the two resource
  graph runs, canonical form identity, per-stream dictionary plans, placement
  ownership records, and text-in-form ownership resolution.
- `KernelContent.roc` — form content stream lowering and `Do` placement
  lowering (`Plan.build_with_forms`).
- `KernelResourceUse.roc` — `TextPlan.build_with_forms` counts direct use
  across the page and form command arenas.
- `KernelTextOwnership.roc` — `Plan.build_with_forms` assigns runs painted
  inside forms to the owner resolved for the unique placement of that form.
- `KernelGate4FormObjects.roc` — deterministic object planning: form stream
  objects (and font objects when text is present) appended after the Gate 2
  base plan.
- `KernelGate2PageObjects.roc` — gains `Plan.build_with_page_resources`, the
  per-page-resource-dictionary variant of the existing page lowering.
- `KernelGate4FormStructure.roc` — assembles tagged, page, resource, form, and
  font objects into one sealed deterministic plan.
- `Gate4FormEvidence.roc`, `Gate4FormTextEvidence.roc` — scenario evidence.
- `scripts/check_gate4_forms.py` — the independent structural checker.
- `scripts/check_gate4_form_renderers.py` — pinned PDFium/PDFBox rendering and
  PDFBox text-extraction evidence.

## The semantic and tagging model

**Decision: placement-site tagging over ownership-neutral physical forms.**

1. A Form XObject's content stream never contains structure-bearing marked
   content: no MCIDs, no `/StructParents`, no `/StructParent`, and no OBJR.
   Form streams may contain non-structural presentation sequences (the
   existing `ActualText` spans emitted by text lowering) because those carry
   no ParentTree ownership.
2. Every meaningful placement is tagged in the *consuming page content
   stream*: the placing scene group is fragment-owned, so the existing
   `/P <</MCID n>> BDC … EMC` wrapper (ISO 32000-2, 14.6.2: content painted by
   a `Do` inside a marked-content sequence is part of that sequence) encloses
   the balanced `q <matrix> cm /XOn Do Q` invocation. Artifact placements are
   likewise enclosed by the group's `/Artifact … BDC … EMC` wrapper.
3. MCIDs, page `/StructParents`, and ParentTree rows therefore remain exactly
   the page-stream facts the Gate 2 tagged plan already produces. No form
   stream acquires a ParentTree mapping, so ISO 32000-2's stream-scoped
   content-item rules (14.7.5.4: an MCID in a non-page stream needs an MCR
   with `/Stm` and the stream's own `/StructParents` key) never apply to
   emitted output.

### Why this model is valid tagged PDF

- Marked-content sequences and MCIDs are scoped to one content stream. A
  content item identified by `(StructParents key, MCID)` resolves through the
  ParentTree to exactly one structure element. Because a physical stream's
  MCIDs have exactly one ParentTree mapping, a stream containing
  structure-bearing marked content is placement-bound: painting it twice would
  repaint the *same* content items, which cannot express two distinct semantic
  occurrences. ISO 32000-2 (14.7.5.4, Note on multiply-referenced streams) and
  the pinned tagged-PDF requirements therefore make in-form MCIDs incompatible
  with physical sharing across distinct owners.
- Placement-site tagging avoids that entirely: the content item is the
  marked-content sequence *in the page stream*, and the whole form invocation
  is inside it. Each placement gets its own MCID and its own structure parent,
  so reusable visual identity stays independent of semantic ownership — the
  exact split `architecture.md` ("Resources and annotations") requires.
- Deduplication merges only the ownership-neutral physical stream. Semantic
  wrappers, MCIDs, fragment ownership, and artifact classifications live in
  page streams and in the placement records, so deduplication cannot merge
  them by construction.

### Sharing and duplication rules

| Case | Physical form object |
| --- | --- |
| One artifact form placed repeatedly | shared |
| One meaningful form placed once | shared (trivially) |
| Identical visuals, two distinct semantic fragments | shared; each placement keeps its own page-stream MCID |
| Identical visuals, different MCIDs/occurrences | shared, as above |
| One occurrence fragmented across placements | shared; the occurrence's fragments each wrap one placement |
| Identical visuals used semantically and as artifact | shared; wrappers stay distinct |
| Nested forms | inner form shared through direct edges |
| Text-bearing form | shared only when recipes are identical; each authored placement owns its own runs |

**Deterministic duplication rule.** Physical duplication becomes necessary
exactly when a form stream itself carries placement-bound tagged facts. In
this slice that state is structurally unrepresentable: form content is a
command range, ownership wrappers are produced only for page-level scene
groups, and no API attaches MCIDs, `/StructParents`, or OBJR facts to a form.
The enforcement backstops still exist and are tested: the resource graph
rejects a placement that declares a placement-specific semantic association as
`Reusable` (`SemanticOwnershipMerge`), and the lowering counters record
`semantically_duplicated_forms` (always 0 in this slice) so the future
fine-grained in-form structure capability must either duplicate per semantic
placement or reject — never merge. Unsafe tagged reuse is therefore a
*documented structured rejection*, which the exit criteria permit in place of
duplication.

### Text inside forms

- A form that paints text (directly or through nested forms) must be
  instantiated exactly once: every `Text.RunId` is drawn exactly once
  globally, matching the existing run-ownership contract. Placing a
  text-bearing form more than once (any placement multiplicity across the
  DAG) is the stable rejection `TextFormMultiplyPlaced`; text reachable under
  an artifact owner is `ArtifactTextInForm`, the form-DAG analogue of the
  existing `ArtifactTextUnsupported`.
- The run's fragment ownership is the owner of the form's unique placement
  chain, resolved iteratively over the DAG (no recursion). The fragment's
  MCID wraps the placement in the page stream; `ActualText`, `ToUnicode`,
  CID, and subset behavior are unchanged because the same
  `KernelPdfText.ScenePlan` run lowering produces the in-form text operators.
- Two authored text-bearing forms whose canonical recipes are byte-identical
  (same glyphs, font, paint, geometry — which requires their occurrences'
  presentation to be identical) deduplicate to one physical stream; each
  placement still extracts through its own MCID and occurrence.

### Logical order versus paint order

Reading order continues to come only from the semantic content spine; MCIDs
are assigned from page paint order; the `/K` order of structure elements is
spine order. Form placement order participates in paint order exactly like any
other painted group, so the `order` scenario proves a document whose spine
order is intentionally different from its form paint order.

## Form identity

The visual identity of a form is a **canonical recipe**, not its raw command
bytes, its authored dense IDs, or its emitted name-bearing stream bytes:

- bounding box (exact fixed-point raw values),
- the canonical identity matrix (this slice fixes `/Matrix [1 0 0 1 0 0]`;
  placement transforms are entirely placement-side facts),
- the form's command tree serialized in arena order with explicit open/close
  structure markers, path geometry and dash values inlined from the shared
  stores, colors serialized as channel values plus the *identity digest* of
  their color space, and every image/form/font reference replaced by the
  referenced resource's 32-byte domain-separated identity digest,
- text commands serialized as the run's prepared `ActualText`/body bytes from
  `KernelPdfText.ScenePlan` (deterministic; font references inside those bytes
  use the planned dense font identity, which is pinned across this slice's
  adversarial permutations — full canonical font facts join the later font
  allowlist-closure slice).

Because nested references are encoded by content-derived digests (Merkle over
the DAG) rather than authored IDs or emitted names, two forms with identical
visuals deduplicate regardless of authoring order, and identity never depends
on incidental resource-name allocation. The digest remains a candidate only:
the resource graph's exact byte equality confirms every merge.

Two graph runs implement this without duplicating any graph logic:

1. **Structure run** — nodes are all authored resources (color spaces, images,
   fonts, forms) with unique 8-byte ordinal payloads; edges are the derived
   direct dependencies; roots are the page content streams. This run validates
   edges, rejects self-cycles/cycles/unreachable resources transactionally,
   and yields the deterministic topological order.
2. Recipes are then built in that order (dependencies first, iteratively), and
   the **canonical run** re-runs the graph over real leaf payloads and form
   recipes, with the derived placement records. It performs deduplication,
   assigns content-derived canonical IDs, proves closure again, and produces
   the per-root and per-resource direct dictionaries that lowering consumes.

Leaf resources (color spaces, images, fonts) remain 1:1 with their authored
stores in this slice; the plan rejects byte-identical authored leaves
(`DuplicateLeafPayload`) rather than silently emitting an orphan object. Leaf
deduplication joins the image/ICC slices that own leaf object emission.

## Dictionaries, names, and object planning

- Every content stream's `/Resources` dictionary is exactly its direct uses
  from the canonical run: pages consume `root_dictionary(page)`; each form
  stream consumes `direct_dependencies(form)`. Transitive dependencies never
  appear in a parent dictionary, and the serializer never scans operators.
- Names are deterministic and content-derived: `CS`/`Im`/`F` keep their
  existing dense authored identities (1:1 with canonical in this slice), and
  forms use `XO<width>_<ordinal>` where the ordinal is the form's position in
  canonical-ID order. Each consuming stream's dictionary binds exactly the
  names its operators use.
- Object planning appends, after the unchanged Gate 2 base plan: one
  stream+length object pair per canonical form in canonical-ID order (the
  documented total order), then the font objects when text is present, then
  the xref. Canonical resource IDs remain independent of PDF object numbers.
- Form stream dictionaries are `/Type /XObject`, `/Subtype /Form`,
  `/FormType 1`, explicit `/BBox`, explicit `/Matrix [1 0 0 1 0 0]`, and a
  complete direct `/Resources` dictionary (present even when empty). Deferred
  capabilities (`/Group`, soft masks, reference/PostScript XObjects, optional
  content, `/StructParents`) emit no keys at all.
- Graphics state is balanced by construction: every placement lowers to
  `q`, the placement matrix `cm`, `Do`, `Q`, so no transformation, clip,
  color, text, or state depth leaks across an invocation.

## Complexity, ownership, and retention contracts

- Scene/form validation, use derivation, ownership resolution, recipe
  serialization, content emission, and dictionary construction are all linear
  in commands, placements, resources, direct edges, and recipe/content bytes;
  the graph adds its documented `O((V+E) log V)` planning and `O(n log n)`
  identity-sort factors, twice (structure + canonical run).
- All DAG traversals are iterative over dense buffers with explicit stacks or
  topological sweeps; a form cycle is rejected by the resource graph before
  any traversal could recurse; nested relationships are scalar IDs and ranges.
- Instantiation counts, transitive text facts, and owner resolution are one
  reversed-topological sweep each — per form plus per direct edge, never per
  path through the DAG (a diamond DAG multiplies counts, not work).
- Ownership: the form store, recipes, and content streams are built once and
  consumed forward; the canonical run retains the recipe/leaf payload
  allocation (`retained_payload_bytes`), and form content bytes are Generated
  payloads owned by the object store until emission (`retained_form_bytes`).
  `copied_form_bytes` records bytes copied because of semantic duplication and
  is 0 under this model. Form streams are generated payloads, so chunked
  output never shares them as seamless resource slices; the unique/shared
  scenarios instead prove the retained-input cost of planning the same
  immutable input twice, with identical bytes and work.
- No allocation or ARC work per emitted byte, per compared byte, or per edge
  traversal in the graph, recipe, or emission inner loops; allocation counts
  scale with resources, edges, placements, and streams and are recorded per
  scenario in `tests/spec.json`.

## Explicitly deferred

- Transparency `/Group`, soft masks, isolated/knockout groups, blend modes,
  and non-opaque placements (`Opacity` remains a rejected scene command).
- Reference and PostScript XObjects, external streams, optional content,
  caller-supplied raw operators, implicit resource discovery.
- Form `/StructParents`, in-form MCIDs/MCR `/Stm`, OBJR content items, and the
  per-semantic-placement physical duplication they will require.
- Leaf (image/ICC/font) deduplicated object emission and annotation
  appearances, which will consume this slice's form machinery.
- Recursive forms are permanently rejected (the direct-edge DAG has no legal
  cycle).

## Structurally unrepresentable failure classes

Several rejection classes from the slice requirements are prevented by
construction rather than detected late, which is the stronger property:

- *Undeclared or missing direct dependencies*: every dictionary is derived
  from the same normalized use facts that produced the graph edges, so a
  dictionary cannot disagree with use. The canonical run still re-proves
  closure, and the independent checker enforces exact
  operators-equal-dictionary per stream.
- *Ownership conflict/missing association*: placement ownership is inherited
  from the containing owned scene group, so a placement cannot declare a
  conflicting or absent owner. The reachable guards are tested instead:
  duplicate fragment ownership, the graph's `SemanticOwnershipMerge`, and the
  text-form owner resolution rejections.
- *Unbalanced graphics state*: `q <matrix> cm /XOn Do Q` is one lowering unit
  and marked-content wrappers close per group, so imbalance cannot be
  authored; the checker still counts q/Q, BDC/EMC, and BT/ET pairs.

## Evidence

Roc `expect` coverage lives beside each module and in the two evidence
modules. Harness cases (`tests/spec.json`, scenario revision
`gate4-form-xobjects-v1`, measured on the pinned dev backend at
`before_fixture_main`; `arm64mac` recorded equal to the measured `x64musl`
values, matching the suite convention):

| Case | Allocations | Selected counters |
| --- | ---: | --- |
| showcase (adversarial fwd+rev) | 4778 | authored 9 → canonical 5, semantic placements 5, artifact 4, MCIDs 5 |
| unique input | 2390 | one pipeline run, identical counters and bytes |
| retained input | 4754 | two pipeline runs over one retained input, identical bytes |
| repeat x100 | 4105 | placements 100, one physical form, form bytes 39 |
| repeat x1000 | 32536 | placements 1000, one physical form, form bytes 39 |
| dag x8 | 4344 | 12 canonical forms, 32 nested edges, 44 nested dict entries |
| dag x32 | 12957 | 36 canonical forms, 128 nested edges, 164 nested dict entries |
| deep x64 | 13406 | 64-deep legal chain, iterative planning and recipes |
| text in form | 1557 | 8 glyphs/mappings, form dict carries the font, 2 rejections |
| atomic negatives | 2222 | 22 distinct rejections, 0 escaped plans |

What the scaling shows: repeat isolates per-placement cost (do_operators,
graphics pairs, ownership sweep, and content bytes scale 100 → 1000 while
canonical forms, recipes, digests, dictionaries, and objects stay fixed); dag
isolates per-form and per-direct-edge cost (all placement, edge, dictionary,
recipe, and graph counters scale exactly 4x from 8 to 32 parents while the
four shared bases stay four); deep proves the traversal is per-node plus
per-edge over a chain no recursive implementation could hide. `unique` versus
`shared` is the retained-input ARC cost (2390 versus 4754) with byte-identical
output. `copied_form_bytes` is 0 everywhere; `retained_identity_bytes` is the
canonical run's identity allocation (leaf payload copies plus recipes), and
form content bytes are Generated payloads owned by the object store until
emission — they are never shared as seamless resource chunks, so the
unique/retained pair is the applicable retention evidence.

Every fixture regenerates byte-for-byte across repeated runs, and the
adversarial reversed authoring is byte-compared inside the showcase scenario
itself. `qpdf --check` (12.3.2) passes every snapshot with no warnings.

Independent structural checking is `scripts/check_gate4_forms.py`; pinned
rendering, extraction, and the version-scoped nested-form depth limits of the
pinned readers are `scripts/check_gate4_form_renderers.py`. The showcase,
repeat, and DAG rasters are constructed independently from the typed
scenarios and match PDFium Chromium 7988 and PDFBox 3.0.8 with zero pixel and
zero channel tolerance; the text-in-form fixture reproduces the Gate 3 text
ink metrics and extracts exactly its logical text, and the artifact-only
showcase extracts nothing.

MuPDF 1.28.2 is vendored as its exact upstream source archive
(`vendor/mupdf/`), and veraPDF greenfield 1.30.2 as its signed upstream
installer (`vendor/verapdf/`); `scripts/provision_extended_tools.py` verifies
both against `assets/provenance.json` and builds/installs them without
network access. With `--mutool`, the renderer checker runs MuPDF as the
extended-diversity third renderer: it matches the same independent rasters
with zero tolerance through its pinned CalGray handling (MuPDF displays the
linear CalGray luminance ISO 32000-2 defines through the sRGB transfer curve
per ICC channel, where PDFium and PDFBox map CalGray directly to device
gray — the exact per-value triples are pinned, including the vector/image
rounding split at 128 and the green-channel offset at 192), reproduces the
text metrics and extraction, and holds its own pinned nesting limit (renders
a 60-deep chain, fails outright from 61 with an exception-stack limit error,
versus PDFium's silent stop at 40 and PDFBox's logged stop at 50). Poppler
remains unvendored — upstream publishes no pinned artifact and MuPDF fills
the diversity role.

veraPDF is provisioned but deliberately not wired into this slice's
evidence: this slice claims `Pdf20`/`Standard` only. As a one-off smoke
check, veraPDF 1.30.2 parsed the showcase and text fixtures completely under
an explicit `--flavour 4` run and reported exactly one failed PDF/A-4 rule —
6.7.2.1-1, the missing XMP metadata stream that is precisely the deferred
Gate 4/5 capability. That run is recorded as tool validation, not as any
conformance claim; its evidence lane begins with the XMP and PDF/A slices.

The compiler-defect workaround in `Gate4FormTextEvidence` (all const-evaluable
analysis/inspection/shaping calls live in one `build_prelude` body) is
documented in the module; it works around the pinned nightly's multi-body
packed-constant restore defect (roc-lang/roc#10697 family) without changing
any contract.
