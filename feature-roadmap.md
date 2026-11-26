# Pure Roc PDF Generation Feature Roadmap

## Purpose

This roadmap delivers the business-document product defined in
[architecture.md](architecture.md): reports, invoices, and business letters
authored through public APIs with combined PDF/A-4 and PDF/UA-2 declarations.
It is capability-gated rather than schedule-based. Gates state observable
completion criteria and dependency order; they do not prescribe task ownership
or a calendar. Gate 7 is the first production-release destination for the
bounded document set below. Gates 8 and 9 are independently justified expansions.

The primary objective is a correct PDF library with deterministic output and
transactional failure. Standards support is best effort. Each slice records
its declarations and implemented checks. Performance evidence exists only to keep the package usable by
catching super-linear or exponential blow-ups; it does not set product speed,
memory, or throughput targets. Project-owned mechanical checks are required.
Independent local tools and human reader or assistive-technology review can
supplement that evidence.

Once a capability has executable behavior, it is complete only when it:

- Has a typed public representation.
- Preserves every fact required by later stages.
- Is validated internally with stable diagnostics.
- Serializes deterministically.
- Has positive and atomic negative tests.
- Is inspected structurally rather than only rendered.
- Passes project-owned checks for the supported structure, resources, and
  declarations it emits.
- Has documented author obligations where quality cannot be machine verified.
- Meets its declared algorithmic-complexity, exact-allocation, deterministic-
  work, and retention contracts under the pinned dev backend.

Gate 0 is different: it defines contracts and test machinery but does not claim
that later PDF behavior exists. For a define-only capability, the applicable
completion criteria are a typed representation where the boundary is public,
preservation of every fact required downstream, documented author obligations,
traceability to pinned standards, and declared complexity/ownership/performance
contracts. Compile checks, schema consistency checks, and harness self-tests may
exercise those definitions. Runtime validation and diagnostics, deterministic
serialization, positive and negative feature behavior, structural inspection,
project-owned profile checks, and exact allocation and work-counter evidence
become mandatory only in the gate that implements the behavior. Gate 0
prototypes are not accepted as substitutes for that later evidence.

No gate permits fallback output, profile downgrade, font substitution, feature
removal, outlining, or rasterization after an error.

## First production release: complete business documents

The first release is judged by correctness: complete business documents that
author through public APIs, lay out predictably, report actionable diagnostics,
and pass the project-owned checks for the supported output profiles.

The [reference document contract](docs/contributors/reference-documents.md)
defines the business-document fixtures, their adverse variants, and the text
and layout policies used by the public facade.

| Reference document | Required authoring and behavior | Representative adverse variations |
| --- | --- | --- |
| Multi-page invoice | Caller-supplied values; address blocks; aligned amount columns; wrapped descriptions; repeated table headers; explicit row-break policy; totals kept together; logo; payment link; page numbers | Long names, identifiers and descriptions; many rows; a row taller than a page; totals near a break; unsupported text and incompatible mandatory keeps |
| Business report | Headings; rich inline text; ordinary tables; bounded vector/image figures and captions; running page furniture; page and total-page numbers; outlines and internal links | A heading or caption near a break; a table continued across pages; a reference value that outgrows its field; supported mixed-language text; oversized figures |
| Business letter | Letterhead and address blocks; paragraphs; controlled spacing and explicit breaks; first-page and continuation-page templates; metadata title without a required visible heading | Long recipient details; multiple pages; template content leaving insufficient body space; omission of visible title while retaining the combined profile |

Each reference declares its exact supported text and layout policies, expected
appearance and reading order, author obligations, optional reader/assistive-
technology review tasks, and a scale case for its growth evidence. Reference
documents and adverse variants are correctness scenarios; workloads exist only
as scale cases. Adverse variants define either an
acceptable layout under an explicitly selected policy or a specific structured
error with no bytes. A valid-looking reference with short placeholder content
alone is insufficient.

The bounded business-authoring scope includes ordinary table continuation,
page templates, bounded flow figures and a measured custom-block seam.
General custom pagination, floats, footnotes and indexes are Gate 8
capabilities.

### Bounded manual authoring

The facade supports authored contents entries with wrapped linked titles,
a shared page-number column and optional decorative leaders. Fixed-width
destination references select decimal page numbers or configured PDF page
labels, which can also appear in furniture. Page scopes are nonnested
full-body-page regions with independently authored opening and continuation
templates and short running labels. The
[manual-composition evidence](docs/contributors/performance/manual-composition.md)
and [contents-entry checks](docs/contributors/performance/contents-entries.md)
exercise these capabilities through the public facade.

List items can contain source blocks, captioned figures, ordinary tables
and bounded callouts after the lead paragraph. Items preserve logical
identity across pages. Native callouts measure and continue at legal
content boundaries, with a decorative rectangular panel on each fragment.
The measured custom-block API has its own unsplittable contract.

The [diagram adapter](examples/vector-diagrams/README.md) exercises checked,
bounded Mermaid/SVG conversion at authoring time through the public
drawing API. General SVG or HTML rendering is outside the package.

### Performance intent

Every focused case keeps its exact Roc allocation count and deterministic work
counters under the pinned build, as described in the performance review below;
these remain mandatory. Every case also records the bytes its Roc allocations
request (`allocated_bytes`, the sum of every `roc_alloc` size and every
`roc_realloc` new size), and a run fails when a case exceeds its recorded value
by more than 10%. The ceiling catches a list copied on every append, which
grows allocated bytes quadratically while the allocation count (one event per
copy) still looks linear. Decreases pass; a reviewed rebaseline lowers the
recorded value. Every scalable feature additionally carries at least one
small/large scale pair whose work counters prove linear or `n log n` growth,
for example a small invoice against a large statement/invoice batch. The goal
of this evidence is to catch super-linear or exponential blow-ups that would
make the package unusable, together with unreviewed representation changes.

There are no numeric latency, peak-memory, throughput, output-size, or
benchmark product targets, and no controlled timing or memory jobs are
required. Timing or memory figures that existing instrumentation happens to
report are diagnostic context, not acceptance thresholds.

## Capability readiness

Every implemented slice records the following dimensions independently, with
evidence links. Each dimension is unavailable, representable-only, executable
with evidence pending, or closed for an explicitly named subset. Inapplicability
requires a recorded reason. Public document features require a closed facade
path; a private compiler primitive may instead justify having no direct facade.

| Dimension | Evidence required for closure |
| --- | --- |
| Backend | Validation, exact lowering, emission, and ownership/performance evidence |
| Facade | Useful end-to-end public authoring, layout, and diagnostics for the declared subset |
| Advanced integration | A supported public boundary exercised by a separately authored consumer, where applicable |
| Profile support | Implemented checks, emitted declarations, and focused tests for the supported subset |
| Reader and AT behavior | Optional: declared observable tasks on pinned readers and assistive technology, recorded where performed; an unperformed review is recorded as such and does not block closure |

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
      static PDF/A-4     business authoring +
                         core UA vocabulary
         (Gate 5)             (Gate 6)
              |                 |
              +--------+--------+
                       |
                       v
       business-document production release
        PDF/A-4 + PDF/UA-2 closure (Gate 7)
                       |
                       v
       advanced document composition (Gate 8)
                       |
                       v
        extended modern vocabulary (Gate 9)
```

Every painted file from Gate 2 onward exercises the tagged-PDF ownership path.
Gates 8 and 9 add features to the existing accessible archive profile. Each
feature documents its supported behavior and tests the rules it implements.

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
- The expected allocation shape, cache growth, and error-path diagnostic
  bound, plus copied-byte, ARC, and peak-live-data behavior where existing
  instrumentation reports them.
- For output-facing work, whether bytes are generated into owned buffers,
  copied into the final contiguous result, or shared as seamless slices of
  individually allocated final-form resources. Retained-slice behavior is part
  of the review.

Completion evidence uses focused, versioned scenarios and at least enough
scaled inputs to distinguish fixed cost, per-document, per-page, per-resource,
and per-item work. Every scalable feature includes at least one small/large
scale pair whose work counters prove linear or `n log n` growth. Relevant
slices add unique one-shot and deliberately shared
input cases, immediate-consumption and retained-output cases, adversarial
ordering, cache hit/miss cases, and both success and bounded-error paths.

For every focused test case, the compiled Roc generator reports the exact
number of Roc allocations. A whole-pipeline case resets the counter before Roc
authoring construction; a phase-specific case resets it at an explicitly named
phase boundary. Python excludes its own work and external validators from that
count. The checked-in performance record identifies the Roc compiler revision,
target, optimization mode, scenario revision, measurement boundary, input
dimensions, exact allocation count, allocated-bytes ceiling, and deterministic
work counters. Bytes copied, ARC increments/decrements, retained/live bytes,
peak RSS, and timing are recorded only where existing instrumentation reports
them; a slice does not need to build new timing or memory instrumentation.

Exact allocation equality and the allocated-bytes ceiling are enforced only
for the pinned compiler, target, and dev backend; results from other
configurations are diagnostic. A count
increase cannot be accepted by mechanically regenerating the baseline: review
must identify its representation or ownership cause and record why the feature
benefit requires it. Decreases are likewise reviewed and recorded deliberately.
Selected inner kernels additionally require zero allocation and zero ARC work
per emitted byte, glyph, path command, or object. Allocation counts do not
replace scaling work counters or retention tests.

A pinned compiler or target change uses a distinct bulk re-baseline protocol:

1. Run the complete allocation suite with the old and proposed toolchains on
   the same controlled host, target, optimization mode, scenarios, and inputs.
2. Compare the full distribution, investigate every outlier, and inspect a
   representative sample from each subsystem and allocation shape.
3. Confirm deterministic work counters, and compare allocated/copied bytes,
   ARC, retained memory, and timing where existing instrumentation reports
   them, so a toolchain-wide count shift does not conceal an architectural
   regression.
4. Record the compiler/target delta as the shared cause, list any feature-
   caused changes separately, and update `.roc-version`, toolchain metadata,
   and all accepted baselines atomically.

This protocol permits reviewed bulk acceptance of a compiler-caused shift. It
does not permit blanket acceptance when outliers, feature-caused changes, or
algorithmic-counter changes remain unexplained.

Gate completion aggregates the performance records of its slices. A favorable
whole-gate aggregate cannot conceal a regression in a focused scenario, and a
super-linear blow-up cannot be deferred merely because the capability is still
within an early correctness gate.

## Gate 0: standards, representation, and test contract

### Capabilities

- Cite applicable editions, clauses and errata near implementations and
  focused tests. The architecture identifies the standards used by the writer.
- Pin the applicable normative references and data versions for the Unicode
  Standard and UCD, UAX #9, UAX #14, UAX #29, BCP 47/RFC 5646, OpenType, ICC,
  XMP/XML, JPEG, DEFLATE, and other implemented dependencies. Define the
  provenance and licensing contract for language-specific hyphenation data.
- Define the facade mapping `Standard = Pdf20`,
  `Archive = Pdf20 + StaticPdfA4`, and
  `AccessibleArchive = Pdf20 + StaticPdfA4 + PdfUa2`; WTPDF declarations and
  `PdfA4f` remain orthogonal explicit capabilities.
- Define the one-import `pdf.Pdf` facade, `Pdf.to_bytes` default contract,
  `Pdf.to_chunks` encoder contract, and explicit option-taking paths using
  current Roc type-module, associated-item, `Try`, `List(a)`, and package-
  import syntax.
- Define the required high-level author facts—metadata title and language—and
  distinguish them from optional visible title content. A report template may
  include a visible title by convention; conformance profile eligibility does
  not require one. Define typed constructors that distinguish meaningful
  content from artifacts without boolean flags. This revises the former
  planned visible-title policy without claiming a new executable profile.
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
- Implemented checks cite their standards edition and provisions. Focused
  fixtures exercise the project-owned contract.
- The same scenario protocol runs on every supported host.
- Public API examples compile with the pinned Roc compiler and do not require
  imports of advanced layout, scene, font, or conformance modules.
- Flat-store schemas and size/ownership accounting show that repeated
  placements and fragments retain one payload plus scalar IDs/ranges rather
  than requiring payload copies. Executable allocation evidence belongs to the
  gate implementing each store.
- Focused harness self-tests prove that allocation counts exclude Python and
  validator work, reset at each declared whole-pipeline or phase boundary, and
  reproduce exactly for the pinned compiler, dev backend, target, fixture
  revision, and measurement boundary.
- A deliberately introduced allocation regression fails the baseline check
  (for grouped fixtures, `--group-mode inject` adds one allocation inside every
  case's window and must be reported exactly), allocated bytes above the
  recorded ceiling fail it, and scaling fixtures
  demonstrate that deterministic work counters catch a complexity regression
  even when allocation counts remain unchanged.

## Gate 1: PDF 2.0 structural kernel

### Capabilities

- PDF 2.0 header and binary marker.
- Canonical lexical forms for booleans, integers, finite reals, names, byte
  strings, text strings, arrays, dictionaries, references, and streams.
- Direct and indirect objects with generation number zero.
- Catalog, page tree, page objects, content streams, resources, and trailer
  information.
- Xref streams, `startxref`, and end-of-file marker.
- Flate streams through the package's single private compressor seam over the
  pinned pure-Roc `roc-deflate` dependency (a libdeflate port); the
  independent Python checker uses zlib to reconstruct the exact emitted
  payload.
- Three sealed compression presets selected by `Pdf.Options.compression`:
  `Balanced` (the default), `Smallest`, and `Fastest`. Each preset is
  deterministic and byte-identical across buffered, chunked, and prepared
  output; `Smallest` reproduces the earlier level-10 bytes. Evidence:
  [docs/contributors/performance/output-size.md](docs/contributors/performance/output-size.md).
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
  deterministic per-stream DEFLATE, compressed object streams and a
  predicted compressed xref stream, bounded
  owned generated chunks, and optional seamless slices of validated unchanged
  resource allocations.
- Default consume-and-release chunk sharing plus an explicit owned-chunk
  retention policy; both produce byte-identical output.
- Checked arithmetic and explicit size/depth limits.

### Gate evidence

- White-box tests independently recalculate every object offset and stream
  length.
- Project-owned byte and object checks verify expected page facts, stream
  lengths and cross-references against the original output. Independent
  parsers can supplement those checks in local review.
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

The [tagged visual checks](docs/contributors/performance/tagged-visual-closure.md)
cover exact structure, renderer comparisons, rejection and scale for this
compiler boundary.

## Gate 3: searchable international text and useful layout

### Capabilities

- Bounds-checked TrueType-flavoured OpenType parsing.
- Deterministic font planning from exact theme faces, declared coverage,
  script, language, embedding rights, and font instance.
- Font identity, metrics, widths, embedding rights, and exact instance
  selection.
- A public typed caller-resource path accepts complete replayable font bytes,
  validates them, registers opaque faces and policies, and makes those handles
  selectable by `Theme` without caller-assigned resource IDs. The application
  or its platform owns file, network, store, or optional asset-package
  acquisition; the pure PDF package performs no acquisition effects.
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
- The core distribution contains only the small, audited face needed by the
  built-in theme. Broader multilingual and specialist coverage is supplied by
  callers or optional pure Roc asset packages and does not become a mandatory
  core-package payload. Packaged and caller-provided faces enter the same
  validation, planning, subsetting, and conformance pipeline.
- Compact cursor continuations, speculative measurement separated from final
  page materialization, and exact bounded caches for font parsing/coverage,
  shaping, measurement, and hyphenation.
- Font-table offset/range views, once-per-face coverage/`cmap`/GSUB/GPOS data,
  contiguous glyph buffers, global used-glyph accumulation, and once-only
  composite closure/subset-table emission.
- At this gate `Pdf.Options.default` selects public profile `Standard`, whose
  claim set is `Pdf20`. The options' `profile` is the only way to request a
  different implemented profile; incomplete `Archive` or `AccessibleArchive`
  claims remain unavailable.

### Upstream Unicode coordination

Use pure Roc Unicode algorithms from [roc-lang/unicode](https://github.com/roc-lang/unicode)
for scalar analysis, grapheme ranges, line breaks, bidirectional resolution,
script properties and itemization, and case mappings. The
[analysis dependency record](docs/contributors/performance/unicode-analysis.md)
pins Unicode 18.0.0, the package revision, the data manifest and the
separately versioned script-itemization policy. Review correctness, ownership,
allocations and deterministic work when adopting a new revision.

Language-specific hyphenation data is independently licensed and pinned.
OpenType parsing, GSUB/GPOS, glyph selection and shaping are separate from
the Unicode analysis boundary.

### Text capability planning for the production release

Maintain a [declared support matrix](docs/contributors/reference-documents.md#declared-production-text-support)
with explicit rows for:

- Scripts and language-sensitive shaping behavior.
- Font formats, exact font instances, and supported OpenType features.
- Direction, bidirectional mixtures, and writing modes.
- Grapheme selection, legal breaks, selected line-breaking policies,
  presentation transformations, and any supported hyphenation languages.

For each row distinguish advanced positioned-run input, built-in facade
shaping/layout, and packaged/caller-font coverage. Record its availability,
pure Roc dependency or owning component, pinned data, positive/negative
evidence, rendering/extraction expectations, and performance limits. A font
containing a character cannot close the facade shaping/layout column.

Use names, addresses, prose, formatted amounts and mixed-language content
from reference documents when selecting new rows. Broader typography belongs
to Gates 8 and 9.

Shaping/layout integration tests exercise safe splits, context-sensitive
reshaping after a selected break, changed advances and fit rechecking, per-line
bidirectional placement, and budget exhaustion. Unsupported cases remain
explicit errors. Use independently pinned shaping expectations, including a
test-only HarfBuzz comparison corpus where appropriate; native tooling is never
a production dependency or a majority-vote oracle. UAX #14 supplies break
opportunities, not the line-fitting algorithm, and shaping boundaries may
require reshaping after a break. See the
[Unicode line-breaking contract](https://www.unicode.org/reports/tr14/tr14-57.html)
and [HarfBuzz boundary facts](https://harfbuzz.github.io/harfbuzz-hb-buffer.html#hb-glyph-flags-t).

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
- A public end-to-end fixture supplies a valid font whose bytes are absent from
  the core production package, registers it through the caller-resource API,
  selects it through a `Theme`, and proves deterministic parsing, coverage,
  shaping, subsetting, embedding, extraction, and rendering. Structural
  inspection proves that the PDF contains the expected sanitized subset and no
  external font reference; package/distribution inspection proves that the
  fixture font did not become a core production asset. Its atomic negative twin
  supplies invalid or embedding-prohibited caller bytes and receives a stable
  error with no emitted PDF.
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
- Caller-font performance evidence records input-byte copying, parse/cache
  work, source-byte retention through final subset emission, and unique versus
  deliberately shared inputs. Reusing one caller-provided face across many
  placements retains one source payload and does not reparse or copy it per
  placement.
- Adversarial paragraph, line-break, font-selection, shaping, and single-column
  pagination cases meet their declared operation-count bounds; accepted page
  scenes are materialized once.

The [text and layout checks](docs/contributors/performance/text-layout-closure.md)
cover the declared single- and multi-face boundaries from source facts through
extraction and placement. See the text-support matrix for currently supported
shaping and layout.

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

The [visual compiler evidence](docs/contributors/performance/production-visual-closure.md)
covers resource and graphics validation, exact emission and scale for
`Standard`. Public drawing, flow figure and fixed-page limits are specified
under Gates 6 and 8.

## Gate 5: static PDF/A-4

### Capabilities

- Enforce the static profile's supported-feature whitelist.
- Embed every font, non-predefined CMap, ICC profile, and required resource.
- Ensure complete resource closure with no external dependencies.
- Emit correct XMP PDF/A identification and consistent metadata.
- Emit explicit file identifiers and output intent.
- Apply static-profile rules to page content, forms, transparency, images, and
  annotation appearances uniformly.
- Reject encryption, external visual/file references, incremental history,
  deprecated features, interactive forms, JavaScript, optional content,
  multimedia, 3D, and attachments under package policy. Supported URI link actions remain
  annotation data rather than rendering dependencies.
- Keep PDF/A-4f and PDF/A-4e outside this capability.

### Evidence and status

`Archive` selects PDF 2.0 with a static PDF/A-4 declaration. Preparation
checks the supported-feature whitelist, selected text, resource closure and
sealed-plan metadata. Fixtures exercise accepted Archive and Standard output,
identification and unchanged page appearance, plus atomic rejection. The
[archive implementation record](docs/contributors/performance/static-pdfa4.md)
describes the supported path.

## Gate 6: business authoring and core PDF/UA-2 vocabulary

This gate defines the business authoring and semantic vocabulary used by the
reference invoice, report and letter.

### Capabilities

- Public facade constructors and layout for every reference-document feature,
  including rich inline content, links, ordinary tables, figures, captions,
  address/letterhead composition, page templates, and navigation.
- Ordinary tables that continue across pages with explicit column sizing and
  alignment, wrapped cells, row-splitting policy, repeated headers, and keeps
  for groups such as invoice totals. The supported span/fragmentation subset
  is declared precisely; general row-group and complex-span behavior remains
  Gate 8. Repeated visual content preserves the declared semantic/artifact
  policy rather than inventing new logical table relationships.
- Bounded first-page and continuation-page templates with single-column body
  flow, explicit headers/footers/decorations, and resolved page/total-page
  numbers, with independently themed furniture face, size, leading, and color
  (body-style inheritance by default). Template regions have reserved geometry; decorative/repeated page
  furniture has explicit artifact ownership, and meaningful authored content
  retains semantic ownership. General fixed pages, columns, and float/footnote
  interaction remain Gate 8.
- Bounded image/vector flow figures and captions through validated drawings,
  plus one separately authored chart or callout exercising the custom-block
  seam. Its supported measurement and fragmentation contract is explicit;
  neither PDF operators nor arbitrary custom pagination become public.
  Drawing labels occupy one shaped line in the body face
  (`Scene.Drawing.text`) or an inline role face (`Scene.Drawing.text_in`).
  Each intrinsic label stays within the drawing, scales with it, and belongs
  to the Figure. The bounded decoration API and ordered font policies
  exclude drawing labels.

- Typed mandatory layout constraints and ranked preferences, including
  oversize-content and unbreakable-token behavior, supported wrapping and
  splitting, required/preferred keeps, deterministic tie breaks, and bounded
  conflict diagnostics. Final reference fields may have explicit fixed widths
  only when their resolved values are shaped and checked to fit.
- Bounded preformatted source blocks with independent registered typography,
  explicit LF/CRLF and tab policy, preserved indentation and empty lines,
  measured wrapping with a declared oversized-token policy, and continuation
  between visual lines. Optional padded panels repeat as decoration artifacts
  on each page fragment; Code semantics and source order remain logical facts.
  Foreground ranges preserve the source, wrapping and semantic ownership.
  [Source-block evidence](docs/contributors/performance/source-blocks.md) and
  [foreground-range evidence](docs/contributors/performance/source-foregrounds.md)
  exercise these contracts.
- The declared production text-support matrix and any additions needed by the
  reference documents, including bounded boundary reshaping and final fit
  verification where applicable.
- A bounded read-only preparation report exposing authoring locations, final
  layout summaries, reading order, authored alternatives/assertions, policy
  outcomes, and applicable human-review obligations without PDF object IDs or
  retention of discarded compiler stages.
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
- Catalog `/MarkInfo` and per-page `/Tabs` entries for the tagged output.
- Page- and stream-spanning occurrences and exact mixed structure order.
- Page-content artifacts and contextual Artifact structure elements.
- Language inheritance and nested language changes. The document language
  and scoped language tags identify specific languages. Standalone PDF text
  strings use their inherited language.
- Theme, panel, spacing and other styling controls provide presentation. The
  supported semantic properties use authored content, roles, alternatives and
  the typed Table, List and Artifact attributes. Independent semantic Layout
  properties are outside this bounded authoring scope.
- Alternative, expanded, replacement, actual, phoneme, and phonetic-alphabet
  text where applicable.
- IDTree construction and typed structure references.
- Author-obligation diagnostics distinct from mechanically proven facts.

### Gate evidence

- All three reference documents and their content variants execute through the
  supported release API. Expected page composition, typography, wrapping,
  alignment, image placement, and navigation are reviewed as complete documents
  as well as through atomic fixtures. Every variant has either an acceptable
  policy-defined layout or a stable error with no PDF bytes.
- Tests cover repeated table headers, row continuation, totals near page
  breaks, oversized rows/figures, incompatible mandatory keeps, and permitted
  preference relaxation. Each result preserves source and semantic ownership;
  no hidden clipping, shrinking, omission, or weaker conformance is accepted.
- First/continuation-page templates preserve body bounds and declared semantic
  or artifact ownership. Page/total-page fields contain exact resolved values;
  insufficient field widths, cycles where stabilization is used, and work
  exhaustion reject deterministically.
- A separately authored extension consumer uses the supported public contract
  without private stores or PDF objects. Its supported continuation or explicit
  unsplittable behavior, semantic ownership, and bounded allocation/work are
  exercised before that subset is declared stable.
- Preparation-report fixtures map observations back to author input and
  distinguish mechanical facts from human obligations. Inspection is bounded,
  does not alter bytes, and does not keep discarded stages or resource payloads
  alive through diagnostics. Report-budget failures are explicit rather than
  silently omitting obligations.
- The production text matrix has evidence for every required row, distinct
  facade and advanced-input claims, and atomic unsupported-case diagnostics.
  Required shaping/layout interactions meet their declared work bounds.
- The required readiness dimensions and exact allocation/work records,
  including a small/large scale pair for each scalable slice, are satisfied
  for each required business slice.
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
- Optional and non-blocking: human-reviewed scenarios cover reading order,
  heading navigation, lists, links, figures, simple tables, nested language,
  and artifact behavior. An unperformed review is recorded as not performed.
- Optional exploratory reader/AT work may use the available public subset and
  expand as these slices become executable. Tasks include locating invoice
  amounts through table navigation, following payment links, navigating report
  headings, and understanding figures through their alternatives. Missing
  capabilities and reader limitations are recorded explicitly; exploratory
  observations do not replace machine-verifiable gate evidence.
- Where human review is performed, its protocol pins AT/reader versions, tasks,
  expected observable navigation outcomes, and optional assessor sign-off. It
  does not require identical synthesized speech or UI output.
- Negative twins cover missing or empty required alternatives, misleading
  structure relationships detectable mechanically, skipped ownership, missing
  Unicode, bad heading representation, inaccessible annotation structure,
  invalid namespace/attribute/language/relationship facts, and missing or
  mismatched destination pairs. Each failure has a stable diagnostic and emits
  no bytes.

Unsupported semantic constructs are rejected; they are never flattened into
paragraphs or figures.

The [business-authoring evidence](docs/contributors/performance/business-authoring-closure.md)
links the public fixtures, independent checks and scale baselines. See the
[authoring guide](docs/authoring.adoc) for supported combinations and
diagnostics.

## Gate 7: business documents and the combined default

`AccessibleArchive` is the facade default for the supported business-document
subset. It emits PDF/A-4 and PDF/UA-2 declarations. `Archive` and `Standard`
remain explicit selections. WTPDF accessibility is a separate opt-in on the
combined profile. Preparation rejects unsupported features or failed checks
before emission.

Preparation checks the selected declaration metadata, document title and
language, resource eligibility, and tagged structure. The report exposes
content-dependent obligations such as accurate alternatives and meaningful
reading order. The reference invoice, report and warranty letter exercise the
public facade, including the letter without a visible title. Project-owned
fixtures cover document structure, navigation, metadata, diagnostics, and
exact byte, allocation, and work evidence on the pinned targets. Invoice and
report scale pairs check growth as their authored content increases.

Standards support is best effort. Independent certification requires a
separate scope, funding, and ownership. Discuss proposals in
[GitHub Issues](https://github.com/lukewilliamboswell/roc-pdf/issues).

## Gate 8: advanced document composition

These capabilities extend the single-column flow, ordinary tables, bounded
figures, page references and source blocks described under Gate 6.

### Capabilities

- Complex tables with richer row groups, span combinations, and fragmentation
  beyond the declared Gate 6 subset, preserving repeated-header semantics.
- General fixed-page composition, richer page templates, multi-column layout,
  floats, footnotes, side content, and explicit logical order.
- General cross-references, generated tables of contents, indexes, richer page
  labeling, and deterministic layout stabilization beyond Gate 6's bounded
  page/total-page fields and Gate 4's navigation primitives.
- Notes, references, bibliographies, and caption/inline semantics beyond the
  core business vocabulary.
- General accessible custom-block fragmentation and vector-scene integration
  beyond Gate 6's bounded figure/callout contract.
- Broader explicitly declared script/font coverage and vertical writing where
  the shaping and layout boundary supports them.
- Broader public composition with reusable Form XObjects, transparency,
  gradients, and patterns using the Gate 4 compiler and the Gate 6 flow-figure
  boundary.

### Gate evidence

- Table fixtures cover spans, IDs, scopes, headers, fragmentation, repetition,
  and invalid intersections.
- Reference layouts cover convergence, cycles, and budget exhaustion without
  accepted approximations.
- Custom-block fixtures fragment across columns and pages while preserving
  occurrence identity, typed continuation state, semantic ownership, and
  bounded operation/allocation evidence.
- Optional human AT review covers table navigation, multi-column order,
  footnotes, references, and mixed language/direction.
- Each capability verifies its supported profile declarations and applicable
  emission checks with focused project-owned fixtures.

### Bounded fixed-page text and artwork

The fixed-page builder supports explicit sheet sizes, framed titles,
numbered headings, paragraphs and rich paragraphs, and solid rectangle
backgrounds and overlays. Placements determine reading order. A per-page
permutation can independently select paint order. Preparation checks nominal
line-box and advance fit and reports errors at the authored page and placement.
The [remittance example](examples/remittance-advice/main.roc) exercises mixed
sizes and differing orders. The [fixed-page evidence](docs/contributors/performance/fixed-pages.md)
covers the combined and WTPDF declarations, exact reading and paint order,
and two- and twenty-page scale checks.

Flowing columns are a separate slice. Define a typed cursor that resumes an
occurrence across a column and a page before adding column selection policy.
Next select table fragmentation, stabilized references, or custom-block
continuation from an application that needs it. Each slice carries its own
profile eligibility and independent ownership and geometry evidence.

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
- WTPDF reuse as a separate capability with defined behavior and focused tests.
- Optional advanced print-color capabilities independently of accessibility.

### Gate evidence

- MathML element/attribute namespace and containment tests cover positive and
  atomic negative cases.
- Base PDF/A-4 and PDF/A-4f math cases validate the exact selected attachment
  policy; structured math is never replaced with alternate text.
- Optional human AT review covers mathematics, ruby/warichu, vertical/mixed
  writing, and new annotation interactions where implemented.
- New roles, namespaces, text systems, and annotations carry edition and clause
  references and tests for their declared support.

## Local PDF review tools

Local independent validators and readers may inspect the original bytes emitted
by Roc. Their reports can inform focused regressions. CI uses project-owned
checks, and recorded observations identify the tool and version used.

## Assets and provenance

Every retained external asset records its source URL, upstream revision,
cryptographic digest, license identifier, required attribution, and whether
modification or redistribution is permitted. The same manifest covers fonts,
ICC profiles, images, Unicode/UCD data, hyphenation patterns, fuzz seeds, and
expected renderings.

Retained redistributable assets under `vendor/` keep their exact upstream
bytes. The provenance check verifies their manifest digest. An upgrade is an explicit
reviewed commit that updates the artifact, license and attribution material,
provenance record, CI reference, and affected evidence together. Git LFS is
not used because it would make a separate remote service part of checkout and
historical reproducibility.

Repository and CI availability does not imply core-package distribution.
Production defaults contain only the minimal audited assets required by the
facade contract. Broader fonts and language data remain test-only inputs or
separately versioned optional asset packages; applications opt into those
packages and pass their bytes through the same public caller-resource boundary.
Generated `StaticPdfA4` files nevertheless embed every selected font subset and
required resource, so no optional package or acquisition source is a rendering
dependency of the resulting PDF.

Large platform-specific compiler toolchains, JDKs, and container images are
not committed to Git. Their action source is pinned by full commit identity,
their selected version or image digest is exact, and a network-isolated CI
deployment pre-provisions them in its immutable runner image. `.roc-version`
remains the sole Roc compiler-version pin. Reference external standards by
edition and clause, with redistribution governed by their own licenses.

## CI gates

### Per change

- Fast ordinary CI checks and tests `package/main.roc`, compiles and tests every
  checked-in public example, and runs a bounded campaign for every property fuzz
  target through `./scripts/fuzz.py`. Compiling a target is not evidence about
  its property, so the lane executes each one against its seed corpus rather
  than only type-checking it.
- The reusable applicable-check workflow binds every checkout to one commit
  SHA and aggregates the full pinned-build suite, allocation/byte/work guards,
  project-owned PDF structure and profile checks, the user manual/API, and
  exact bundle/gallery/examples/docs-archive consumers. Release dispatch invokes the
  same checks with Linux and macOS coverage before artifact-only publication.
- Before a change is treated as feature evidence, its author runs the complete
  local `./scripts/test.py` suite. This retains Roc unit and typed property
  tests, deterministic fixture and structural checks, exact allocation
  baselines, work counters, and the focused
  ownership and performance evidence required by the affected slice.
- A `.roc-version`, target, optimization-policy, snapshot, or allocation
  baseline change still requires the documented review protocol; the fast CI
  lane does not turn generated evidence changes into automatic acceptance.

### Extended

- Expanded project-owned feature fixtures and optional local PDF review.
- Random small typed scenarios with minimized retained seeds.
- Deterministic corpus-mutation fuzzing of font, JPEG, and ICC inspectors,
  or coverage-guided fuzzing when reliable Roc coverage is available, under
  input/work/memory/time bounds with minimized failures retained as ordinary
  regression tests.
- Bounded large-document, offset, subset, stream, and structure stress suites.
- Exact-allocation and scale-pair work-counter checks for large-document,
  serializer, and compressor paths. Timing, peak-RSS, and copied-byte figures
  are reported only where existing instrumentation provides them and carry no
  acceptance thresholds.

### Release

- Public reference invoice/report/letter acceptance, including adverse content,
  supported typography/layout, authoring feedback, and scale-growth evidence,
  as required by Gate 7.
- Cross-platform byte-for-byte reproducibility.
- Published performance evidence from the pinned dev backend, including
  unique and deliberately shared pipeline inputs.
- Current allocation baselines, scaling records, and resolved performance
  review decisions for the shipped slices.
- Optional current-reader smoke tests.
- Optional accessibility expert review.
- Optional scripted representative assistive-technology journeys.

## Deliberately separate future expansions

The following are separate capabilities if an application needs them:

- PDF/A-4f attachments.
- WTPDF reuse conformance beyond accessibility.
- Alternative replay or spooling surfaces beyond the baseline compact-plan,
  stateful-compression, owned-generated-chunk, and shared-final-resource-slice
  design.
- CFF, CFF2, variable-font instancing, or additional image codecs after the
  initial validated font/image set.
- Interactive forms, signatures, encryption, optional content, JavaScript,
  multimedia, RichMedia, and 3D.
- Linearization, incremental updates, reading, editing, repair, or conversion.

Some of these conflict with the static package policy and may remain
permanently unsupported.

## Built-in typography

The facade selects Inter for ordinary body/headings, Merriweather for explicit
serif typography, and Fira Code for inline/source code through exact static
family/style choices. Sans/serif provide genuine Regular/Bold/Italic/Bold Italic;
mono provides Regular/Bold. Missing coverage, unavailable styles and unsupported
shaping reject before bytes, without automatic fallback. This adds no runtime
variable-font, script-shaping or conformance-profile claim.

[Packaged-font contracts](docs/contributors/roc-font.md) define asset provenance,
selection and ownership. [Default-family fixtures](docs/contributors/performance/default-fonts.md)
cover independent source/subset metadata, searchable text, atomic rejection and
scaling. Use the current allocation baselines and publication checks rather than
an earlier integration run to assess a change.
