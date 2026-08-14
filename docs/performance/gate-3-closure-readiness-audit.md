# Gate 3 closure-readiness audit

Date: 2026-08-14

Audited branch state: `gate-3-closure`, after the ordered multi-face facade,
authored chunked delivery, combining-mark registration, resolved
right-to-left output, and case-transformation slices.

This is a read-only closure audit. It assesses the Gate 3 capability and
evidence criteria in
[`feature-roadmap.md`](../../feature-roadmap.md#gate-3-searchable-international-text-and-useful-layout),
the enduring staged-text contract in
[`architecture.md`](../../architecture.md#text-and-font-boundary), and every
current `docs/performance/gate-3-*.md` record. “Satisfied” means satisfied for
the stated local/dev evidence only; it does not make a Gate 5--7 conformance or
cross-platform claim. The closure decision it reaches is recorded separately in
[`gate-3-closure.md`](gate-3-closure.md).

## Criterion audit

| Roadmap criterion | Status | Current evidence | Remaining boundary |
| --- | --- | --- | --- |
| Bounds-checked TrueType parsing; exact identity, metrics, widths, rights, and instances | Satisfied | `KernelFont` is the single inspected source used by `Pdf` (`package/Pdf.roc:197-246`); inspection/subsetting evidence and an independent fontTools check are recorded in `gate-3-font-subsetting.md`. | None for the declared static TrueType subset. Other program formats remain correctly rejected. |
| Deterministic plan, Type 0/CID output, whole-font-to-subset flow, composite closure, CIDs, and complete direct Unicode maps | Satisfied | The facade output composes plan, subset, Type 0 objects, text maps, and sealed structure (`gate-3-facade-output-checkpoint.md`); the multi-face path builds one plan, subset, and `F1_k` resource per used font (`gate-3-multiface-public-facade.md`). | This does not establish unsupported font formats or later profile requirements. |
| Advanced glyph-run facts and context-dependent extraction | Satisfied for the advanced boundary | Combining, reordered/`ActualText`, supplementary-plane, CJK, ligature, hyphen, right-to-left, and case fixtures all retain source/cluster facts and direct maps (`gate-3-combining-text.md`, `gate-3-actual-text.md`, `gate-3-supplementary-text.md`, `gate-3-cjk-text.md`, `gate-3-fi-ligature.md`, `gate-3-rtl-text.md`, `gate-3-case-transformation.md`). | It is not proof of automatic shaping for every script; that limitation stays explicit at the advanced boundary. |
| Combining-mark output | Satisfied | Decomposed `A + U+0300` maps to one positioned glyph with a direct two-scalar `ToUnicode`, now registered with byte-exact snapshot, dev allocations, and a checker self-test (`gate-3-combining-text.md`). | None for this matrix row. |
| Supplementary-plane output | Satisfied | U+1F12F fixture has surrogate-pair CMap, extraction, rendering, and registered dev evidence (`gate-3-supplementary-text.md`). | None for this matrix row. |
| CJK subset output | Satisfied | U+4E2D advanced run has proven fixture provenance, Type 0 subset, extraction, renderer, and atomic range negative (`gate-3-cjk-text.md`). | None for this matrix row; deliberately not facade CJK or vertical writing. |
| Reordered-glyph extraction | Satisfied | The `fa` logical / `af` visual fixture proves the direct CMap and required `ActualText` separately (`gate-3-actual-text.md`). | It is context-dependent extraction evidence; real bidi is the separate row below. |
| Ligature rendering and extraction | Satisfied | The `fi` fixture consumes a parsed GSUB Type-4 fact through shaping into one painted CID with `ActualText`, extraction, renderer, subset digest, and an atomic negative (`gate-3-fi-ligature.md`). | Narrow to the retained `liga` relation; broader OpenType shaping is not claimed. |
| Real UAX #9 RTL logical/visual output, including mixed span and mirroring | Satisfied | `KernelBidiBoundary` wraps the pinned `unicode.Bidi`; seven normative Unicode 17.0.0 conformance vectors, the typed handoff `validate_advanced_with_bidi_order`, a provenanced Hebrew fixture face, and the bracket-pair output fixture with mirrored CIDs, logical `ActualText`, extraction, renderers, and two atomic negatives are recorded in `gate-3-rtl-text.md`. | The public facade stays left-to-right by design; Arabic joining and vertical writing remain out of scope. |
| Case-transformation extraction | Satisfied | `KernelCaseTransform` wraps the pinned `unicode.Case` with local coverage/order/shape validation; the `aß` expansion fixture proves presentation glyphs, logical `ActualText`, per-CID maps, extraction, renderers, and two atomic negatives (`gate-3-case-transformation.md`). | Unicode default uppercase only; contextual sigma, Turkic/Lithuanian, and titlecase remain future rows and cannot be silently requested. |
| Soft and discretionary hyphen extraction | Satisfied | The explicit U+00AD case and the selected external zero-width discretionary opportunity both have positive structural/extraction/rendering evidence with atomic negatives (`gate-3-soft-hyphen.md`). | Automatic hyphenation is not claimed and therefore needs no language-pattern corpus. |
| Generated labels | Satisfied | `Pdf.bullets` retains generated presentation evidence through the full pipeline; output, extraction, renderer, and atomic missing-property negative are registered (`gate-3-generated-labels.md`). | None for the declared bullet-label row. |
| Pinned UAX #14/UAX #29 fixtures, including version-sensitive boundaries | Satisfied for the project seam | The pin records UAX 14 rev. 55, UAX 29 rev. 47, and UAX 9 rev. 51 in `conformance/normative-baseline.json`; registered vectors assert exact UTF-8/scalar ranges, line decisions, and atomic limits (`gate-3-uax-boundary-vectors.md`, `gate-3-rtl-text.md`). | This deliberately does not duplicate the upstream conformance corpus; `roc-lang/unicode` owns that corpus and its Unicode-version upgrades. |
| One-import authoring path and `Standard` default | Satisfied | Nonblank `Pdf.to_bytes`/`to_bytes_with` use the staged pipeline, and `Pdf.to_chunks_with` now drives the same sealed plan so authored buffered and chunked forms are byte-identical by construction with an atomic pre-encoder rejection (`gate-3-chunked-facade-output.md`). `Archive` and `AccessibleArchive` correctly remain unavailable at this gate. | None for the declared authoring path. |
| Caller-provided font resource path | Satisfied | The registry, opaque `FaceId`, `Theme.with_font`, single-face selection, and restricted-rights negative are joined by the finite ordered policy path: `Theme.with_font_policy`, per-cluster coverage selection, and four stable typed negatives (`gate-3-caller-font-facade.md`, `gate-3-multiface-public-facade.md`). | The convenience path's declared script set is `{Latn, Hani}`; anything else is a typed rejection rather than an implicit fallback. |
| Bounded parsing/coverage/shaping/measurement/hyphenation caches and compact continuations | Satisfied | `gate-3-cache-closure.md` records each declared kind with its exact key, bounded retention, and hit/miss evidence — font parse (`ParseKey`, register-once), coverage (`CoverageKey`, read-only visits), selection plan (once per unique interned source), shaping (per-source templates), measurement (`BatchKey` with `cache_hits = N-1`), and the source intern table — and classifies hyphenation **inapplicable** because automatic hyphenation is not accepted at this gate. | No cross-document or cross-process cache is claimed. |
| Public and caller-font performance/retention evidence | Satisfied | Shared-registry and deliberately unique-registry controls now cover one face (`gate-3-caller-font-retention.md`) and two faces (`gate-3-multiface-public-facade.md`): one retained payload per face across two complete public outputs, zero registry-copied bytes, and exactly doubled dimensions in the unique control. | None for the declared faces. |
| Adversarial paragraph, line-break, font-selection, shaping, and pagination operation bounds; scenes materialized once | Satisfied | Scaled authoring, line-layout, pagination, materialization, fragments, and scene fixtures remain registered, and ordered font selection now has its own x1000/x10000 bounds at both the registry level (worst-case alternating probe: `face_visits = 1.5N` under the `N x policy_len` bound, exact x10 linearity) and the facade level (plan/shape once per unique source, `cache_hits = N-1`, exactly two subsets) (`gate-3-multiface-public-facade.md`). | Bounds are declared for the accepted paths; unsupported scripts and shaping remain typed rejections rather than measured paths. |
| All Gate 3 performance records use the pinned dev backend | Satisfied documentation/evidence hygiene | Exact current allocations are the dev-backend expectations in `tests/spec.json`; `dev-backend-allocation-rebaseline-2026-08-09.md` records the reviewed atomic mode transition. Historical speed-backend tables remain only as explicitly superseded representation-review evidence. | This removes a documentation blocker only. |

## Closure decision

Every roadmap row above is satisfied for its declared local/dev evidence. The
four decisive rows the 2026-08-09 audit named — end-to-end ligature output,
real right-to-left output, case-transformation output, and positive
discretionary-hyphen output — now each have registered output fixtures,
atomic negatives, independent extraction, and reviewed dev allocations, and
the caller-font policy and cache rows are complete. **Gate 3 is closed**; the
closure record is [`gate-3-closure.md`](gate-3-closure.md).

The `gate-3-facade-output-checkpoint.md` record remains a checkpoint of the
state it described and is not relabelled.

## Dependency record

The two upstream boundaries this audit previously tracked are resolved.
`roc-lang/unicode` 4.0.0 shipped UAX #9 bidirectional analysis
(`roc-lang/unicode#39`) and full case mapping with source-range facts
(`roc-lang/unicode#52`); its adoption, asset identity, and zero-delta
verification are recorded in `gate-3-unicode-4.0.0-adoption.md`, and the
corresponding blocker audits carry dated closing pointers.
