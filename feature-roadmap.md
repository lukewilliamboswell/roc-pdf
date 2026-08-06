# Pure Roc PDF Generation Feature Roadmap

## Purpose

This roadmap expands the architecture in [architecture.md](architecture.md)
from a PDF 2.0 structural kernel to combined PDF/A-4 and PDF/UA-2 output. It is
capability-gated rather than schedule-based. Gates state observable completion
criteria and dependency order; they do not prescribe task ownership or a
calendar.

Once a capability has executable behavior, it is complete only when it:

- Has a typed public representation.
- Preserves every fact required by later stages.
- Is validated internally with stable diagnostics.
- Serializes deterministically.
- Has positive and atomic negative tests.
- Is inspected structurally rather than only rendered.
- Passes every applicable independent oracle and conformance profile.
- Has documented author obligations where quality cannot be machine verified.
- Meets its declared algorithmic-complexity, allocation, ARC, and retained-
  memory contracts in optimized builds.

Gate 0 is different: it defines contracts and test machinery but does not claim
that later PDF behavior exists. For a define-only capability, the applicable
completion criteria are a typed representation where the boundary is public,
preservation of every fact required downstream, documented author obligations,
traceability to pinned standards, and declared complexity/ownership/performance
contracts. Compile checks, schema consistency checks, and harness self-tests may
exercise those definitions. Runtime validation and diagnostics, deterministic
serialization, positive and negative feature behavior, structural inspection,
external conformance oracles, and measured optimized performance become
mandatory only in the gate that implements the behavior. Gate 0 prototypes are
not accepted as substitutes for that later evidence.

No gate permits fallback output, profile downgrade, font substitution, feature
removal, outlining, or rasterization after an error.

## Capability map

```text
semantic/content/fragment contract (Gate 0)
                       |
                       v
             PDF object kernel (Gate 1)
                       |
                       v
        minimal tagged visual kernel (Gate 2)
                       |
                       v
      Unicode text and useful layout (Gate 3)
                       |
                       v
     production resources and graphics (Gate 4)
                       |
              +--------+--------+
              |                 |
              v                 v
      static PDF/A-4       core UA vocabulary
         (Gate 5)             (Gate 6)
              |                 |
              +--------+--------+
                       |
                       v
        PDF/A-4 + PDF/UA-2 closure (Gate 7)
                       |
                       v
       broad production documents (Gate 8)
                       |
                       v
        extended modern vocabulary (Gate 9)
```

Every painted file from Gate 2 onward exercises the tagged-PDF ownership path.
Gates 8 and 9 add accepted features to an already conforming accessible
archive; each added feature must close its own applicable PDF/A-4 and PDF/UA-2
rules before it joins that profile.

## Performance review for every feature slice

A feature slice is the smallest independently reviewable addition within a
gate. Performance is part of its design and completion evidence, not a later
optimization phase. Before its public or normalized representation is fixed,
each slice records:

- Expected input sizes, worst-case complexity, and the deterministic operation
  counters that demonstrate that bound.
- Ownership across every phase, including which values are consumed, shared,
  copied, cached, or retained and when large payload references are released.
- Dense-store, scalar-range, continuation, cache-key, and builder choices,
  including why the representation does not allocate a recursive hot-path
  object per semantic node, glyph, command, token, byte, or PDF object.
- Whether each traversal is a direct dense-buffer loop or a coarse `Iter`
  boundary. An `Iter` hot-path choice requires optimized evidence that its
  allocation, ARC, and dispatch behavior is equivalent or better.
- The expected allocation shape, copied-byte behavior, ARC behavior where
  instrumented, peak live data, cache growth, and error-path diagnostic bound.
- For output-facing work, whether bytes are generated into owned buffers,
  copied into the final contiguous result, or shared as seamless slices of
  individually allocated final-form resources. Retained-slice behavior is part
  of the review.

Completion evidence uses focused, versioned scenarios and at least enough
scaled inputs to distinguish fixed cost, per-document, per-page, per-resource,
and per-item work. Relevant slices add unique one-shot and deliberately shared
input cases, immediate-consumption and retained-output cases, adversarial
ordering, cache hit/miss cases, and both success and bounded-error paths.

For every focused test case, the compiled Roc generator reports the exact
number of Roc allocations. A whole-pipeline case resets the counter before Roc
authoring construction; a phase-specific case resets it at an explicitly named
phase boundary. Python excludes its own work and external validators from that
count. The checked-in performance record identifies the Roc compiler revision,
target, optimization mode, scenario revision, measurement boundary, input
dimensions, exact allocation count, and deterministic work counters. Allocated
bytes, bytes copied, ARC increments/decrements, retained/live bytes, and peak
RSS are also recorded where instrumentation supports them.

Exact allocation equality is enforced only for the pinned compiler, target,
and optimized build; results from other configurations are diagnostic. A count
increase cannot be accepted by mechanically regenerating the baseline: review
must identify its representation or ownership cause and record why the feature
benefit requires it. Decreases are likewise reviewed and recorded deliberately.
Selected inner kernels additionally require zero allocation and zero ARC work
per emitted byte, glyph, path command, or object. Allocation counts do not
replace scaling counters, copied-byte measurements, retention tests, or
controlled timing and memory jobs.

A pinned compiler or target change uses a distinct bulk re-baseline protocol:

1. Run the complete allocation suite with the old and proposed toolchains on
   the same controlled host, target, optimization mode, scenarios, and inputs.
2. Compare the full distribution, investigate every outlier, and inspect a
   representative sample from each subsystem and allocation shape.
3. Confirm deterministic work counters and compare allocated/copied bytes, ARC,
   retained memory, and controlled timing so a toolchain-wide count shift does
   not conceal an architectural regression.
4. Record the compiler/target delta as the shared cause, list any feature-
   caused changes separately, and update `.roc-version`, toolchain metadata,
   and all accepted baselines atomically.

This protocol permits reviewed bulk acceptance of a compiler-caused shift. It
does not permit blanket acceptance when outliers, feature-caused changes, or
algorithmic-counter changes remain unexplained.

Gate completion aggregates the performance records of its slices. A favorable
whole-gate benchmark cannot conceal a regression in a focused scenario, and a
performance concern cannot be deferred merely because the capability is still
within an early correctness gate.

## Gate 0: standards, representation, and test contract

### Capabilities

- Pin ISO 32000-2:2020, ISO 19005-4:2020, ISO 14289-2:2024,
  ISO/TS 32005:2023, WTPDF 1.0, and the selected resolved errata.
- Pin the applicable normative references and data versions for the Unicode
  Standard and UCD, UAX #9, UAX #14, UAX #29, BCP 47/RFC 5646, OpenType, ICC,
  XMP/XML, JPEG, DEFLATE, and other implemented dependencies. Define the
  provenance and licensing contract for language-specific hyphenation data.
- Establish the machine-readable conformance ledger and stable internal rule
  IDs.
- Establish the composable capability matrix for `Pdf20`, `StaticPdfA4`,
  `PdfUa2`, WTPDF accessibility/reuse, and future `PdfA4f`.
- Define the facade mapping `Standard = Pdf20`,
  `Archive = Pdf20 + StaticPdfA4`, and
  `AccessibleArchive = Pdf20 + StaticPdfA4 + PdfUa2`; WTPDF declarations and
  `PdfA4f` remain orthogonal explicit capabilities.
- Define the one-import `pdf.Pdf` facade, `Pdf.to_bytes` default contract,
  `Pdf.to_chunks` encoder contract, and explicit option-taking paths using
  current Roc type-module, associated-item, `Try`, `List(a)`, and package-
  import syntax.
- Define the required high-level author facts—metadata title and language—and
  the stricter default-facade policy that `AccessibleArchive` additionally
  requires a visible semantic document title. Define typed constructors that
  distinguish meaningful content from artifacts without boolean flags.
- Define `Theme` as typed convenience-layout typography, spacing, page-margin,
  and visual policy that cannot carry semantics or weaken conformance.
- Define opaque semantic, content-occurrence, layout-fragment, namespace,
  annotation, and structure identities and exactly one PDF 2.0 `Document` root.
- Define the ordered content spine that interleaves child nodes, direct content,
  annotations, and contextual Artifact nodes.
- Separate contextual Artifact structure nodes from page-content artifacts.
- Define typed namespace identity, namespace-scoped roles, structure
  attributes, ID relationships, and the MathML subtree boundary.
- Represent language, source Unicode, presentation transformations,
  alternative/expanded/replacement/actual/phonetic text, relationships,
  meaningful content occurrences, and page-artifact ownership.
- Link every painted scene group to a layout fragment or page artifact.
- Define the layout measurement, fragmentation, continuation, custom-block,
  and deterministic reference-stabilization contracts.
- Define pre-shaping font planning and the difference between advanced shaped-
  run support, built-in shaping support, and packaged-font coverage.
- Define structured, deterministic diagnostics and transactional failure.
- Define canonical number, ordering, metadata, identifier, and compression
  policies.
- Define a typed, dimension-specific `ResourcePolicy` and phase-lifetime/
  retention rules, including deterministic diagnostic limits.
- Define checked fixed-point `LayoutUnit`, dense-ID/flat-store conventions,
  scalar-range ownership, compact continuation rules, and the policy that
  `Iter` is a coarse traversal interface rather than hot storage.
- Define a consumption-shaped `Document.Builder` for large inputs that writes
  compact authoring stores directly while the simple `List(Document.Block)`
  facade remains available.
- Define per-stage worst-case complexity, exact cache-key, diagnostic-budget,
  and consumption-shaped builder contracts.
- Define the optimized-build performance harness, deterministic operation
  counters, allocation-counter reset boundary, and versioned exact-allocation
  baseline format.
- Define the per-feature-slice performance record and review rule, including
  ownership, ARC/uniqueness, `Iter`/direct-loop, cache, seamless-slice
  retention, scaling, error-path, and baseline-delta evidence.
- Define the versioned scenario protocol between the compiled Roc fixture
  generator and Python.
- Establish the asset provenance manifest.

### Gate evidence

- The typed schemas and contract examples can represent direct paragraph text
  interleaved with a link child and more direct text; one occurrence split
  across pages and streams;
  paint order differing from reading order; page artifacts; and contextual
  Artifact nodes without inferring any relationship.
- The fragmentation contract can represent a custom block continuation without
  losing occurrence identity, and the stabilization contract represents
  success, cycle, and budget exhaustion as distinct outcomes. This is a type
  and invariant review, not evidence that either engine exists.
- Diagnostic schemas assign distinct stable codes to the planned identity,
  ownership, namespace, structure-attribute, language, relationship, font-
  coverage, fragment, cycle, and budget errors without claiming runtime
  detection at this gate.
- The normative corpus and ledger are compiled/versioned package data changed
  only through review; independently pinned external tool versions can be
  upgraded without redefining that baseline.
- The same scenario protocol runs on every supported host.
- Public API examples compile with the pinned Roc compiler and do not require
  imports of advanced layout, scene, font, or conformance modules.
- Flat-store schemas and size/ownership accounting show that repeated
  placements and fragments retain one payload plus scalar IDs/ranges rather
  than requiring payload copies. Executable allocation evidence belongs to the
  gate implementing each store.
- Focused harness self-tests prove that allocation counts exclude Python and
  validator work, reset at each declared whole-pipeline or phase boundary, and
  reproduce exactly for the pinned optimized compiler, target, fixture
  revision, and measurement boundary.
- A deliberately introduced allocation regression fails the baseline check,
  while scaling fixtures demonstrate that deterministic work counters catch a
  complexity regression even when allocation counts remain unchanged.

## Gate 1: PDF 2.0 structural kernel

### Capabilities

- PDF 2.0 header and binary marker.
- Canonical lexical forms for booleans, integers, finite reals, names, byte
  strings, text strings, arrays, dictionaries, references, and streams.
- Direct and indirect objects with generation number zero.
- Catalog, page tree, page objects, content streams, resources, and trailer
  information.
- Xref streams, `startxref`, and end-of-file marker.
- Flate streams through the private package-owned stateful compressor seam;
  the independent Python checker uses zlib to reconstruct the exact emitted
  payload, while the package dependency graph remains compressor-free.
- Stable object allocation, resource naming, stream length handling, and file
  identifiers.
- Deterministic fixed-fanout balanced builders for page, name, number, ID, and
  ParentTree structures, plus deterministic linked outline hierarchies with
  exact ordering/count/limit rules.
- Blank, single-page, and multi-page documents.
- Buffered bytes and the byte-identical pure chunk encoder.
- Flat object/value/edge stores, a consumption-shaped builder, and bulk lexical
  emission without one allocation or `Iter` step per token or byte.
- A compact replayable sealed plan, preassigned indirect stream-length objects,
  stateful deterministic DEFLATE, fixed-width unfiltered xref streams, bounded
  owned generated chunks, and optional seamless slices of validated unchanged
  resource allocations.
- Default consume-and-release chunk sharing plus an explicit owned-chunk
  retention policy; both produce byte-identical output.
- Checked arithmetic and explicit size/depth limits.

### Gate evidence

- White-box tests independently recalculate every object offset and stream
  length.
- qpdf exits successfully with no warnings or recovery.
- A named and version-pinned Arlington checker reports zero violations for
  every object within its documented scope.
- A designated strict parser reports no warnings or recovery and asserts the
  expected page/object facts. Additional readers provide separately recorded
  interoperability evidence against the original bytes.
- Identical inputs produce identical hashes across supported systems.
- Negative twins cover malformed numeric values, duplicate keys, bad
  references, offset/count overflow, invalid names/strings, non-monotonic tree
  keys, bad limits/counts, and size limits.
- Stress fixtures exercise thousands of pages and large name, number, ID,
  ParentTree, and outline structures without changing the documented
  representation rule.
- Buffered/chunked and shared/owned-chunk hashes agree; a counting sink verifies
  offsets beyond 4 GiB; output-bound proofs prevent late encoder errors.
- Retained-chunk tests demonstrate that seamless slices pin the actual source
  backing allocation and no package-created whole-document resource arena,
  that the encoder releases its reference after the final range, and that
  owned-chunk mode bounds output-chunk retention independently of source-
  resource size. A fixture whose resource input is itself a small seamless
  slice of a large caller allocation makes the caller-retention tradeoff
  explicit.

## Gate 2: minimal tagged visual kernel

### Capabilities

- Page media, crop, bleed, trim, and art boxes where applicable.
- Page rotation and a documented coordinate/unit model.
- Balanced graphics-state groups.
- Affine transforms.
- Lines, rectangles, cubic Bezier paths, fills, strokes, and clipping.
- Line widths, caps, joins, miters, and dash patterns.
- Typed grayscale and RGB colors.
- Raster grayscale/RGB images.
- Bounds-checked JPEG inspection and sanitized embedding for supported forms.
- Resource reuse across scene groups and pages.
- One PDF 2.0 `Document` root, `P`, the PDF 2.0 namespace, marked content,
  MCIDs, `StructTreeRoot`, structure elements, and ParentTree construction.
- Fragment ownership for all meaningful paint and typed page artifacts for all
  other paint.
- One contextual Artifact structure element.
- Logical structure order independent of page paint order.
- Flat scene-command, occurrence, and fragment stores with the reverse
  occurrence index built by counts and prefix sums.

### Gate evidence

- Analytical geometry fixtures assert path and transform results independently
  of rasterization.
- PDFium and at least one non-PDFium renderer agree on dimensions and geometry
  within declared, feature-specific tolerances.
- Simple pixel fixtures have independently constructed expectations rather than
  another PDF generator as their oracle.
- Negative twins cover unbalanced or invalid geometry, non-finite operands,
  invalid page boxes, invalid image dimensions/channels, malformed JPEGs,
  invalid semantic/content/fragment identities, orphan/duplicate MCIDs,
  missing ParentTree entries, unowned content, and confusion between page and
  contextual artifacts. Each rejection has a stable diagnostic and emits no
  bytes.
- A normalized structure representation asserts exact mixed `/K` order rather
  than only tree parentage.
- A million-command stress fixture has bounded stack use, linear visits, and no
  payload duplication per placement.

### Closure status

Gate 2 is closed. The capability, negative, exact-structure, renderer, and
performance aggregation is recorded in
`docs/performance/gate-2-closure.md`. This closes the private minimal tagged
visual kernel only; it does not make Gate 3 authoring or later conformance
profiles available.

## Gate 3: searchable international text and useful layout

This is the first genuinely useful public document milestone.

### Capabilities

- Bounds-checked TrueType-flavoured OpenType parsing.
- Deterministic font planning from exact theme faces, declared coverage,
  script, language, embedding rights, and font instance.
- Font identity, metrics, widths, embedding rights, and exact instance
  selection.
- Type 0 fonts, CID descendants, CID assignment, and embedded font programs.
- Whole-font embedding followed by deterministic subsetting.
- Composite-glyph closure and deterministic subset prefixes.
- Positioned glyph runs carrying source Unicode, clusters, language, script,
  direction, advances, offsets, and source-to-presentation transformations.
- `ToUnicode` CMaps and explicit `ActualText` handling where mappings are
  context-dependent.
- Complete extraction mappings for every emitted character code.
- Explicit rejection of restricted embedding, unsupported font programs,
  missing glyphs, `.notdef`, invalid clusters, or absent Unicode evidence.
- A small convenience shaping/layout path may initially support a constrained
  explicitly declared script set, while the PDF boundary accepts fully shaped
  multilingual runs.
- Line breaking and grapheme-cluster font selection use the pinned UAX #14 and
  UAX #29 data and rules. Any automatic hyphenation uses only explicitly
  supported language pattern sets whose revision, license, digest, and
  deterministic normalization are recorded in the asset manifest.
- The `Pdf.document`, title, heading, paragraph, list, built-in theme,
  single-column pagination, explicit breaks, keeps, widow/orphan policy, and
  `Pdf.to_bytes` facade provide a useful one-import path without exposing
  glyphs, scenes, resources, profiles, or object plans.
- Compact cursor continuations, speculative measurement separated from final
  page materialization, and exact bounded caches for font parsing/coverage,
  shaping, measurement, and hyphenation.
- Font-table offset/range views, once-per-face coverage/`cmap`/GSUB/GPOS data,
  contiguous glyph buffers, global used-glyph accumulation, and once-only
  composite closure/subset-table emission.
- At this gate `Pdf.Options.default` selects public profile `Standard`, whose
  claim set is `Pdf20`. `Pdf.Options.with_profile` is the only way to request a
  different implemented profile; incomplete `Archive` or `AccessibleArchive`
  claims remain unavailable.

### Upstream Unicode coordination

The preferred pure Roc Unicode building blocks are tracked as independently
resolvable issues in [`roc-lang/unicode`](https://github.com/roc-lang/unicode).
These links coordinate reusable dependency work; they do not replace this
roadmap's capability gates or evidence. Before adopting any result, pin its
exact release asset or revision and digest, record its Unicode data provenance,
and verify the applicable correctness, ownership, allocation, and deterministic
work requirements locally.

| Upstream issue | Reusable boundary |
| --- | --- |
| [#36: Unicode 17 upgrade and auditable versioning](https://github.com/roc-lang/unicode/issues/36) | One synchronized Unicode/UCD/UAX data version, source manifest, deterministic generation, and public version identity. |
| [#35: Unicode 17 extended-grapheme conformance](https://github.com/roc-lang/unicode/issues/35) | Complete un-tailored UAX #29 grapheme boundaries, regressions, official conformance tests, and fuzzing. |
| [#37: zero-copy grapheme byte ranges](https://github.com/roc-lang/unicode/issues/37) | Source-preserving UTF-8 boundary ranges and an allocation-conscious walk API for cluster-based font selection. |
| [#38: Unicode 17 line-break opportunities](https://github.com/roc-lang/unicode/issues/38) | UAX #14 boundary analysis, explicit tailoring, and validated seams for separately versioned complex-context analyzers and hyphenators. |
| [#39: Unicode 17 bidirectional analysis](https://github.com/roc-lang/unicode/issues/39) | UAX #9 levels, logical and visual mappings, directional runs, per-line reordering, brackets, and mirroring facts. |
| [#41: Script and Script_Extensions](https://github.com/roc-lang/unicode/issues/41) | Normative Unicode script properties plus an explicitly named, non-normative script-itemization policy. |
| [#42: panic-free, resource-bounded public APIs](https://github.com/roc-lang/unicode/issues/42) | Typed failure, checked limits, bounded traversal, adversarial tests, fuzzing, and documented allocation/copy/retention behavior. |
| [#43: bounded shaping-oriented Unicode properties](https://github.com/roc-lang/unicode/issues/43) | Generated UCD properties needed by independent text engines without moving OpenType parsing or shaping into the Unicode package. |

Language-specific hyphenation data remains a separate licensed and pinned
dependency. OpenType parsing, GSUB/GPOS processing, glyph selection, and shaping
remain separate pure Roc components; the upstream Unicode issues provide facts
and analysis boundaries rather than those font-specific behaviors.

### Gate evidence

- Each independent extractor matches an explicit normalized expectation for
  that extractor's API; agreement between engines is not the oracle. CID,
  `ToUnicode`, cluster, and `ActualText` relationships are also inspected
  directly.
- Rendering and extraction fixtures cover combining marks, ligatures,
  supplementary-plane characters, right-to-left runs, reordered glyphs, and
  CJK subsets within the declared advanced boundary.
- Extraction fixtures cover discretionary and soft hyphens, generated labels,
  case transformations, and bidirectional logical/visual order.
- Embedded font programs and subsets pass independent font validation and have
  the exact glyph closure expected.
- Font widths, glyph positioning, CID maps, and Unicode maps are structurally
  inspected.
- Negative twins cover license restrictions, corrupt/overlapping tables,
  composite cycles, integer overflow, invalid composite closure, uncovered
  scalars, unsupported shaping, ambiguous mappings without `ActualText`, and
  undeclared glyph use. Font coverage and shaping failures have stable
  diagnostics and emit no bytes.
- Unicode fixtures pin UAX #14 line-break and UAX #29 grapheme boundaries,
  including version-sensitive cases. Each supported hyphenation language has
  revision-pinned positive, negative, extraction, and determinism fixtures.
- Compile-checked public examples pin modern Roc syntax and assert that the
  default and explicit-option entrypoints produce the intended profile.
- Facade-list and compact-builder authoring benchmarks include construction
  allocations and establish the intended large-document path.
- Adversarial paragraph, line-break, font-selection, shaping, and single-column
  pagination cases meet their declared operation-count bounds; accepted page
  scenes are materialized once.

## Gate 4: production visual document model

### Capabilities

- Form XObjects and deterministic resource deduplication without merging
  placement-specific semantic associations.
- Transparency, soft masks, opacity, and isolated groups required by supported
  scenes.
- Linear and radial shadings and supported tiling patterns.
- Raster images with alpha and explicitly supported color forms.
- ICCBased sRGB, calibrated grayscale, the packaged sRGB profile, output
  intents, Normal blending, constant opacity, alpha soft masks, and isolated
  groups where required.
- XMP metadata with canonical serialization.
- Document language.
- URI links and typed internal destinations that pair a semantic structure
  target with an explicit layout anchor.
- Internal GoTo actions containing both `/SD` and a deterministic post-layout
  geometric `/D` fallback. Named destinations provide a reusable authored-name
  registry for outlines, cross-references, and public destination names; they
  do not replace the pair on link actions.
- Outlines, page labels, and supported annotations.
- Annotation appearances produced through the same scene/resource pipeline.
- Explicit direct-edge resource dependency DAG with cycle rejection, closure
  proof, deterministic topological planning, and complete direct resource
  dictionaries without materialized all-pairs reachability.
- Sanitized font subsets, JPEG streams, and ICC profiles built from supported
  allowlists rather than arbitrary container passthrough.
- Link annotation page association, rectangles, quadpoints, normal appearance,
  display/print flags, OBJR, semantic and keyboard order.
- Packed raster planes and row/chunk decode, alpha, predictor, color, hash, and
  compression stages that avoid simultaneous full-size intermediate copies.

### Gate evidence

- Before the sRGB asset becomes a dependency, its exact profile revision,
  digest, and license explicitly permitting redistribution and embedding in
  generated PDFs are recorded and tested.
- A cross-renderer matrix covers transparency, masks, gradients, patterns,
  forms, image alpha, and color management.
- Metadata, output intents, image profiles, blending spaces, links,
  destinations, outlines, labels, and appearances are inspected structurally.
- Structural inspection confirms every internal GoTo has matching `/SD` and
  `/D` targets and every applicable named-destination dictionary carries the
  same paired facts. Independent processors must navigate successfully through
  the geometric fallback; `/SD` support is recorded separately and is not an
  interoperability prerequisite.
- Reused resources are byte-deterministic and confirmed equal, not merely hash
  collisions.
- Digest-collision buckets use deterministic descriptor/length partitioning and
  bytewise radix/trie ordering with adjacent exact equality; white-box
  collisions meet the declared entry/byte work bound rather than all-pairs
  comparison.
- Negative twins cover resource cycles and missing nested resources, invalid
  ICC/JPEG/font data, conflicting JPEG orientation, uncharacterized color,
  unsupported blend behavior, remote-file destinations, malformed annotation
  ownership/appearance/OBJR/quadpoints, `/SD`-only internal links, mismatched
  structure/geometric targets, missing layout anchors, and forbidden actions.
  Supported URI actions are not external rendering resources.

The initial profile does not include CMYK, Separation/DeviceN/spot color,
overprint, luminosity masks, non-Normal blending, rollover/down annotation
appearances, or annotation types other than links.

## Gate 5: static PDF/A-4

### Capabilities

- Represent every applicable PDF/A-4 requirement in the conformance ledger.
- Enforce the static profile's supported-feature whitelist.
- Embed every font, non-predefined CMap, ICC profile, and required resource.
- Ensure complete resource closure with no external dependencies.
- Emit correct XMP PDF/A identification and consistent metadata.
- Emit explicit file identifiers and output intent.
- Apply static-profile rules to page content, forms, transparency, images, and
  annotation appearances uniformly.
- Reject encryption, external visual/file references, incremental history,
  deprecated features, forms, JavaScript, optional content, multimedia, 3D,
  and attachments under package policy. Supported URI link actions remain
  annotation data rather than rendering dependencies.
- Keep PDF/A-4f and PDF/A-4e outside this capability.
- Advance `Pdf.Options.default` to public profile `Archive`, whose claim set is
  `Pdf20 + StaticPdfA4`; failure returns a structured error and never falls
  back to `Standard`/ordinary PDF 2.0.

### Gate evidence

- Every positive fixture passes veraPDF explicitly as PDF/A-4 with zero failed
  checks.
- Every package negative twin is rejected internally with no bytes. External
  invalid PDFs are confined to pinned validator corpora and must fail the
  intended external rule; false PDF/A metadata is itself a failure.
- The upstream veraPDF PDF/A-4 corpus verifies that the pinned validator returns
  its expected pass/fail results.
- All machine requirements in the ledger have positive and negative coverage.
- A pinned renderer/version matrix processes the original bytes with the
  declared error policy and meets fixture-specific page-size, geometry, pixel,
  and color tolerances.

## Gate 6: core PDF/UA-2 vocabulary

### Capabilities

- PDF 2.0 document title, document, document fragment, part, division, section,
  numbered heading, paragraph, and inline semantics.
- Emphasis, strong, quotation, and code.
- Lists with explicit item, label, and body relationships.
- Figures and captions with author-supplied alternatives.
- Simple tables with captions, logical grids, spans, header cells, scope, IDs,
  and explicit header associations.
- Links, link annotations, paired structure and geometric destinations, and
  OBJR ownership. `/SD` expresses the semantic target while `/D` preserves
  navigation in readers that do not implement structure destinations.
- XMP `dc:title` agreeing with the authored metadata title and catalog
  `/ViewerPreferences` with `/DisplayDocTitle true`.
- Required catalog `/MarkInfo` and per-page `/Tabs` entries and values, driven
  by explicit PDF/UA-2 ledger requirements.
- Page- and stream-spanning occurrences and exact mixed structure order.
- Page-content artifacts and contextual Artifact structure elements.
- Language inheritance and nested language changes.
- Alternative, expanded, replacement, actual, phoneme, and phonetic-alphabet
  text where applicable.
- IDTree construction and typed structure references.
- Author-obligation diagnostics distinct from mechanically proven facts.

### Gate evidence

- A project-owned normalized structure representation is compared independently
  of PDF object numbers.
- Every MCID and object reference is reachable bidirectionally through the
  ParentTree and semantic graph exactly once as required.
- Fixtures intentionally separate paint and reading order, split semantic nodes
  across pages, interleave direct content and children, reuse visual resources,
  and repeat page artifacts.
- The legal and illegal namespace-containment matrix is tested.
- Negative twins cover duplicate/orphan MCIDs, missing ParentTree entries,
  unowned content, artifact-kind confusion, missing IDTree entries, role-map
  cycles, illegal namespace/containment/attributes, invalid language
  inheritance, broken table headers, and untagged annotations.
- Structure-tree extraction agrees across independent inspection paths.
- Structural inspection verifies `dc:title`, `DisplayDocTitle`, `/MarkInfo`,
  and every applicable page `/Tabs` value. Atomic negative twins omit or
  mismatch each requirement independently.
- For every internal link, `/SD` resolves to its semantic target, `/D` resolves
  to the post-layout geometry of the declared anchor, and both identify the
  same authored destination.
- Human-reviewed scenarios cover reading order, heading navigation, lists,
  links, figures, simple tables, nested language, and artifact behavior.
- Human protocols pin AT/reader versions, tasks, expected observable navigation
  outcomes, and assessor sign-off. They do not require identical synthesized
  speech or UI output.
- Negative twins cover missing or empty required alternatives, misleading
  structure relationships detectable mechanically, skipped ownership, missing
  Unicode, bad heading representation, inaccessible annotation structure,
  invalid namespace/attribute/language/relationship facts, and missing or
  mismatched destination pairs. Each failure has a stable diagnostic and emits
  no bytes.

Unsupported semantic constructs are rejected; they are never flattened into
paragraphs or figures.

## Gate 7: PDF/UA-2 closure and combined accessible archive

### Capabilities

- Audit every PDF/UA-2 and applicable ISO/TS 32005 requirement against the
  conformance ledger for the explicitly supported Gate 0-6 vocabulary.
- Build that audit clause-by-clause from the pinned standards and errata; the
  requirements named in the architecture and roadmap are cross-checks, not the
  source or an exhaustive checklist.
- Classify every requirement as applicable, inapplicable because the feature is
  rejected, machine-verifiable, human-verifiable, or both.
- Cover every applicable machine-verifiable requirement with positive and
  atomic negative tests.
- Represent every applicable human-verifiable requirement in the author
  assertion and accessibility-review protocols.
- Validate combined `StaticPdfA4 + PdfUa2` output independently against both
  profiles.
- Support the WTPDF accessibility declaration where its requirements and
  declaration rules are met; keep WTPDF reuse separate.
- Make `AccessibleArchive` the enduring default used by `Pdf.to_bytes`.

### Gate evidence

- Explicit veraPDF runs pass `4`, `ua2`, and `wt1a` as applicable; metadata
  autodetection is not the only test.
- Arlington and independent object/file checks pass every produced fixture.
- Text, semantic, navigation, rendering, and metadata inspection all agree with
  the authored scenario.
- Cross-platform generation produces identical bytes.
- The release accessibility protocol completes expert and representative
  assistive-technology review.
- The conformance ledger contains no unexplained applicable or untested clause.
- The published claim distinguishes package guarantees, author assertions, and
  human judgment.

At this gate the package may produce conforming PDF/UA-2 for its supported
feature subset. It does not need to accept every PDF feature, annotation type,
or structure role; unsupported inputs remain errors.

## Gate 8: broad production documents

### Capabilities

- Complex tables with row groups, spans, repeated headers, and continued
  structures.
- Page templates, multi-column layout, floats, footnotes, side content, and
  explicit logical order.
- Cross-references, generated tables of contents, indexes, page labels, and
  deterministic layout stabilization.
- Notes, references, bibliographies, captions, and richer inline semantics.
- Accessible custom layout blocks and validated vector-scene integration.
- Broader explicitly declared script/font coverage and vertical writing where
  the shaping and layout boundary supports them.
- Reusable forms, transparency, gradients, and patterns only within their
  independently closed capability subsets.

### Gate evidence

- Table fixtures cover spans, IDs, scopes, headers, fragmentation, repetition,
  and invalid intersections.
- Reference layouts cover convergence, cycles, and budget exhaustion without
  accepted approximations.
- Custom-block fixtures fragment across columns and pages while preserving
  occurrence identity, typed continuation state, semantic ownership, and
  bounded operation/allocation evidence.
- Human AT review covers table navigation, multi-column order, footnotes,
  references, and mixed language/direction.
- Every accepted capability preserves Gate 7's full applicable-requirements
  closure and combined-profile validation.

## Gate 9: extended modern accessibility vocabulary

### Capabilities

- Typed MathML structure subtrees.
- Associated-file MathML only through a separate PDF/A-4f attachment
  capability.
- Ruby, warichu, advanced vertical and mixed writing modes, and mixed scripts.
- Color-font and emoji support through explicitly selected supported formats.
- Additional annotation types, each with complete structure, appearance,
  navigation, focus, and conformance rules.
- Extension namespaces and specialized standard roles.
- WTPDF reuse only after its separate ledger is complete.
- Optional advanced print-color capabilities independently of accessibility.

### Gate evidence

- MathML element/attribute namespace and containment tests cover positive and
  atomic negative cases.
- Base PDF/A-4 and PDF/A-4f math cases validate the exact selected attachment
  policy; structured math is never replaced with alternate text.
- Human AT review covers mathematics, ruby/warichu, vertical/mixed writing, and
  new annotation interactions where implemented.
- Each new role, namespace, text system, and annotation closes all applicable
  PDF/A-4/PDF/UA-2/WTPDF requirements before joining a declared profile.
- WTPDF reuse remains unclaimed until its independent audit has no unexplained
  applicable clauses.

## Independent test tools

The Python harness pins exact versions, preferably by container digest, and
runs without network access under time, memory, and output limits. Raw reports
and rendering differences are retained on failure.

| Tool | License | Role | Boundary |
| --- | --- | --- | --- |
| [qpdf](https://github.com/qpdf/qpdf) | Apache-2.0 | Lexical, xref, stream, and JSON inspection | A clean check is not full PDF conformance |
| [pikepdf](https://github.com/pikepdf/pikepdf) | MPL-2.0 | Convenient Python object inspection | It uses qpdf and is not an independent parser |
| [Arlington PDF Model](https://github.com/pdf-association/arlington-pdf-model) | Apache-2.0 | Specification-derived PDF 2.0 object schema | It excludes important lexical, content-stream, and file-layout rules |
| [veraPDF](https://docs.verapdf.org/validation/) | MPL-2.0 or GPL-3.0-or-later | PDF/A-4, PDF/UA-2, and WTPDF validation | PDF/UA coverage is machine-verifiable checks only |
| [PDFium](https://pdfium.googlesource.com/pdfium/) | BSD-style | Rendering, text, annotations, and navigation | Reader behavior is not conformance proof |
| [PDF.js](https://github.com/mozilla/pdf.js) | Apache-2.0 | Independent browser rendering and interaction | Tolerant recovery may conceal malformed input |
| [Apache PDFBox](https://pdfbox.apache.org/) | Apache-2.0 | Independent rendering and Unicode extraction | Its preflight is not the modern conformance oracle |
| MuPDF or Poppler | AGPL/commercial or GPL | Extended renderer and extraction diversity | Review licensing before distributing CI images; multiple Poppler backends are not independent parsers |
| Ghostscript | AGPL-3.0 or commercial | Advanced color and print rendering | Use only for capabilities with pinned color/profile settings |

PDFium and PDFBox both participate in ordinary CI. PDF.js adds browser text,
annotation, and structure-layer coverage. MuPDF or Poppler participates in
extended graphics CI, and Ghostscript is used for declared advanced color or
print capabilities. More engines increase diversity but do not vote on
correctness.

The harness never passes a rewritten qpdf or pikepdf output to later checks.
Every oracle receives the exact bytes emitted by Roc.

## Reusable corpora and assets

- The [veraPDF corpus](https://github.com/veraPDF/veraPDF-corpus) is available
  under CC-BY-4.0 and contains atomic pass/fail material for modern profiles.
- The PDF Association's
  [PDF 2.0 examples](https://pdfa.org/pdf-2-0-examples-now-available/) are
  CC-BY-SA-4.0. Unmodified examples may be studied; derivatives retain the
  required attribution and ShareAlike terms.
- The
  [Accessible PDF Techniques](https://github.com/pdf-association/techniques-for-accessible-pdf)
  repository is CC-BY-4.0 and supplies small pass/fail accessibility examples.
- The [PDF/UA reference suite](https://pdfa.org/resource/pdfua-reference-suite/)
  is CC-BY-4.0 and useful for sophisticated tagged-document patterns, but does
  not replace a PDF/UA-2 oracle.
- The [LaTeX Tagged PDF project](https://tagging-project.latex-project.org/)
  and tagpdf examples under LPPL-1.3c are useful for complex structure,
  namespace, artifact, and MathML study. Copying or modifying material follows
  its license rather than the package's default license.
- [Noto fonts](https://notofonts.github.io/noto-docs/website/use/) under
  OFL-1.1 provide fixed multilingual font fixtures.
- Every retained Unicode Character Database file and Unicode conformance test
  file records the Unicode version, exact source path, digest, applicable
  Unicode data license, and whether it is production data or test-only data.
- Hyphenation patterns are selected per language only after license and
  redistribution review. Each normalized production pattern file and its
  upstream source records language, revision, digest, license, attribution,
  transformation procedure, and associated test corpus; system dictionaries
  and unversioned pattern collections are never used.
- The [PDF corpus index](https://github.com/pdf-association/pdf-corpora) helps
  discover additional material, but each corpus requires an independent
  license and safety review.

External PDFs do not pass through the Roc generator. They verify the pinned
oracles, demonstrate structures for study, and inspire independently authored
and attributed Roc scenarios.

Every retained external asset records its source URL, upstream revision,
cryptographic digest, license identifier, required attribution, and whether
modification or redistribution is permitted. The same manifest covers fonts,
ICC profiles, images, Unicode/UCD data, hyphenation patterns, fuzz seeds, and
expected renderings. Isartor files must not be copied into the repository
because their terms prohibit redistribution.

## CI gates

### Per change

- Roc unit tests and typed property tests.
- Deterministic fixture regeneration checks.
- qpdf with warnings and recovery forbidden.
- Structural and semantic assertions.
- Selected independent rendering and extraction.
- Focused veraPDF PDF/A-4 and PDF/UA-2 fixtures for affected capabilities.
- The performance record for every affected feature slice, including scaled
  deterministic work counters and exact Roc allocation counts under the pinned
  optimized compiler and target.
- A reviewed allocation-baseline delta. An unexplained increase or a
  mechanically regenerated baseline fails CI; selected hot kernels also fail
  on per-item allocation or ARC work.
- Focused copied-byte, retention, cache, unique/shared-input, and ARC checks
  whenever the slice changes ownership, representation, traversal, or output
  behavior.
- A `.roc-version`, target, or optimization-policy change runs the documented
  old/new bulk re-baseline protocol; CI rejects an atomic baseline update that
  lacks its toolchain comparison, outlier review, and separated feature deltas.

### Extended

- All renderers and feature fixtures.
- Full explicit veraPDF profiles.
- Arlington validation.
- Upstream corpora used to verify the validators themselves.
- Random small typed scenarios with minimized retained seeds.
- Deterministic corpus-mutation fuzzing of font, JPEG, PNG, and ICC inspectors,
  or coverage-guided fuzzing when reliable Roc coverage is available, under
  input/work/memory/time bounds with minimized failures retained as ordinary
  regression tests.
- Bounded large-document, offset, subset, stream, and structure stress suites.
- Controlled timing, peak-RSS, allocation, copied-byte, time-to-first-chunk,
  and integrated serializer/compressor benchmarks.

### Release

- Cross-platform byte-for-byte reproducibility.
- Published performance evidence from the pinned optimized build, including
  unique and deliberately shared pipeline inputs.
- An audit that every shipped feature slice has a current allocation baseline,
  scaling record, and resolved performance-review decision.
- Full pinned validator and corpus reports.
- Current-reader smoke tests.
- Accessibility expert review.
- Scripted representative assistive-technology journeys.
- Audited conformance ledger with no unexplained coverage gaps for claimed
  capabilities.

## Deliberately separate future expansions

The following do not block PDF/A-4 plus PDF/UA-2 closure and receive separate
capabilities if ever justified:

- PDF/A-4f attachments.
- WTPDF reuse conformance beyond accessibility.
- Alternative replay or spooling surfaces beyond the baseline compact-plan,
  stateful-compression, owned-generated-chunk, and shared-final-resource-slice
  design.
- CFF, CFF2, variable-font instancing, or additional image codecs after the
  initial validated font/image set.
- Forms, signatures, encryption, optional content, JavaScript, multimedia,
  RichMedia, and 3D.
- Linearization, incremental updates, reading, editing, repair, or conversion.

Some of these conflict with the static package policy and may remain
permanently unsupported.
