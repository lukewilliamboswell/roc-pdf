# Static PDF/A-4: the `Archive` profile and Gate 5 closure

This slice makes the public `Archive` profile executable, closes Gate 5 on
its declared basis, and advances `Pdf.Options.default` from `Standard` to
`Archive`. `Archive` claims exactly `Pdf20 + StaticPdfA4`. `AccessibleArchive`
still rejects until Gate 7, and `Standard` remains available as an explicit
opt-out. Nothing ever falls back from one profile to another.

## Scope and non-goals

In scope:

- a typed static PDF/A-4 claim derived from the public profile's exact claim set;
- the PDF/A Identification schema (`pdfaid:part` 4, `pdfaid:rev` 2020) in canonical
  XMP, emitted only for a validated claim;
- whitelist-based profile validation over prepared facts, and lowered-plan
  validation over the sealed object store;
- a clause-by-clause conformance ledger covering every rule of the pinned
  veraPDF PDF/A-4 profile;
- independent structural, veraPDF, upstream-corpus, and renderer evidence;
- the default-profile change and its reviewed rebaseline.

Not in scope:

- PDF/A-4e, PDF/A-4f, and attachments (`PdfA4f` remains `future`);
- PDF/UA-2 and the combined claim;
- CMYK, spot colour, overprint, or any construct outside the Gate 4
  visual profile;
- a static PDF/A-4 claim through the advanced `Encode` boundary. That boundary
  has no profile input and continues to emit `Standard` output only.

## Typed claim and identification

`KernelPdfA4.Claim` is `[NoArchiveClaim, StaticPdfA4Claim]`. `Pdf.build_plan`
derives it from `Conformance.claims_for_profile(options.profile).static_pdf_a4`.
`AccessibleArchive` is rejected before any work with `FeatureUnavailable`
`profile.accessible_archive`.

The identification is a typed input, not a metadata fact:
`KernelXmp.Packet.build_identified(facts, PdfA4Identification, limit)`.

- **Canonical position.** The `pdfaid` namespace URI
  (`http://www.aiim.org/pdfa/ns/id/`) sorts after the XMP and Dublin Core URIs.
  Its declaration therefore follows `xmlns:dc`, and `part` then `rev` follow
  `dc:title`.
- **No conformance property.** No `pdfaid:conformance` is written (rule
  6.7.3-3).
- **Size.** The identified packet is exactly 112 bytes longer than the
  unidentified one, which stays byte-identical. The independent Python oracle
  in `check_metadata.py` derives the same +112.
- **Identifiers.** XMP document identifiers remain omitted. The trailer `/ID`
  digest hashes the sealed plan, including the packet, so it cannot appear
  inside it.

## Validation stages and the whitelist

`package/KernelPdfA4.roc` owns the profile boundary. It has one `Requirement`
tag per runtime-checked ledger entry, each with `requirement_code` (the ledger
id), `clause`, and an author-facing `summary`.

**Profile validation** (`validate_text`) consumes the prepared text facts that
only the text planner can state:

- the exact ToUnicode mappings retained by `KernelPdfText.ScenePlan`;
- the first ActualText run whose replacement contains a private-use scalar.
  `KernelPdfText` records this where it materializes the replacement, so
  validation never re-reads content streams.

It rejects U+0000, U+FEFF, and U+FFFE mappings (6.2.10.7) and private-use
ActualText (6.2.10.8). It performs zero allocations and is linear in mapped
scalars.

**Lowered-plan validation** (`validate_lowered`) runs on every prepared plan,
blank or authored, before it is wrapped in `Pdf.Prepared`.

For an unclaimed plan it only compares the packet's identification with the
claim. A `Standard` packet that declares PDF/A is therefore a false
declaration and is rejected without scanning.

For a claimed plan it:

1. Classifies each interned name once into a dense `List(NameClass)`. This is
   the only allocation. The same pass checks strict UTF-8 (6.1.7).
2. Checks every dictionary value and every stream dictionary against the
   whitelist:
   - **Forbidden keys:** `Encrypt`, `PieceInfo`, stream `F`/`FFilter`/`FDecodeParms`,
     `Perms`, `DestOutputProfileRef`, `TR`/`TR2`/`HT`/`HTO`, `Alternates`, `OPI`, `Ref`,
     `AcroForm`/`XFA`/`NeedAppearances`/`NeedsRendering`, `JS`/`JavaScript`, `AA`,
     `EmbeddedFiles`/`AF`, `OC`/`OCProperties`, `AlternatePresentations`/`PresSteps`,
     `Requirements`.
   - **Value checks:**
     - `Interpolate` is false;
     - `BitsPerComponent` ∈ {1, 2, 4, 8, 16}, and 1 for image masks;
     - `BM` is `Normal`;
     - `Filter` is `FlateDecode` or `DCTDecode`;
     - actions are only `URI` or `GoTo`, without `Next`;
     - annotations are only `Link`, with Print set and Hidden, Invisible,
       NoView and ToggleNoView clear; an appearance, if present, is exactly one
       `/N` stream;
     - fonts are only `Type0` or `CIDFontType2`, with a `CIDToGIDMap`;
     - font descriptors carry `FontFile2` and no other font program.
3. Checks the catalog:
   - the `/Metadata` stream is `/Type /Metadata /Subtype /XML`, unfiltered, and
     byte-equal to the claim's canonical packet;
   - there is exactly one `GTS_PDFA1` output intent whose embedded profile is an
     ICC v2–v4 `mntr` or `prtr` profile;
   - any `/Version` is 2.x.

The whitelist is closed in both directions. A new name class, action type,
annotation subtype, font subtype, or filter is not eligible until this module
lists it. Link annotations need no appearance, per pinned rule 6.3.3-1, which
exempts Popup, Link, and Projection. Facade links deliberately emit none.

Violations return the first finding in deterministic store order as
`InvalidDocument` with:

- `code: ProfileRequirementViolated`, a new public `Conformance.DiagnosticCode`;
- `feature: profile.archive`;
- the ledger requirement id and the ISO 19005-4 clause;
- `stage` set to `ProfileValidation` or `LoweredPlanValidation`;
- `location: Document`, because object identity is never exposed.

No bytes are emitted, and there is no rescan.

## Conformance ledger

`conformance/ledger.json` is now schema 2. Every requirement declares an
`applicability`: `applicable`, `rejected_by_profile`, `package_excluded`, or
`pending_iso_confirmation`.

- **Rule catalog.** `conformance/verapdf-pdfa4-rules.json` is extracted from
  the vendored veraPDF 1.30.2 installer bytes by
  `scripts/extract_verapdf_rules.py` (`PDFA-4.xml`, SHA-256 `7c1d9450…`,
  109 rules in clauses 6.1.2–6.12).
- **Coverage.** 46 `ROC-PDF-PDFA4-*` entries map every rule exactly once. Each
  names its enforcement (construction, profile validation, or lowered-plan
  validation) and its positive and negative scenarios.
- **Contract checks.** `check_contracts.py` enforces exactly-once coverage, that
  every `KernelPdfA4` requirement code is a ledger id, and that every confirmed
  `StaticPdfA4` requirement is `implemented` now that the capability is
  available. Each rule has a mutation twin.
- **Pending ISO-text confirmation.** Requirements of ISO 19005-4:2020 that the
  pinned validator profile does not encode are represented by
  `ROC-PDF-PDFA4-ISO-TEXT-CONFIRMATION`. Examples are the rendering-intent,
  digital-signature, and general clause text. They were derived from public
  information and are covered mechanically by construction: no `/RI` or `ri`
  is emitted, signatures are unrepresentable, and the whitelist rejects
  unlisted constructs. The entry stays `partial` with the human obligation to
  confirm them against the licensed standard text before Gate 7.

## Ownership, copying, retention, and complexity

**Allocations over `Standard`, per successful generation: exactly +2.**

| Stage | Allocations |
| --- | ---: |
| Identification segment in the reserved packet | 1 |
| Profile validation | 0 |
| Lowered-plan name-class vector | 1 |
| Everything else | 0 |

The output-intent device class is compared in place rather than through a
slice. A slice-based first draft cost one more allocation per generation.
That extra allocation was found and removed during rebaseline review.

- **Output:** +112 bytes, and +112 bytes hashed by the identity digest. The
  chunk count and cross-reference width are unchanged.
- **Retention:** the facade output plan retains the text facts (shared
  mapping lists plus one tag) only until preparation wraps the sealed plan.
  `Pdf.Prepared` retains nothing new.
- **Complexity:** O(names × classified-table) for classification, where the
  table has 82 fixed entries; O(values + dictionary entries + streams) for the
  whitelist; O(packet bytes) for the metadata comparison; O(mapped scalars)
  for profile validation.
- **Diagnostics:** bounded to one finding.

## Structurally unrepresentable failure classes

Authoring cannot express encryption, JavaScript, interactive forms, optional
content, attachments, multimedia, 3D, alternate presentations, transfer
functions or halftones, simple fonts, CMYK, spot colour, JPEG 2000, reference
XObjects, inline images, or non-link annotations.

The lowered-plan whitelist still rejects each of them if a future lowering
ever produces it. The white-box twins in `package/Pdf.roc` and
`package/KernelPdfA4.roc` prove this by injecting each construct into an
otherwise valid claimed plan.

The facade's text-support matrix rejects U+0000, U+FEFF, U+FFFE, and uncovered
private-use scalars before profile validation. Its links always print. The
facade-level set of constructs that only Archive rejects is therefore
honestly empty:

- `tests/archive/archive_facade_negative.roc` proves that selecting Archive
  never masks an earlier authoring-stage cause;
- the profile rules themselves are proven by the white-box twins.

## Evidence

**Package expects**

`KernelXmp`:

- the identified packet is pinned byte for byte;
- namespace order with timestamps;
- the identified budget.

`KernelPdfA4`:

- a claimed blank plan is eligible;
- false and missing identification are rejected;
- a filtered metadata stream is rejected;
- ten forbidden keys, each with its own requirement;
- the output-intent subtype, profile reference, and device class;
- invalid UTF-8 names;
- text facts.

`Pdf`:

- default equals explicit Archive and declares the claim;
- Standard never declares it;
- a blank Archive document validates.

Facade-plan twins over a realistic plan (text, alpha raster figure, URI and
internal links, outline, labels): the unmutated plan is accepted, and each
single-fact mutation is rejected with its own requirement:

- annotation flags;
- a forbidden action;
- the annotation type;
- image interpolation, depth, or OPI;
- a simple font;
- a non-FontFile2 program;
- a missing `CIDToGIDMap`;
- seven package-excluded keys;
- external stream data;
- ToUnicode U+FEFF;
- private-use ActualText.

**Harness cases** (`static-pdfa4-v1`, pinned `nightly-2026-09-26-d6267b4`,
`x64musl` dev backend, measured from a cold Roc cache):

| Case | Pages | Allocations | Work |
| --- | ---: | ---: | --- |
| blank archive document | 1 | 235 | 4,838 bytes |
| archived report with timestamps | 4 | 70,631 | 61,944 bytes |
| archived report scaling x400 | 29 | 667,863 | 404,888 bytes |
| raster, alpha, gray, and JPEG figures | 1 | 4,239 | 22,529 bytes |
| navigation x8 links | 1 | 7,850 | 26,902 bytes |
| navigation x64 links | 3 | 29,248 | 61,455 bytes |
| caller font | 1 | 1,581 | 14,386 bytes |
| owned chunked output | 4 | 141,219 | 110 chunks, identical to buffered |
| shared chunked output | 4 | 141,218 | 110 chunks, identical to buffered |
| Archive and Standard profile twins | 4 | 141,217 | 61,944 vs 61,832 bytes, growth 112 |
| facade atomic negatives | 1 | 2,450 | 5 rejections |
| Standard twin of the figures | 1 | 4,237 | 22,417 bytes |
| Standard twin of the navigation | 1 | 7,848 | 26,790 bytes |

The report, chunked, and twin cases share one snapshot. Byte identity across
them is itself evidence.

- **Linear scaling.** The x400 report grows linearly over x40: 10× the
  paragraphs cost 9.46× the allocations and 6.5× the bytes.
- **The +2 invariant.** The Archive and Standard twin pairs differ by exactly
  2 allocations.

## Independent evidence

**Structural checker.** `scripts/check_pdfa4_structure.py` is the per-case
`pdfa4` validator. It re-derives the static facts from bytes alone and shares
no code with the Roc validator:

- the skeleton and `/ID`, with no `/Info` or `/Encrypt`;
- the XMP parsed as XML: exactly part 4 and rev 2020, no conformance, and
  canonical namespace order;
- a single `GTS_PDFA1` intent whose profile bytes equal
  `vendor/icc/sRGB2014.icc`;
- printable links and action types;
- FontFile2 Type 0 fonts;
- filters, bit depths, and blend modes;
- no excluded keys.

Its self-test covers 8 Archive snapshots plus 9 length-preserving mutation
twins. After the default change it validates all 20 Archive snapshots.

**veraPDF 1.30.2** (`scripts/check_pdfa4.py`, explicit `--flavour 4`, JSON with
parser logs; warnings and task exceptions in package output are failures):

- `--cases`: all 20 Archive snapshots are compliant with zero failed rules and
  checks. These are the 8 archive-family snapshots and the 12 former Standard
  snapshots now produced through the default. The 9 regenerated gallery PDFs
  are also compliant.
- `--standard-cases`: the 137 remaining `Standard` (and kernel) snapshots fail
  only what they deliberately omit:
  - 6.7.2.1-1 (no metadata) on 126 and 6.7.3-1 (no identification) on 11;
  - 6.3.2-2 on the four kernel navigation snapshots that carry one deliberately
    screen-only `/F 0` link;
  - 6.1.2-2 and 6.1.3-1 on the harness's fixed placeholder PDF, which the test
    platform writes, not the package.

  Every Gate 4 construct the kernel emits — forms, transparency groups, soft
  masks, shadings and patterns, ICC colour and alpha images, embedded subsets,
  navigation and appearances — is therefore otherwise PDF/A-4 eligible. This
  is what "apply static-profile rules uniformly" requires, without new kernel
  builders.
- `--corpus`: all 487 files of the upstream veraPDF-corpus `PDF_A-4` tree
  (CC BY 4.0, commit `49de56c`) return the verdict their names encode: 129
  pass files compliant and 358 fail files non-compliant. Of the fail files,
  326 fail a rule within their named clause. The exception ledger
  (`conformance/verapdf-exceptions.json`) is empty.

  Upstream `tNN` numbers test files, not profile rule test numbers, so the
  verdict is the whole-file expectation. The 142 MB upstream archive exceeds a
  repository blob, so `scripts/build_verapdf_corpus_subset.py` repacks only
  the PDF/A-4 tree deterministically. It keeps a per-file SHA-256 manifest
  verifiable against the pinned upstream digest `5c1a138e…`.

**Renderers.** `scripts/check_archive_renderers.py` uses PDFium Chromium 7988,
PDFBox 3.0.8, and MuPDF 1.28.2:

- every single-page Archive document renders at A4 without diagnostics;
- the blank page stays white;
- the figures (opaque, alpha, gray, and JPEG) and navigation documents
  rasterize pixel-identically to their Standard twins in all three engines;
- MuPDF renders all 36 pages of the three multi-page Archive documents.

The regenerated gallery also rasterizes pixel-identically to its previous
files, so the committed previews are unchanged.

**qpdf 12.3.2.** `--check` reports no errors or warnings on every
`tests/archive` snapshot.

**Arlington 1.30.2** (pinned image `sha256:15433689…`) accepts the blank
Archive document with 9,022 passed rules.

When this slice closed, every font-bearing output, Archive and Standard
alike and predating this slice, failed two object-model rules: `CIDSystemInfo`
`/Registry` and `/Ordering` were written as UTF-16BE text strings (`<FEFF…>`),
but ISO 32000-2 Table 114 requires ASCII strings. veraPDF PDF/A-4 decodes them
and reports no finding, so it did not block the Gate 5 claim.

That `Pdf20` defect is now resolved in its own reviewed change
([cid-system-info-ascii.md](cid-system-info-ascii.md)): the entries are ASCII
byte strings, and the Arlington `--cases` lane in Linux CI requires every
package snapshot, Archive and Standard, and every gallery example to pass with
zero failed rules and checks.

## Reviewed rebaselines

**Toolchain.** The pinned toolchain is unchanged. Every measurement comes from
a cold Roc cache, which is the CI protocol.

**Harness finding: warm-cache drift.** A warm local `~/.cache/roc` can compile
identical source into different binaries with different allocation counts:

- the kernel outline x64 case produced 2,795 in CI order;
- 2,978 after a comment-only edit with a warm cache;
- 1,771 when built alone into an empty cache.

Bytes and work counters were identical throughout. Baseline comparisons must
therefore use a fresh `XDG_CACHE_HOME` and the full harness order. The
integration commit had zero deltas under that protocol, even though a warm
cache showed spurious navigation deltas.

**Harness addition.** `test.py --baseline-report PATH` writes each differing
case's expected and observed metrics as JSON for review. It never edits the
spec.

**Default change: 35 reviewed deltas.**

- 12 default-path snapshots grow by exactly 112 bytes (`pdf_facade` ×3,
  metadata facade ×2, navigation facade ×2, caller, multiface, generated
  label, image figure, and the structural blank). Their `output_bytes` or
  `byte_visits` counters grow by 112 per generation, and chunk offset weights
  shift by 3,920.
- Successful default generations cost +2 allocations (+4 where a case
  generates twice). Negatives that fail after the packet is built cost +1,
  because the identification segment exists and lowering does not run.
- The structural blank case stays at 0 allocations, because its constant
  document is evaluated at compile time.
- Removing the device-class slice lowers every `tests/archive` Archive
  generation by 1 (by 2 for the chunked cases, which generate twice).
- No other work counter changed. Each changed snapshot is byte-identical to an
  explicit-Archive generation and passes veraPDF.

**Transient compiler crash.** The pinned Roc compiler once segfaulted in
`roc check tests/authoring/authoring.roc` while a fresh cache was being
populated in parallel. It did not reproduce in four warm or cold reruns, and
the rerun passed.

## Readiness dimensions

| Dimension | Status |
| --- | --- |
| Backend | Closed: typed claim, validation stages, exact lowering, ownership and allocation evidence |
| Facade | Closed: `Archive` default and explicit opt-in; `Standard` opt-out; atomic diagnostics |
| Advanced integration | Not applicable: `Encode` has no profile input and remains `Standard`-only |
| Conformance | `StaticPdfA4` closed on the pinned veraPDF PDF/A-4 profile basis, with ISO-text confirmation pending |
| Reader and AT behavior | Not applicable to static PDF/A-4; the renderer matrix records interoperability |

## Exact remaining work

- Confirm `ROC-PDF-PDFA4-ISO-TEXT-CONFIRMATION` against the licensed ISO
  19005-4:2020 text before Gate 7's combined claim.
- `AccessibleArchive` and the combined `StaticPdfA4 + PdfUa2` validation remain
  Gate 7.
- A PDF/A claim through the advanced `Encode` boundary would need a typed
  claim input and the same two validation stages.
