# Pure Roc PDF Generation Architecture

## Purpose

This document defines the enduring architecture for a pure Roc package that
generates PDF 2.0 documents. It describes stable boundaries, data ownership,
invariants, conformance policy, and test architecture. Feature delivery order
belongs in [feature-roadmap.md](feature-roadmap.md).

The package is generation-only. It does not read, edit, repair, incrementally
update, or convert existing PDFs. Its primary production profile is a closed,
static subset of PDF/A-4. Its semantic model is capable of additionally
producing PDF/UA-2. Legacy PDF output is outside the design.

The production implementation and all of its runtime dependencies are pure
Roc. Python and native PDF tools are independent test oracles; they are not
linked into or invoked by the package.

## Standards basis

The implementation is defined against a pinned standards corpus, not the
informal label "PDF 2.0":

- ISO 32000-2:2020, including the resolved errata artifact named in the
  conformance ledger. The initial baseline is Errata Collection 3, identified
  there by source revision, retrieval date, and cryptographic digest rather
  than by its mutable download URL alone. This collection incorporates the
  ISO-approved structure-destination clarifications from
  [issue 140](https://github.com/pdf-association/pdf-issues/issues/140) and
  [issue 162](https://github.com/pdf-association/pdf-issues/issues/162); both
  resolutions are pinned as individual ledger requirements rather than being
  assumed from the collection label.
- ISO 19005-4:2020 and its resolved errata for PDF/A-4.
- ISO 14289-2:2024 for PDF/UA-2.
- ISO/TS 32005:2023 and its resolved errata for the containment of structure
  elements from the PDF 1.7 and PDF 2.0 standard namespaces.
- WTPDF 1.0 when WTPDF accessibility or reuse is claimed.

The ledger also pins every applicable normative dependency and data version,
including the Unicode Standard and Unicode Character Database, Unicode
Standard Annex #9 for bidirectional text, Unicode Standard Annex #14 for line
breaking, Unicode Standard Annex #29 for text segmentation, BCP 47/RFC 5646,
OpenType, ICC, XMP/XML, JPEG, and DEFLATE specifications. Any hyphenation
pattern set is a separately pinned, licensed data dependency with language,
revision, digest, and provenance; no unversioned system dictionary participates
in deterministic layout.

The PDF Association maintains an archive of ISO 32000-2's
[normative references](https://pdfa.org/pdf-2-0/). A pure implementation does
not make those dependencies implicit.

ISO 32000-2:2020 replaces the 2017 edition and contains corrections and
clarifications discovered during early PDF 2.0 implementation. The PDF
Association publishes the current corrected text and errata information in its
[ISO 32000-2 resource](https://pdfa.org/resource/iso-32000-2/).
The corresponding maintained entry points are
[PDF/A-4](https://pdfa.org/resource/iso-19005-4-pdf-a-4/),
[PDF/UA-2](https://pdfa.org/iso-14289-2-pdfua-2/),
[ISO/TS 32005](https://www.iso.org/standard/45878.html), and
[WTPDF](https://pdfa.org/wtpdf/).

Standards and errata updates are reviewed changes to the package. Each update
changes the conformance ledger explicitly; validator upgrades must not silently
change the normative baseline.

## Scope and claims

The package supports distinct, composable claims:

- `Pdf20`: valid output within the implemented ISO 32000-2 subset.
- `StaticPdfA4`: the package's static, self-contained subset of PDF/A-4.
- `PdfUa2`: PDF/UA-2 accessibility requirements, optionally combined with
  `StaticPdfA4`.
- `WtpdfAccessibility`: the WTPDF accessibility declaration, whose file
  requirements align with PDF/UA-2.
- `WtpdfReuse`: a separate capability with additional requirements.
- `PdfA4f`: a possible future attachment-bearing profile, separate from the
  base static profile.

These are not successive values in a maturity enum. PDF/A-4 concerns durable
static appearance; PDF/UA-2 concerns accessibility; WTPDF reuse is a further,
orthogonal claim. A file may combine compatible claims only when the package
has a validator and test matrix for that exact combination. The relationship
between PDF/UA-2 and WTPDF is summarized in the PDF Association's
[Tagged PDF Q&A](https://pdfa.org/resource/tagged-pdf-q-a/).

The package's `StaticPdfA4` profile is intentionally narrower than everything
ISO 19005-4 may permit. It rejects forms, JavaScript, optional content,
attachments, multimedia, 3D, encryption, external visual/file dependencies,
and incremental updates. Supported URI link actions remain ordinary annotation
data. These are package policy exclusions, not claims that every such construct
is universally prohibited by PDF/A-4.

Passing machine validation does not establish that a document is useful to a
person with a disability. PDF/UA-2 cannot determine whether author-supplied
alternative text is truthful, whether reading order is meaningful, or whether
the content meets every WCAG requirement. The package may establish mechanical
conformance and make author obligations explicit; it must not claim to certify
semantic quality.

## Core invariants

1. Semantics exist before layout. They are never inferred from coordinates,
   drawing order, glyph positions, or extracted text.
2. Logical reading order and page paint order are independent explicit data.
3. Stable semantic identity survives line, column, page, and content-stream
   fragmentation.
4. Each semantic element has one explicit ordered content spine that may
   interleave child elements, direct content occurrences, annotations, and
   contextual Artifact elements. PDF structure order is never recovered from
   ownership or paint order.
5. Every painted item is associated with exactly one layout fragment whose
   source is either a semantic content occurrence or a page-content artifact.
   There is no unclassified content.
6. Page-content artifacts excluded from the logical structure and PDF 2.0
   contextual Artifact structure elements are distinct typed data.
7. Source Unicode and its exact relationship to shaped glyphs cross the text
   boundary explicitly. They are never reconstructed from glyph IDs.
8. Fonts, images, ICC profiles, annotations, destinations, and metadata are
   validated inputs. Reusable resource identity and per-placement semantic
   ownership remain distinct.
9. Unsupported or non-conforming requests are errors. The package does not
   substitute fonts, outline text, rasterize content, drop features, repair
   semantics, or downgrade profiles.
10. Conformance and the exact lowered object plan are validated before sealing
   for byte serialization. The serializer has no conformance policy and
   performs no repairs.
11. The low-level PDF object model and object numbers are private implementation
   details.
12. Identical explicit inputs and package versions produce identical bytes.

## The package as a compiler

PDF generation is a typed, one-way compilation pipeline:

```text
semantic document                         validated resources
        |                                         |
        +-------------------+---------------------+
                            |
                            v
               font planning and validation
                            |
                            v
            shaping, layout, and stabilization
                            |
                            v
                     PreparedDocument
             /              |               \
 semantic content spine  fragment map     page scenes
             \              |               /
              normalization and resource analysis
                            |
                            v
                profile-conformance validation
                            |
                            v
                   PDF 2.0 object plan
                            |
                            v
                  lowered-plan validation
                            |
                            v
                    sealed PDF plan
                            |
                            v
                 deterministic byte emission
```

Each stage consumes explicit output from the preceding stage. A later stage
does not recover missing data from geometry, names, content bytes, reader
behavior, or incidental collection order.

## Performance and storage architecture

The tree-shaped examples in this document describe typed relationships, not
the required hot-path memory representation. Public authoring values may be
recursive and ergonomic. Normalization lowers them exactly once into compact,
non-recursive stores. Large-document authors also have a consumption-shaped
`Document.Builder` that writes the same compact authoring store directly,
avoiding a boxed recursive `List(Document.Block)` front end without exposing
PDF or normalized-plan internals.

The compact stores use these rules:

- Semantic nodes, content occurrences, layout fragments, scene commands,
  glyph runs, resources, and PDF objects receive dense scalar IDs.
- Fixed-shape records live in contiguous lists indexed by those IDs.
- Variable children, keys, commands, clusters, and dependencies are spans into
  flat scalar or record buffers.
- Scene-command ownership ranges follow canonical dense arena visitation order;
  a scalar cursor rejects gaps and repeats without a per-command ownership map.
- Source text, font/image/ICC bytes, paths, glyph arrays, content recipes, and
  compressed inputs are each owned once; every relationship uses an ID and an
  exact `(start, length)` range.
- Semantic order and page paint order reference one fragment table. A reverse
  occurrence-to-fragment index is built in linear time from counts and prefix
  sums rather than by duplicating fragments or comparison-sorting dense IDs.

The conceptual `List(DrawNode)` scene and generic PDF object union must not
become allocation-per-node recursive runtime values. The normalized scene is a
flat command arena. The object plan uses a flat object store and separate edge
and value buffers; arrays and dictionaries contain spans rather than recursively
embedded objects. Lexical tokens are emitted in bulk and are not individual
`Str` or `List(U8)` allocations.

All large traversals are iterative and resource-budgeted. When dense indexing
cannot replace ordering, the package uses a deterministic comparison sort with
worst-case `O(n log n)` time and a total tie-break order. Its scalability must
not depend on a first-pivot quicksort or other algorithm with quadratic
behavior on already ordered, reverse-ordered, or equal input.

### ARC and phase ownership

Stage implementations are consumption-shaped. A builder consumes and returns
one accumulator, preallocates from exact earlier counts where available, and
does not retain aliases to a list across append or update operations. This
allows Roc's ARC analysis and runtime uniqueness checks to reuse storage on the
ordinary one-shot path. Correctness never depends on uniqueness: an advanced
caller may retain earlier immutable values and receive the same result with
higher allocation and retention cost.

Each successful stage transfers only the data required by its successor:

```text
authoring tree
    -> normalized semantic/layout input
    -> final PreparedDocument stores
    -> compact SealedPdfPlan
    -> Encoder state
```

The sealed plan has no back-reference to the authoring tree, speculative layout
passes, or full page-scene source. It retains compact object/content recipes,
validated resource bytes still required for output, immutable validation
summaries, and scalar indexes. Resource inspection facts, digests, use counts,
tree facts, and budget totals are calculated once and passed forward
explicitly; later validation boundaries do not rescan or rehash them.

Large payloads are not captured in stored closures. Custom layout handlers are
supplied separately with static dispatch and are gone by `PreparedDocument`.
Blocks, scene records, caches, plans, and encoder states contain declarative
data. Diagnostics contain compact IDs, locations, and bounded details rather
than retaining documents or resource byte buffers; a deterministic diagnostic
count/size budget prevents error storms.

### Layout representation and complexity

All layout geometry uses one checked fixed-point `LayoutUnit` with documented
scale, range, arithmetic, and rounding. Font-unit conversion and division have
one explicit rounding policy. Conversion to canonical PDF numbers occurs at a
defined lowering boundary. Cache and convergence identity never depends on
host floating-point equality.

Layout continuations are compact component/source IDs plus scalar cursors and
explicit state. They are not list suffixes, string slices, rebuilt remaining-
block lists, or copies of earlier measurements. Text ranges retain validated
UTF-8 byte and Unicode-scalar offsets into one source value.

Speculative measurement is separate from committed materialization. Line and
page breaking operate on measurements, prefix data, break candidates, and
scalar cursors; after a break is selected, its page scene is materialized once.
Old versions of a growing scene list are not rollback checkpoints. Paragraph
analysis, table grids, cell measurements, and other invariant work are computed
once per exact input and reused by explicit cache entries.

Each layout algorithm declares its worst-case complexity and exact cache keys.
Line breaking does not rescan a paragraph for every candidate; pagination
resumes from its continuation; keep/backtracking rules do not permit exponential
search; table grids and header relations normalize once. Exhausting an exact
work budget is an error rather than permission to use an approximation.

Stabilization retains the current candidate and compact exact layout-affecting
states, never every prior page scene. A digest may locate a possible repeated
state but exact state equality confirms it. A deterministic cycle-detection
algorithm may further bound retained history. Final scenes are materialized or
transferred only from the accepted stable state.

Phase-local caches have complete typed identities. These include font parse,
font instance, coverage, shaping, measurement, and hyphenation. A shaping key
includes exact font instance, content range, script, language, direction,
writing mode, feature policy, and required boundary context; it never reuses a
run across a context that can change joining or substitution. Cache count and
retained bytes are budgeted.

### Iter policy

`Iter` is a traversal interface, not an internal storage representation or an
assumed optimization. It is appropriate for coarse pages, rows, scanlines,
resources, or output chunks; known-size single-pass folds; and public adapters
that avoid unnecessary intermediate lists. Exact size hints are preserved when
available.

Hot byte, glyph, path, pixel, scene-command, and object loops use direct indexed
or `while` loops over dense buffers unless optimized-code and benchmark evidence
shows an `Iter` path has equivalent allocation, ARC, and dispatch behavior.
The architecture does not use `Iter(U8)`, does not rely on deep
adapter/`concat` chains, and does not assume unknown-length reverse/tail
operations remain streaming. `Iter` values are not stored in `Document`,
`PreparedDocument`, continuations, caches, or `SealedPdfPlan`.

### Emission representation

`SealedPdfPlan` is an exact compact replayable plan, not a fully materialized
recursive PDF tree or a collection of precompressed byte blobs. Every object
and indirect stream-length object is assigned before emission. Object IDs
follow emission order so offsets append to a dense list rather than update a
map. Ordinary stream lengths use indirect objects emitted immediately after
their streams, allowing the encoder to run validated content recipes through
lexical emission and stateful deterministic DEFLATE without buffering the
entire uncompressed or compressed stream.

The baseline DEFLATE transition is a private, package-owned pure Roc
implementation. Its internal seam accepts preflighted input and checked
limits, exposes a conservative output bound, and yields deterministic bounded
chunks plus explicit work and source-release facts. `roc-deflate` is pinned as
an independent test-only decompression oracle; it is not the production
compressor. A future `roc-deflate` release may replace the owned implementation
only when it can satisfy that same stateful seam and after its byte policy,
bounds, ownership, deterministic work, allocation, and retention evidence have
been reviewed together. Such a replacement cannot weaken these contracts or
silently change emitted bytes.

The initial xref stream is unfiltered, covers the complete contiguous object
range, and uses `/W [1 8 2]`; its direct length is therefore 11 bytes per entry
with checked multiplication. The encoder retains `U64` offsets proportional to
object count. Any alternative compressed or replay/counting strategy is a
separately specified capability. Sealing proves exact counts where possible
and safe upper bounds for lexical output, compression, offsets, and configured
output budgets so the infallible encoder cannot discover overflow or limit
failures.

The encoder is an explicit state machine, not a stored iterator closure. It
consumes one state and returns its successor plus a coarse output segment. A
segment is either a generated, independently owned bounded-capacity buffer or
an exact range of validated resource bytes that are already in their final PDF
representation. The public `List(U8)` for the latter may be a Roc seamless
slice, avoiding a payload copy. Generated PDF syntax, transformed image data,
font subsets, and DEFLATE output are never presented as slices of mutable
accumulators or oversized internal arenas. Retaining an old encoder state is
valid but forfeits the unique-state fast path.

The package never coalesces shareable resources into one whole-document byte
arena, and package-created shareable resources use separate reference-counted
allocations. A caller-supplied resource may itself already be a seamless slice
of a larger caller allocation; sharing it can retain that actual backing
allocation, not merely the visible resource range. The encoder releases its
own resource reference immediately after its final emitted range; any remaining
lifetime is then caused by caller-retained chunks. Chunked output has an
explicit retention policy: the default shares unchanged resources for the
ordinary consume-and-release streaming path, while an owned-chunk mode copies
such ranges into bounded buffers when predictable retained memory is more
important than avoiding the copy. Both policies emit identical bytes.

Buffered output drives the same lower-level emission transition into one unique
byte accumulator, reserving only an exact known size. When the final size is
not exact, the accumulator follows one deterministic bounded-growth policy; a
loose validated worst-case bound is never used as a requested allocation size.
It does not first build a `List(List(U8))` and concatenate it. Resource ranges
are copied directly into this final contiguous result, because `to_bytes`
cannot both return one allocation and preserve zero-copy resource sharing. The
public chunk wrapper either returns a permitted seamless resource slice or
supplies a fresh bounded buffer to the transition. A high-level chunk
entrypoint may expose the validated encoder, while one-shot byte sources that
cannot be replayed or fully validated are not accepted as resources.

The bounded-memory target is proportional to the compact input/sealed stores,
validated resource bytes still referenced by the encoder or caller-retained
seamless slices, the object-offset table, bounded cache state, compressor
state, and one or a bounded number of owned output chunks. It is not a
constant-memory promise. Whole-document conformance, global font subsetting,
destinations, the structure tree, and xref offsets require global facts.
The pure package exposes no concurrency capability and does not promise that
any work executes in parallel. Page, resource, and font work is nevertheless
decomposed into explicit independent tasks with a canonical merge order so a
future Roc compiler optimization or a separately designed platform-assisted
evaluation seam could evaluate eligible tasks concurrently without changing
bytes. Ordered serialization and offset accumulation remain sequential.

Document identifier derivation uses a versioned, domain-separated digest of
explicit normalized or plan data. It never requires hashing final serialized
bytes that themselves contain the identifier.

## Public architectural boundary

### High-level API is the primary product

Most users should never construct a `PreparedDocument`, page scene, glyph run,
font subset, output intent, semantic node, or conformance value. The primary
API accepts semantic document blocks and returns PDF bytes. Advanced types
exist as integration boundaries behind the facade; they do not define the
normal authoring experience.

The package follows modern Roc's type-module design. Its package module exposes
capitalized type modules, and consumers import the `Pdf` facade through their
lowercase package shorthand. The other modules are available for advanced
integration, but the common path needs one import:

```roc
package [
    Pdf,
    Document,
    Semantics,
    Layout,
    Scene,
    Text,
    Font,
    Image,
    Color,
    Metadata,
    Conformance,
    Encode,
    Theme,
] { deflate: "..." }
```

```roc
app [main!] {
    pf: platform "...",
    pdf: "...",
}

import pdf.Pdf
```

`Pdf.roc` is a void type module whose associated items form the facade. The
shape below is an API design sketch using current Roc syntax; private backing
types and the exact error alternatives may evolve without changing the
boundary:

```roc
Pdf :: [].{
    Error := [
        InvalidDocument(List(Diagnostic)),
        UnsupportedFeature(Feature),
        InvalidResource(ResourceError),
    ]

    Profile := [
        AccessibleArchive,
        Archive,
        Standard,
    ]

    PageSize := [A4, Letter]

    ChunkRetention := [
        ShareUnchangedResources,
        OwnChunks,
    ]

    Options :: {
        profile : Profile,
        page_size : PageSize,
        theme : Theme,
        chunk_retention : ChunkRetention,
    }.{
        default : Options
        with_profile : Options, Profile -> Options
        with_page_size : Options, PageSize -> Options
        with_theme : Options, Theme -> Options
        with_chunk_retention : Options, ChunkRetention -> Options
    }

    document : {
        title : Str,
        language : Str,
        contents : List(Document.Block),
    } -> Document

    title : Str -> Document.Block
    heading : U8, Str -> Document.Block
    paragraph : Str -> Document.Block
    bullets : List(Str) -> Document.Block
    png_srgb : List(U8) -> Try(Image, Error)
    figure : Image, Str -> Document.Block
    decorative_image : Image -> Document.Block

    to_bytes : Document -> Try(List(U8), Error)
    to_bytes_with : Document, Options -> Try(List(U8), Error)
    to_chunks : Document -> Try(Encode, Error)
    to_chunks_with : Document, Options -> Try(Encode, Error)
    next_chunk : Encode -> [Done, Emit(List(U8), Encode)]
}
```

The public profile names map to conformance claims exactly as follows:

| `Pdf.Profile` | Required claim set | Meaning |
| --- | --- | --- |
| `AccessibleArchive` | `Pdf20 + StaticPdfA4 + PdfUa2` | Self-contained accessible archive; WTPDF accessibility is declared only through its separately validated declaration capability |
| `Archive` | `Pdf20 + StaticPdfA4` | Self-contained static archive without a PDF/UA-2 claim |
| `Standard` | `Pdf20` | The implemented generation-only PDF 2.0 subset without archival or accessibility conformance claims |

`Profile` selects requirements, not feature availability or reader behavior.
Choosing a weaker profile never repairs, substitutes, or removes unsupported
input. Orthogonal claims such as `WtpdfAccessibility`, `WtpdfReuse`, and future
`PdfA4f` remain explicit conformance capabilities rather than additional
meanings hidden inside the three facade values.

`Theme` is the typed visual and layout policy used by the convenience authoring
path. It contains exact font policies and text styles; page margins and default
spacing; heading, paragraph, list, table, caption, and code presentation; and
typed color and decoration choices. It does not contain semantic roles,
language, metadata, alternative text, reading order, conformance claims, output
intent, serializer options, or system-font names. A theme references only
validated packaged or caller-provided resources, and a theme override cannot
weaken the selected profile. The built-in theme is versioned because changing
its metrics, fonts, or spacing can change pagination and bytes.

The common path is deliberately short:

```roc
make_report : Str -> Try(List(U8), Pdf.Error)
make_report = |summary| {
    document = Pdf.document({
        title: "Quarterly report",
        language: "en-AU",
        contents: [
            Pdf.title("Quarterly report"),
            Pdf.heading(1, "Summary"),
            Pdf.paragraph(summary),
            Pdf.bullets([
                "Searchable Unicode text",
                "Embedded fonts",
                "Tagged reading order",
            ]),
        ],
    })

    Pdf.to_bytes(document)
}
```

`Pdf.document` requires the small set of facts that cannot be responsibly
guessed, including metadata title and natural language. It fills in layout,
typography, metadata, color, tagging, and serialization policy. A visible
document title remains authored content and is created with `Pdf.title`; it is
not inferred from metadata or from the first heading. Typed document
constructors create their semantic structure automatically:

- A title block becomes the PDF 2.0 `Title` structure element independently of
  the metadata title.
- Headings carry an explicit level and become heading structure elements.
- Paragraph and inline constructors retain canonical Unicode.
- Lists create labels, bodies, and list-item relationships.
- Tables require declared headers and retain a logical grid.
- A meaningful image is constructed as a figure with author-supplied
  alternative text; a decorative image uses a separate decoration constructor
  and becomes an artifact.
- Common image constructors perform validation and make color assumptions
  explicit in their names or inputs; `Pdf.png_srgb` never guesses an unknown
  source profile.
- Links retain their text, URI or internal destination, annotation ownership,
  and keyboard order.
- Page headers, footers, numbers, backgrounds, and watermarks enter through
  artifact-specific constructors.

The API does not represent semantic decisions as booleans such as
`decorative: Bool` or `accessible: Bool`. Distinct constructors make the choice
visible and carry the fields required by that choice.

### Defaults contract

`Pdf.to_bytes` is equivalent to `Pdf.to_bytes_with(document,
Pdf.Options.default)`. This section states the enduring post-Gate-7 default
contract. During delivery, the roadmap advances the default only to a public
profile whose complete claim set has been implemented and validated; an
unfinished claim is never selected implicitly. The enduring defaults are:

- PDF version 2.0 only; no legacy output.
- `AccessibleArchive`, requiring the combined `Pdf20 + StaticPdfA4 + PdfUa2`
  claim set in the mapping above.
- Tagged output derived from the typed document structure.
- Canonical XMP whose `dc:title` agrees with the authored metadata title, and
  catalog `/ViewerPreferences << /DisplayDocTitle true >>`.
- The required catalog `/MarkInfo` and page `/Tabs` values for the selected
  tagged and PDF/UA-2 claims, as defined clause-by-clause in the conformance
  ledger.
- Embedded and deterministically subsetted package fonts with known embedding
  rights; no system-font lookup or substitution.
- The pinned sRGB output intent and color-managed static profile.
- Deterministic object planning, metadata, identifiers, compression, and byte
  output.
- Chunked output shares unchanged final-form resources by default; callers that
  retain or queue chunks can request bounded owned chunks without changing
  bytes.
- A readable built-in theme, A4 pages, and conservative margins, all
  explicitly overridable through typed options or a `Theme`.
- No current timestamp unless the author supplies one.
- No encryption, scripts, forms, external rendering dependencies, or other
  features outside the static package policy.

Changing a default in a way that changes document semantics, conformance, or
bytes is a reviewed package-version change.

The facade never silently weakens these defaults. If accessible archival output
cannot be produced, `Pdf.to_bytes` returns a structured error explaining the
missing author fact or unsupported feature. As an intentional facade policy,
`AccessibleArchive` additionally requires a visible semantic `Title` block
that is distinct from the metadata title. PDF/UA-2 itself requires the metadata
title and title-display preference, not a visible `Title` structure element;
this stricter requirement is a package usability policy intended to keep the
default document's visible and reader-displayed identity explicit. `Archive`
and `Standard` do not impose that extra visible-title policy. Authors who
intentionally need a less constrained PDF select `Archive` or `Standard` with
`Pdf.Options.with_profile`; this is an opt-out, not an automatic downgrade.

```roc
options = Pdf.Options.with_profile(
    Pdf.Options.default,
    Pdf.Profile.Archive,
)

Pdf.to_bytes_with(document, options)
```

Defaulting to PDF/UA-2 does not certify the quality of prose, alternative text,
reading order, or table design. Supplying those semantic values is an author
assertion, and the human-verifiable requirements described later still apply.

### Advanced integration boundary

The stable integration boundary is `PreparedDocument`, conceptually containing:

```text
PreparedDocument
|- authored metadata, language, and output intent
|- one PDF 2.0 Document root and its ordered semantic content spine
|- resolved layout-dependent references
|- content occurrences and their layout-fragment mappings
|- laid-out pages
|  `- fragment-owned or page-artifact-owned scene groups
`- validated resources
   |- exact font faces
   |- raster or inspected encoded images
   `- ICC profiles and typed color spaces
```

Every reference that can affect layout is resolved before this boundary. A
`PreparedDocument` never contains an approximate page number, unresolved
counter, guessed reference width, or incomplete continuation.

This boundary allows a simple layout system supplied with the package and
independent pure Roc layout systems to target the same PDF generator. PDF
lowering does not depend on a particular layout engine.

The advanced conceptual lifecycle uses `Try`, current Roc's fallible-result
type:

```roc
prepare : DocumentInput -> Try(PreparedDocument, List(Diagnostic))

conform :
    PreparedDocument,
    Conformance
    -> Try(SealedPdfPlan, List(Diagnostic))

encode : SealedPdfPlan -> List(U8)
```

`SealedPdfPlan` is opaque. `conform` normalizes the prepared document, applies
the requested profile, lowers it to the exact PDF object plan, validates that
plan, and seals it. Convenience functions may compose these operations, but
byte emission accepts only the sealed result and has no user-data error path.

## Semantic document graph

The semantic document is the source of meaning and logical reading order. It
has exactly one top-level `Document` element in the PDF 2.0 namespace. A
`DocumentFragment` is a descendant rather than an alternative root.

Every semantic node has one structural parent and an ordered content spine.
The spine, rather than a separate child list, may contain:

```text
SemanticContent :=
    ChildNode(SemanticNodeId)
    ContentOccurrence(ContentOccurrenceId)
    AnnotationOccurrence(AnnotationId)
    ContextualArtifact(ContextualArtifactNodeId)

ContentOccurrence
|- canonical text or non-text source range
|- semantic properties and logical position
`- zero or more LayoutFragmentId values

LayoutFragment
|- content occurrence and continuation identity
|- page and content-stream placement
|- exact source subrange
`- painted scene nodes
```

This mixed order is preserved through normalization and becomes the source of
PDF structure-element `/K` ordering. A later stage never attempts to insert a
node among direct content by consulting paint order or fragment geometry.

The graph also contains:

- Opaque semantic node, content occurrence, layout fragment, namespace,
  annotation, and emitted structure-element IDs allocated independently of PDF
  object numbers.
- Roles identified by namespace identity and local name.
- Typed PDF 2.0, PDF 1.7/ISO 32005, MathML, and supported extension
  namespaces, with namespace-scoped role mappings.
- Typed structure attributes carrying their owner, value type, and
  applicability, including Layout, Table, List, Artifact, and namespace-owned
  attributes.
- Document and nested language values.
- Alternative, expanded, replacement, actual, phoneme, and phonetic-alphabet
  text properties where applicable.
- Explicit relationships between links, annotations, destinations, notes,
  labels, headers, cells, captions, figures, and formulae.
- Author assertions that cannot be mechanically proven, retained as such.

Namespace identity is not reduced to URI equality. Two namespace objects with
the same URI remain distinct when the applicable standard requires distinct
element and attribute namespace references. Role mapping and deduplication
consume namespace IDs, not a URI-only digest.

Headers, notes, references, destinations, annotations, and similar non-parental
associations use separately typed cross-relations. They never turn containment
into a multiple-parent DAG.

The enduring vocabulary includes document and fragment roots; titles, parts,
divisions, headings and paragraphs; inline emphasis and code; quotations and
notes; lists with labels and bodies; tables with a logical grid; figures and
captions; links and structured destinations; footnotes and side content;
tables of contents and indexes; and formulae with accessible semantics.

Metadata title, visible title content, the PDF 2.0 `Title` structure element,
and numbered headings remain distinct. Heading depth is represented as data
rather than a union limited to six levels. PDF/UA-2 lowering emits explicit
`H1` through `Hn`, never a generic `H`, and validates the selected heading
progression policy.

Tables retain row groups, rows, cells, row and column spans, scopes, IDs, and
explicit header relationships. The normalized graph contains the emitted
structure IDs, IDTree membership, and typed `Headers` associations. Flattening
a table to positioned boxes before semantic validation is forbidden.

Parent-child legality is not represented merely by `role` and `children`.
Normalization checks namespace-aware containment, required attributes, role
mapping, and content-specific constraints against ISO/TS 32005 and PDF/UA-2.

Page-content artifacts and contextual Artifact elements have separate types.
A page-content artifact is painted but excluded from the logical structure.
A contextual Artifact element occupies an explicit place in the content spine
and carries its required Artifact structure attributes.

MathML is a typed namespaced subtree or the output of a bounded, validating
pure Roc parser. Unchecked markup is never copied into a structure element or
associated file. MathML as an Associated File is a distinct `PdfA4f`
capability; it is not silently substituted for structure-element MathML.

## Layout, shaping, and stabilization

The built-in authoring path and independent layout packages target an explicit
fragmentation contract. The concrete Roc API may use data and functions rather
than an object-shaped interface, but it preserves these operations and outputs:

```text
LayoutComponent
|- measure(constraints, style, validated resources)
|- fragment(constraints, continuation)
`- output
   |- fragment geometry
   |- Complete or typed continuation
   |- content-occurrence mappings
   |- resource uses
   `- deterministic diagnostics
```

The contract represents legal line, column, and page breaks; before/after
spacing; keeps; widow/orphan constraints; repeated table headings; and
footnote, float, or side-content participation where the selected capability
supports them. A continuation contains only explicit state needed to resume the
same component. A consumer does not remeasure previous fragments to recover it.

This is also the safe extension boundary for charts, callouts, invoice widgets,
and other domain-specific blocks. Each extension supplies its semantic
occurrences or explicit page artifacts and lowers visual content to validated
scene nodes. Raw PDF objects and operators are not extension points. A separate
pure Roc SVG or vector package may target the scene boundary; rasterization is
not a fallback.

Layout-dependent references are symbolic before layout and fully resolved in a
`PreparedDocument`. Stabilization is deterministic:

1. Each pass consumes an explicit reference state.
2. It outputs the complete resolved-reference and pagination state.
3. An identical consecutive state is success.
4. Repetition of an earlier non-identical state is a cycle and an error.
5. An explicit pass or work budget may report exhaustion, but no attempted
   state is accepted as an approximation.

This covers counters, tables of contents, indexes, page references, footnotes,
and total-page labels without guessed widths or reserved placeholder digits.

Before shaping, a deterministic `FontPlan` maps source scalar ranges to exact
validated font instances:

```text
theme font policy + text + script + language
                       |
                       v
          exact ordered font-face ranges
                       |
                       v
               shaping and layout
```

A font policy contains a finite ordered set of exact packaged or caller-
provided faces, explicit coverage, supported scripts, embedding rights, and
exact font instances. The type can represent a variable-font instance only when
that future capability is selected; the initial policy accepts static
instances. Selection uses those facts rather than system lookup or best-effort
fallback. Uncovered scalars and unsupported shaping are errors before final
layout.

## Page scenes and content ownership

Pages contain a balanced scene tree rather than raw PDF content operators:

```roc
OwnedGroup := [
    Fragment(LayoutFragmentId, List(DrawNode)),
    PageArtifact(PageArtifactKind, List(DrawNode)),
]

DrawNode := [
    Transform(Matrix, List(DrawNode)),
    Clip(Path, List(DrawNode)),
    Opacity(OpacityGroup, List(DrawNode)),
    DrawPath(PathStyle, Path),
    DrawText(TextPaint, GlyphRun),
    Image(ImagePlacement),
]
```

The concrete Roc representation may differ, but it preserves the following
properties:

- Graphics-state nesting is balanced by construction.
- Raw `q`, `Q`, `BT`, `ET`, marked-content, or arbitrary operators are not
  public.
- A content occurrence may produce many fragments on many pages and streams.
- Paint order may differ from logical child order.
- Repeated headers, footers, page numbers, backgrounds, watermarks, and layout
  decoration are explicit artifact kinds.
- Annotations remain structured semantic objects rather than late additions to
  a page dictionary.

Tagged-PDF lowering, not the caller, assigns MCIDs, marked-content references,
`StructParent`/`StructParents` values, ParentTree entries, annotation object
references, and final structure-element object references.

An expert fixed-layout API may construct page scenes directly, but PDF/UA-2
output remains available only when every scene group has fragment or page-
artifact ownership and the complete semantic graph and occurrence map are
supplied. A canvas-only document cannot claim PDF/UA-2.

## Text and font boundary

The PDF package consumes positioned glyph runs, not unshaped strings:

```text
GlyphRun
|- exact validated font instance
|- content occurrence ID and exact scalar range
|- glyph IDs, advances, and offsets
|- explicit range-relative Unicode-to-glyph cluster mapping
|- script, language, direction, and writing mode
|- substitution and ligature evidence
|- source-to-presentation transformations
`- reference to an explicit semantic ActualText override when present
```

Cluster mappings support one-to-one, one-to-many, many-to-one, combining,
ligature, reordered, bidirectional, and context-dependent relationships. This
evidence allows lowering to choose exact CID allocation, `ToUnicode` mappings,
and `ActualText` without guessing.

The content occurrence is the sole source of logical Unicode and text
ownership. A glyph run covers an exact range of that occurrence and supplies
only the shaping and presentation evidence for that range. An `OwnedGroup`
supplies placement ownership; the run does not duplicate it. Emitted
`ActualText` comes from the occurrence range or its explicit semantic override,
never a second run-local string.

Presentation evidence explicitly covers inserted discretionary hyphens,
suppressed soft hyphens, generated labels and counters, ligature replacement
boundaries, case transformations, bidirectional logical versus visual order,
and supported graphics representing textual content. Lowering never infers
whether a visible glyph belongs in extraction.

`TextPaint` contains only the supported visual policy: fill or stroke color,
opacity, and an allowed rendering mode. The initial policy permits visible fill
and, when implemented, fill-and-stroke. Invisible OCR text, clipping text, and
other rendering modes require separate capabilities.

Text shaping, bidirectional resolution, line breaking, hyphenation, and
pagination are not serializer responsibilities. They may be separate pure Roc
packages. Their interchange types must preserve all information required for
search, extraction, accessibility, and deterministic subset construction.

Font processing is a separate pure Roc component with bounds-checked parsing,
embedding-rights inspection, exact font-instance identity, composite-glyph
closure, deterministic subsetting, CID assignment, widths, CMaps, and font
descriptor generation. Initial support may be limited to TrueType-flavoured
OpenType, with other formats rejected explicitly.

Font tables remain offset/length ranges into one validated font byte resource.
Coverage, `cmap`, GSUB, and GPOS data are compiled once per exact face. Shaping
uses contiguous glyph/cluster buffers and pass-oriented substitution rather
than repeated list insertion. Used glyphs accumulate once per font in a dense
bitset or an equivalently bounded ordered set; composite closure is computed
once; subset table sizes are known before each table is written once. Font
selection operates on grapheme clusters rather than independent scalars and has
an explicit worst-case search bound.

Every font used by `StaticPdfA4` is embedded. A font that forbids embedding is
rejected before final layout. Font substitution and text outlining are not
conformance repairs because they change metrics or destroy searchable semantic
text. `.notdef` is never emitted as content, and every character code has the
required Unicode relationship.

## Images and color

Images enter the PDF core only as validated forms:

- A raster image with checked dimensions, explicit typed color space, pixels,
  and optional alpha.
- An encoded JPEG produced by a bounds-checked inspector that records every
  property required for safe embedding and outputs an allowed, sanitized
  marker sequence.
- Additional encoded formats only when their parser and selected profile make
  their properties explicit.

PNG is an input transport format, not a PDF image representation. A pure Roc
image package decodes it to validated channels. Alpha becomes an explicit soft
mask. Alternative text belongs to the owning semantic figure, not to a reused
image resource.

Raster planes are packed byte buffers rather than lists of pixel records.
Decode, alpha separation, predictor filtering, supported color conversion,
hashing, and compression accept rows or coarse chunks so the pipeline does not
require simultaneous whole-image copies of every intermediate plane. Repeated
placements carry one image resource ID. A future encoded PNG fast path requires
a separately specified fully validated subset; it is never unchecked
passthrough.

JPEG orientation policy is explicit. A constructor either applies a validated
EXIF orientation before creating the image placement, or states that the input
must already be in display orientation and rejects a conflicting orientation.
It never silently ignores orientation-bearing metadata. Irrelevant application
and comment metadata is not copied into the PDF image stream.

Color component counts cannot be untyped arrays. A color value identifies its
space. The static PDF/A policy begins with a licensed, embedded sRGB ICC
profile, an sRGB output intent, explicit treatment of source image profiles,
and an explicit transparency blending space. All profile assets have recorded
provenance, license, and digest.

The initial static color and transparency whitelist contains ICCBased sRGB,
calibrated grayscale, Normal blending, constant opacity, alpha soft masks, and
isolated groups where required. Axial/radial shadings and colored tiling
patterns are added only through explicitly bounded subsets. CMYK, Separation,
DeviceN, spot color, overprint, luminosity masks, non-Normal blend modes, and
complex nested mask/group combinations are separate capabilities.

## Resources and annotations

Resource identity describes reusable visual data, never semantic ownership or
an eventual object number. Fonts, image bytes, ICC profiles, and Form XObjects
are ownership-neutral; each placement carries fragment or page-artifact
ownership.
Normalization determines use, validates it, closes dependencies, and performs
deterministic deduplication using a digest plus exact equality. Deduplication
may share resource bytes but never merges semantic wrappers, MCIDs, annotation
associations, or artifact classifications. Each meaningful Form XObject
placement receives a placement-specific semantic association. If the tagged
PDF machinery cannot express safe reuse for those associations, lowering
duplicates the object deterministically rather than sharing it. Artifact-only
forms may remain ownership-neutral and reusable.

Each resource is inspected and hashed once. A digest collision bucket is
partitioned by exact descriptor and byte length, then exact-deduplicated with a
deterministic bytewise radix/trie ordering and adjacent equality checks. Its
declared work is bounded by bucket entries plus input bytes, rather than all-
pairs comparison. Collision and compared-byte totals consume explicit resource
work limits.

Resources form an explicit acyclic dependency graph. Forms, masks, patterns,
fonts, ICC profiles, and images name every direct resource dependency.
Normalization rejects cycles, proves that all reachable dependencies close,
orders resource planning deterministically, and proves that each content stream
has a complete direct resource dictionary. The graph stores direct edges and
does not materialize a transitive-reachability set for every node. Resource use
is never recovered by scanning serialized operators.

An inspected resource is safe for the Roc implementation to process; a
sanitized resource is also safe to hand to downstream PDF readers within the
implemented format subset. Embedding requires the latter. Font subsetting
constructs a fresh font from an allowlist of validated tables with explicit
policies for overlapping tables, checksums, composite cycles, instruction and
hinting data, private tables, variation/color tables, and table order. JPEG and
ICC outputs follow equivalent allowlist policies. Arbitrary input containers
are not copied wholesale into a valid PDF wrapper.

Annotations are first-class structured values carrying:

- Their semantic owner and annotation-occurrence identity.
- Page association, `Rect`, and fragmented-link quadpoints.
- Normal appearance scene, bounding box, and matrix.
- Display and print visibility flags.
- Logical and keyboard order.
- Action or destination from a closed supported union.
- Description and other accessibility properties when required.
- Profile eligibility.

Annotation appearances are subject to the same font, color, graphics, and
content-ownership rules as ordinary page content. Arbitrary actions and raw
annotation dictionaries are unavailable.

The initial annotation union contains URI links and internal GoTo links. Each
linkable internal target names both a semantic structure target and an explicit
layout anchor occurrence. After layout, `PreparedDocument` resolves that anchor
to a deterministic geometric destination using its exact page and fragment
geometry. Lowering emits every internal GoTo action with both `/SD`, identifying
the structure destination required by PDF/UA-2, and `/D`, identifying the
geometric destination used by current readers. A target without a resolvable
geometric anchor is rejected rather than emitted as an `/SD`-only link.

Named destinations are the deterministic reusable registry for authored public
destination names, outlines, cross-references, and other features that refer to
a destination by name. A named destination associated with a semantic target
contains the same paired structure and geometric destination facts. It does not
replace the direct `/SD` plus `/D` pair on a link's GoTo action. Structure and
geometric targets are validated to identify the same authored destination, and
navigation tests exercise the geometric fallback independently of structural
inspection. This policy implements the pinned Errata Collection 3 resolutions
for issues 140 and 162 without assuming that shipping readers navigate `/SD`.

Rollover/down appearances and every other annotation type are unsupported until
a separate capability defines their structure ownership, OBJR, appearance,
focus behavior, and profile rules.

## Conformance validation

Validation occurs at three explicit boundaries:

1. **Authoring validation** checks graph identity, reachability, acyclicity,
   ordered content spines, semantic containment, namespace identity,
   structure attributes, table geometry, occurrence/fragment coverage, scene
   ownership, glyph clusters and presentation evidence, resource references,
   annotations, and author obligations.
2. **Profile validation** checks every requested PDF/A-4, PDF/UA-2, and WTPDF
   rule that applies to the prepared representation.
3. **Lowered-plan validation** checks exact objects, references, streams,
   namespaces, ParentTree relationships, metadata agreement, and forbidden
   constructs before sealing the plan for serialization.

The static profile is implemented as a whitelist of supported constructs.
Adding a feature requires declaring its profile eligibility and conformance
rules; absence from the whitelist is rejection, not best-effort output.

Conformance metadata is emitted only for claims requested by the author and
successfully validated. A declaration is not itself proof of conformance.

Diagnostics are deterministic structured values containing a stable project
code, document/resource location, applicable internal requirement IDs,
standards clause references, and concrete details. Advice that does not affect
validity is kept separate and never changes output.

## Internal PDF object plan

Only typed lowering modules may construct the private generic object model:

- Null, boolean, integer, and canonical finite real.
- Validated name.
- Text string and byte string as distinct types.
- Array and unique-key dictionary.
- Indirect reference.
- Stream with explicit dictionary, bytes source, and filter plan.

Before serialization the plan establishes:

- Every indirect object and reference.
- Object order and generation number zero.
- Resource names and ownership.
- Stream length strategy.
- Complete page, structure, ParentTree, name, number, ID, and outline trees.
- Xref representation and trailer data.
- Metadata, identifiers, output intents, and conformance declarations.

All references resolve; dictionary keys are unique; counts and offsets fit
their defined integer types; numeric operands are finite; every rendered
resource is declared; and every tagged content item has a valid semantic
parent.

Large index structures use reusable deterministic balanced builders. Each
balanced tree kind defines a fixed maximum fanout, partitioning rule, ordering,
exact `Count` and `Limits` behavior where applicable, checked key uniqueness,
and monotonicity. The output does not change from a flat to a balanced
representation based on an undocumented size heuristic.

Document outlines are ordered linked hierarchies rather than balanced search
trees. Planning preserves authored preorder and open/closed state and seals
exact parent, sibling, first/last-child, and visible-descendant `Count` facts.
It never inserts synthetic grouping items to balance sibling lists because
those items would alter the visible document outline. Entry and depth limits
are explicit and checked before an outline plan can escape.

The initial file representation uses PDF 2.0 xref streams. Object streams are
an independent compression optimization and are not required by the
architecture. Incremental revisions and linearization are outside the
generation-only baseline.

The Arlington PDF Model is a useful independent schema cross-check, but its
documented scope excludes parts of lexical syntax, content streams, and file
structure. It informs tests; it is not the architectural source of truth.
[Arlington PDF Model](https://github.com/pdf-association/arlington-pdf-model)

## Deterministic serialization

Determinism is part of the public contract:

- Numbers use a canonical, locale-independent finite decimal representation;
  negative zero is normalized.
- Pages, semantic nodes, scene nodes, and resources have defined traversal
  orders.
- Object numbering and resource naming never depend on hash-map iteration.
- IDs and names are assigned during planning, not public document construction.
- Names, strings, XML, and content tokens use canonical escaping.
- Dictionary and XMP property ordering is defined.
- Newlines and compression parameters are fixed.
- Font subset prefixes and glyph order are deterministic.
- Timestamps are explicit inputs or omitted when optional.
- Document identity is explicit or derived by a specified digest procedure.
- Deduplication confirms exact equality after a digest match.

Roc numeric inputs that cannot be represented exactly enough by the supported
PDF scalar type are rejected. Host floating-point formatting is not used to
write PDF syntax.

## Pure output and chunked delivery

The convenient API returns `List(U8)`. `Pdf.to_chunks` and
`Pdf.to_chunks_with` validate and seal the document, then return an opaque
encoder over the same compact plan and internal emission transition used by
the buffered path. Platforms can write its chunks without the package
performing effects:

```roc
Pdf.next_chunk : Encode -> [Done, Emit(List(U8), Encode)]
```

The buffered and chunked APIs drive the same internal emission transition, so
their forms are byte-identical. The buffered path supplies its final unique
accumulator directly; it does not allocate public owned chunks and copy each
one, nor collect a list of chunks before concatenation. Because all user-data,
conformance, size-bound, and safe-output-bound errors occur before sealing,
`next_chunk` has no document-error branch and cannot emit a partial file
followed by a validation failure.

Generated chunks have bounded independently owned backing allocations. When a
validated JPEG, ICC profile, or other resource range is already exactly the
bytes required by the PDF stream, the default chunk policy may instead return
a seamless slice of that resource allocation. Such a slice is immutable and
avoids copying, but retaining even a small slice can retain the whole source
allocation. The package does not place resources eligible for sharing into a
combined backing arena, and the encoder drops its reference after the last
range. A caller-supplied resource can nevertheless already be a view into a
larger caller allocation, which is then the allocation a returned slice
retains. Callers that retain or queue chunks can select `OwnChunks`, which
copies resource ranges into bounded owned chunks and gives predictable output-
chunk retention. Generated syntax, DEFLATE output, subsets, transformed raster
data, and views into large internal stores are never shared this way.

`Pdf.Options.default` selects `ShareUnchangedResources`, optimized for a sink
that consumes and releases each chunk before requesting the next one. The
choice affects allocation, copying, and retention only; it cannot affect PDF
bytes. `Pdf.to_bytes` necessarily copies resource ranges into its single final
contiguous `List(U8)`. Planning assigns every object and indirect stream-length
ID before emission, and emission tracks a compact `U64` offset list. Stateful
lexical, DEFLATE, and resource encoders produce stream bytes without
materializing whole uncompressed and compressed copies.

This is a bounded-retention design, not a constant-memory claim. The compact
sealed plan, validated live resource bytes, global font subset facts, structure
and destination data, object offsets, compressor state, owned output chunks,
and source allocations pinned by caller-retained seamless slices remain
necessary. Callers who retain earlier immutable stages, slices, or old encoder
states intentionally retain additional data.

All byte counts, offsets, object counts, image dimensions, allocation sizes,
font table arithmetic, decompressed sizes, recursion depths, and compression
inputs use checked arithmetic and explicit resource limits. Font, JPEG, PNG,
ICC, and other externally supplied bytes are untrusted even though the package
does not read PDFs.

## Module boundaries

Conceptual public modules are:

- `Pdf`: facade and one-shot operations.
- `Document`: semantic document, consumption-shaped compact builder, and
  prepared-document construction.
- `Semantics`: roles, relationships, artifacts, and semantic builder.
- `Layout`: measurement, fragmentation, continuations, reference
  stabilization, and accessible custom-block integration.
- `Scene`: geometry and balanced fixed-layout scene trees.
- `Text`: shaped-run interchange values.
- `Font`: validated font resources.
- `Image`: validated raster and encoded images.
- `Color`: typed color spaces, ICC profiles, and output intents.
- `Metadata`: logical metadata and author assertions.
- `Conformance`: capability selection and structured diagnostics.
- `Encode`: buffered bytes and pure chunk encoding.
- `Theme`: typed convenience-layout typography, spacing, and visual policy.

Consumers import these as `pdf.Document`, `pdf.Scene`, and so on. A dot after
the lowercase package shorthand selects an exposed type module; nested types
such as `Pdf.Options` use subsequent dots as defined by modern Roc's module
syntax.

Internal modules own normalization, resource analysis, font subsetting and CID
mapping, tagged-PDF lowering, profile rule validation, object planning, the PDF
object representation, content serialization, xref generation, and lexical
byte emission.

Separate pure Roc packages may own shaping, OpenType parsing, image decoding,
XML/XMP construction, hashing, ICC inspection, and DEFLATE. Integration occurs
through validated data types, not private representation coupling.

## Enduring test architecture

Five claims are tested independently:

1. Readers accept the bytes.
2. Independent renderers produce the intended appearance.
3. The file and object model satisfy ISO 32000-2.
4. The file satisfies each declared PDF/A-4, PDF/UA-2, or WTPDF profile.
5. Human users can navigate and understand the authored semantics.

No tool is the specification or the sole oracle. Python invokes a compiled Roc
scenario application and then runs layered checks against the original,
unmodified bytes:

```text
typed versioned scenario
          |
          v
compiled Roc generator
    |              |
    |              `- structured error and no bytes
    v
PDF bytes + normalized generation report
          |
          +-- exact byte/file checks
          +-- independent parsing and object inspection
          +-- Arlington schema checks
          +-- independent rendering and text extraction
          +-- explicit veraPDF profile validation
          +-- normalized semantic-spine inspection
          +-- normalized occurrence-to-fragment inspection
          `-- human accessibility protocol where required
```

Tools do not rewrite or repair a file before it is checked. Parser recovery and
warnings fail tests. Tool disagreements retain original bytes and raw reports,
are minimized to a semantic scenario, and are decided against the pinned
standard and errata. Known tool defects live in a version-scoped exception
ledger; majority behavior does not define correctness.

The test suite maintains a machine-readable conformance ledger. Each internal
requirement records the relevant standard clauses, applicable capabilities,
machine and human verification status, positive and negative scenarios, and
external validator rule identifiers. The prose examples in this architecture
are not an exhaustive checklist: mechanical requirements such as XMP
`dc:title`, `/ViewerPreferences /DisplayDocTitle`, `/MarkInfo`, and page `/Tabs`
are implemented because their pinned clauses appear in the ledger, not merely
because they are named here.

Every public API example is also a compile fixture checked with the Roc version
pinned by the package. Documentation must not preserve obsolete module,
function, collection, or fallible-result syntax. The one-import facade examples
are tested separately from advanced integration examples so internal types do
not leak into the common path accidentally.

Every feature fixture has a small semantic source, selected capabilities,
expected generation result, normalized content spine, occurrence-to-fragment
map, lowered structure order, text and reading order, visual assertions,
validator expectations, human checks where applicable, asset provenance, and
an atomic negative twin. Validation failure is transactional and produces no
partial PDF.

Determinism tests compare byte hashes across supported operating systems and
architectures. Property tests randomly compose small typed semantic and visual
constructs, including explicitly valid and invalid trees, tables, glyph runs,
graphics nesting, and resource sharing. Bounded stress suites separately cover
large offsets, page and object counts, balanced page/name/number/ID trees,
subsets, MCIDs, streams, resource dependency graphs, and deep legal
structures.

Attacker-controlled binary inspectors have a separate fuzzing lane. It mutates
small valid and invalid font, JPEG, PNG, and ICC corpus seeds and invokes the
pure Roc inspection boundary under deterministic input-size, work, memory, and
diagnostic limits. Coverage-guided generation is used when Roc tooling exposes
reliable coverage; otherwise deterministic corpus mutation is required. A
panic, out-of-bounds access, non-termination, uncontrolled allocation, or
acceptance of an unsanitized resource is a failure. Minimized reproductions are
retained with asset provenance and promoted to ordinary regression tests. This
lane complements rather than replaces typed construct generation and atomic
hand-authored negative twins.

Performance evidence uses pinned optimized Roc builds and combines controlled
timing and peak-RSS jobs with deterministic operation counters. Every focused
test case records the exact number of Roc allocations after resetting the
allocator counter at its declared Roc measurement boundary. Whole-pipeline
cases reset before authoring construction; phase cases reset immediately before
the operation they isolate. Python harness and external-tool allocations are
excluded. The baseline identifies compiler revision, target, optimization
mode, scenario revision, and measurement boundary, because exact counts are
comparable only under the same configuration. An increased count fails review
until its ownership or representation cause is understood and the checked-in
baseline is accepted deliberately; a decrease is also recorded deliberately
rather than silently rewriting expectations.

A pinned Roc compiler or target upgrade uses an explicit bulk re-baseline
procedure rather than treating every changed count as an implementation
regression. The old and proposed toolchains run the full allocation suite on
the same controlled host and inputs; all outliers and a representative sample
from every subsystem are investigated alongside deterministic work, copied-
byte, ARC, timing, and retained-memory evidence. The review records the
toolchain change as the shared cause, separates any feature-caused deltas, and
updates `.roc-version`, compiler metadata, and allocation baselines atomically.
Unexplained outliers or changed algorithmic counters block the upgrade.

Allocation count is a design signal, not the sole performance oracle. Each
phase also records input/output counts, node and edge visits, allocated bytes,
bytes copied, live/retained bytes, ARC operations where instrumentation exists,
cache entries/hits, layout passes, resource hashes and collision-equality work,
time to sealed plan, time to first chunk, and total output. Ordinary tests
assert declared linear, `O(n log n)`, or pass-multiplied-linear bounds through
operation counts rather than fragile wall-clock thresholds. Slice-output tests
separately cover immediate consumption and retained small slices of large
resources so a lower copy count cannot hide excessive source retention.

The benchmark corpus scales homogeneous documents through 1, 10, 100, 1,000,
and 10,000 pages and includes million-node/object/tree cases; one source range
split into many fragments; huge paragraphs and tables; stable and cyclic
layouts; one large image placed many times; one shared font and many one-use
fonts; digest-collision injection; sorted/equal ordering inputs; retained
chunks; unique and deliberately shared pipeline values; and offsets beyond 4
GiB through a counting sink. Hot-loop codegen audits require no allocation or
ARC operation per emitted byte, glyph, path command, or object in selected
kernels. Direct loops and proposed `Iter` implementations are compared under
the same optimized build before an iterator becomes a hot-path choice.

Ordinary CI uses PDFium and PDFBox as independent reader/render/extraction
paths. PDF.js adds browser text-, annotation-, and structure-layer coverage.
MuPDF or Poppler extends graphics diversity; Ghostscript is used for declared
advanced color and print capabilities. These engines have distinct configured
expectations and do not vote on correctness.

veraPDF is invoked with the explicit `4`, `ua2`, and `wt1a` profiles as
applicable rather than relying only on metadata autodetection. The validator
executable and validation-profile revisions are pinned independently.

veraPDF formalizes PDF/A-4, PDF/UA-2, and WTPDF rules, but its PDF/UA checks are
limited to machine-verifiable requirements. This limitation is why the human
review protocol is an architectural requirement rather than a release
afterthought. [veraPDF validation documentation](https://docs.verapdf.org/validation/)

## Security and resource policy

Although generation is pure and effects-free, supplied assets are attacker-
controlled byte sequences. Every parser is bounds checked, cycle aware where
applicable, and limited by explicit policy. Errors include the precise asset
and failed bound.

One typed `ResourcePolicy` record applies across authoring, layout, shaping,
resource processing, conformance, lowering, compression, and emission. It has
dimension-specific limits for semantic depth and node counts; content
occurrences and fragments; pages and scene nodes; reference and resource-graph
sizes; font tables, glyphs, and composite depth; encoded and decoded image
sizes; ICC tags; metadata and XMP sizes; diagnostics; MCIDs and ParentTree
entries; comparison, hashing, and compression work; and total output. Every
allocation and multiplication derived from input uses checked arithmetic.

The package never executes embedded code, dereferences external visual or file
resources, loads system fonts, consults environment locale or time, or performs
network access. Supported URI link actions merely record an author-supplied URI
for a reader; they do not supply rendering resources. Remote-file destinations
and external rendering dependencies remain rejected. All fonts, profiles,
images, metadata, timestamps, and identifiers are explicit inputs or documented
deterministic assets.

## Rejected alternatives

- **PDF 1.x as the internal model:** legacy output is not a goal and must not
  constrain PDF 2.0 semantics.
- **Canvas-only design with tagging added later:** semantics, reading order,
  tables, Unicode relationships, and artifacts cannot be recovered reliably.
- **Coordinate-based reading-order inference:** paint geometry is ambiguous and
  can legitimately disagree with logical order.
- **Public dictionaries or content operators:** arbitrary injection defeats
  package-level conformance guarantees.
- **Object IDs assigned while authoring:** this makes bytes construction-order
  dependent and confuses semantic identity with serialization identity.
- **Recursive authoring trees as normalized storage:** allocation-per-node
  values, pointer chasing, and ARC traffic prevent predictable large-document
  behavior; normalization lowers once to dense stores and flat spans.
- **Persistent whole-stage rewrites or retained rollback scenes:** keeping
  earlier lists alive defeats uniqueness and can copy growing prefixes;
  builders consume accumulators and layout commits a selected fragment once.
- **`Iter` as a universal hot-path representation:** current per-step closure,
  dispatch, and ARC costs are not assumed away; dense byte/glyph/object loops
  use the representation demonstrated fastest in optimized evidence.
- **Text shaping inside the serializer:** typography and PDF lowering have
  different responsibilities; the boundary must instead carry complete shaped
  evidence.
- **Font substitution, outlining, or rasterization:** these are observable
  changes that can destroy extraction and accessibility.
- **One combined validation/serialization pass:** it mixes standards policy
  with byte writing and invites silent repairs.
- **Floating-point syntax formatting:** platform formatting is not a canonical
  PDF representation.
- **One validator or one renderer as truth:** tolerant readers and incomplete
  validators establish different, limited claims.
- **Python or native production dependencies:** they would violate the pure Roc
  package boundary; they remain external development tools.

The defining architectural decision is that accessibility evidence crosses the
layout boundary as first-class typed data, while PDF syntax remains private and
downstream.
