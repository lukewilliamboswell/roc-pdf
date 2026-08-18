# Gate 4 canonical metadata, document language, and sRGB output intent

This slice makes every facade document carry its authored metadata as PDF
data: the validated document language in the catalog `/Lang` entry, a
canonically serialized XMP metadata stream, and a PDF output intent that
links the catalog to the packaged sRGB profile. The same capability is an
optional typed input on the canonical Gate 4 kernel path, where the intent's
profile shares the deduplicated canonical ICC stream with the painted
ICCBased color spaces. It absorbs the veraPDF 6.7.2.1-1 finding (the missing
XMP metadata stream) that every earlier Gate 4 slice recorded as deferred.

## Scope and non-goals

Implemented:

- `KernelMetadata`: one validation boundary for the authored metadata facts.
  The document language validates as a canonical-case well-formed RFC 5646
  subset; the metadata title validates as bounded, non-empty XML 1.0 text
  with its escape counts recorded as reusable facts; optional explicit
  timestamps validate as exactly the canonical UTC form
  `YYYY-MM-DDThh:mm:ssZ` with a checked proleptic-Gregorian date.
- `KernelXmp`: one deterministic canonical XMP serialization from those
  validated facts.
- Catalog `/Lang`, `/Metadata`, and `/OutputIntents` entries; the
  uncompressed `/Type /Metadata /Subtype /XML` stream; and one
  `/S /GTS_PDFA1` output intent whose `/DestOutputProfile` references the
  packaged sRGB profile stream.
- Public inputs: `Pdf.document`'s existing required `title` and `language`
  now reach the emitted file; `Pdf.with_created`/`Pdf.with_modified` (and the
  `Document` equivalents) supply optional explicit timestamps. `Pdf.Error`
  gains `InvalidMetadata(Metadata.Error)`.
- Integration through all three lowering paths: the authored facade pipeline,
  the facade's blank-document structural path, and the canonical Gate 4
  kernel path (`KernelGate4FormStructure.build_with_facts`).

Explicitly not in this slice:

- PDF/A identification metadata (`pdfaid:part`/`pdfaid:rev`): that schema is
  the PDF/A-4 conformance claim itself and belongs to Gate 5. veraPDF's
  6.7.3-1 is the deferred finding this leaves (see independent evidence).
- XMP identifiers (`xmpMM:DocumentID`/`InstanceID`): deterministic document
  identity remains the trailer `/ID` digest, which hashes the sealed plan —
  including the metadata stream bytes — and therefore cannot itself appear
  inside the packet without circularity. The packet deterministically omits
  identifier properties; a later slice may add a second, separately
  domain-separated pre-serialization identity if XMP identifiers are ever
  required.
- Caller-authored raw XMP/XML, additional XMP schemas or properties, output
  intents over any profile other than the packaged sRGB asset, `/Info`
  dictionaries (PDF 2.0 deprecates them), and language tags outside the
  validated subset.
- URI links, internal destinations, named destinations, outlines, page
  labels, and annotation appearances remain the following slices. No
  PDF/A-4 or PDF/UA-2 claim is made; the slice claims `Pdf20`/`Standard`
  output only.

## Typed facts and validation policies

All metadata facts originate in typed authoring data and cross the compiler
stages explicitly; no later stage re-parses, re-derives, or recovers a value
from serialized bytes.

**Language.** The pinned standard is BCP 47 / RFC 5646 (normative-baseline
`bcp47-rfc5646`). The accepted subset is the canonical-case form
`language["-" script]["-" region]`: a two- or three-letter lowercase primary
language, an optional four-letter titlecase script, and an optional
two-letter uppercase or three-digit region. Three rejection families keep
the boundary honest and the diagnostics stable:

- `MalformedLanguageTag` — shapes RFC 5646 itself cannot produce (`en_AU`,
  `en--AU`, digit-bearing primaries, a second region), with the byte offset;
- `UnsupportedLanguageForm` — well-formed RFC 5646 outside the subset
  (private use, singletons, variants, extended language subtags, 4–8 letter
  primaries), never silently accepted;
- `LanguageNotCanonicalCase` — supported tags in non-canonical case
  (`en-au`, `EN`, `zh-hans`), rejected rather than silently normalized.

Registry validity beyond RFC 5646 syntax is out of scope because the IANA
subtag registry is not a pinned data dependency. Length is bounded before
parsing (`max_language_bytes`, 64 on the facade; the subset's own maximum is
12 bytes).

**Title.** Non-empty, bounded (`max_title_bytes`, 2048 on the facade), and
every scalar must be an XML 1.0 character: C0 controls, DEL, U+FFFE, and
U+FFFF reject with `InvalidTitleScalar` at the exact byte offset (U+FFFD and
all other supplementary scalars pass through as canonical UTF-8). The same
single validation scan counts the `&`/`<`/`>` occurrences, so serialization
later knows its exact output size without rescanning.

**Timestamps.** `Metadata.TimestampInput` stays `Explicit(Str)` or
`Omitted`; the package never reads a clock. Explicit values accept exactly
the 20-byte canonical UTC form `YYYY-MM-DDThh:mm:ssZ` — no offsets, no
fractional seconds — with month/day ranges and the Gregorian leap rule
checked (`2024-02-29` accepted, `2023-02-29` rejected at offset 8). One
canonical input form means the emitted `xmp:CreateDate`/`xmp:ModifyDate`
need no normalization step.

Validation runs once, in `Pdf.build_standard_plan` before any layout work on
the facade (so a rejected document costs no shaping or pagination) and at
the head of the kernel evidence pipeline; the returned `Facts` record —
including the escape counts — is what every later stage consumes.

## Canonical XMP serialization

`KernelXmp.Packet.build` is the single serialization policy:

- UTF-8 packet with the standard `xpacket` frame, the UTF-8 byte order mark
  inside the `begin` attribute, id `W5M0MpCehiHzreSzNTczkc9d`, no padding,
  and `end="w"`; no trailing newline after the end instruction.
- Namespace declarations and properties follow the Gate 0
  `Metadata.canonical.property_order` policy (`NamespaceUriThenLocalName`):
  the XMP namespace URI (`http://ns.adobe.com/xap/1.0/`) orders before the
  Dublin Core URI (`http://purl.org/dc/elements/1.1/`), so explicit
  timestamps precede `dc:language` and `dc:title`, and `CreateDate` precedes
  `ModifyDate`.
- `dc:language` is an `rdf:Bag` holding the single validated document
  language — the same value the catalog `/Lang` entry carries, from the same
  validated fact, so disagreement is unrepresentable. `dc:title` is an
  `rdf:Alt` with one `x-default` item.
- Omitted timestamps omit their property elements entirely and, when both
  are omitted, the `xmlns:xmp` declaration; no empty elements exist.
- Element text escapes exactly `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`;
  validation already rejected everything XML 1.0 cannot carry, and no other
  substitution or whitespace policy applies. Indentation is one tab per
  element depth with single `\n` separators.
- No time, locale, environment, filesystem, or map-iteration input exists
  anywhere in the path; identical facts produce identical bytes, pinned by a
  byte-for-byte golden expect.

Because validation carried the escape counts forward, the exact packet size
is known before a byte is written: the packet is emitted once into an
exactly reserved buffer (`List.reserve` with the computed total, verified by
a length invariant), escapes append per byte without per-escape allocations,
and the `max_xmp_bytes` budget (16384 on the facade, far above the bounded
title's worst case) rejects before the allocation. The showcase packet is
695 bytes; omitting both timestamps yields 540.

## The output intent and the packaged profile

The packaged asset is unchanged from the color/image-leaf slice:
`vendor/icc/sRGB2014.icc`, the ICC's official v2 sRGB profile, 3,024 bytes,
SHA-256 `384b832d…5c6e0a`, license permitting copying, distribution, and
embedding without restriction, provenance and the ISO 15076-1 profile-ID
self-check recorded in `vendor/icc/NOTICE.md`, compiled into
`package/KernelSrgbProfile.roc` by `scripts/build_srgb_profile.py`, and
digest-and-length pinned both by the generated module's `expect` under
`roc test` and by the provenance manifest.

The emitted intent is one direct dictionary inside the catalog's
`/OutputIntents` array:

```text
/OutputIntents [<< /DestOutputProfile N 0 R
                   /OutputConditionIdentifier (sRGB2014)
                   /RegistryName (http://www.color.org)
                   /S /GTS_PDFA1 /Type /OutputIntent >>]
```

The condition identifier and registry are package constants tied to the
packaged profile's published identity (`KernelMetadata.
srgb_condition_identifier` / `icc_registry_name`); both strings serialize as
canonical BOM-prefixed UTF-16BE text strings. `/S /GTS_PDFA1` is the ISO
32000-2 output-intent subtype that PDF/A-4 will later claim against; using
it now is data, not a conformance declaration. The referenced
`/DestOutputProfile` stream is the ordinary profile stream shape every Gate 4
slice already emits — `<< /N 3 /Length L 0 R >>`, unfiltered, payload shared
as an unchanged resource — so the intent adds no second embedding path.

On the canonical kernel path the implemented capability is exactly the
packaged profile: `KernelMetadata.validate_intent` requires the registry and
identifier constants, an in-range three-component profile, and exact byte
equality with the packaged bytes (one early-exit comparison, reported as
`intent_bytes_compared`; there is no digest, so no repeated profile
hashing). The facade constructs its intent from the packaged constants
directly, so a mismatched profile is unrepresentable there and the
comparison does not run.

## Pipeline integration

Structure planning accepts optional document facts
(`KernelMetadata.PlanFacts`); `NoDocumentFacts` keeps every existing plan —
name table, identity digest, and emitted bytes — exactly as before, which is
why no kernel fixture outside this slice rebaselined.

With facts present:

- `KernelGate2TaggedObjects` adds the fact-only names conditionally and
  writes the catalog as `/Lang`, `/MarkInfo`, `/Metadata`, `/OutputIntents`,
  `/Pages`, `/StructTreeRoot`, `/Type` — the sorted key order the object
  store already enforces byte-lexicographically.
- The metadata stream and its indirect length append immediately after the
  font objects (`KernelMetadata.plan_objects` assigns `base+1`, `base+2`,
  and the shifted xref `base+3`); the catalog forward-references it, which
  sealing validates like every other reference. The stream is `Generated`
  and `Unfiltered`: the packet stays byte-addressable, which the later
  PDF/A-4 profile also requires of metadata streams.
- On the facade path (`KernelFacadePipeline` → `KernelFacadeOutput` →
  `KernelGate3TaggedTextStructure.build_with_facts`), the scene stage's
  validated color store gains the packaged profile — validated through the
  ICC inspection boundary, tags included — without adding a painting space,
  so the existing profile-object machinery plans and emits exactly one ICC
  stream that the intent references. Text keeps painting in calibrated
  gray; no content-stream byte changes because of the intent.
- Empty facade documents route through
  `KernelStructure.build_blank_with_facts`, which appends the metadata and
  profile streams after the page objects and derives the plan identity from
  the sealed-store digest (`KernelGate2Identity`), so distinct facts produce
  distinct file identifiers where the fact-free blank kernel path keeps its
  constant `Blank` identity.
- On the canonical Gate 4 path
  (`KernelGate4FormStructure.build_with_facts`), the intent's authored
  `Color.ProfileId` resolves through the canonical-ordinal map that
  resource-identity deduplication already produces (`profile_names`), so the
  intent references the same canonical profile object every ICCBased color
  space shares. The xref object shifts by the two appended metadata objects
  (`finished.xref`), which the evidence pins as `objects + 1`.

Conformance decisions stay out of the serializer: every fact is validated
before sealing, `KernelSeal` revalidates the lowered plan (dense object
numbers, key order, reference closure, stream adjacency), and `KernelEmit`
emits an already validated plan unchanged.

## Identity and deduplication

- The trailer `/ID` remains the versioned, domain-separated digest over the
  plan facts. For authored documents the stage-1 digest hashes the sealed
  store, which now includes the metadata payload, the language and intent
  text strings, and the fact names — so any metadata change changes the
  file identifier deterministically. The blank facade path switches from
  the constant `Blank` identity to the same sealed-store digest for exactly
  that reason.
- The packaged profile participates in canonical resource identity
  unchanged: authored copies of the profile deduplicate to one canonical
  leaf (digest plus exact byte equality, with the declared work bounds), and
  the output intent is one more consumer of that leaf, not a second
  embedding. `share x64` proves 64 authored profile/space copies plus the
  intent collapse to one ICC stream and one ICCBased array.
- On the canonical path the intent's profile must be color-reachable (used
  by at least one color space); an intent-only profile would be rejected by
  the existing unreachable-resource rule. The facade path embeds the
  profile for the intent without graph participation, which is the intended
  ordinary-facade shape.

## Ownership, copying, retention, and complexity

- Metadata validation is one linear scan per fact: `O(language bytes +
  title bytes + 20 per timestamp)`, reported as `language_bytes`,
  `title_bytes`, `timestamp_bytes`. No allocation beyond the returned facts.
- XMP serialization is `O(packet bytes)` with exactly one output
  allocation, size known in advance from the validation facts; the packet
  is serialized once per document and the same `List(U8)` value flows to
  the payload store and emission (shared, not copied — Roc lists are
  reference-counted values).
- The intent byte comparison is `O(min(profile bytes, first divergence))`,
  once per kernel-path document; the facade skips it structurally.
- The metadata stream payload is `Generated`/`Unfiltered`: emission writes
  it once; under `to_bytes` it is copied into the single final buffer like
  every payload, under shared-chunk delivery it emits without an extra
  copy. The ICC payload keeps the existing unchanged-resource retention
  behavior (shared slice under `ShareUnchangedResources`, bounded owned
  copy under `OwnChunks`), byte-identical either way.
- No sorting was added anywhere; property order is a fixed policy, catalog
  key order is the existing enforced dictionary order, and object order is
  arithmetic.
- Scaling evidence separates the axes: `title x64/x256` moves only the
  title/packet/output counters (exactly 6 bytes per escaped `A&` segment:
  2 raw + 4 escape); `share x16/x64` moves only the authored-profile
  counters and the graph's linear hashing work while the canonical
  profile count, packet, and metadata counters stay fixed; `unique`
  versus `retained` shows the one-shot path at 1198 allocations and the
  deliberately retained input at 2394 (two full plans over one retained
  authored store, byte-identical output).

## Structurally unrepresentable failure classes

- A facade document whose catalog `/Lang` disagrees with its XMP
  `dc:language`: both serialize from the single validated language fact.
- A facade output intent over the wrong profile, registry, or identifier:
  the facade constructs the intent from the packaged constants and the
  packaged bytes; there is no caller input to mismatch.
- A metadata stream whose bytes differ from the canonical packet of the
  validated facts: the packet is serialized once and carried by value;
  nothing re-serializes or edits it.
- Two embedded copies of the packaged profile because both a color space
  and the intent need it: the intent references the planned profile object;
  it cannot introduce a stream.
- Arbitrary caller XMP, a second metadata stream, a filtered metadata
  stream, or catalog entries in non-canonical order: no such construction
  path exists, and the object store rejects unsorted dictionary keys.
- A skipped validation: `build_with_facts` consumes the typed facts record;
  a caller cannot hand unvalidated strings to the object planner because
  the planner takes the same validated values the XMP packet was built
  from, and the facade has exactly one entry point through
  `KernelMetadata.validate`.

Runtime negatives cover everything representable: the three language
families plus empty/oversized, empty/oversized/invalid-scalar titles, both
timestamp fields, the packet budget, the four intent configuration errors
(registry, identifier, out-of-range, component mismatch), altered and
truncated packaged bytes, and the facade path's typed `InvalidMetadata`
rejections on both the buffered and chunked entry points — each atomic,
each with the exact typed error, none emitting a byte.

## Evidence

`roc test` pins, in `KernelMetadata`/`KernelXmp`/`Metadata`/`Document`
expects: the full accepted language subset and all three rejection families
with exact offsets; timestamp acceptance including the leap day and the
exact field/offset rejections; title escape counts, U+FFFF rejection, and
U+FFFD acceptance; the byte-for-byte golden packet; property order with
timestamps; omission rules; packet determinism; the packet budget; the
packaged-profile intent validation with exact `bytes_compared` facts; and
the blank-facts structural plan (9 objects, distinct identities per
language). `Gate4MetadataEvidence` expects run the whole canonical pipeline
under `roc test package/evidence.roc`, including the adversarial showcase,
sharing checks, the xref invariant, and the 18-step negative sweep.

Harness cases (`tests/spec.json`, revision
`gate4-metadata-output-intent-v1`, exact x64musl allocations under the
pinned dev backend; arm64mac carries the same accepted values):

| Case | Dimensions | Allocations | Key counters |
| --- | --- | --- | --- |
| showcase (adversarial order) | 1 page, 2 authored profiles | 2,395 | canonical 1, packet 695, intent compare 3024, output 6,129 |
| omitted-timestamp packet | timestamps omitted | 1,182 | packet 540, 2 properties |
| unique-input ownership | one-shot | 1,198 | same facts as showcase |
| retained-input ownership | input planned twice | 2,394 | byte-identical output |
| shared intent profile x16 / x64 | 16/64 authored copies | 3,020 / 9,528 | canonical 1, graph bytes hashed 48,912 / 195,648 (linear) |
| title scaling x64 / x256 | escape-heavy titles | 1,199 / 1,201 | packet 1,033 / 2,185 (exactly 6 bytes per segment) |
| atomic negatives | 18 rejections | 1,212 | no escaped plan, carrier bytes only |
| facade output | 3 pages, 41 blocks | 40,292 | output 46,423 |
| facade determinism | built twice | 80,583 | byte_identical 1 |
| facade atomic negatives | 9 rejections | 1,306 | carrier 13,350 |

The showcase byte-compares a fully adversarial authoring (profile references
and the intent target swapped across the two authored packaged-profile
copies) against the forward document inside the scenario; the harness
additionally regenerates every snapshot byte-for-byte on every run.

## Independent evidence

`scripts/check_gate4_metadata.py` parses the emitted bytes directly and, for
all eleven snapshots: rebuilds the canonical XMP packet from the fixture's
typed facts in independent Python and byte-compares the metadata stream;
verifies `/Lang` as the exact BOM-prefixed UTF-16BE string and its agreement
with the packet's `dc:language`; verifies the catalog's sorted key order,
the `/Type /Metadata /Subtype /XML` unfiltered stream facts, the exact
GTS_PDFA1 intent dictionary with its identifier and registry strings, the
`/N 3` unfiltered profile stream byte-identical to the vendored asset,
exactly one embedded profile copy with every `/ICCBased` array referencing
that same object, xref/page-tree/stream-length integrity, and the absence of
`/DestOutputProfileRef`. Seven length-preserving mutation twins (packet
byte, `/Lang` value, intent subtype, `/N`, metadata subtype, a filter key,
an ICC payload byte) must each be rejected; the self-test joins
`./scripts/test.py`, and the per-case checks run on every matching case.

`scripts/check_gate4_metadata_renderers.py` runs the pinned
PDFium 7988 / PDFBox 3.0.8 / MuPDF 1.28.2 matrix: the showcase's two
sRGB-space fills render at the exact pinned codes ((255, 64, 32) and
(32, 64, 255) in PDFBox; one code lower on non-saturated channels through
PDFium's and MuPDF's ICC pipelines, the same ±1 the color/image slice
pinned), the calibrated background at its pinned display codes (224 direct;
240 through MuPDF's recorded tone behavior), the 64-fill share grid paints
identically through the one canonical profile, and MuPDF renders all three
facade pages and extracts the page-one logical text unchanged. This lane is
recorded as rendering/color-management interoperability only: rendering does
not validate metadata or output-intent correctness.

`qpdf --check` (12.3.2) passes every one of the eleven new snapshots with no
errors or warnings. veraPDF 1.30.2 (`--flavour 4`, diagnostic only) now
reports exactly one rule on the metadata-bearing fixtures — **6.7.3-1, the
missing PDF/A Identification extension schema** (`pdfaid:part`/`pdfaid:rev`)
— and no longer reports 6.7.2.1-1: the XMP metadata stream finding every
earlier Gate 4 slice deferred is resolved by this slice. The identification
schema is deliberately not emitted here because it *is* the PDF/A-4
conformance claim, which belongs to Gate 5's validated whitelist; emitting
it from a `Standard` document would be a false declaration. This
distinction — PDF 2.0 structural validity (qpdf, the structural checker)
versus rendering interoperability (the renderer matrix) versus deferred
PDF/A-4 requirements (6.7.3-1) — is exactly the boundary the slice claims.

## Reviewed rebaselines

Every kernel fixture outside this slice is byte-identical: absent facts add
no names, values, objects, or identity input. The rebaselines are confined
to fixtures that generate through the public facade, and all of them have
one architectural cause — every facade document now carries `/Lang`, the
canonical XMP stream, the packaged profile stream, and the output intent:

- Bytes: each facade snapshot grows by its packet plus the 3,024-byte
  profile plus the intent/catalog syntax (for example `gate3_pdf_facade`
  12,397 → 16,472; the blank documents 667 → 4,717; the multiface facade
  11,416 → 15,480). Chunked delivery gains the corresponding chunks
  (32 → 40) and offset weight.
- Allocations: +149–151 per facade generation (metadata validation, one
  packet allocation and its segment temporaries, profile-store validation,
  and the four extra planned objects); the two-generation retention cases
  move by twice that (+~300). Facade negative fixtures that reject during
  font selection or authoring now additionally run metadata validation
  first (+15; the metadata-invalid facade rejections themselves cost 1,306
  allocations in the new negative fixture).
- `gate1_blank` (a facade fixture despite its name) now carries the facts
  and a sealed-plan identity; its case gains the
  `normalized_plan_identity` dimension, and `check_pdf_structure`'s
  self-test validates it under that identity mode — the blank-identity
  derivation stays covered by the kernel-path `gate1_pages` stress case.
  The Gate 1 kernel evidence itself (Gate1Evidence fixtures and
  `KernelStructure` expects) is untouched.

During integration the canonical-path xref object was initially planned
without the two appended metadata objects; the structural checker's xref
validation caught the collision immediately, the fix (`finished.xref`) is
pinned by an evidence invariant (`xref == objects + 1`), and every canonical
snapshot regenerated 22 bytes larger (two 11-byte xref entries).

## Exact remaining Gate 4 work

- URI links, typed internal destinations with paired `/SD` + `/D`, named
  destinations, outlines, and page labels.
- Annotation appearances through this same scene/resource pipeline.

This slice deliberately claims `Pdf20`/`Standard` output only. The PDF/A
Identification schema (veraPDF 6.7.3-1) and the `Archive` profile's
whitelist enforcement remain Gate 5; PDF/UA-2 metadata requirements
(`dc:title` agreement with `DisplayDocTitle`, `/MarkInfo`, `/Tabs`) remain
Gate 6 — the canonical `dc:title` this slice emits is the prerequisite they
build on.
