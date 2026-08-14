# Gate 3 public ordered multi-face facade output

This closes the public finite ordered multi-face policy and per-cluster
coverage selection row of the caller-resource boundary. `Theme.FontSelection`
now records either the existing exact `StyleFaces` selection or a
`Policy(Font.PolicyId)` constructed by `Font.Registry.with_policy`;
`Theme.with_font_policy` is the only way to request policy selection, and a
policy without the caller registry that constructed it (the packaged
built-in source) is a stable `InvalidFontSelection` error, never a
single-face fallback.

## Pipeline boundary

The single-face facade path is untouched: `Pdf.build_standard_plan` resolves
a `[Single(inspection), Ordered({ policy, registry })]` selection union whose
`Single` arm delegates to the exact previous code, and the full registered
suite passes byte-identically with unchanged dev allocation baselines. The
`Ordered` arm composes parallel entry points over the same downstream
stages:

- `KernelFacadeShape.Plan.build_ordered` itemizes each unique interned
  source's grapheme clusters with their pinned script runs, enforces the
  convenience path's declared script set `{Latn, Hani}` (anything else,
  including an unresolved Common run, is a typed `UndeclaredScript`
  rejection), calls `Font.Registry.plan` exactly once per unique source, and
  refines the returned `FaceRange`s at script-run boundaries into physical
  `SelectedBatchRequest`s. Each face's registered `ShapingProvision` must be
  `BuiltIn`; a face registered for advanced caller runs only is rejected.
- `KernelShape.shape_selected_batch` validates that every occurrence group's
  cluster ranges exactly partition its source and that every occurrence of
  one source carries the identical split, walks each unique source once to
  resolve the planner-assigned dense font's glyph and metrics per cluster,
  and emits one physical run per request. It remains the horizontal
  left-to-right one-scalar-per-cluster convenience boundary.
- `KernelLineLayout.BatchPlan.build_logical` measures one logical request
  across its adjacent physical face runs, so a line may legally cross the
  face boundary; the existing `BatchKey` stays a complete cache identity
  because one policy per build makes each source's split deterministic.
- `KernelFacadeText` splits each painted line at face boundaries into one
  final run and placement per segment with accumulated-advance origins, and
  page run ranges are counted over the final materialized runs.
- `KernelFacadeOutput.Plan.build_multi` groups glyph usage by each run's
  dense instance fact and builds one plan, one sanitized subset, and one
  `F1_k` Type 0 resource per used font; a one-font list delegates to the
  exact single-face path.

Dense output-font identity `k` is assigned in policy order over the faces
actually selected anywhere in the document, so `run.instance.index()` is the
same value that names the k-th font plan, subset, and page resource. No
later stage re-derives a font from coverage or glyph IDs.

## Registered public fixture

`tests/gate3_multiface_facade/main.roc` registers the 7,816-byte caller
Latin face and the 2,104-byte Noto-derived Han face, constructs the ordered
policy `[latin, cjk]`, and authors one `"C中é"` paragraph through
`Pdf.to_bytes_with`. The 11,416-byte snapshot paints three visual-order
marked-content segments — `F1_0` CID 1 (`C`, x 72), `F1_1` CID 1 (`中`,
x 80.035), `F1_0` CID 3 (`é`, x 91.035) — with per-font canonical ToUnicode
rows (`<0001> <0043>`/`<0003> <00E9>` and `<0001> <4E2D>`), exact CID widths
(`[656 730 583 583 0]` and `[1000 1000]`), and two embedded sanitized
subsets (5,960 bytes, SHA-256 `77b0528896cf30390cecb2554e74d424aa5331f153845282bc63cacded6d0d29`;
940 bytes, SHA-256
`e63604452a131dbaf60dd6baf21017b1ac63e13199c5bd5846dd77ecb97e2175` — the Han
subset is byte-identical to the advanced multi-face fixture's). The
positive case measures 1,711 dev allocations with work
`[7816, 2104, 7816, 2104, 0, 2, 2, 2, 3, 2, 1, 11416]`.
`scripts/check_gate3_multiface_facade.py` verifies these facts directly with
mutation self-tests; PDFBox 3.0.8 extracts exactly `C中é\n`; PDFBox/PDFium
72-dpi ink metrics are pinned per engine in `check_gate3_renderers.py`
(`--multiface-facade`).

## Negatives

`tests/gate3_multiface_facade_negative/main.roc` proves four stable typed
errors, each with zero PDF bytes:

- `missing-coverage`: `"z"` is Latin but uncovered by both faces —
  `InvalidFontSelection([MissingCoverage(..)])` (114 allocations).
- `undeclared-script`: `"α"` itemizes as Greek, outside the declared set —
  `InvalidFontSelection([UnsupportedBuiltInShaping(..)])` (114 allocations).
- `unknown-policy`: policy id 99 was never constructed —
  `InvalidFontSelection([InvalidPolicy(99)])` (70 allocations).
- `builtin-policy`: policy selection over the packaged built-in source —
  `InvalidFontSelection([InvalidPolicy(0)])` (1 allocation, the constructed
  theme; the fixture derives its policy index from the validated runtime
  argument count so the rejection is a real runtime path rather than a
  compile-time-folded constant).

The private planner-level negatives (uncovered scalar, mismatched script,
ambiguous policy face, unknown policy face) remain registered through the
`gate3_font` evidence fixture and are deliberately not duplicated here: the
facade consumes the same `Font.Registry.plan` boundary those cases already
prove.

## Retention

Extending `gate-3-caller-font-retention.md` to two faces:
`shared-registry` authors two independent documents against one completed
registry — one retained payload per face (7,816 + 2,104 = 9,920 retained
bytes), zero copied registry bytes, byte-identical 11,416-byte outputs, and
3,350 allocations. The `unique-registries` control duplicates both font
payloads into a second caller allocation and registers each independently:
every ownership dimension exactly doubles (19,840 input and retained bytes,
9,920 deliberately duplicated caller bytes, 4 resources/faces/instances,
3,419 allocations) while both outputs stay byte-identical. No registry-level
content deduplication is claimed.

## Adversarial bounds

Registry level (`Gate3FontEvidence.multi_face_probe_scale`, x1000/x10000):
alternating `C`/`中` clusters force the worst-case ordered probe — every Han
cluster probes and rejects the Latin face first. Measured
`grapheme_visits = N`, `face_visits = 1.5N` (bound `N × policy_len = 2N`),
`coverage_span_visits = 4N` (bound `N × total_spans = 8N`), and
`face_ranges = N` (alternation never merges), with exact ×10 linearity
between the two scales (`[1000, 1000, 1500, 4000, 1000]` and
`[10000, 10000, 15000, 40000, 10000]`).

Facade level (`Gate3FacadeEvidence.ordered_facade`, x1000/x10000): N
repeated `"C中é"` paragraphs intern to one unique source; selection plans
once (`planned_sources = 1`, 3 grapheme visits, 4 face visits, 15 coverage
visits, 3 ranges — all constant), shaping's template walk resolves 3 metric
reads once per unique source, exactly 2 dense fonts are selected at any
scale, and the logical line cache reports 1 template with `cache_hits =
N − 1` (999 and 9,999). Physical runs and line writes scale exactly linearly
(3,000/1,000 and 30,000/10,000) with near-constant dev allocations (241 and
267). This doubles as the selection-plan and measurement cache hit/miss
evidence recorded in [`gate-3-cache-closure.md`](gate-3-cache-closure.md).

Facade-path bullets under policy selection are out of this row's scope: a
generated `•` label itemizes as an unresolved Common run and is rejected by
the declared-script boundary; bullet documents keep the `StyleFaces`
selection. Facade RTL, vertical writing, and automatic shaping beyond the
declared boundary likewise remain explicitly out of scope.
