# production-visual navigation: links, destinations, outlines, page labels, and annotation appearances

This records the design, semantics, ownership model, complexity, and
evidence for the final production-visual capability slice: URI and internal GoTo link
annotations, typed named internal destinations pairing a semantic structure
target with an explicit layout anchor, document outlines, page labels, and
normal annotation appearances through the shared scene/resource pipeline —
end to end on both the canonical production-visual kernel path and the public `Pdf`
facade. It is built on the resource graph
([resource-graph.md](resource-graph.md)), the Form XObject
machinery ([form-xobjects.md](form-xobjects.md)), the
canonical leaves and font bundles
([color-image-leaves.md](color-image-leaves.md),
[font-leaves.md](font-leaves.md)), the metadata slice
([metadata-output-intent.md](metadata-output-intent.md)), and
the structural-kernel outline and balanced-index planners
([outline-hierarchy.md](outline-hierarchy.md),
[balanced-indexes.md](balanced-indexes.md)). It does not
close production-visual — the separate closure audit remains — and claims no PDF/A-4
or PDF/UA-2 conformance.

## Capability boundary

Implemented:

- **URI links**: a closed authored action carrying a validated RFC 3986
  byte-string URI (required scheme, checked percent-encoding, printable
  ASCII). The URI is recorded for the reader; nothing dereferences it.
- **Typed internal destinations**: every authored destination names both a
  semantic structure target (`Semantics.NodeId`) and an explicit layout
  anchor occurrence (`Semantics.OccurrenceId`). After layout, the anchor
  resolves through the prepared per-fragment geometry to the exact page and
  top-left point.
- **Internal GoTo actions with paired `/SD` and `/D`**: every emitted GoTo
  carries both the structure destination `[structelem /XYZ x y null]` and
  the geometric destination `[page /XYZ x y null]`, produced from one
  resolved record so the pair cannot disagree. A destination whose anchor
  has no resolvable geometry is rejected — an `/SD`-only link is
  unrepresentable. This implements the pinned Errata Collection 3
  resolutions for pdf-issues #140 and #162.
- **Named destinations**: all authored destinations are named; the registry
  lowers as the catalog `/Names /Dests` name tree over the shared
  fixed-fanout-32 balanced shape, each value a `<< /D … /SD … >>`
  dictionary carrying the identical paired facts. Links still carry their
  direct `/SD` + `/D` pair; outlines resolve through the registry.
- **Outlines**: authored dense preorder with explicit open state, sealed by
  the unchanged structural-kernel `KernelOutline` planner and lowered as the linked
  hierarchy — root visible count, `First`/`Last`/`Prev`/`Next`/`Parent`
  links, signed visible-descendant `Count` facts, UTF-16BE titles, and
  byte-string `/Dest` names. No synthetic balancing items exist.
- **Page labels**: authored ranges keyed by physical page index over the
  closed style vocabulary (`/D`, `/R`, `/r`, `/A`, `/a`, prefix-only),
  first range at page zero, strictly ascending, lowered as the
  `/PageLabels` number tree through the same balanced machinery.
- **Link annotations** carrying: the semantic owner and per-page
  annotation-occurrence identity; page association; normalized `/Rect`;
  fragmented-link `/QuadPoints` in the pinned
  top-left/top-right/bottom-left/bottom-right order, every quadrilateral
  axis-aligned and inside the rect; the typed print flag (`/F 4` or
  `/F 0`); the zero-width border style; optional `/Contents` description;
  logical order (spine rank) and keyboard order (dense per-page
  permutation) as independent explicit data; `/StructParent` keys
  continuing the ParentTree after the content-stream rows; and OBJR kids
  inside the owning structure element.
- **Normal appearances**: an annotation's `/AP /N` references a canonical
  Form XObject from the existing scene/form/resource pipeline. Appearance
  references join both resource-graph runs as closure-only uses (reachable
  without resource-dictionary entries), their dependencies close and
  participate in cycle validation, the bounding box must be exactly
  `[0 0 w h]` with the annotation rectangle's extents under the identity
  matrix, and text-bearing forms are rejected as appearances. Deduplicated
  appearance visuals share one canonical form without merging annotation
  occurrences.
- **Facade authoring**: `Pdf.link`, `Pdf.internal_link`,
  `Pdf.destination_heading`, `Pdf.destination_paragraph`,
  `Pdf.with_outline`, and `Pdf.with_page_labels` (with the same compact
  `Document.Builder` constructors). A facade link block is a paragraph-
  shaped `P` wrapper containing one `Link` node owning the link text; after
  pagination each link lowers to one annotation per page its line runs land
  on, with the page's exact painted line boxes as quadrilaterals and their
  union as the rectangle.

Explicitly not in this slice (structurally unrepresentable or typed
rejections):

- Remote-file destinations, launch/JavaScript/named/arbitrary actions, and
  raw annotation dictionaries: no representation exists in the closed
  `AuthoredAction` union or anywhere else.
- Rollover and down appearances, and annotation types other than links: the
  appearance union is `[NoAppearance, NormalAppearance(FormId)]` and the
  only annotation constructor is the link.
- Appearance authoring through the facade: facade links emit no `/AP`
  (the typed appearance capability is the kernel-path boundary this slice
  fixes); nothing prevents a later slice from surfacing it.
- Outline items without destinations, `/Dest` on link annotations (links
  always use `/A`), and structure-destination-only navigation.
- Any PDF/A-4, PDF/UA-2, or WTPDF claim, and any default-profile change:
  every fixture claims `Pdf20`/`Standard` only. The catalog `/Tabs /S`
  entry every page already carries is unchanged.

## Stage contracts and representations

**Authoring and validation (`KernelNavigation.validate`).** One boundary
validates the whole navigation input against a closed subset and explicit
limits: destination names (non-empty printable ASCII, bounded, per-name
byte scan), URIs, rects and quadrilaterals (checked fixed-point
arithmetic), descriptions, appearance references, outline preorder depth
rules, and label-range ordering. The normalized store is dense and flat:
annotations, destinations, outline entries, and label ranges in fixed-shape
lists; name and URI bytes in single flat buffers addressed by
`(start, length)` ranges; quadrilaterals in one flat buffer addressed by
per-annotation spans. Name identity is deterministic: a stable bottom-up
merge sort orders destination indices by unsigned byte order
(`O(n log n)` worst case on sorted, reverse-sorted, and equal input),
adjacent equality rejects duplicates, and actions and outline entries
resolve names by binary search (`O(log n)` per reference). Keyboard order
validates as a dense per-page permutation via one counting sort that also
materializes the documented total annotation order (page, then keyboard
order) and its per-page prefix sums.

**Semantics and tagging.** `KernelSemantics.build_navigation` /
`build_text_navigation` accept the annotation store the contract-definition types always
declared: dense identities, owners in range, exactly one
`AnnotationOccurrence` spine item per annotation inside its declared owner,
and a logical order equal to the annotation's rank among spine occurrences
— all inside the existing one-pass ownership walk. The `Link` role joins
the accepted set only on this path; the plain entry points keep rejecting,
so a path that cannot lower annotation objects fails structurally
(`AnnotationObjectUnplanned`) rather than dropping a link. `KernelTagged`
lowers annotation occurrences as first-class `AnnotationChild` kids in
exact spine order — they never consume an MCID — and exposes dense
annotation-owner and occurrence-owner maps so later stages consume
ownership facts instead of re-walking the spine.

**Destination resolution (`KernelNavigation.resolve`).** Post-layout, each
destination resolves through its anchor occurrence's first layout fragment
to `{page, left, top}` using a dense per-fragment anchor-rect list derived
from the prepared geometry, and through its target node to the structure
element. The pairing is validated, not assumed: the anchor occurrence's
owning node must be exactly the semantic target
(`DestinationTargetMismatch`), and missing geometry is
`UnresolvedDestinationAnchor`. One resolved record feeds `/D`, `/SD`, and
the named-destination value, so the paired facts are identical by
construction.

**Object planning and lowering (`KernelNavigationObjects`).** Identities
are planned arithmetically after the existing planned count (fonts and the
metadata stream included), in the documented order: annotation dictionaries
in total order, name-tree nodes in breadth-first order, the outline root
and items in authored preorder, label-tree nodes, then the shifted xref.
Every lowered object lands on its planned identity (`ensure_object`), page
`/Annots` arrays and OBJR kids forward-reference the planned annotation
objects (sealing validates every reference), and
`KernelOutputBound` enforces `xref == objects + 1`. The tagged prefix
gains conditional navigation names, the catalog's `/Names`, `/Outlines`,
and `/PageLabels` entries in canonical sorted key order, scalar annotation
ParentTree rows (key → one direct structure-element reference), and the
extended `/ParentTreeNextKey`. The facade's text-layout structure builder
mirrors the production-visual assembler exactly.

**Facade pipeline.** Link and destination records are planned before any
layout (`KernelFacadeSemantics`); the post-layout fragments stage derives
per-run line boxes (baseline origin, exact glyph-advance width, one font
size above the baseline, leading-tall — never less than the size), groups
each link's runs by page into per-page annotations, patches the content
spine with the per-page annotation occurrences, validates the navigation
store once, and revalidates the patched store through the navigation-aware
attach. Documents without navigation take `NoNavigationAuthoring` and stay
byte-identical.

## Complexity and deterministic work

- Validation is linear in destinations + name bytes + annotations + quads +
  URI bytes + outline entries + label ranges, plus the `O(n log n)` name
  sort and `O(log n)` per name reference; counters report each dimension
  (`destinations_checked`, `name_bytes_checked`, `name_ordering_steps`,
  `annotations_checked`, `quads_checked`, …).
- Resolution is `O(destinations)` with exactly one anchor lookup each
  (`anchor_lookups == destinations_resolved`).
- Planning and lowering are linear in annotations, tree nodes, outline
  entries, and label ranges; `KernelOutline` and `KernelIndex` keep their
  documented `O(entries)` / `O(entries + key bytes)` bounds and fixed
  fanout; the ParentTree keeps its counting-sort construction. No stage
  performs comparison-quadratic work; adversarial authored orders
  (reversed destination names, reversed keyboard order) canonicalize
  through the sorts and are byte-compared inside the scenarios.
- The facade adds one linear pass over runs for geometry (glyph advances
  summed once per run), one linear grouping pass, and one linear spine
  rebuild — all `O(runs + spine + annotations)`.
- No inner loop (name comparison, quad emission, tree-node emission,
  `/Annots` construction) allocates or performs ARC work per compared or
  emitted byte. Allocation counts scale with annotations, destinations,
  outline entries, label ranges, and tree nodes, and are recorded per
  scenario in `tests/spec.json`.

## Ownership, copying, and retention

- The navigation input is consumed; the normalized store retains flat
  buffers (name/URI bytes, quads) plus fixed-shape record lists, addressed
  by spans — no per-item runtime structures survive normalization.
- Resolution and lowering read the store, the semantics store, and the
  prepared anchor rects in place; the only copies are the exact name-byte
  and URI-byte ranges lowered into object-store strings.
- Appearance forms follow the existing form-identity retention contract;
  an appearance-only form's recipe is retained by the canonical run like
  any placed form, and one canonical form serves any number of annotations
  (the ×16 sharing scenario pins one form, one recipe, sixteen `/AP`
  references).
- `unique` versus `retained` pins the one-shot path at 2,491 allocations
  against 4,979 for planning the same retained input twice, byte-identical.

## Evidence

`roc test` covers `KernelNavigation` (the accepted subset and every
rejection family with exact offsets, ordering, resolution, and pairing
checks), `KernelSemantics`/`KernelTagged` (annotation ownership, rank, and
K-item lowering), `KernelNavigationObjects` (planned-identity arithmetic),
and the end-to-end facade expects in `Pdf.roc` and
`tests/contracts/pdf_facade.roc`. `NavigationEvidence` runs the whole
canonical pipeline under `./scripts/test.py capability fixture tests`, including the
adversarial showcase byte-compare and the 32-step negative sweep.

Harness cases (`tests/spec.json`, revision
`navigation-annotations-v1`, exact x64musl allocations under the
pinned dev backend; arm64mac carries the same accepted values):

| Case | Dimensions | Allocations | Key counters |
| --- | --- | ---: | --- |
| showcase (adversarial fwd+rev) | 2 pages, 3 annots, 2 dests, 3 outline, 2 labels, 1 appearance | 4,981 | 32 quad numbers, 3 ParentTree rows, 32 objects |
| annots x8 / x64 | keyboard order fully reversed | 2,740 / 15,701 | annotation objects 8→64, quad numbers 64→512, exactly linear |
| quads x32 | one link, 32 quads | 3,918 | 256 quad numbers, 1 annotation object |
| share x32 | 32 links → one destination | 9,385 | 1 destination resolved, 32 GoTo actions |
| appearance x16 | 16 links → one canonical form | 4,930 | 1 canonical form, 16 `/AP` references |
| outline deep x16 / wide x64 | chain / alternating siblings | 1,521 / 2,980 | 17 / 65 outline objects, exact counts |
| names x8 / x40 | reverse-authored registry | 1,974 / 6,384 | 1 → 3 name-tree nodes past the fanout |
| labels x8 | 8 ranges over 8 pages | 2,747 | 1 label node, 40 objects |
| unique / retained | one-shot vs retained input | 2,491 / 4,979 | identical counters and bytes |
| atomic negatives | 32 rejections | 4,577 | 0 escaped plans, carrier bytes only |
| facade output | 3 pages, 1 split link, 4 annots | 44,507 | one authored link → two page annotations |
| facade determinism | built twice | 89,013 | byte_identical 1 |
| facade atomic negatives | 9 rejections | 3,439 | carrier 16,873 |

What the scaling shows: `annots` isolates per-annotation work (annotation
objects, ParentTree rows, quad numbers, and `/Annots` entries scale exactly
8× while destinations, trees, and outlines stay zero); `quads` isolates
per-quadrilateral work at one annotation object; `share` isolates
many-consumers-one-destination (one resolution, one name, 32 paired
actions); `appearance` proves reuse without occurrence merging (one
canonical form and recipe under 16 annotations); `names` crosses the
fanout boundary (one node at 8 entries, three at 40) with reverse-authored
input canonicalizing; `outline_deep`/`outline_wide` isolate per-entry work
across both shapes with exact visible counts; `labels` isolates per-range
work across 8 pages.

The 32 kernel negatives cover every author-facing family: destination name
charset/empty/length/duplicates, target and anchor ranges, the four URI
rejections, unknown names, degenerate rects, inverted and escaping quads,
empty quad lists, page association, keyboard-order range and density,
annotation-count agreement, outline first-depth/jump/unknown-destination,
label zero-start/ascent/start-number, appearance range and geometry,
paired-target mismatch, the unresolvable anchor (the `/SD`-only case),
in-appearance text, semantic owner and logical-order disagreement, the
transactional annotation budget, and the facade's typed
`InvalidNavigation` surfacing — each atomic, each a distinct typed error,
none emitting a byte. The 9 facade negatives repeat the author-facing
families through `Pdf.to_bytes`.

## Independent evidence

`scripts/check_navigation.py` parses the emitted bytes directly and
proves, for all sixteen snapshots: keyboard-ordered `/Annots` arrays
referencing every emitted link exactly once; sorted annotation
dictionaries with the closed action union; **both `/SD` and `/D` on every
GoTo with identical coordinates**, `/D` referencing a real page and `/SD` a
real structure element; the pinned QuadPoints order with every
quadrilateral axis-aligned inside the normalized rect; unique
`/StructParent` keys continuing the ParentTree, scalar rows mapping to the
owning structure element, and that element's OBJR referencing exactly that
annotation with the correct `/Pg`; strictly ascending name-tree keys with
exact non-root `/Limits` and paired `/D`+`/SD` values; outline link
consistency with independently recomputed visible-descendant counts and
registry-resolved `/Dest` names; ascending zero-based page-label keys over
the closed vocabulary; and appearance forms with the exact `[0 0 w h]`
bounding box and identity matrix. Ten length-preserving mutation twins (a
forbidden action type, an `/SD`-only pairing break, an escaping quad,
unsupported flags, StructParent drift, outline count drift, name-order
break, zero-key loss, OBJR target drift, and a duplicated `/Annots` entry)
must each be rejected; the self-test joins `./scripts/test.py`.

`scripts/check_navigation_renderers.py` runs the pinned matrix live.
PDFBox 3.0.8 (`scripts/PdfBoxNavigate.java`) navigates **through the
geometric `/D` fallback alone** — it never reads `/SD` — and its extracted
reports equal the pinned expectations exactly: every kernel-showcase and
facade link's rect, quad count, resolved destination page, and `/XYZ`
coordinates (including the facade's long link fragmenting into page-2 and
page-3 annotations that resolve to the same destination); the expanded
page-label sequences (`i`, `A-5`; `1`, `S-I`, `Annex `, …); and outline
entries resolved to pages through the named-destination registry
(`findNamedDestinationPage`). MuPDF 1.28.2 lists the same outlines with
their `#nameddest=` targets, renders all pages of the multi-page fixtures,
and extracts the facade text unchanged. PDFBox composites the normal
appearance streams: the appearance's inset paints the pinned darker code
(32) inside every annotation rectangle while the page's own paint (96)
shows at the inset border; the pinned PDFium adapter renders page content
without the annotation layer (it does not pass `FPDF_ANNOT`), recorded as
adapter behavior. `/SD` structure destinations are inspected structurally
and are deliberately **not** claimed interoperable — that is the exact
issue-140 posture.

`qpdf --check` (12.3.2) passes every one of the sixteen new snapshots with
no errors or warnings. veraPDF 1.30.2 (`--flavour 4`, diagnostic only)
reports on the metadata-bearing facade fixtures exactly the known deferred
6.7.3-1 (PDF/A identification schema, static PDF/A-4 capability); on the metadata-less kernel
fixtures the expected 6.7.2.1-1 (no XMP authored — author choice under
`Standard`); and on the kernel showcase additionally 6.3.2-2 for the one
deliberately screen-only annotation (`/F 0`): PDF/A-4 requires the Print
flag set, which is precisely a profile-eligibility rule for static PDF/A-4 capability's
`Archive` whitelist, not a PDF 2.0 validity issue. Navigation introduces
no other findings.

## Structurally unrepresentable failure classes

- *A mismatched `/SD`/`/D` pair on a link, a named destination, or between
  a link and the registry*: every emission site consumes one resolved
  record produced by the validated pairing.
- *An `/SD`-only internal link*: emission requires the resolved geometric
  record; an unresolvable anchor rejects the document.
- *A remote-file destination, an arbitrary action, a rollover/down
  appearance, a non-link annotation, or a raw annotation dictionary*: no
  constructor exists at any boundary.
- *A silently dropped link*: an annotation spine item on a plan without
  planned navigation objects is the structured
  `AnnotationObjectUnplanned` rejection.
- *Keyboard order disagreeing with `/Annots`*: the array is emitted from
  the validated dense permutation; `/StructParent` keys and annotation
  objects follow the same total order.
- *An appearance escaping validation*: `/AP` can only reference a
  canonical form from the shared pipeline, closure-checked in both graph
  runs, geometry-checked against the rect, and text-rejected.

## Reviewed rebaselines

All 200 pre-existing snapshots are byte-identical; only allocation counts
moved — 104 cases, between +1 and +14 with +2/+3 the dominant shape (one or
two kernel pipeline runs) and the largest movement on the double-generation
facade determinism case — from three uniform causes recorded per case in
`tests/spec.json`:

- **Every tagged plan allocates its dense annotation-owner and
  occurrence-owner maps** (KernelTagged; +1–2 per plan, including empty
  documents), which every kernel fixture from tagged-visual up shows as +1 to +6
  depending on how many plans the scenario builds.
- **Page dictionaries assemble their entry lists by conditional append**
  (the `/Annots`/`/Group` refactor in KernelPageObjects; a constant
  +0–2 per page batch from list growth).
- **The facade pipeline derives navigation authoring and threads the
  navigation-aware stages** (+7 per facade generation, doubled for the
  build-twice retention cases), and facade phase probes gained +1 for the
  extended stage records.

No deterministic work counter changed anywhere; the deltas are allocation
shape only, and every fixture's bytes regenerate identically.

## Exact remaining production-visual work

The production-visual closure audit remains, as its own follow-up. Every roadmap
capability line of production-visual is now implemented with its evidence: resource
graph, forms, leaves, transparency, soft masks, shadings/patterns, font
leaves, metadata/output intent, and this navigation slice.
