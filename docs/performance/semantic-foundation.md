# Gate 6 semantic foundation: nested containers and core structure vocabulary

This slice (S3) implements `reference-documents-v2`. It makes `Pdf.part`,
`Pdf.section`, and `Pdf.division` executable over a dense nested authoring
tree, widens the kernel's semantic subset to the grouping, inline, and table
roles with an ISO/TS 32005 Table 5 containment checker, lowers node languages,
element identifiers with the StructTreeRoot IDTree, typed Table and List
attributes, and node text properties, and declares `/DisplayDocTitle` for
every tagged facade document. It closes no Gate 6 capability as a whole and
makes no PDF/UA-2 claim: `PdfUa2` stays `defined_only`.

## Scope and non-goals

In scope:

- a nested authoring tree normalized into dense preorder arenas;
- public `Pdf.part`, `Pdf.section`, and `Pdf.division` (`Part`, `Sect`, `Div`),
  replacing the `Pdf.section : Str` placeholder;
- the kernel role vocabulary Part, Sect, Div, DocumentFragment, Caption, Span,
  Em, Strong, Code, Quote, Table, THead, TBody, TFoot, TR, TH, and TD;
- a table-driven parent/child containment checker with content-item,
  at-most-one, and Caption-position rules;
- typed element identifiers, `HeaderFor`/`CaptionFor`/`LabelFor` relations,
  and Table/List-owned node attributes;
- lowering of `/Lang`, `/ID`, `/IDTree`, `/A`, `/Alt`, `/E`, and `/ActualText`,
  and catalog `/ViewerPreferences << /DisplayDocTitle true >>`;
- PDF/UA-2 ledger requirements, an independent structure checker, and tests.

Not in scope: public constructors for inline content, languages, tables,
lists with `ListNumbering`, or captions (later Gate 6 slices); role maps,
MathML, author assertions, per-role attribute lists, and Layout- or
namespace-owned attributes, which remain rejected; any layout effect of
grouping.

## Authoring tree

`Document.Block` gains `Container({ contents, kind })` with
`ContainerKind : [Division, Part, Section]`. The authored value is recursive,
but normalization walks it with an explicit frame stack, allocated only when a
document has containers, so authored nesting never becomes Roc call depth.

`Document.NormalizedAuthoring` stays flat for layout:

- `blocks` is the leaf list in authored preorder, exactly as before, and each
  `NormalizedBlock` gains `parent` (`0` for the Document root, `g + 1` for
  group `g`);
- `groups : List(NormalizedGroup)` is the container arena in preorder. Each
  record holds `parent`, the contiguous leaf span `first_block..block_end`,
  the contiguous descendant-group span `index + 1..group_end`, `depth`, and its
  `position` in its parent's authored contents.

No recursive per-node Roc value survives normalization. The compact builder
has no containers and produces an empty arena.

## Semantic planning

`KernelFacadeSemantics` allocates node identities in authored preorder: a
container's node is allocated immediately before its first descendant, or at
the end for trailing containers. A document without containers therefore
keeps its exact node, content-spine, MCID, and structure-element numbering.

The content spine begins with the Document's child list followed by each
container's child list in group order. A stable counting sort by parent builds
these spans in O(children + groups); leaf content follows in block order as
before.

Two facade rejections are stable diagnostics with no bytes. Both carry the
container's compact block path in `details`:

| Code | Family | Cause |
| --- | --- | --- |
| `semantics.container_depth` | `BudgetExceeded` | More than 16 nested containers |
| `semantics.empty_container` | `InvalidRelationship` | No semantic block inside; a container holding only page artifacts is empty |

**Bounds.** The facade container depth is 16. The kernel semantic depth limit
rises from 4 to 32: Document, 16 containers, and the deepest leaf chains
(`L > LI > Lbl`, or `Table > TBody > TR > TD > P > Link` in the table slice)
stay below it, so the facade bound always rejects first. `max_attributes`
rises from 0 to 8192 and now also bounds relationships. `max_namespaces`
stays 1, because every supported role is in the PDF 2.0 namespace.

## Kernel vocabulary and containment

`KernelSemantics.role_index` maps each supported local name to a dense index;
`H1`..`H6` share the `Hn` row. The tagged-visual subset still admits only `P`.
`Link` still requires the navigation variants. A non-root `Document` is
rejected.

`containment_row` is a 28 × 28 bit matrix transcribed from ISO/TS 32005:2023
Table 5 as encoded by the pinned veraPDF 1.30.2 `PDFUA-2-ISO32005.xml` rules
("Table 5. <Parent>-<Child>"). Each child edge costs one role lookup and one
bit test. The same walk enforces:

- the Table 5 content-item rows plus PDF/UA-2 8.2.5.25: no content items in
  Document, DocumentFragment, Sect, L, LI, Table, THead, TBody, TFoot, or TR;
- the at-most-one rows (one generic H, one Caption, one THead, one TFoot, and
  one Sect per heading, as tabulated);
- PDF/UA-2 8.2.5.27: a Caption is the first or last child.

**Other validation.**

- **Element identifiers** are dense, non-empty, stored in strictly ascending
  byte order, and owned by exactly one node. Uniqueness is one adjacent
  comparison, and the IDTree lowers the same order without sorting.
- **Attributes.** Table-owned `Scope` (TH only; Row, Column, Both), `Headers`
  (TH/TD; each value an existing identifier, found by binary search),
  `ColSpan`/`RowSpan` (TH/TD, at least 1), and `Summary` (Table); List-owned
  `ListNumbering` (L, ISO 32000-2 Table 380 values). Each name occurs at most
  once per node.
- **Relations.** `HeaderFor` links a TH or TD cell to a different TH;
  `CaptionFor` links a Caption to an element that may contain one, as its
  child or sibling; `LabelFor` links an Lbl to a sibling. Other relation kinds
  are rejected.
- **Node text properties** are at most one each of ActualText, Alt, and E;
  other kinds are rejected rather than silently dropped.
- **Languages.** A non-root explicit language that differs from its nearest
  explicit ancestor must match `^[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*$`. A
  repeated inherited language was checked on its ancestor, so it costs
  nothing.

Every rejection names dense node, content, attribute, identifier, or
relation indexes; none names a PDF object.

## Lowering

`KernelTaggedObjects` emits each StructElem's entries in canonical key order
`A, ActualText, Alt, E, ID, K, Lang, NS, P, S, Type`. Nodes without extra facts
take the previous code path unchanged.

- **`/A`**: one direct dictionary per owner (`/O /Table` or `/O /List`); an
  array only if a node ever carries both. `/Headers` values lower as byte
  strings that equal the targets' `/ID`.
- **`/ID`**: the identifier bytes as a byte string.
- **`/IDTree`**: node objects are planned by `KernelObjectPlan` after the
  contextual Artifact elements and before the page tree, only when
  identifiers exist. They are emitted by the balanced name-tree lowering now
  shared with named destinations (`KernelNavigationObjects.emit_name_tree`).
- **`/Lang`**: lowered when a node's explicit language differs from the one
  it inherits. The Document inherits the catalog `/Lang`. On the kernel path
  without document facts, where no catalog `/Lang` exists, the Document's own
  language is the unexpressed default, as before.
- **`/Alt`, `/E`, `/ActualText`**: from node text properties. A Figure still
  requires `/Alt`.
- **`/RoleMap`**: never lowered, because role mappings stay outside the
  subset.
- **Catalog**: with document facts, `/ViewerPreferences << /DisplayDocTitle
  true >>` follows `/Type`.

## Ownership, copying, retention, and complexity

- **Normalization** is O(blocks + groups) with one frame stack per top-level
  container; the arena shares authored strings.
- **Planning** is O(blocks + groups). The counting sort allocates three lists
  only when groups exist. Documents without containers allocate exactly as
  before.
- **Validation** costs O(1) per edge plus O(roles) per node lookup. Identifier
  checks are O(ids × key bytes), `Headers` lookups O(refs × log ids),
  attributes O(attributes), and relations O(relations + nodes).
- **Lowering** is O(entries); the IDTree is O(ids) with the fixed fanout of 32.
- **Retention**: nothing new is retained past preparation. The normalized
  authoring value is handed to the pipeline uniquely. The container
  diagnostic path re-normalizes only on its rejection path.

## Evidence

**Package expects.**

- `KernelSemantics`: a 53-pair legal and 33-pair illegal Table 5 matrix
  expect; nested grouping with one containment check per edge; negatives for
  illegal edges, content items in Sect and LI, a duplicate THead, and a
  middle Caption; a TH/TD fixture with identifiers, typed attributes, and
  `HeaderFor`, plus negatives for duplicate, unordered, empty, and orphaned
  identifiers, a dangling `Headers` target, mistyped attributes, reversed and
  out-of-range header relations, a wrong-role caption relation, and an
  unsupported relation kind; `CaptionFor` and `ListNumbering` typing; nested,
  repeated, and malformed languages; and node text-property limits.
- `KernelObjectPlan`: IDTree node placement.
- `KernelTaggedStructure`: the `/ID`, `/IDTree`, and nested `/Lang` bytes on
  the kernel pipeline.
- `KernelFacadeSemantics`: preorder container nodes and spans, depth, and
  emptiness.
- `Pdf`: public containers, `DisplayDocTitle`, and both container
  diagnostics with their block paths.

**Harness family** `tests/containers` (`semantic-foundation-v1`, pinned
`nightly-2026-09-26-d6267b4`, cold cache, full harness order):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| nested public containers (4 deep) | 1 | 8,612 | 28 nodes, 6 containers, 27 edges, depth 8 |
| sections x10 | 2 | 17,088 | 42 nodes, 10 containers, 41 edges, 72 spine items |
| sections x100 | 11 | 148,623 | 402 nodes, 100 containers, 401 edges, 702 spine items |
| container atomic negatives | 1 | 9,255 | 5 rejections, 16-deep boundary accepted |
| kernel attribute, identifier, and language lowering | 1 | 2,488 | 3 `/A`, 2 IDTree entries, 2 `/Lang` |

The negatives are a 17-deep nesting, an empty nested division, an empty
top-level section, `table.simple` inside a section, and `document.figure`
inside a part. Each rejection returns a stable diagnostic and no bytes.

**Linear scale pair.** From x10 to x100 (10× the sections), nodes grow 9.6×,
containment edges 9.8×, spine items 9.8×, and allocations 8.7×. All are within
the linear bound.

**Independent checker.** `scripts/check_structure_semantics.py` (validator
and preflight `structure_semantics`) parses the bytes with its own value
parser. For each document it:

- derives an object-number-independent normalized tree and pins the exact
  trees of `nested.pdf` and `lowering.pdf`;
- proves ParentTree ↔ MCR and ParentTree ↔ OBJR in both directions, exactly
  once, and that page MCIDs are dense;
- checks IDTree ↔ `/ID`, `/Headers` targets, language syntax and
  non-redundancy, and typed `/A` dictionaries;
- requires `DisplayDocTitle` whenever the catalog has metadata, plus
  `/MarkInfo` and page `/Tabs /S`;
- checks containment, content items, cardinality, and Caption position
  against its own transcription of Table 5.

Its self-test covers six snapshots and 13 length-preserving mutation twins,
each rejected for its intended reason. When veraPDF is provisioned, it also
compares its table with the veraPDF ISO 32005 profile on all 784 role pairs.
It also passes on every tagged Archive and facade snapshot.

**External lanes.** veraPDF PDF/A-4 `--cases` passes every Archive snapshot,
including the four new container snapshots and the rebaselined facade
snapshots, with zero failures. `--standard-cases` passes, with the new kernel
lowering snapshot failing only the deliberate metadata omission. Arlington
`--cases` passes on every snapshot and gallery example.

## Reviewed rebaselines

Every delta below comes from a cold-cache, full-order run. Each cause was
confirmed by a same-cache A/B build that removes only the named change.

**Bytes: 28 snapshots and 9 gallery PDFs.** Every tagged document lowered with
document facts gains exactly `/ViewerPreferences << /DisplayDocTitle true >>`
in its catalog: +47 bytes, plus the dependent xref and trailer `/ID`. The
parsed object graphs are otherwise identical, and the gallery rasterizes
pixel-identically in PDFium. No other snapshot changed; documents without
containers keep their exact bytes.

**Allocations.**

- **+12 per generation with document facts** (38 cases, including the +8,
  +11, and +13 variants below; ×2 where a case generates twice). All 12 come from constructing the catalog entry: two
  interned names, a boolean, and a direct dictionary, carried through sealing,
  validation, and emission. Removing only that construction restores every
  baseline exactly.
- **+13 instead of +12** (the metadata facade negatives, navigation facade
  output and negatives, and Archive navigation x64). The 47 extra bytes cross
  one growth step of the buffered output. The same-cache A/B again restores
  the exact baseline.
- **One fewer per figure.** Figure StructElem entries are now built in one
  reserved list instead of a singleton list concatenated with the base
  entries. Archived figures (4 figures) and its Standard twin show +8, and
  the image-figure facade shows +11.
- **+1 at 1,000-node scale** (six x1000 cases). `NodeFrame` grew from two to
  four words (role index, nearest language owner). The frames list's
  byte-size-dependent growth takes one more reallocation at about 1,000 nodes
  and none at 10,000.
- **No per-block cost.** Two intermediate regressions were found and removed
  during review:
  - a nested `while` in planning cost one allocation per block (fixed by
    flattening the loop);
  - binding the normalized authoring for the error closure made it non-unique
    and cost one allocation per paragraph (fixed by re-normalizing on the
    rejection path).

  A third, revalidating repeated inherited languages, cost one allocation per
  languaged fixture node and was removed by skipping repeats.

**Work counters.** Only `output_bytes` and derived byte counters
(`chunk_offset_weight`, twin byte totals) change, by 47 per generation.

**Transient compiler crash.** The pinned compiler segfaulted in `roc check
tests/authoring/authoring.roc` in three of about ten parallel harness runs,
as first recorded in [static-pdfa4.md](static-pdfa4.md). It never reproduced
in isolation or in concurrent cold probes, and every rerun passed.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Executable: validation, lowering, IDTree planning, and allocation and work evidence for the vocabulary above |
| Facade | Executable for `Pdf.part`, `Pdf.section`, and `Pdf.division` with stable diagnostics; roles without facade constructors remain kernel-only |
| Advanced integration | Kernel store vocabulary widened; no separately authored consumer yet |
| Conformance | `DisplayDocTitle`, `MarkInfo`, page `Tabs`, IDTree integrity, language inheritance, and containment are ledger-`implemented`; `PdfUa2` stays `defined_only` |
| Reader and AT behavior | Not performed (optional) |

## Exact remaining work

- `ListNumbering` on facade bullet lists (ledger `planned`,
  `ROC-PDF-PDFUA2-8-2-5-25-LIST-NUMBERING`) belongs to the lists slice.
- Public inline, language, expansion, table, and caption constructors, and the
  `HeaderFor` ↔ `/Headers` agreement for generated tables.
- Structure-element `/Lang` does not yet lower content-occurrence languages,
  and a blank document is untagged, so it carries no `DisplayDocTitle`.
