# Gate 3 closure-readiness audit

Date: 2026-08-09

Audited branch state: `codex/gate-3` at `0c288ee`.

This is a read-only closure audit, not a closure record. It assesses the Gate
3 capability and evidence criteria in
[`feature-roadmap.md`](../../feature-roadmap.md#gate-3-searchable-international-text-and-useful-layout),
the enduring staged-text contract in
[`architecture.md`](../../architecture.md#text-and-font-boundary), and every
current `docs/performance/gate-3-*.md` record. “Satisfied” means satisfied for
the stated local/dev evidence only; it does not make a Gate 5--7 conformance or
cross-platform claim.

## Criterion audit

| Roadmap criterion | Status | Current evidence | Remaining boundary |
| --- | --- | --- | --- |
| Bounds-checked TrueType parsing; exact identity, metrics, widths, rights, and instances | Satisfied | `KernelFont` is the single inspected source used by `Pdf` (`package/Pdf.roc:171-186`); inspection/subsetting evidence and independent fontTools check are recorded in `gate-3-font-subsetting.md:29-46`. | None for the declared static TrueType subset. Other program formats remain correctly rejected. |
| Deterministic plan, Type 0/CID output, whole-font-to-subset flow, composite closure, CIDs, and complete direct Unicode maps | Satisfied | The facade output composes plan, subset, Type 0 objects, text maps, and sealed structure (`docs/performance/gate-3-facade-output-checkpoint.md:20-36`). Direct font, CID, and `ToUnicode` inspection is required by the registered scenarios (`feature-roadmap.md:440-461`). | This does not establish unsupported font formats or later profile requirements. |
| Advanced glyph-run facts and context-dependent extraction | Satisfied for the advanced boundary | Combining, reordered/`ActualText`, supplementary-plane, and CJK fixtures all retain source/cluster facts and direct maps; see `gate-3-combining-text.md:3-19`, `gate-3-actual-text.md:1-47`, `gate-3-supplementary-text.md:1-45`, and `gate-3-cjk-text.md:1-45`. | It is not proof of automatic shaping for every script. That limitation is permitted only where the advanced boundary remains explicit. |
| Combining-mark output | Satisfied | Decomposed `A + U+0300` maps to one positioned glyph with direct two-scalar `ToUnicode`, with an atomic malformed range negative (`gate-3-combining-text.md:3-30`). | None for this matrix row. |
| Supplementary-plane output | Satisfied | U+1F12F fixture has surrogate-pair CMap, extraction, rendering, and registered dev evidence (`gate-3-supplementary-text.md:3-55`; `tests/spec.json:851-880`). | None for this matrix row. |
| CJK subset output | Satisfied | U+4E2D advanced run has proven CJK fixture provenance, Type 0 subset, extraction, renderer, and atomic range negative (`gate-3-cjk-text.md:3-52`; `tests/spec.json:881-910`). | None for this matrix row; it deliberately is not facade CJK or vertical-writing support. |
| Reordered-glyph extraction | Satisfied | The `fa` logical / `af` visual fixture proves the direct CMap and required `ActualText` separately (`gate-3-actual-text.md:1-54`). | It is explicitly not real bidi output. |
| Ligature rendering and extraction | Partial | `KernelGsub.validate_ligature` validates a narrow GSUB Type-4 fact and shaping consumes it (`gate-3-gsub-ligature-inspection.md:3-41`). | No end-to-end `fi`/`liga` fixture, snapshot, renderer/extractor evidence, or dev baseline exists. This is a **local** fixture/provenance and output-slice dependency: the present face lacks the needed mapping (`gate-3-gsub-ligature-inspection.md:403-426`). |
| Real UAX #9 RTL logical/visual output, including mixed span and mirroring | Blocked | The private one-level bidi boundary is intentionally non-integrated; mixed text, neutrals, numbers, isolates, brackets, and mirrors reject (`gate-3-bidi-boundary.md:3-32`, `gate-3-rtl-blocker.md:80-113`). | **Upstream dependency:** `roc-lang/unicode#39` must provide bounded UAX #9 levels, mappings, directional runs, bracket/mirror facts. Then a local typed shaping/lowering handoff and an end-to-end fixture remain (`gate-3-rtl-blocker.md:115-148`). |
| Case-transformation extraction | Blocked | The local semantic and PDF consumers preserve a transformation fact and use source-derived `ActualText` (`gate-3-case-transformation-blocker.md:177-205`). | **Upstream dependency:** `roc-lang/unicode#52` full case mappings with source/output ranges and policy. Its adoption still needs local range validation and positive/negative output fixtures (`gate-3-case-transformation-blocker.md:207-241`). |
| Soft and discretionary hyphen extraction | Partial | The selected explicit U+00AD case has positive structural/extraction/rendering evidence and three atomic negatives (`gate-3-soft-hyphen.md:3-35`, `tests/spec.json:791-850`). | A selected external zero-width discretionary opportunity is intentionally rejected. A local generated-glyph/presentation boundary is required before positive discretionary-hyphen output. Automatic hyphenation is not claimed and therefore needs no language-pattern corpus unless accepted (`gate-3-soft-hyphen.md:18-30`). |
| Generated labels | Satisfied | `Pdf.bullets` retains generated presentation evidence through the full pipeline; output, extraction, renderer, and atomic missing-property negative are registered (`gate-3-generated-labels.md:1-55`; `tests/spec.json:731-760`). | None for the declared bullet-label row. |
| Pinned UAX #14/UAX #29 fixtures, including version-sensitive boundaries | Satisfied for the project seam | The package pin records UAX 14 rev. 55 and UAX 29 rev. 47 in `conformance/normative-baseline.json:107-131`; registered vectors assert exact UTF-8/scalar ranges, line decisions, structural carriers, and atomic limits (`gate-3-uax-boundary-vectors.md`). | This deliberately does not duplicate the upstream full conformance corpus; `roc-lang/unicode` remains responsible for that corpus and its Unicode-version upgrades. |
| One-import authoring path and `Standard` default | Partial | Nonblank `Pdf.to_bytes` and `to_bytes_with` use the staged pipeline for Standard (`package/Pdf.roc:126-136`); public output, facade authoring, and list-label cases are registered. `Archive` and `AccessibleArchive` correctly remain unavailable at this gate. | `Pdf.to_chunks_with` still rejects every nonblank document and emits only a blank Gate 1 plan (`package/Pdf.roc:138-150`). The roadmap names `to_bytes`, so this does not by itself falsify the narrow Gate 3 capability; it does leave the architecture's byte-identical buffered/chunked public contract incomplete for useful authored documents. |
| Caller-provided font resource path | Partial | The registry, opaque `FaceId`, `Theme.with_font`, facade selection, one retained source, three placements, structural checks, and restricted-rights negative are all present (`package/Pdf.roc:42-92`, `gate-3-caller-font-facade.md:19-53`). | The public facade resolves exactly one selected face. It does not yet implement the required finite ordered multi-face policy and per-cluster coverage selection (`gate-3-caller-font-facade.md:55-61`). This is a **local** implementation gap. |
| Bounded parsing/coverage/shaping/measurement/hyphenation caches and compact continuations | Partial | The source cache, shaped-line cache, pagination/materialization, fragments, and scenes each have focused flat-store/linear-work evidence. | No closure-level evidence shows all declared cache kinds, especially font parse/coverage and hyphenation, with exact keys, bounded retention, hit/miss, and unique/shared cases. Hyphenation itself is not accepted; its cache can remain absent, but the closure record must explicitly classify it inapplicable rather than silently omit it. |
| Public and caller-font performance/retention evidence | Partial | The caller facade records zero copied input bytes, one retained payload, one inspection, and three placements (`gate-3-caller-font-facade.md:30-43`). Facade list and compact-builder scale fixtures are registered. | The roadmap also requires unique **and deliberately shared** caller input evidence and source retention through final subset emission (`feature-roadmap.md:474-478`). The registered caller facade fixture proves multiple placements, not a separately measured deliberately shared registry/input case. |
| Adversarial paragraph, line-break, font-selection, shaping, and pagination operation bounds; scenes materialized once | Partial | Scaled authoring, line-layout, pagination, materialization, fragments, and scene fixtures are registered; the facade checkpoint records one accepted staged output path (`docs/performance/gate-3-facade-output-checkpoint.md:48-57`). | Font-selection adversarial evidence cannot close before multi-face cluster selection exists. The missing bidi, ligature, discretionary, and case paths also have no relevant adversarial bound evidence. |
| All Gate 3 performance records use the pinned dev backend | Satisfied documentation/evidence hygiene | Exact current allocations are the dev-backend expectations in `tests/spec.json`; `dev-backend-allocation-rebaseline-2026-08-09.md` records the reviewed atomic mode transition. Historical speed-backend tables remain only as explicitly superseded representation-review evidence. | This removes a documentation blocker only. It does not satisfy any still-partial performance, cache, retention, or capability criterion. |

## Closure decision

**Gate 3 is not closed.** The decisive unmet roadmap rows are end-to-end
ligature output, real RTL logical/visual output, case-transformation output,
and positive discretionary-hyphen output. The caller-font policy and
Unicode-vector/performance/retention evidence are also incomplete. The current
checkpoint reaches the same conclusion and must remain a checkpoint rather
than be relabelled as closure (`gate-3-facade-output-checkpoint.md:9-11`,
`84-93`).

## Dependency split and next valid order

1. Resolve or track the upstream Unicode boundaries for bidi (`#39`) and full
   case mapping (`#52`); neither permits local approximation or manual text
   reversal/mapping.
2. Independently complete local finite ordered multi-face planning and
   cluster-based coverage selection, then add its adversarial and
   unique/shared-retention evidence.
3. Add the local `fi` GSUB fixture/output slice and the generated discretionary
   hyphen presentation slice. Both need the normal original-byte structural,
   extractor, renderer, positive, atomic-negative, deterministic-work, and
   reviewed dev-allocation evidence.
4. Add the project-owned UAX #14/#29 boundary-vector cases. The historical
   allocation records have been deliberately superseded by the reviewed
   dev-backend baseline, so no speed-mode rebaseline is required.
5. Only after the preceding rows are satisfied should a new audit decide
   whether a Gate 3 closure record is justified. This audit intentionally does
   not create one.
